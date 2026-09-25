import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../main.dart';
import '../../../models/entradas_retiro.dart';

/// Retiro de entradas por alumno — SQLite + cola → Supabase.
///
/// Una fila por alumno con id fijo (`UuidUtils.entradasRetiroId`): un egresado
/// no puede tener dos retiros, porque las dos PCs escriben la misma fila.
/// Solo lee `contratos_alumnos` y los pagos; nunca los escribe.
class EntradasRetiroRepository {
  final SupabaseClient _supabase;

  EntradasRetiroRepository(this._supabase);

  Future<Map<String, EntradasRetiro>> obtenerPorContratoIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    final db = await LocalDatabase.instance;
    final unicos = ids.toSet().toList();
    final marcas = List.filled(unicos.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM entradas_retiro WHERE contrato_alumno_id IN ($marcas)',
      unicos,
    );
    return {
      for (final r in rows)
        (r['contrato_alumno_id'] as String): EntradasRetiro.fromMap(r),
    };
  }

  /// Guarda la fila completa y la encola. Se encola como alta: en la nube es un
  /// upsert, así que anda igual si la fila ya existía (una anulación, una
  /// entrega completada) o si todavía no llegó.
  Future<void> guardar(EntradasRetiro retiro) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      await txn.insert(
        'entradas_retiro',
        retiro.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await SyncQueue.enqueue(
        executor: txn,
        tabla: 'entradas_retiro',
        operacion: SyncOperation.insert,
        registroId: retiro.id,
        payload: retiro.toMap(),
      );
    });
  }

  /// Lo que dice la nube del retiro de este alumno, justo antes de entregar:
  /// si la otra PC ya entregó hace un minuto, todavía puede no haber bajado.
  ///
  /// Si la nube lo tiene y acá no hay un cambio propio esperando subir, lo deja
  /// guardado igual que lo haría la bajada, para que la pantalla lo muestre ya.
  /// Tira si no hay red: quien llama decide qué avisar.
  Future<EntradasRetiro?> traerDeLaNube(String contratoAlumnoId) async {
    final fila = await _supabase
        .from('entradas_retiro')
        .select()
        .eq('contrato_alumno_id', contratoAlumnoId)
        .maybeSingle()
        .timeout(const Duration(seconds: 6));
    if (fila == null) return null;
    final retiro = EntradasRetiro.fromMap(fila);

    final db = await LocalDatabase.instance;
    final pendiente = await db.query(
      '_sync_queue',
      columns: ['id'],
      where: 'tabla = ? AND registro_id = ?',
      whereArgs: ['entradas_retiro', retiro.id],
      limit: 1,
    );
    if (pendiente.isEmpty) {
      await db.insert(
        'entradas_retiro',
        retiro.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return retiro;
  }
}

final entradasRetiroRepositoryProvider = Provider<EntradasRetiroRepository>(
  (ref) => EntradasRetiroRepository(ref.watch(supabaseProvider)),
);
