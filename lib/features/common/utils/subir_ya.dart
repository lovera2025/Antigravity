import 'dart:async';

import '../../../core/database/local_database.dart';
import '../../../core/services/sync_engine.dart';

/// Sube ya lo que se acaba de guardar, con reintentos si el motor está
/// ocupado. Devuelve `true` si el registro dejó la cola (llegó a la nube).
///
/// Lógica pura, separada del motor para poder probarla: [subir] intenta la
/// subida, [pendiente] dice si el registro sigue en la cola y [ocupado] si el
/// motor está en medio de otra sincronización.
///
/// Si el motor está ocupado, `flushPending` sale sin subir nada: por eso se
/// espera un poco y se vuelve a probar. Si no está ocupado y el registro sigue
/// en la cola, es que no hay red o la nube lo rechazó: no tiene sentido insistir
/// acá, queda en la cola y el ciclo de siempre lo sube cuando pueda.
Future<bool> subirConReintentos({
  required Future<void> Function() subir,
  required Future<bool> Function() pendiente,
  required bool Function() ocupado,
  int intentos = 10,
  Duration espera = const Duration(milliseconds: 400),
}) async {
  for (var i = 0; i < intentos; i++) {
    await subir();
    if (!await pendiente()) return true;
    if (!ocupado()) return false;
    await Future<void>.delayed(espera);
  }
  return !await pendiente();
}

/// Sube ya el registro [registroId] de [tabla] (y lo que se haya encolado desde
/// [desde]), sin esperar el ciclo de 10 s y sin depender del rol elegido.
///
/// Existe para lo que dos PCs pueden tocar a la vez desde el mostrador —una
/// entrega de entradas, el reparto de sillas—: cuanto antes llega a la nube,
/// antes le avisa el pulso a la otra PC y antes lo ve. Sin esto, la PC del jefe
/// tardaba hasta 10 s en subir, y una sesión sin rol elegido (Asesor) no subía
/// sola si la subida automática caía justo cuando el motor estaba ocupado.
Future<bool> subirYa(
  SyncEngine engine, {
  required String tabla,
  required String registroId,
  required DateTime desde,
}) =>
    subirConReintentos(
      subir: () => engine.flushPending(createdSince: desde),
      pendiente: () async {
        final db = await LocalDatabase.instance;
        final rows = await db.rawQuery(
          'SELECT 1 FROM _sync_queue WHERE tabla = ? AND registro_id = ? LIMIT 1',
          [tabla, registroId],
        );
        return rows.isNotEmpty;
      },
      ocupado: () =>
          engine.status == SyncStatus.syncing ||
          engine.status == SyncStatus.wakingUp ||
          engine.status == SyncStatus.probing,
    );
