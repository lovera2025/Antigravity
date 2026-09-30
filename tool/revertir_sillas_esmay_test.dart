// ESMAY, THIAGO: el pago de sillas del 25/06 vuelve a $12.000, como lo pagó la
// familia, y sus sillas vuelven a $36.000, pagadas. Pedido del cliente el
// 29-sep, solo para este alumno.
//
// El 24-sep (`corregir_extras_alumnos_test.dart`) las sillas pasaron de $36.000
// a $32.000 y ese pago se partió en $8.000 de sillas + $4.000 de cuota base. El
// 28-sep la familia completó la cuota 7 contando con esos $4.000. Por eso:
//   - el pago de sillas pasa de $8.000 a $12.000 (lo que la familia pagó);
//   - la entrega parcial de $4.000 y el cobro del 28-sep NO se tocan;
//   - sillas $32.000 → $36.000 y total $417.000 → $421.000;
//   - saldo y cuotas quedan como hoy: $70.000 y 7 de 9.
// Los $4.000 de más son el redondeo que el cliente da por descartado.
//
// Uso:
//   flutter test tool/revertir_sillas_esmay_test.dart                  (DRY-RUN)
//   ... --dart-define=APPLY=1   (escribe: con la app CERRADA y después de las 20 hs)
//
// Aborta SIN ESCRIBIR NADA si algún valor de hoy no es el revisado, si hay algo
// en la cola de subida para el alumno o sus pagos, o si el saldo, las cuotas o
// la cuota base no dan lo acordado.
// APPLY: copia de data.db, una sola transacción, UPDATE + encolado. Ningún DELETE.
// Después: abrir la app, "Subir pendientes" y comparar.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _id = 'dd8af936-8880-4a50-8ee0-4de0086ce0e5';
const _nombre = 'ESMAY, THIAGO';

/// Valores de hoy, revisados con el usuario el 29-sep.
const _esperado = <String, num>{
  'monto_total_pactado': 417000,
  'saldo_deudor': 70000,
  'cuotas_pagadas': 7,
  'mesa_extra_precio': 70000,
  'sillas_extra_cantidad': 4,
  'sillas_extra_precio_total': 32000,
  'sillas_extra_pagado': 32000,
};

const _cambios = <String, num>{
  'sillas_extra_precio_total': 36000,
  'monto_total_pactado': 421000,
};

/// El pago de sillas del 25/06, que vuelve a lo que pagó la familia.
const _pagoSillas = 'e5f9473f-b9cf-4652-ad0c-b6d9a15ada56';

/// La entrega parcial de $4.000 que completó la cuota 7: no se toca.
const _pagoEntrega = 'e4d0c0e6-f5ef-4a60-bfd7-056a5e0bdf48';

class _Freno implements Exception {
  final String motivo;
  _Freno(this.motivo);
  @override
  String toString() => motivo;
}

bool _igual(dynamic a, dynamic b) {
  if (a is num && b is num) return (a.toDouble() - b.toDouble()).abs() <= 0.01;
  return a == b;
}

String _p(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}\$$b';
}

RecalculoContratoDesdePagos _recalcular(
  ContratoAlumno c,
  List<Map<String, dynamic>> pagos,
) =>
    recalcularSaldoDesdePagos(
      montoTotalPactado: c.montoTotalPactado,
      totalCuotas: c.totalCuotas,
      mesaExtraPrecio: c.mesaExtraPrecio,
      sillasExtraPrecioTotal: c.sillasExtraPrecioTotal,
      precioUnitarioMesaExtra: c.precioUnitarioMesaExtra,
      mesaExtraCuotas: c.mesaExtraCuotas,
      mesaExtraCantidad: c.mesaExtraCantidad,
      sillasExtraCuotas: c.sillasExtraCuotas,
      pagos: pagos,
    );

class _Plan {
  final Map<String, dynamic> pagoNuevo;
  final Map<String, dynamic> updates;
  final List<String> lineas;
  _Plan(this.pagoNuevo, this.updates, this.lineas);
}

Future<_Plan> _planificar(DatabaseExecutor db) async {
  final rows = await db.query(
    'contratos_alumnos',
    where: 'id = ?',
    whereArgs: [_id],
    limit: 1,
  );
  if (rows.isEmpty) throw _Freno('$_nombre: no está en la base local.');
  final row = rows.first;
  if ((row['nombre_alumno'] as String? ?? '').trim().toUpperCase() != _nombre) {
    throw _Freno('$_id: no es $_nombre (${row['nombre_alumno']}).');
  }
  for (final e in _esperado.entries) {
    if (!_igual(row[e.key], e.value)) {
      throw _Freno('$_nombre: ${e.key} es ${row[e.key]} y se revisó '
          '${e.value}. Algo cambió desde la revisión: no se toca.');
    }
  }

  final pagos = (await db.query(
    'pagos_contrato_alumno',
    where: 'contrato_alumno_id = ?',
    whereArgs: [_id],
    orderBy: 'fecha_pago',
  ))
      .map((p) => Map<String, dynamic>.from(p))
      .toList();

  final idsEnJuego = [_id, ...pagos.map((p) => p['id'] as String)];
  final enCola = await db.query(
    '_sync_queue',
    columns: ['tabla'],
    where: 'registro_id IN (${List.filled(idsEnJuego.length, '?').join(',')})',
    whereArgs: idsEnJuego,
  );
  if (enCola.isNotEmpty) {
    throw _Freno('$_nombre: tiene ${enCola.length} cambio(s) sin subir. '
        'Primero "Subir pendientes".');
  }

  final contratoAntes = ContratoAlumno.fromJson(row);
  final recAntes = _recalcular(contratoAntes, pagos);
  if (!_igual(recAntes.saldoDeudor, row['saldo_deudor'])) {
    throw _Freno('$_nombre: el saldo guardado (${row['saldo_deudor']}) no '
        'coincide con sus pagos (${recAntes.saldoDeudor}). No se toca.');
  }

  final sillas = pagos.where((p) => p['id'] == _pagoSillas).toList();
  if (sillas.length != 1) throw _Freno('$_nombre: no está el pago de sillas.');
  final pagoSillas = sillas.single;
  if ((pagoSillas['anulado'] as num? ?? 0) != 0 ||
      pagoSillas['concepto'] != 'Sillas Extras - Entrega' ||
      !_igual(pagoSillas['monto'], 8000) ||
      !_igual(pagoSillas['monto_gross'], 8000)) {
    throw _Freno('$_nombre: el pago de sillas no es el revisado '
        '(${pagoSillas['concepto']} ${pagoSillas['monto']}).');
  }
  final entrega = pagos.where((p) => p['id'] == _pagoEntrega).toList();
  if (entrega.length != 1 ||
      (entrega.single['anulado'] as num? ?? 0) != 0 ||
      !_igual(entrega.single['monto'], 4000) ||
      !'${entrega.single['concepto']}'.contains('Cuota Base (7/9)')) {
    throw _Freno('$_nombre: la entrega parcial de \$4.000 no es la revisada.');
  }

  final ahora = DateTime.now().toUtc().toIso8601String();
  final pagoNuevo = Map<String, dynamic>.from(pagoSillas)
    ..['monto'] = 12000.0
    ..['monto_gross'] = 12000.0
    ..['updated_at'] = ahora;
  final pagosDespues = [
    for (final p in pagos) p['id'] == _pagoSillas ? pagoNuevo : p,
  ];

  final rowDespues = Map<String, dynamic>.from(row)..addAll(_cambios);
  final contratoDespues = ContratoAlumno.fromJson(rowDespues);
  final rec = _recalcular(contratoDespues, pagosDespues);

  // Lo mismo que hace recalcularProgresoContrato.
  final nuevos = <String, dynamic>{
    ..._cambios,
    'cuotas_pagadas': rec.cuotasBase,
    'mesa_extra_cuotas_pagadas': rec.cuotasMesa,
    'sillas_extra_cuotas_pagadas': rec.cuotasSillas,
    'mesa_extra_pagado': rec.grossMesa,
    'sillas_extra_pagado': rec.grossSillas,
    'saldo_deudor': rec.saldoDeudor.clamp(0, double.infinity),
  };

  // Frenos sobre el resultado: lo acordado con el usuario.
  if (!_igual(rec.saldoDeudor, 70000) || rec.cuotasBase != 7) {
    throw _Freno('$_nombre: quedaría saldo ${_p(rec.saldoDeudor)} y '
        '${rec.cuotasBase} cuotas; se acordó \$70.000 y 7.');
  }
  if (!_igual(rec.grossSillas, 36000)) {
    throw _Freno('$_nombre: lo pagado de sillas daría ${_p(rec.grossSillas)}, '
        'no \$36.000.');
  }
  final cuotaAntes = MoraCuotaCalculator.cuotaBaseDe(contratoAntes);
  final cuotaDespues = MoraCuotaCalculator.cuotaBaseDe(contratoDespues);
  if (!_igual(cuotaAntes, cuotaDespues)) {
    throw _Freno('$_nombre: la cuota base cambiaría '
        '(${_p(cuotaAntes)} → ${_p(cuotaDespues)}) y con ella la mora.');
  }

  final updates = <String, dynamic>{
    for (final e in nuevos.entries)
      if (!_igual(row[e.key], e.value)) e.key: e.value,
  };

  final lineas = <String>[
    '$_nombre  ($_id)',
    '  pago de sillas del 25/06 ($_pagoSillas): '
        '${_p(pagoSillas['monto'] as num)} → ${_p(12000)}',
    '  entrega parcial de \$4.000 ($_pagoEntrega): no se toca',
    '  total ${_p(contratoAntes.montoTotalPactado)} → '
        '${_p(contratoDespues.montoTotalPactado)}   '
        'saldo ${_p(contratoAntes.saldoDeudor)} → ${_p(rec.saldoDeudor)}   '
        'cuotas ${contratoAntes.cuotasPagadas} → ${rec.cuotasBase}   '
        'cuota base ${_p(cuotaAntes)} (igual: la mora no cambia)',
    for (final e in updates.entries) '    ${e.key}: ${row[e.key]} → ${e.value}',
  ];
  return _Plan(pagoNuevo, updates, lineas);
}

Future<void> _aplicar(DatabaseExecutor txn, _Plan plan) async {
  final p = plan.pagoNuevo;
  final n = await txn.update(
    'pagos_contrato_alumno',
    {
      'monto': p['monto'],
      'monto_gross': p['monto_gross'],
      'updated_at': p['updated_at'],
    },
    where: 'id = ?',
    whereArgs: [_pagoSillas],
  );
  if (n != 1) throw _Freno('$_nombre: no se pudo actualizar el pago.');
  await SyncQueue.enqueue(
    executor: txn,
    tabla: 'pagos_contrato_alumno',
    operacion: SyncOperation.update,
    registroId: _pagoSillas,
    payload: Map<String, dynamic>.from(p)..remove('line_kind'),
  );

  final m = await txn.update(
    'contratos_alumnos',
    {...plan.updates, 'updated_at': DateTime.now().toUtc().toIso8601String()},
    where: 'id = ?',
    whereArgs: [_id],
  );
  if (m != 1) throw _Freno('$_nombre: no se pudo actualizar el contrato.');
  await SyncQueue.enqueue(
    executor: txn,
    tabla: 'contratos_alumnos',
    operacion: SyncOperation.update,
    registroId: _id,
    payload: ContratoAlumno.payloadForRemote({'id': _id, ...plan.updates}),
  );
}

Future<bool> _appAbierta() async {
  final r = await Process.run(
    'tasklist',
    ['/FI', 'IMAGENAME eq arguello_events.exe', '/NH'],
  );
  return (r.stdout as String).toLowerCase().contains('arguello_events.exe');
}

void main() {
  final apply = const String.fromEnvironment('APPLY') == '1';

  test('ESMAY: el pago de sillas del 25/06 vuelve a \$12.000', () async {
    sqfliteFfiInit();
    final home = Platform.environment['USERPROFILE'] ?? '';
    final sep = Platform.pathSeparator;
    final dbPath = '$home${sep}Documents${sep}Junior Eventos${sep}data.db';

    print('DB: $dbPath');
    print(apply ? 'Modo: APLICAR\n' : 'Modo: DRY-RUN (no escribe nada)\n');

    if (apply) {
      if (await _appAbierta()) {
        fail('La app está abierta. Cerrala (en esta PC) y volvé a correr.');
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final copia = '$dbPath.bak.esmay.$stamp';
      await File(dbPath).copy(copia);
      print('Copia: $copia\n');
    }

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: !apply),
    );
    try {
      final plan = apply
          ? await db.transaction((txn) async {
              final p = await _planificar(txn);
              await _aplicar(txn, p);
              return p;
            })
          : await _planificar(db);
      print('${plan.lineas.join('\n')}\n');
      print(apply
          ? 'Aplicado. Abrí la app y tocá "Subir pendientes": el contador tiene '
              'que quedar en 0.'
          : 'DRY-RUN OK: no se escribió nada.');
    } on _Freno catch (e) {
      fail('FRENO, no se escribió nada: $e');
    } finally {
      await db.close();
    }
  });
}
