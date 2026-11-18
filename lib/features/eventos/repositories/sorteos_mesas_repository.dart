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

  /// Le agrega a un renglón **ya escrito** lo que cada familia tenía cargado al
  /// sorteo (`_lugares`), cuando el jefe acepta la lista de una fiesta sorteada
  /// antes de la regla del descuento (17-nov-2026).
  ///
  /// **Es la única vez que se toca un renglón del registro**, y lo aprobó el
  /// usuario con el plan: un renglón aparte rompería "deshacer solo los
  /// últimos", el HISTORIAL y la línea de los papeles. Nada de lo que el
  /// renglón dice del sorteo cambia: se reescribe el texto crudo con la clave
  /// agregada (`SorteoMesasRegistro.resultadoConLugares`), sin pasar por el
  /// modelo, así no se pierde una clave que esta versión no conozca.
  ///
  /// Sube la fila entera como un `insert`, que en la nube es un `upsert`: sirve
  /// igual si el renglón todavía estaba en la cola.
  ///
  /// Devuelve false, sin escribir nada, si el renglón no está en esta PC, no es
  /// un sorteo ni una restauración, o su texto no se puede leer.
  static Future<bool> completarLugaresEn(
    DatabaseExecutor exec,
    String registroId,
    Map<String, String> lugares, {
    DateTime? ahora,
  }) async {
    final filas = await exec.query(
      'sorteos_mesas',
      where: 'id = ?',
      whereArgs: [registroId],
      limit: 1,
    );
    if (filas.isEmpty) return false;
    final fila = Map<String, dynamic>.from(filas.first);
    if (fila['tipo'] == TipoRegistroSorteo.deshacer.clave) return false;
    final texto =
        SorteoMesasRegistro.resultadoConLugares(fila['resultado'], lugares);
    if (texto == null) return false;
    fila['resultado'] = texto;
    fila['updated_at'] = (ahora ?? DateTime.now()).toUtc().toIso8601String();
    await exec.update(
      'sorteos_mesas',
      {'resultado': fila['resultado'], 'updated_at': fila['updated_at']},
      where: 'id = ?',
      whereArgs: [registroId],
    );
    await SyncQueue.enqueue(
      executor: exec,
      tabla: 'sorteos_mesas',
      operacion: SyncOperation.insert,
      registroId: registroId,
      payload: fila,
    );
    return true;
  }

  /// [completarLugaresEn], en una transacción de la base de esta PC.
  Future<bool> completarLugares(
    String registroId,
    Map<String, String> lugares,
  ) async {
    final db = await LocalDatabase.instance;
    return db.transaction(
      (txn) => completarLugaresEn(txn, registroId, lugares),
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
