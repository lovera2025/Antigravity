import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../main.dart';
import '../../../models/predio.dart';

/// Los predios con nombre (6.1.0) — SQLite + cola → Supabase.
///
/// Son de todas las fiestas. Guardar, renombrar y borrar es del jefe, desde la
/// pantalla del plano (`test/solo_modo_jefe_test.dart`); quien solo los lee
/// entra por [leerPrediosProvider].
///
/// **Nada se borra de la base:** borrar un predio es guardarlo con
/// `borrado_at`. Una PC que estaba apagada se entera igual, en la bajada.
class PrediosRepository {
  final SupabaseClient _supabase;

  PrediosRepository(this._supabase);

  /// Los que se pueden elegir, por nombre: sin los borrados.
  static Future<List<Predio>> todosEn(DatabaseExecutor exec) async {
    final rows = await exec.query(
      'predios',
      where: 'borrado_at IS NULL',
    );
    return [for (final r in rows) Predio.fromMap(r)]
      ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
  }

  Future<List<Predio>> todos() async => todosEn(await LocalDatabase.instance);

  /// Guarda la fila completa y la encola como alta: en la nube es un upsert,
  /// que anda igual si la fila ya existía o si todavía no llegó.
  static Future<void> guardarEn(DatabaseExecutor exec, Predio predio) async {
    await exec.insert(
      'predios',
      predio.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await SyncQueue.enqueue(
      executor: exec,
      tabla: 'predios',
      operacion: SyncOperation.insert,
      registroId: predio.id,
      payload: predio.toMap(),
    );
  }

  Future<void> guardar(Predio predio) async {
    final db = await LocalDatabase.instance;
    await db.transaction((txn) => guardarEn(txn, predio));
  }

  /// Lo que dice la nube de los predios, antes de cambiar uno: si la otra PC
  /// guardó o renombró hace un momento, todavía puede no haber bajado.
  ///
  /// Lo que la nube tiene y acá no espera subir queda guardado igual que lo
  /// haría la bajada; lo que espera subir manda. Tira si no hay red: quien
  /// llama decide qué avisar.
  Future<List<Predio>> traerDeLaNube() async {
    final filas = await _supabase
        .from('predios')
        .select()
        .timeout(const Duration(seconds: 6));
    final db = await LocalDatabase.instance;
    await db.transaction((txn) => guardarLoDeLaNubeEn(txn, filas));
    return todos();
  }

  /// La mitad de [traerDeLaNube] que escribe, aparte para probarla sin red.
  static Future<void> guardarLoDeLaNubeEn(
    DatabaseExecutor exec,
    List<Map<String, dynamic>> filas,
  ) async {
    final pendientes = {
      for (final r in await exec.query(
        '_sync_queue',
        columns: ['registro_id'],
        where: 'tabla = ?',
        whereArgs: ['predios'],
      ))
        r['registro_id'] as String,
    };
    for (final f in filas) {
      final id = f['id'];
      if (id is! String || id.length != 36 || pendientes.contains(id)) continue;
      await exec.insert(
        'predios',
        Predio.fromMap(f).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}

final prediosRepositoryProvider = Provider<PrediosRepository>(
  (ref) => PrediosRepository(ref.watch(supabaseProvider)),
);

/// Para quien solo lee los predios, de la base de esta PC: no da cómo
/// guardarlos.
final leerPrediosProvider = Provider<Future<List<Predio>> Function()>(
  (ref) => ref.watch(prediosRepositoryProvider).todos,
);
