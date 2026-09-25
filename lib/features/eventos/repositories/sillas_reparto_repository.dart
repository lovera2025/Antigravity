import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/sillas_reparto.dart';

/// Reparto de sillas extra por alumno — SQLite + cola → Supabase.
///
/// Una fila por alumno con id fijo, igual que las notas operativas: las dos PCs
/// escriben la misma fila, así que no puede quedar un alumno con dos repartos.
/// No toca `contratos_alumnos`.
class SillasRepartoRepository {
  Future<Map<String, SillasReparto>> obtenerPorContratoIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await LocalDatabase.instance;
    final unicos = ids.toSet().toList();
    final marcas = List.filled(unicos.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM sillas_reparto WHERE contrato_alumno_id IN ($marcas)',
      unicos,
    );
    return {
      for (final r in rows)
        (r['contrato_alumno_id'] as String): SillasReparto.fromMap(r),
    };
  }

  /// Guarda la elección y la encola completa. Se encola como alta: en la nube
  /// es un upsert, que anda igual si la fila ya existía o si todavía no llegó.
  Future<SillasReparto> guardar({
    required String contratoAlumnoId,
    required int sillasPrincipal,
    required int sillasExtra,
    required int mesas,
    required String? hechoPor,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.sillasRepartoId(contratoAlumnoId);
    final anterior =
        (await obtenerPorContratoIds([contratoAlumnoId]))[contratoAlumnoId];
    final ahora = ArTime.nowUtc();
    final fila = SillasReparto(
      id: id,
      contratoAlumnoId: contratoAlumnoId,
      sillasPrincipal: sillasPrincipal,
      sillasExtra: sillasExtra,
      mesas: mesas,
      hechoPor: hechoPor,
      createdAt: anterior?.createdAt ?? ahora,
      updatedAt: ahora,
    );
    await db.transaction((txn) async {
      await txn.insert(
        'sillas_reparto',
        fila.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await SyncQueue.enqueue(
        executor: txn,
        tabla: 'sillas_reparto',
        operacion: SyncOperation.insert,
        registroId: id,
        payload: fila.toMap(),
      );
    });
    return fila;
  }
}

final sillasRepartoRepositoryProvider = Provider<SillasRepartoRepository>(
  (ref) => SillasRepartoRepository(),
);
