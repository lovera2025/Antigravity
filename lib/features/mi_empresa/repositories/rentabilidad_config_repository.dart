import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/local_database.dart';
import '../../../../core/database/sync_queue.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/services/sync_engine.dart';
import '../../../../models/rentabilidad_config.dart';

class RentabilidadConfigRepository {
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  /// UUID estable y compartido entre todas las PCs para el único registro
  /// de configuración. Permite que el upsert remoto sea idempotente y
  /// pasa la validación de UUID del [SyncEngine] (vs. el `'default'` legacy).
  static const String singletonId = '00000000-0000-4000-8000-000000000001';

  RentabilidadConfigRepository(this._connectivity, this._syncEngine);

  Future<RentabilidadConfig> getConfig() async {
    try {
      final db = await LocalDatabase.instance;
      final res = await db.query('rentabilidad_config', limit: 1);
      if (res.isNotEmpty) {
        return RentabilidadConfig.fromJson(res.first);
      }
      return RentabilidadConfig.defaultConfig();
    } catch (e) {
      debugPrint('Error obteniendo config de rentabilidad: $e');
      return RentabilidadConfig.defaultConfig();
    }
  }

  /// Guarda la configuración localmente y la encola para que el SyncEngine
  /// la propague a las demás PCs (antes era 100% local).
  Future<void> saveConfig(RentabilidadConfig config) async {
    try {
      final db = await LocalDatabase.instance;
      // Promovemos el id legacy `'default'` a un UUID v4 fijo y compartido.
      final effectiveId =
          (config.id.length == 36) ? config.id : singletonId;
      final map = config.toJson();
      map['id'] = effectiveId;

      // Si quedaron filas con id legacy, las reemplazamos por la canónica.
      await db.delete('rentabilidad_config', where: "id != ?", whereArgs: [effectiveId]);
      await db.insert(
        'rentabilidad_config',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await SyncQueue.enqueue(
        tabla: 'rentabilidad_config',
        operacion: SyncOperation.insert,
        registroId: effectiveId,
        payload: map,
      );

    } catch (e) {
      debugPrint('Error guardando config de rentabilidad: $e');
      rethrow;
    }
  }
}

final rentabilidadConfigRepositoryProvider = Provider<RentabilidadConfigRepository>((ref) {
  return RentabilidadConfigRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
