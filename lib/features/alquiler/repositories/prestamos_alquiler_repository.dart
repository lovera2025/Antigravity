import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../main.dart';
import '../../../models/prestamo_alquiler.dart';
import '../../clientes/repositories/clientes_repository.dart';
import '../prestamo_redaccion_helper.dart';

final prestamosAlquilerRepositoryProvider = Provider<PrestamosAlquilerRepository>((ref) {
  return PrestamosAlquilerRepository(
    ref.watch(supabaseProvider),
    ref.watch(connectivityServiceProvider),
    ref.watch(clientesRepositoryProvider),
  );
});

class PrestamosAlquilerRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;
  final ClientesRepository _clientes;

  PrestamosAlquilerRepository(this._supabase, this._connectivity, this._clientes);

  /// Oculta préstamos cuya fecha de fin ya pasó (operativo fuera de listado; pagos persisten).
  ///
  /// Optimización: si hay decenas/cientos de préstamos vencidos, agrupamos los UPDATEs
  /// locales en una transacción y un solo IN (...) remoto, evitando que la pantalla quede
  /// bloqueada esperando un round-trip por cada fila.
  Future<void> archivarVencidosSiCorresponde() async {
    final db = await LocalDatabase.instance;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final vencidos = await db.query(
      'prestamos_alquiler',
      where: 'fecha_fin < ? AND visible_listado = 1',
      whereArgs: [nowIso],
    );
    if (vencidos.isEmpty) return;

    final ids = <String>[];
    final payloads = <String, Map<String, dynamic>>{};
    for (final row in vencidos) {
      final id = row['id'].toString();
      ids.add(id);
      final p = PrestamoAlquiler.fromMap({...row, 'visible_listado': 0, 'updated_at': nowIso});
      payloads[id] = p.toRemotePayload();
    }

    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'prestamos_alquiler',
          {'visible_listado': 0, 'updated_at': nowIso},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });

    for (final id in ids) {
      await SyncQueue.enqueue(
        tabla: 'prestamos_alquiler',
        operacion: SyncOperation.update,
        registroId: id,
        payload: payloads[id]!,
      );
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      try {
        await _supabase
            .from('prestamos_alquiler')
            .update({'visible_listado': false, 'updated_at': nowIso})
            .inFilter('id', ids);
      } catch (e) {
        debugPrint('⚠️ sync archivado masivo vencidos: $e');
      }
    }
  }

  Future<List<PrestamoAlquiler>> listarVisibles() async {
    await archivarVencidosSiCorresponde();
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'prestamos_alquiler',
      where: 'visible_listado = 1',
      orderBy: 'fecha_fin DESC',
    );
    return rows.map(PrestamoAlquiler.fromMap).toList();
  }

  Future<List<PrestamoAlquiler>> listarTodosIncluidoArchivados() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('prestamos_alquiler', orderBy: 'fecha_fin DESC');
    return rows.map(PrestamoAlquiler.fromMap).toList();
  }

  Future<PrestamoAlquiler?> obtenerPorId(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('prestamos_alquiler', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return PrestamoAlquiler.fromMap(rows.first);
  }

  Future<List<PrestamoAlquilerLinea>> lineasDe(String prestamoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'prestamo_alquiler_lineas',
      where: 'prestamo_id = ?',
      whereArgs: [prestamoId],
      orderBy: 'orden ASC, id ASC',
    );
    return rows.map(PrestamoAlquilerLinea.fromMap).toList();
  }

  Future<List<PagoPrestamoAlquiler>> pagosDe(String prestamoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'pagos_prestamo_alquiler',
      where: 'prestamo_id = ?',
      whereArgs: [prestamoId],
      orderBy: 'fecha_pago DESC',
    );
    return rows.map(PagoPrestamoAlquiler.fromMap).toList();
  }

  Future<double> sumaPagos(String prestamoId) async {
    final db = await LocalDatabase.instance;
    final r = await db.rawQuery(
      'SELECT SUM(monto) as t FROM pagos_prestamo_alquiler WHERE prestamo_id = ? AND (anulado IS NULL OR anulado = 0)',
      [prestamoId],
    );
    return (r.isNotEmpty ? (r.first['t'] as num?)?.toDouble() : null) ?? 0;
  }

  /// Resuelve [clienteId] existente o crea cliente mínimo y devuelve su id.
  Future<String> resolverOCrearCliente({
    String? clienteId,
    required String nombreCompleto,
    String? telefono,
    String? email,
  }) async {
    if (clienteId != null && clienteId.isNotEmpty) {
      final ex = await _clientes.getById(clienteId);
      if (ex != null) return clienteId;
    }
    final nombre = nombreCompleto.trim();
    if (nombre.isEmpty) {
      throw ArgumentError('El nombre del cliente es obligatorio.');
    }
    final todos = await _clientes.getAll();
    for (final c in todos) {
      if (c.nombreCompleto.toLowerCase() == nombre.toLowerCase()) return c.id;
    }
    return _clientes.crear(
      nombreCompleto: nombre,
      telefono: telefono,
      email: email,
    );
  }

  static Map<String, double> calcularTotales({
    required List<PrestamoAlquilerLinea> lineas,
    required bool aplicaIva,
    required double alicuotaIva,
  }) {
    final subtotal = lineas.fold<double>(0, (s, l) => s + l.lineaTotal);
    if (!aplicaIva || alicuotaIva <= 0) {
      return {'subtotal_neto': subtotal, 'monto_iva': 0.0, 'total': subtotal};
    }
    final iva = subtotal * (alicuotaIva / 100.0);
    return {'subtotal_neto': subtotal, 'monto_iva': iva, 'total': subtotal + iva};
  }

  Future<String> crearPrestamo({
    String? clienteId,
    required String nombreCliente,
    String? telefonoCliente,
    String? emailCliente,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required bool aplicaIva,
    required double alicuotaIva,
    required List<PrestamoAlquilerLinea> lineasSinId,
    String? textoRedaccion,
    String? textoDisclaimer,
  }) async {
    if (lineasSinId.isEmpty) {
      throw ArgumentError('Agregá al menos un ítem al préstamo.');
    }
    if (fechaFin.isBefore(fechaInicio)) {
      throw ArgumentError('La fecha de fin no puede ser anterior al inicio.');
    }

    final cid = await resolverOCrearCliente(
      clienteId: clienteId,
      nombreCompleto: nombreCliente,
      telefono: telefonoCliente,
      email: emailCliente,
    );

    final prestamoId = UuidUtils.generate();
    final lineas = <PrestamoAlquilerLinea>[];
    var orden = 0;
    for (final l in lineasSinId) {
      final lid = UuidUtils.generate();
      lineas.add(PrestamoAlquilerLinea(
        id: lid,
        prestamoId: prestamoId,
        descripcion: l.descripcion.trim(),
        cantidad: l.cantidad,
        precioUnitario: l.precioUnitario,
        lineaTotal: l.lineaTotal,
        orden: orden++,
      ));
    }

    final tot = calcularTotales(lineas: lineas, aplicaIva: aplicaIva, alicuotaIva: alicuotaIva);
    final clienteRow = await _clientes.getById(cid);
    final nombre = clienteRow?.nombreCompleto ?? nombreCliente;

    final redaccion = textoRedaccion?.trim().isNotEmpty == true
        ? textoRedaccion!.trim()
        : PrestamoRedaccionHelper.generarCuerpo(
            nombreCliente: nombre,
            fechaInicio: fechaInicio,
            fechaFin: fechaFin,
            lineas: lineas,
            subtotalNeto: tot['subtotal_neto']!,
            montoIva: tot['monto_iva']!,
            total: tot['total']!,
            aplicaIva: aplicaIva,
            alicuotaIva: alicuotaIva,
          );
    final disclaimer = textoDisclaimer?.trim().isNotEmpty == true
        ? textoDisclaimer!.trim()
        : PrestamoRedaccionHelper.disclaimerPredeterminado();

    final now = DateTime.now().toUtc();
    final prestamo = PrestamoAlquiler(
      id: prestamoId,
      clienteId: cid,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      aplicaIva: aplicaIva,
      alicuotaIva: alicuotaIva,
      subtotalNeto: tot['subtotal_neto']!,
      montoIva: tot['monto_iva']!,
      total: tot['total']!,
      textoRedaccion: redaccion,
      textoDisclaimer: disclaimer,
      visibleListado: true,
      createdAt: now,
      updatedAt: now,
    );

    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      await txn.insert('prestamos_alquiler', prestamo.toSqlMap());
      for (final l in lineas) {
        await txn.insert('prestamo_alquiler_lineas', l.toInsertMap());
      }
    });

    await SyncQueue.enqueue(
      tabla: 'prestamos_alquiler',
      operacion: SyncOperation.insert,
      registroId: prestamoId,
      payload: prestamo.toRemotePayload(),
    );
    for (final l in lineas) {
      await SyncQueue.enqueue(
        tabla: 'prestamo_alquiler_lineas',
        operacion: SyncOperation.insert,
        registroId: l.id,
        payload: _lineaRemote(l),
      );
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      final clienteListo = await _clientes.ensureClienteEnNube(cid);
      if (clienteListo) {
        try {
          await _supabase.from('prestamos_alquiler').upsert(prestamo.toRemotePayload());
          for (final l in lineas) {
            await _supabase.from('prestamo_alquiler_lineas').upsert(_lineaRemote(l));
          }
          final dbq = await LocalDatabase.instance;
          await dbq.delete('_sync_queue',
              where: 'tabla = ? AND registro_id = ?', whereArgs: ['prestamos_alquiler', prestamoId]);
          for (final l in lineas) {
            await dbq.delete('_sync_queue',
                where: 'tabla = ? AND registro_id = ?',
                whereArgs: ['prestamo_alquiler_lineas', l.id]);
          }
          debugPrint('☁️ Préstamo sync inmediato OK: $prestamoId');
        } catch (e) {
          debugPrint('⚠️ Sync inmediato préstamo (queda en cola): $e');
        }
      }
    }

    return prestamoId;
  }

  Map<String, dynamic> _lineaRemote(PrestamoAlquilerLinea l) => {
        'id': l.id,
        'prestamo_id': l.prestamoId,
        'descripcion': l.descripcion,
        'cantidad': l.cantidad,
        'precio_unitario': l.precioUnitario,
        'linea_total': l.lineaTotal,
        'orden': l.orden,
      };

  /// Actualiza cabecera, totales, textos PDF y líneas (altas, bajas, cambios).
  Future<void> actualizarPrestamo({
    required String prestamoId,
    String? clienteId,
    required String nombreCliente,
    String? telefonoCliente,
    String? emailCliente,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required bool aplicaIva,
    required double alicuotaIva,
    required List<PrestamoAlquilerLinea> lineasEntrada,
    String? textoRedaccion,
    String? textoDisclaimer,
  }) async {
    if (lineasEntrada.isEmpty) {
      throw ArgumentError('Agregá al menos un ítem al préstamo.');
    }
    if (fechaFin.isBefore(fechaInicio)) {
      throw ArgumentError('La fecha de fin no puede ser anterior al inicio.');
    }

    final existing = await obtenerPorId(prestamoId);
    if (existing == null) throw StateError('Préstamo no encontrado.');

    final cid = await resolverOCrearCliente(
      clienteId: clienteId,
      nombreCompleto: nombreCliente,
      telefono: telefonoCliente,
      email: emailCliente,
    );

    final lineasDb = await lineasDe(prestamoId);
    final idsEnDb = lineasDb.map((e) => e.id).toSet();

    final resolved = <PrestamoAlquilerLinea>[];
    var orden = 0;
    for (final src in lineasEntrada) {
      final id = (src.id.isNotEmpty && idsEnDb.contains(src.id)) ? src.id : UuidUtils.generate();
      resolved.add(PrestamoAlquilerLinea(
        id: id,
        prestamoId: prestamoId,
        descripcion: src.descripcion.trim(),
        cantidad: src.cantidad,
        precioUnitario: src.precioUnitario,
        lineaTotal: src.cantidad * src.precioUnitario,
        orden: orden++,
      ));
    }

    final idsMantener = resolved.map((e) => e.id).toSet();
    final idsBorrar = idsEnDb.difference(idsMantener);

    final tot = calcularTotales(lineas: resolved, aplicaIva: aplicaIva, alicuotaIva: alicuotaIva);
    final clienteRow = await _clientes.getById(cid);
    final nombre = clienteRow?.nombreCompleto ?? nombreCliente;

    final redFinal = textoRedaccion?.trim().isNotEmpty == true
        ? textoRedaccion!.trim()
        : PrestamoRedaccionHelper.generarCuerpo(
            nombreCliente: nombre,
            fechaInicio: fechaInicio,
            fechaFin: fechaFin,
            lineas: resolved,
            subtotalNeto: tot['subtotal_neto']!,
            montoIva: tot['monto_iva']!,
            total: tot['total']!,
            aplicaIva: aplicaIva,
            alicuotaIva: alicuotaIva,
          );
    final disFinal = textoDisclaimer?.trim().isNotEmpty == true
        ? textoDisclaimer!.trim()
        : PrestamoRedaccionHelper.disclaimerPredeterminado();

    final now = DateTime.now().toUtc();
    final nowIso = now.toIso8601String();

    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      for (final bid in idsBorrar) {
        await txn.delete('prestamo_alquiler_lineas', where: 'id = ?', whereArgs: [bid]);
      }
      for (final l in resolved) {
        if (idsEnDb.contains(l.id)) {
          await txn.update(
            'prestamo_alquiler_lineas',
            l.toInsertMap(),
            where: 'id = ?',
            whereArgs: [l.id],
          );
        } else {
          await txn.insert('prestamo_alquiler_lineas', l.toInsertMap());
        }
      }
      await txn.update(
        'prestamos_alquiler',
        {
          'cliente_id': cid,
          'fecha_inicio': fechaInicio.toUtc().toIso8601String(),
          'fecha_fin': fechaFin.toUtc().toIso8601String(),
          'aplica_iva': aplicaIva ? 1 : 0,
          'alicuota_iva': alicuotaIva,
          'subtotal_neto': tot['subtotal_neto'],
          'monto_iva': tot['monto_iva'],
          'total': tot['total'],
          'texto_redaccion': redFinal,
          'texto_disclaimer': disFinal,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [prestamoId],
      );
    });

    for (final bid in idsBorrar) {
      await SyncQueue.enqueue(
        tabla: 'prestamo_alquiler_lineas',
        operacion: SyncOperation.delete,
        registroId: bid,
        payload: {'id': bid},
      );
    }
    for (final l in resolved) {
      final op = idsEnDb.contains(l.id) ? SyncOperation.update : SyncOperation.insert;
      await SyncQueue.enqueue(
        tabla: 'prestamo_alquiler_lineas',
        operacion: op,
        registroId: l.id,
        payload: _lineaRemote(l),
      );
    }

    final mergedPrestamo = PrestamoAlquiler(
      id: prestamoId,
      clienteId: cid,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      aplicaIva: aplicaIva,
      alicuotaIva: alicuotaIva,
      subtotalNeto: tot['subtotal_neto']!,
      montoIva: tot['monto_iva']!,
      total: tot['total']!,
      textoRedaccion: redFinal,
      textoDisclaimer: disFinal,
      visibleListado: existing.visibleListado,
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    await SyncQueue.enqueue(
      tabla: 'prestamos_alquiler',
      operacion: SyncOperation.update,
      registroId: prestamoId,
      payload: mergedPrestamo.toRemotePayload(),
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      final clienteListo = await _clientes.ensureClienteEnNube(cid);
      if (clienteListo) {
        try {
          await _supabase.from('prestamos_alquiler').upsert(mergedPrestamo.toRemotePayload());
          for (final bid in idsBorrar) {
            await _supabase.from('prestamo_alquiler_lineas').delete().eq('id', bid);
          }
          for (final l in resolved) {
            await _supabase.from('prestamo_alquiler_lineas').upsert(_lineaRemote(l));
          }
          final dbq = await LocalDatabase.instance;
          await dbq.delete('_sync_queue',
              where: 'tabla = ? AND registro_id = ?', whereArgs: ['prestamos_alquiler', prestamoId]);
          for (final l in resolved) {
            await dbq.delete('_sync_queue',
                where: 'tabla = ? AND registro_id = ?',
                whereArgs: ['prestamo_alquiler_lineas', l.id]);
          }
          for (final bid in idsBorrar) {
            await dbq.delete('_sync_queue',
                where: 'tabla = ? AND registro_id = ?',
                whereArgs: ['prestamo_alquiler_lineas', bid]);
          }
          debugPrint('☁️ Préstamo actualizado sync OK: $prestamoId');
        } catch (e) {
          debugPrint('⚠️ Sync inmediato actualización préstamo (queda en cola): $e');
        }
      }
    }
  }

  Future<void> actualizarTextos({
    required String prestamoId,
    String? textoRedaccion,
    String? textoDisclaimer,
  }) async {
    final db = await LocalDatabase.instance;
    final p = await obtenerPorId(prestamoId);
    if (p == null) return;

    final data = <String, dynamic>{
      'texto_redaccion': textoRedaccion ?? p.textoRedaccion,
      'texto_disclaimer': textoDisclaimer ?? p.textoDisclaimer,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await db.update('prestamos_alquiler', data, where: 'id = ?', whereArgs: [prestamoId]);

    final merged = p.toRemotePayload()
      ..['texto_redaccion'] = data['texto_redaccion']
      ..['texto_disclaimer'] = data['texto_disclaimer']
      ..['updated_at'] = data['updated_at'];

    await SyncQueue.enqueue(
      tabla: 'prestamos_alquiler',
      operacion: SyncOperation.update,
      registroId: prestamoId,
      payload: merged,
    );
    if (_connectivity.currentStatus == AppConnectivity.online) {
      try {
        await _supabase.from('prestamos_alquiler').update({
          'texto_redaccion': data['texto_redaccion'],
          'texto_disclaimer': data['texto_disclaimer'],
          'updated_at': data['updated_at'],
        }).eq('id', prestamoId);
      } catch (e) {
        debugPrint('⚠️ Sync texto préstamo: $e');
      }
    }
  }

  /// Quita el préstamo del listado activo; no borra pagos ni la fila (sigue en BD para vínculos).
  Future<void> archivarOperativo(String prestamoId) async {
    final db = await LocalDatabase.instance;
    final p = await obtenerPorId(prestamoId);
    if (p == null) return;

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'prestamos_alquiler',
      {'visible_listado': 0, 'updated_at': updatedAt},
      where: 'id = ?',
      whereArgs: [prestamoId],
    );

    final payload = p.toRemotePayload()
      ..['visible_listado'] = false
      ..['updated_at'] = updatedAt;

    await SyncQueue.enqueue(
      tabla: 'prestamos_alquiler',
      operacion: SyncOperation.update,
      registroId: prestamoId,
      payload: payload,
    );
    if (_connectivity.currentStatus == AppConnectivity.online) {
      try {
        await _supabase.from('prestamos_alquiler').update({
          'visible_listado': false,
          'updated_at': updatedAt,
        }).eq('id', prestamoId);
      } catch (e) {
        debugPrint('⚠️ archivar préstamo remoto: $e');
      }
    }
  }

  Future<void> registrarPago({
    required String prestamoId,
    required double monto,
    String? concepto,
    DateTime? fechaPago,
    String? medioPago,
  }) async {
    if (monto <= 0) throw ArgumentError('El monto debe ser mayor a cero.');
    final p = await obtenerPorId(prestamoId);
    if (p == null) throw StateError('Préstamo no encontrado.');

    final id = UuidUtils.generate();
    // Instante preciso en UTC — se muestra en huso AR vía ArTime.
    final now = ArTime.nowUtc();
    final fp = fechaPago ?? now;
    final row = PagoPrestamoAlquiler(
      id: id,
      prestamoId: prestamoId,
      monto: monto,
      concepto: concepto?.trim().isNotEmpty == true ? concepto!.trim() : 'Pago alquiler ítems',
      fechaPago: fp,
      createdAt: now,
      medioPago: medioPago,
    );

    final db = await LocalDatabase.instance;
    await db.insert('pagos_prestamo_alquiler', row.toInsertMap());

    final remote = row.toInsertMap();

    await SyncQueue.enqueue(
      tabla: 'pagos_prestamo_alquiler',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: remote,
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      try {
        await _supabase.from('pagos_prestamo_alquiler').upsert(remote);
      } catch (e) {
        debugPrint('⚠️ pago préstamo remoto: $e');
      }
    }
  }
}
