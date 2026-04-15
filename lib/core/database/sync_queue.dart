import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'local_database.dart';
import 'package:sqflite_common/sqlite_api.dart'; // Para DatabaseExecutor

/// Operaciones soportadas por la cola de sincronización.
enum SyncOperation { insert, update, delete }

/// Registro pendiente de sincronización con la nube.
class SyncQueueEntry {
  final int? id;
  final String tabla;
  final SyncOperation operacion;
  final String registroId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int intentos;
  final String? ultimoError;

  SyncQueueEntry({
    this.id,
    required this.tabla,
    required this.operacion,
    required this.registroId,
    required this.payload,
    DateTime? createdAt,
    this.intentos = 0,
    this.ultimoError,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'tabla': tabla,
    'operacion': operacion.name,
    'registro_id': registroId,
    'payload': jsonEncode(payload),
    'created_at': createdAt.toIso8601String(),
    'intentos': intentos,
    'ultimo_error': ultimoError,
  };

  factory SyncQueueEntry.fromMap(Map<String, dynamic> map) => SyncQueueEntry(
    id: map['id'] as int?,
    tabla: map['tabla'] as String,
    operacion: SyncOperation.values.byName(map['operacion'] as String),
    registroId: map['registro_id'] as String,
    payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
    createdAt: DateTime.parse(map['created_at'] as String),
    intentos: (map['intentos'] as int?) ?? 0,
    ultimoError: map['ultimo_error'] as String?,
  );
}

/// Cola de sincronización FIFO con deduplicación.
///
/// Las operaciones offline se encolan aquí y se procesan
/// cuando se recupera la conectividad.
class SyncQueue {
  /// Verifica si un registroId es válido:
  /// - UUID estándar de 36 caracteres (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
  /// - Clave compuesta de dos UUIDs de 36 chars separados por '_' (para eventos_servicios)
  static bool _isValidId(String id) {
    // UUID estándar
    if (id.length == 36) return true;
    // Clave compuesta: uuid_uuid (73 chars con separador _)
    if (id.length == 73) {
      final parts = id.split('_');
      if (parts.length == 2 && parts[0].length == 36 && parts[1].length == 36) return true;
    }
    return false;
  }

  /// Encola una operación para sincronización futura.
  /// Si ya existe una operación pendiente para el mismo registro+tabla,
  /// la reemplaza (deduplicación).
  static Future<void> enqueue({
    required String tabla,
    required SyncOperation operacion,
    required String registroId,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    // Blindaje contra IDs malformados
    if (!_isValidId(registroId)) {
      debugPrint('🚫 Sync: Ignorando encolado para ID malformado ($registroId) en $tabla');
      return;
    }

    // Si se provee un ejecutor (transacción), lo usamos para evitar deadlocks
    final db = executor ?? await LocalDatabase.instance;

    // Deduplicación: si ya hay una entrada pendiente para este registro,
    // la actualizamos en vez de crear duplicados.
    final existing = await db.query(
      '_sync_queue',
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: [tabla, registroId],
    );

    if (existing.isNotEmpty) {
      // Si la nueva operación es DELETE, prevalece sobre INSERT/UPDATE.
      // Si había un INSERT y ahora es UPDATE, mantenemos INSERT con datos nuevos.
      final oldOp = SyncOperation.values.byName(existing.first['operacion'] as String);
      SyncOperation finalOp;

      if (operacion == SyncOperation.delete) {
        if (oldOp == SyncOperation.insert) {
          // INSERT + DELETE = no hacer nada (el registro nunca existió en la nube)
          await db.delete('_sync_queue',
            where: 'tabla = ? AND registro_id = ?',
            whereArgs: [tabla, registroId],
          );
          debugPrint('🔄 Sync: INSERT+DELETE cancelados para $tabla/$registroId');
          return;
        }
        finalOp = SyncOperation.delete;
      } else if (oldOp == SyncOperation.insert) {
        // INSERT + UPDATE = INSERT con datos actualizados
        finalOp = SyncOperation.insert;
      } else {
        finalOp = operacion;
      }

      final existingPayloadString = existing.first['payload'] as String;
      final Map<String, dynamic> existingPayload = jsonDecode(existingPayloadString);
      
      // Combinamos: prevalece lo nuevo pero conservamos lo viejo que no se cambió
      final Map<String, dynamic> mergedPayload = {...existingPayload, ...payload};

      await db.update(
        '_sync_queue',
        {
          'operacion': finalOp.name,
          'payload': jsonEncode(mergedPayload),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'intentos': 0,
          'ultimo_error': null,
        },
        where: 'tabla = ? AND registro_id = ?',
        whereArgs: [tabla, registroId],
      );
      // Log silenciado por pedido del usuario (evitar ruido en terminal)
      // debugPrint('🔄 Sync: Actualizado $finalOp para $tabla/$registroId');
    } else {
      final entry = SyncQueueEntry(
        tabla: tabla,
        operacion: operacion,
        registroId: registroId,
        payload: payload,
      );
      await db.insert('_sync_queue', entry.toMap());
      // Log silenciado por pedido del usuario (evitar ruido en terminal)
      // debugPrint('📝 Sync: Encolado ${operacion.name} para $tabla/$registroId');
    }
  }

  /// Obtiene todas las operaciones pendientes, ordenadas FIFO.
  static Future<List<SyncQueueEntry>> getPending({int limit = 50}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      '_sync_queue',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  /// Cantidad de operaciones pendientes (excluye errores permanentes).
  static Future<int> get pendingCount async {
    final db = await LocalDatabase.instance;
    // Un registro es "pendiente" solo si no tiene un error permanente 
    // y no ha fallado demasiadas veces (dead letters).
    // Alineado a 10 intentos como límite de reintento del motor.
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM _sync_queue "
      "WHERE (ultimo_error IS NULL OR ultimo_error NOT LIKE 'ERROR_PERMANENTE%') "
      "AND intentos < 10"
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Elimina una entrada completada exitosamente.
  static Future<void> markCompleted(int entryId) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue', where: 'id = ?', whereArgs: [entryId]);
  }

  /// Marca un intento fallido con su error.
  static Future<void> markFailed(int entryId, String error) async {
    final db = await LocalDatabase.instance;
    await db.rawUpdate(
      'UPDATE _sync_queue SET intentos = intentos + 1, ultimo_error = ? WHERE id = ?',
      [error, entryId],
    );
  }

  /// Marca un registro como pausado (esperando dependencia) SIN incrementar intentos.
  static Future<void> markPaused(int entryId, String error) async {
    final db = await LocalDatabase.instance;
    await db.update(
      '_sync_queue',
      {'ultimo_error': error},
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  /// Saneamiento total: Limpia toda la cola de sincronización.
  static Future<void> clearQueue() async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue');
  }

  /// Limpia entradas con demasiados intentos fallidos (dead letter).
  static Future<int> purgeDeadLetters({int maxIntentos = 10}) async {
    final db = await LocalDatabase.instance;
    return db.delete(
      '_sync_queue',
      where: 'intentos >= ?',
      whereArgs: [maxIntentos],
    );
  }

  /// PURGA DE ESTABILIZACIÓN: Elimina registros marcados con ERROR_PERMANENTE 
  /// o que han excedido el límite de reintentos (10).
  static Future<int> purgePermanentErrors() async {
    final db = await LocalDatabase.instance;
    final count = await db.delete(
      '_sync_queue',
      where: "ultimo_error LIKE 'ERROR_PERMANENTE%' OR intentos >= 10",
    );
    if (count > 0) {
      debugPrint('🧹 Sync: Purgados $count registros agotados o corruptos');
    }
    return count;
  }
}
