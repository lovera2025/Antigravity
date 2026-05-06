import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/cliente.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/uuid_utils.dart';

/// Repositorio de Clientes — Offline-First.
///
/// Lee siempre de SQLite local (velocidad instantánea).
/// Escribe en SQLite + encola sync a Supabase.
/// Cuando hay conexión, sincroniza en segundo plano.
class ClientesRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  ClientesRepository(this._supabase, this._connectivity);

  // ── LECTURA (SQLite local) ────────────────────────────────────────────────

  /// Obtiene los clientes desde SQLite, filtrando por estado (activo/archivado).
  Future<List<Cliente>> getAll({bool archived = false}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'clientes', 
      where: 'is_archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'nombre_completo ASC'
    );
    
    if (rows.isEmpty && !archived && _connectivity.currentStatus == AppConnectivity.online) {
      // Primera carga: pull de la nube
      await _pullFromCloud(db);
      final freshRows = await db.query(
        'clientes', 
        where: 'is_archived = ?',
        whereArgs: [0],
        orderBy: 'nombre_completo ASC'
      );
      return freshRows.map((r) => Cliente.fromJson(r)).toList();
    }
    
    return rows.map((r) => Cliente.fromJson(r)).toList();
  }

  /// Obtiene un cliente por ID desde SQLite.
  Future<Cliente?> getById(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('clientes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Cliente.fromJson(rows.first);
  }

  /// Obtiene estadísticas rápidas para etiquetas inteligentes.
  Future<Map<String, dynamic>> getStats(String clienteId) async {
    final db = await LocalDatabase.instance;
    
    // Contar eventos totales (para VIP)
    final eventosCountResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM eventos WHERE cliente_id = ?', [clienteId]
    );
    final eventosCount = (eventosCountResult.isNotEmpty ? eventosCountResult.first['count'] as int? : 0) ?? 0;
    
    // Verificar si hay saldos pendientes (para etiqueta SALDO)
    // Buscamos en contratos_alumnos vinculados a los eventos de este cliente
    final saldoDeudorResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM contratos_alumnos 
      WHERE evento_id IN (SELECT id FROM eventos WHERE cliente_id = ?) 
      AND saldo_deudor > 0
      ''', [clienteId]
    );
    final saldoDeudor = (saldoDeudorResult.isNotEmpty ? saldoDeudorResult.first['count'] as int? : 0) ?? 0;

    return {
      'total_eventos': eventosCount,
      'tiene_deuda': saldoDeudor > 0,
    };
  }

  /// Obtiene la inversión total de un cliente (suma de presupuestos confirmados o contratos).
  Future<double> getInversionTotal(String clienteId) async {
    final db = await LocalDatabase.instance;
    
    // Suma de montos en contratos_alumnos vinculados a este cliente
    final result = await db.rawQuery(
      '''
      SELECT SUM(monto_total_pactado) as total FROM contratos_alumnos 
      WHERE evento_id IN (SELECT id FROM eventos WHERE cliente_id = ?)
      ''', [clienteId]
    );
    
    final total = (result.isNotEmpty ? result.first['total'] as double? : 0.0) ?? 0.0;
    return total;
  }

  /// Cuenta cuántos clientes están archivados.
  Future<int> getArchivedCount() async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM clientes WHERE is_archived = 1');
    return (result.isNotEmpty ? result.first['count'] as int? : 0) ?? 0;
  }

  // ── ESCRITURA (SQLite + Sync Queue) ───────────────────────────────────────

  /// Crea un nuevo cliente. Escribe en SQLite y encola sync a la nube.
  Future<String> crear({
    required String nombreCompleto,
    String? telefono,
    String? email,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();

    final data = {
      'id': id,
      'nombre_completo': nombreCompleto,
      'telefono': telefono,
      'email': email,
      'created_at': now,
    };

    // Escritura local inmediata
    await db.insert('clientes', data, conflictAlgorithm: ConflictAlgorithm.replace);

    // Encolar para sincronización
    await SyncQueue.enqueue(
      tabla: 'clientes',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );

    // Si hay conexión, intentar subir de inmediato
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data, SyncOperation.insert, id);
    }

    debugPrint('✅ Cliente creado localmente: $id');
    return id;
  }

  /// Actualiza un cliente existente.
  Future<void> actualizar({
    required String id,
    required String nombreCompleto,
    String? telefono,
    String? email,
  }) async {
    final db = await LocalDatabase.instance;

    final data = {
      'nombre_completo': nombreCompleto,
      'telefono': telefono,
      'email': email,
    };

    // Update local
    await db.update('clientes', data, where: 'id = ?', whereArgs: [id]);

    // Encolar sync
    await SyncQueue.enqueue(
      tabla: 'clientes',
      operacion: SyncOperation.update,
      registroId: id,
      payload: {...data, 'id': id},
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data, SyncOperation.update, id);
    }

    debugPrint('✅ Cliente actualizado localmente: $id');
  }

  /// Archiva un cliente (o cambia su estado de archivado).
  Future<void> setArchived(String id, bool archived) async {
    final db = await LocalDatabase.instance;
    final data = {'is_archived': archived ? 1 : 0};

    // Update local
    await db.update('clientes', data, where: 'id = ?', whereArgs: [id]);

    // Encolar sync
    await SyncQueue.enqueue(
      tabla: 'clientes',
      operacion: SyncOperation.update,
      registroId: id,
      payload: {...data, 'id': id},
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately(data, SyncOperation.update, id);
    }

    debugPrint('✅ Cliente ${archived ? "archivado" : "desarchivado"} localmente: $id');
  }

  /// Elimina definitivamente un cliente y todos sus datos asociados.
  Future<void> eliminarDefinitivamente(String id) async {
    final db = await LocalDatabase.instance;

    // Delete local
    await db.delete('clientes', where: 'id = ?', whereArgs: [id]);

    // Encolar sync
    await SyncQueue.enqueue(
      tabla: 'clientes',
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {'id': id},
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncImmediately({'id': id}, SyncOperation.delete, id);
    }

    debugPrint('✅ Cliente eliminado definitivamente localmente: $id');
  }

  /// Elimina un cliente. (Por defecto ahora solo archiva por seguridad)
  /// Si se desea borrar todo, usar [eliminarDefinitivamente].
  Future<void> eliminar(String id) async {
    await setArchived(id, true);
  }

  // ── SYNC ──────────────────────────────────────────────────────────────────

  /// Pull de clientes desde Supabase → SQLite.
  Future<void> _pullFromCloud(Database db) async {
    try {
      final response = await _supabase
          .from('clientes')
          .select('*')
          .order('nombre_completo', ascending: true);

      final batch = db.batch();
      for (final row in (response as List)) {
        batch.insert('clientes', {
          'id': row['id'],
          'nombre_completo': row['nombre_completo'],
          'telefono': row['telefono'],
          'email': row['email'],
          'is_archived': row['is_archived'] ?? 0,
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      debugPrint('📥 Clientes: ${response.length} sincronizados desde la nube');
    } catch (e) {
      debugPrint('⚠️ Error pull clientes: $e');
    }
  }

  /// Garantiza que el cliente exista en Supabase antes de crear FKs (p. ej. préstamos).
  /// Devuelve false si no hay red, no hay fila local, o falla el upsert.
  Future<bool> ensureClienteEnNube(String clienteId) async {
    if (_connectivity.currentStatus != AppConnectivity.online) return false;
    final db = await LocalDatabase.instance;
    final rows = await db.query('clientes', where: 'id = ?', whereArgs: [clienteId]);
    if (rows.isEmpty) return false;
    final r = rows.first;
    final payload = <String, dynamic>{
      'id': r['id'],
      'nombre_completo': r['nombre_completo'],
      'telefono': r['telefono'],
      'email': r['email'],
      'is_archived': r['is_archived'] ?? 0,
      'created_at': r['created_at'],
    };
    try {
      await _supabase.from('clientes').upsert(payload);
      await _removeFromQueue(clienteId);
      debugPrint('☁️ Cliente asegurado en nube (FK): $clienteId');
      return true;
    } catch (e) {
      debugPrint('⚠️ ensureClienteEnNube falló: $e');
      return false;
    }
  }

  /// Intenta sincronizar una operación inmediatamente (fire & forget).
  void _syncImmediately(Map<String, dynamic> data, SyncOperation op, String id) {
    Future.microtask(() async {
      try {
        switch (op) {
          case SyncOperation.insert:
            await _supabase.from('clientes').upsert(data);
            break;
          case SyncOperation.update:
            final updateData = Map<String, dynamic>.from(data);
            updateData.remove('id');
            await _supabase.from('clientes').update(updateData).eq('id', id);
            break;
          case SyncOperation.delete:
            await _supabase.from('clientes').delete().eq('id', id);
            break;
        }
        // Éxito: remover de la cola
        await _removeFromQueue(id);
        debugPrint('☁️ Cliente sync inmediato OK: $id');
      } catch (e) {
        debugPrint('⚠️ Sync inmediato fallido (se reintentará): $e');
        // Se queda en la cola para el SyncEngine
      }
    });
  }

  Future<void> _removeFromQueue(String registroId) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue',
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: ['clientes', registroId],
    );
  }

  /// Genera un UUID v4 simple (sin dependencia externa).

  // ── REALTIME ──────────────────────────────────────────────────────────────

  /// Escucha cambios en la tabla clientes para actualizar la base local.
  RealtimeChannel subscribeToChanges(void Function() onUpdate) {
    final channel = _supabase.channel('public:clientes_repo_changes');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'clientes',
      callback: (payload) {
        debugPrint('🔔 Realtime clientes: ${payload.eventType}');
        _refreshLocal().then((_) => onUpdate());
      },
    ).subscribe();
    return channel;
  }

  /// Refresh: pull clientes desde la nube y actualizar SQLite.
  Future<void> _refreshLocal() async {
    final db = await LocalDatabase.instance;
    await _pullFromCloud(db);
  }

  /// Fuerza un refresh de datos desde la nube.
  Future<void> forceRefresh() async {
    await _refreshLocal();
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final clientesRepositoryProvider = Provider<ClientesRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return ClientesRepository(supabase, connectivity);
});
