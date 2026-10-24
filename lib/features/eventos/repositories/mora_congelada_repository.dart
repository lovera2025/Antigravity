import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../models/mora_congelada_alumno.dart';
import '../services/mora_congelada.dart';

/// La mora congelada (6.2.1) — SQLite + cola → Supabase.
///
/// Guardar es del jefe, desde el diálogo de la grilla (cada función que guarda
/// arranca con su freno de modo jefe). La cuenta de la mora no lee la base: lee
/// el registro en memoria ([MoraCongelada.de]), que esto deja al día.
class MoraCongeladaRepository {
  const MoraCongeladaRepository();

  /// Todas las filas de la base, por alumno.
  static Future<Map<String, MoraCongelada>> todasEn(DatabaseExecutor db) async {
    final rows = await db.query('mora_congelada');
    return {
      for (final r in rows)
        (r['contrato_alumno_id'] as String): MoraCongeladaAlumno.fromMap(r).mora,
    };
  }

  /// Carga el registro en memoria desde la base. Lo llaman el arranque, la
  /// revisión de la mora (antes de repasar) y el sync cuando baja filas. Nunca
  /// tira: sin la tabla (una base que no migró) el registro queda vacío y la
  /// mora se cuenta como siempre.
  static Future<void> cargarRegistroEn(DatabaseExecutor db) async {
    try {
      MoraCongelada.cargar(await todasEn(db));
    } catch (e) {
      debugPrint('⚠️ Mora congelada sin cargar: $e');
    }
  }

  static Future<void> cargarRegistro() async =>
      cargarRegistroEn(await LocalDatabase.instance);

  /// La fila de un alumno, si tiene.
  static Future<MoraCongeladaAlumno?> deEn(
    DatabaseExecutor db,
    String contratoAlumnoId,
  ) async {
    final rows = await db.query(
      'mora_congelada',
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoAlumnoId],
      limit: 1,
    );
    return rows.isEmpty ? null : MoraCongeladaAlumno.fromMap(rows.first);
  }

  /// Guarda las pausas de un alumno: la fila completa y su alta en la cola, en
  /// la misma transacción (en la nube es un upsert). Nunca borra la fila.
  static Future<MoraCongeladaAlumno> guardarEn(
    DatabaseExecutor db, {
    required String contratoAlumnoId,
    String? eventoId,
    required MoraCongelada mora,
    required DateTime ahora,
  }) async {
    final antes = await deEn(db, contratoAlumnoId);
    final fila = MoraCongeladaAlumno.para(
      contratoAlumnoId: contratoAlumnoId,
      eventoId: eventoId ?? antes?.eventoId,
      mora: mora,
      createdAt: antes?.createdAt,
      ahora: ahora,
    );
    await db.insert(
      'mora_congelada',
      fila.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await SyncQueue.enqueue(
      executor: db,
      tabla: 'mora_congelada',
      operacion: SyncOperation.insert,
      registroId: fila.id,
      payload: fila.toMap(),
    );
    return fila;
  }

  /// [guardarEn] en una transacción, y el registro al día para la cuenta.
  Future<void> guardar({
    required String contratoAlumnoId,
    String? eventoId,
    required MoraCongelada mora,
    DateTime? ahora,
  }) async {
    final db = await LocalDatabase.instance;
    await db.transaction(
      (txn) => guardarEn(
        txn,
        contratoAlumnoId: contratoAlumnoId,
        eventoId: eventoId,
        mora: mora,
        ahora: ahora ?? DateTime.now(),
      ),
    );
    MoraCongelada.poner(contratoAlumnoId, mora);
  }
}

final moraCongeladaRepositoryProvider = Provider<MoraCongeladaRepository>(
  (ref) => const MoraCongeladaRepository(),
);
