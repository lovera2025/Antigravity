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
          'clientes': {'nombre_completo': row['cliente_nombre']},
        },
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
  }

  /// Registra un egreso sin `evento_id` (SQLite + sync), p. ej. gasto empresa, retiro dueño o gasto personal desde bolsillo.
  Future<void> registrarEgresoSinEvento({
    required double monto,
    required String proveedor,
    required String categoria,
    DateTime? fecha,
    String? medioPago,
    String? sesionCajaId,
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
      'sesion_caja_id': sesionCajaId,
      'updated_at': now,
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
  }

  /// Actualiza campos de un egreso existente (offline-first).
  Future<void> actualizarEgreso({
    required String id,
    String? categoria,
    String? proveedor,
    String? medioPago,
    double? monto,
  }) async {
    if (id.isEmpty || id.length != 36) {
      debugPrint('🚫 actualizarEgreso: id inválido');
      return;
    }
    final db = await LocalDatabase.instance;
    final updates = <String, dynamic>{};
    if (categoria != null) updates['categoria'] = categoria;
    if (proveedor != null) updates['proveedor'] = proveedor.trim();
    if (medioPago != null) updates['medio_pago'] = medioPago;
    if (monto != null) updates['monto'] = monto;
    if (updates.isEmpty) return;
    updates['updated_at'] = ArTime.nowUtcIso();

    await db.update('egresos', updates, where: 'id = ?', whereArgs: [id]);

    final fullRow = await db.query('egresos', where: 'id = ?', whereArgs: [id]);
    final payload = fullRow.isNotEmpty
        ? Map<String, dynamic>.from(fullRow.first)
        : {'id': id, ...updates};

    await SyncQueue.enqueue(
      tabla: 'egresos',
      operacion: SyncOperation.update,
      registroId: id,
      payload: payload,
    );
  }

  /// Elimina un egreso en SQLite y encola sync.
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
  }

  /// Escucha cambios en la tabla de egresos para refrescar UI.
  RealtimeChannel subscribeToChanges(void Function() onUpdate) {
    // Sigue usando Supabase Realtime para cambios remotos
    final channel = _supabase.channel('public:egresos_repo_changes');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'egresos',
          callback: (_) => onUpdate(),
        )
        .subscribe();
    return channel;
  }
}

final egresosRepositoryProvider = Provider<EgresosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return EgresosRepository(supabase, connectivity);
});
