import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/presupuesto.dart';
import '../../../models/cliente.dart';
import '../../../models/servicio.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/uuid_utils.dart';
import 'eventos_repository.dart';

class PresupuestosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;
  final Ref _ref;

  PresupuestosRepository(this._supabase, this._connectivity, this._ref, this._syncEngine);

  // ── LECTURA ────────────────────────────────────────────────────────────────

  Future<List<Presupuesto>> getAll() async {
    final db = await LocalDatabase.instance;

    const query = '''
      SELECT p.*, c.nombre_completo as cliente_nombre, c.telefono as cliente_telefono, c.email as cliente_email
      FROM presupuestos p
      LEFT JOIN clientes c ON p.cliente_id = c.id
      ORDER BY p.created_at DESC
    ''';

    final rows = await db.rawQuery(query);

    if (_connectivity.currentStatus == AppConnectivity.online) {
      await _pullPresupuestosFromCloud(db);
      final freshRows = await db.rawQuery(query);
      return _mapRowsToPresupuestos(db, freshRows);
    }

    return _mapRowsToPresupuestos(db, rows);
  }

  Future<Presupuesto?> getById(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT p.*, c.nombre_completo as cliente_nombre, c.telefono as cliente_telefono, c.email as cliente_email
      FROM presupuestos p
      LEFT JOIN clientes c ON p.cliente_id = c.id
      WHERE p.id = ?
    ''', [id]);
    
    if (rows.isEmpty) return null;
    
    final budgets = await _mapRowsToPresupuestos(db, rows);
    return budgets.first;
  }

  // ── ESCRITURA ─────────────────────────────────────────────────────────────

  Future<String> crearPresupuesto({
    String? id, // <-- Parámetro de vinculación añadido
    String? clienteId,
    String? nombreCliente,
    String? telefonoCliente,
    String? emailCliente,
    required String tipoEvento,
    String? lugar,
    String? detalleAnclaje,
    int diasValidez = 7,
    String? instagram,
    String? telefonoPublicidad,
    required List<Map<String, dynamic>> servicios,
  }) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now();
    final nowIso = now.toUtc().toIso8601String();
    final fechaVencimiento = now.add(Duration(days: diasValidez));

    // 1. Cliente
    String finalClienteId;
    if (clienteId != null) {
      finalClienteId = clienteId;
    } else {
      finalClienteId = UuidUtils.generate();
      final clienteData = {
        'id': finalClienteId,
        'nombre_completo': nombreCliente ?? '',
        'telefono': telefonoCliente,
        'email': emailCliente,
        'created_at': nowIso,
      };
      await db.insert('clientes', clienteData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(tabla: 'clientes', operacion: SyncOperation.insert, registroId: finalClienteId, payload: clienteData);
    }

    // 2. Presupuesto
    final presupuestoId = id ?? UuidUtils.generate(); // <-- El sistema ahora respeta el ID de la sesión
    final presupuestoData = {
      'id': presupuestoId,
      'cliente_id': finalClienteId,
      'tipo_evento': tipoEvento,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
      'estado': 'activo',
      'instagram': instagram,
      'telefono': telefonoPublicidad,
      'notificado_vencimiento': 0,
      'created_at': nowIso,
    };
    await db.insert('presupuestos', presupuestoData);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.insert, registroId: presupuestoId, payload: presupuestoData);

    // 3. Servicios
    for (final s in servicios) {
      final psData = {
        'presupuesto_id': presupuestoId,
        'servicio_id': s['servicio_id'],
        'precio_final': s['precio_final'],
        'cantidad': s['cantidad'] ?? 1.0,
        'detalle_servicio': s['detalle_servicio'],
        'grupo': s['grupo'],
      };
      await db.insert('presupuesto_servicios', psData);
      await SyncQueue.enqueue(
        tabla: 'presupuesto_servicios', 
        operacion: SyncOperation.insert, 
        registroId: '${presupuestoId}_${s['servicio_id']}', 
        payload: psData
      );
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }

    return presupuestoId;
  }


  Future<void> confirmarPresupuesto(String id, {bool crearContratoSena = false}) async {
    final db = await LocalDatabase.instance;
    final p = await getById(id);
    if (p == null) return;

    // 1. Crear Evento Real
    final repoEventos = _ref.read(eventosRepositoryProvider);
    // Convertir servicios de presupuesto a formato compatible con el nuevo selector {'precio': x, 'cantidad': y}
    final Map<String, Map<String, dynamic>> serviciosMap = { 
      for (var s in p.servicios) s.servicioId : {
        'precio': s.precioFinal,
        'cantidad': s.cantidad,
      }
    };
    
    await repoEventos.crearEventoCompleto(
      clienteId: p.clienteId,
      tipoEvento: p.tipoEvento,
      fechaEvento: DateTime.now().add(const Duration(days: 30)), 
      modalidad: 'particular',
      observaciones: p.detalleAnclaje,
      serviciosSeleccionados: serviciosMap,
    );

    // 2. Marcar como confirmado
    await db.update('presupuestos', {'estado': 'confirmado'}, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: 'presupuestos', 
      operacion: SyncOperation.update, 
      registroId: id, 
      payload: {'id': id, 'estado': 'confirmado'}
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  Future<void> eliminar(String id) async {
    final db = await LocalDatabase.instance;
    await db.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [id]);
    await db.delete('presupuestos', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.delete, registroId: id, payload: {});
    
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  Future<void> actualizar({
    required String id,
    required String tipoEvento,
    String? lugar,
    String? detalleAnclaje,
    int diasValidez = 7,
    required List<Map<String, dynamic>> servicios,
  }) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now();
    final nowIso = now.toUtc().toIso8601String();
    
    // 1. Actualizar presupuesto base
    final presupuestoData = {
      'tipo_evento': tipoEvento,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      'fecha_vencimiento': now.add(Duration(days: diasValidez)).toUtc().toIso8601String(),
    };
    
    await db.update('presupuestos', presupuestoData, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.update, registroId: id, payload: presupuestoData);

    // 2. Reemplazar servicios (borrar y reinsertar)
    await db.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [id]);
    
    for (final s in servicios) {
      final psData = {
        'presupuesto_id': id,
        'servicio_id': s['servicio_id'],
        'precio_final': s['precio_final'],
        'cantidad': s['cantidad'] ?? 1.0,
        'detalle_servicio': s['detalle_servicio'],
        'grupo': s['grupo'],
      };
      await db.insert('presupuesto_servicios', psData);
    }
    
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  Future<void> actualizarConfiguracionIntegral({
    required String presupuestoId,
    required String? vendedorNombre,
    required String? tituloFestejado,
    required String? telefonoPublicidad,
    required String? instagram,
    required String? lugar,
    required String? detalleAnclaje,
    required DateTime fechaVencimiento,
    required String? clienteId,
    required String? clienteNombre,
    required String? clienteTelefono,
    required String? clienteEmail,
  }) async {
    final db = await LocalDatabase.instance;
    
    // 1. Actualizar Presupuesto
    final budgetData = {
      'vendedor_nombre': vendedorNombre,
      'titulo_festejado': tituloFestejado,
      'telefono': telefonoPublicidad,
      'instagram': instagram,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
    };
    
    await db.update('presupuestos', budgetData, where: 'id = ?', whereArgs: [presupuestoId]);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.update, registroId: presupuestoId, payload: budgetData);
    
    // 2. Actualizar Cliente (si aplica)
    if (clienteId != null) {
      final clientData = {
        'nombre_completo': clienteNombre ?? '',
        'telefono': clienteTelefono,
        'email': clienteEmail,
      };
      await db.update('clientes', clientData, where: 'id = ?', whereArgs: [clienteId]);
      await SyncQueue.enqueue(tabla: 'clientes', operacion: SyncOperation.update, registroId: clienteId, payload: clientData);
    }
    
    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Future<List<Presupuesto>> _mapRowsToPresupuestos(Database db, List<Map<String, dynamic>> rows) async {
    final List<Presupuesto> results = [];
    for (final row in rows) {
      final pid = row['id'] as String;
      
      // Cargar servicios vinculados
      final sRows = await db.rawQuery('''
        SELECT ps.*, s.nombre, s.categoria, s.costo_base, s.margen_ganancia
        FROM presupuesto_servicios ps
        LEFT JOIN servicios s ON ps.servicio_id = s.id
        WHERE ps.presupuesto_id = ?
      ''', [pid]);

      final List<Map<String, dynamic>> serviciosJson = sRows.map((sr) => {
        'presupuesto_id': sr['presupuesto_id'],
        'servicio_id': sr['servicio_id'],
        'precio_final': sr['precio_final'],
        'cantidad': sr['cantidad'],
        'detalle_servicio': sr['detalle_servicio'],
        'grupo': sr['grupo'],
        'servicios': {
          'id': sr['servicio_id'],
          'nombre': sr['nombre'] ?? sr['detalle_servicio'] ?? 'Servicio Ad-hoc',
          'categoria': sr['categoria'] ?? 'Personalizado',
          'costo_base': sr['costo_base'],
          'margen_ganancia': sr['margen_ganancia'],
        }
      }).toList();

      final fullJson = Map<String, dynamic>.from(row);
      fullJson['presupuesto_servicios'] = serviciosJson;
      fullJson['clientes'] = {
        'id': (row['cliente_id'] ?? 'unknown_id').toString(),
        'nombre_completo': row['cliente_nombre'] ?? 'CLIENTE DESCONOCIDO',
        'telefono': row['cliente_telefono'],
        'email': row['cliente_email'],
      };

      results.add(Presupuesto.fromJson(fullJson));
    }
    return results;
  }

  Future<void> _pullPresupuestosFromCloud(Database db) async {
    try {
      final pResp = await _supabase.from('presupuestos').select('*, presupuesto_servicios(*)');
      final list = pResp as List;
      
      final batch = db.batch();
      for (final row in list) {
        batch.insert('presupuestos', {
          'id': row['id'],
          'cliente_id': row['cliente_id'],
          'tipo_evento': row['tipo_evento'],
          'lugar': row['lugar'],
          'detalle_anclaje': row['detalle_anclaje'],
          'fecha_vencimiento': row['fecha_vencimiento'],
          'estado': row['estado'],
          'instagram': row['instagram'],
          'telefono': row['telefono'],
          'vendedor_nombre': row['vendedor_nombre'],
          'titulo_festejado': row['titulo_festejado'],
          'notificado_vencimiento': row['notificado_vencimiento'] == true ? 1 : 0,
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final servicios = row['presupuesto_servicios'] as List;
        for (final s in servicios) {
          batch.insert('presupuesto_servicios', {
            'presupuesto_id': s['presupuesto_id'],
            'servicio_id': s['servicio_id'],
            'precio_final': s['precio_final'],
            'cantidad': s['cantidad'] ?? 1.0,
            'detalle_servicio': s['detalle_servicio'],
            'grupo': s['grupo'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull presupuestos: $e');
    }
  }

  // _syncInmediato deprecado a favor de SyncEngine

  Future<void> _removeFromQueue(String tabla, String registroId) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: [tabla, registroId]);
  }

  Future<void> _removeQueueByPrefix(String tabla, String prefix) async {
    final db = await LocalDatabase.instance;
    await db.delete('_sync_queue', where: 'tabla = ? AND registro_id LIKE ?', whereArgs: [tabla, '$prefix%']);
  }
}

final presupuestosRepositoryProvider = Provider<PresupuestosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  return PresupuestosRepository(supabase, connectivity, ref, syncEngine);
});
