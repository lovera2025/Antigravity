import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/local_database.dart';
import '../database/sync_queue.dart';
import '../utils/uuid_utils.dart';
import 'connectivity_service.dart';
import '../../features/cierre_caja/cierre_caja_sync_config.dart';
import '../../features/mi_empresa/repositories/finanzas_repository.dart';
import '../../features/eventos/services/mora_tracked_recovery.dart';
import '../../models/contrato_alumno.dart';

/// Estado del motor de sincronización.
enum SyncStatus {
  idle,
  wakingUp,
  syncing,
  probing,
  error,
  offline,
}

/// Resultado del último chequeo remoto (sin descargar datos).
class RemoteProbeInfo {
  final int remoteChangeCount;
  final DateTime? lastProbeAt;
  final bool probeSucceeded;
  final String? probeError;

  const RemoteProbeInfo({
    this.remoteChangeCount = 0,
    this.lastProbeAt,
    this.probeSucceeded = false,
    this.probeError,
  });

  bool get hasRemoteChanges => probeSucceeded && remoteChangeCount > 0;
}

/// Motor de sincronización — local-first, nube manual.
class SyncEngine {
  final ConnectivityService _connectivity;
  final SupabaseClient _supabase;

  /// Mapa que define qué columna usar para el filtro incremental en cada tabla.
  /// Todas las tablas usan updated_at para detectar creaciones Y ediciones.
  static const Map<String, String> _incrementalColumns = {
    'clientes': 'updated_at',
    'eventos': 'updated_at',
    'servicios': 'updated_at',
    'eventos_servicios': 'updated_at',
    'presupuestos': 'updated_at',
    'presupuesto_servicios': 'updated_at',
    'transacciones': 'updated_at',
    'egresos': 'updated_at',
    'contratos_alumnos': 'updated_at',
    'notas_operativas_contrato': 'updated_at',
    'pagos_contrato_alumno': 'updated_at',
    'invitados': 'updated_at',
    'solicitudes_cotizacion': 'updated_at',
    'prestamos_alquiler': 'updated_at',
    'prestamo_alquiler_lineas': 'updated_at',
    'pagos_prestamo_alquiler': 'updated_at',
    'calculos_rentabilidad': 'updated_at',
    'obligaciones_pago': 'updated_at',
    'caja_fuerte_movimientos': 'updated_at',
    'rentabilidad_config': 'updated_at',
    'cierre_caja_guia_movimientos': 'updated_at',
    'cierre_caja_anotaciones': 'updated_at',
  };

  /// Tablas con fecha calendario mínima para pull/probe (rollout cierre operativo).
  static const Set<String> _tablasFechaCorteCierre = {
    'cierre_caja_guia_movimientos',
    'cierre_caja_anotaciones',
  };

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  RemoteProbeInfo _remoteProbe = const RemoteProbeInfo();
  RemoteProbeInfo get remoteProbe => _remoteProbe;
  int get remotePendingCount => _remoteProbe.remoteChangeCount;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastUploadTime;
  DateTime? get lastUploadTime => _lastUploadTime;

  DateTime? _lastPullTime;
  DateTime? get lastPullTime => _lastPullTime;

  /// @deprecated Use [lastUploadTime] / [lastPullTime].
  DateTime? get lastSyncTime => _lastPullTime ?? _lastUploadTime;

  // Stream de estado
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  final _pendingController = StreamController<int>.broadcast();
  Stream<int> get pendingStream => _pendingController.stream;

  final _remoteProbeController = StreamController<RemoteProbeInfo>.broadcast();
  Stream<RemoteProbeInfo> get remoteProbeStream => _remoteProbeController.stream;

  StreamSubscription<AppConnectivity>? _connectivitySub;

  SyncEngine({
    required ConnectivityService connectivity,
    SupabaseClient? supabase,
  })  : _connectivity = connectivity,
        _supabase = supabase ?? Supabase.instance.client;

  /// Inicia el motor — solo contadores locales, sin sync automático.
  void start() {
    debugPrint('⚡ SyncEngine iniciado (modo local-first, sync manual)');

    SyncQueue.onChanged = () {
      unawaited(refreshPendingCount());
    };

    _connectivitySub = _connectivity.stream.listen((status) {
      if (status == AppConnectivity.offline) {
        _updateStatus(SyncStatus.offline);
      } else if (_status == SyncStatus.offline) {
        _updateStatus(SyncStatus.idle);
      }
    });

    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _updateStatus(SyncStatus.offline);
    } else {
      _updateStatus(SyncStatus.idle);
    }

    unawaited(refreshPendingCount());
    _remoteProbeController.add(_remoteProbe);
  }

  bool get _isBusy =>
      _status == SyncStatus.syncing ||
      _status == SyncStatus.wakingUp ||
      _status == SyncStatus.probing;

  /// Sube todos los cambios locales pendientes a la nube.
  Future<void> flushPending() async {
    if (_isBusy) {
      debugPrint('🔄 Sync ocupado, ignorando flush...');
      return;
    }
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _lastError = 'Sin conexión';
      _updateStatus(SyncStatus.offline);
      return;
    }

    try {
      _updateStatus(SyncStatus.wakingUp);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        return;
      }

      _updateStatus(SyncStatus.syncing);
      _lastError = null;

      var rounds = 0;
      const maxRounds = 50;
      while (rounds < maxRounds) {
        final progress = await _flushQueue(unlimited: true);
        if (!progress) break;
        rounds++;
      }

      _lastUploadTime = DateTime.now();
      _updateStatus(SyncStatus.idle);
      debugPrint('✅ Subida completada ($_pendingCount pendientes restantes)');
    } catch (e) {
      debugPrint('❌ Error flushPending: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
    } finally {
      await refreshPendingCount();
    }
  }

  /// Baja cambios remotos a SQLite (no sube pendientes locales).
  Future<void> pullRemote({bool reconcileDeletes = false}) async {
    if (_isBusy) return;
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _lastError = 'Sin conexión';
      _updateStatus(SyncStatus.offline);
      return;
    }

    try {
      _updateStatus(SyncStatus.wakingUp);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _lastError = 'Supabase no disponible';
        _updateStatus(SyncStatus.error);
        return;
      }

      _updateStatus(SyncStatus.syncing);
      _lastError = null;
      await _pullFromCloud();

      if (reconcileDeletes) {
        await _reconcileDeletes();
      }

      FinanzasRepository.invalidateProyeccionCache();
      _lastPullTime = DateTime.now();
      _updateStatus(SyncStatus.idle);
      debugPrint('✅ Bajada completada');

      await probeRemoteChanges();
    } catch (e) {
      debugPrint('❌ Error pullRemote: $e');
      _lastError = e.toString();
      _updateStatus(SyncStatus.error);
    } finally {
      await refreshPendingCount();
    }
  }

  /// Chequeo liviano: cuántos cambios hay en la nube que aún no bajaste.
  Future<RemoteProbeInfo> probeRemoteChanges() async {
    if (_connectivity.currentStatus == AppConnectivity.offline) {
      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: _remoteProbe.remoteChangeCount,
        lastProbeAt: _remoteProbe.lastProbeAt,
        probeSucceeded: false,
        probeError: 'Sin conexión',
      );
      _remoteProbeController.add(_remoteProbe);
      return _remoteProbe;
    }

    if (_isBusy) return _remoteProbe;

    try {
      _updateStatus(SyncStatus.probing);
      final awake = await _connectivity.wakeUpCloud();
      if (!awake) {
        _remoteProbe = RemoteProbeInfo(
          remoteChangeCount: _remoteProbe.remoteChangeCount,
          lastProbeAt: DateTime.now(),
          probeSucceeded: false,
          probeError: 'Nube no disponible',
        );
        _remoteProbeController.add(_remoteProbe);
        _updateStatus(SyncStatus.error);
        return _remoteProbe;
      }

      final db = await LocalDatabase.instance;
      var total = 0;
      for (final table in _incrementalColumns.keys) {
        total += await _probeTable(db, table);
      }

      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: total,
        lastProbeAt: DateTime.now(),
        probeSucceeded: true,
      );
      _remoteProbeController.add(_remoteProbe);
      _updateStatus(SyncStatus.idle);
      debugPrint('🔍 Probe remoto: $total cambios disponibles para bajar');
      return _remoteProbe;
    } catch (e) {
      debugPrint('❌ Error probeRemoteChanges: $e');
      _remoteProbe = RemoteProbeInfo(
        remoteChangeCount: _remoteProbe.remoteChangeCount,
        lastProbeAt: DateTime.now(),
        probeSucceeded: false,
        probeError: e.toString(),
      );
      _remoteProbeController.add(_remoteProbe);
      _updateStatus(SyncStatus.error);
      return _remoteProbe;
    }
  }

  /// Subir + bajar (solo cuando el usuario lo pide explícitamente).
  Future<void> syncBidirectional({bool reconcileDeletes = false}) async {
    await flushPending();
    if (_lastError != null && _status == SyncStatus.error) return;
    await pullRemote(reconcileDeletes: reconcileDeletes);
  }

  /// Alias de compatibilidad → bidireccional manual.
  Future<void> syncNow() => syncBidirectional();

  /// Borra todos los timestamps de último pull para forzar pull completo
  /// en la próxima sincronización. Útil para recuperar datos faltantes
  /// cuando se cambió de PC o se detectaron registros perdidos.
  Future<void> resetPullTimestamps() async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_meta');
    debugPrint('🔄 Timestamps de pull reseteados — el próximo pull será completo');
  }

  /// Resetea timestamps y hace pull completo de inmediato.
  Future<void> forceFullPull() async {
    await resetPullTimestamps();
    await pullRemote();
  }

  Future<int> _probeTable(Database db, String table) async {
    final dateColumn = _incrementalColumns[table];
    if (dateColumn == null) return 0;

    try {
      final claveMeta = 'last_pull_$table';
      final metaRows =
          await db.query('_sync_meta', where: 'clave = ?', whereArgs: [claveMeta]);
      final lastPullStr =
          metaRows.isNotEmpty ? metaRows.first['valor'] as String? : null;

      final countRes =
          await db.rawQuery('SELECT COUNT(*) as c FROM $table');
      final localCount = (countRes.first['c'] as int?) ?? 0;

      dynamic query = _supabase.from(table).select('id');

      if (lastPullStr != null) {
        query = query.gt(dateColumn, lastPullStr);
      } else if (localCount > 0) {
        final maxRes = await db.rawQuery(
          'SELECT MAX($dateColumn) as m FROM $table',
        );
        final maxLocal = maxRes.first['m'] as String?;
        if (maxLocal != null && maxLocal.isNotEmpty) {
          query = query.gt(dateColumn, maxLocal);
        } else {
          return 0;
        }
      }

      if (_tablasFechaCorteCierre.contains(table)) {
        query = query.gte('fecha', kCierreCajaSyncFechaCorte);
      }

      final response = await query.count(CountOption.exact);
      return response.count;
    } catch (e) {
      debugPrint('  ⚠️ Error probe $table: $e');
      return 0;
    }
  }

  /// Envía los cambios locales pendientes a la nube.
  /// Devuelve true si al menos una operación se completó con éxito.
  Future<bool> _flushQueue({bool unlimited = false}) async {
    final pending = await SyncQueue.getPending(limit: unlimited ? null : 50);
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
      if (table == 'cierre_caja_guia_movimientos' ||
          table == 'cierre_caja_anotaciones') return 5;

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
           final healed = await _attemptSelfHealing(entry);
           
           if (healed) {
             await SyncQueue.markPaused(entry.id!, 'ESPERANDO_PADRE: $e'); 
           } else {
             // Si el padre no existe localmente, es un error referencial insalvable localmente.
             // Incrementa los intentos. Al llegar a 10 se marcará como ERROR_PERMANENTE.
             final isPermanent = entry.intentos >= 9;
             final errorMsg = isPermanent ? 'ERROR_PERMANENTE: Padre no encontrado localmente' : 'ESPERANDO_PADRE: Padre no encontrado localmente';
             await SyncQueue.markFailed(entry.id!, errorMsg);
           }
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
  /// Devuelve true si encontró y re-encoló al menos un padre localmente.
  Future<bool> _attemptSelfHealing(SyncQueueEntry childEntry) async {
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
    bool anyParentHealed = false;
    bool hasAnyFkToCheck = false;

    for (final entry in parentDependencies.entries) {
      final fkField = entry.key;
      final parentTable = entry.value;
      
      final parentId = payload[fkField] as String?;
      if (parentId == null || parentId.isEmpty) continue;

      hasAnyFkToCheck = true;

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
          anyParentHealed = true;
          break;
        }
      }

      if (!parentFound) {
        debugPrint('  [Self-Healing] Padre $parentId no encontrado en ${potentialTables.join('/')} localmente.');
      }
    }

    return hasAnyFkToCheck ? anyParentHealed : false;
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
    final payload = _cleanForRemote(entry.tabla, entry.payload);

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
      _pullTable(db, 'clientes', 'updated_at'),
      _pullTable(db, 'servicios', 'updated_at'),
      _pullTable(db, 'eventos', 'updated_at'),
      _pullTable(db, 'eventos_servicios', 'updated_at', primaryKey: 'id'),
      _pullTable(db, 'presupuestos', 'updated_at'),
      _pullTable(db, 'presupuesto_servicios', 'updated_at', primaryKey: 'id'),
      _pullTable(db, 'transacciones', 'updated_at'),
      _pullTable(db, 'egresos', 'updated_at'),
      _pullTable(db, 'contratos_alumnos', 'updated_at'),
      _pullTable(db, 'notas_operativas_contrato', 'updated_at'),
      _pullTable(db, 'pagos_contrato_alumno', 'updated_at'),
      _pullTable(db, 'invitados', 'updated_at'),
      _pullTable(db, 'solicitudes_cotizacion', 'updated_at'),
      _pullTable(db, 'prestamos_alquiler', 'updated_at'),
      _pullTable(db, 'prestamo_alquiler_lineas', 'updated_at'),
      _pullTable(db, 'pagos_prestamo_alquiler', 'updated_at'),
      _pullTable(db, 'calculos_rentabilidad', 'updated_at'),
      _pullTable(db, 'obligaciones_pago', 'updated_at'),
      _pullTable(db, 'caja_fuerte_movimientos', 'updated_at'),
      _pullTable(db, 'rentabilidad_config', 'updated_at'),
      _pullTable(db, 'cierre_caja_guia_movimientos', 'updated_at'),
      _pullTable(db, 'cierre_caja_anotaciones', 'updated_at'),
    ]);

    try {
      final recalibrados = await MoraTrackedRecovery.reconciliarTodos(
        db: db,
        encolarSync: true,
      );
      if (recalibrados > 0) {
        debugPrint(
          '  🔧 Post-pull mora: $recalibrados contrato(s) recalibrados desde historial',
        );
      }
    } catch (e) {
      debugPrint('  ⚠️ Post-pull mora reconcile: $e');
    }

    debugPrint('📥 Pull completado');
  }

  /// Descarga y upsert de una tabla. Soporta pull incremental mediante _sync_meta.
  Future<void> _pullTable(Database db, String table, String? orderBy, {String primaryKey = 'id'}) async {
    try {
      final String claveMeta = 'last_pull_$table';
      // Consultar última fecha de sincronización exitosa
      final metaRows = await db.query('_sync_meta', where: 'clave = ?', whereArgs: [claveMeta]);
      final String? lastSyncStr = metaRows.isNotEmpty ? metaRows.first['valor'] as String : null;

      final String? dateColumn = _incrementalColumns[table];
      dynamic query = _supabase.from(table).select();

      // Guardar la marca de tiempo de inicio para esta sincronización (UTC)
      final String currentSyncStr = DateTime.now().toUtc().toIso8601String();

      if (lastSyncStr != null && dateColumn != null) {
        // Pull Incremental: traer solo lo nuevo/modificado
        query = query.gt(dateColumn, lastSyncStr);
        debugPrint('  📥 $table: Solicitando cambios incremental desde $lastSyncStr (usando $dateColumn)...');
      } else {
        debugPrint('  📥 $table: Solicitando pull completo...');
      }

      if (_tablasFechaCorteCierre.contains(table)) {
        query = query.gte('fecha', kCierreCajaSyncFechaCorte);
      }

      if (orderBy != null) {
        query = query.order(orderBy, ascending: false);
      }

      // Paginación: Supabase devuelve máx. 1000 filas por request.
      // Iteramos en páginas hasta agotar los registros disponibles.
      const int kPageSize = 1000;
      final allData = <Map<String, dynamic>>[];
      int fromIdx = 0;
      while (true) {
        final List<dynamic> page = await query.range(fromIdx, fromIdx + kPageSize - 1);
        final pageRows = page.cast<Map<String, dynamic>>();
        allData.addAll(pageRows);
        if (pageRows.length < kPageSize) break;
        fromIdx += kPageSize;
      }
      final rows = allData;

      if (rows.isEmpty) {
        // Aunque no haya nuevos registros, actualizamos el timestamp del último pull
        if (dateColumn != null) {
          await db.insert(
            '_sync_meta',
            {'clave': claveMeta, 'valor': currentSyncStr},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return;
      }

      // No pisar registros con cambios locales pendientes de subir.
      final pendingRows = await db.query(
        '_sync_queue',
        columns: ['registro_id'],
        where: 'tabla = ?',
        whereArgs: [table],
      );
      final pendingIds =
          pendingRows.map((r) => r['registro_id'] as String).toSet();

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

      Map<String, double>? preservedMoraOffsetByContratoId;
      if (table == 'contratos_alumnos') {
        final localOffsetRows = await db.query(
          'contratos_alumnos',
          columns: ['id', 'mora_cobrada_offset'],
        );
        preservedMoraOffsetByContratoId = {
          for (final r in localOffsetRows)
            r['id'] as String:
                (r['mora_cobrada_offset'] as num?)?.toDouble() ?? 0,
        };
      }

      final batch = db.batch();
      int skipped = 0;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (_tablasFechaCorteCierre.contains(table)) {
          final f = row['fecha']?.toString() ?? '';
          if (!cierreCajaFechaElegibleSync(f)) {
            skipped++;
            continue;
          }
        }
        final id = row['id'] as String?;
        if (id != null && pendingIds.contains(id)) {
          skipped++;
          continue;
        }
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
        } else if (table == 'contratos_alumnos' &&
            preservedMoraOffsetByContratoId != null) {
          final cid = cleanRow['id'] as String;
          final insertRow = Map<String, dynamic>.from(cleanRow);
          insertRow['mora_cobrada_offset'] =
              preservedMoraOffsetByContratoId[cid] ?? 0;
          batch.insert(table, insertRow, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          batch.insert(table, cleanRow, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);

      // Guardar última marca de tiempo de sincronización exitosa
      if (dateColumn != null) {
        await db.insert(
          '_sync_meta',
          {'clave': claveMeta, 'valor': currentSyncStr},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

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

  /// Filtra payload antes de subir: solo columnas de nube, sin campos solo SQLite.
  Map<String, dynamic> _cleanForRemote(String table, Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('mora_cobrada_offset');
    copy.remove('line_kind');

    final cleaned = _cleanForSqlite(table, copy);

    if (table == 'contratos_alumnos') {
      if (cleaned.containsKey('nombres_acompanantes')) {
        cleaned['nombres_acompanantes'] =
            ContratoAlumno.acompanantesForRemote(cleaned['nombres_acompanantes']);
      }
      if (cleaned.containsKey('contrato_firmado')) {
        final v = cleaned['contrato_firmado'];
        if (v is int) cleaned['contrato_firmado'] = v != 0;
      }
    }

    return cleaned;
  }

  /// Limpia un mapa de datos para que solo contenga columnas de la tabla SQLite.
  Map<String, dynamic> _cleanForSqlite(String table, Map<String, dynamic> row) {
    const tableColumns = {
      'clientes': ['id', 'nombre_completo', 'telefono', 'email', 'is_archived', 'created_at', 'updated_at'],
      'eventos': ['id', 'cliente_id', 'tipo', 'fecha_evento', 'cantidad_cuotas', 'modalidad', 'estado', 'pin_operador', 'observaciones', 'bonificacion_global_pct', 'created_at', 'updated_at'],
      'servicios': ['id', 'nombre', 'categoria', 'costo_base', 'margen_ganancia', 'costo_interno', 'evento_id', 'is_archived', 'updated_at'],
      'eventos_servicios': ['id', 'evento_id', 'servicio_id', 'precio_final_acordado', 'cantidad', 'grupo', 'detalle_servicio', 'combo_orden', 'es_extra', 'updated_at'],
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
        'updated_at',
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
        'es_extra',
        'updated_at',
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
        'updated_at',
      ],
      'egresos': ['id', 'evento_id', 'monto', 'proveedor', 'categoria', 'fecha', 'created_by', 'medio_pago', 'updated_at'],
      'contratos_alumnos': ['id', 'evento_id', 'nombre_alumno', 'institucion', 'cantidad_acompanantes', 'monto_total_pactado', 'saldo_deudor', 'cuotas_pagadas', 'total_cuotas', 'nombres_acompanantes', 'dia_vencimiento_mensual', 'mesa_extra_precio', 'mesa_extra_cuotas', 'mesa_extra_cuotas_pagadas', 'mesa_extra_cantidad', 'mesas_extra_estado', 'sillas_extra_cantidad', 'sillas_extra_cuotas', 'sillas_extra_precio_total', 'sillas_extra_cuotas_pagadas', 'mesa_extra_pagado', 'sillas_extra_pagado', 'curso_division', 'musica_elegida', 'numero_mesa', 'telefono', 'created_at', 'contrato_firmado', 'mora_pendiente_tracked', 'updated_at'],
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
        'updated_at',
      ],
      'invitados': ['id', 'evento_id', 'nombre_completo', 'dni', 'numero_mesa', 'estado_ingreso', 'intentos_fallidos', 'updated_at', 'created_at'],
      'solicitudes_cotizacion': ['id', 'cliente_nombre', 'cliente_celular', 'servicios_seleccionados', 'estado', 'updated_at'],
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
        'updated_at',
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
        'updated_at',
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
        'updated_at',
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
        'updated_at',
      ],
      'caja_fuerte_movimientos': [
        'id',
        'tipo',
        'monto',
        'nota',
        'created_at',
        'updated_at',
      ],
      'cierre_caja_guia_movimientos': [
        'id',
        'fecha',
        'tipo',
        'monto',
        'saldo_antes',
        'saldo_despues',
        'nota',
        'fecha_mov',
        'created_at',
        'updated_at',
      ],
      'cierre_caja_anotaciones': [
        'id',
        'fecha',
        'turno',
        'texto',
        'created_at',
        'updated_at',
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

  /// Reconcilia eliminaciones remotas comparando IDs cloud vs local.
  /// Solo aplica a tablas padre para limitar el número de queries.
  Future<void> _reconcileDeletes() async {
    final db = await LocalDatabase.instance;

    const reconcileTables = [
      'clientes', 'eventos', 'presupuestos',
      'contratos_alumnos', 'prestamos_alquiler', 'servicios',
    ];

    debugPrint('🔄 Reconciliación periódica de deletes remotos...');

    for (final table in reconcileTables) {
      try {
        // Obtener todos los IDs del cloud
        final cloudData = await _supabase.from(table).select('id');
        final cloudIds = (cloudData as List)
            .map((r) => (r as Map<String, dynamic>)['id'] as String)
            .toSet();

        // Obtener IDs locales
        final localRows = await db.query(table, columns: ['id']);

        // Excluir IDs pendientes en la cola de sync (no eliminar lo que aún no subió)
        final pendingRows = await db.query('_sync_queue',
            columns: ['registro_id'],
            where: "tabla = ?",
            whereArgs: [table]);
        final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

        int removed = 0;
        for (final row in localRows) {
          final localId = row['id'] as String;
          if (!cloudIds.contains(localId) && !pendingIds.contains(localId)) {
            await db.delete(table, where: 'id = ?', whereArgs: [localId]);
            removed++;
          }
        }

        if (removed > 0) {
          debugPrint('  🗑️ $table: $removed registros eliminados (no existen en cloud)');
        }
      } catch (e) {
        debugPrint('  ⚠️ Error reconciliando $table: $e');
      }
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

  Future<void> refreshPendingCount() async {
    _pendingCount = await SyncQueue.pendingCount;
    _pendingController.add(_pendingCount);
  }

  void _updateStatus(SyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    SyncQueue.onChanged = null;
    _connectivitySub?.cancel();
    _statusController.close();
    _pendingController.close();
    _remoteProbeController.close();
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

final remoteProbeProvider = StreamProvider<RemoteProbeInfo>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.remoteProbeStream;
});
