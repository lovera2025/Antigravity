// Simulacro de "Primero las familias de una sola mesa" (pedido del jefe el
// 16-nov-2026) sobre una COPIA de la base del usuario: toma cada fiesta masiva
// con plano, hace de cuenta que todavía no se sorteó (nadie tiene mesa) y
// sortea con el tilde muchas veces, **por el mismo camino que la app**
// (`SorteoDelCartel`: lo que elige el cartel, el sorteo y el control final),
// con "Con su familia", "Al final" y "Cumplimiento debido".
//
// Nunca abre la base real ni la nube: lee la copia en solo lectura y no guarda
// nada. La salida no lleva nombres de alumnos, pero va igual a `build/`.
//
//   python -I tool/copiar_base_solo_lectura.py <copia>
//   flutter test tool/simulacro_una_mesa_primero_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=salida=<carpeta, fuera de git>
//     [--dart-define=sorteos=200]

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_del_cartel.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/mesas_del_paso.dart';
import 'package:arguello_events/features/plano/services/orden_en_el_salon.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _sorteos = int.fromEnvironment('sorteos', defaultValue: 200);

/// Lo que elige el cartel en cada caso, como lo devuelve al apretar SORTEAR.
class _Caso {
  final String nombre;
  final bool alFinal;
  final bool cumplimiento;
  final RecorridoDelOrden recorrido;
  const _Caso(
    this.nombre, {
    this.alFinal = false,
    this.cumplimiento = false,
    this.recorrido = RecorridoDelOrden.columnas,
  });
}

const _casos = [
  _Caso('Con su familia'),
  _Caso('Al final', alFinal: true),
  _Caso('Cumplimiento debido, por filas',
      cumplimiento: true, recorrido: RecorridoDelOrden.filas),
  _Caso('Cumplimiento debido, por columnas', cumplimiento: true),
  _Caso('Cumplimiento debido por filas, Al final',
      alFinal: true, cumplimiento: true, recorrido: RecorridoDelOrden.filas),
];

void main() {
  test('primero las de una sola mesa, sobre las fiestas de verdad', () async {
    if (_copia.isEmpty) {
      print('Falta --dart-define=copia=<copia de data.db>: no se corre.');
      return;
    }
    expect(File(_copia).existsSync(), isTrue, reason: 'no está la copia');
    expect(
      _copia.replaceAll('\\', '/').toLowerCase(),
      isNot(endsWith('junior eventos/data.db')),
      reason: 'esto se corre sobre una copia, nunca sobre la base de verdad',
    );
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      File(_copia).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final b = StringBuffer()
      ..writeln('Simulacro: "Primero las familias de una sola mesa" (16-nov-2026)')
      ..writeln('Sobre una copia de la base. No se guardó nada. Cada fiesta, '
          'como si todavía no se hubiera sorteado.')
      ..writeln();
    var fallas = 0;
    var fiestas = 0;
    try {
      final planos = await db.query('planos_evento');
      for (final fila in planos) {
        final plano = PlanoEvento.fromMap(Map<String, dynamic>.from(fila));
        final guardado = plano.armadoONull;
        if (guardado == null || guardado.mesas.isEmpty) continue;
        final alumnosGuardados = [
          for (final r in await db.query(
            'contratos_alumnos',
            where: 'evento_id = ?',
            whereArgs: [plano.eventoId],
          ))
            ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
        ];
        // Como antes del sorteo: nadie tiene mesa.
        final alumnos = [
          for (final a in alumnosGuardados) a.copyWith(numeroMesa: ''),
        ];
        final activos = alumnos.where((a) => !a.esBajaTemporal).toList();
        if (activos.length < 5) continue;
        final pagosCrudos = <String, List<Map<String, dynamic>>>{};
        for (final a in alumnos) {
          pagosCrudos[a.id] = [
            for (final p in await db.query(
              'pagos_contrato_alumno',
              where: 'contrato_alumno_id = ?',
              whereArgs: [a.id],
            ))
              Map<String, dynamic>.from(p),
          ];
        }
        final pagos = pagosPorAlumno(alumnos, pagosCrudos);
        final exclusion = exclusionSorteo(
          candidatos: candidatosPorPago(alumnos, pagos),
          soloPagado: true,
          incluirBase: const {},
          incluirExtras: const {},
        );
        final pedidos = SorteoMesasMotor.pedidos(
          alumnos,
          sinMesa: exclusion.sinMesa,
          soloBase: exclusion.soloBase,
        );
        // Las que tienen una mesa fijada a mano quedan fuera de los grupos,
        // como en la app (el control final no las mira): se quedan con su
        // fijada esté donde esté.
        final fijadas = (OrdenEnElSalon.sinFijadasDelOrden(plano.config) ??
                plano.config)
            .fijadasPorAlumno
            .keys
            .toSet();
        final unaSola = {
          for (final a in activos)
            if (MesasExtraUtils.cantidadMesasFisicasSorteo(a) <= 1) a.id,
        };
        final conAdicional =
            pedidos.where((p) => !unaSola.contains(p.alumnoId)).length;
        if (conAdicional == 0) continue;
        fiestas++;
        // El salón numerado fila por fila, como el jefe lo deja para que
        // "primero" sean las filas de adelante. Un armado del Canva, como está.
        final salon = ArmarAMedida.esAMedida(guardado)
            ? ArmarAMedida.ordenarNumeros(guardado, fin: FinNumeracion.filas)
                .armado
            : guardado;
        final planoDelSimulacro = plano.copyWith(
          armado: salon,
          config: plano.config.copyWith(numeracion: FinNumeracion.filas),
          ahora: DateTime.utc(2026, 11, 16),
        );
        b.writeln('== Fiesta ${fiestas.toString().padLeft(2)}: '
            '${activos.length} alumnos activos, ${pedidos.length} se sortean '
            '(${pedidos.length - conAdicional} de una sola mesa, '
            '$conAdicional con adicional); ${salon.mesas.length} mesas en el '
            'plano${ArmarAMedida.esAMedida(guardado) ? ', numeradas fila por fila' : ' (del Canva)'}'
            '${fijadas.isEmpty ? '' : '; ${fijadas.length} familias con mesa fijada a mano (quedan fuera de los grupos)'}. ==');

        // Los "lejos" que el cartel trae tildados: más de 3 mesas.
        final separaciones = {
          for (final p in pedidos)
            if (p.mesas > 3) p.alumnoId: p.mesas - 3,
        };
        final cas = CasillerosPlano.de(salon);
        for (final caso in _casos) {
          final elegido = SorteoMesasDialogResult(
            capacidadSalon: 0,
            separaciones:
                caso.alFinal || caso.cumplimiento ? const {} : separaciones,
            distancias: caso.alFinal || caso.cumplimiento
                ? const {}
                : {
                    for (final id in separaciones.keys)
                      id: DistanciaLejos.bienLejos,
                  },
            soloPagado: true,
            modo: ModoSorteo.entera,
            adicionalesAlFinal: caso.alFinal,
            alFinal: caso.alFinal && !caso.cumplimiento
                ? SorteoConPlano.alFinalSegunElCartel(pedidos)
                : const {},
            porCumplimiento: caso.cumplimiento,
            recorrido: caso.recorrido,
            unaMesaPrimero: true,
          );
          final delCartel = SorteoDelCartel.armar(
            eventoId: plano.eventoId,
            plano: planoDelSimulacro,
            alumnos: alumnos,
            config: elegido,
            exclusion: exclusion,
            pagos: pagos,
            pagosCrudos: pagosCrudos,
            hoyAr: DateTime(2026, 11, 16),
            ahora: DateTime.utc(2026, 11, 16, 18),
            por: 'Simulacro',
          );
          if (!delCartel.sePuede) {
            b.writeln('  ${caso.nombre}: no se puede (${delCartel.problema}).');
            continue;
          }
          final plan = SorteoConPlano.preparar(delCartel.entrada!);
          if (!plan.entra) {
            final sinTilde = SorteoConPlano.preparar(
              EntradaSorteoPlano(
                armado: salon,
                config: planoDelSimulacro.config,
                alumnos: alumnos,
                exclusion: exclusion,
              ),
            ).entra;
            b.writeln('  ${caso.nombre}: NO ENTRA con el tilde'
                '${sinTilde ? ' (sin el tilde sí entra: el cartel lo dice en rojo y no deja sortear)' : ' (tampoco sin el tilde)'}. '
                'Dice: ${plan.avisos.join(' ')}');
            continue;
          }
          // Con Cumplimiento debido, las partidas sin el tilde, para comparar.
          var partidasSinTilde = 0;
          if (caso.cumplimiento) {
            final sin = SorteoDelCartel.armar(
              eventoId: plano.eventoId,
              plano: planoDelSimulacro,
              alumnos: alumnos,
              config: SorteoMesasDialogResult(
                capacidadSalon: 0,
                soloPagado: true,
                modo: ModoSorteo.entera,
                adicionalesAlFinal: caso.alFinal,
                porCumplimiento: true,
                recorrido: caso.recorrido,
              ),
              exclusion: exclusion,
              pagos: pagos,
              pagosCrudos: pagosCrudos,
              hoyAr: DateTime(2026, 11, 16),
              ahora: DateTime.utc(2026, 11, 16, 18),
              por: 'Simulacro',
            );
            if (sin.sePuede) {
              for (final e in sin.orden!.lugares.entries) {
                final atras = caso.alFinal ? e.value.skip(1).toSet() : <int>{};
                final adelante =
                    e.value.where((n) => !atras.contains(n)).toList();
                if (adelante.length > 1 &&
                    SorteoConPlano.gruposEnElSalon(salon, adelante).length > 1) {
                  partidasSinTilde++;
                }
              }
            }
          }
          final paso = caso.cumplimiento
              ? MesasDelPaso.de(salon, recorrido: caso.recorrido)
              : null;
          int lugar(int n) =>
              paso == null ? (cas.casillero(n) ?? 0) : paso.enOrden.indexOf(n);
          var malos = 0;
          var partidas = 0;
          final vueltas = caso.cumplimiento ? 20 : _sorteos;
          for (var semilla = 0; semilla < vueltas; semilla++) {
            try {
              final r = delCartel.sortear(random: Random(semilla));
              final problema = delCartel.controlFinal(r);
              if (problema != null) {
                malos++;
                b.writeln('    semilla $semilla: $problema');
                continue;
              }
              // Lo que pidió el jefe: ninguna con adicional antes que una de
              // una sola mesa (sus mesas de adelante; con "Al final", la
              // principal).
              final unas = <int>[];
              final con = <int>[];
              final delFinal = caso.cumplimiento
                  ? <String, List<int>>{
                      for (final l
                          in delCartel.orden!.configAGuardar!.frente!.lugares)
                        if (caso.alFinal && l.mesas.length > 1)
                          l.alumnoId: l.mesas.skip(1).toList(),
                    }
                  : SorteoConPlano.delFinal(delCartel.entrada!, r);
              for (final x in r.asignaciones.entries) {
                if (fijadas.contains(x.key)) continue;
                if (unaSola.contains(x.key)) {
                  unas.addAll(x.value);
                } else {
                  final atras = delFinal[x.key] ?? const <int>[];
                  final adelante =
                      x.value.where((n) => !atras.contains(n)).toList();
                  con.addAll(adelante);
                  if (caso.cumplimiento &&
                      adelante.length > 1 &&
                      SorteoConPlano.gruposEnElSalon(salon, adelante).length >
                          1) {
                    partidas++;
                  }
                }
              }
              if (unas.isNotEmpty &&
                  con.isNotEmpty &&
                  con.map(lugar).reduce(min) < unas.map(lugar).reduce(max)) {
                malos++;
                b.writeln('    semilla $semilla: una con adicional quedó antes '
                    'que una de una sola mesa');
              }
            } on StateError catch (x) {
              malos++;
              b.writeln('    semilla $semilla: no sorteó (${x.message})');
            }
          }
          fallas += malos;
          final rangos = caso.cumplimiento
              ? ''
              : ' Una sola mesa: de la 1 a la ${plan.unaMesaHasta} · con '
                  'adicional: de la ${plan.conAdicionalDesde} a la '
                  '${plan.hastaMesa}'
                  '${plan.mesasAlFinal > 0 ? ' · al final: de la ${plan.alFinalDesde} a la ${plan.alFinalHasta}' : ''}.';
          b.writeln('  ${caso.nombre}: entra.$rangos $vueltas sorteos: '
              '${malos == 0 ? 'todos pasaron' : '$malos CON PROBLEMAS'}'
              '${caso.cumplimiento ? ' · familias partidas en el borde de una fila: ${partidas ~/ vueltas} con el tilde, $partidasSinTilde sin el tilde' : ''}.');
        }
        b.writeln();
      }
    } finally {
      await db.close();
    }
    b.writeln('Fiestas con plano y familias con adicional: $fiestas. '
        '${fallas == 0 ? 'Ningún sorteo con problemas.' : '$fallas sorteos CON PROBLEMAS.'}');
    print(b);
    if (_salida.isNotEmpty) {
      final carpeta = Directory(_salida)..createSync(recursive: true);
      File('${carpeta.path}/simulacro_una_mesa_primero.txt')
          .writeAsStringSync(b.toString());
    }
    expect(fiestas, greaterThan(0), reason: 'no había ninguna fiesta para probar');
    expect(fallas, 0, reason: 'algún sorteo no pasó');
  });
}
