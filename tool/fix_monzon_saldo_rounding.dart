// Alinea monto_gross del abono mesa (cobro mixto 27/05) y recalcula saldo.
// Uso: dart run tool/fix_monzon_saldo_rounding.dart
//      dart run tool/fix_monzon_saldo_rounding.dart --apply

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _dbPath = r'C:\Users\lover\Documents\Junior Eventos\data.db';
const _contratoId = 'f3ddd0d3-5ec1-4f08-956c-0a5819d53a8a';

void main(List<String> args) {
  final apply = args.contains('--apply');
  if (!File(_dbPath).existsSync()) {
    stderr.writeln('No se encontró: $_dbPath');
    exit(1);
  }

  final db = sqlite3.open(_dbPath);
  final cRow = db.select(
    'SELECT nombre_alumno, monto_total_pactado, saldo_deudor FROM contratos_alumnos WHERE id = ?',
    [_contratoId],
  );
  if (cRow.isEmpty) {
    stderr.writeln('Contrato no encontrado');
    exit(1);
  }
  final nombre = cRow.first['nombre_alumno'];
  final pactado = (cRow.first['monto_total_pactado'] as num).toDouble();
  final saldoAntes = (cRow.first['saldo_deudor'] as num).toDouble();

  // Línea mesa del mixto 27/05: neto 13018.87, gross inflado 13018.9 (+0.03 al saldo).
  final targets = db.select(
    '''
    SELECT id, monto, monto_gross, concepto, fecha_pago
    FROM pagos_contrato_alumno
    WHERE contrato_alumno_id = ?
      AND (anulado IS NULL OR anulado = 0)
      AND LOWER(concepto) LIKE '%abono a mesa%'
      AND ABS(monto - 13018.87) < 0.02
      AND ABS(IFNULL(monto_gross, monto) - 13018.9) < 0.02
    ''',
    [_contratoId],
  );

  if (targets.isEmpty) {
    stderr.writeln('No se encontró la línea mesa a corregir.');
    db.dispose();
    exit(1);
  }

  double grossSaldoAntes = 0;
  final pagos = db.select(
    '''
    SELECT monto, monto_gross, concepto, line_kind
    FROM pagos_contrato_alumno
    WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)
    ''',
    [_contratoId],
  );
  for (final p in pagos) {
    final lk = (p['line_kind'] as String?) ?? '';
    final conc = (p['concepto'] as String).toLowerCase();
    if (lk == 'interes_mora' ||
        lk == 'cargo_canal_ref' ||
        conc.contains('mora') ||
        conc.contains('cargo canal')) {
      continue;
    }
    grossSaldoAntes +=
        (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num).toDouble();
  }
  final saldoEsperado =
      double.parse((pactado - grossSaldoAntes + 0.03).toStringAsFixed(2));

  print('=== Fix redondeo: $nombre ===');
  print('Saldo actual: $saldoAntes');
  print('Saldo esperado tras fix: $saldoEsperado');
  for (final t in targets) {
    print(
      'Pago ${t['id']}: gross ${t['monto_gross']} → 13018.87 (${t['concepto']})',
    );
  }

  if (!apply) {
    print('\n(dry-run) dart run tool/fix_monzon_saldo_rounding.dart --apply');
    db.dispose();
    return;
  }

  final backupPath =
      '$_dbPath.bak.monzon.${DateTime.now().toIso8601String().replaceAll(':', '-')}';
  File(_dbPath).copySync(backupPath);
  print('\nBackup: $backupPath');

  final nowUtc = DateTime.now().toUtc().toIso8601String();
  db.execute('BEGIN');
  try {
    for (final t in targets) {
      final pagoId = t['id'] as String;
      db.execute(
        '''
        UPDATE pagos_contrato_alumno
        SET monto_gross = 13018.87, updated_at = ?
        WHERE id = ?
        ''',
        [nowUtc, pagoId],
      );
      _enqueueSyncPago(db, pagoId, 13018.87);
    }

    db.execute(
      '''
      UPDATE contratos_alumnos
      SET saldo_deudor = ?, updated_at = ?
      WHERE id = ?
      ''',
      [saldoEsperado, nowUtc, _contratoId],
    );
    _enqueueSyncContrato(db, _contratoId, saldoEsperado);

    db.execute('COMMIT');

    final saldoDespues = (db.select(
      'SELECT saldo_deudor FROM contratos_alumnos WHERE id = ?',
      [_contratoId],
    ).first['saldo_deudor'] as num).toDouble();
    print('Saldo después: $saldoDespues');
    print('Listo. Sync encolado para subir cuando quieras.');
  } catch (e) {
    db.execute('ROLLBACK');
    stderr.writeln('Error — rollback: $e');
    exit(1);
  } finally {
    db.dispose();
  }
}

void _enqueueSyncPago(Database db, String pagoId, double montoGross) {
  final rows = db.select('SELECT payload FROM _sync_queue WHERE tabla = ? AND registro_id = ?', [
    'pagos_contrato_alumno',
    pagoId,
  ]);
  final now = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> payload;
  if (rows.isNotEmpty) {
    payload = jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>;
    payload['monto_gross'] = montoGross;
    db.execute(
      'UPDATE _sync_queue SET payload = ?, created_at = ?, intentos = 0, ultimo_error = NULL WHERE tabla = ? AND registro_id = ?',
      [jsonEncode(payload), now, 'pagos_contrato_alumno', pagoId],
    );
  } else {
    final p = db.select('SELECT * FROM pagos_contrato_alumno WHERE id = ?', [pagoId]).first;
    payload = Map<String, dynamic>.from(p);
    payload.remove('line_kind');
    payload['monto_gross'] = montoGross;
    db.execute(
      'INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, created_at, intentos) VALUES (?, ?, ?, ?, ?, 0)',
      ['pagos_contrato_alumno', 'update', pagoId, jsonEncode(payload), now],
    );
  }
}

void _enqueueSyncContrato(Database db, String contratoId, double saldo) {
  const tabla = 'contratos_alumnos';
  final now = DateTime.now().toUtc().toIso8601String();
  final existing = db.select(
    'SELECT payload FROM _sync_queue WHERE tabla = ? AND registro_id = ?',
    [tabla, contratoId],
  );
  if (existing.isNotEmpty) {
    final merged = {
      ...jsonDecode(existing.first['payload'] as String) as Map<String, dynamic>,
      'id': contratoId,
      'saldo_deudor': saldo,
    };
    db.execute(
      'UPDATE _sync_queue SET payload = ?, created_at = ?, intentos = 0, ultimo_error = NULL WHERE tabla = ? AND registro_id = ?',
      [jsonEncode(merged), now, tabla, contratoId],
    );
  } else {
    db.execute(
      'INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, created_at, intentos) VALUES (?, ?, ?, ?, ?, 0)',
      [
        tabla,
        'update',
        contratoId,
        jsonEncode({'id': contratoId, 'saldo_deudor': saldo}),
        now,
      ],
    );
  }
}
