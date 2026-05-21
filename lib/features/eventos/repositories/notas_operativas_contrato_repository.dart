import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Future<NotaOperativaContrato?> obtenerUno(String contratoAlumnoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'notas_operativas_contrato',
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoAlumnoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return NotaOperativaContrato.fromMap(rows.first);
  }

  /// Salva y encola sync. [texto] no vacío tras trim.
  Future<void> guardar({
    required String contratoAlumnoId,
    required String texto,
    required bool resuelto,
  }) async {
    final t = texto.trim();
    if (t.isEmpty) {
      throw ArgumentError('La nota no puede estar vacía.');
    }
    final db = await LocalDatabase.instance;
    final nowIso = ArTime.nowUtcIso();
    final canonicalId = UuidUtils.notaOperativaContratoId(contratoAlumnoId);
    final existente = await obtenerUno(contratoAlumnoId);

    if (existente == null) {
      final localRow = <String, dynamic>{
        'id': canonicalId,
        'contrato_alumno_id': contratoAlumnoId,
        'texto': t,
        'resuelto': resuelto ? 1 : 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      };
      await db.insert('notas_operativas_contrato', localRow);
      await SyncQueue.enqueue(
        tabla: 'notas_operativas_contrato',
        operacion: SyncOperation.insert,
        registroId: canonicalId,
        payload: {
          'id': canonicalId,
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
          'id': canonicalId,
          'texto': t,
          'resuelto': resuelto ? 1 : 0,
          'updated_at': nowIso,
        },
        where: 'contrato_alumno_id = ?',
        whereArgs: [contratoAlumnoId],
      );
      await SyncQueue.enqueue(
        tabla: 'notas_operativas_contrato',
        operacion: SyncOperation.update,
        registroId: canonicalId,
        payload: {
          'id': canonicalId,
          'contrato_alumno_id': contratoAlumnoId,
          'texto': t,
          'resuelto': resuelto,
          'created_at': createdIso,
          'updated_at': nowIso,
        },
      );
    }

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
    debugPrint('📝 Nota operativa encolada sync ($contratoAlumnoId)');
  }

  Future<void> eliminar(String contratoAlumnoId) async {
    final existente = await obtenerUno(contratoAlumnoId);
    if (existente == null) return;
    final canonicalId = UuidUtils.notaOperativaContratoId(contratoAlumnoId);
    final db = await LocalDatabase.instance;
    await db.delete(
      'notas_operativas_contrato',
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoAlumnoId],
    );
    await SyncQueue.enqueue(
      tabla: 'notas_operativas_contrato',
      operacion: SyncOperation.delete,
      registroId: canonicalId,
      payload: {'id': canonicalId},
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      _syncEngine.syncNow();
    }
    debugPrint('🗑️ Nota operativa borrada local + encolada ($contratoAlumnoId)');
  }
}

final notasOperativasContratoRepositoryProvider =
    Provider<NotasOperativasContratoRepository>((ref) {
  return NotasOperativasContratoRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
