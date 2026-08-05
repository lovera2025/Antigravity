import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../models/modo_jefe_caja.dart';
import '../models/sesion_caja.dart';
import 'operadores_caja_repository.dart';

class SesionesCajaRepository {
  // ignore: unused_field
  final ConnectivityService _connectivity;
  final SyncEngine _syncEngine;
  final OperadoresCajaRepository _operadores;

  SesionesCajaRepository(
    this._connectivity,
    this._syncEngine,
    this._operadores,
  );

  Future<SesionCaja?> getById(String id) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT s.*, o.nombre AS operador_nombre
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      WHERE s.id = ?
      LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return SesionCaja.fromMap(rows.first);
  }

  /// Todas las sesiones abiertas de un operador, de la más vieja a la más nueva.
  ///
  /// Normalmente hay una sola (índice único parcial). Puede haber más si dos
  /// dispositivos abrieron **sin verse** (sin red): el índice es local a cada
  /// SQLite, así que ninguno lo impide. El orden es determinístico —
  /// `abierta_at ASC, id ASC` — para que todos los dispositivos elijan la misma
  /// apenas sincronizan, en vez de quedar apuntando a filas distintas para
  /// siempre.
  Future<List<SesionCaja>> sesionesAbiertasDeOperador(String operadorId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT s.*, o.nombre AS operador_nombre
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      WHERE s.operador_id = ? AND s.cerrada_at IS NULL
      ORDER BY s.abierta_at ASC, s.id ASC
    ''',
      [operadorId],
    );
    return rows.map(SesionCaja.fromMap).toList();
  }

  Future<SesionCaja?> sesionAbiertaDeOperador(String operadorId) async {
    final abiertas = await sesionesAbiertasDeOperador(operadorId);
    return abiertas.isEmpty ? null : abiertas.first;
  }

  Future<List<SesionCaja>> sesionesAbiertas() async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT s.*, o.nombre AS operador_nombre
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      WHERE s.cerrada_at IS NULL
      ORDER BY s.abierta_at DESC
    ''');
    return rows.map(SesionCaja.fromMap).toList();
  }

  /// Sesiones cuya apertura (reloj AR) cae en el día calendario [dia].
  Future<List<SesionCaja>> sesionesDelDia(DateTime dia) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT s.*, o.nombre AS operador_nombre
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      ORDER BY s.abierta_at DESC
    ''');
    final y = dia.year;
    final m = dia.month;
    final d = dia.day;
    return rows.map(SesionCaja.fromMap).where((s) {
      final ar = ArTime.toAr(s.abiertaAt);
      return ar.year == y && ar.month == m && ar.day == d;
    }).toList();
  }

  Future<double> totalCobradoSesion(String sesionId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM pagos_contrato_alumno
      WHERE sesion_caja_id = ?
        AND (anulado IS NULL OR anulado = 0)
    ''',
      [sesionId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<SesionCaja> abrir({
    required String operadorId,
    required double cambioInicial,
    required String etiqueta,
    String? notaApertura,
    String? deviceId,
  }) async {
    final turno = etiqueta.trim();
    final esJefe = esOperadorModoJefeId(operadorId);
    if (esJefe) {
      if (turno != kEtiquetaModoJefe) {
        throw ArgumentError('La sesión de modo jefe usa la etiqueta "$kEtiquetaModoJefe"');
      }
    } else if (turno != 'Mañana' && turno != 'Tarde') {
      throw ArgumentError('El turno debe ser Mañana o Tarde');
    }
    final abierta = await sesionAbiertaDeOperador(operadorId);
    if (abierta != null) return abierta;

    final now = DateTime.parse(ArTime.nowUtcIso());
    final sesion = SesionCaja(
      id: UuidUtils.generate(),
      operadorId: operadorId,
      abiertaAt: now,
      cambioInicial: cambioInicial.clamp(0, double.infinity),
      notaApertura: notaApertura?.trim().isEmpty == true
          ? null
          : notaApertura?.trim(),
      etiqueta: turno,
      deviceId: deviceId,
      lastHeartbeat: now,
      createdAt: now,
      updatedAt: now,
    );
    final db = await LocalDatabase.instance;
    try {
      await db.insert('sesiones_caja', sesion.toMap());
    } catch (_) {
      final concurrente = await sesionAbiertaDeOperador(operadorId);
      if (concurrente != null) return concurrente;
      rethrow;
    }
    await SyncQueue.enqueue(
      tabla: 'sesiones_caja',
      operacion: SyncOperation.insert,
      registroId: sesion.id,
      payload: sesion.toSyncPayload(),
    );
    return sesion;
  }

  /// Una sola sesión del día calendario AR para cobros en modo jefe.
  /// Sin corte Mañana/Tarde: el jefe no hereda turnos de caja.
  Future<SesionCaja> ensureSesionModoJefe() async {
    final op = await _operadores.ensureOperadorModoJefe();

    // Regla de corte única, compartida con el autocierre del provider: una
    // sesión de ayer se cierra sellada a las 23:59 de ayer, no con la hora del
    // cobro de hoy.
    await cerrarSesionesVencidasDeOperador(
      op.id,
      notaCierre: kNotaCierreCambioDiaJefe,
    );
    // Si dos dispositivos abrieron sin verse, converger en una sola.
    await consolidarSesionesDuplicadas(op.id);

    final abierta = await sesionAbiertaDeOperador(op.id);
    if (abierta != null) {
      // Upsert remoto: si el encolado original quedó dead-letter (id legacy
      // de 4.5.1), esto lo repone. Deduplicado e idempotente.
      await SyncQueue.enqueue(
        tabla: 'sesiones_caja',
        operacion: SyncOperation.insert,
        registroId: abierta.id,
        payload: abierta.toSyncPayload(),
      );
      return abierta.copyWith(operadorNombre: kOperadorModoJefeNombre);
    }

    // Si la sesión jefe del día ya se cerró (arqueo hecho), NO se reutiliza:
    // un cobro posterior abre una sesión nueva para no alterar un cierre ya
    // registrado. El índice único solo limita sesiones ABIERTAS por operador.
    final creada = await abrir(
      operadorId: op.id,
      cambioInicial: 0,
      etiqueta: kEtiquetaModoJefe,
      notaApertura: 'Sesión automática · cobro en modo jefe',
    );
    return creada.copyWith(operadorNombre: kOperadorModoJefeNombre);
  }

  /// Cierra una sesión. [cerradaAtOverride] sella `cerrada_at` en un instante
  /// distinto al actual — lo usan los cierres automáticos para quedar
  /// registrados a las 23:59 del día al que pertenecen, no en el momento en que
  /// se detectaron.
  ///
  /// `updated_at` y `last_heartbeat` siguen siendo el instante real: el motor de
  /// sync usa `updated_at` como watermark, y sellarlo en el pasado dejaría el
  /// UPDATE sin subir nunca.
  Future<SesionCaja> cerrar({
    required String sesionId,
    double? arqueoCierre,
    String? notaCierre,
    DateTime? cerradaAtOverride,
  }) async {
    final actual = await getById(sesionId);
    if (actual == null) throw StateError('Sesión no encontrada');
    if (!actual.estaAbierta) return actual;

    final now = DateTime.parse(ArTime.nowUtcIso());
    final cerrada = actual.copyWith(
      cerradaAt: cerradaAtOverride?.toUtc() ?? now,
      arqueoCierre: arqueoCierre,
      notaCierre: notaCierre?.trim().isEmpty == true
          ? null
          : notaCierre?.trim(),
      lastHeartbeat: now,
      updatedAt: now,
    );
    final db = await LocalDatabase.instance;
    await db.update(
      'sesiones_caja',
      cerrada.toMap(),
      where: 'id = ?',
      whereArgs: [sesionId],
    );
    await SyncQueue.enqueue(
      tabla: 'sesiones_caja',
      operacion: SyncOperation.update,
      registroId: sesionId,
      payload: cerrada.toSyncPayload(),
    );
    return cerrada;
  }

  /// Cierra la sesión abierta del operador (si hay). Usado al eliminar operador.
  Future<SesionCaja?> cerrarAbiertaDeOperador(
    String operadorId, {
    String? notaCierre,
  }) async {
    final abierta = await sesionAbiertaDeOperador(operadorId);
    if (abierta == null) return null;
    return cerrar(
      sesionId: abierta.id,
      notaCierre: notaCierre ?? 'Cerrada al eliminar operador',
    );
  }

  /// Cierra las sesiones abiertas de [operadorId] que pertenecen a un día AR
  /// anterior al de hoy, **sellando cada una a las 23:59:59 de su propio día**.
  ///
  /// El sello es lo que hace que no importe cuándo se detecte: con la app
  /// cerrada no corre nada, así que el cierre ocurre recién al volver a abrir —
  /// pero queda registrado en el día que corresponde, se abra al otro día o tres
  /// días después.
  ///
  /// Idempotente y barato (consulta indexada): se puede llamar en cada tick del
  /// latido y en cada arranque sin costo. Devuelve las sesiones que cerró.
  Future<List<SesionCaja>> cerrarSesionesVencidasDeOperador(
    String operadorId, {
    required String notaCierre,
  }) async {
    final abiertas = await sesionesAbiertasDeOperador(operadorId);
    if (abiertas.isEmpty) return const [];
    final ahora = ArTime.nowUtc();
    final cerradas = <SesionCaja>[];
    for (final s in abiertas) {
      if (ArTime.mismoDia(s.abiertaAt, ahora)) continue;
      cerradas.add(
        await cerrar(
          sesionId: s.id,
          notaCierre: notaCierre,
          cerradaAtOverride: ArTime.finDeDiaArUtc(s.abiertaAt),
        ),
      );
    }
    return cerradas;
  }

  /// Autocierre de la caja de modo jefe al cambiar el día.
  ///
  /// No depende del rol logueado ni crea el operador: se puede llamar desde
  /// cualquier dispositivo, así que la PC del operario que abre a la mañana ya
  /// cierra la caja que el jefe dejó abierta anoche, para todos.
  Future<List<SesionCaja>> cerrarSesionJefeVencida() =>
      cerrarSesionesVencidasDeOperador(
        kOperadorModoJefeId,
        notaCierre: kNotaCierreCambioDiaJefe,
      );

  /// Cierra las sesiones abiertas sobrantes de un operador (solo puede haber
  /// una). Aparecen cuando dos dispositivos abrieron **sin verse** por falta de
  /// red: el índice único es local a cada SQLite y el remoto rechaza la segunda
  /// en silencio.
  ///
  /// Conserva la más vieja — la misma que elige [sesionAbiertaDeOperador] en
  /// todos los dispositivos — y cierra solo las que **no dan señales**: una que
  /// sigue latiendo la está usando alguien ahora mismo, y sacársela de abajo
  /// sería peor que el duplicado.
  Future<List<SesionCaja>> consolidarSesionesDuplicadas(
    String operadorId,
  ) async {
    final abiertas = await sesionesAbiertasDeOperador(operadorId);
    if (abiertas.length < 2) return const [];
    final cerradas = <SesionCaja>[];
    for (final s in abiertas.skip(1)) {
      if (!s.sinSenales()) continue;
      cerradas.add(
        await cerrar(sesionId: s.id, notaCierre: kNotaCierreDuplicada),
      );
    }
    return cerradas;
  }

  /// Cierra cajas abiertas de operadores inactivos o eliminados (sesiones huérfanas).
  Future<int> cerrarSesionesDeOperadoresInactivos() async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT s.id
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      WHERE s.cerrada_at IS NULL
        AND (o.id IS NULL OR o.activo = 0)
    ''');
    var n = 0;
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) continue;
      await cerrar(
        sesionId: id,
        notaCierre: 'Cerrada: operador inactivo o eliminado',
      );
      n++;
    }
    return n;
  }

  Future<void> heartbeat(String sesionId) async {
    final actual = await getById(sesionId);
    if (actual == null || !actual.estaAbierta) return;
    final now = DateTime.parse(ArTime.nowUtcIso());
    final updated = actual.copyWith(lastHeartbeat: now, updatedAt: now);
    final db = await LocalDatabase.instance;
    await db.update(
      'sesiones_caja',
      {
        'last_heartbeat': updated.lastHeartbeat!.toUtc().toIso8601String(),
        'updated_at': updated.updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [sesionId],
    );
    await SyncQueue.enqueue(
      tabla: 'sesiones_caja',
      operacion: SyncOperation.update,
      registroId: sesionId,
      payload: updated.toSyncPayload(),
    );
  }

  /// Borra una sesión de caja (local + cola sync). No toca los pagos:
  /// solo limpia `sesion_caja_id` en cobros que la referencien.
  Future<void> eliminar(String sesionId) async {
    final db = await LocalDatabase.instance;
    final pagos = await db.query(
      'pagos_contrato_alumno',
      where: 'sesion_caja_id = ?',
      whereArgs: [sesionId],
    );
    final nowIso = ArTime.nowUtcIso();
    for (final pago in pagos) {
      final id = pago['id']?.toString();
      if (id == null) continue;
      final actualizado = Map<String, dynamic>.from(pago)
        ..['sesion_caja_id'] = null
        ..['updated_at'] = nowIso;
      await db.update(
        'pagos_contrato_alumno',
        actualizado,
        where: 'id = ?',
        whereArgs: [id],
      );
      actualizado.remove('line_kind');
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.update,
        registroId: id,
        payload: actualizado,
      );
    }
    await db.delete('sesiones_caja', where: 'id = ?', whereArgs: [sesionId]);
    await SyncQueue.enqueue(
      tabla: 'sesiones_caja',
      operacion: SyncOperation.delete,
      registroId: sesionId,
      payload: {'id': sesionId},
    );
  }

  /// Sube pendientes best-effort (cierre / heartbeat). No lanza si no hay red.
  Future<void> flushBestEffort({DateTime? createdSince}) async {
    try {
      await _syncEngine.flushPending(createdSince: createdSince);
    } catch (_) {}
  }

  /// Sube pendientes e informa si [sesionId] **realmente** llegó al servidor:
  /// después del intento, ¿quedó algo suyo en la cola?
  ///
  /// `flushPending` nunca lanza — sin conexión sale por lo silencioso —, así que
  /// preguntarle a la cola es la única forma honesta de saberlo. Lo necesita el
  /// cierre de caja: un cierre que no subió reaparece horas después en otra PC
  /// como "caja abierta", y si nadie avisó en el momento eso se vive como un bug
  /// del programa en vez de como lo que es, una PC que estaba sin internet.
  Future<bool> flushConfirmandoSesion(String sesionId) async {
    await flushBestEffort();
    try {
      final db = await LocalDatabase.instance;
      final rows = await db.rawQuery(
        '''
        SELECT 1 FROM _sync_queue
        WHERE tabla = 'sesiones_caja' AND registro_id = ?
        LIMIT 1
      ''',
        [sesionId],
      );
      return rows.isEmpty;
    } catch (_) {
      return false;
    }
  }
}

final sesionesCajaRepositoryProvider = Provider<SesionesCajaRepository>((ref) {
  return SesionesCajaRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
    ref.watch(operadoresCajaRepositoryProvider),
  );
});
