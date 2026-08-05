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
/// cuando el usuario elige subir a la nube.
class SyncQueue {
  /// Notifica al [SyncEngine] que el contador de pendientes cambió.
  static void Function()? onChanged;
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

    // Si es un borrado de un registro principal, limpiamos de la cola a sus hijos huérfanos
    if (operacion == SyncOperation.delete) {
      await _cleanOrphanQueueEntries(db, tabla, registroId);
    }

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
          onChanged?.call();
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
      onChanged?.call();
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
    onChanged?.call();
  }

  /// Obtiene operaciones pendientes, ordenadas FIFO.
  /// [limit] null = sin límite (drenado manual completo).
  static Future<List<SyncQueueEntry>> getPending({int? limit = 50}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      '_sync_queue',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  /// Cantidad de operaciones que TODAVÍA NO subieron a la nube.
  ///
  /// Cuenta todo lo que está en la cola, sin excepciones. Antes descontaba los
  /// que tenían error permanente o 10 intentos fallidos: justo esos. El
  /// indicador marcaba "0 pendientes / todo sincronizado" mientras un cobro
  /// estaba trabado, y nadie se enteraba hasta que la familia aparecía con el
  /// recibo en la mano. Si algo no subió, tiene que verse.
  static Future<int> get pendingCount async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM _sync_queue',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Pendientes que vale la pena intentar YA (menos de 10 intentos fallidos).
  ///
  /// Es lo que mira el disparador automático. [pendingCount] cuenta todo
  /// porque es el número honesto para el usuario, pero si se usara para
  /// disparar, una PC con un registro imposible de subir llamaría a la nube
  /// cada 10 segundos para siempre y el indicador viviría parpadeando. Los
  /// trabados se reintentan aparte, espaciados, desde el motor.
  static Future<int> get readyCount async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM _sync_queue WHERE intentos < 10',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Cuántos de los pendientes están trabados (fallaron 10 veces o más).
  /// Se reintentan igual, pero conviene poder mirarlos.
  static Future<int> get stuckCount async {
    final db = await LocalDatabase.instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM _sync_queue WHERE intentos >= 10',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Detalle de los trabados, para diagnosticar sin abrir la base a mano.
  static Future<List<SyncQueueEntry>> getStuck() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      '_sync_queue',
      where: 'intentos >= ?',
      whereArgs: [10],
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncQueueEntry.fromMap).toList();
  }

  /// Elimina una entrada completada exitosamente.
  static Future<void> markCompleted(int entryId) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue', where: 'id = ?', whereArgs: [entryId]);
    onChanged?.call();
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

  // NO agregar acá ninguna función que borre de la cola por cantidad de
  // intentos o por "error permanente". Existieron dos (purgeDeadLetters y
  // purgePermanentErrors) y se sacaron a propósito: borrar un registro que
  // nunca subió es perder un cobro. Los trabados se reintentan espaciados
  // desde el motor y se cuentan en stuckCount. Si alguno hay que descartarlo,
  // que sea una decisión explícita de una persona mirando getStuck().

  /// Limpia de la cola de sincronización cualquier entrada de tablas secundarias
  /// que dependan del registro principal (padre) que se está eliminando.
  static Future<void> _cleanOrphanQueueEntries(
    DatabaseExecutor db,
    String padreTabla,
    String padreId,
  ) async {
    // Definimos el mapa de dependencias: TablaPadre -> { TablaHija: CampoFK }
    final Map<String, Map<String, String>> relaciones = {
      'clientes': {
        'eventos': 'cliente_id',
        'presupuestos': 'cliente_id',
        'prestamos_alquiler': 'cliente_id',
      },
      'eventos': {
        'transacciones': 'evento_id',
        'egresos': 'evento_id',
        'contratos_alumnos': 'evento_id',
        'invitados': 'evento_id',
        'eventos_servicios': 'evento_id',
        'calculos_rentabilidad': 'evento_id',
      },
      'presupuestos': {
        'presupuesto_servicios': 'presupuesto_id',
        'calculos_rentabilidad': 'presupuesto_id',
      },
      'contratos_alumnos': {
        'pagos_contrato_alumno': 'contrato_alumno_id',
        'notas_operativas_contrato': 'contrato_alumno_id',
      },
      'prestamos_alquiler': {
        'prestamo_alquiler_lineas': 'prestamo_id',
        'pagos_prestamo_alquiler': 'prestamo_id',
      },
    };

    final hijas = relaciones[padreTabla];
    if (hijas == null || hijas.isEmpty) return;

    for (final entrada in hijas.entries) {
      final tablaHija = entrada.key;
      final campoFk = entrada.value;

      // Obtener todas las entradas de la cola de sync para la tabla hija
      final rows = await db.query(
        '_sync_queue',
        columns: ['id', 'payload'],
        where: 'tabla = ?',
        whereArgs: [tablaHija],
      );

      final toDeleteIds = <int>[];

      for (final r in rows) {
        final id = r['id'] as int;
        final payloadString = r['payload'] as String?;
        if (payloadString == null || payloadString.isEmpty) continue;

        try {
          final payload = jsonDecode(payloadString) as Map<String, dynamic>;
          if (payload[campoFk]?.toString() == padreId) {
            toDeleteIds.add(id);
          }
        } catch (e) {
          debugPrint('⚠️ Error decodificando payload para limpiar huérfanos: $e');
        }
      }

      if (toDeleteIds.isNotEmpty) {
        debugPrint('🧹 Sync: Limpiando ${toDeleteIds.length} registros huérfanos de $tablaHija asociados al $padreTabla/$padreId en la cola');
        // Eliminar registros huérfanos de la cola
        for (final id in toDeleteIds) {
          await db.delete('_sync_queue', where: 'id = ?', whereArgs: [id]);
        }
      }
    }
  }
}
