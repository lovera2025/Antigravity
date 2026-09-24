// Corrige las mesas y sillas extra de 6 alumnos puntuales (CACERES no se toca).
// Plan: docs/CONTEXTO_v4.9.9-wip_2026-09-23.md, "PENDIENTE 1".
//
// Uso:
//   flutter test tool/corregir_extras_alumnos_test.dart                  (DRY-RUN)
//   flutter test tool/corregir_extras_alumnos_test.dart --dart-define=SOLO=mesas
//   flutter test tool/corregir_extras_alumnos_test.dart --dart-define=SOLO=sillas
//   ... --dart-define=APPLY=1   (escribe: con la app CERRADA y después de las 20 hs)
//
// Trabaja solo sobre la lista cerrada de ids de abajo; no recorre eventos.
// Calcula con las mismas funciones que la app (`recalcularSaldoDesdePagos` y
// `MesasExtraUtils.estadoMesasReconciliado`), y aborta SIN ESCRIBIR NADA si:
//   - un valor actual no es el que se revisó con el usuario;
//   - hay algo en la cola de subida para ese alumno o sus pagos;
//   - la reconciliación de mesas quisiera renombrar un pago;
//   - lo pagado de mesa o de sillas quedaría mayor que su precio;
//   - el total o el saldo no dan lo que se acordó.
// APPLY: copia de data.db, una sola transacción, UPDATE + encolado. Ningún DELETE.
// Después: abrir la app, "Subir pendientes" y comparar.

import 'dart:io';

import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/mesa_extra_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Un pago que se parte en dos: queda con [montoQueda] y nace uno nuevo de
/// [montoNuevo] con [conceptoNuevo], misma fecha, medio y sesión de caja.
class _PartirPago {
  final String pagoId;
  final String conceptoEsperado;
  final double montoEsperado;
  final double montoQueda;
  final double montoNuevo;

  const _PartirPago({
    required this.pagoId,
    required this.conceptoEsperado,
    required this.montoEsperado,
    required this.montoQueda,
    required this.montoNuevo,
  });
}

class _Correccion {
  final String id;
  final String nombre;
  final String grupo; // 'mesas' | 'sillas'
  final String cambio;

  /// Valores de hoy, revisados con el usuario. Si alguno no coincide, se frena.
  final Map<String, num> esperado;

  /// Columnas del contrato que se cambian a mano (el resto sale del recálculo).
  final Map<String, num> cambios;

  final double totalDespues;
  final double saldoDespues;
  final _PartirPago? partir;

  const _Correccion({
    required this.id,
    required this.nombre,
    required this.grupo,
    required this.cambio,
    required this.esperado,
    required this.cambios,
    required this.totalDespues,
    required this.saldoDespues,
    this.partir,
  });
}

// Orden acordado: primero los 3 de mesas, después Quiroz, Baldi y Esmay.
const _correcciones = <_Correccion>[
  _Correccion(
    id: '9544c706-81a2-4e85-89af-281f6322a1af',
    nombre: 'PONCE, AYELEN MILAGROS',
    grupo: 'mesas',
    cambio: 'mesas extra 1 → 2 (el precio total sigue en \$140.000)',
    esperado: {
      'monto_total_pactado': 410000,
      'saldo_deudor': 260000,
      'mesa_extra_precio': 140000,
      'mesa_extra_cantidad': 1,
      'mesa_extra_pagado': 60000,
      'sillas_extra_cantidad': 0,
      'sillas_extra_precio_total': 0,
    },
    cambios: {'mesa_extra_cantidad': 2},
    totalDespues: 410000,
    saldoDespues: 260000,
  ),
  _Correccion(
    id: 'fbbd5418-7c44-4099-be9c-78b07af6baec',
    nombre: 'SILVERO, MAXIMILIANO NAHUEL',
    grupo: 'mesas',
    cambio: 'mesas extra 1 → 2 (el precio total sigue en \$140.000)',
    esperado: {
      'monto_total_pactado': 455000,
      'saldo_deudor': 192500,
      'mesa_extra_precio': 140000,
      'mesa_extra_cantidad': 1,
      'mesa_extra_pagado': 87500,
      'sillas_extra_cantidad': 0,
      'sillas_extra_precio_total': 0,
    },
    cambios: {'mesa_extra_cantidad': 2},
    totalDespues: 455000,
    saldoDespues: 192500,
  ),
  _Correccion(
    id: '424c1630-73dd-4839-95e5-3b358e46b0f1',
    nombre: 'GONZALES, ALINA JAZMIN',
    grupo: 'mesas',
    cambio: 'mesas extra 1 → 2 (sus 2 sillas a \$8.000 ya están bien)',
    esperado: {
      'monto_total_pactado': 471000,
      'saldo_deudor': 236000,
      'mesa_extra_precio': 140000,
      'mesa_extra_cantidad': 1,
      'mesa_extra_pagado': 60000,
      'sillas_extra_cantidad': 2,
      'sillas_extra_precio_total': 16000,
    },
    cambios: {'mesa_extra_cantidad': 2},
    totalDespues: 471000,
    saldoDespues: 236000,
  ),
  _Correccion(
    id: '3199a441-cc45-41d0-af94-13b820b75ce9',
    nombre: 'QUIROZ MEZA, MATIAS NAHUEL',
    grupo: 'sillas',
    cambio: 'sillas 2 → 4 a \$8.000 (el total de sillas sigue en \$32.000)',
    esperado: {
      'monto_total_pactado': 372000,
      'saldo_deudor': 100000,
      'mesa_extra_precio': 70000,
      'mesa_extra_cantidad': 1,
      'sillas_extra_cantidad': 2,
      'sillas_extra_precio_total': 32000,
      'sillas_extra_pagado': 32000,
    },
    cambios: {'sillas_extra_cantidad': 4},
    totalDespues: 372000,
    saldoDespues: 100000,
  ),
  _Correccion(
    id: 'd5f01890-84f6-4d6e-be33-670e6e6aa348',
    nombre: 'BALDI, JUAN MARTIN',
    grupo: 'sillas',
    cambio: '1 silla de \$6.000 → \$8.000 (debe \$2.000 más)',
    esperado: {
      'monto_total_pactado': 391000,
      'saldo_deudor': 105000,
      'mesa_extra_precio': 70000,
      'mesa_extra_cantidad': 1,
      'sillas_extra_cantidad': 1,
      'sillas_extra_precio_total': 6000,
      'sillas_extra_pagado': 6000,
    },
    cambios: {
      'sillas_extra_precio_total': 8000,
      'monto_total_pactado': 393000,
    },
    totalDespues: 393000,
    saldoDespues: 107000,
  ),
  _Correccion(
    id: 'dd8af936-8880-4a50-8ee0-4de0086ce0e5',
    nombre: 'ESMAY, THIAGO',
    grupo: 'sillas',
    cambio: 'sillas 2 → 4 a \$8.000 (\$36.000 → \$32.000); los \$4.000 de más '
        'pasan a la cuota base partiendo el pago del 25-jun',
    esperado: {
      'monto_total_pactado': 421000,
      'saldo_deudor': 115000,
      'mesa_extra_precio': 70000,
      'mesa_extra_cantidad': 1,
      'sillas_extra_cantidad': 2,
      'sillas_extra_precio_total': 36000,
      'sillas_extra_pagado': 36000,
    },
    cambios: {
      'sillas_extra_cantidad': 4,
      'sillas_extra_precio_total': 32000,
      'monto_total_pactado': 417000,
    },
    totalDespues: 417000,
    saldoDespues: 111000,
    partir: _PartirPago(
      pagoId: 'e5f9473f-b9cf-4652-ad0c-b6d9a15ada56',
      conceptoEsperado: 'Sillas Extras - Entrega',
      montoEsperado: 12000,
      montoQueda: 8000,
      montoNuevo: 4000,
    ),
  ),
];

/// CACERES, ANAEL (b9fe4391-053a-4582-9758-5da1a7512150): NO SE TOCA. Su "2" de
/// sillas no tiene precio, no figura en su cuenta y la app ya no lo muestra.

class _Freno implements Exception {
  final String motivo;
  _Freno(this.motivo);
  @override
  String toString() => motivo;
}

/// Lo que se va a escribir para un alumno.
class _Plan {
  final _Correccion c;
  final Map<String, dynamic> antes;
  final Map<String, dynamic> updates; // solo columnas que cambian
  final Map<String, dynamic>? pagoPartido; // fila completa, ya con el monto nuevo
  final Map<String, dynamic>? pagoNuevo;
  final List<String> lineas;

  _Plan({
    required this.c,
    required this.antes,
    required this.updates,
    required this.pagoPartido,
    required this.pagoNuevo,
    required this.lineas,
  });
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

String _mesasTexto(List<MesaExtraItem> mesas) => mesas
    .map((m) => 'Mesa ${m.n}: ${_p(m.pagado)} de ${_p(m.precio)} '
        '(${m.cuotasPagadas} cuotas${m.liquidada ? ', paga' : ''})')
    .join(' · ');

Future<_Plan> _planificar(DatabaseExecutor db, _Correccion c) async {
  final rows = await db.query(
    'contratos_alumnos',
    where: 'id = ?',
    whereArgs: [c.id],
    limit: 1,
  );
  if (rows.isEmpty) throw _Freno('${c.nombre}: no está en la base local.');
  final row = rows.first;

  final nombre = (row['nombre_alumno'] as String? ?? '').trim();
  if (nombre.toUpperCase() != c.nombre.toUpperCase()) {
    throw _Freno('${c.id}: se esperaba "${c.nombre}" y es "$nombre".');
  }

  for (final e in c.esperado.entries) {
    if (!_igual(row[e.key], e.value)) {
      throw _Freno('${c.nombre}: ${e.key} es ${row[e.key]} y se revisó '
          '${e.value}. Algo cambió desde la revisión: no se toca.');
    }
  }

  final pagos = (await db.query(
    'pagos_contrato_alumno',
    where: 'contrato_alumno_id = ?',
    whereArgs: [c.id],
    orderBy: 'fecha_pago',
  ))
      .map((p) => Map<String, dynamic>.from(p))
      .toList();

  final idsEnJuego = [c.id, ...pagos.map((p) => p['id'] as String)];
  final enCola = await db.query(
    '_sync_queue',
    columns: ['tabla', 'registro_id'],
    where: 'registro_id IN (${List.filled(idsEnJuego.length, '?').join(',')})',
    whereArgs: idsEnJuego,
  );
  if (enCola.isNotEmpty) {
    throw _Freno('${c.nombre}: tiene ${enCola.length} cambio(s) sin subir '
        '(${enCola.map((e) => e['tabla']).toSet().join(', ')}). '
        'Primero "Subir pendientes".');
  }

  final contratoAntes = ContratoAlumno.fromJson(row);

  // La base de hoy tiene que cerrar con la misma cuenta que usa la app.
  final recAntes = _recalcular(contratoAntes, pagos);
  if (!_igual(recAntes.saldoDeudor, row['saldo_deudor'])) {
    throw _Freno('${c.nombre}: el saldo guardado (${row['saldo_deudor']}) no '
        'coincide con sus pagos (${recAntes.saldoDeudor}). No se toca.');
  }

  // Pago que se parte (solo ESMAY).
  Map<String, dynamic>? pagoPartido;
  Map<String, dynamic>? pagoNuevo;
  final pagosDespues = [for (final p in pagos) Map<String, dynamic>.from(p)];
  final partir = c.partir;
  if (partir != null) {
    final i = pagosDespues.indexWhere((p) => p['id'] == partir.pagoId);
    if (i < 0) throw _Freno('${c.nombre}: no está el pago ${partir.pagoId}.');
    final p = pagosDespues[i];
    if ((p['anulado'] as num? ?? 0) != 0 ||
        p['concepto'] != partir.conceptoEsperado ||
        !_igual(p['monto'], partir.montoEsperado) ||
        !_igual(p['monto_gross'], partir.montoEsperado)) {
      throw _Freno('${c.nombre}: el pago a partir no es el revisado '
          '(${p['concepto']} ${p['monto']}).');
    }
    if (!_igual(partir.montoQueda + partir.montoNuevo, partir.montoEsperado)) {
      throw _Freno('${c.nombre}: las dos partes no suman el pago original.');
    }
    final ahora = DateTime.now().toUtc().toIso8601String();
    p['monto'] = partir.montoQueda;
    p['monto_gross'] = partir.montoQueda;
    p['updated_at'] = ahora;
    pagoPartido = p;

    // Rótulo que usa la app para un abono de cuota base: la cuota a la que va
    // es la siguiente a las que ya están pagas.
    final cuotasBase = recAntes.cuotasBase;
    final total = contratoAntes.totalCuotas;
    pagoNuevo = {
      'id': UuidUtils.generate(),
      'contrato_alumno_id': c.id,
      'monto': partir.montoNuevo,
      'monto_gross': partir.montoNuevo,
      'descuento_porcentaje': p['descuento_porcentaje'] ?? 0.0,
      'concepto': rotuloEntregaParcial('Cuota Base (${cuotasBase + 1}/$total)'),
      'fecha_pago': p['fecha_pago'],
      'created_at': p['created_at'],
      'updated_at': ahora,
      'medio_pago': p['medio_pago'],
      'anulado': 0,
      if (p['sesion_caja_id'] != null) 'sesion_caja_id': p['sesion_caja_id'],
    };
    pagosDespues.add(pagoNuevo);
  }

  // Contrato con los cambios acordados.
  final rowDespues = Map<String, dynamic>.from(row)..addAll(c.cambios);
  final contratoDespues = ContratoAlumno.fromJson(rowDespues);
  final rec = _recalcular(contratoDespues, pagosDespues);

  // Lo mismo que hace recalcularProgresoContrato.
  final nuevos = <String, dynamic>{
    ...c.cambios,
    'cuotas_pagadas': rec.cuotasBase,
    'mesa_extra_cuotas_pagadas': rec.cuotasMesa,
    'sillas_extra_cuotas_pagadas': rec.cuotasSillas,
    'mesa_extra_pagado': rec.grossMesa,
    'sillas_extra_pagado': rec.grossSillas,
    'saldo_deudor': rec.saldoDeudor.clamp(0, double.infinity),
  };

  // Y lo que hace reconciliarMesasEstadoContrato, solo donde cambian las mesas.
  List<MesaExtraItem>? mesasAntes;
  List<MesaExtraItem>? mesasDespues;
  if (c.grupo == 'mesas') {
    if (MesasExtraUtils.inferirEntregasMesasColapsadas(
          c: contratoDespues,
          pagos: pagosDespues,
        ) !=
        null) {
      throw _Freno('${c.nombre}: la reconciliación quiere renombrar pagos.');
    }
    mesasAntes = MesasExtraUtils.estadoMesasReconciliado(
      contrato: contratoAntes,
      pagos: pagos,
    )!
        .mesas;
    final estado = MesasExtraUtils.estadoMesasReconciliado(
      contrato: contratoDespues,
      pagos: pagosDespues,
    )!;
    if (estado.cantidad != c.cambios['mesa_extra_cantidad']) {
      throw _Freno('${c.nombre}: la app calcularía ${estado.cantidad} mesas '
          'extra, no ${c.cambios['mesa_extra_cantidad']}.');
    }
    mesasDespues = estado.mesas;
    final pagadoMesas = MesasExtraUtils.totalPagado(estado.mesas);
    if (!_igual(pagadoMesas, rec.grossMesa)) {
      throw _Freno('${c.nombre}: el reparto por mesa (${_p(pagadoMesas)}) no '
          'suma lo pagado de mesa (${_p(rec.grossMesa)}): algo quedaría de más.');
    }
    nuevos['mesa_extra_cantidad'] = estado.cantidad;
    nuevos['mesas_extra_estado'] = MesaExtraItem.encodeList(estado.mesas);
    nuevos['mesa_extra_pagado'] = double.parse(pagadoMesas.toStringAsFixed(2));
    nuevos['mesa_extra_cuotas_pagadas'] =
        MesasExtraUtils.maxCuotasPagadas(estado.mesas);
  }

  // Frenos sobre el resultado.
  if (rec.grossMesa > contratoDespues.mesaExtraPrecio + 0.01) {
    throw _Freno('${c.nombre}: lo pagado de mesa quedaría mayor que su precio.');
  }
  if (rec.grossSillas > contratoDespues.sillasExtraPrecioTotal + 0.01) {
    throw _Freno('${c.nombre}: lo pagado de sillas (${_p(rec.grossSillas)}) '
        'quedaría mayor que su precio '
        '(${_p(contratoDespues.sillasExtraPrecioTotal)}).');
  }
  final maxSillas = 2 * (1 + contratoDespues.mesaExtraCantidad);
  if (contratoDespues.sillasExtraCantidad > maxSillas) {
    throw _Freno('${c.nombre}: ${contratoDespues.sillasExtraCantidad} sillas '
        'superan el máximo de $maxSillas.');
  }
  if (!_igual(contratoDespues.montoTotalPactado, c.totalDespues) ||
      !_igual(rec.saldoDeudor, c.saldoDespues)) {
    throw _Freno('${c.nombre}: total ${_p(contratoDespues.montoTotalPactado)} '
        '/ saldo ${_p(rec.saldoDeudor)}; se acordó ${_p(c.totalDespues)} / '
        '${_p(c.saldoDespues)}.');
  }
  final cuotaAntes = MoraCuotaCalculator.cuotaBaseDe(contratoAntes);
  final cuotaDespues = MoraCuotaCalculator.cuotaBaseDe(contratoDespues);
  if (!_igual(cuotaAntes, cuotaDespues)) {
    throw _Freno('${c.nombre}: la cuota base cambiaría '
        '(${_p(cuotaAntes)} → ${_p(cuotaDespues)}) y con ella la mora.');
  }

  final updates = <String, dynamic>{
    for (final e in nuevos.entries)
      if (!_igual(row[e.key], e.value)) e.key: e.value,
  };

  final lineas = <String>[
    '${c.nombre}  (${c.id})',
    '  ${c.cambio}',
    '  total ${_p(contratoAntes.montoTotalPactado)} → '
        '${_p(contratoDespues.montoTotalPactado)}   '
        'saldo ${_p(contratoAntes.saldoDeudor)} → ${_p(rec.saldoDeudor)}   '
        'cuota base ${_p(cuotaAntes)} (igual: la mora no cambia)',
    for (final e in updates.entries)
      if (e.key != 'mesas_extra_estado')
        '    ${e.key}: ${row[e.key]} → ${e.value}',
    if (mesasAntes != null) '    por mesa antes:   ${_mesasTexto(mesasAntes)}',
    if (mesasDespues != null)
      '    por mesa después: ${_mesasTexto(mesasDespues)}',
    if (pagoPartido != null)
      '    pago ${pagoPartido['id']} "${pagoPartido['concepto']}" '
          '${pagoPartido['fecha_pago']}: ${_p(partir!.montoEsperado)} → '
          '${_p(partir.montoQueda)}',
    if (pagoNuevo != null)
      '    pago NUEVO "${pagoNuevo['concepto']}" ${_p(partir!.montoNuevo)}, '
          'misma fecha (${pagoNuevo['fecha_pago']}), medio '
          '${pagoNuevo['medio_pago']}, sesión ${pagoNuevo['sesion_caja_id'] ?? '—'}',
    if (pagoPartido != null)
      '    cobrado ese día: ${_p(partir!.montoEsperado)} antes, '
          '${_p(partir.montoQueda + partir.montoNuevo)} después (la caja no cambia)',
  ];

  return _Plan(
    c: c,
    antes: row,
    updates: updates,
    pagoPartido: pagoPartido,
    pagoNuevo: pagoNuevo,
    lineas: lineas,
  );
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

Future<void> _aplicar(DatabaseExecutor txn, _Plan plan) async {
  final id = plan.c.id;
  final ahora = DateTime.now().toUtc().toIso8601String();

  if (plan.pagoPartido != null) {
    final p = plan.pagoPartido!;
    final n = await txn.update(
      'pagos_contrato_alumno',
      {
        'monto': p['monto'],
        'monto_gross': p['monto_gross'],
        'updated_at': p['updated_at'],
      },
      where: 'id = ?',
      whereArgs: [p['id']],
    );
    if (n != 1) throw _Freno('${plan.c.nombre}: no se pudo partir el pago.');
    await SyncQueue.enqueue(
      executor: txn,
      tabla: 'pagos_contrato_alumno',
      operacion: SyncOperation.update,
      registroId: p['id'] as String,
      payload: Map<String, dynamic>.from(p)..remove('line_kind'),
    );
  }
  if (plan.pagoNuevo != null) {
    final p = plan.pagoNuevo!;
    await txn.insert('pagos_contrato_alumno', p);
    await SyncQueue.enqueue(
      executor: txn,
      tabla: 'pagos_contrato_alumno',
      operacion: SyncOperation.insert,
      registroId: p['id'] as String,
      payload: Map<String, dynamic>.from(p)..remove('line_kind'),
    );
  }

  if (plan.updates.isEmpty) return;
  final n = await txn.update(
    'contratos_alumnos',
    {...plan.updates, 'updated_at': ahora},
    where: 'id = ?',
    whereArgs: [id],
  );
  if (n != 1) throw _Freno('${plan.c.nombre}: no se pudo actualizar.');
  await SyncQueue.enqueue(
    executor: txn,
    tabla: 'contratos_alumnos',
    operacion: SyncOperation.update,
    registroId: id,
    payload: ContratoAlumno.payloadForRemote({'id': id, ...plan.updates}),
  );
}

Future<int> _contarCola(DatabaseExecutor db) async {
  final r = await db.rawQuery('SELECT COUNT(*) AS n FROM _sync_queue');
  return (r.first['n'] as num?)?.toInt() ?? 0;
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
  final solo = const String.fromEnvironment('SOLO');

  test('corregir mesas y sillas extra de alumnos puntuales', () async {
    sqfliteFfiInit();
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final sep = Platform.pathSeparator;
    final dbPath = '$home${sep}Documents${sep}Junior Eventos${sep}data.db';

    final lista = _correcciones
        .where((c) => solo.isEmpty || c.grupo == solo)
        .toList();
    expect(lista, isNotEmpty, reason: 'SOLO=$solo no coincide con nadie');

    // ignore: avoid_print
    print('DB: $dbPath');
    // ignore: avoid_print
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
      final copia = '$dbPath.bak.extras.$stamp';
      await File(dbPath).copy(copia);
      // ignore: avoid_print
      print('Copia: $copia\n');
    }

    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(readOnly: !apply),
    );
    try {
      final colaAntes = await _contarCola(db);

      List<_Plan> planes;
      if (apply) {
        planes = await db.transaction((txn) async {
          final out = <_Plan>[];
          for (final c in lista) {
            final plan = await _planificar(txn, c);
            await _aplicar(txn, plan);
            out.add(plan);
          }
          return out;
        });
      } else {
        planes = [for (final c in lista) await _planificar(db, c)];
      }

      for (final plan in planes) {
        // ignore: avoid_print
        print('${plan.lineas.join('\n')}\n');
      }

      final colaDespues = await _contarCola(db);
      // ignore: avoid_print
      print('Cola de subida: $colaAntes → $colaDespues');
      // ignore: avoid_print
      print(apply
          ? '\nAplicado. Abrí la app y tocá "Subir pendientes": el contador '
              'tiene que quedar en 0.'
          : '\nDRY-RUN OK: no se escribió nada. CACERES no se toca.');
    } on _Freno catch (e) {
      fail('FRENO, no se escribió nada: $e');
    } finally {
      await db.close();
    }
  });
}
