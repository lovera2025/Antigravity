import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../../../models/silla_puerta.dart';

/// Las sillas sumadas la noche de la fiesta (`SillaPuerta`) — SQLite + cola →
/// Supabase. Anda sin internet: se escribe en la PC y sube cuando hay.
///
/// **Las filas solo se agregan.** Quitar una silla reescribe la misma fila con
/// `quitada_at`, quién y el motivo: no hay `delete`, ni acá ni en la cola. No
/// toca `contratos_alumnos`.
class SillasPuertaRepository {
  final _cambios = StreamController<String>.broadcast();

  /// El evento de lo que escribió esta PC, al escribirlo.
  Stream<String> get cambios => _cambios.stream;

  /// Todas las del evento, vigentes y quitadas, en el orden en que se anotaron.
  Future<List<SillaPuerta>> delEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final filas = await db.query(
      'sillas_puerta',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'created_at, id',
    );
    return [for (final f in filas) SillaPuerta.fromMap(f)];
  }

  /// Las vigentes de una familia, leídas en el momento.
  Future<List<SillaPuerta>> vigentesDe(String contratoAlumnoId) async {
    final db = await LocalDatabase.instance;
    final filas = await db.query(
      'sillas_puerta',
      where: 'contrato_alumno_id = ? AND quitada_at IS NULL',
      whereArgs: [contratoAlumnoId],
      orderBy: 'created_at, id',
    );
    return [for (final f in filas) SillaPuerta.fromMap(f)];
  }

  /// Anota una silla nueva y la encola.
  Future<SillaPuerta> anotar({
    required String eventoId,
    required String contratoAlumnoId,
    required int mesa,
    required String vale,
    String? anotadoPor,
    String? nota,
  }) async {
    final ahora = ArTime.nowUtc();
    final fila = SillaPuerta(
      id: UuidUtils.generate(),
      eventoId: eventoId,
      contratoAlumnoId: contratoAlumnoId,
      mesa: mesa,
      vale: vale.trim(),
      anotadoPor: anotadoPor,
      nota: nota,
      createdAt: ahora,
      updatedAt: ahora,
    );
    await _escribir(fila);
    return fila;
  }

  /// La quita: le pone `quitada_at`, quién y el motivo. Null si no estaba o ya
  /// estaba quitada.
  Future<SillaPuerta?> quitar(
    String id, {
    required String por,
    required String motivo,
  }) async {
    final db = await LocalDatabase.instance;
    final filas = await db.query(
      'sillas_puerta',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    final antes = SillaPuerta.fromMap(filas.first);
    if (!antes.vigente) return null;
    final fila = antes.quitada(por: por, motivo: motivo, ahora: ArTime.nowUtc());
    await _escribir(fila);
    return fila;
  }

  /// En la base y en la cola, juntas. Se encola como alta: en la nube es un
  /// upsert, que anda igual si la fila ya estaba o si todavía no llegó.
  Future<void> _escribir(SillaPuerta fila) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      await txn.insert(
        'sillas_puerta',
        fila.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await SyncQueue.enqueue(
        executor: txn,
        tabla: 'sillas_puerta',
        operacion: SyncOperation.insert,
        registroId: fila.id,
        payload: fila.toMap(),
      );
    });
    _cambios.add(fila.eventoId);
  }
}

final sillasPuertaRepositoryProvider = Provider<SillasPuertaRepository>(
  (ref) => SillasPuertaRepository(),
);
