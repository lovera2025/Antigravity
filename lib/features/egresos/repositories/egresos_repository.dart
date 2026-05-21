import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../main.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';

class EgresosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  EgresosRepository(this._supabase, this._connectivity);

  /// Obtiene todos los egresos con información de eventos y clientes desde SQLite.
  Future<List<Map<String, dynamic>>> getEgresosConEvento() async {
    final db = await LocalDatabase.instance;
    
    // JOIN SQL para traer datos complementarios offline
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        e.*, 
        ev.tipo as evento_tipo, 
        c.nombre_completo as cliente_nombre 
      FROM egresos e
      LEFT JOIN eventos ev ON e.evento_id = ev.id
      LEFT JOIN clientes c ON ev.cliente_id = c.id
      ORDER BY e.fecha DESC
    ''');
    
    // Transformar al formato esperado por la UI (evitando romper el resto del código)
    // Supabase devuelve el objeto join anidado, lo emulamos aquí.
    return maps.map((row) {
      return {
        ...row,
        'eventos': {
          'id': row['evento_id'],
          'tipo': row['evento_tipo'],
          'clientes': {
            'nombre_completo': row['cliente_nombre']
          }
        }
      };
    }).toList();
  }

  /// Registra un nuevo gasto vinculado a un evento (Offline-first).
  Future<void> registrarEgreso({
    required String eventoId,
    required double monto,
    required String proveedor,
    required String categoria,
    DateTime? fecha,
    String? medioPago,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    // Instante preciso del egreso en UTC. La UI/PDF lo muestran en huso AR.
    final now = (fecha?.toUtc() ?? ArTime.nowUtc()).toIso8601String();

    final data = {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'proveedor': proveedor.trim(),
      'categoria': categoria,
      'fecha': now,
      'created_by': _supabase.auth.currentUser?.id,
      'medio_pago': medioPago,
    };

    // 1. Guardar localmente
    await db.insert('egresos', data);

    // 2. Encolar para sincronización
    await SyncQueue.enqueue(
      tabla: 'egresos',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    // 3. Intento de sincronización inmediata si hay red
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data);
    }
  }

  void _syncImmediately(Map<String, dynamic> data) {
    Future.microtask(() async {
      try {
        await _supabase.from('egresos').upsert(data);
        final db = await LocalDatabase.instance;
        await db.delete('_sync_queue', 
          where: 'tabla = ? AND registro_id = ?', 
          whereArgs: ['egresos', data['id']]
        );
      } catch (e) {
        debugPrint('⚠️ Sync egreso fallido: $e');
      }
    });
  }

  /// Registra un egreso sin `evento_id` (SQLite + sync), p. ej. gasto empresa, retiro dueño o gasto personal desde bolsillo.
  Future<void> registrarEgresoSinEvento({
    required double monto,
    required String proveedor,
    required String categoria,
    DateTime? fecha,
    String? medioPago,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    // Instante preciso del egreso sin evento (UTC).
    final now = (fecha?.toUtc() ?? ArTime.nowUtc()).toIso8601String();

    final data = <String, dynamic>{
      'id': id,
      'monto': monto,
      'proveedor': proveedor.trim(),
      'categoria': categoria,
      'fecha': now,
      'created_by': _supabase.auth.currentUser?.id,
      'medio_pago': medioPago,
    };

    // 1. Guardar localmente (sin evento_id)
    await db.insert('egresos', data);

    // 2. Encolar para sincronización
    await SyncQueue.enqueue(
      tabla: 'egresos',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    // 3. Intento de sincronización inmediata si hay red
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data);
    }
  }

  /// Elimina un egreso en SQLite y en la nube (offline-first).
  Future<void> eliminarEgreso(String id) async {
    if (id.isEmpty || id.length != 36) {
      debugPrint('🚫 eliminarEgreso: id inválido');
      return;
    }
    final db = await LocalDatabase.instance;
    await db.delete('egresos', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: 'egresos',
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {'id': id},
    );
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncDeleteImmediately(id);
    }
  }

  void _syncDeleteImmediately(String id) {
    Future.microtask(() async {
      try {
        await _supabase.from('egresos').delete().eq('id', id);
        final db = await LocalDatabase.instance;
        await db.delete(
          '_sync_queue',
          where: 'tabla = ? AND registro_id = ?',
          whereArgs: ['egresos', id],
        );
      } catch (e) {
        debugPrint('⚠️ Sync delete egreso fallido: $e');
      }
    });
  }

  /// Escucha cambios en la tabla de egresos para refrescar UI.
  RealtimeChannel subscribeToChanges(void Function() onUpdate) {
    // Sigue usando Supabase Realtime para cambios remotos
    final channel = _supabase.channel('public:egresos_repo_changes');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'egresos',
      callback: (_) => onUpdate(),
    ).subscribe();
    return channel;
  }
}

final egresosRepositoryProvider = Provider<EgresosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return EgresosRepository(supabase, connectivity);
});
