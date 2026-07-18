import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../models/operador_caja.dart';

class OperadoresCajaRepository {
  // ignore: unused_field
  final ConnectivityService _connectivity;
  // ignore: unused_field
  final SyncEngine _syncEngine;

  OperadoresCajaRepository(this._connectivity, this._syncEngine);

  Future<List<OperadorCaja>> listar({bool soloActivos = false}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'operadores_caja',
      where: soloActivos ? 'activo = 1' : null,
      orderBy: 'nombre COLLATE NOCASE ASC',
    );
    return rows.map(OperadorCaja.fromMap).toList();
  }

  Future<OperadorCaja?> getById(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'operadores_caja',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OperadorCaja.fromMap(rows.first);
  }

  Future<OperadorCaja?> findByPin(String pin) async {
    final trimmed = pin.trim();
    if (trimmed.isEmpty) return null;
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'operadores_caja',
      where: 'pin = ? AND activo = 1',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OperadorCaja.fromMap(rows.first);
  }

  Future<OperadorCaja> crear({
    required String nombre,
    required String pin,
  }) async {
    final n = nombre.trim();
    final p = pin.trim();
    if (n.isEmpty) throw ArgumentError('El nombre es obligatorio');
    if (p.length < 4)
      throw ArgumentError('El PIN debe tener al menos 4 dígitos');

    final existing = await findByPin(p);
    if (existing != null) {
      throw StateError('Ese PIN ya está asignado a ${existing.nombre}');
    }

    final now = DateTime.parse(ArTime.nowUtcIso());
    final op = OperadorCaja(
      id: UuidUtils.generate(),
      nombre: n,
      pin: p,
      activo: true,
      createdAt: now,
      updatedAt: now,
    );
    final db = await LocalDatabase.instance;
    await db.insert('operadores_caja', op.toMap());
    await SyncQueue.enqueue(
      tabla: 'operadores_caja',
      operacion: SyncOperation.insert,
      registroId: op.id,
      payload: op.toSyncPayload(),
    );
    return op;
  }

  Future<OperadorCaja> actualizar(OperadorCaja op) async {
    final n = op.nombre.trim();
    final p = op.pin.trim();
    if (n.isEmpty) throw ArgumentError('El nombre es obligatorio');
    if (p.length < 4)
      throw ArgumentError('El PIN debe tener al menos 4 dígitos');

    final byPin = await findByPin(p);
    if (byPin != null && byPin.id != op.id) {
      throw StateError('Ese PIN ya está asignado a ${byPin.nombre}');
    }

    final updated = op.copyWith(
      nombre: n,
      pin: p,
      updatedAt: DateTime.parse(ArTime.nowUtcIso()),
    );
    final db = await LocalDatabase.instance;
    await db.update(
      'operadores_caja',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    await SyncQueue.enqueue(
      tabla: 'operadores_caja',
      operacion: SyncOperation.update,
      registroId: updated.id,
      payload: updated.toSyncPayload(),
    );
    return updated;
  }

  Future<void> setActivo(String id, bool activo) async {
    final op = await getById(id);
    if (op == null) return;
    await actualizar(op.copyWith(activo: activo));
  }

  /// Elimina operador: cierra caja abierta si hay; hard delete si no tiene
  /// historial de sesiones; si no, baja lógica (activo = false).
  Future<void> eliminar(String id) async {
    final op = await getById(id);
    if (op == null) return;

    final db = await LocalDatabase.instance;

    // Cerrar sesión abierta antes de desactivar (evita chip "Caja activa" huérfano).
    final abiertas = await db.query(
      'sesiones_caja',
      where: 'operador_id = ? AND cerrada_at IS NULL',
      whereArgs: [id],
    );
    final nowIso = ArTime.nowUtcIso();
    for (final row in abiertas) {
      final sesionId = row['id'] as String;
      final updated = Map<String, dynamic>.from(row)
        ..['cerrada_at'] = nowIso
        ..['nota_cierre'] = 'Cerrada al eliminar operador'
        ..['last_heartbeat'] = nowIso
        ..['updated_at'] = nowIso;
      await db.update(
        'sesiones_caja',
        updated,
        where: 'id = ?',
        whereArgs: [sesionId],
      );
      await SyncQueue.enqueue(
        tabla: 'sesiones_caja',
        operacion: SyncOperation.update,
        registroId: sesionId,
        payload: {
          'id': sesionId,
          'operador_id': id,
          'abierta_at': row['abierta_at'],
          'cerrada_at': nowIso,
          'cambio_inicial': row['cambio_inicial'],
          'nota_apertura': row['nota_apertura'],
          'etiqueta': row['etiqueta'],
          'arqueo_cierre': row['arqueo_cierre'],
          'nota_cierre': 'Cerrada al eliminar operador',
          'device_id': row['device_id'],
          'last_heartbeat': nowIso,
          'created_at': row['created_at'],
          'updated_at': nowIso,
        },
      );
    }

    final sesiones = await db.query(
      'sesiones_caja',
      columns: ['id'],
      where: 'operador_id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (sesiones.isEmpty) {
      await db.delete('operadores_caja', where: 'id = ?', whereArgs: [id]);
      await SyncQueue.enqueue(
        tabla: 'operadores_caja',
        operacion: SyncOperation.delete,
        registroId: id,
        payload: {'id': id},
      );
      return;
    }

    await actualizar(op.copyWith(activo: false));
  }
}

final operadoresCajaRepositoryProvider = Provider<OperadoresCajaRepository>((
  ref,
) {
  return OperadoresCajaRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
