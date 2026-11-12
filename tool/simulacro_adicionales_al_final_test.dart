// Simulacro de la numeración fila por fila y de las adicionales al final (6.6.1)
// sobre una COPIA de la base del usuario: toma una fiesta que todavía no se
// sorteó, con su plano, sus alumnos y sus pagos, y hace lo que va a hacer el jefe
// (acomodar las mesas, numerar fila por fila, sortear con "Al final"), muchas
// veces, pasando cada sorteo por el control final. Lo mismo que corre la app.
//
// Nunca abre la base real ni la nube: lee la copia en solo lectura y no guarda
// nada.
//
//   flutter test tool/simulacro_adicionales_al_final_test.dart
//     --dart-define=copia=<copia de data.db>
//     --dart-define=fiesta=<parte del nombre de la institución>
//     --dart-define=salida=<carpeta, fuera de git>
//     [--dart-define=todo=true]   a todo lo cargado, sin el candado de lo pagado
//
// La salida no lleva nombres de alumnos, pero va igual a `build/`.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _copia = String.fromEnvironment('copia');
const _fiesta = String.fromEnvironment('fiesta');
const _salida = String.fromEnvironment('salida');
const _sorteos = int.fromEnvironment('sorteos', defaultValue: 200);

/// Con `--dart-define=todo=true`, "a todo lo cargado": sin el candado de lo
/// pagado, como si el jefe tildara sortear igual a todos.
const _todo = bool.fromEnvironment('todo');

/// El salón dibujado en texto: una fila por renglón, desde el escenario, con
/// lo que diga [rotulo] de cada mesa.
String _dibujo(ArmadoSalon a, String Function(MesaPlano m) rotulo) {
  final b = StringBuffer();
  for (final h in a.hojas) {
    final mesas = a.mesasDeHoja(h.id)..sort((x, y) => x.y.compareTo(y.y));
    if (mesas.isEmpty) continue;
    double? cx;
    for (final s in a.sectoresDeHoja(h.id)) {
      if (s.tipo == TipoSector.pasarela) cx = s.caja.centroX;
    }
    for (final s in a.sectoresDeHoja(h.id)) {
      if (s.tipo == TipoSector.escenario) cx ??= s.caja.centroX;
    }
    final medio = cx ?? h.caja.centroX;
    final filas = <List<MesaPlano>>[];
    for (final m in mesas) {
      if (filas.isNotEmpty && (m.y - filas.last.first.y).abs() < a.radio) {
        filas.last.add(m);
      } else {
        filas.add([m]);
      }
    }
    final ancho = filas
        .map((f) => f.where((m) => m.x < medio).length)
        .reduce(max);
    b.writeln('    (escenario)');
    for (final f in filas) {
      f.sort((x, y) => x.x.compareTo(y.x));
      final izq = [for (final m in f) if (m.x < medio) rotulo(m).padLeft(5)];
      final der = [for (final m in f) if (m.x >= medio) rotulo(m).padLeft(5)];
      b.writeln('    ${('     ' * (ancho - izq.length))}${izq.join()}  |'
          '${der.join()}');
    }
    b.writeln('    (fondo)');
  }
  return b.toString();
}

void main() {
  test('fila por fila y adicionales al final, sobre una fiesta de verdad',
      () async {
    if (_copia.isEmpty || _fiesta.isEmpty) {
      print('Faltan --dart-define=copia=<copia de data.db> y '
          '--dart-define=fiesta=<institución>: no se corre.');
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
      ..writeln('Simulacro: numeración fila por fila y adicionales al final '
          '(6.6.1)')
      ..writeln('Sobre una copia de la base. No se guardó nada.')
      ..writeln();
    var fallas = 0;
    try {
      final eventos = await db.rawQuery(
        'select id, encabezado_evento from eventos '
        "where upper(coalesce(encabezado_evento, '')) like ?",
        ['%${_fiesta.toUpperCase()}%'],
      );
      expect(eventos, hasLength(1), reason: 'una sola fiesta con "$_fiesta"');
      final eventoId = eventos.single['id'] as String;
      b.writeln('== ${eventos.single['encabezado_evento']} ==');

      final filasPlano = await db.query(
        'planos_evento',
        where: 'evento_id = ?',
        whereArgs: [eventoId],
      );
      expect(filasPlano, hasLength(1), reason: 'la fiesta tiene su plano');
      final plano =
          PlanoEvento.fromMap(Map<String, dynamic>.from(filasPlano.single));
      final guardado = plano.armadoONull!;
      final alumnos = [
        for (final r in await db.query(
          'contratos_alumnos',
          where: 'evento_id = ?',
          whereArgs: [eventoId],
        ))
          ContratoAlumno.fromJson(Map<String, dynamic>.from(r)),
      ];
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
      final activos = alumnos.where((a) => !a.esBajaTemporal).toList();
      final conMesa = activos
          .where((a) =>
              MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isNotEmpty)
          .length;
      final cargadas = activos.fold<int>(
        0,
        (s, a) => s + MesasExtraUtils.cantidadMesasFisicasSorteo(a),
      );
      b.writeln('  ${alumnos.length} alumnos (${activos.length} activos, '
          '$conMesa con mesa), $cargadas mesas cargadas, '
          '${guardado.mesas.length} mesas en el plano guardado '
          '("${guardado.nombre}", numeración: '
          '${plano.config.eligioNumeracion ? plano.config.numeracion.texto : 'nunca se eligió'}).');

      // Lo que el cartel sortea por defecto: solo a lo que tiene algo pagado.
      final exclusion = exclusionSorteo(
        candidatos: candidatosPorPago(alumnos, pagos),
        soloPagado: !_todo,
        incluirBase: const {},
        incluirExtras: const {},
      );
      final pedidos = SorteoMesasMotor.pedidos(
        alumnos,
        sinMesa: exclusion.sinMesa,
        soloBase: exclusion.soloBase,
      );
      final aSortear = pedidos.fold<int>(0, (s, p) => s + p.mesas);
      final principales = pedidos.length;
      b.writeln('  ${_todo ? 'A todo lo cargado (sin el candado)' : 'Con el candado de siempre ("solo a lo que tiene algo pagado")'}: '
          '${pedidos.length} familias, $aSortear mesas '
          '($principales principales y ${aSortear - principales} '
          'adicionales). Sin mesa por no haber pagado nada: '
          '${exclusion.sinMesa.length}. Solo con la base: '
          '${exclusion.soloBase.length}.');
      b.writeln();

      // Los salones que se prueban: el guardado, solo renumerado, y acomodado
      // de nuevo para lo que hay cargado y para lo que se sortea.
      final lugar = ArmarAMedida.lugarDe(guardado);
      final salones = <String, ArmadoSalon>{
        'el plano como está guardado (${guardado.mesas.length} mesas), '
                'solo renumerado':
            ArmarAMedida.ordenarNumeros(guardado, fin: FinNumeracion.filas)
                .armado,
      };
      for (final n in {aSortear, cargadas}) {
        final r = ArmarAMedida.acomodar(
          guardado,
          cantidad: n,
          lugarM: lugar,
          fin: FinNumeracion.filas,
        );
        salones['ACOMODAR LAS MESAS con $n '
                '(entraron ${r.armado.mesas.length})'] =
            r.armado;
      }

      for (final s in salones.entries) {
        final salon = s.value;
        b.writeln('-- Salón: ${s.key} --');
        b.writeln('  Numerado fila por fila:');
        b.write(_dibujo(salon, (m) => '${m.numero}'));
        b.writeln('  Cortes (donde una familia junta no puede seguir): '
            '${(salon.cortes.toList()..sort()).join(', ')}');

        final casos = <String, Map<String, int>>{
          'Con su familia (lo de hoy)': const {},
          'Al final, ninguna pegada': SorteoConPlano.alFinalSegunElCartel(pedidos),
          'Al final, 1 pegada a la principal':
              SorteoConPlano.alFinalSegunElCartel(pedidos, juntas: 1),
        };
        for (final c in casos.entries) {
          final e = EntradaSorteoPlano(
            armado: salon,
            config: plano.config,
            alumnos: alumnos,
            exclusion: exclusion,
            alFinal: c.value,
          );
          final plan = SorteoConPlano.preparar(e);
          if (!plan.entra) {
            b.writeln('  ${c.key}: NO ENTRA en este salón. '
                '${plan.avisos.join(' ')}');
            continue;
          }
          var malos = 0;
          ResultadoSorteoPlano? muestra;
          for (var semilla = 0; semilla < _sorteos; semilla++) {
            try {
              final r = SorteoConPlano.sortear(e, random: Random(semilla));
              final problema = SorteoConPlano.validar(e, r);
              if (problema != null) {
                malos++;
                b.writeln('    semilla $semilla: $problema');
              }
              muestra ??= r;
            } on StateError catch (x) {
              malos++;
              b.writeln('    semilla $semilla: no sorteó (${x.message})');
            }
          }
          fallas += malos;
          b.writeln('  ${c.key}: entra. '
              '${plan.mesasAlFinal == 0 ? 'Usa hasta la mesa ${plan.hastaMesa}.' : 'Adelante: de la 1 a la ${plan.hastaMesa} · Al final: de la ${plan.alFinalDesde} a la ${plan.alFinalHasta} (${plan.mesasAlFinal} mesas).'} '
              '$_sorteos sorteos: ${malos == 0 ? 'todos pasaron el control final' : '$malos CON PROBLEMAS'}.');
          if (muestra != null && c.value.isNotEmpty && malos == 0) {
            final delFinal = {
              for (final l in SorteoConPlano.delFinal(e, muestra).values) ...l,
            };
            final dadas = {
              for (final l in muestra.asignaciones.values) ...l,
            };
            b.writeln('    Un sorteo de ejemplo (P = adelante, A = al final, '
                '. = libre):');
            b.write(_dibujo(
              salon,
              (m) => delFinal.contains(m.numero)
                  ? 'A${m.numero}'
                  : dadas.contains(m.numero)
                      ? 'P${m.numero}'
                      : '.',
            ));
          }
        }
        b.writeln();
      }
    } finally {
      await db.close();
    }
    print(b);
    if (_salida.isNotEmpty) {
      final carpeta = Directory(_salida)..createSync(recursive: true);
      File('${carpeta.path}/simulacro_adicionales_al_final.txt')
          .writeAsStringSync(b.toString());
    }
    expect(fallas, 0, reason: 'algún sorteo no pasó el control final');
  });
}
