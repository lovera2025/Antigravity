import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../models/movimiento_mesas.dart';

/// Los cambios de mesa de las familias — SQLite + cola → Supabase. Solo se
/// agregan renglones: deshacer es un renglón más, nunca un borrado.
class MesasMovimientosRepository {
  /// Agrega un renglón con el ejecutor que le pasen. Los cambios lo llaman
  /// adentro de la misma transacción que escribe los números: o quedan los
  /// números y su renglón, o ninguno de los dos.
  static Future<void> registrarEn(
    DatabaseExecutor exec,
    MovimientoMesas movimiento,
  ) async {
    await exec.insert('mesas_movimientos', movimiento.toMap());
    await SyncQueue.enqueue(
      executor: exec,
      tabla: 'mesas_movimientos',
      operacion: SyncOperation.insert,
      registroId: movimiento.id,
      payload: movimiento.toMap(),
    );
  }

  /// Los renglones de la fiesta, del más viejo al más nuevo.
  Future<List<MovimientoMesas>> delEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'mesas_movimientos',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(MovimientoMesas.fromMap).toList();
  }
}

final mesasMovimientosRepositoryProvider =
    Provider<MesasMovimientosRepository>(
  (ref) => MesasMovimientosRepository(),
);
