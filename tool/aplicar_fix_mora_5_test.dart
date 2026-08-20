// Aplica fix mora a los 5 contratos drift + columna v61.
// Uso: flutter test tool/aplicar_fix_mora_5_test.dart
//      flutter test tool/aplicar_fix_mora_5_test.dart --dart-define=APPLY=1

import 'dart:io';

import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('aplicar fix mora 5 contratos', () async {
    sqfliteFfiInit();
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final dbPath =
        '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
        'Junior Eventos${Platform.pathSeparator}data.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);

    // ignore: avoid_print
    print('DB: $dbPath');
    // ignore: avoid_print
    print(apply ? 'Modo: APLICAR\n' : 'Modo: DRY-RUN\n');

    try {
      await db.execute(
        'ALTER TABLE contratos_alumnos '
        'ADD COLUMN mora_exencion_reinicia INTEGER DEFAULT 1',
      );
      // ignore: avoid_print
      print('+ columna mora_exencion_reinicia');
    } catch (_) {
      // ignore: avoid_print
      print('= columna mora_exencion_reinicia ya existe');
    }

    final verRows = await db.rawQuery('PRAGMA user_version');
    final ver = (verRows.first.values.first as num?)?.toInt() ?? 0;
    if (ver < 61) {
      if (apply) await db.execute('PRAGMA user_version = 61');
      // ignore: avoid_print
      print('${apply ? "+" : "~"} user_version $ver → 61');
    }

    final ids = [
      'cb435b1d-6fd4-41c5-b0e4-184198f6e805',
      '0c9a6b75-72c1-4094-ae20-cbdb7c384133',
      '10f7424e-1db6-4fbf-bb0c-7af11f7493da',
      'f035fac3-60c2-4c5e-a467-f8067bb2ff67',
      '39fd5d47-4bc6-450a-933a-65472de930d4',
    ];

    final nowUtc = DateTime.now().toUtc().toIso8601String();

    for (final id in ids) {
      final rows =
          await db.query('contratos_alumnos', where: 'id = ?', whereArgs: [id]);
      expect(rows, isNotEmpty, reason: id);
      final c = ContratoAlumno.fromJson(rows.first);
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [id],
      );
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: c,
        pagos: pagos,
      );
      final ex = MoraTrackedRecovery.calcularExencionDesdeHistorial(
        contratoBase: c,
        pagos: pagos,
      );
      final moraHist = pagos
          .where((p) => (p['anulado'] as int? ?? 0) == 0)
          .where((p) {
            final lk = (p['line_kind'] as String?)?.trim() ?? '';
            final cl = (p['concepto'] as String? ?? '').toLowerCase();
            return lk == 'interes_mora' ||
                cl.contains('mora') ||
                cl.contains('interes');
          })
          .fold<double>(
              0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

      final cFix = c.copyWith(
        moraPendienteTracked: obj.tracked,
        moraCobradaOffset: obj.offset,
        moraExentaHasta: ex?.hasta,
        moraExencionReinicia: ex?.reinicia ?? true,
      );
      final op = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: cFix,
        moraCobradaHistorial: moraHist,
        ahoraAr: DateTime(2026, 7, 9),
      );

      // ignore: avoid_print
      print('${c.nombreAlumno}');
      // ignore: avoid_print
      print(
        '  tracked ${c.moraPendienteTracked}→${obj.tracked} | '
        'offset ${c.moraCobradaOffset}→${obj.offset} | '
        'reinicia ${c.moraExencionReinicia}→${ex?.reinicia} | '
        'op@9jul=$op',
      );

      if (apply) {
        await db.update(
          'contratos_alumnos',
          {
            'mora_pendiente_tracked': obj.tracked,
            'mora_cobrada_offset': obj.offset,
            'mora_exencion_reinicia': (ex?.reinicia ?? true) ? 1 : 0,
            if (ex != null)
              'mora_exenta_hasta':
                  '${ex.hasta.year.toString().padLeft(4, '0')}-'
                  '${ex.hasta.month.toString().padLeft(2, '0')}-'
                  '${ex.hasta.day.toString().padLeft(2, '0')}',
            'updated_at': nowUtc,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }

    if (apply) {
      final exenciones =
          await MoraTrackedRecovery.repararExencionDesdeHistorial(
        db: db,
        soloEventosMasivosActivos: true,
      );
      final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        soloEventosMasivosActivos: true,
      );
      // ignore: avoid_print
      print('\nMasivos: $exenciones exenciones, $recalibrados tracked');
    }

    await db.close();
    // ignore: avoid_print
    print(apply ? '\nAplicado OK.' : '\nDry-run OK (sin escribir).');
  });
}
