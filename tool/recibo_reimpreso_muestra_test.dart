// Muestras del recibo reimpreso con los datos reales, y control de todos los
// alumnos: que la reimpresión de su último recibo diga las cuotas que tiene.
//
// Antes el recuadro "X/9 pagadas" de una reimpresión se deducía del saldo con
// mesas y sillas adentro: GAUNA, GERALDINE (Puerto Viejo) tenía 6 cuotas y el
// papel decía 4/9. Ahora sale de los pagos (`progresoAlDia`).
//
// La base real se abre SOLO LECTURA y se copia con `VACUUM INTO` a una carpeta
// temporal; todo pasa sobre la copia. Los PDF se guardan en
// <salida>/Junior Eventos/PDFs.
//
//   flutter test tool/recibo_reimpreso_muestra_test.dart --dart-define=salida=<carpeta>
//
// Opcional: --dart-define=base=<ruta> para otra base (siempre solo lectura).

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';

String _baseReal() {
  const elegida = String.fromEnvironment('base');
  if (elegida.isNotEmpty) return elegida;
  final perfil = Platform.environment['USERPROFILE'] ?? '';
  return '$perfil\\Documents\\Junior Eventos\\data.db';
}

const _muestras = {
  '626ec708-19d0-4c68-83b7-dda451608f55': 'GAUNA, GERALDINE',
  '2646f9b8-db60-42a0-9cf1-5b307d0db589': 'SEGOVIA, PABLO',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recibo reimpreso con los datos reales', () async {
    const salida = String.fromEnvironment('salida');
    if (salida.isEmpty) {
      fail('Falta --dart-define=salida=<carpeta>');
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => salida,
        );

    sqfliteFfiInit();
    final temp = Directory.systemTemp.createTempSync('recibo_reimpreso');
    final copia = '${temp.path}\\copia.db';
    final real = await databaseFactoryFfi.openDatabase(
      _baseReal(),
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    await real.execute("VACUUM INTO '${copia.replaceAll("'", "''")}'");
    await real.close();
    final db = await databaseFactoryFfi.openDatabase(
      copia,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );

    try {
      // ── Las dos del aviso: el recibo del 25-sep, reimpreso ──
      for (final e in _muestras.entries) {
        final fila = (await db.query(
          'contratos_alumnos',
          where: 'id = ?',
          whereArgs: [e.key],
        )).single;
        final contrato = ContratoAlumno.fromJson(fila);
        final evento = Evento.fromJson((await db.query(
          'eventos',
          where: 'id = ?',
          whereArgs: [contrato.eventoId],
        )).single);
        final pagos = await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [contrato.id],
        );
        final cuota6 = pagos.singleWhere(
          (p) => p['concepto'] == 'Cuota Base (6/9)',
        );
        final fecha = DateTime.parse(cuota6['fecha_pago'] as String);
        final progreso = progresoAlDia(
          contrato: contrato,
          pagos: pagos,
          hasta: fecha,
        );
        print('${e.value}: ${progreso.cuotasBase}/${contrato.totalCuotas} '
            'pagadas, saldo ${progreso.saldoDeudor} (la ficha dice '
            '${contrato.cuotasPagadas}/${contrato.totalCuotas}, '
            'saldo ${contrato.saldoDeudor})');
        expect(progreso.cuotasBase, contrato.cuotasPagadas, reason: e.value);

        await PdfService.generarReciboAlumno(
          alumno: contrato,
          evento: evento,
          montoPagado: (cuota6['monto'] as num).toDouble(),
          saldoPendiente: progreso.saldoDeudor,
          conceptosPagados: [
            {
              'concepto': cuota6['concepto'],
              'monto': (cuota6['monto'] as num).toDouble(),
              'esMora': false,
              'esCargoCanal': false,
            },
          ],
          fechaManual: fecha,
          esReimpresion: true,
          cuotasPagadasAlDia: progreso.cuotasBase,
          medioPago: cuota6['medio_pago'] as String?,
        );
      }

      // ── Todos: la reimpresión de su último recibo ──
      final contratos = await db.query('contratos_alumnos');
      var revisados = 0;
      final distintos = <String>[];
      for (final fila in contratos) {
        final contrato = ContratoAlumno.fromJson(fila);
        if (contrato.totalCuotas <= 0) continue;
        final pagos = await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ? AND COALESCE(anulado, 0) = 0',
          whereArgs: [contrato.id],
        );
        if (pagos.isEmpty) continue;
        final ultima = pagos
            .map((p) => DateTime.tryParse('${p['fecha_pago']}'))
            .whereType<DateTime>()
            .reduce((a, b) => a.isAfter(b) ? a : b);
        final progreso = progresoAlDia(
          contrato: contrato,
          pagos: pagos,
          hasta: ultima,
        );
        revisados++;
        if (progreso.cuotasBase != contrato.cuotasPagadas) {
          distintos.add('${contrato.nombreAlumno} (${contrato.institucion}): '
              'pagos ${progreso.cuotasBase}, ficha ${contrato.cuotasPagadas}');
        }
      }
      print('Revisados: $revisados. Distintos de la ficha: ${distintos.length}');
      distintos.forEach(print);
    } finally {
      await db.close();
      temp.deleteSync(recursive: true);
    }
  });
}
