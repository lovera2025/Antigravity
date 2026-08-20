// Revierte el Reg de BUENA VISTA y PUERTO VIEJO a su valor original de marzo.
//
//   Simulacro:  flutter test tool/revertir_reg_masivos_test.dart
//   Aplicar:    flutter test tool/revertir_reg_masivos_test.dart --dart-define=APPLY=1
//
// Por qué: en esos dos colegios la cuota 1 vence el 30/04, o sea que el Reg va
// en marzo (el programa hace vencer la cuota N el último día del mes Reg+N).
// Se los había pasado a 01/04 por leer el Reg como "fecha de alta del alumno",
// y eso corría el cronograma un mes: quien tenía 3 cuotas pagas figuraba al día
// cuando le corresponde deber la cuarta.
//
// Restaura el created_at exacto que cada contrato tenía, leyéndolo de la copia
// `data.db.bak.regabril.*`, y rehace tracked/offset/exención desde el historial
// de pagos sobre esa fecha. No toca `mora_fecha_referencia`, así que las bajas
// congeladas siguen congeladas, ni el saldo de MONTIEL, ni los offsets sueltos.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/services/cronograma_cuotas_utils.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

String _carpeta() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents'
      '${Platform.pathSeparator}Junior Eventos';
}

String _f(double v) => v.toStringAsFixed(2);
String _d(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

double _moraCobrada(List<Map<String, Object?>> pagos) => pagos
    .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
    .where((p) {
      final lk = (p['line_kind'] as String?)?.trim() ?? '';
      final cl = (p['concepto'] as String? ?? '').toLowerCase();
      return lk == 'interes_mora' ||
          cl.contains('mora') ||
          cl.contains('interes') ||
          cl.contains('interés');
    })
    .fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('revertir reg masivos', () async {
    sqfliteFfiInit();
    final dir = _carpeta();
    final live = '$dir${Platform.pathSeparator}data.db';

    // Copia previa a la corrección: de ahí sale el Reg original de cada uno.
    final backups = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.bak.regabril.'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    if (backups.isEmpty) {
      fail('No se encontró ninguna copia data.db.bak.regabril.* en $dir');
    }
    final backup = backups.first;

    final dbBak = await databaseFactoryFfi.openDatabase(
      backup.path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final originales = <String, String?>{};
    for (final r in await dbBak.query(
      'contratos_alumnos',
      columns: ['id', 'created_at'],
    )) {
      originales[r['id'] as String] = r['created_at'] as String?;
    }
    await dbBak.close();

    final db = await databaseFactoryFfi.openDatabase(
      live,
      options: OpenDatabaseOptions(readOnly: !apply, singleInstance: false),
    );

    final hoy = ArTime.nowAr();
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    void w(String s) {
      // ignore: avoid_print
      print(s);
    }

    w(apply ? '=== REVIRTIENDO Reg A MARZO ===' : '=== SIMULACRO ===');
    w('Copia usada: ${backup.uri.pathSegments.last}');
    w('Corte: ${_d(hoy)}');
    w('');

    final eventos = await db.rawQuery('''
      SELECT e.id, cl.nombre_completo AS cliente
      FROM eventos e
      LEFT JOIN clientes cl ON cl.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
        AND (UPPER(COALESCE(cl.nombre_completo,'')) LIKE '%BUENA VISTA%'
          OR UPPER(COALESCE(cl.nombre_completo,'')) LIKE '%PUERTO VIEJO%')
      ORDER BY cl.nombre_completo
    ''');

    var tocados = 0;
    var totalAntes = 0.0;
    var totalDespues = 0.0;

    for (final ev in eventos) {
      final contratos = await db.query(
        'contratos_alumnos',
        where: 'evento_id = ?',
        whereArgs: [ev['id']],
        orderBy: 'nombre_alumno COLLATE NOCASE',
      );

      w('--- ${ev['cliente']} (${contratos.length}) ---');

      for (final row in contratos) {
        final c = ContratoAlumno.fromJson(row);
        final regOriginal = originales[c.id];
        if (regOriginal == null) {
          w('   ${c.nombreAlumno}: sin registro en la copia, se omite');
          continue;
        }

        final pagos = await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [c.id],
        );
        final moraHist = _moraCobrada(pagos);

        final antes = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: c,
          moraCobradaHistorial: moraHist,
          ahoraAr: hoy,
        );
        final cuotasAntes =
            CronogramaCuotasUtils.cuotasImpagasVencidas(c, hoy) +
                c.cuotasPagadas;

        // Fecha original + estado de mora en blanco: lo que hay se derivó del
        // Reg de abril y no sirve como punto de partida.
        final base = c.copyWith(
          createdAt: DateTime.parse(regOriginal),
          moraPendienteTracked: 0,
          moraCobradaOffset: 0,
          moraExentaHasta: null,
          moraExencionReinicia: true,
        );
        final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
          contrato: base,
          pagos: pagos,
        );
        final exencion = MoraTrackedRecovery.calcularExencionDesdeHistorial(
          contratoBase: base,
          pagos: pagos,
        );
        final exentaIso = exencion == null
            ? null
            : '${exencion.hasta.year.toString().padLeft(4, '0')}-'
                '${exencion.hasta.month.toString().padLeft(2, '0')}-'
                '${exencion.hasta.day.toString().padLeft(2, '0')}';
        final reinicia = exencion?.reinicia ?? true;

        final corregido = base.copyWith(
          moraPendienteTracked: obj.tracked,
          moraCobradaOffset: obj.offset,
          moraExentaHasta: exencion?.hasta,
          moraExencionReinicia: reinicia,
        );
        final despues = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: corregido,
          moraCobradaHistorial: moraHist,
          ahoraAr: hoy,
        );
        final cuotasDespues =
            CronogramaCuotasUtils.cuotasImpagasVencidas(corregido, hoy) +
                corregido.cuotasPagadas;

        totalAntes += antes;
        totalDespues += despues;
        tocados++;

        if (apply) {
          await db.update(
            'contratos_alumnos',
            {
              'created_at': regOriginal,
              'mora_pendiente_tracked': obj.tracked,
              'mora_cobrada_offset': obj.offset,
              'mora_exenta_hasta': exentaIso,
              'mora_exencion_reinicia': reinicia ? 1 : 0,
              'updated_at': nowUtc,
            },
            where: 'id = ?',
            whereArgs: [c.id],
          );
          await SyncQueue.enqueue(
            executor: db,
            tabla: 'contratos_alumnos',
            operacion: SyncOperation.update,
            registroId: c.id,
            payload: {
              'id': c.id,
              'created_at': regOriginal,
              'mora_pendiente_tracked': obj.tracked,
              'mora_exenta_hasta': exentaIso,
              'mora_exencion_reinicia': reinicia ? 1 : 0,
            },
          );
        }

        if ((antes - despues).abs() > 0.5 || cuotasAntes != cuotasDespues) {
          w('   ${c.nombreAlumno.padRight(36)} '
              'pagas ${c.cuotasPagadas}/${c.totalCuotas} | '
              'vencidas $cuotasAntes→$cuotasDespues | '
              '\$${_f(antes).padLeft(9)} → \$${_f(despues).padLeft(9)}');
        }
      }
      w('');
    }

    w('=' * 72);
    w('Contratos: $tocados');
    w('Mora antes:   \$${_f(totalAntes)}');
    w('Mora después: \$${_f(totalDespues)}');
    if (apply) {
      final p = await db.rawQuery('SELECT COUNT(*) AS n FROM _sync_queue');
      w('REVERTIDO. Pendientes en cola: ${p.first['n']}');
    } else {
      w('SIMULACRO — no se escribió nada.');
    }
    w('=' * 72);

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
