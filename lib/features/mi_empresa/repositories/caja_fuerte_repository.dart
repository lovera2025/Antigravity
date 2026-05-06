import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/database/sync_queue.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_engine.dart';
import '../../../../core/utils/ar_time.dart';
import '../../../../core/utils/uuid_utils.dart';
import '../../../../models/caja_fuerte_movimiento.dart';

class CajaFuerteRepository {
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  CajaFuerteRepository(this._connectivity, this._syncEngine);

  Future<List<CajaFuerteMovimiento>> listarOrdenDesc() async {
    final db = await LocalDatabase.instance;
    final maps = await db.query(
      'caja_fuerte_movimientos',
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => CajaFuerteMovimiento.fromJson(m)).toList();
  }

  /// Saldo actual: suma asignaciones − suma retiros (montos siempre positivos en DB).
  Future<double> saldoActual() async {
    final lista = await listarOrdenDesc();
    var s = 0.0;
    for (final m in lista) {
      if (m.esAsignacion) {
        s += m.monto;
      } else {
        s -= m.monto;
      }
    }
    return s;
  }

  Future<void> insertar({
    required String tipo,
    required double monto,
    String? nota,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a 0');
    }
    final tipoNorm = tipo == CajaFuerteMovimiento.tipoAsignacion
        ? CajaFuerteMovimiento.tipoAsignacion
        : CajaFuerteMovimiento.tipoRetiro;

    final id = UuidUtils.generate();
    final data = <String, dynamic>{
      'id': id,
      'tipo': tipoNorm,
      'monto': monto,
      'nota': nota?.trim().isEmpty == true ? null : nota?.trim(),
      'created_at': ArTime.nowUtcIso(),
    };
    final db = await LocalDatabase.instance;
    await db.insert('caja_fuerte_movimientos', data);

    await SyncQueue.enqueue(
      tabla: 'caja_fuerte_movimientos',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }

    debugPrint('📥 Caja fuerte: insert $tipoNorm $monto (encolado sync)');
  }

  /// Última asignación por fecha (no retiro): para umbrales de advertencia.
  Future<double?> montoUltimaAsignacion() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'caja_fuerte_movimientos',
      where: 'tipo = ?',
      whereArgs: [CajaFuerteMovimiento.tipoAsignacion],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['monto'] as num?)?.toDouble();
  }
}

final cajaFuerteRepositoryProvider = Provider<CajaFuerteRepository>((ref) {
  return CajaFuerteRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
