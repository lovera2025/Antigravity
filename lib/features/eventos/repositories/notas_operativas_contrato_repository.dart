import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/nota_operativa_contrato.dart';

/// Notas operativas por contrato — SQLite + cola → Supabase (sin impacto contable).
class NotasOperativasContratoRepository {
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;

  NotasOperativasContratoRepository(this._connectivity, this._syncEngine);

  Future<Map<String, NotaOperativaContrato>> obtenerPorContratoIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await LocalDatabase.instance;
    final uniques = ids.toSet().toList();
    final placeholders = List.filled(uniques.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM notas_operativas_contrato WHERE contrato_alumno_id IN ($placeholders)',
      uniques,
    );
    final map = <String, NotaOperativaContrato>{};
    for (final r in rows) {
      final n = NotaOperativaContrato.fromMap(r);
      map[n.contratoAlumnoId] = n;
    }
    return map;
  }

  Future<NotaOperativaContrato?> obtenerUno(String contratoAlumnoId) async =>
      obtenerUnoEn(await LocalDatabase.instance, contratoAlumnoId);

  static Future<NotaOperativaContrato?> obtenerUnoEn(
    DatabaseExecutor db,
    String contratoAlumnoId,
  ) async {
    final rows = await db.query(
      'notas_operativas_contrato',
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoAlumnoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotaOperativaContrato.fromMap(rows.first);
  }

  /// El id con el que la nota se guarda y viaja a la nube.
  ///
  /// Una nota nueva lleva el id fijo de su alumno, el mismo en todas las PCs.
  /// **Una que ya existe conserva el suyo, aunque no sea el fijo.** Las notas
  /// de mora condonada de julio de 2026 las escribió una herramienta con otro
  /// id: al editarlas o borrarlas, la app mandaba el cambio a la nube con el id
  /// fijo, que allá no existe. La edición no llegaba a ninguna otra PC y el
  /// borrado dejaba la nota en la nube, sin avisar.
  static String idDe(
    NotaOperativaContrato? existente,
    String contratoAlumnoId,
  ) =>
      existente != null && existente.id.length == 36
          ? existente.id
          : UuidUtils.notaOperativaContratoId(contratoAlumnoId);

  /// Salva y encola sync. [texto] no vacío tras trim.
  Future<void> guardar({
    required String contratoAlumnoId,
    required String texto,
    required bool resuelto,
  }) async {
    final db = await LocalDatabase.instance;
    // La nota y su subida van juntas: una nota guardada sin su entrada en la
    // cola no sube nunca, y nada la reporta como pendiente.
    await db.transaction(
      (txn) => guardarEn(
        txn,
        contratoAlumnoId: contratoAlumnoId,
        texto: texto,
        resuelto: resuelto,
      ),
    );
    debugPrint('📝 Nota operativa encolada sync ($contratoAlumnoId)');
  }

  /// Lo mismo que [guardar], sobre la base o la transacción que se le pase.
  static Future<void> guardarEn(
    DatabaseExecutor db, {
    required String contratoAlumnoId,
    required String texto,
    required bool resuelto,
    String? ahoraIso,
  }) async {
    final t = texto.trim();
    if (t.isEmpty) {
      throw ArgumentError('La nota no puede estar vacía.');
    }
    final nowIso = ahoraIso ?? ArTime.nowUtcIso();
    final existente = await obtenerUnoEn(db, contratoAlumnoId);
    final id = idDe(existente, contratoAlumnoId);

    if (existente == null) {
      await db.insert('notas_operativas_contrato', <String, dynamic>{
        'id': id,
        'contrato_alumno_id': contratoAlumnoId,
        'texto': t,
        'resuelto': resuelto ? 1 : 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await SyncQueue.enqueue(
        executor: db,
        tabla: 'notas_operativas_contrato',
        operacion: SyncOperation.insert,
        registroId: id,
        payload: {
          'id': id,
          'contrato_alumno_id': contratoAlumnoId,
          'texto': t,
          'resuelto': resuelto,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
      );
    } else {
      final createdIso = existente.createdAt.toUtc().toIso8601String();
      await db.update(
        'notas_operativas_contrato',
        {
          'id': id,
          'texto': t,
          'resuelto': resuelto ? 1 : 0,
          'updated_at': nowIso,
        },
        where: 'contrato_alumno_id = ?',
        whereArgs: [contratoAlumnoId],
      );
      await SyncQueue.enqueue(
        executor: db,
        tabla: 'notas_operativas_contrato',
        operacion: SyncOperation.update,
        registroId: id,
        payload: {
          'id': id,
          'contrato_alumno_id': contratoAlumnoId,
          'texto': t,
          'resuelto': resuelto,
          'created_at': createdIso,
          'updated_at': nowIso,
        },
      );
    }
  }

  Future<void> eliminar(String contratoAlumnoId) async {
    final db = await LocalDatabase.instance;
    final borrada = await db.transaction(
      (txn) => eliminarEn(txn, contratoAlumnoId),
    );
    if (borrada) {
      debugPrint(
        '🗑️ Nota operativa borrada local + encolada ($contratoAlumnoId)',
      );
    }
  }

  /// Lo mismo que [eliminar], sobre la base o la transacción que se le pase.
  /// Devuelve si había una nota para borrar.
  static Future<bool> eliminarEn(
    DatabaseExecutor db,
    String contratoAlumnoId,
  ) async {
    final existente = await obtenerUnoEn(db, contratoAlumnoId);
    if (existente == null) return false;
    // Con el id que la nota tiene de verdad: es el que está en la nube.
    final id = idDe(existente, contratoAlumnoId);
    await db.delete(
      'notas_operativas_contrato',
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoAlumnoId],
    );
    await SyncQueue.enqueue(
      executor: db,
      tabla: 'notas_operativas_contrato',
      operacion: SyncOperation.delete,
      registroId: id,
      payload: {'id': id},
    );
    return true;
  }
}

final notasOperativasContratoRepositoryProvider =
    Provider<NotasOperativasContratoRepository>((ref) {
  return NotasOperativasContratoRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
