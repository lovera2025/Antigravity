import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_database.dart';
import '../database/sync_queue.dart';
import 'connectivity_service.dart';

/// Estado del motor de sincronización.
enum SyncStatus {
  idle,
  wakingUp,
  syncing,
  error,
  offline,
}

/// Motor de sincronización bidireccional.
class SyncEngine {
  final ConnectivityService _connectivity;
  final SupabaseClient _supabase;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastSyncTime;
  DateTime? get lastSyncTime => _lastSyncTime;

  // Exponential backoff state
  int _retryAttempt = 0;
  static const int _maxRetryDelay = 32; // segundos
  static const int _baseRetryDelay = 2;
  Timer? _retryTimer;

  // Stream de estado
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  final _pendingController = StreamController<int>.broadcast();
  Stream<int> get pendingStream => _pendingController.stream;

  StreamSubscription<AppConnectivity>? _connectivitySub;

  SyncEngine({
    required ConnectivityService connectivity,
    SupabaseClient? supabase,
  })  : _connectivity = connectivity,
        _supabase = supabase ?? Supabase.instance.client;

  /// Inicia el motor de sincronización.
  void start() {
    debugPrint('⚡ SyncEngine iniciado');

    // Escuchar cambios de conectividad
    _connectivitySub = _connectivity.stream.listen((status) {
      if (status == AppConnectivity.online) {
        debugPrint('🌐 Conexión restaurada → Iniciando sync...');
        _retryAttempt = 0; // Reset backoff
        syncNow();
      } else {
        _updateStatus(SyncStatus.offline);
      }
    });

    // Sync inicial si estamos online
    if (_connectivity.currentStatus == AppConnectivity.online) {
      syncNow();
    } else {
      _updateStatus(SyncStatus.offline);
    }

    // Actualizar contador periódicamente
    _refreshPendingCount();
  }

  /// Ejecuta un ciclo completo de sincronización.
  Future<void> syncNow() async {
    if (_status == SyncStatus.syncing || _status == SyncStatus.wakingUp) {
      debugPrint('🔄 Sync ya en progreso, ignorando...');
      return;
    }

    try {
      // ── Paso 1: Wake-up ────────────────────────────────────────────────────
      _updateStatus(SyncStatus.wakingUp);
      final awake = await _connectivity.wakeUpCloud();

      if (!awake) {
        debugPrint('💤 Supabase no respondió al wake-up, reintentando con backoff...');
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        _scheduleRetry();
        return;
      }

      debugPrint('✅ Supabase despierto, iniciando sincronización...');

      // ── Paso 2: Flush Local → Cloud ────────────────────────────────────────
      _updateStatus(SyncStatus.syncing);
      
      int maxRounds = 3; // Evitar bucles infinitos
      bool madeProgress = true;
      
      while (madeProgress && maxRounds > 0) {
        madeProgress = await _flushQueue();
        maxRounds--;
        if (madeProgress && maxRounds > 0) {
          debugPrint('🚀 Turbo Boost: Progresos detectados, iniciando ronda extra de sync...');
        }
      }

      // ── Paso 3: Pull Cloud → Local ─────────────────────────────────────────
      await _pullFromCloud();

      _lastSyncTime = DateTime.now();
      _updateStatus(SyncStatus.idle);
      debugPrint('✅ Ciclo de sincronización completado');

    } catch (e) {
      debugPrint('❌ Error fatal syncNow: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
      _scheduleRetry();
    } finally {
      _refreshPendingCount();
    }
  }

  /// Envía los cambios locales pendientes a la nube.
  /// Devuelve true si al menos una operación se completó con éxito.
  Future<bool> _flushQueue() async {
    final pending = await SyncQueue.getPending();
    if (pending.isEmpty) return false;

    bool anySuccess = false;

    // ── PRIORIZACIÓN JERÁRQUICA ──────────────────────────────────────────
    // Definimos niveles de importancia para procesar primero los "padres"
    int getPriority(SyncQueueEntry entry) {
      final table = entry.tabla;
      final payload = entry.payload;
      
      if (table == 'clientes') return 0;
      if (table == 'eventos' || table == 'presupuestos') return 1;
      
      // Los servicios globales son prioridad 0, los ad-hoc (con evento_id) son prioridad 2
      if (table == 'servicios') {
        return (payload['evento_id'] != null) ? 2 : 0;
      }
      
      if (table == 'pagos_contrato_alumno') return 4;
      if (table == 'eventos_servicios' || table == 'presupuesto_servicios') return 3; // Depende de padre y servicio
      
      // Resto de tablas (transacciones, egresos, invitados, etc) dependen de evento
      return 2;
    }

    // Ordenamos la cola: primero por prioridad, luego por fecha (FIFO dentro de la prioridad)
    final sortedPending = List<SyncQueueEntry>.from(pending);
    sortedPending.sort((a, b) {
      final pA = getPriority(a);
      final pB = getPriority(b);
      if (pA != pB) return pA.compareTo(pB);
      return a.createdAt.compareTo(b.createdAt);
    });

    debugPrint('📤 Procesando ${sortedPending.length} operaciones (Orden Jerárquico)...');

    // Mantenemos un set de los IDs que están en esta cola para detectar dependencias pendientes
    final pendingIdsInQueue = pending.map((e) => e.registroId).toSet();

    for (final entry in sortedPending) {
      if (entry.intentos >= 10) {
        debugPrint('  ! Registro agotado: ${entry.tabla}/${entry.registroId} (falló 10 veces)');
        continue;
      }

      // BLOQUEO REFERENCIAL: Si el padre de este registro está en la MISMA cola pendiente,
      // posponemos este registro para la siguiente vuelta del motor.
      final payload = entry.payload;
      bool hasPendingParent = false;
      String? parentTable;
      String? parentId;

      if (payload['evento_id'] != null && pendingIdsInQueue.contains(payload['evento_id'])) {
        hasPendingParent = true;
        // Detectar si el ID es de un evento o presupuesto en la cola
        final isPresupuesto = sortedPending.any((e) => e.tabla == 'presupuestos' && e.registroId == payload['evento_id']);
        parentTable = isPresupuesto ? 'presupuestos' : 'eventos';
        parentId = payload['evento_id'];
      } else if (payload['cliente_id'] != null && pendingIdsInQueue.contains(payload['cliente_id'])) {
        hasPendingParent = true;
        parentTable = 'clientes';
        parentId = payload['cliente_id'];
      } else if (payload['contrato_alumno_id'] != null && pendingIdsInQueue.contains(payload['contrato_alumno_id'])) {
        hasPendingParent = true;
        parentTable = 'contratos_alumnos';
        parentId = payload['contrato_alumno_id'];
      } else {
        final table = entry.tabla;
        final payload = entry.payload;

        // 1. Verificar integridad del Evento Padre
        if (table == 'servicios' && payload['evento_id'] != null) {
          if (pendingIdsInQueue.contains(payload['evento_id'])) {
             debugPrint('  ⏳ Posponiendo Servicio (${entry.registroId}): Evento Padre ${payload['evento_id']} en cola.');
             continue;
          }
        }

        // 2. Verificar integridad del Presupuesto Padre
        if (table == 'presupuesto_servicios' && payload['presupuesto_id'] != null) {
          if (pendingIdsInQueue.contains(payload['presupuesto_id'])) {
             debugPrint('  ⏳ Posponiendo Detalle Presupuesto: Presupuesto Padre ${payload['presupuesto_id']} en cola.');
             continue;
          }
        }
        
        // 3. Verificar integridad de Evento-Servicio
        if (table == 'eventos_servicios') {
          final eid = payload['evento_id'];
          final sid = payload['servicio_id'];
          if (pendingIdsInQueue.contains(eid) || pendingIdsInQueue.contains(sid)) {
             debugPrint('  ⏳ Posponiendo Presupuesto Item: Padre(s) en cola.');
             continue;
          }
        }
      }

      if (hasPendingParent) {
        debugPrint('  ⏳ Posponiendo ${entry.tabla}/${entry.registroId}: esperando a $parentTable/$parentId');
        continue;
      }

      try {
        await _executeSyncOperation(entry);
        await SyncQueue.markCompleted(entry.id!);
        debugPrint('  √ ${entry.operacion.name} ${entry.tabla}/${entry.registroId}');
        anySuccess = true;
        
        // ACELERACIÓN TURBO: Si acabamos de subir un "padre", notificamos al loop
        // para que re-intente procesar hijos pausados en esta misma vuelta si es posible.
      } catch (e) {
        debugPrint('  ✗ Error sync ${entry.tabla}/${entry.registroId}: $e');
        
        bool isNonRetryable = _isNonRetryableError(e);
        
        // Detección de Código 23503 (FK Violation / Huérfamos) -> AUTOCURACIÓN
        if (e is PostgrestException && (e.code == '23503' || e.message.contains('violates'))) {
           isNonRetryable = false;
           debugPrint('  ⏳ Pausa Referencial (${entry.tabla}/${entry.registroId}): Esperando integridad en la nube.');
           
           // Intentar Autocuración en silencio
           await _attemptSelfHealing(entry);
           
           await SyncQueue.markPaused(entry.id!, 'ESPERANDO_PADRE: $e'); 
           continue; 
        }

        if (isNonRetryable) {
          await SyncQueue.markCompleted(entry.id!);
        } else {
          final isPermanent = entry.intentos >= 9; 
          final errorMsg = isPermanent ? 'ERROR_PERMANENTE: $e' : e.toString();
          await SyncQueue.markFailed(entry.id!, errorMsg);
        }
      }
    }
    return anySuccess;
  }

  /// Intenta sanar la integridad referencial re-encolando registros padre faltantes.
  Future<void> _attemptSelfHealing(SyncQueueEntry childEntry) async {
    final payload = childEntry.payload;
    final parentDependencies = {
      'evento_id': 'eventos',
      'presupuesto_id': 'presupuestos',
      'cliente_id': 'clientes',
      'contrato_alumno_id': 'contratos_alumnos',
      'servicio_id': 'servicios',
    };

    final db = await LocalDatabase.instance;

    for (final entry in parentDependencies.entries) {
      final fkField = entry.key;
      final parentTable = entry.value;
      
      final parentId = payload[fkField] as String?;
      if (parentId == null || parentId.isEmpty) continue;

      // SOPORTE CASCADA: Si es evento_id, también podría estar en 'presupuestos'
      final potentialTables = (fkField == 'evento_id') 
          ? ['eventos', 'presupuestos'] 
          : [parentTable];

      bool parentFound = false;
      for (final table in potentialTables) {
        final parentRows = await db.query(table, where: 'id = ?', whereArgs: [parentId]);
        if (parentRows.isNotEmpty) {
          debugPrint('  [Self-Healing] Re-encolando padre $table/$parentId para desbloquear ${childEntry.tabla}');
          await SyncQueue.enqueue(
            tabla: table,
            operacion: SyncOperation.insert,
            registroId: parentId,
            payload: parentRows.first,
          );
          parentFound = true;
          break;
        }
      }

      if (!parentFound) {
        debugPrint('  [Self-Healing] Padre $parentId no encontrado en ${potentialTables.join('/')} localmente.');
      }
    }
  }

  // Tablas que usan clave primaria compuesta (sin columna 'id' propia).
  static const _compositePrimaryKeyTables = {'eventos_servicios', 'presupuesto_servicios'};

  /// Valida que todos los campos UUID en el payload tengan formato correcto (36 chars).
  String? _validateUuidFields(Map<String, dynamic> payload) {
    const uuidFields = ['id', 'evento_id', 'cliente_id', 'servicio_id', 'contrato_alumno_id', 'invitado_id'];
    for (final field in uuidFields) {
      if (payload.containsKey(field)) {
        final val = payload[field];
        if (val is String && val.isNotEmpty && val.length != 36) {
          return field;
        }
      }
    }
    return null;
  }

  /// Ejecuta una operación individual contra Supabase.
  Future<void> _executeSyncOperation(SyncQueueEntry entry) async {
    final payload = Map<String, dynamic>.from(entry.payload);

    // Pre-validación: rechazar cualquier operación con UUID malformado
    final badField = _validateUuidFields(payload);
    if (badField != null) {
      throw Exception('UUID_INVALIDO: El campo "$badField" contiene un valor no-UUID en ${entry.tabla}');
    }

    final isComposite = _compositePrimaryKeyTables.contains(entry.tabla);

    switch (entry.operacion) {
      case SyncOperation.insert:
        await _supabase.from(entry.tabla).upsert(payload);
        break;
      case SyncOperation.update:
        if (isComposite) {
          await _supabase.from(entry.tabla).upsert(payload);
        } else {
          await _supabase.from(entry.tabla)
              .update(payload)
              .eq('id', entry.registroId);
        }
        break;
      case SyncOperation.delete:
        if (entry.tabla == 'eventos_servicios' || entry.tabla == 'presupuesto_servicios') {
          final parts = entry.registroId.split('_');
          if (parts.length == 2) {
            final parentField = entry.tabla == 'eventos_servicios' ? 'evento_id' : 'presupuesto_id';
            await _supabase.from(entry.tabla)
                .delete()
                .eq(parentField, parts[0])
                .eq('servicio_id', parts[1]);
          }
        } else {
          await _supabase.from(entry.tabla)
              .delete()
              .eq('id', entry.registroId);
        }
        break;
    }
  }

  /// Descarga datos frescos de Supabase → SQLite.
  Future<void> _pullFromCloud() async {
    final db = await LocalDatabase.instance;

    debugPrint('📥 Pull Cloud → Local...');

    await _pullTable(db, 'clientes', 'created_at');
    await _pullTable(db, 'servicios', null);
    await _pullTable(db, 'eventos', 'created_at');
    await _pullTable(db, 'eventos_servicios', null, primaryKey: 'evento_id');
    await _pullTable(db, 'transacciones', 'fecha_pago');
    await _pullTable(db, 'egresos', 'fecha');
    await _pullTable(db, 'contratos_alumnos', 'created_at');
    await _pullTable(db, 'pagos_contrato_alumno', 'created_at');
    await _pullTable(db, 'invitados', 'updated_at');
    await _pullTable(db, 'solicitudes_cotizacion', null);

    debugPrint('📥 Pull completado');
  }

  /// Descarga y upsert de una tabla completa.
  Future<void> _pullTable(Database db, String table, String? orderBy, {String primaryKey = 'id'}) async {
    try {
      final List<dynamic> data;
      if (orderBy != null) {
        data = await _supabase.from(table).select().order(orderBy, ascending: false);
      } else {
        data = await _supabase.from(table).select();
      }
      final rows = data.cast<Map<String, dynamic>>();

      if (rows.isEmpty) return;

      const fkFields = ['evento_id', 'cliente_id', 'contrato_alumno_id', 'servicio_id', 'invitado_id'];

      final batch = db.batch();
      int skipped = 0;
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id != null && id.length != 36) {
          skipped++;
          continue;
        }

        bool hasBadFk = false;
        for (final fk in fkFields) {
          final fkVal = row[fk] as String?;
          if (fkVal != null && fkVal.isNotEmpty && fkVal.length != 36) {
            hasBadFk = true;
            skipped++;
            break;
          }
        }
        if (hasBadFk) continue;

        final cleanRow = _cleanForSqlite(table, row);
        batch.insert(table, cleanRow, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);

      final stored = rows.length - skipped;
      debugPrint('  📥 $table: $stored registros${skipped > 0 ? " ($skipped corruptos omitidos)" : ""}');
    } catch (e) {
      debugPrint('  ⚠️ Error pull $table: $e');
    }
  }

  /// Limpia un mapa de datos para que solo contenga columnas de la tabla SQLite.
  Map<String, dynamic> _cleanForSqlite(String table, Map<String, dynamic> row) {
    const tableColumns = {
      'clientes': ['id', 'nombre_completo', 'telefono', 'email', 'is_archived', 'created_at'],
      'eventos': ['id', 'cliente_id', 'tipo', 'fecha_evento', 'cantidad_cuotas', 'modalidad', 'estado', 'pin_operador', 'observaciones', 'created_at'],
      'servicios': ['id', 'nombre', 'categoria', 'costo_base', 'margen_ganancia', 'costo_interno', 'evento_id'],
      'eventos_servicios': ['evento_id', 'servicio_id', 'precio_final_acordado', 'cantidad'],
      'transacciones': ['id', 'evento_id', 'monto', 'concepto', 'fecha_pago', 'created_by'],
      'egresos': ['id', 'evento_id', 'monto', 'proveedor', 'categoria', 'fecha', 'created_by'],
      'contratos_alumnos': ['id', 'evento_id', 'nombre_alumno', 'institucion', 'cantidad_acompanantes', 'monto_total_pactado', 'saldo_deudor', 'cuotas_pagadas', 'total_cuotas', 'nombres_acompanantes', 'dia_vencimiento_mensual', 'mesa_extra_precio', 'mesa_extra_cuotas', 'mesa_extra_cuotas_pagadas', 'sillas_extra_cantidad', 'sillas_extra_cuotas', 'sillas_extra_precio_total', 'sillas_extra_cuotas_pagadas', 'mesa_extra_pagado', 'sillas_extra_pagado', 'curso_division', 'musica_elegida', 'numero_mesa', 'telefono', 'created_at'],
      'pagos_contrato_alumno': ['id', 'contrato_alumno_id', 'monto', 'concepto', 'fecha_pago', 'created_at'],
      'invitados': ['id', 'evento_id', 'nombre_completo', 'dni', 'numero_mesa', 'estado_ingreso', 'intentos_fallidos', 'updated_at', 'created_at'],
      'solicitudes_cotizacion': ['id', 'cliente_nombre', 'cliente_celular', 'servicios_seleccionados', 'estado'],
      'presupuesto_servicios': ['presupuesto_id', 'servicio_id', 'precio_final', 'cantidad', 'detalle_servicio'],
    };

    final validCols = tableColumns[table];
    if (validCols == null) return row;

    final clean = <String, dynamic>{};
    for (final col in validCols) {
      if (row.containsKey(col)) {
        var value = row[col];
        if (value is List || value is Map) {
          value = value.toString();
        }
        if (value is bool) {
          value = value ? 1 : 0;
        }
        clean[col] = value;
      }
    }

    if (table == 'contratos_alumnos' && row.containsKey('cantidad_acompañantes')) {
      clean['cantidad_acompanantes'] = row['cantidad_acompañantes'];
    }
    if (table == 'contratos_alumnos' && row.containsKey('nombres_acompañantes')) {
      final val = row['nombres_acompañantes'];
      clean['nombres_acompanantes'] = val is List ? jsonEncode(val) : (val ?? '[]');
    }

    return clean;
  }

  /// Purga de IDs corruptos directamente en Supabase.
  Future<void> _purgeCloudCorruptData() async {
    const tablesWithId = [
      'contratos_alumnos', 'pagos_contrato_alumno', 'transacciones', 'egresos',
      'invitados', 'clientes', 'eventos', 'servicios',
    ];

    int totalEliminados = 0;

    for (final table in tablesWithId) {
      try {
        final rows = await _supabase.from(table).select('id');
        final badIds = (rows as List)
            .map((r) => r['id'] as String?)
            .where((id) => id != null && id.length != 36)
            .cast<String>()
            .toList();

        if (badIds.isEmpty) continue;

        for (final badId in badIds) {
          await _supabase.from(table).delete().eq('id', badId);
          totalEliminados++;
        }
      } catch (e) {
        debugPrint('  ⚠️ Error purga cloud en $table: $e');
      }
    }

    if (totalEliminados > 0) {
      debugPrint('🗑️ Purga cloud: $totalEliminados registros corruptos eliminados');
    }
  }

  bool _isNonRetryableError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('unique') ||
           msg.contains('duplicate') ||
           msg.contains('not found') ||
           msg.contains('22p02') ||
           msg.contains('uuid_invalido') ||
           msg.contains('invalid input syntax for type uuid');
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = min(_baseRetryDelay * pow(2, _retryAttempt).toInt(), _maxRetryDelay);
    _retryAttempt++;

    _retryTimer = Timer(Duration(seconds: delay), () {
      if (_connectivity.currentStatus != AppConnectivity.offline) {
        syncNow();
      }
    });
  }

  Future<void> _refreshPendingCount() async {
    _pendingCount = await SyncQueue.pendingCount;
    _pendingController.add(_pendingCount);
  }

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    _retryTimer?.cancel();
    _connectivitySub?.cancel();
    _statusController.close();
    _pendingController.close();
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  final engine = SyncEngine(connectivity: connectivity);
  engine.start();
  ref.onDispose(() => engine.dispose());
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.statusStream;
});

final syncPendingCountProvider = StreamProvider<int>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.pendingStream;
});
