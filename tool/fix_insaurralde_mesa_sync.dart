// Vacía cola sync, reclasifica $55k Insaurralde Base→Mesa, encola solo ese arreglo.
//
//   dart run tool/fix_insaurralde_mesa_sync.dart
//   dart run tool/fix_insaurralde_mesa_sync.dart --dry-run

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _contratoId = '39b31c35-2f41-46e8-9ce3-5bd20fe4755e';
const _pago55Id = '0b566d73-e56d-4e8a-979f-19fd268a6821';

String _dbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final dbPath = _dbPath();
  if (!File(dbPath).existsSync()) {
    stderr.writeln('No se encontró: $dbPath');
    exit(1);
  }

  final db = sqlite3.open(dbPath);
  try {
    final colaAntes = db.select('SELECT COUNT(*) AS c FROM _sync_queue').first;
    print('Cola antes: ${colaAntes['c']}');

    final contrato = db.select(
      'SELECT * FROM contratos_alumnos WHERE id = ?',
      [_contratoId],
    );
    if (contrato.isEmpty) {
      stderr.writeln('Contrato Insaurralde no encontrado');
      exit(1);
    }
    final c = contrato.first;
    print(
      'Contrato: ${c['nombre_alumno']} | total=${c['monto_total_pactado']} '
      'saldo=${c['saldo_deudor']} mesa_pagado=${c['mesa_extra_pagado']} '
      'cuotas_base=${c['cuotas_pagadas']}',
    );

    final pago = db.select(
      'SELECT * FROM pagos_contrato_alumno WHERE id = ?',
      [_pago55Id],
    );
    if (pago.isEmpty) {
      stderr.writeln('Pago de 55000 no encontrado');
      exit(1);
    }
    final p = pago.first;
    print(
      'Pago: concepto="${p['concepto']}" monto=${p['monto']} '
      'fecha=${p['fecha_pago']}',
    );

    final mesaPrecio = (c['mesa_extra_precio'] as num).toDouble();
    final mesaCuotas = (c['mesa_extra_cuotas'] as int?) ?? 7;
    final now = DateTime.now().toUtc().toIso8601String();
    final conceptoNuevo = 'Mesa Extra';
    final estadoMesa = [
      {
        'n': 1,
        'precio': mesaPrecio,
        'pagado': mesaPrecio,
        'cuotasPagadas': mesaCuotas,
        'liquidada': true,
      },
    ];
    final estadoJson = jsonEncode(estadoMesa);

    // Verificación: tras reclasificar, gross debe seguir 140k / saldo 245k
    final pagos = db.select(
      'SELECT concepto, monto_gross, monto, anulado, line_kind '
      'FROM pagos_contrato_alumno WHERE contrato_alumno_id = ?',
      [_contratoId],
    );
    var grossBase = 0.0;
    var grossMesa = 0.0;
    for (final row in pagos) {
      if ((row['anulado'] as int? ?? 0) != 0) continue;
      final lk = (row['line_kind'] as String?)?.trim() ?? '';
      final cl = (row['concepto'] as String? ?? '').toLowerCase();
      if (lk == 'interes_mora' ||
          lk == 'cargo_canal_ref' ||
          cl.contains('interes mora') ||
          cl.contains('interés mora') ||
          cl.contains('cargo canal')) {
        continue;
      }
      final g = (row['monto_gross'] as num?)?.toDouble() ??
          (row['monto'] as num?)?.toDouble() ??
          0.0;
      final isTarget = (row['concepto'] as String?) == '5 Enteras + Adelanto' &&
          ((row['monto'] as num?)?.toDouble() ?? 0) == 55000.0;
      final conceptoSim =
          isTarget ? conceptoNuevo : (row['concepto'] as String? ?? '');
      final clSim = conceptoSim.toLowerCase();
      if (clSim.contains('mesa')) {
        grossMesa += g;
      } else if (!clSim.contains('silla')) {
        grossBase += g;
      }
    }
    final pactado = (c['monto_total_pactado'] as num).toDouble();
    final saldoNuevo =
        double.parse((pactado - grossBase - grossMesa).toStringAsFixed(2));
    print(
      'Post-fix sim: base=$grossBase mesa=$grossMesa saldo=$saldoNuevo '
      '(esperado mesa=$mesaPrecio, base=70000, saldo=245000)',
    );

    if (dryRun) {
      print('\n[DRY-RUN] No se escribió nada.');
      print('Acciones previstas:');
      print('  1. DELETE FROM _sync_queue (${colaAntes['c']} filas)');
      print('  2. UPDATE pago $_pago55Id concepto → "$conceptoNuevo"');
      print(
        '  3. UPDATE contrato: mesa_pagado=$mesaPrecio, '
        'mesa_cuotas_pagadas=$mesaCuotas, cuotas_base=2, liquidada',
      );
      print('  4. Encolar update pago + update contrato');
      return;
    }

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM _sync_queue');
      final colaAfterDel =
          db.select('SELECT COUNT(*) AS c FROM _sync_queue').first['c'];
      print('Cola vaciada: quedan $colaAfterDel');

      db.execute(
        'UPDATE pagos_contrato_alumno SET concepto = ?, updated_at = ? WHERE id = ?',
        [conceptoNuevo, now, _pago55Id],
      );

      db.execute(
        '''
        UPDATE contratos_alumnos SET
          mesa_extra_pagado = ?,
          mesa_extra_cuotas_pagadas = ?,
          mesas_extra_estado = ?,
          cuotas_pagadas = 2,
          saldo_deudor = ?,
          updated_at = ?
        WHERE id = ?
        ''',
        [mesaPrecio, mesaCuotas, estadoJson, saldoNuevo, now, _contratoId],
      );

      // Encolar SOLO el arreglo
      final pagoPayload = jsonEncode({
        'id': _pago55Id,
        'contrato_alumno_id': _contratoId,
        'concepto': conceptoNuevo,
        'monto': 55000.0,
        'monto_gross': 55000.0,
        'fecha_pago': p['fecha_pago'],
        'medio_pago': p['medio_pago'],
        'anulado': 0,
        'updated_at': now,
      });
      final contratoPayload = jsonEncode({
        'id': _contratoId,
        'saldo_deudor': saldoNuevo,
        'cuotas_pagadas': 2,
        'mesa_extra_pagado': mesaPrecio,
        'mesa_extra_cuotas_pagadas': mesaCuotas,
        'mesa_extra_cantidad': 1,
        'mesas_extra_estado': estadoMesa,
        'updated_at': now,
      });

      db.execute(
        '''
        INSERT INTO _sync_queue
          (tabla, operacion, registro_id, payload, created_at, intentos, ultimo_error)
        VALUES (?, 'update', ?, ?, ?, 0, NULL)
        ''',
        ['pagos_contrato_alumno', _pago55Id, pagoPayload, now],
      );
      db.execute(
        '''
        INSERT INTO _sync_queue
          (tabla, operacion, registro_id, payload, created_at, intentos, ultimo_error)
        VALUES (?, 'update', ?, ?, ?, 0, NULL)
        ''',
        ['contratos_alumnos', _contratoId, contratoPayload, now],
      );

      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }

    final colaFinal = db.select('SELECT COUNT(*) AS c FROM _sync_queue').first;
    final c2 = db.select(
      'SELECT mesa_extra_pagado, mesa_extra_cuotas_pagadas, cuotas_pagadas, '
      'saldo_deudor, mesas_extra_estado FROM contratos_alumnos WHERE id = ?',
      [_contratoId],
    ).first;
    final p2 = db.select(
      'SELECT concepto FROM pagos_contrato_alumno WHERE id = ?',
      [_pago55Id],
    ).first;

    print('\n=== LISTO ===');
    print('Pago concepto: ${p2['concepto']}');
    print(
      'Contrato: mesa_pagado=${c2['mesa_extra_pagado']} '
      'mesa_cuotas=${c2['mesa_extra_cuotas_pagadas']} '
      'base_cuotas=${c2['cuotas_pagadas']} saldo=${c2['saldo_deudor']}',
    );
    print('Estado mesa: ${c2['mesas_extra_estado']}');
    print('Cola sync: ${colaFinal['c']} (debe ser 2: pago + contrato)');
    print('\nAbrí la app y tocá la NUBE para subir SOLO estos 2.');
  } finally {
    db.dispose();
  }
}
