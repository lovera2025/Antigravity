import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/como_lo_nombran.dart';

/// **Cómo nombra el locutor** a cada egresado (`como_lo_nombran`, v85) — SQLite + cola →
/// Supabase. Anda sin internet: se escribe en la PC y sube cuando hay.
///
/// Una fila por alumno con id fijo. **Nunca se borra**: volver a la lista la deja vacía.
/// No hay `delete` acá ni en la cola. No toca `contratos_alumnos` ni `invitados`.
class ComoLoNombranRepository {
  final _cambios = StreamController<String>.broadcast();

  /// El evento de lo que escribió esta PC, al escribirlo.
  Stream<String> get cambios => _cambios.stream;

  /// Las del evento, por id de contrato. Una fila con un id que no es el fijo de su
  /// alumno no se toma (la escribió algo que no es esta app).
  Future<Map<String, ComoLoNombran>> delEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final filas = await db.query('como_lo_nombran', where: 'evento_id = ?', whereArgs: [eventoId]);
    return {
      for (final f in filas)
        if (ComoLoNombran.fromMap(f) case final c when c.id == UuidUtils.comoLoNombranId(c.contratoAlumnoId))
          c.contratoAlumnoId: c,
    };
  }

  /// La de un alumno, leída en el momento.
  Future<ComoLoNombran?> deAlumno(String contratoAlumnoId) async {
    final db = await LocalDatabase.instance;
    final filas = await db.query(
      'como_lo_nombran',
      where: 'id = ?',
      whereArgs: [UuidUtils.comoLoNombranId(contratoAlumnoId)],
      limit: 1,
    );
    return filas.isEmpty ? null : ComoLoNombran.fromMap(filas.first);
  }

  /// Cuántas del evento esperan subir (para "Todo subido" de Recepción).
  Future<int> sinSubir(String eventoId) async {
    final db = await LocalDatabase.instance;
    final filas = await db.rawQuery(
      'SELECT COUNT(DISTINCT q.registro_id) AS n FROM _sync_queue q '
      'JOIN como_lo_nombran c ON c.id = q.registro_id '
      "WHERE q.tabla = 'como_lo_nombran' AND c.evento_id = ?",
      [eventoId],
    );
    return (filas.first['n'] as int?) ?? 0;
  }

  /// En la base y en la cola, juntas. Se encola como alta: en la nube es un upsert.
  Future<void> guardar(ComoLoNombran fila) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      await txn.insert('como_lo_nombran', fila.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await SyncQueue.enqueue(
        executor: txn,
        tabla: 'como_lo_nombran',
        operacion: SyncOperation.insert,
        registroId: fila.id,
        payload: fila.toMap(),
      );
    });
    _cambios.add(fila.eventoId);
  }
}

final comoLoNombranRepositoryProvider = Provider<ComoLoNombranRepository>((ref) => ComoLoNombranRepository());
