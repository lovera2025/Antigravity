import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_database.dart';
import '../database/sync_queue.dart';
import '../utils/uuid_utils.dart';
import 'connectivity_service.dart';
import '../../features/mi_empresa/repositories/finanzas_repository.dart';

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

      FinanzasRepository.invalidateProyeccionCache();

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
      if (table == 'eventos' || table == 'presupuestos' || table == 'prestamos_alquiler') return 1;
      
      // Los servicios globales son prioridad 0, los ad-hoc (con evento_id) son prioridad 2
      if (table == 'servicios') {
        return (payload['evento_id'] != null) ? 2 : 0;
      }
      
      if (table == 'pagos_contrato_alumno' || table == 'pagos_prestamo_alquiler') return 4;
      if (table == 'notas_operativas_contrato') return 4;
      if (table == 'eventos_servicios' || table == 'presupuesto_servicios' || table == 'prestamo_alquiler_lineas') {
        return 3;
      } // Depende de padre y servicio / préstamo

      // Análisis de rentabilidad: opcionalmente referencia evento/presupuesto; va al final
      if (table == 'calculos_rentabilidad') return 5;
      // Caja fuerte (Mi empresa PERSONAL): sin FK a eventos; cola estable
      if (table == 'caja_fuerte_movimientos') return 5;

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
      } else if (payload['presupuesto_id'] != null && pendingIdsInQueue.contains(payload['presupuesto_id'])) {
        hasPendingParent = true;
        parentTable = 'presupuestos';
        parentId = payload['presupuesto_id'];
      } else if (payload['cliente_id'] != null && pendingIdsInQueue.contains(payload['cliente_id'])) {
        hasPendingParent = true;
        parentTable = 'clientes';
        parentId = payload['cliente_id'];
      } else if (payload['contrato_alumno_id'] != null && pendingIdsInQueue.contains(payload['contrato_alumno_id'])) {
        hasPendingParent = true;
        parentTable = 'contratos_alumnos';
        parentId = payload['contrato_alumno_id'];
      } else if (payload['prestamo_id'] != null && pendingIdsInQueue.contains(payload['prestamo_id'])) {
        hasPendingParent = true;
        parentTable = 'prestamos_alquiler';
        parentId = payload['prestamo_id'];
      } else if (entry.tabla == 'eventos_servicios' &&
                 payload['servicio_id'] != null &&
                 pendingIdsInQueue.contains(payload['servicio_id'])) {
        // Caso especial: línea de servicio cuyo servicio (catálogo o ad-hoc) aún no subió.
        hasPendingParent = true;
        parentTable = 'servicios';
        parentId = payload['servicio_id'];
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
      'prestamo_id': 'prestamos_alquiler',
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

  /// Valida que todos los campos UUID en el payload tengan formato correcto (36 chars).
  String? _validateUuidFields(Map<String, dynamic> payload) {
    const uuidFields = [
      'id',
      'evento_id',
      'presupuesto_id',
      'cliente_id',
      'servicio_id',
      'contrato_alumno_id',
      'invitado_id',
      'prestamo_id',
    ];
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

    switch (entry.operacion) {
      case SyncOperation.insert:
        await _supabase.from(entry.tabla).upsert(payload);
        break;
      case SyncOperation.update:
        await _supabase.from(entry.tabla)
            .update(payload)
            .eq('id', entry.registroId);
        break;
      case SyncOperation.delete:
        if (entry.registroId.length == 36) {
          await _supabase.from(entry.tabla)
              .delete()
              .eq('id', entry.registroId);
        } else if (entry.tabla == 'eventos_servicios' || entry.tabla == 'presupuesto_servicios') {
          // Legado: eventoId_servicioId
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

  Future<void> _pullFromCloud() async {
    final db = await LocalDatabase.instance;

    debugPrint('📥 Pull Cloud → Local (En Paralelo)...');

    await Future.wait([
      _pullTable(db, 'clientes', 'created_at'),
      _pullTable(db, 'servicios', null),
      _pullTable(db, 'eventos', 'created_at'),
      _pullTable(db, 'eventos_servicios', null, primaryKey: 'id'),
      _pullTable(db, 'presupuestos', 'created_at'),
      _pullTable(db, 'presupuesto_servicios', null, primaryKey: 'id'),
      _pullTable(db, 'transacciones', 'fecha_pago'),
      _pullTable(db, 'egresos', 'fecha'),
      _pullTable(db, 'contratos_alumnos', 'created_at'),
      _pullTable(db, 'notas_operativas_contrato', 'updated_at'),
      _pullTable(db, 'pagos_contrato_alumno', 'created_at'),
      _pullTable(db, 'invitados', 'updated_at'),
      _pullTable(db, 'solicitudes_cotizacion', null),
      _pullTable(db, 'prestamos_alquiler', 'created_at'),
      _pullTable(db, 'prestamo_alquiler_lineas', null),
      _pullTable(db, 'pagos_prestamo_alquiler', 'created_at'),
      _pullTable(db, 'calculos_rentabilidad', 'created_at'),
      _pullTable(db, 'obligaciones_pago', 'fecha_vencimiento'),
      _pullTable(db, 'caja_fuerte_movimientos', 'created_at'),
      _pullTable(db, 'rentabilidad_config', null),
    ]);

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

      const fkFields = ['evento_id', 'cliente_id', 'contrato_alumno_id', 'servicio_id', 'invitado_id', 'prestamo_id'];

      Map<String, double?>? preservedBonifPctByEventoId;
      if (table == 'eventos') {
        final localPctRows = await db.query('eventos', columns: ['id', 'bonificacion_global_pct']);
        preservedBonifPctByEventoId = {
          for (final r in localPctRows)
            r['id'] as String: r['bonificacion_global_pct'] != null
                ? (r['bonificacion_global_pct'] as num).toDouble()
                : null,
        };
      }

      final batch = db.batch();
      int skipped = 0;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final id = row['id'] as String?;
        if (id != null && id.length != 36) {
          if (table != 'eventos_servicios' && table != 'presupuesto_servicios') {
            skipped++;
            continue;
          }
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

        var cleanRow = _cleanForSqlite(table, row);
        if (table == 'eventos_servicios' || table == 'presupuesto_servicios') {
          final insertMap = Map<String, dynamic>.from(cleanRow);
          final rawId = (insertMap['id'] as String?)?.trim() ?? '';
          if (rawId.length != 36) {
            final parentKey = table == 'eventos_servicios' ? 'evento_id' : 'presupuesto_id';
            final pid = (insertMap[parentKey] as String?)?.trim() ?? '';
            final sid = (insertMap['servicio_id'] as String?)?.trim() ?? '';
            if (pid.isEmpty || sid.isEmpty) {
              skipped++;
              continue;
            }
            final ctx = table == 'eventos_servicios' ? 'es' : 'ps';
            insertMap['id'] = UuidUtils.lineaIdDeterministic(ctx, pid, sid, index);
          }
          cleanRow = insertMap;
        }
        if (table == 'eventos' && preservedBonifPctByEventoId != null) {
          final eid = cleanRow['id'] as String;
          final cloudPctRaw = row['bonificacion_global_pct'];
          final insertRow = Map<String, dynamic>.from(cleanRow);
          if (cloudPctRaw != null) {
            insertRow['bonificacion_global_pct'] = double.tryParse(cloudPctRaw.toString());
          } else {
            final preserved = preservedBonifPctByEventoId[eid];
            if (preserved != null) {
              insertRow['bonificacion_global_pct'] = preserved;
            }
          }
          batch.insert(table, insertRow, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          batch.insert(table, cleanRow, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);

      // Prune orphan rows for line-item tables (eventos_servicios / presupuesto_servicios).
      // Migration v35 reassigned local UUIDs, so cloud rows arrive with their original UUIDs
      // and coexist with the locally-generated ones → duplicates.  Prune removes any local
      // row whose id is NOT in the cloud set and NOT pending in the sync queue.
      if (table == 'eventos_servicios' || table == 'presupuesto_servicios') {
        final cloudIds = <String>{};
        for (var i = 0; i < rows.length; i++) {
          final rawId = (rows[i]['id'] as String?)?.trim() ?? '';
          if (rawId.length == 36) {
            cloudIds.add(rawId);
          } else {
            final parentKey = table == 'eventos_servicios' ? 'evento_id' : 'presupuesto_id';
            final pid = (rows[i][parentKey] as String?)?.trim() ?? '';
            final sid = (rows[i]['servicio_id'] as String?)?.trim() ?? '';
            if (pid.isNotEmpty && sid.isNotEmpty) {
              final ctx = table == 'eventos_servicios' ? 'es' : 'ps';
              cloudIds.add(UuidUtils.lineaIdDeterministic(ctx, pid, sid, i));
            }
          }
        }

        final pendingRows = await db.query('_sync_queue',
            columns: ['registro_id'],
            where: "tabla = ?",
            whereArgs: [table]);
        final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

        final localRows = await db.query(table, columns: ['id']);
        int pruned = 0;
        for (final r in localRows) {
          final localId = (r['id'] as String?) ?? '';
          if (localId.isNotEmpty && !cloudIds.contains(localId) && !pendingIds.contains(localId)) {
            await db.delete(table, where: 'id = ?', whereArgs: [localId]);
            pruned++;
          }
        }
        if (pruned > 0) {
          debugPrint('  🧹 $table: $pruned filas huérfanas eliminadas (dedup post-migración)');
        }
      }

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
      'eventos': ['id', 'cliente_id', 'tipo', 'fecha_evento', 'cantidad_cuotas', 'modalidad', 'estado', 'pin_operador', 'observaciones', 'bonificacion_global_pct', 'created_at'],
      'servicios': ['id', 'nombre', 'categoria', 'costo_base', 'margen_ganancia', 'costo_interno', 'evento_id', 'is_archived'],
      'eventos_servicios': ['id', 'evento_id', 'servicio_id', 'precio_final_acordado', 'cantidad', 'grupo', 'detalle_servicio', 'combo_orden'],
      'presupuestos': [
        'id',
        'cliente_id',
        'tipo_evento',
        'lugar',
        'detalle_anclaje',
        'fecha_vencimiento',
        'fecha_evento',
        'estado',
        'instagram',
        'telefono',
        'vendedor_nombre',
        'titulo_festejado',
        'notificado_vencimiento',
        'created_at',
      ],
      'presupuesto_servicios': [
        'id',
        'presupuesto_id',
        'servicio_id',
        'precio_final',
        'cantidad',
        'detalle_servicio',
        'grupo',
        'combo_orden',
      ],
      'transacciones': [
        'id',
        'evento_id',
        'monto',
        'concepto',
        'fecha_pago',
        'created_by',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
      ],
      'egresos': ['id', 'evento_id', 'monto', 'proveedor', 'categoria', 'fecha', 'created_by', 'medio_pago'],
      'contratos_alumnos': ['id', 'evento_id', 'nombre_alumno', 'institucion', 'cantidad_acompanantes', 'monto_total_pactado', 'saldo_deudor', 'cuotas_pagadas', 'total_cuotas', 'nombres_acompanantes', 'dia_vencimiento_mensual', 'mesa_extra_precio', 'mesa_extra_cuotas', 'mesa_extra_cuotas_pagadas', 'sillas_extra_cantidad', 'sillas_extra_cuotas', 'sillas_extra_precio_total', 'sillas_extra_cuotas_pagadas', 'mesa_extra_pagado', 'sillas_extra_pagado', 'curso_division', 'musica_elegida', 'numero_mesa', 'telefono', 'created_at', 'contrato_firmado', 'mora_pendiente_tracked'],
      'notas_operativas_contrato': [
        'id',
        'contrato_alumno_id',
        'texto',
        'resuelto',
        'created_at',
        'updated_at',
      ],
      'pagos_contrato_alumno': [
        'id',
        'contrato_alumno_id',
        'monto',
        'monto_gross',
        'descuento_porcentaje',
        'concepto',
        'fecha_pago',
        'created_at',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
      ],
      'invitados': ['id', 'evento_id', 'nombre_completo', 'dni', 'numero_mesa', 'estado_ingreso', 'intentos_fallidos', 'updated_at', 'created_at'],
      'solicitudes_cotizacion': ['id', 'cliente_nombre', 'cliente_celular', 'servicios_seleccionados', 'estado'],
      'prestamos_alquiler': [
        'id',
        'cliente_id',
        'fecha_inicio',
        'fecha_fin',
        'aplica_iva',
        'alicuota_iva',
        'subtotal_neto',
        'monto_iva',
        'total',
        'texto_redaccion',
        'texto_disclaimer',
        'visible_listado',
        'created_at',
        'updated_at',
      ],
      'prestamo_alquiler_lineas': [
        'id',
        'prestamo_id',
        'descripcion',
        'cantidad',
        'precio_unitario',
        'linea_total',
        'orden',
      ],
      'pagos_prestamo_alquiler': [
        'id',
        'prestamo_id',
        'monto',
        'concepto',
        'fecha_pago',
        'created_at',
        'medio_pago',
        'anulado',
        'motivo_anulacion',
        'fecha_anulacion',
      ],
      'calculos_rentabilidad': [
        'id',
        'evento_id',
        'presupuesto_id',
        'precio_venta',
        'honorario_adrian_monto',
        'honorario_adrian_pct',
        'honorario_modo',
        'costos_variables_json',
        'costos_fijos_json',
        'resultado',
        'notas',
        'created_at',
        'created_by',
      ],
      'obligaciones_pago': [
        'id',
        'titulo',
        'tipo_obligacion',
        'fecha_vencimiento',
        'monto_estimado',
        'estado',
        'fecha_pago',
        'created_at',
      ],
      'caja_fuerte_movimientos': [
        'id',
        'tipo',
        'monto',
        'nota',
        'created_at',
      ],
      'rentabilidad_config': [
        'id',
        'alquiler_local',
        'sueldos_admin',
        'servicios_oficina',
        'impuestos_fijos',
        'honorario_adrian_default_monto',
        'honorario_adrian_default_pct',
        'honorario_modo_default',
        'eventos_estimados_mes',
        'updated_at',
        'updated_by',
      ],
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
