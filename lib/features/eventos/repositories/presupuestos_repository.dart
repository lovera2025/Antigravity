import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/presupuesto.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/uuid_utils.dart';
import 'eventos_repository.dart';

/// Se intentó confirmar un presupuesto cuyos ítems no están en esta PC.
///
/// No es un error del usuario ni un dato roto: los ítems existen, pero todavía
/// no bajaron de la nube. Confirmar igual crearía el evento vacío, así que se
/// frena y se le dice cómo destrabarlo.
class PresupuestoSinItemsException implements Exception {
  const PresupuestoSinItemsException();

  static const String mensaje =
      'Este presupuesto no tiene sus ítems cargados en esta PC, así que el '
      'evento se crearía sin monto.\n\n'
      'Bajá los datos de la nube y volvé a intentar: tocá el ícono de nube '
      'arriba en el Panel y elegí "Pull completo forzado".';

  @override
  String toString() => mensaje;
}

/// El presupuesto ya no está en esta PC (lo borraron en la otra y se bajó).
/// Antes se salía sin hacer nada y la pantalla igual decía "creado con éxito".
class PresupuestoNoEncontradoException implements Exception {
  const PresupuestoNoEncontradoException();

  static const String mensaje =
      'Este presupuesto ya no está en esta PC: puede que lo hayan borrado en la '
      'otra. Actualizá la lista y fijate si sigue.';

  @override
  String toString() => mensaje;
}

/// El presupuesto no trae fecha del evento: la confirmación la pide antes.
class PresupuestoSinFechaException implements Exception {
  const PresupuestoSinFechaException();

  static const String mensaje =
      'Este presupuesto no tiene la fecha del evento. Elegila para crearlo.';

  @override
  String toString() => mensaje;
}

/// El cliente del presupuesto no está en esta PC (la tarjeta dice "registro
/// corrupto / huérfano"): un evento así no aparece en el Panel.
class PresupuestoSinClienteException implements Exception {
  const PresupuestoSinClienteException();

  static const String mensaje =
      'El cliente de este presupuesto no está en esta PC. Primero hay que '
      'arreglar el cliente; después se crea el evento.';

  @override
  String toString() => mensaje;
}

/// Un presupuesto que ya tiene su evento no se borra.
class PresupuestoConEventoException implements Exception {
  const PresupuestoConEventoException();

  static const String mensaje =
      'Este presupuesto ya tiene su evento y no se borra: de él salen el lugar '
      'y los detalles que muestra el evento.';

  @override
  String toString() => mensaje;
}

class PresupuestosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;
  // El `Ref` ya no se usa: crear el evento es una cuenta estática sobre la
  // base (`EventosRepository.crearEventoEn`), dentro de la transacción.
  PresupuestosRepository(this._supabase, this._connectivity, Ref _, this._syncEngine);

  void _scheduleSync() {
    // Local-first: encolar ya ocurrió; subida manual vía nubecita.
  }

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// [pullRemoteWhenOnline]: legacy, ignorado — lectura solo local.
  Future<List<Presupuesto>> getAll({bool pullRemoteWhenOnline = false}) async {
    final db = await LocalDatabase.instance;

    const query = '''
      SELECT p.*, c.nombre_completo as cliente_nombre, c.telefono as cliente_telefono, c.email as cliente_email
      FROM presupuestos p
      LEFT JOIN clientes c ON p.cliente_id = c.id
      ORDER BY p.created_at DESC
    ''';

    final rows = await db.rawQuery(query);

    return _mapRowsToPresupuestos(db, rows);
  }

  Future<Presupuesto?> getById(String id) async =>
      _leerEn(await LocalDatabase.instance, id);

  static Future<Presupuesto?> _leerEn(DatabaseExecutor db, String id) async {
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

  static String _fechaEventoSql(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<String> crearPresupuesto({
    String? id, // <-- Parámetro de vinculación añadido
    String? clienteId,
    String? nombreCliente,
    String? telefonoCliente,
    String? emailCliente,
    required String tipoEvento,
    String? lugar,
    String? detalleAnclaje,
    String? tituloFestejado,
    String? nombreFestejado,
    String? encabezadoEvento,
    DateTime? fechaEvento,
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
      if (nombreFestejado != null && nombreFestejado.trim().isNotEmpty)
        'nombre_festejado': nombreFestejado.trim(),
      if (encabezadoEvento != null && encabezadoEvento.trim().isNotEmpty)
        'encabezado_evento': encabezadoEvento.trim(),
      if (tituloFestejado != null && tituloFestejado.trim().isNotEmpty)
        'titulo_festejado': tituloFestejado.trim(),
      if (fechaEvento != null) 'fecha_evento': _fechaEventoSql(fechaEvento),
      'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
      'estado': 'activo',
      'instagram': instagram,
      'telefono': telefonoPublicidad,
      'notificado_vencimiento': 0,
      'created_at': nowIso,
    };
    await db.insert('presupuestos', presupuestoData, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.insert, registroId: presupuestoId, payload: presupuestoData);

    // 3. Servicios
    for (final s in servicios) {
      final lineaId = (s['id'] is String && (s['id'] as String).length == 36) ? s['id'] as String : UuidUtils.generate();
      final psData = {
        'id': lineaId,
        'presupuesto_id': presupuestoId,
        'servicio_id': s['servicio_id'],
        'precio_final': s['precio_final'],
        'cantidad': s['cantidad'] ?? 1.0,
        'detalle_servicio': s['detalle_servicio'],
        'grupo': s['grupo'],
        'combo_orden': s['combo_orden'] ?? 0,
        'es_extra': (s['es_extra'] == true || s['es_extra'] == 1) ? 1 : 0,
      };
      await db.insert('presupuesto_servicios', psData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(
        tabla: 'presupuesto_servicios', 
        operacion: SyncOperation.insert, 
        registroId: lineaId, 
        payload: psData
      );
    }

    _scheduleSync();

    return presupuestoId;
  }


  /// Convierte el presupuesto en su evento particular y devuelve el id del
  /// evento. Si ya tenía uno, devuelve ese y no crea nada ([yaExistia]).
  ///
  /// [fechaEvento] es la que eligió el usuario cuando el presupuesto no la
  /// trae: ya no se inventa "hoy + 30 días".
  Future<({String eventoId, bool yaExistia})> confirmarPresupuesto(
    String id, {
    DateTime? fechaEvento,
  }) async {
    final r = await confirmarEn(
      await LocalDatabase.instance,
      id,
      fechaEvento: fechaEvento,
    );
    _scheduleSync();
    return r;
  }

  /// El evento que salió de este presupuesto, o null si todavía no tiene.
  Future<String?> eventoDelPresupuesto(String presupuestoId) async =>
      eventoDelPresupuestoEn(await LocalDatabase.instance, presupuestoId);

  static Future<String?> eventoDelPresupuestoEn(
    DatabaseExecutor db,
    String presupuestoId,
  ) async {
    final rows = await db.query(
      'eventos',
      columns: ['id'],
      where: 'presupuesto_id = ?',
      whereArgs: [presupuestoId],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  /// Lo que hace [confirmarPresupuesto], sobre [db] (los tests usan una base
  /// en memoria).
  ///
  /// - **Nunca dos eventos del mismo presupuesto.** Si ya hay un evento con su
  ///   `presupuesto_id`, se devuelve ese (y se deja el presupuesto confirmado si
  ///   no lo estaba). Antes el botón CREAR EVENTO no se iba nunca: crearlo otra
  ///   vez mudaba los renglones del primer evento al segundo, porque llevan el
  ///   mismo id, y el primero quedaba en $0.
  /// - **Todo junto:** evento, renglones y estado van en una transacción.
  /// - Sin ítems, sin fecha o sin cliente en esta PC, no crea y dice por qué.
  static Future<({String eventoId, bool yaExistia})> confirmarEn(
    Database db,
    String id, {
    DateTime? fechaEvento,
  }) async {
    final p = await _leerEn(db, id);
    if (p == null) throw const PresupuestoNoEncontradoException();

    final existente = await eventoDelPresupuestoEn(db, id);
    if (existente != null) {
      if (!p.confirmado) {
        await db.transaction((txn) => _marcarConfirmadoEn(txn, id));
      }
      return (eventoId: existente, yaExistia: true);
    }

    // Sin ítems no se confirma. Se lee la base LOCAL, así que un presupuesto
    // cuyos ítems todavía no bajaron de la nube llega acá con la lista vacía, y
    // el evento se creaba sin un solo servicio, en silencio. Como el monto de
    // un evento particular sale de sumar sus servicios, quedaba en $0 para
    // siempre y el presupuesto igual pasaba a "confirmado".
    //
    // Le pasó al de braian colman el 2026-09-04: 6 ítems por $1.750.000 en la
    // nube, cero en la PC que lo confirmó. Mejor no confirmar y decir por qué.
    if (p.servicios.isEmpty) {
      throw const PresupuestoSinItemsException();
    }

    final fecha = p.fechaEvento ?? fechaEvento;
    if (fecha == null) throw const PresupuestoSinFechaException();

    final cliente = await db.query(
      'clientes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [p.clienteId],
      limit: 1,
    );
    if (cliente.isEmpty) throw const PresupuestoSinClienteException();

    // Convertir servicios de presupuesto a formato compatible con el nuevo selector {'precio': x, 'cantidad': y}
    final Map<String, Map<String, dynamic>> serviciosMap = {
      for (var s in p.servicios) s.id: {
        'servicio_id': s.servicioId,
        'precio': s.precioFinal,
        'cantidad': s.cantidad,
        'grupo': s.grupo,
        'combo_orden': s.comboOrden,
        'detalle_servicio': s.detalleServicio,
        'es_extra': s.esExtra,
      }
    };

    final eventoId = await db.transaction((txn) async {
      final nuevo = await EventosRepository.crearEventoEn(
        txn,
        clienteId: p.clienteId,
        tipoEvento: p.tipoEvento,
        fechaEvento: fecha,
        modalidad: 'particular',
        observaciones: p.detalleAnclaje,
        nombreFestejado: p.nombreFestejado,
        encabezadoEvento: p.encabezadoEvento,
        tituloFestejado: p.encabezadoEvento ?? p.tituloFestejado ?? p.nombreFestejado,
        presupuestoId: p.id,
        serviciosSeleccionados: serviciosMap,
      );
      await _marcarConfirmadoEn(txn, id);
      return nuevo;
    });
    return (eventoId: eventoId, yaExistia: false);
  }

  static Future<void> _marcarConfirmadoEn(DatabaseExecutor txn, String id) async {
    await txn.update('presupuestos', {'estado': 'confirmado'}, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      executor: txn,
      tabla: 'presupuestos',
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, 'estado': 'confirmado'},
    );
  }

  Future<void> cambiarEstado(String id, EstadoPresupuesto nuevoEstado) async {
    final db = await LocalDatabase.instance;
    await db.update('presupuestos', {'estado': nuevoEstado.name}, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(
      tabla: 'presupuestos', 
      operacion: SyncOperation.update, 
      registroId: id, 
      payload: {'id': id, 'estado': nuevoEstado.name}
    );

    _scheduleSync();
  }

  Future<void> eliminar(String id) async {
    final db = await LocalDatabase.instance;
    // Un presupuesto con su evento no se borra: de él salen el lugar que muestra
    // el evento y la reparación de sus renglones (6.2.1).
    if (await eventoDelPresupuestoEn(db, id) != null) {
      throw const PresupuestoConEventoException();
    }
    await db.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [id]);
    await db.delete('presupuestos', where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.delete, registroId: id, payload: {});
    
    _scheduleSync();
  }

  Future<void> actualizar({
    required String id,
    required String tipoEvento,
    String? lugar,
    String? detalleAnclaje,
    DateTime? fechaEvento,
    int diasValidez = 7,
    required List<Map<String, dynamic>> servicios,
  }) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now();

    // 1. Actualizar presupuesto base
    final presupuestoData = {
      'tipo_evento': tipoEvento,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      if (fechaEvento != null) 'fecha_evento': _fechaEventoSql(fechaEvento),
      'fecha_vencimiento': now.add(Duration(days: diasValidez)).toUtc().toIso8601String(),
    };
    
    await db.update('presupuestos', presupuestoData, where: 'id = ?', whereArgs: [id]);
    await SyncQueue.enqueue(tabla: 'presupuestos', operacion: SyncOperation.update, registroId: id, payload: presupuestoData);

    // 2. Reemplazar servicios (local + cola de sync: borrados en nube + upserts)
    final oldRows = await db.query(
      'presupuesto_servicios',
      columns: ['id'],
      where: 'presupuesto_id = ?',
      whereArgs: [id],
    );
    final newIds = servicios
        .map((s) {
          final raw = s['id'];
          return raw is String && raw.length == 36 ? raw : null;
        })
        .whereType<String>()
        .toSet();
    for (final row in oldRows) {
      final linea = row['id'] as String;
      if (!newIds.contains(linea)) {
        await SyncQueue.enqueue(
          tabla: 'presupuesto_servicios',
          operacion: SyncOperation.delete,
          registroId: linea,
          payload: {'id': linea, 'presupuesto_id': id},
        );
      }
    }

    await db.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [id]);

    for (final s in servicios) {
      final lineaId = (s['id'] is String && (s['id'] as String).length == 36) ? s['id'] as String : UuidUtils.generate();
      final psData = {
        'id': lineaId,
        'presupuesto_id': id,
        'servicio_id': s['servicio_id'],
        'precio_final': s['precio_final'],
        'cantidad': s['cantidad'] ?? 1.0,
        'detalle_servicio': s['detalle_servicio'],
        'grupo': s['grupo'],
        'combo_orden': s['combo_orden'] ?? 0,
        'es_extra': (s['es_extra'] == true || s['es_extra'] == 1) ? 1 : 0,
      };
      await db.insert('presupuesto_servicios', psData, conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(
        tabla: 'presupuesto_servicios',
        operacion: SyncOperation.insert,
        registroId: lineaId,
        payload: psData,
      );
    }

    _scheduleSync();
  }

  Future<void> actualizarConfiguracionIntegral({
    required String presupuestoId,
    required String? vendedorNombre,
    required String? nombreFestejado,
    required String? encabezadoEvento,
    required String? telefonoPublicidad,
    required String? instagram,
    required String? lugar,
    required String? detalleAnclaje,
    required DateTime fechaVencimiento,
    DateTime? fechaEvento,
    required String? clienteId,
    required String? clienteNombre,
    required String? clienteTelefono,
    required String? clienteEmail,
  }) async {
    final db = await LocalDatabase.instance;
    
    final nombre = nombreFestejado?.trim();
    final encabezado = encabezadoEvento?.trim();
    final tituloSync = (encabezado != null && encabezado.isNotEmpty)
        ? encabezado
        : nombre;

    // 1. Actualizar Presupuesto
    final budgetData = {
      'vendedor_nombre': vendedorNombre,
      'nombre_festejado': nombre,
      'encabezado_evento': encabezado,
      'titulo_festejado': tituloSync,
      'telefono': telefonoPublicidad,
      'instagram': instagram,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      'fecha_vencimiento': fechaVencimiento.toUtc().toIso8601String(),
      if (fechaEvento != null) 'fecha_evento': _fechaEventoSql(fechaEvento),
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
    
    _scheduleSync();
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  static Future<List<Presupuesto>> _mapRowsToPresupuestos(DatabaseExecutor db, List<Map<String, dynamic>> rows) async {
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
        'id': sr['id'],
        'presupuesto_id': sr['presupuesto_id'],
        'servicio_id': sr['servicio_id'],
        'precio_final': sr['precio_final'],
        'cantidad': sr['cantidad'],
        'detalle_servicio': sr['detalle_servicio'],
        'grupo': sr['grupo'],
        'combo_orden': sr['combo_orden'] ?? 0,
        'es_extra': sr['es_extra'] ?? 0,
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
        final presupuestoId = row['id'] as String? ?? '';
        if (presupuestoId.isEmpty) continue;

        batch.insert('presupuestos', {
          'id': row['id'],
          'cliente_id': row['cliente_id'],
          'tipo_evento': row['tipo_evento'],
          'lugar': row['lugar'],
          'detalle_anclaje': row['detalle_anclaje'],
          'fecha_vencimiento': row['fecha_vencimiento'],
          'fecha_evento': row['fecha_evento'],
          'estado': row['estado'],
          'instagram': row['instagram'],
          'telefono': row['telefono'],
          'vendedor_nombre': row['vendedor_nombre'],
          'titulo_festejado': row['titulo_festejado'],
          'nombre_festejado': row['nombre_festejado'],
          'encabezado_evento': row['encabezado_evento'],
          'notificado_vencimiento': row['notificado_vencimiento'] == true ? 1 : 0,
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Reemplazar líneas solo para este presupuesto: evita mezclar borrados locales
        // con filas viejas que el pull volvería a insertar (mismos ids que en la nube).
        batch.delete('presupuesto_servicios', where: 'presupuesto_id = ?', whereArgs: [presupuestoId]);

        final servicios = row['presupuesto_servicios'] as List? ?? [];
        for (var i = 0; i < servicios.length; i++) {
          final s = servicios[i] as Map;
          final sMap = Map<String, dynamic>.from(s);
          final pid = (sMap['presupuesto_id'] as String?)?.trim() ?? presupuestoId;
          final sid = (sMap['servicio_id'] as String?)?.trim() ?? '';
          if (pid.isEmpty || sid.isEmpty) continue;

          final rawId = sMap['id'] ?? sMap['Id'];
          final idStr = (rawId is String) ? rawId.trim() : '';
          final lineaId = (idStr.length == 36)
              ? idStr
              : UuidUtils.lineaIdDeterministic('ps', pid, sid, i);

          batch.insert('presupuesto_servicios', {
            'id': lineaId,
            'presupuesto_id': pid,
            'servicio_id': sid,
            'precio_final': sMap['precio_final'],
            'cantidad': sMap['cantidad'] ?? 1.0,
            'detalle_servicio': sMap['detalle_servicio'],
            'grupo': sMap['grupo'],
            'combo_orden': sMap['combo_orden'] ?? 0,
            'es_extra': sMap['es_extra'] ?? 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull presupuestos: $e');
    }
  }

  // _syncInmediato deprecado a favor de SyncEngine
}

final presupuestosRepositoryProvider = Provider<PresupuestosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  return PresupuestosRepository(supabase, connectivity, ref, syncEngine);
});
