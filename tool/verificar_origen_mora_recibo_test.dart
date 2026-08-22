// Imprime el aviso de mora tal como va a salir en el recibo, sin tener que
// hacer un cobro de prueba. Sirve para ver si el "Viene de:" nombra las cuotas
// o cae en el texto genérico (historial que no se puede reconstruir).
//
// Uso: flutter test tool/verificar_origen_mora_recibo_test.dart
//      flutter test tool/verificar_origen_mora_recibo_test.dart --dart-define=NOMBRE=bernel
//
// Solo lectura: no escribe nada en la base.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/common/utils/currency_extensions.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _resolveDbPath() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

/// Misma regla que [ContratosRepository.sumMoraCobradaHistorial].
double _moraCobradaHistorial(List<Map<String, dynamic>> pagos) {
  return pagos.where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0).where((
    p,
  ) {
    final lk = (p['line_kind'] as String?)?.trim();
    final concepto = p['concepto'] as String? ?? '';
    return lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(concepto);
  }).fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));
}

void main() {
  final filtroNombre =
      const String.fromEnvironment('NOMBRE').trim().toLowerCase();

  test('origen de mora en el recibo', () async {
    sqfliteFfiInit();
    final dbPath = _resolveDbPath();
    final db = await databaseFactoryFfi.openDatabase(dbPath);

    final contratos = await db.rawQuery('''
      SELECT c.*, cl.nombre_completo AS evento_nombre
      FROM contratos_alumnos c
      JOIN eventos e ON e.id = c.evento_id
      LEFT JOIN clientes cl ON cl.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
        AND e.estado IN ('Confirmado', 'Planificacion')
        AND c.nombre_alumno NOT LIKE '[BAJA]%'
      ORDER BY cl.nombre_completo COLLATE NOCASE, c.nombre_alumno COLLATE NOCASE
    ''');

    print('\n=== AVISO DE MORA DEL RECIBO ===');
    print('DB: $dbPath');
    if (filtroNombre.isNotEmpty) print('Filtro: "$filtroNombre"');
    print('');

    var conMora = 0;
    var nombradas = 0;
    var genericas = 0;
    final sinReconstruir = <String>[];
    final descuadres = <String>[];

    for (final row in contratos) {
      final c = ContratoAlumno.fromJson(row);
      if (filtroNombre.isNotEmpty &&
          !c.nombreAlumno.toLowerCase().contains(filtroNombre)) {
        continue;
      }

      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [c.id],
      );

      // Mismos pasos que hace el recibo antes de imprimir.
      final detalle = MoraCuotaCalculator.moraPendienteOperativaDetallada(
        contrato: c,
        moraCobradaHistorial: _moraCobradaHistorial(pagos),
      );
      if (detalle.total <= 0.01) continue;
      conMora++;

      final trackedDetalle = detalle.tracked > 0.01
          ? MoraTrackedOrigen.inferir(
              contratoBase: c,
              pagos: pagos,
              trackedMonto: detalle.tracked,
              recorte: MoraOrigenRecorte.loQueQueda,
            )
          : const <MoraPendientePreviaDetalle>[];

      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: detalle.desglose,
        tracked: detalle.tracked,
        trackedDetalle: trackedDetalle,
        formatoMonto: (v) => v.toCurrency(),
      );

      // Lo atribuido tiene que cerrar con el tracked: si explica de menos, el
      // recibo estaría nombrando cuotas que no suman lo que se debe.
      final atribuido = trackedDetalle.fold<double>(
        0,
        (s, d) => s + d.montoAtribuido,
      );
      if (detalle.tracked > 0.01 &&
          trackedDetalle.isNotEmpty &&
          (atribuido - detalle.tracked).abs() > 0.02) {
        descuadres.add(
          '${row['evento_nombre']} / ${c.nombreAlumno}: '
          'atribuido ${atribuido.toCurrency()} vs tracked '
          '${detalle.tracked.toCurrency()}',
        );
      }

      final generica =
          detalle.tracked > 0.01 && trackedDetalle.isEmpty;
      if (generica) {
        genericas++;
        sinReconstruir.add('${row['evento_nombre']} / ${c.nombreAlumno}');
      } else {
        nombradas++;
      }

      print('${row['evento_nombre']} / ${c.nombreAlumno}');
      print('  cuotas ${c.cuotasPagadas}/${c.totalCuotas} · '
          'tracked ${c.moraPendienteTracked.toCurrency()} · '
          'ajuste ${c.moraTrackedAjuste.toCurrency()} · '
          'desglose ${detalle.desglose.length} cuota(s)');

      // Cuando la ficha tiene menos plata que la que el historial explica, hubo
      // un perdón (o un ajuste a mano). Ahí es donde las dos reglas difieren y
      // conviene ver las dos: la vieja recortaba por la cola y dejaba nombrado
      // el mes más viejo — justo el que se quiso perdonar.
      if (detalle.tracked > 0.01) {
        final vivos = MoraTrackedOrigen.inferir(
          contratoBase: c,
          pagos: pagos,
          trackedMonto: double.maxFinite,
        );
        final totalVivo = vivos.fold<double>(0, (s, d) => s + d.montoAtribuido);
        if ((totalVivo - detalle.tracked).abs() > 0.02) {
          final comoAntes = MoraTrackedOrigen.inferir(
            contratoBase: c,
            pagos: pagos,
            trackedMonto: detalle.tracked,
          );
          String cola(List<MoraPendientePreviaDetalle> l) => l.isEmpty
              ? '(sin origen)'
              : l
                    .map((d) => '${d.etiquetaCorta} '
                        '${d.montoAtribuido.toCurrency()}')
                    .join(' · ');
          print('  ── el historial explica ${totalVivo.toCurrency()} y la '
              'ficha tiene ${detalle.tracked.toCurrency()}');
          print('     historial:  ${cola(vivos)}');
          print('     regla vieja: ${cola(comoAntes)}');
          print('     regla nueva: ${cola(trackedDetalle)}');
        }
      }
      print('  ┌ ATENCIÓN: QUEDA MORA SIN PAGAR — ${detalle.total.toCurrency()}');
      print('  │ En este pago no se cobró.');
      if (linea.isNotEmpty) print('  │ $linea');
      print('  │ Sigue sumando todos los días hasta que se abone.');
      if (generica) print('  ⚠️  sin reconstruir: no nombra cuotas');
      print('');
    }

    print('=== RESUMEN ===');
    print('Contratos con mora pendiente: $conMora');
    print('  nombran las cuotas: $nombradas');
    print('  texto genérico:     $genericas');
    print('  descuadres origen/tracked: ${descuadres.length}');
    if (sinReconstruir.isNotEmpty) {
      print('\nSin reconstruir:');
      for (final n in sinReconstruir) {
        print('  · $n');
      }
    }
    if (descuadres.isNotEmpty) {
      print('\nDescuadres:');
      for (final n in descuadres) {
        print('  · $n');
      }
    }
    expect(descuadres, isEmpty, reason: 'el origen no suma el tracked');

    await db.close();
  });
}
