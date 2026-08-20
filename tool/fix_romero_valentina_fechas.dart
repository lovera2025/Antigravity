// Realinea ROMERO, VALENTINA (SAGRADO CORAZON) con los recibos físicos.
//
// Qué pasó: el cobro del 18/04 se perdió de la base. Desde ahí la app numeró
// una cuota menos, así que los recibos del 12/05, 13/06 y 13/07 salieron
// rotulados 2, 3 y 4 cuando eran 3, 4 y 5. El 03/08 17:22 alguien recuperó la
// cuota faltante (no fue una entrega de plata: fue una recarga) y 16 minutos
// después le puso fecha 13/07 a mano, que es el mes equivocado — iba al 18/04.
//
// Correcciones:
//   4505f79e  13/07 12:00 → 18/04 09:49   y  rótulo (5/9) → (2/9)
//   95462991  fecha OK (12/05)            y  rótulo (2/9) → (3/9)
//   98f21233  fecha OK (13/06)            y  rótulo (3/9) → (4/9)
//   0911d84c  fecha OK (13/07)            y  rótulo (4/9) → (5/9)
//
// No se tocan montos: saldo y cuotas pagadas no cambian.
//
// Uso: dart run tool/fix_romero_valentina_fechas.dart
//      dart run tool/fix_romero_valentina_fechas.dart --apply

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const _dbPath = r'C:\Users\lover\Documents\Junior Eventos\data.db';
const _contratoId = '00a2820b-d0db-4710-a1af-46003d7b1a18';

const _fixes = <_FixPago>[
  _FixPago(
    pagoId: '72eff53e-c996-4aed-bba0-b8de2a0fe631',
    conceptoActual: 'Cuota Base (1/9)',
    conceptoNuevo: 'Cuota Base (1/9)',
    fechaActual: '2026-03-25T14:30:52.162167+00:00',
    fechaNueva: '2026-03-25T14:30:52.162167+00:00',
    medioActual: null,
    medioNuevo: 'Efectivo',
    motivo: 'esa versión no guardaba el medio; se cobró en efectivo',
  ),
  _FixPago(
    pagoId: '4505f79e-9d0a-4e61-a4dd-d01e824fc7cb',
    conceptoActual: 'Cuota Base (5/9)',
    conceptoNuevo: 'Cuota Base (2/9)',
    fechaActual: '2026-07-13T15:00:00+00:00',
    fechaNueva: '2026-04-18T12:49:00.000000+00:00', // 18/04 09:49 AR
    medioActual: 'Efectivo',
    motivo: 'es la cuota que se perdió: recibo firmado del 18/04 09:49',
  ),
  _FixPago(
    pagoId: '95462991-0db9-49ab-8888-931915185c81',
    conceptoActual: 'Cuota Base (2/9)',
    conceptoNuevo: 'Cuota Base (3/9)',
    fechaActual: '2026-05-12T21:18:31.269893+00:00',
    fechaNueva: '2026-05-12T21:18:31.269893+00:00',
    medioActual: 'Efectivo',
    motivo: 'el papel dice 2/9 porque el 18/04 faltaba; era la 3',
  ),
  _FixPago(
    pagoId: '98f21233-8bdc-46d6-a50d-9ebe3bbc3f4d',
    conceptoActual: 'Cuota Base (3/9)',
    conceptoNuevo: 'Cuota Base (4/9)',
    fechaActual: '2026-06-13T13:38:01.530281+00:00',
    fechaNueva: '2026-06-13T13:38:01.530281+00:00',
    medioActual: 'Efectivo',
    motivo: 'corrido por el mismo hueco',
  ),
  _FixPago(
    pagoId: '0911d84c-9977-4fae-a703-86a8cbc0e63e',
    conceptoActual: 'Cuota Base (4/9)',
    conceptoNuevo: 'Cuota Base (5/9)',
    fechaActual: '2026-07-13T14:00:45.391141+00:00',
    fechaNueva: '2026-07-13T14:00:45.391141+00:00',
    medioActual: 'Efectivo',
    motivo: 'corrido por el mismo hueco',
  ),
];

class _FixPago {
  final String pagoId;
  final String conceptoActual;
  final String conceptoNuevo;
  final String fechaActual;
  final String fechaNueva;

  /// `medioActual` es el valor que se auditó (null = columna vacía). Si
  /// `medioNuevo` es null se deja como está.
  final String? medioActual;
  final String? medioNuevo;
  final String motivo;

  const _FixPago({
    required this.pagoId,
    required this.conceptoActual,
    required this.conceptoNuevo,
    required this.fechaActual,
    required this.fechaNueva,
    required this.motivo,
    this.medioActual,
    this.medioNuevo,
  });

  bool get cambiaFecha => fechaActual != fechaNueva;
  bool get cambiaConcepto => conceptoActual != conceptoNuevo;
  bool get cambiaMedio => medioNuevo != null && medioNuevo != medioActual;
}

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
    'SELECT nombre_alumno, institucion, created_at, saldo_deudor, '
    'cuotas_pagadas, total_cuotas FROM contratos_alumnos WHERE id = ?',
    [_contratoId],
  );
  if (cRow.isEmpty) {
    stderr.writeln('Contrato no encontrado: $_contratoId');
    db.dispose();
    exit(1);
  }
  final c = cRow.first;
  final altaAr = DateTime.parse(c['created_at'] as String)
      .toUtc()
      .subtract(const Duration(hours: 3));

  print('=== ${c['nombre_alumno']} (${c['institucion']}) ===');
  print('Saldo \$${c['saldo_deudor']} · ${c['cuotas_pagadas']}/'
      '${c['total_cuotas']} cuotas · no se tocan montos');
  print('');

  final pendientes = <_FixPago>[];
  for (final f in _fixes) {
    final rows = db.select(
      'SELECT concepto, fecha_pago, medio_pago, anulado '
      'FROM pagos_contrato_alumno WHERE id = ? AND contrato_alumno_id = ?',
      [f.pagoId, _contratoId],
    );
    if (rows.isEmpty) {
      stderr.writeln('✗ ${f.pagoId}: no existe en este contrato. Aborto.');
      db.dispose();
      exit(1);
    }
    final r = rows.first;
    if ((r['anulado'] as int? ?? 0) != 0) {
      stderr.writeln('✗ ${f.pagoId}: está anulado. Aborto.');
      db.dispose();
      exit(1);
    }
    final concepto = r['concepto'] as String;
    final fecha = r['fecha_pago'] as String;
    final medio = r['medio_pago'] as String?;
    final medioEsperado = f.medioNuevo ?? f.medioActual;

    if (concepto == f.conceptoNuevo &&
        fecha == f.fechaNueva &&
        medio == medioEsperado) {
      print('• ${f.conceptoNuevo}: ya estaba corregida, se saltea.');
      continue;
    }
    if (concepto != f.conceptoActual ||
        fecha != f.fechaActual ||
        medio != f.medioActual) {
      stderr.writeln('✗ ${f.pagoId}: la fila no está como se auditó '
          '(hoy "$concepto" / $fecha / medio ${medio ?? '(vacío)'}). '
          'Alguien la movió. Aborto.');
      db.dispose();
      exit(1);
    }

    print(f.cambiaConcepto
        ? '• ${f.conceptoActual} → ${f.conceptoNuevo}'
        : '• ${f.conceptoActual}');
    if (f.cambiaFecha) {
      print('    ${_ar(f.fechaActual)} → ${_ar(f.fechaNueva)}');
    } else {
      print('    ${_ar(f.fechaNueva)} (la fecha ya estaba bien)');
    }
    if (f.cambiaMedio) {
      print('    medio de pago: ${f.medioActual ?? '(vacío)'} → '
          '${f.medioNuevo}');
    }
    print('    ${f.motivo}');
    pendientes.add(f);
  }

  if (pendientes.isEmpty) {
    print('\nNada que hacer.');
    db.dispose();
    return;
  }

  // Control: la numeración tiene que quedar 1..6 sin repetidos ni huecos, en
  // orden cronológico, y ninguna cuota pagada fuera de término.
  final nuevoConcepto = {for (final f in pendientes) f.pagoId: f.conceptoNuevo};
  final nuevaFecha = {for (final f in pendientes) f.pagoId: f.fechaNueva};
  final todos = db.select(
    'SELECT id, concepto, fecha_pago FROM pagos_contrato_alumno '
    'WHERE contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)',
    [_contratoId],
  );

  final finales = <({int k, String iso, String concepto})>[];
  for (final p in todos) {
    final id = p['id'] as String;
    final concepto = nuevoConcepto[id] ?? p['concepto'] as String;
    final iso = nuevaFecha[id] ?? p['fecha_pago'] as String;
    final k = _numeroCuota(concepto);
    if (k == null) continue;
    finales.add((k: k, iso: iso, concepto: concepto));
  }
  finales.sort((a, b) => a.iso.compareTo(b.iso));

  print('\n--- Como queda la cuenta ---');
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
    print('  ${_ar(f.iso)}  ${f.concepto}  vence '
        '${venc.day}/${venc.month}/${venc.year}  '
        '${dias < 0 ? '⚠ ${-dias} días TARDE' : '✓ $dias días antes'}'
        '${ordenOk ? '' : '  ⚠ fuera de orden (esperaba ${i + 1})'}');
  }
  if (!ok) {
    stderr.writeln('\n✗ La numeración no queda limpia o hay mora. Aborto.');
    db.dispose();
    exit(1);
  }
  print('  → numeración 1..${finales.length} en orden, mora \$0.');

  if (!apply) {
    print('\n(dry-run) para aplicar:');
    print('dart run tool/fix_romero_valentina_fechas.dart --apply');
    db.dispose();
    return;
  }

  final backupPath = '$_dbPath.bak.romero.'
      '${DateTime.now().toIso8601String().replaceAll(':', '-')}';
  File(_dbPath).copySync(backupPath);
  print('\nBackup: $backupPath');

  final nowUtc = DateTime.now().toUtc().toIso8601String();
  db.execute('BEGIN');
  try {
    for (final f in pendientes) {
      db.execute(
        'UPDATE pagos_contrato_alumno '
        'SET concepto = ?, fecha_pago = ?, medio_pago = ?, updated_at = ? '
        'WHERE id = ?',
        [
          f.conceptoNuevo,
          f.fechaNueva,
          f.medioNuevo ?? f.medioActual,
          nowUtc,
          f.pagoId,
        ],
      );
      _enqueueSyncPago(db, f.pagoId);
    }
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
  final saldo = db.select(
    'SELECT saldo_deudor, cuotas_pagadas FROM contratos_alumnos WHERE id = ?',
    [_contratoId],
  ).first;
  print('Saldo \$${saldo['saldo_deudor']} · ${saldo['cuotas_pagadas']}/9 '
      '(sin cambios)');
  print('Sync encolado para subir cuando quieras.');
  db.dispose();
}

void _enqueueSyncPago(Database db, String pagoId) {
  const tabla = 'pagos_contrato_alumno';
  final now = DateTime.now().toUtc().toIso8601String();
  final p = db
      .select('SELECT * FROM pagos_contrato_alumno WHERE id = ?', [pagoId])
      .first;
  final fresco = Map<String, dynamic>.from(p)..remove('line_kind');

  final existing = db.select(
    'SELECT payload FROM _sync_queue WHERE tabla = ? AND registro_id = ?',
    [tabla, pagoId],
  );
  if (existing.isNotEmpty) {
    final merged = {
      ...jsonDecode(existing.first['payload'] as String) as Map<String, dynamic>,
      ...fresco,
    };
    db.execute(
      'UPDATE _sync_queue SET payload = ?, created_at = ?, intentos = 0, '
      'ultimo_error = NULL WHERE tabla = ? AND registro_id = ?',
      [jsonEncode(merged), now, tabla, pagoId],
    );
  } else {
    db.execute(
      'INSERT INTO _sync_queue (tabla, operacion, registro_id, payload, '
      'created_at, intentos) VALUES (?, ?, ?, ?, ?, 0)',
      [tabla, 'update', pagoId, jsonEncode(fresco), now],
    );
  }
}
