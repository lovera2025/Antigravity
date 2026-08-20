// Repone el pago del 07/07/2026 de OSORIO, URIEL (NORMAL MARIANO ILOZA) que
// nunca llegó a la nube desde la PC de Recepción, y recalcula saldo y cuotas.
//
// El pago existe en papel: recibo N° 007BED9E, 07/07/2026 12:08 hs, Efectivo,
// "Cuota Base (4/9)", $30.000, saldo pendiente $150.000. La mora no está
// persistida (mora_pendiente_tracked = 0), así que se corrige sola al volver
// la cuota 4 a su lugar: vencía el 31/07 y se pagó el 07/07.
//
// Uso: dart run tool/fix_osorio_uriel_pago_perdido.dart
//      dart run tool/fix_osorio_uriel_pago_perdido.dart --apply

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _dbPath = r'C:\Users\lover\Documents\Junior Eventos\data.db';
const _contratoId = '007bed9e-8dd7-4555-9a63-35df35aa885a';

// Id fijo para que el script sea idempotente: si ya se aplicó, no duplica.
const _pagoId = '7e430764-e29b-42f7-8a11-5a6887f4c9c0';
const _concepto = 'Cuota Base (4/9)';
const _fechaPago = '2026-07-07T15:08:00.000000+00:00'; // 07/07 12:08 AR
const _monto = 30000.0;
const _medioPago = 'Efectivo';

String _ar(String iso) {
  final d = DateTime.parse(iso).toUtc().subtract(const Duration(hours: 3));
  String dd(int v) => v.toString().padLeft(2, '0');
  return '${dd(d.day)}/${dd(d.month)}/${d.year} ${dd(d.hour)}:${dd(d.minute)}';
}

/// Vencimiento de la cuota [k]: último día del mes k contado desde el alta.
DateTime _vencimiento(DateTime altaAr, int k) {
  final m = altaAr.month + k;
  return DateTime(altaAr.year + ((m - 1) ~/ 12), ((m - 1) % 12) + 2, 0);
}

int? _numeroCuota(String concepto) {
  final m = RegExp(r'\((\d+)/').firstMatch(concepto);
  return m == null ? null : int.tryParse(m.group(1)!);
}

void main(List<String> args) {
  final apply = args.contains('--apply');
  if (!File(_dbPath).existsSync()) {
    stderr.writeln('No se encontró: $_dbPath');
    exit(1);
  }

  final db = sqlite3.open(_dbPath);

  final cRow = db.select(
    'SELECT nombre_alumno, institucion, created_at, monto_total_pactado, '
    'saldo_deudor, cuotas_pagadas, total_cuotas, mesa_extra_precio, '
    'sillas_extra_precio_total, mora_pendiente_tracked '
    'FROM contratos_alumnos WHERE id = ?',
    [_contratoId],
  );
  if (cRow.isEmpty) {
    stderr.writeln('Contrato no encontrado: $_contratoId');
    db.dispose();
    exit(1);
  }
  final c = cRow.first;
  final pactado = (c['monto_total_pactado'] as num).toDouble();
  final totalCuotas = c['total_cuotas'] as int;
  final altaAr = DateTime.parse(c['created_at'] as String)
      .toUtc()
      .subtract(const Duration(hours: 3));

  print('=== ${c['nombre_alumno']} (${c['institucion']}) ===');
  print('Hoy: saldo \$${c['saldo_deudor']} · '
      '${c['cuotas_pagadas']}/$totalCuotas cuotas');

  // El script no está preparado para mesa/sillas: ahí el recálculo de cuotas
  // no es una simple división y hay que hacerlo con el motor de la app.
  final mesa = (c['mesa_extra_precio'] as num?)?.toDouble() ?? 0;
  final sillas = (c['sillas_extra_precio_total'] as num?)?.toDouble() ?? 0;
  if (mesa > 0.01 || sillas > 0.01) {
    stderr.writeln('✗ El contrato tiene mesa/sillas extra. Aborto.');
    db.dispose();
    exit(1);
  }

  final yaEsta = db.select(
    'SELECT id FROM pagos_contrato_alumno WHERE id = ?',
    [_pagoId],
  );
  if (yaEsta.isNotEmpty) {
    print('\nEl pago ya estaba repuesto. Nada que hacer.');
    db.dispose();
    return;
  }

  // Blindaje: si ya hay un pago ese día por ese monto, no duplicar.
  final duplicado = db.select(
    "SELECT id, concepto, fecha_pago FROM pagos_contrato_alumno "
    "WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0) "
    "AND fecha_pago >= '2026-07-07' AND fecha_pago < '2026-07-08' "
    "AND abs(monto - ?) < 0.01",
    [_contratoId, _monto],
  );
  if (duplicado.isNotEmpty) {
    stderr.writeln('✗ Ya existe un pago del 07/07 por \$$_monto '
        '(${duplicado.first['id']}). Aborto para no duplicar.');
    db.dispose();
    exit(1);
  }

  print('\n--- Pago a reponer (tal cual el recibo N° 007BED9E) ---');
  print('  ${_ar(_fechaPago)}  $_concepto  \$$_monto  · $_medioPago');

  // Recálculo desde la suma de pagos del plan, igual que hace la app.
  final pagos = db.select(
    'SELECT monto, monto_gross, concepto, line_kind FROM pagos_contrato_alumno '
    'WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)',
    [_contratoId],
  );
  var grossBase = 0.0;
  for (final p in pagos) {
    final lk = (p['line_kind'] as String?) ?? '';
    final conc = (p['concepto'] as String? ?? '').toLowerCase();
    if (lk == 'interes_mora' ||
        lk == 'cargo_canal_ref' ||
        conc.contains('mora') ||
        conc.contains('interés') ||
        conc.contains('cargo canal')) {
      continue;
    }
    grossBase +=
        (p['monto_gross'] as num?)?.toDouble() ?? (p['monto'] as num).toDouble();
  }
  grossBase += _monto;

  final cuotaPura = pactado / totalCuotas;
  final saldoNuevo = double.parse(
    (pactado - grossBase).clamp(0.0, double.infinity).toStringAsFixed(2),
  );
  final cuotasNuevas =
      ((grossBase + 0.1) / cuotaPura).floor().clamp(0, totalCuotas);

  print('\n--- Como queda la cuenta ---');
  final finales = <({int k, String iso})>[];
  final todos = db.select(
    'SELECT concepto, fecha_pago FROM pagos_contrato_alumno '
    'WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)',
    [_contratoId],
  );
  for (final p in todos) {
    final k = _numeroCuota(p['concepto'] as String);
    if (k != null) finales.add((k: k, iso: p['fecha_pago'] as String));
  }
  finales.add((k: 4, iso: _fechaPago));
  finales.sort((a, b) => a.iso.compareTo(b.iso));

  var ok = true;
  for (var i = 0; i < finales.length; i++) {
    final f = finales[i];
    final pagoAr =
        DateTime.parse(f.iso).toUtc().subtract(const Duration(hours: 3));
    final venc = _vencimiento(altaAr, f.k);
    final dias = venc
        .difference(DateTime(pagoAr.year, pagoAr.month, pagoAr.day))
        .inDays;
    final ordenOk = f.k == i + 1;
    if (!ordenOk || dias < 0) ok = false;
    print('  ${_ar(f.iso)}  Cuota ${f.k}/$totalCuotas  vence '
        '${venc.day}/${venc.month}/${venc.year}  '
        '${dias < 0 ? '⚠ ${-dias} días TARDE' : '✓ $dias días antes'}'
        '${ordenOk ? '' : '  ⚠ fuera de orden'}');
  }
  if (!ok) {
    stderr.writeln('\n✗ La numeración no queda limpia o hay mora. Aborto.');
    db.dispose();
    exit(1);
  }

  final proxima = finales.length + 1;
  final vencProxima = _vencimiento(altaAr, proxima);
  print('  → próxima: cuota $proxima, vence '
      '${vencProxima.day}/${vencProxima.month}/${vencProxima.year}');
  print('\nSaldo: ${c['saldo_deudor']} → $saldoNuevo   ·   '
      'Cuotas: ${c['cuotas_pagadas']} → $cuotasNuevas');
  print('Mora: no está persistida (tracked = ${c['mora_pendiente_tracked']}), '
      'se recalcula sola → \$0');

  if (!apply) {
    print('\n(dry-run) para aplicar:');
    print('dart run tool/fix_osorio_uriel_pago_perdido.dart --apply');
    db.dispose();
    return;
  }

  final backupPath = '$_dbPath.bak.osorio.'
      '${DateTime.now().toIso8601String().replaceAll(':', '-')}';
  File(_dbPath).copySync(backupPath);
  print('\nBackup: $backupPath');

  final nowUtc = DateTime.now().toUtc().toIso8601String();
  db.execute('BEGIN');
  try {
    db.execute(
      'INSERT INTO pagos_contrato_alumno '
      '(id, contrato_alumno_id, monto, monto_gross, descuento_porcentaje, '
      ' concepto, fecha_pago, created_at, medio_pago, anulado, updated_at) '
      'VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?, 0, ?)',
      [
        _pagoId,
        _contratoId,
        _monto,
        _monto,
        _concepto,
        _fechaPago,
        _fechaPago,
        _medioPago,
        nowUtc,
      ],
    );
    db.execute(
      'UPDATE contratos_alumnos SET saldo_deudor = ?, cuotas_pagadas = ?, '
      'updated_at = ? WHERE id = ?',
      [saldoNuevo, cuotasNuevas, nowUtc, _contratoId],
    );
    _enqueue(db, 'pagos_contrato_alumno', 'insert', _pagoId);
    _enqueue(db, 'contratos_alumnos', 'update', _contratoId);
    db.execute('COMMIT');
  } catch (e) {
    db.execute('ROLLBACK');
    stderr.writeln('Error — rollback: $e');
    db.dispose();
    exit(1);
  }

  print('\n--- Quedó así ---');
  final fin = db.select(
    'SELECT concepto, fecha_pago, medio_pago FROM pagos_contrato_alumno '
    'WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0) '
    'ORDER BY fecha_pago',
    [_contratoId],
  );
  for (final p in fin) {
    print('  ${_ar(p['fecha_pago'] as String)}  ${p['concepto']}'
        '  · ${p['medio_pago'] ?? '(sin medio)'}');
  }
  final f = db.select(
    'SELECT saldo_deudor, cuotas_pagadas FROM contratos_alumnos WHERE id = ?',
    [_contratoId],
  ).first;
  print('Saldo \$${f['saldo_deudor']} · ${f['cuotas_pagadas']}/$totalCuotas');
  print('Sync encolado para subir cuando quieras.');
  db.dispose();
}

void _enqueue(Database db, String tabla, String operacion, String registroId) {
  final now = DateTime.now().toUtc().toIso8601String();
  final row = db.select('SELECT * FROM $tabla WHERE id = ?', [registroId]).first;
  final payload = Map<String, dynamic>.from(row)..remove('line_kind');

  final existing = db.select(
    'SELECT payload FROM _sync_queue WHERE tabla = ? AND registro_id = ?',
    [tabla, registroId],
  );
  if (existing.isNotEmpty) {
    final merged = {
      ...jsonDecode(existing.first['payload'] as String) as Map<String, dynamic>,
      ...payload,
    };
    db.execute(
      'UPDATE _sync_queue SET payload = ?, created_at = ?, intentos = 0, '
      'ultimo_error = NULL WHERE tabla = ? AND registro_id = ?',
      [jsonEncode(merged), now, tabla, registroId],
    );
  } else {
    db.execute(
      'INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, '
      'created_at, intentos) VALUES (?, ?, ?, ?, ?, 0)',
      [tabla, operacion, registroId, jsonEncode(payload), now],
    );
  }
}
