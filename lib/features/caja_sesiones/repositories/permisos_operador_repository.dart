import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/instalacion_id.dart';
import '../models/permisos_operador.dart';

/// Los permisos de los operadores — SQLite + cola → Supabase.
///
/// Guardar es del jefe, desde OPERADORES. **Nada se borra:** ni la fila de un
/// operador ni los renglones del registro.
class PermisosOperadorRepository {
  const PermisosOperadorRepository();

  /// La fila de un operador, si tiene. Sin la tabla (una base que no migró) no
  /// tira: da null, y el operador sigue de Cobros como hasta ahora.
  static Future<PermisosOperador?> deEn(
    DatabaseExecutor db,
    String operadorId,
  ) async {
    try {
      final rows = await db.query(
        'permisos_operador',
        where: 'operador_id = ?',
        whereArgs: [operadorId],
        limit: 1,
      );
      return rows.isEmpty ? null : PermisosOperador.fromMap(rows.first);
    } catch (e) {
      debugPrint('⚠️ Permisos sin leer: $e');
      return null;
    }
  }

  /// Todas las filas, por operador.
  static Future<Map<String, PermisosOperador>> todasEn(
    DatabaseExecutor db,
  ) async {
    try {
      final rows = await db.query('permisos_operador');
      return {
        for (final r in rows)
          (r['operador_id'] as String): PermisosOperador.fromMap(r),
      };
    } catch (e) {
      debugPrint('⚠️ Permisos sin leer: $e');
      return const {};
    }
  }

  /// Guarda los permisos de un operador y anota qué cambió, con su subida en la
  /// misma transacción.
  ///
  /// **Si no cambió nada, no escribe nada:** abrir a un operador de los de antes
  /// y guardar sin tocar las casillas no le crea una fila. Devuelve los renglones
  /// del registro que se agregaron.
  static Future<List<CambioDePermiso>> guardarEn(
    DatabaseExecutor db, {
    required String operadorId,
    required PermisosEfectivos permisos,
    String? quien,
    String? deviceId,
    required DateTime ahora,
  }) async {
    final antes = await deEn(db, operadorId);
    final cambios = CambioDePermiso.entre(
      operadorId: operadorId,
      antes: PermisosEfectivos.de(antes),
      despues: permisos,
      hechoPor: quien,
      deviceId: deviceId,
      ahora: ahora,
    );
    if (cambios.isEmpty) return const [];

    final fila = PermisosOperador.para(
      operadorId: operadorId,
      permisos: permisos,
      hechoPor: quien,
      deviceId: deviceId,
      createdAt: antes?.createdAt,
      ahora: ahora,
    );
    await db.insert(
      'permisos_operador',
      fila.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await SyncQueue.enqueue(
      executor: db,
      tabla: 'permisos_operador',
      operacion: SyncOperation.insert,
      registroId: fila.id,
      payload: fila.toMap(),
    );
    for (final c in cambios) {
      await db.insert('permisos_operador_cambios', c.toMap());
      await SyncQueue.enqueue(
        executor: db,
        tabla: 'permisos_operador_cambios',
        operacion: SyncOperation.insert,
        registroId: c.id,
        payload: c.toMap(),
      );
    }
    return cambios;
  }

  Future<PermisosEfectivos> de(String operadorId) async =>
      PermisosEfectivos.de(await deEn(await LocalDatabase.instance, operadorId));

  Future<Map<String, PermisosOperador>> todas() async =>
      todasEn(await LocalDatabase.instance);

  /// [guardarEn] en una transacción.
  Future<List<CambioDePermiso>> guardar({
    required String operadorId,
    required PermisosEfectivos permisos,
    required String quien,
    DateTime? ahora,
  }) async {
    final db = await LocalDatabase.instance;
    final deviceId = await InstalacionId.inicializar();
    return db.transaction(
      (txn) => guardarEn(
        txn,
        operadorId: operadorId,
        permisos: permisos,
        quien: quien,
        deviceId: deviceId,
        ahora: ahora ?? DateTime.now(),
      ),
    );
  }
}

final permisosOperadorRepositoryProvider = Provider<PermisosOperadorRepository>(
  (ref) => const PermisosOperadorRepository(),
);
