import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/evento.dart';
import '../../../models/cliente.dart';
import '../../../models/servicio.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/uuid_utils.dart';

/// Repositorio de Eventos — Offline-First.
///
/// Centraliza todo acceso a eventos, servicios del catálogo,
/// y eventos_servicios (presupuesto).
class EventosRepository {
  final SyncEngine _syncEngine;
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  EventosRepository(this._supabase, this._connectivity, this._syncEngine);

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// Lista de eventos con cliente join, opcionalmente filtrados por modalidad.
  Future<List<Evento>> getAll({String? modalidad}) async {
    final db = await LocalDatabase.instance;

    String query = '''
      SELECT e.*, c.nombre_completo as cliente_nombre, c.telefono as cliente_telefono, c.email as cliente_email, c.created_at as cliente_created_at
      FROM eventos e
      LEFT JOIN clientes c ON e.cliente_id = c.id
    ''';

    final List<dynamic> args = [];
    if (modalidad != null) {
      query += ' WHERE e.modalidad = ?';
      args.add(modalidad);
    }
    query += ' ORDER BY e.fecha_evento DESC';

    final rows = await db.rawQuery(query, args);

    return rows.map(_eventoFromLocalRow).where((e) => e.estado != EstadoEvento.cancelado).toList();
  }

  /// Obtiene un evento por ID con su cliente.
  Future<Evento?> getById(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT e.*, c.nombre_completo as cliente_nombre, c.telefono as cliente_telefono, c.email as cliente_email
      FROM eventos e LEFT JOIN clientes c ON e.cliente_id = c.id
      WHERE e.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return _eventoFromLocalRow(rows.first);
  }

  /// Catálogo de servicios.
  /// Incluye los servicios globales (evento_id IS NULL) y los exclusivos de este evento.
  Future<List<Servicio>> getCatalogo({String? eventoId, bool includeArchived = false}) async {
    final db = await LocalDatabase.instance;
    
    String query = 'SELECT * FROM servicios WHERE ';
    if (!includeArchived) {
      query += '(is_archived = 0 OR is_archived IS NULL) AND ';
    } else {
      query += 'is_archived = 1 AND ';
    }
    query += '(evento_id IS NULL';
    List<dynamic> args = [];
    
    if (eventoId != null) {
      query += ' OR evento_id = ?';
      args.add(eventoId);
    }
    
    query += ') ORDER BY nombre ASC';
    final rows = await db.rawQuery(query, args);

    if (rows.isEmpty && _connectivity.currentStatus == AppConnectivity.online) {
      await _pullServiciosFromCloud(db);
      final freshRows = await db.rawQuery(query, args);
      return freshRows.map((r) => Servicio.fromJson(r)).toList();
    }

    return rows.map((r) => Servicio.fromJson(r)).toList();
  }

  /// Presupuesto de un evento (eventos_servicios).
  Future<List<EventosServicios>> getPresupuesto(String eventoId) async {
    final db = await LocalDatabase.instance;

    final rows = await db.rawQuery('''
      SELECT es.*, s.nombre as servicio_nombre, s.costo_base, s.margen_ganancia
      FROM eventos_servicios es
      LEFT JOIN servicios s ON es.servicio_id = s.id
      WHERE es.evento_id = ?
    ''', [eventoId]);

    return rows.map((r) {
      return EventosServicios(
        id: r['id'] as String,
        eventoId: r['evento_id'] as String,
        servicioId: r['servicio_id'] as String,
        precioFinalAcordado: (r['precio_final_acordado'] as num).toDouble(),
        cantidad: (r['cantidad'] as num?)?.toDouble() ?? 1.0,
        grupo: r['grupo'] as String?,
        comboOrden: (r['combo_orden'] as num?)?.toInt() ?? 0,
        esExtra: (r['es_extra'] ?? 0) == 1,
        detalleServicio: r['detalle_servicio'] as String?,
        servicio: r['servicio_nombre'] != null ? Servicio(
          id: r['servicio_id'] as String,
          nombre: r['servicio_nombre'] as String,
          categoria: '',
          costoBase: r['costo_base'] != null ? (r['costo_base'] as num).toDouble() : null,
        ) : Servicio(
          id: r['servicio_id'] as String,
          nombre: (r['detalle_servicio'] as String?)?.split('\n').first ?? 'Servicio Ad-hoc',
          categoria: 'Personalizado',
        ),
      );
    }).toList();
  }

  // ── ESCRITURA ─────────────────────────────────────────────────────────────

  /// Crea un evento completo: cliente (si nuevo) + evento + servicios.
  Future<String> crearEventoCompleto({
    String? id,
    String? clienteId,
    String? nombreCliente,
    String? telefonoCliente,
    String? emailCliente,
    required String tipoEvento,
    required DateTime fechaEvento,
    int cantidadCuotas = 1,
    String modalidad = 'particular',
    String? observaciones,
    /// [lineaId] -> { 'servicio_id', 'precio', 'cantidad', 'grupo', 'combo_orden', 'detalle_servicio' } (mismo servicio varias filas)
    required Map<String, Map<String, dynamic>> serviciosSeleccionados,
  }) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().toUtc().toIso8601String();

    // 1. Crear cliente si no existe
    String finalClienteId;
    if (clienteId != null) {
      finalClienteId = clienteId;
    } else {
      finalClienteId = UuidUtils.generate();
      final clienteData = {
        'id': finalClienteId,
        'nombre_completo': nombreCliente ?? '',
        'telefono': telefonoCliente,
        'email': (emailCliente?.isEmpty ?? true) ? null : emailCliente,
        'created_at': now,
      };
      await db.insert('clientes', clienteData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(tabla: 'clientes', operacion: SyncOperation.insert, registroId: finalClienteId, payload: clienteData);
    }

    // 2. Crear evento
    final eventoId = id ?? UuidUtils.generate();
    final fechaStr = '${fechaEvento.year}-${fechaEvento.month.toString().padLeft(2, '0')}-${fechaEvento.day.toString().padLeft(2, '0')}';
    final eventoData = {
      'id': eventoId,
      'cliente_id': finalClienteId,
      'tipo': tipoEvento,
      'fecha_evento': fechaStr,
      'cantidad_cuotas': cantidadCuotas,
      'estado': 'Planificacion',
      'modalidad': modalidad,
      'observaciones': observaciones,
      'created_at': now,
    };
    await db.insert('eventos', eventoData, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(tabla: 'eventos', operacion: SyncOperation.insert, registroId: eventoId, payload: eventoData);

    // 3. Crear presupuesto (servicios)
    for (final entry in serviciosSeleccionados.entries) {
      final lineaId = entry.key;
      final v = entry.value;
      final servicioId = (v['servicio_id'] as String?)?.trim() ?? lineaId;
      final esData = {
        'id': lineaId,
        'evento_id': eventoId,
        'servicio_id': servicioId,
        'precio_final_acordado': v['precio'] ?? 0.0,
        'cantidad': v['cantidad'] ?? 1.0,
        'grupo': v['grupo'],
        'combo_orden': v['combo_orden'] ?? 0,
        'detalle_servicio': v['detalle_servicio'],
        'es_extra': (v['es_extra'] == true || v['es_extra'] == 1) ? 1 : 0,
      };
      await db.insert('eventos_servicios', esData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(
        tabla: 'eventos_servicios',
        operacion: SyncOperation.insert,
        registroId: lineaId,
        payload: esData,
      );
    }

    debugPrint('✅ Evento creado localmente: $eventoId');
    return eventoId;
  }

  /// Actualiza presupuesto de un evento existente.
  Future<void> actualizarPresupuesto(String eventoId, Map<String, Map<String, dynamic>> servicios) async {
    final db = await LocalDatabase.instance;

    final oldRows = await db.query(
      'eventos_servicios',
      columns: ['id'],
      where: 'evento_id = ?',
      whereArgs: [eventoId],
    );
    final newLineaIds = servicios.keys.toSet();
    for (final row in oldRows) {
      final id = row['id'] as String;
      if (!newLineaIds.contains(id)) {
        await SyncQueue.enqueue(
          tabla: 'eventos_servicios',
          operacion: SyncOperation.delete,
          registroId: id,
          payload: {'id': id, 'evento_id': eventoId},
        );
      }
    }

    await db.delete('eventos_servicios', where: 'evento_id = ?', whereArgs: [eventoId]);

    for (final entry in servicios.entries) {
      final lineaId = entry.key;
      final v = entry.value;
      final servicioId = (v['servicio_id'] as String?)?.trim() ?? lineaId;
      final esData = {
        'id': lineaId,
        'evento_id': eventoId,
        'servicio_id': servicioId,
        'precio_final_acordado': v['precio'] ?? 0.0,
        'cantidad': v['cantidad'] ?? 1.0,
        'grupo': v['grupo'],
        'combo_orden': v['combo_orden'] ?? 0,
        'detalle_servicio': v['detalle_servicio'],
        'es_extra': (v['es_extra'] == true || v['es_extra'] == 1) ? 1 : 0,
      };
      await db.insert('eventos_servicios', esData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(
        tabla: 'eventos_servicios',
        operacion: SyncOperation.insert,
        registroId: lineaId,
        payload: esData,
      );
    }

  }

  /// Crea un nuevo servicio en el catálogo.
  /// Si eventoId es nulo, es un servicio global.
  Future<String> crearServicio({
    required String nombre,
    String categoria = 'Personalizado',
    double costoBase = 0.0,
    String? eventoId,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    
    final data = {
      'id': id,
      'nombre': nombre,
      'categoria': categoria,
      'costo_base': costoBase,
      'evento_id': eventoId,
    };

    await db.insert('servicios', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(tabla: 'servicios', operacion: SyncOperation.insert, registroId: id, payload: data);

    return id;
  }

  /// Actualiza un servicio existente en el catálogo.
  Future<void> actualizarServicio(String id, Map<String, dynamic> data) async {
    final db = await LocalDatabase.instance;
    await db.update('servicios', data, where: 'id = ?', whereArgs: [id]);
    
    final row = await db.query('servicios', where: 'id = ?', whereArgs: [id]);
    if (row.isNotEmpty) {
      await SyncQueue.enqueue(
        tabla: 'servicios', 
        operacion: SyncOperation.update, 
        registroId: id, 
        payload: row.first,
      );
    }

  }

  /// Elimina servicios creados para un evento que no se confirmó.
  Future<void> borrarServiciosTemporales(String eventoId) async {
    final db = await LocalDatabase.instance;
    // 1. Obtener los IDs de los servicios vinculados a este evento provisional
    final rows = await db.query('servicios', where: 'evento_id = ?', whereArgs: [eventoId]);
    if (rows.isEmpty) return;
    
    final ids = rows.map((r) => r['id'] as String).toList();
    
    // 2. Borrado local
    await db.delete('servicios', where: 'evento_id = ?', whereArgs: [eventoId]);
    
    // 3. Limpieza de cola de sincronización
    for (final id in ids) {
      await _removeFromQueue('servicios', id);
      await SyncQueue.enqueue(
        tabla: 'servicios',
        operacion: SyncOperation.delete,
        registroId: id,
        payload: {},
      );
    }
  }

  /// Purgue de servicios huérfanos: Elimina servicios que tengan un eventoId 
  /// pero que NO estén en la lista de servicios del presupuesto oficial.
  Future<void> purgarServiciosHuerfanos(String eventoId, List<String> idsEnPresupuesto) async {
    final db = await LocalDatabase.instance;
    
    // Buscamos servicios vinculados a este evento que NO estén en el presupuesto
    final query = idsEnPresupuesto.isEmpty 
      ? 'SELECT id FROM servicios WHERE evento_id = ?'
      : 'SELECT id FROM servicios WHERE evento_id = ? AND id NOT IN (${idsEnPresupuesto.map((_) => '?').join(',')})';
    
    final args = [eventoId, ...idsEnPresupuesto];
    final rows = await db.rawQuery(query, args);
    
    if (rows.isEmpty) return;
    
    final idsABorrar = rows.map((r) => r['id'] as String).toList();
    debugPrint('🧹 Purgando ${idsABorrar.length} servicios huérfanos del evento $eventoId');
    
    for (final id in idsABorrar) {
      await eliminarServicio(id);
    }
  }

  /// Archiva un servicio específico por ID (Soft Delete).
  Future<void> eliminarServicio(String id) async {
    final db = await LocalDatabase.instance;
    await db.update('servicios', {'is_archived': 1}, where: 'id = ?', whereArgs: [id]);
    
    final row = await db.query('servicios', where: 'id = ?', whereArgs: [id]);
    if (row.isNotEmpty) {
      await SyncQueue.enqueue(
        tabla: 'servicios', 
        operacion: SyncOperation.update, 
        registroId: id, 
        payload: row.first,
      );
    }
  }
  
  /// Restaura un servicio archivado (vuelve a estar disponible).
  Future<void> restaurarServicio(String id) async {
    final db = await LocalDatabase.instance;
    await db.update('servicios', {'is_archived': 0}, where: 'id = ?', whereArgs: [id]);
    
    final row = await db.query('servicios', where: 'id = ?', whereArgs: [id]);
    if (row.isNotEmpty) {
      await SyncQueue.enqueue(
        tabla: 'servicios', 
        operacion: SyncOperation.update, 
        registroId: id, 
        payload: row.first,
      );
    }

  }

  /// Elimina definitivamente un servicio (físico).
  Future<void> eliminarServicioDefinitivo(String id) async {
    final db = await LocalDatabase.instance;
    await db.delete('servicios', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'servicios', operacion: SyncOperation.delete, registroId: id, payload: {});

  }

  /// Actualiza información básica del evento.
  Future<void> actualizarEventoInfo(String eventoId, {String? tipo, String? observaciones}) async {
    final db = await LocalDatabase.instance;
    final Map<String, dynamic> data = {};
    if (tipo != null) data['tipo'] = tipo;
    if (observaciones != null) data['observaciones'] = observaciones;

    if (data.isEmpty) return;

    await db.update('eventos', data, where: 'id = ?', whereArgs: [eventoId]);
    await SyncQueue.enqueue(
      tabla: 'eventos',
      operacion: SyncOperation.update,
      registroId: eventoId,
      payload: {'id': eventoId, ...data},
    );

  }

  /// Persiste el % de bonificación global acordado (sobre presupuesto total del evento).
  Future<void> actualizarBonificacionGlobalPct(String eventoId, double? porcentaje) async {
    final db = await LocalDatabase.instance;
    final data = <String, dynamic>{
      'bonificacion_global_pct': porcentaje,
    };
    await db.update('eventos', data, where: 'id = ?', whereArgs: [eventoId]);
    await SyncQueue.enqueue(
      tabla: 'eventos',
      operacion: SyncOperation.update,
      registroId: eventoId,
      payload: {'id': eventoId, ...data},
    );

  }

  /// Actualiza el estado de un evento.
  Future<void> actualizarEstado(String eventoId, EstadoEvento nuevoEstado) async {
    final estadoStr = _estadoToString(nuevoEstado);
    final db = await LocalDatabase.instance;
    await db.update('eventos', {'estado': estadoStr}, where: 'id = ?', whereArgs: [eventoId]);
    await SyncQueue.enqueue(
      tabla: 'eventos',
      operacion: SyncOperation.update,
      registroId: eventoId,
      payload: {'id': eventoId, 'estado': estadoStr},
    );

  }

  /// Actualiza la cantidad de cuotas.
  Future<void> actualizarCuotas(String eventoId, int nuevasCuotas) async {
    final db = await LocalDatabase.instance;
    await db.update('eventos', {'cantidad_cuotas': nuevasCuotas}, where: 'id = ?', whereArgs: [eventoId]);
    await SyncQueue.enqueue(
      tabla: 'eventos',
      operacion: SyncOperation.update,
      registroId: eventoId,
      payload: {'id': eventoId, 'cantidad_cuotas': nuevasCuotas},
    );

  }

  // ── ACTUALIZAR FECHA ───────────────────────────────────────────────────────
  Future<void> actualizarFecha(String eventoId, DateTime nuevaFecha) async {
    final fechaStr = '${nuevaFecha.year}-${nuevaFecha.month.toString().padLeft(2, '0')}-${nuevaFecha.day.toString().padLeft(2, '0')}';
    final db = await LocalDatabase.instance;
    await db.update('eventos', {'fecha_evento': fechaStr}, where: 'id = ?', whereArgs: [eventoId]);
    await SyncQueue.enqueue(
      tabla: 'eventos',
      operacion: SyncOperation.update,
      registroId: eventoId,
      payload: {'id': eventoId, 'fecha_evento': fechaStr},
    );

  }

  // ── REALTIME ──────────────────────────────────────────────────────────────

  RealtimeChannel subscribeToChanges(void Function() onUpdate) {
    final channel = _supabase.channel('public:eventos_repo_changes');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'eventos',
      callback: (_) {
        _refreshLocal().then((_) => onUpdate());
      },
    ).subscribe();
    return channel;
  }

  /// Escucha cambios en tiempo real para un evento específico y su presupuesto.
  RealtimeChannel subscribeToEvent(String eventoId, void Function() onUpdate) {
    debugPrint('🔔 Suscribiendo a cambios en tiempo real para evento: $eventoId');
    final channel = _supabase.channel('public:evento_detalle_$eventoId');
    
    // Cambios en el evento (estado, fecha, etc)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'eventos',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: eventoId,
      ),
      callback: (payload) {
        debugPrint('🔔 Realtime: Cambio detectado en evento');
        onUpdate();
      },
    );

    // Cambios en el presupuesto
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'eventos_servicios',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'evento_id',
        value: eventoId,
      ),
      callback: (payload) {
        debugPrint('🔔 Realtime: Cambio detectado en presupuesto');
        onUpdate();
      },
    );

    channel.subscribe();
    return channel;
  }

  // ── PULL FROM CLOUD ───────────────────────────────────────────────────────

  Future<void> _pullEventosFromCloud(Database db, {bool prune = false}) async {
    try {
      final response = await _supabase.from('eventos').select().order('fecha_evento', ascending: false);
      final List<dynamic> list = response as List;
      final cloudIds = list.map((r) => r['id'] as String).toSet();

      // IDs con cambios locales pendientes
      final pendingRows = await db.query('_sync_queue', columns: ['registro_id'], where: "tabla = 'eventos'");
      final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

      if (prune) {
        final localRows = await db.query('eventos', columns: ['id']);
        final localIds = localRows.map((r) => r['id'] as String).toList();
        final orphans = localIds.where((id) => !cloudIds.contains(id)).toList();

        if (orphans.isNotEmpty) {
          final List<String> toDelete = [];
          for (final id in orphans) {
            final inQueue = await db.query('_sync_queue', where: "tabla = 'eventos' AND registro_id = ?", whereArgs: [id]);
            if (inQueue.isEmpty) toDelete.add(id);
          }
          if (toDelete.isNotEmpty) {
            debugPrint('🧹 Purgando ${toDelete.length} eventos eliminados en cloud...');
            await db.delete('eventos', where: "id IN (${toDelete.map((_) => '?').join(',')})", whereArgs: toDelete);
          }
        }
      }

      final localPctRows = await db.query('eventos', columns: ['id', 'bonificacion_global_pct']);
      final preservedPctById = <String, double?>{
        for (final r in localPctRows)
          r['id'] as String: r['bonificacion_global_pct'] != null
              ? (r['bonificacion_global_pct'] as num).toDouble()
              : null,
      };

      final batch = db.batch();
      
      // Aseguramos de descargar también a los clientes (previniendo nombres nulos)
      try {
        final clientIds = list.map((r) => r['cliente_id'] as String).toSet().toList();
        if (clientIds.isNotEmpty) {
          // Process in chunks of 100 to avoid long query parameters
          for (var i = 0; i < clientIds.length; i += 100) {
            final chunk = clientIds.sublist(i, i + 100 > clientIds.length ? clientIds.length : i + 100);
            final clientResponse = await _supabase.from('clientes').select('id, nombre_completo, telefono, email').inFilter('id', chunk);
            for (final cRow in clientResponse as List) {
              batch.insert('clientes', {
                'id': cRow['id'],
                'nombre_completo': cRow['nombre_completo'],
                'telefono': cRow['telefono'],
                'email': cRow['email'],
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
      } catch (ce) {
        debugPrint('⚠️ Error al asegurar clientes vinculados: $ce');
      }

      for (final row in list) {
        final id = row['id'] as String;
        if (pendingIds.contains(id)) continue;

        final preservedPct = preservedPctById[id];
        final cloudPct = row['bonificacion_global_pct'] != null
            ? double.tryParse(row['bonificacion_global_pct'].toString())
            : null;

        batch.insert('eventos', {
          'id': row['id'],
          'cliente_id': row['cliente_id'],
          'tipo': row['tipo'],
          'fecha_evento': row['fecha_evento'],
          'cantidad_cuotas': row['cantidad_cuotas'] ?? 1,
          'modalidad': row['modalidad'] ?? 'particular',
          'estado': row['estado'] ?? 'Planificacion',
          'pin_operador': row['pin_operador'],
          'observaciones': row['observaciones'],
          'bonificacion_global_pct': cloudPct ?? preservedPct,
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      debugPrint('📥 Eventos: ${list.length} sincronizados');
    } catch (e) {
      debugPrint('⚠️ Error pull eventos: $e');
    }
  }

  String _lineaIdEventoServicioCloud(Map<String, dynamic> r, String eventoIdFallback, int indexInList) {
    var k = (r['id'] as String?)?.trim() ?? '';
    if (k.length == 36) return k;
    final eid = (r['evento_id'] as String?)?.trim() ?? eventoIdFallback;
    final sid = (r['servicio_id'] as String?)?.trim() ?? '';
    if (eid.isEmpty || sid.isEmpty) return '';
    return UuidUtils.lineaIdDeterministic('es', eid, sid, indexInList);
  }

  Future<void> _pullPresupuestoByEvento(Database db, String eventoId, {bool prune = false}) async {
    try {
      final response = await _supabase.from('eventos_servicios').select().eq('evento_id', eventoId);
      final List<dynamic> list = response as List;
      
      final cloudKeys = <String>{};
      for (var i = 0; i < list.length; i++) {
        final r = list[i] as Map<String, dynamic>;
        final id = _lineaIdEventoServicioCloud(r, eventoId, i);
        if (id.isNotEmpty) cloudKeys.add(id);
      }

      // Claves con cambios locales pendientes
      final pendingRows = await db.query('_sync_queue', columns: ['registro_id'], where: "tabla = 'eventos_servicios'");
      final pendingKeys = pendingRows.map((r) => r['registro_id'] as String).toSet();

      if (prune) {
        final localRows = await db.query('eventos_servicios', where: 'evento_id = ?', whereArgs: [eventoId]);
        final orphans = localRows.where((r) {
          final id = r['id'] as String? ?? '';
          return id.isNotEmpty && !cloudKeys.contains(id);
        }).toList();

        if (orphans.isNotEmpty) {
          for (final r in orphans) {
            final key = r['id'] as String? ?? '';
            final inQueue = await db.query('_sync_queue', 
              where: "tabla = 'eventos_servicios' AND registro_id = ?", 
              whereArgs: [key]
            );
            if (inQueue.isEmpty) {
              await db.delete('eventos_servicios', 
                where: 'id = ?', 
                whereArgs: [key]
              );
            }
          }
        }
      }

      final batch = db.batch();
      for (var i = 0; i < list.length; i++) {
        final row = list[i] as Map<String, dynamic>;
        final rid = _lineaIdEventoServicioCloud(row, eventoId, i);
        if (rid.isEmpty) continue;
        if (pendingKeys.contains(rid)) continue;

        batch.insert('eventos_servicios', {
          'id': rid,
          'evento_id': row['evento_id'] ?? eventoId,
          'servicio_id': row['servicio_id'],
          'precio_final_acordado': row['precio_final_acordado'],
          'cantidad': row['cantidad'] ?? 1.0,
          'grupo': row['grupo'],
          'combo_orden': row['combo_orden'] ?? 0,
          'detalle_servicio': row['detalle_servicio'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull presupuesto: $e');
    }
  }

  Future<void> _pullServiciosFromCloud(Database db) async {
    try {
      final response = await _supabase.from('servicios').select();
      final batch = db.batch();
      for (final row in (response as List)) {
        batch.insert('servicios', {
          'id': row['id'],
          'nombre': row['nombre'],
          'costo_base': row['costo_base'],
          'margen_ganancia': row['margen_ganancia'],
          'is_archived': row['is_archived'] == true ? 1 : 0,
          'evento_id': row['evento_id'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
      debugPrint('📥 Servicios: ${response.length} sincronizados');
    } catch (e) {
      debugPrint('⚠️ Error pull servicios: $e');
    }
  }

  Future<void> _refreshLocal() async {
    final db = await LocalDatabase.instance;
    await _pullEventosFromCloud(db);
  }

  Future<void> forceRefresh() async => _refreshLocal();

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Evento _eventoFromLocalRow(Map<String, dynamic> row) {
    final clienteData = row['cliente_nombre'] != null
        ? {
            'id': row['cliente_id'],
            'nombre_completo': row['cliente_nombre'],
            'telefono': row['cliente_telefono'],
            'email': row['cliente_email'],
          }
        : null;

    return Evento(
      id: row['id'] as String,
      clienteId: row['cliente_id'] as String,
      tipo: row['tipo'] as String,
      fechaEvento: DateTime.parse(row['fecha_evento'] as String),
      estado: _parseEstado(row['estado'] as String? ?? 'Planificacion'),
      cantidadCuotas: (row['cantidad_cuotas'] as int?) ?? 1,
      modalidad: (row['modalidad'] as String?) ?? 'particular',
      pinOperador: row['pin_operador'] as String?,
      observaciones: row['observaciones'] as String?,
      bonificacionGlobalPct: row['bonificacion_global_pct'] != null
          ? (row['bonificacion_global_pct'] as num).toDouble()
          : null,
      createdAt: row['created_at'] != null ? DateTime.tryParse(row['created_at'] as String) : null,
      cliente: clienteData != null ? Cliente.fromJson(clienteData) : null,
    );
  }

  EstadoEvento _parseEstado(String est) {
    switch (est) {
      case 'Confirmado': return EstadoEvento.confirmado;
      case 'Finalizado': return EstadoEvento.finalizado;
      case 'Cancelado': return EstadoEvento.cancelado;
      default: return EstadoEvento.planificacion;
    }
  }

  String _estadoToString(EstadoEvento est) {
    switch (est) {
      case EstadoEvento.confirmado: return 'Confirmado';
      case EstadoEvento.finalizado: return 'Finalizado';
      case EstadoEvento.cancelado: return 'Cancelado';
      case EstadoEvento.planificacion: return 'Planificacion';
    }
  }

  // _syncCrearEventoInmediato deprecado a favor de SyncEngine jerárquico.

  Future<void> _removeFromQueue(String tabla, String registroId) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: [tabla, registroId]);
  }

}

// ── Provider ────────────────────────────────────────────────────────────────

final eventosRepositoryProvider = Provider<EventosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  return EventosRepository(supabase, connectivity, syncEngine);
});
