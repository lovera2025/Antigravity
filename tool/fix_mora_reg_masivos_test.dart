// Corrección de mora mal aplicada en eventos masivos.
//
//   Dry-run (no escribe nada):
//     flutter test tool/fix_mora_reg_masivos_test.dart
//   Aplicar:
//     flutter test tool/fix_mora_reg_masivos_test.dart --dart-define=APPLY=1
//
// Qué hace (ver plan "Corrección de mora mal aplicada en eventos masivos"):
//   1. BUENA VISTA y PUERTO VIEJO → Reg 01/04/2026 y mora rehecha desde el
//      historial de pagos sobre esa fecha.
//   2. Las 3 bajas sin fecha de corte → mora congelada al 31/05/2026.
//   3. MONTIEL, MELANIE MELISA → saldo y cuotas recalculados desde los pagos.
//   4. Cinco contratos con `mora_cobrada_offset` divergente → offset del replay.
//
// No borra ni edita pagos. Encola sync por contrato para que la corrección
// llegue a Supabase y al resto de las PCs.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// Fecha de alta real de BUENA VISTA y PUERTO VIEJO.
final kRegAbril = DateTime(2026, 4, 1);

/// Fecha de corte para congelar la mora de los alumnos dados de baja.
const kCongelarBajasIso = '2026-05-31';

const kNombresOffset = [
  'MARTINEZ, LUZMILA',
  'OCAMPO, JUANA',
  'STORTI, NELSON',
  'MOLINA SPAGNOLO',
  'STANCICH',
];

String _dbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

String _f(double v) => v.toStringAsFixed(2);
String _d(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _isoDia(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Mora efectivamente cobrada en el historial (líneas de interés).
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

  test('fix mora reg masivos', () async {
    sqfliteFfiInit();
    final path = _dbPath();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: !apply, singleInstance: false),
    );

    final hoy = ArTime.nowAr();
    final b = StringBuffer();
    void w(String s) {
      b.writeln(s);
      // ignore: avoid_print
      print(s);
    }

    w(apply
        ? '=== APLICANDO CORRECCIÓN DE MORA ==='
        : '=== SIMULACRO (no se escribe nada) ===');
    w('Base: $path');
    w('Corte: ${_d(hoy)}');
    w('');

    // ── Copia de seguridad antes de tocar nada ────────────────────────────
    if (apply) {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final destino = '$path.bak.regabril.$stamp';
      await db.execute("VACUUM INTO '${destino.replaceAll("'", "''")}'");
      w('Copia de seguridad: $destino');
      w('');
    }

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    var contratosTocados = 0;

    Future<List<Map<String, Object?>>> pagosDe(String id) => db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [id],
        );

    Future<void> escribir(
      String id,
      Map<String, Object?> updates,
      Map<String, dynamic> syncPayload,
    ) async {
      if (!apply) return;
      await db.update(
        'contratos_alumnos',
        {...updates, 'updated_at': nowUtc},
        where: 'id = ?',
        whereArgs: [id],
      );
      await SyncQueue.enqueue(
        executor: db,
        tabla: 'contratos_alumnos',
        operacion: SyncOperation.update,
        registroId: id,
        payload: {'id': id, ...syncPayload},
      );
    }

    // ── 1) BUENA VISTA y PUERTO VIEJO: Reg 01/04 + mora rehecha ──────────
    w('=' * 76);
    w('1) BUENA VISTA y PUERTO VIEJO → Reg ${_d(kRegAbril)}');
    w('=' * 76);

    final regIso = MoraCuotaCalculator.regArAUtcIso(kRegAbril);
    final eventos = await db.rawQuery('''
      SELECT e.id, cl.nombre_completo AS cliente
      FROM eventos e
      LEFT JOIN clientes cl ON cl.id = e.cliente_id
      WHERE e.modalidad = 'masivo'
        AND (UPPER(COALESCE(cl.nombre_completo,'')) LIKE '%BUENA VISTA%'
          OR UPPER(COALESCE(cl.nombre_completo,'')) LIKE '%PUERTO VIEJO%')
      ORDER BY cl.nombre_completo
    ''');

    var totalAntes = 0.0;
    var totalDespues = 0.0;
    var bajan = 0;
    var aCero = 0;

    for (final ev in eventos) {
      final contratos = await db.query(
        'contratos_alumnos',
        where: 'evento_id = ?',
        whereArgs: [ev['id']],
        orderBy: 'nombre_alumno COLLATE NOCASE',
      );

      w('');
      w('--- ${ev['cliente']} (${contratos.length} contratos) ---');

      for (final row in contratos) {
        final c = ContratoAlumno.fromJson(row);
        final pagos = await pagosDe(c.id);
        final moraHist = _moraCobrada(pagos);

        final antes = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: c,
          moraCobradaHistorial: moraHist,
          ahoraAr: hoy,
        );

        // Contrato con la fecha correcta y el estado de mora en blanco: los
        // valores viejos se calcularon sobre el Reg equivocado.
        final base = c.copyWith(
          createdAt: DateTime.utc(
            kRegAbril.year,
            kRegAbril.month,
            kRegAbril.day,
            3,
          ),
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

        final corregido = base.copyWith(
          moraPendienteTracked: obj.tracked,
          moraCobradaOffset: obj.offset,
          moraExentaHasta: exencion?.hasta,
          moraExencionReinicia: exencion?.reinicia ?? true,
        );
        final despues = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: corregido,
          moraCobradaHistorial: moraHist,
          ahoraAr: hoy,
        );

        totalAntes += antes;
        totalDespues += despues;
        if (antes - despues > 0.5) bajan++;
        if (antes > 0.5 && despues <= 0.5) aCero++;
        contratosTocados++;

        await escribir(
          c.id,
          {
            'created_at': regIso,
            'mora_pendiente_tracked': obj.tracked,
            'mora_cobrada_offset': obj.offset,
            'mora_exenta_hasta':
                exencion == null ? null : _isoDia(exencion.hasta),
            'mora_exencion_reinicia': (exencion?.reinicia ?? true) ? 1 : 0,
          },
          {
            'created_at': regIso,
            'mora_pendiente_tracked': obj.tracked,
            'mora_cobrada_offset': obj.offset,
            'mora_exenta_hasta':
                exencion == null ? null : _isoDia(exencion.hasta),
            'mora_exencion_reinicia': (exencion?.reinicia ?? true) ? 1 : 0,
          },
        );

        if ((antes - despues).abs() > 0.5) {
          w('   ${c.nombreAlumno.padRight(38)} '
              '\$${_f(antes).padLeft(10)} → \$${_f(despues).padLeft(10)}  '
              '(−\$${_f(antes - despues)})');
        }
      }
    }

    w('');
    w('   Mora antes:   \$${_f(totalAntes)}');
    w('   Mora después: \$${_f(totalDespues)}');
    w('   Diferencia:   \$${_f(totalAntes - totalDespues)}  '
        '($bajan alumnos bajan, $aCero quedan en cero)');
    w('');

    // ── 2) Congelar las bajas ─────────────────────────────────────────────
    w('=' * 76);
    w('2) Bajas → mora congelada al $kCongelarBajasIso');
    w('=' * 76);

    final bajas = await db.rawQuery('''
      SELECT * FROM contratos_alumnos
      WHERE nombre_alumno LIKE '[BAJA]%'
        AND mora_fecha_referencia IS NULL
        AND saldo_deudor > 0.01
      ORDER BY nombre_alumno
    ''');

    for (final row in bajas) {
      final c = ContratoAlumno.fromJson(row);
      final pagos = await pagosDe(c.id);
      final moraHist = _moraCobrada(pagos);

      final antes = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: moraHist,
        ahoraAr: hoy,
      );
      // Tras el paso 1 el Reg de OJEDA (BUENA VISTA) ya puede ser 01/04.
      final refrescado = apply
          ? ContratoAlumno.fromJson(
              (await db.query('contratos_alumnos',
                      where: 'id = ?', whereArgs: [c.id], limit: 1))
                  .first,
            )
          : c;
      final congelado = refrescado.copyWith(
        moraFechaReferencia: DateTime(2026, 5, 31),
      );
      final despues = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: congelado,
        moraCobradaHistorial: moraHist,
        ahoraAr: hoy,
      );

      contratosTocados++;
      await escribir(
        c.id,
        {'mora_fecha_referencia': kCongelarBajasIso},
        {'mora_fecha_referencia': kCongelarBajasIso},
      );

      w('   ${c.nombreAlumno.padRight(38)} '
          '\$${_f(antes).padLeft(10)} → \$${_f(despues).padLeft(10)}');
    }
    w('');

    // ── 3) MONTIEL: saldo y cuotas desde los pagos ────────────────────────
    w('=' * 76);
    w('3) MONTIEL, MELANIE MELISA → saldo y cuotas desde los pagos');
    w('=' * 76);

    final montiel = await db.query(
      'contratos_alumnos',
      where: "nombre_alumno LIKE '%MONTIEL%MELANIE%'",
    );
    for (final row in montiel) {
      final c = ContratoAlumno.fromJson(row);
      final pagos = await pagosDe(c.id);
      final activos = pagos
          .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
          .toList();
      final r = recalcularSaldoDesdePagos(
        montoTotalPactado: c.montoTotalPactado,
        totalCuotas: c.totalCuotas,
        mesaExtraPrecio: c.mesaExtraPrecio,
        sillasExtraPrecioTotal: c.sillasExtraPrecioTotal,
        precioUnitarioMesaExtra: c.precioUnitarioMesaExtra,
        mesaExtraCuotas: c.mesaExtraCuotas,
        mesaExtraCantidad: c.mesaExtraCantidad,
        sillasExtraCuotas: c.sillasExtraCuotas,
        pagos: activos,
      );

      w('   ${c.nombreAlumno}');
      w('      saldo  \$${_f(c.saldoDeudor)} → \$${_f(r.saldoDeudor)}');
      w('      cuotas ${c.cuotasPagadas} → ${r.cuotasBase}');

      contratosTocados++;
      await escribir(
        c.id,
        {
          'saldo_deudor': r.saldoDeudor,
          'cuotas_pagadas': r.cuotasBase,
          'mesa_extra_pagado': r.grossMesa,
          'sillas_extra_pagado': r.grossSillas,
        },
        {
          'saldo_deudor': r.saldoDeudor,
          'cuotas_pagadas': r.cuotasBase,
          'mesa_extra_pagado': r.grossMesa,
          'sillas_extra_pagado': r.grossSillas,
        },
      );
    }
    w('');

    // ── 4) Offsets divergentes ────────────────────────────────────────────
    w('=' * 76);
    w('4) Offsets divergentes → valor del replay');
    w('=' * 76);

    for (final nombre in kNombresOffset) {
      final rows = await db.query(
        'contratos_alumnos',
        where: 'nombre_alumno LIKE ?',
        whereArgs: ['%$nombre%'],
      );
      for (final row in rows) {
        final c = ContratoAlumno.fromJson(row);
        final pagos = await pagosDe(c.id);
        final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
          contrato: c,
          pagos: pagos,
        );
        if ((obj.offset - c.moraCobradaOffset).abs() <= 0.5) continue;

        w('   ${c.nombreAlumno.padRight(38)} '
            'offset \$${_f(c.moraCobradaOffset)} → \$${_f(obj.offset)}');

        contratosTocados++;
        await escribir(
          c.id,
          {'mora_cobrada_offset': obj.offset},
          {'mora_cobrada_offset': obj.offset},
        );
      }
    }
    w('');

    // ── Cierre ────────────────────────────────────────────────────────────
    w('=' * 76);
    if (apply) {
      final pend = await db.rawQuery('SELECT COUNT(*) AS n FROM _sync_queue');
      w('APLICADO. Contratos tocados: $contratosTocados');
      w('Pendientes en la cola de sync: ${pend.first['n']}');
      w('Abrí la app y subí a la nube para propagar al resto de las PCs.');
    } else {
      w('SIMULACRO. Contratos que se tocarían: $contratosTocados');
      w('Para aplicar: flutter test tool/fix_mora_reg_masivos_test.dart '
          '--dart-define=APPLY=1');
    }
    w('=' * 76);

    await db.close();
    await File('${Platform.environment['TEMP']}\\fix_mora_reg'
            '${apply ? '_aplicado' : '_dryrun'}.txt')
        .writeAsString(b.toString());
  }, timeout: const Timeout(Duration(minutes: 15)));
}
