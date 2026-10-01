import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../main.dart';
import '../../../models/plano_evento.dart';

/// El plano de cada fiesta — SQLite + cola → Supabase.
///
/// Una fila por fiesta con id fijo (`UuidUtils.planoEventoId`): las dos PCs
/// escriben la misma. No toca `contratos_alumnos`: los números de mesa siguen
/// yendo por `ContratosRepository.asignarNumerosMesa`.
class PlanosEventoRepository {
  final SupabaseClient _supabase;

  PlanosEventoRepository(this._supabase);

  Future<PlanoEvento?> obtener(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'planos_evento',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      limit: 1,
    );
    return rows.isEmpty ? null : PlanoEvento.fromMap(rows.first);
  }

  /// Guarda la fila completa y la encola como alta: en la nube es un upsert,
  /// que anda igual si la fila ya existía o si todavía no llegó.
  Future<void> guardar(PlanoEvento plano) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) => guardarEn(txn, plano));
  }

  /// Lo mismo, dentro de una transacción ajena: el sorteo guarda los bloques
  /// en la misma transacción que los números.
  static Future<void> guardarEn(DatabaseExecutor exec, PlanoEvento plano) async {
    // Con otro id, acá el REPLACE pisaría sin avisar el plano que ya está (por
    // el UNIQUE de evento_id), y en la nube la fila quedaría trabada en la cola.
    // Dentro del sorteo, esto deshace la transacción entera: no queda nada a
    // medias.
    if (!plano.tieneIdFijo) {
      throw ArgumentError.value(
        plano.id,
        'plano.id',
        'el plano de una fiesta lleva el id de UuidUtils.planoEventoId',
      );
    }
    await exec.insert(
      'planos_evento',
      plano.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await SyncQueue.enqueue(
      executor: exec,
      tabla: 'planos_evento',
      operacion: SyncOperation.insert,
      registroId: plano.id,
      payload: plano.toMap(),
    );
  }

  /// Lo que dice la nube del plano de la fiesta, antes de cambiarlo: si la otra
  /// PC lo tocó hace un momento, todavía puede no haber bajado.
  ///
  /// Si la nube lo tiene y acá no hay un cambio propio esperando subir, lo deja
  /// guardado igual que lo haría la bajada. Tira si no hay red: quien llama
  /// decide qué avisar.
  Future<PlanoEvento?> traerDeLaNube(String eventoId) async {
    final fila = await _supabase
        .from('planos_evento')
        .select()
        .eq('evento_id', eventoId)
        .maybeSingle()
        .timeout(const Duration(seconds: 6));
    if (fila == null) return null;
    final plano = PlanoEvento.fromMap(fila);
    // Uno con otro id (cargado a mano en la nube) no se guarda: pisaría el de
    // esta PC por el UNIQUE de evento_id. Es la misma regla que la bajada
    // (`planoTraeIdFijo`). Manda lo que haya acá.
    if (!plano.tieneIdFijo) return obtener(eventoId);

    final db = await LocalDatabase.instance;
    final pendiente = await db.query(
      '_sync_queue',
      columns: ['id'],
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: ['planos_evento', plano.id],
      limit: 1,
    );
    if (pendiente.isEmpty) {
      await db.insert(
        'planos_evento',
        plano.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return plano;
    }
    return await obtener(eventoId) ?? plano;
  }
}

final planosEventoRepositoryProvider = Provider<PlanosEventoRepository>(
  (ref) => PlanosEventoRepository(ref.watch(supabaseProvider)),
);
