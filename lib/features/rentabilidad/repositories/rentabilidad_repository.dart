import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/calculo_rentabilidad.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';

class RentabilidadRepository {
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  RentabilidadRepository(this._connectivity, this._syncEngine);

  Future<void> guardarCalculo(CalculoRentabilidad calculo) async {
    final db = await LocalDatabase.instance;
    final data = calculo.toJson();
    await db.insert('calculos_rentabilidad', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(
      tabla: 'calculos_rentabilidad', 
      operacion: SyncOperation.insert, 
      registroId: calculo.id, 
      payload: data
    );
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  /// Lectura puramente local — la tabla `calculos_rentabilidad` se sincroniza vía SyncEngine.
  /// (`_pullFromCloud` la incluye con orden por `created_at DESC`.)
  Future<List<CalculoRentabilidad>> getHistorial({String? eventoId, String? presupuestoId}) async {
    final db = await LocalDatabase.instance;
    String where = '';
    List<dynamic> args = [];
    if (eventoId != null) {
      where = 'evento_id = ?';
      args.add(eventoId);
    } else if (presupuestoId != null) {
      where = 'presupuesto_id = ?';
      args.add(presupuestoId);
    }

    final query = where.isEmpty ? null : where;
    final bindings = args.isEmpty ? null : args;

    final rows = await db.query(
      'calculos_rentabilidad',
      where: query,
      whereArgs: bindings,
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => CalculoRentabilidad.fromJson(r)).toList();
  }
}

final rentabilidadRepositoryProvider = Provider<RentabilidadRepository>((ref) {
  return RentabilidadRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
