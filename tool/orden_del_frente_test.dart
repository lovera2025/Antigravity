// El orden por cumplimiento de una fiesta, sobre una COPIA de la base del
// usuario (12-nov-2026): de la familia que mejor cumplió con sus cuotas a la que
// peor, con la oración del porqué de cada una y el detalle cuota por cuota. Es
// la lista con la que el jefe fija las mesas a mano mientras el orden no se
// reparte solo, y el control de `CumplimientoDeCuotas` contra los pagos de
// verdad.
//
// Nunca abre la base real ni la nube: lee la copia en solo lectura y no guarda
// nada en ella.
//
//   flutter test tool/orden_del_frente_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>
//     [--dart-define=fiesta=<parte del nombre de la institución>]
//     [--dart-define=corte=2026-11-12]   el día del sorteo; si no, hoy
//     [--dart-define=semilla=20261112]   la de los empates
//
// Sin `fiesta`, solo el resumen de todas (sin nombres de alumnos). **La lista
// de una fiesta lleva nombres y cómo pagó cada uno: va a `build/`, nunca a
// git** (el repo es público).

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/repositories/mora_congelada_repository.dart';
import 'package:arguello_events/features/eventos/services/cumplimiento_de_cuotas.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/plano/services/mesas_del_paso.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _copia = String.fromEnvironment('copia');
const _fiesta = String.fromEnvironment('fiesta');
const _salida = String.fromEnvironment('salida');
const _corte = String.fromEnvironment('corte');
const _semilla = int.fromEnvironment('semilla', defaultValue: 20261112);
const _sorteos = int.fromEnvironment('sorteos', defaultValue: 200);

String _dia(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _html(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

class _Fiesta {
  final String id;
  final String nombre;
  final List<ContratoAlumno> alumnos;
  final Map<String, List<Map<String, dynamic>>> pagos;
  final List<PuestoDelOrden> orden;

  /// El plano guardado de la fiesta, si tiene.
  final PlanoEvento? plano;

  _Fiesta(this.id, this.nombre, this.alumnos, this.pagos, this.orden,
      this.plano);

  int grupo(GrupoDeCumplimiento g) => orden.where((p) => p.grupo == g).length;
  int get activos => alumnos.where((a) => !a.esBajaTemporal).length;

  /// Los de plan nuevo contando a todos los contratos, también los de baja y
  /// los que no entran al orden por no tener nada pagado.
  int get planNuevoDeTodos {
    final plan = PlanDeLaFiesta.de(alumnos);
    return alumnos.where(plan.esPlanNuevo).length;
  }
  int get planDistinto => orden.where((p) => p.planDistinto).length;
  int get cancelaron => orden
      .where((p) =>
          p.grupo == GrupoDeCumplimiento.nuncaTarde &&
          p.cumplimiento.canceloEl != null)
      .length;
}

void main() {
  test('el orden por cumplimiento, sobre una copia de la base', () async {
    if (_copia.isEmpty || _salida.isEmpty) {
      print('Faltan --dart-define=copia=<copia de data.db> y '
          '--dart-define=salida=<carpeta>: no se corre.');
      return;
    }
    expect(File(_copia).existsSync(), isTrue, reason: 'no está la copia');
    expect(
      _copia.replaceAll('\\', '/').toLowerCase(),
      isNot(endsWith('junior eventos/data.db')),
      reason: 'esto se corre sobre una copia, nunca sobre la base de verdad',
    );
    final hoy = _corte.isEmpty ? ArTime.nowAr() : DateTime.parse(_corte);
    final corte = DateTime(hoy.year, hoy.month, hoy.day);

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      File(_copia).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final fiestas = <_Fiesta>[];
    String? ultimoPago;
    try {
      // Como la app: sin la mora congelada cargada, los congelados darían más
      // días de atraso de los que tienen.
      await MoraCongeladaRepository.cargarRegistroEn(db);
      ultimoPago = (await db.rawQuery(
        'select max(created_at) as u from pagos_contrato_alumno',
      ))
          .single['u']
          ?.toString();
      final eventos = await db.rawQuery(
        'select e.id, e.encabezado_evento from eventos e '
        'where exists (select 1 from contratos_alumnos c where c.evento_id = e.id) '
        'order by e.encabezado_evento',
      );
      for (final e in eventos) {
        final id = e['id'] as String;
        final alumnos = [
          for (final r in await db.query(
            'contratos_alumnos',
            where: 'evento_id = ?',
            whereArgs: [id],
          ))
            ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
        ];
        final pagos = <String, List<Map<String, dynamic>>>{};
        for (final a in alumnos) {
          pagos[a.id] = [
            for (final p in await db.query(
              'pagos_contrato_alumno',
              where: 'contrato_alumno_id = ?',
              whereArgs: [a.id],
            ))
              Map<String, dynamic>.from(p),
          ];
        }
        final filasPlano = await db.query(
          'planos_evento',
          where: 'evento_id = ?',
          whereArgs: [id],
        );
        fiestas.add(_Fiesta(
          id,
          (e['encabezado_evento'] ?? '(sin nombre)').toString(),
          alumnos,
          pagos,
          OrdenPorCumplimiento.de(
            alumnos: alumnos,
            pagos: pagos,
            corteAr: corte,
            rng: Random(_semilla),
          ),
          filasPlano.isEmpty
              ? null
              : PlanoEvento.fromMap(
                  Map<String, dynamic>.from(filasPlano.first),
                ),
        ));
      }
    } finally {
      MoraCongelada.vaciar();
      await db.close();
    }

    final carpeta = Directory(_salida)..createSync(recursive: true);

    // ── El resumen de todas: sin nombres de alumnos ───────────────────────
    final r = StringBuffer()
      ..writeln('El orden por cumplimiento, al ${_dia(corte)}/${corte.year}')
      ..writeln('Sobre una copia de la base (último pago cargado: '
          '${ultimoPago ?? '—'}). No se guardó nada.')
      ..writeln()
      ..writeln('  activos  entran   nunca tarde (cancelaron)   pagó tarde   '
          'plan nuevo   plan distinto   fiesta');
    var contratos = 0, nuevos = 0, distintos = 0, cancelaron = 0;
    var nuevosDeTodos = 0;
    for (final f in fiestas) {
      contratos += f.alumnos.length;
      nuevosDeTodos += f.planNuevoDeTodos;
      nuevos += f.grupo(GrupoDeCumplimiento.planNuevo);
      distintos += f.planDistinto;
      cancelaron += f.cancelaron;
      r.writeln('  ${f.activos.toString().padLeft(7)}'
          '${f.orden.length.toString().padLeft(8)}'
          '${f.grupo(GrupoDeCumplimiento.nuncaTarde).toString().padLeft(14)}'
          ' (${f.cancelaron.toString().padLeft(2)})       '
          '${f.grupo(GrupoDeCumplimiento.pagoTarde).toString().padLeft(13)}'
          '${f.grupo(GrupoDeCumplimiento.planNuevo).toString().padLeft(13)}'
          '${f.planDistinto.toString().padLeft(16)}   ${f.nombre}');
    }
    r
      ..writeln()
      ..writeln('  ${fiestas.length} fiestas, $contratos contratos: $nuevos de '
          'plan nuevo ($nuevosDeTodos contando a los de baja y a los que no '
          'entran), $distintos de plan distinto, $cancelaron que nunca '
          'pagaron tarde y ya cancelaron.');
    File('${carpeta.path}/resumen.txt').writeAsStringSync(r.toString());
    print(r);

    if (_fiesta.isEmpty) return;

    // ── La lista de una fiesta: con nombres, solo a `build/` ──────────────
    final elegidas = fiestas
        .where((f) => f.nombre.toUpperCase().contains(_fiesta.toUpperCase()))
        .toList();
    expect(elegidas, hasLength(1),
        reason: 'una sola fiesta con "$_fiesta": '
            '${elegidas.map((f) => f.nombre).join(' · ')}');
    final f = elegidas.single;
    final pagado = pagosPorAlumno(f.alumnos, f.pagos);
    final extras = extrasPorAlumno(f.alumnos, pagado);

    String mesas(ContratoAlumno a) {
      final ya = MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa);
      if (ya.isNotEmpty) return 'ya tiene la ${ya.join(' y ')}';
      final x = extras[a.id]!;
      final n = x.mesasConElSorteoDeHoy;
      return '$n${x.recibeMenos ? ' (de ${x.mesasCargadas}: el resto sin pagar)' : ''}';
    }

    String marca(PuestoDelOrden p) => [
          if (p.grupo == GrupoDeCumplimiento.planNuevo) 'plan nuevo',
          if (p.planDistinto) 'plan distinto',
        ].join(' · ');

    final t = StringBuffer()
      ..writeln(f.nombre)
      ..writeln('El orden, de quien mejor cumplió a quien peor, al '
          '${_dia(corte)}/${corte.year}.')
      ..writeln('Último pago cargado en la copia: ${ultimoPago ?? '—'}.')
      ..writeln('Los empates se sortearon (semilla $_semilla).')
      ..writeln();
    GrupoDeCumplimiento? anterior;
    for (final p in f.orden) {
      if (anterior != null && anterior != p.grupo) {
        t.writeln('  ${'─' * 70}');
      }
      anterior = p.grupo;
      final m = marca(p);
      t
        ..writeln('${p.puesto.toString().padLeft(3)}. '
            '${p.alumno.nombreAlumno}'
            '${(p.alumno.cursoDivision ?? '').isEmpty ? '' : '  [${p.alumno.cursoDivision}]'}'
            '  ·  mesas: ${mesas(p.alumno)}'
            '${m.isEmpty ? '' : '  ·  $m'}')
        ..writeln('     ${p.frase}');
    }
    final sinBase = [
      for (final a in f.alumnos)
        if (!a.esBajaTemporal && !f.orden.any((p) => p.alumno.id == a.id)) a,
    ]..sort((x, y) => x.nombreAlumno.compareTo(y.nombreAlumno));
    t
      ..writeln()
      ..writeln('No entran (nada pagado de la cuota base): ${sinBase.length}');
    for (final a in sinBase) {
      t.writeln('     ${a.nombreAlumno}');
    }
    t
      ..writeln()
      ..writeln('De baja: ${f.alumnos.where((a) => a.esBajaTemporal).length}')
      ..writeln()
      ..writeln('══ El detalle, cuota por cuota ══')
      ..writeln();
    for (final p in f.orden) {
      final c = p.cumplimiento;
      t.writeln('${p.puesto.toString().padLeft(3)}. ${p.alumno.nombreAlumno}'
          '  ·  ${c.cubiertas} de ${c.totalCuotas} cubiertas'
          '  ·  ${c.diasDeAtraso} días de atraso'
          '${p.inicioDelPlan == null ? '' : '  ·  plan desde el ${_dia(p.inicioDelPlan)}'}');
      for (final d in c.detalle) {
        if (!d.vencida && d.cubierta == null) continue;
        t.writeln('       cuota ${d.numero.toString().padLeft(2)}'
            '  vence ${_dia(d.vencimiento)}'
            '  cubierta ${_dia(d.cubierta)}'
            '${d.dias > 0 ? '  ${d.dias} días tarde' : ''}'
            '${d.vencida && d.cubierta == null ? '  SIN PAGAR' : ''}');
      }
    }
    final base = f.nombre.replaceAll(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ]+'), '_');
    File('${carpeta.path}/orden_$base.txt').writeAsStringSync(t.toString());

    // La misma lista, para leer e imprimir.
    final h = StringBuffer()
      ..writeln('<!doctype html><meta charset="utf-8">'
          '<title>Orden · ${_html(f.nombre)}</title>'
          '<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;'
          'color:#111}h1{font-size:18px;margin:0 0 4px}p{margin:0 0 12px;'
          'color:#555;font-size:13px}table{border-collapse:collapse;width:100%;'
          'font-size:13px}td,th{border-bottom:1px solid #ccc;padding:5px 8px;'
          'text-align:left;vertical-align:top}th{font-size:12px;color:#555}'
          'tr.corte td{border-top:3px solid #111}td.n{text-align:right;'
          'font-weight:600;width:34px}td.m{white-space:nowrap}</style>')
      ..writeln('<h1>${_html(f.nombre)}</h1>')
      ..writeln('<p>El orden, de quien mejor cumplió a quien peor, al '
          '${_dia(corte)}/${corte.year}. Último pago cargado: '
          '${_html(ultimoPago ?? '—')}. Uso interno: no se entrega.</p>')
      ..writeln('<table><tr><th>#</th><th>Familia</th><th>Curso</th>'
          '<th>Mesas</th><th>Por qué</th></tr>');
    anterior = null;
    for (final p in f.orden) {
      final corta = anterior != null && anterior != p.grupo;
      anterior = p.grupo;
      final m = marca(p);
      h.writeln('<tr${corta ? ' class="corte"' : ''}><td class="n">${p.puesto}</td>'
          '<td>${_html(p.alumno.nombreAlumno)}</td>'
          '<td>${_html(p.alumno.cursoDivision ?? '')}</td>'
          '<td class="m">${_html(mesas(p.alumno))}</td>'
          '<td>${_html(p.frase)}${m.isEmpty ? '' : ' <i>(${_html(m)})</i>'}</td></tr>');
    }
    h.writeln('</table>');
    if (sinBase.isNotEmpty) {
      h.writeln('<p style="margin-top:16px">No entran (nada pagado de la cuota '
          'base): ${sinBase.map((a) => _html(a.nombreAlumno)).join(' · ')}</p>');
    }
    File('${carpeta.path}/orden_$base.html').writeAsStringSync(h.toString());

    // ── El salón por orden: lo que haría el tilde, sobre el plano de verdad ──
    // Sin nombres: en cada mesa va el puesto de su familia. No guarda nada.
    final armado = f.plano?.armadoONull;
    if (armado != null && armado.mesas.isNotEmpty) {
      final cambio = OrdenEnElSalon.prender(
        eventoId: f.id,
        armado: armado,
        config: f.plano!.config,
        alumnos: f.alumnos,
        pagos: f.pagos,
        hoyAr: corte,
        ahora: DateTime.utc(2026, 11, 12, 18),
        por: 'herramienta',
      );
      if (cambio.config == null) {
        print('El salón por orden no se puede: ${cambio.problema}');
      } else {
        final paso = MesasDelPaso.de(armado)!;
        final lugares = cambio.config!.frente!.lugares;
        final enMesa = <int, LugarPorOrden>{
          for (final l in lugares)
            for (final n in l.mesas) n: l,
        };
        final hoja = armado.hoja(paso.hoja)!;
        final c = hoja.caja;
        final r = armado.radio;
        const colores = ['#ffffff', '#d7f0dc', '#eeeeee', '#f6cfcf'];
        final s = StringBuffer()
          ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
              'viewBox="${c.x - r} ${c.y - r} ${c.ancho + 2 * r} '
              '${c.alto + 2 * r}" font-family="Segoe UI, Arial, sans-serif">')
          ..writeln('<rect x="${c.x - r}" y="${c.y - r}" '
              'width="${c.ancho + 2 * r}" height="${c.alto + 2 * r}" '
              'fill="#faf8f3"/>');
        for (final x in armado.sectoresDeHoja(paso.hoja)) {
          final k = x.caja;
          s
            ..writeln('<rect x="${k.x}" y="${k.y}" width="${k.ancho}" '
                'height="${k.alto}" fill="#e3ded2" stroke="#b9b2a2"/>')
            ..writeln('<text x="${k.centroX}" y="${k.centroY}" '
                'text-anchor="middle" dominant-baseline="middle" '
                'font-size="${r * 0.5}" fill="#6b6557">'
                '${_html(x.texto.isEmpty ? x.tipo.name : x.texto)}</text>');
        }
        for (final m in armado.mesasDeHoja(paso.hoja)) {
          final l = enMesa[m.numero];
          final principal = l != null && l.mesas.first == m.numero;
          s
            ..writeln('<circle cx="${m.x}" cy="${m.y}" r="${r * 0.92}" '
                'fill="${colores[l?.grupo ?? 0]}" stroke="#555" '
                'stroke-width="${r * 0.05}"'
                '${l != null && !principal ? ' stroke-dasharray="${r * 0.2} ${r * 0.12}"' : ''}/>')
            ..writeln('<text x="${m.x}" y="${m.y - r * 0.05}" '
                'text-anchor="middle" dominant-baseline="middle" '
                'font-size="${r * 0.72}" font-weight="700" fill="#111">'
                '${l == null ? '' : '${l.puesto}${principal ? '' : '+'}'}'
                '</text>')
            ..writeln('<text x="${m.x}" y="${m.y + r * 0.62}" '
                'text-anchor="middle" font-size="${r * 0.3}" fill="#666">'
                'mesa ${m.numero}</text>');
        }
        s.writeln('</svg>');
        File('${carpeta.path}/salon_$base.svg').writeAsStringSync(s.toString());

        final sinLugar = lugares.where((l) => l.mesas.isEmpty).length;
        final vacias = armado.mesas.length - enMesa.length;
        print('El salón por orden: ${lugares.length - sinLugar} familias en '
            '${enMesa.length} mesas (${paso.enLaLinea(1)} de primera línea, '
            '${paso.enLaLinea(2)} de segunda), $vacias mesas vacías, '
            '$sinLugar familias sin lugar. Dibujo: salon_$base.svg');
        print('Los primeros puestos: ${[
          for (final l in lugares.take(8)) '${l.puesto}→${l.mesas.join('+')}'
        ].join('  ')}');

        // Y el SORTEO de siempre, con el candado de lo pagado, sobre ese
        // plano: tiene que entregarle a cada familia la mesa que le fijó el
        // orden, y pasar el control final. Lo mismo que corre la app.
        final entrada = EntradaSorteoPlano(
          armado: armado,
          config: cambio.config!,
          alumnos: f.alumnos,
          exclusion: exclusionSorteo(
            candidatos: candidatosPorPago(f.alumnos, pagado),
            soloPagado: true,
          ),
          modo: f.plano!.modoSorteo,
        );
        final plan = SorteoConPlano.preparar(entrada);
        expect(plan.entra, isTrue, reason: plan.avisos.join(' · '));
        var distintas = 0;
        for (var semilla = 1; semilla <= _sorteos; semilla++) {
          final r = SorteoConPlano.sortear(entrada, random: Random(semilla));
          expect(SorteoConPlano.validar(entrada, r), isNull,
              reason: 'semilla $semilla');
          for (final l in lugares) {
            final suyas = (r.asignaciones[l.alumnoId] ?? const <int>[]).toSet();
            if (suyas.length != l.mesas.length ||
                !suyas.containsAll(l.mesas)) {
              distintas++;
            }
          }
        }
        expect(distintas, 0,
            reason: 'alguna familia no recibió la mesa que le fijó el orden');
        print('$_sorteos sorteos de verdad sobre ese plano '
            '(${f.plano!.modoSorteo.clave}): todos pasan el control final y '
            'cada familia recibe la mesa que le fijó el orden.');
      }
    } else {
      print('La fiesta no tiene un plano con mesas guardado.');
    }

    print('${f.nombre}: ${f.orden.length} familias en el orden '
        '(${f.grupo(GrupoDeCumplimiento.nuncaTarde)} nunca tarde, '
        '${f.grupo(GrupoDeCumplimiento.pagoTarde)} pagó tarde, '
        '${f.grupo(GrupoDeCumplimiento.planNuevo)} plan nuevo), '
        '${sinBase.length} no entran. Lista en ${carpeta.path}');
  });
}
