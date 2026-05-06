import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../models/obligacion_pago.dart';
import '../../../../core/database/local_database.dart';
import '../../../../core/database/sync_queue.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_engine.dart';

class ObligacionesRepository {
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  ObligacionesRepository(this._connectivity, this._syncEngine);

  Future<void> guardarObligacion(ObligacionPago obligacion) async {
    final db = await LocalDatabase.instance;
    final data = obligacion.toJson();
    await db.insert(
      'obligaciones_pago',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await SyncQueue.enqueue(
      tabla: 'obligaciones_pago',
      operacion: SyncOperation.insert,
      registroId: obligacion.id,
      payload: data,
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  Future<void> eliminarObligacion(String id) async {
    final db = await LocalDatabase.instance;
    await db.delete('obligaciones_pago', where: 'id = ?', whereArgs: [id]);

    await SyncQueue.enqueue(
      tabla: 'obligaciones_pago',
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {},
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  /// Lectura puramente local: el SyncEngine es el responsable de mantener
  /// `obligaciones_pago` actualizada vía `_pullFromCloud`. Esto evita un
  /// roundtrip a Supabase por cada apertura de la pantalla de Avisos.
  Future<List<ObligacionPago>> getObligaciones() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('obligaciones_pago', orderBy: 'fecha_vencimiento ASC');
    return rows.map((r) => ObligacionPago.fromJson(r)).toList();
  }
}

final obligacionesRepositoryProvider = Provider<ObligacionesRepository>((ref) {
  return ObligacionesRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
