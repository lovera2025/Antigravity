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

  Future<SesionCaja?> sesionAbiertaDeOperador(String operadorId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT s.*, o.nombre AS operador_nombre
      FROM sesiones_caja s
      LEFT JOIN operadores_caja o ON o.id = s.operador_id
      WHERE s.operador_id = ? AND s.cerrada_at IS NULL
      ORDER BY s.abierta_at DESC
      LIMIT 1
    ''',
      [operadorId],
    );
    if (rows.isEmpty) return null;
    return SesionCaja.fromMap(rows.first);
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
    final hoy = ArTime.nowAr();
    final y = hoy.year;
    final m = hoy.month;
    final d = hoy.day;

    final abierta = await sesionAbiertaDeOperador(op.id);
    if (abierta != null) {
      final ar = ArTime.toAr(abierta.abiertaAt);
      final sameDay = ar.year == y && ar.month == m && ar.day == d;
      if (sameDay) {
        return abierta.copyWith(operadorNombre: kOperadorModoJefeNombre);
      }
      await cerrar(
        sesionId: abierta.id,
        notaCierre: 'Cerrada al iniciar jornada (modo jefe)',
      );
    }

    // Reusar cualquier sesión jefe del día (compat con etiquetas Mañana/Tarde previas).
    final delDia = await sesionesDelDia(DateTime(y, m, d));
    for (final s in delDia) {
      if (s.operadorId == op.id) {
        return s.copyWith(operadorNombre: kOperadorModoJefeNombre);
      }
    }

    final creada = await abrir(
      operadorId: op.id,
      cambioInicial: 0,
      etiqueta: kEtiquetaModoJefe,
      notaApertura: 'Sesión automática · cobro en modo jefe',
    );
    return creada.copyWith(operadorNombre: kOperadorModoJefeNombre);
  }

  Future<SesionCaja> cerrar({
    required String sesionId,
    double? arqueoCierre,
    String? notaCierre,
  }) async {
    final actual = await getById(sesionId);
    if (actual == null) throw StateError('Sesión no encontrada');
    if (!actual.estaAbierta) return actual;

    final now = DateTime.parse(ArTime.nowUtcIso());
    final cerrada = actual.copyWith(
      cerradaAt: now,
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
}

final sesionesCajaRepositoryProvider = Provider<SesionesCajaRepository>((ref) {
  return SesionesCajaRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
    ref.watch(operadoresCajaRepositoryProvider),
  );
});
