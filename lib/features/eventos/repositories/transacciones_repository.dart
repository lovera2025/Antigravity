import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/transaccion.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/ar_time.dart';
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
    String? medioPago,
    DateTime? fechaPago,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    // Sello temporal ESTRICTO: instante UTC preciso. La presentación al
    // usuario se realiza vía ArTime en huso America/Argentina/Buenos_Aires.
    final now = fechaPago?.toUtc().toIso8601String() ?? ArTime.nowUtcIso();

    final data = {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'concepto': concepto,
      'fecha_pago': now,
      'created_by': createdBy,
      'medio_pago': medioPago,
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

  /// Quita la(s) transacción(es) de bonificación global (reemplazo al cambiar el %).
  Future<void> eliminarBonificacionesGlobales(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'transacciones',
      columns: ['id'],
      where: 'evento_id = ? AND concepto IS NOT NULL AND instr(concepto, ?) = 1',
      whereArgs: [eventoId, kConceptoBonificacionGlobalPrefix],
    );
    for (final r in rows) {
      final id = r['id'] as String;
      await db.delete('transacciones', where: 'id = ?', whereArgs: [id]);
      await SyncQueue.enqueue(
        tabla: 'transacciones',
        operacion: SyncOperation.delete,
        registroId: id,
        payload: {'id': id},
      );
    }
  }

  /// Una sola bonificación global: [presupuestoTotal] × [porcentaje]/100. Si [porcentaje] ≤ 0, solo elimina la anterior.
  Future<void> aplicarBonificacionGlobal({
    required String eventoId,
    required double presupuestoTotal,
    required double porcentaje,
  }) async {
    await eliminarBonificacionesGlobales(eventoId);
    if (porcentaje <= 0.001 || presupuestoTotal <= 0) return;
    final monto = presupuestoTotal * (porcentaje / 100.0);
    if (monto <= 0.01) return;
    final pctStr = porcentaje == porcentaje.roundToDouble()
        ? porcentaje.toInt().toString()
        : porcentaje.toStringAsFixed(2);
    await registrarPago(
      eventoId: eventoId,
      monto: monto,
      concepto: '$kConceptoBonificacionGlobalPrefix$pctStr% sobre presupuesto total)',
    );
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
          'medio_pago': row['medio_pago'],
          'anulado': row['anulado'] ?? 0,
          'motivo_anulacion': row['motivo_anulacion'],
          'fecha_anulacion': row['fecha_anulacion'],
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
