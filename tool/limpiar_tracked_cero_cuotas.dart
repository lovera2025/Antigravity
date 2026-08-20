// Limpieza segura: mora_pendiente_tracked en contratos 0/9 (snapshot restore
// sin cuotas pagadas). No toca cuotas_pagadas, Reg, pagos ni contratos con ≥1 cuota.
//
// Uso:
//   dart run tool/limpiar_tracked_cero_cuotas.dart           # solo auditoría
//   dart run tool/limpiar_tracked_cero_cuotas.dart --apply # backup + limpia + sync

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _dbPath = r'C:\Users\lover\Documents\Junior Eventos\data.db';

void main(List<String> args) {
  final apply = args.contains('--apply');
  if (!File(_dbPath).existsSync()) {
    stderr.writeln('No se encontró: $_dbPath');
    exit(1);
  }

  final db = sqlite3.open(_dbPath);

  const selectSql = '''
    SELECT c.id, c.nombre_alumno, c.cuotas_pagadas, c.total_cuotas,
           c.mora_pendiente_tracked,
           COALESCE((
             SELECT SUM(p.monto) FROM pagos_contrato_alumno p
             WHERE p.contrato_alumno_id = c.id
               AND (p.anulado IS NULL OR p.anulado = 0)
               AND (p.line_kind = 'interes_mora'
                    OR LOWER(IFNULL(p.concepto,'')) LIKE '%mora%'
                    OR LOWER(IFNULL(p.concepto,'')) LIKE '%inter%')
           ), 0) AS mora_hist
    FROM contratos_alumnos c
    WHERE c.cuotas_pagadas = 0
      AND c.mora_pendiente_tracked > 0.01
      AND c.saldo_deudor > 0.01
    ORDER BY c.mora_pendiente_tracked DESC, c.nombre_alumno COLLATE NOCASE
  ''';

  final rows = db.select(selectSql);
  if (rows.isEmpty) {
    print('Nada que limpiar: ningún contrato 0/9 con mora_pendiente_tracked > 0.');
    db.dispose();
    return;
  }

  var totalTracked = 0.0;
  print('=== Candidatos (${rows.length}) — 0 cuotas pagadas, tracked > 0 ===\n');
  for (final r in rows) {
    final tracked = (r['mora_pendiente_tracked'] as num).toDouble();
    totalTracked += tracked;
    print(
      '  ${r['nombre_alumno']} | tracked ${tracked.toStringAsFixed(2)} '
      '| hist mora ${(r['mora_hist'] as num).toStringAsFixed(2)} '
      '| id ${r['id']}',
    );
  }
  print('\nTotal tracked a limpiar: ${totalTracked.toStringAsFixed(2)}');

  if (!apply) {
    print('\n(dry-run) Para aplicar: dart run tool/limpiar_tracked_cero_cuotas.dart --apply');
    db.dispose();
    return;
  }

  final backupPath =
      '$_dbPath.bak.${DateTime.now().toIso8601String().replaceAll(':', '-')}';
  File(_dbPath).copySync(backupPath);
  print('\nBackup: $backupPath');

  final nowUtc = DateTime.now().toUtc().toIso8601String();
  db.execute('BEGIN');
  try {
    for (final r in rows) {
      final id = r['id'] as String;
      db.execute(
        '''
        UPDATE contratos_alumnos
        SET mora_pendiente_tracked = 0,
            updated_at = ?
        WHERE id = ?
        ''',
        [nowUtc, id],
      );
      _enqueueSync(db, id);
    }
    db.execute('COMMIT');
    print('Limpieza aplicada en ${rows.length} contrato(s). Sync encolado.');
  } catch (e) {
    db.execute('ROLLBACK');
    stderr.writeln('Error — rollback: $e');
    exit(1);
  } finally {
    db.dispose();
  }
}

void _enqueueSync(Database db, String contratoId) {
  const tabla = 'contratos_alumnos';
  final payload = jsonEncode({
    'id': contratoId,
    'mora_pendiente_tracked': 0.0,
  });
  final now = DateTime.now().toUtc().toIso8601String();

  final existing = db.select(
    'SELECT id, operacion, payload FROM _sync_queue WHERE tabla = ? AND registro_id = ?',
    [tabla, contratoId],
  );

  if (existing.isNotEmpty) {
    final oldPayload = jsonDecode(existing.first['payload'] as String)
        as Map<String, dynamic>;
    final merged = {...oldPayload, 'id': contratoId, 'mora_pendiente_tracked': 0.0};
    db.execute(
      '''
      UPDATE _sync_queue
      SET payload = ?, created_at = ?, intentos = 0, ultimo_error = NULL
      WHERE tabla = ? AND registro_id = ?
      ''',
      [jsonEncode(merged), now, tabla, contratoId],
    );
  } else {
    db.execute(
      '''
      INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, created_at, intentos)
      VALUES (?, 'update', ?, ?, ?, 0)
      ''',
      [tabla, contratoId, payload, now],
    );
  }
}
