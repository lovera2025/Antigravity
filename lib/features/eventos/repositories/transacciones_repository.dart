import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/transaccion.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/uuid_utils.dart';

/// Repositorio de Transacciones (Ingresos) — Offline-First.
class TransaccionesRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  TransaccionesRepository(this._supabase, this._connectivity);

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// Transacciones de un evento.
  Future<List<Transaccion>> getByEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('transacciones',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'fecha_pago DESC',
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      await _pullByEvento(db, eventoId, prune: true);
      final freshRows = await db.query('transacciones',
        where: 'evento_id = ?', whereArgs: [eventoId], orderBy: 'fecha_pago DESC');
      return freshRows.map((r) => Transaccion.fromJson(r)).toList();
    }

    return rows.map((r) => Transaccion.fromJson(r)).toList();
  }

  /// Todas las transacciones (para dashboard).
  Future<List<Transaccion>> getAll() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('transacciones', orderBy: 'fecha_pago DESC');
    return rows.map((r) => Transaccion.fromJson(r)).toList();
  }

  // ── ESCRITURA ─────────────────────────────────────────────────────────────

  /// Registra un pago (transacción).
  Future<String> registrarPago({
    required String eventoId,
    required double monto,
    String? concepto,
    String? createdBy,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();

    final data = {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'concepto': concepto,
      'fecha_pago': now,
      'created_by': createdBy,
    };

    await db.insert('transacciones', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(
      tabla: 'transacciones',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    /*
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data, id);
    }
    */

    debugPrint('✅ Transacción registrada localmente: $id');
    return id;
  }

  // ── SYNC & REALTIME ────────────────────────────────────────────────────────
  
  /// Escucha cambios en tiempo real para transacciones de un evento.
  RealtimeChannel subscribeToChanges(String eventoId, void Function() onUpdate) {
    debugPrint('🔔 Suscribiendo a transacciones en tiempo real para evento: $eventoId');
    final channel = _supabase.channel('public:transacciones_$eventoId');
    
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'transacciones',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'evento_id',
        value: eventoId,
      ),
      callback: (payload) {
        debugPrint('🔔 Realtime: Cambio detectado en transacciones');
        onUpdate();
      },
    );

    channel.subscribe();
    return channel;
  }

  Future<void> _pullByEvento(Database db, String eventoId, {bool prune = false}) async {
    try {
      final response = await _supabase.from('transacciones')
          .select()
          .eq('evento_id', eventoId)
          .order('fecha_pago', ascending: false);

      final List<dynamic> list = response as List;
      final cloudIds = list.map((r) => r['id'] as String).toSet();

      // IDs con cambios locales pendientes
      final pendingRows = await db.query('_sync_queue', 
        columns: ['registro_id'], 
        where: "tabla = 'transacciones'");
      final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

      if (prune) {
        // 1. Obtener IDs locales para este evento
        final localRows = await db.query('transacciones', 
          columns: ['id'], 
          where: 'evento_id = ?', 
          whereArgs: [eventoId]
        );
        final localIds = localRows.map((r) => r['id'] as String).toList();

        // 2. Identificar huérfanos (están local, no en cloud)
        final orphans = localIds.where((id) => !cloudIds.contains(id)).toList();

        if (orphans.isNotEmpty) {
          // 3. Filtrar los que están en la cola de sincronización (todavía no subieron)
          final List<String> toDelete = [];
          for (final id in orphans) {
            final inQueue = await db.query('_sync_queue', 
              where: "tabla = 'transacciones' AND registro_id = ?", 
              whereArgs: [id]
            );
            if (inQueue.isEmpty) {
              toDelete.add(id);
            }
          }

          if (toDelete.isNotEmpty) {
            debugPrint('🧹 Purgando ${toDelete.length} transacciones eliminadas en cloud...');
            await db.delete('transacciones', 
              where: "id IN (${toDelete.map((_) => '?').join(',')})", 
              whereArgs: toDelete
            );
          }
        }
      }

      final batch = db.batch();
      for (final row in list) {
        final id = row['id'] as String;
        // ROBUSTEZ: No sobrescribir cambios locales pendientes
        if (pendingIds.contains(id)) continue;

        batch.insert('transacciones', {
          'id': row['id'],
          'evento_id': row['evento_id'],
          'monto': row['monto'],
          'concepto': row['concepto'],
          'fecha_pago': row['fecha_pago'],
          'created_by': row['created_by'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull transacciones: $e');
    }
  }



}

// ── Provider ────────────────────────────────────────────────────────────────

final transaccionesRepositoryProvider = Provider<TransaccionesRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return TransaccionesRepository(supabase, connectivity);
});
