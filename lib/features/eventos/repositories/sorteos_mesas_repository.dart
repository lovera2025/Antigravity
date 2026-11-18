import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../services/lugares_al_sorteo.dart';

/// Registro de sorteos — SQLite + cola → Supabase. Solo se agregan renglones.
class SorteosMesasRepository {
  /// Agrega un renglón con el ejecutor que le pasen. El sorteo lo llama adentro
  /// de la misma transacción que escribe los números: o quedan los números y su
  /// registro, o ninguno de los dos.
  static Future<void> registrarEn(
    DatabaseExecutor exec,
    SorteoMesasRegistro registro,
  ) async {
    await exec.insert('sorteos_mesas', registro.toMap());
    await SyncQueue.enqueue(
      executor: exec,
      tabla: 'sorteos_mesas',
      operacion: SyncOperation.insert,
      registroId: registro.id,
      payload: registro.toMap(),
    );
  }

  /// Los renglones del evento, del más viejo al más nuevo.
  Future<List<SorteoMesasRegistro>> delEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'sorteos_mesas',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(SorteoMesasRegistro.fromMap).toList();
  }
}

final sorteosMesasRepositoryProvider = Provider<SorteosMesasRepository>(
  (ref) => SorteosMesasRepository(),
);

/// Lo que cada familia tenía cargado al sorteo de una fiesta
/// ([LugaresAlSorteo.vigente]), para quien solo lo lee: la entrega, la venta de
/// entradas y los papeles. Sale del registro de esta PC, así que anda sin
/// internet. **Si no se puede leer, todo va con descuento, como antes de la
/// regla**: una lectura que falla no le cobra la entrada entera a nadie. En la
/// web no hay base.
final fotoDeLosLugaresProvider =
    Provider<Future<FotoDeLosLugares> Function(String eventoId)>((ref) {
  if (kIsWeb) return (_) async => FotoDeLosLugares.sinSorteo;
  final repo = ref.read(sorteosMesasRepositoryProvider);
  return (eventoId) async {
    try {
      return LugaresAlSorteo.vigente(await repo.delEvento(eventoId));
    } catch (_) {
      return FotoDeLosLugares.sinSorteo;
    }
  };
});
