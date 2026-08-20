import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/uuid_utils.dart';
import '../cierre_caja_sync_config.dart';
import '../models/guia_cambio_movimiento.dart';
import '../models/turno_caja.dart';

class GuiaCambioResumen {
  final double saldoActual;
  final List<GuiaCambioMovimiento> movimientos;
  final int cantReposiciones;
  final int cantUsos;
  final int cantAjustes;
  final double totalReposiciones;
  final double totalUsos;

  const GuiaCambioResumen({
    required this.saldoActual,
    required this.movimientos,
    this.cantReposiciones = 0,
    this.cantUsos = 0,
    this.cantAjustes = 0,
    this.totalReposiciones = 0,
    this.totalUsos = 0,
  });
}

class CierreCajaRepository {
  // Inyectados para alinear con el patrón offline-first del resto de repos.
  // ignore: unused_field
  final ConnectivityService _connectivity;
  // ignore: unused_field
  final SyncEngine _syncEngine;

  CierreCajaRepository(this._connectivity, this._syncEngine);

  static String fechaIso(DateTime dia) =>
      '${dia.year.toString().padLeft(4, '0')}-'
      '${dia.month.toString().padLeft(2, '0')}-'
      '${dia.day.toString().padLeft(2, '0')}';

  void _validarFechaSync(String fechaIso) {
    if (!cierreCajaFechaElegibleSync(fechaIso)) {
      throw StateError(
        'La guía de cambio y anotaciones sincronizan desde el '
        '$kCierreCajaSyncFechaCorte en adelante.',
      );
    }
  }

  Future<double> _saldoActualSesion(String sesionCajaId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'cierre_caja_guia_movimientos',
      columns: ['saldo_despues'],
      where: 'sesion_caja_id = ?',
      whereArgs: [sesionCajaId],
      orderBy: 'fecha_mov DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['saldo_despues'] as num?)?.toDouble() ?? 0;
  }

  Future<GuiaCambioResumen> obtenerGuiaCambioSesiones(
    Iterable<String> sesionIds,
  ) async {
    final ids = sesionIds.toSet().toList();
    if (ids.isEmpty) {
      return const GuiaCambioResumen(saldoActual: 0, movimientos: []);
    }
    final db = await LocalDatabase.instance;
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM cierre_caja_guia_movimientos '
      'WHERE sesion_caja_id IN ($marks) '
      'ORDER BY fecha_mov DESC, created_at DESC',
      ids,
    );
    final movs = rows.map((r) => GuiaCambioMovimiento.fromMap(r)).toList();

    var repos = 0, usos = 0, ajustes = 0;
    var totalRep = 0.0, totalUso = 0.0;
    for (final m in movs) {
      switch (m.tipo) {
        case TipoGuiaCambioMovimiento.reposicion:
          repos++;
          totalRep += m.monto;
        case TipoGuiaCambioMovimiento.uso:
          usos++;
          totalUso += m.monto;
        case TipoGuiaCambioMovimiento.ajuste:
          ajustes++;
      }
    }

    final saldos = <String, double>{};
    for (final m in movs) {
      final sid = m.sesionCajaId;
      if (sid != null) saldos.putIfAbsent(sid, () => m.saldoDespues);
    }
    final saldo = saldos.values.fold<double>(0, (a, b) => a + b);
    return GuiaCambioResumen(
      saldoActual: saldo,
      movimientos: movs,
      cantReposiciones: repos,
      cantUsos: usos,
      cantAjustes: ajustes,
      totalReposiciones: totalRep,
      totalUsos: totalUso,
    );
  }

  static String fechaIsoDia(DateTime dia) => fechaIso(dia);

  Future<void> _insertarMovimientoGuia({
    required String fechaIso,
    required String sesionCajaId,
    required TipoGuiaCambioMovimiento tipo,
    required double monto,
    required double saldoAntes,
    required double saldoDespues,
    String? nota,
  }) async {
    _validarFechaSync(fechaIso);
    final id = UuidUtils.generate();
    final nowIso = ArTime.nowUtcIso();
    final data = <String, dynamic>{
      'id': id,
      'fecha': fechaIso,
      'tipo': tipo.slug,
      'monto': monto,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'nota': nota?.trim().isEmpty == true ? null : nota?.trim(),
      'sesion_caja_id': sesionCajaId,
      'fecha_mov': nowIso,
      'created_at': nowIso,
      'updated_at': nowIso,
    };
    final db = await LocalDatabase.instance;
    await db.insert('cierre_caja_guia_movimientos', data);
    await SyncQueue.enqueue(
      tabla: 'cierre_caja_guia_movimientos',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: data,
    );
    debugPrint('📥 Guía cambio: ${tipo.slug} $monto ($fechaIso)');
  }

  Future<void> registrarReposicion({
    required DateTime dia,
    required String sesionCajaId,
    required double monto,
    String? nota,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualSesion(sesionCajaId);
    await _insertarMovimientoGuia(
      fechaIso: f,
      sesionCajaId: sesionCajaId,
      tipo: TipoGuiaCambioMovimiento.reposicion,
      monto: monto,
      saldoAntes: antes,
      saldoDespues: antes + monto,
      nota: nota,
    );
  }

  Future<void> registrarUso({
    required DateTime dia,
    required String sesionCajaId,
    required double monto,
    String? nota,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualSesion(sesionCajaId);
    final despues = (antes - monto).clamp(0.0, double.infinity);
    await _insertarMovimientoGuia(
      fechaIso: f,
      sesionCajaId: sesionCajaId,
      tipo: TipoGuiaCambioMovimiento.uso,
      monto: monto,
      saldoAntes: antes,
      saldoDespues: despues,
      nota: nota,
    );
  }

  Future<void> registrarAjuste({
    required DateTime dia,
    required String sesionCajaId,
    required double saldoReal,
    String? nota,
  }) async {
    if (saldoReal < 0) {
      throw ArgumentError('El saldo no puede ser negativo.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualSesion(sesionCajaId);
    if ((antes - saldoReal).abs() < 0.001) return;
    await _insertarMovimientoGuia(
      fechaIso: f,
      sesionCajaId: sesionCajaId,
      tipo: TipoGuiaCambioMovimiento.ajuste,
      monto: (saldoReal - antes).abs(),
      saldoAntes: antes,
      saldoDespues: saldoReal,
      nota: nota,
    );
  }

  Future<String?> obtenerAnotacionTexto(String sesionCajaId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'cierre_caja_anotaciones',
      where: 'sesion_caja_id = ?',
      whereArgs: [sesionCajaId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['texto']?.toString();
  }

  /// Sesiones del lote que tienen una nota no vacía (para el chip del jefe).
  Future<Set<String>> sesionesConAnotacion(Iterable<String> sesionIds) async {
    final ids = sesionIds.toSet().toList();
    if (ids.isEmpty) return {};
    final db = await LocalDatabase.instance;
    final marks = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT sesion_caja_id FROM cierre_caja_anotaciones '
      'WHERE sesion_caja_id IN ($marks) '
      "AND TRIM(COALESCE(texto, '')) <> ''",
      ids,
    );
    return {
      for (final r in rows)
        if ((r['sesion_caja_id']?.toString() ?? '').isNotEmpty)
          r['sesion_caja_id'].toString(),
    };
  }

  Future<void> guardarAnotacion({
    required DateTime dia,
    required TurnoCaja turno,
    required String sesionCajaId,
    required String texto,
  }) async {
    final f = fechaIsoDia(dia);
    _validarFechaSync(f);
    final t = texto.trim();
    final id = sesionCajaId;
    final db = await LocalDatabase.instance;
    final nowIso = ArTime.nowUtcIso();
    final existente = await db.query(
      'cierre_caja_anotaciones',
      where: 'sesion_caja_id = ?',
      whereArgs: [sesionCajaId],
      limit: 1,
    );

    if (t.isEmpty) {
      if (existente.isNotEmpty) {
        await db.delete(
          'cierre_caja_anotaciones',
          where: 'id = ?',
          whereArgs: [id],
        );
        await SyncQueue.enqueue(
          tabla: 'cierre_caja_anotaciones',
          operacion: SyncOperation.delete,
          registroId: id,
          payload: {'id': id},
        );
      }
      return;
    }

    if (existente.isEmpty) {
      final data = <String, dynamic>{
        'id': id,
        'fecha': f,
        'turno': turno.slug,
        'sesion_caja_id': sesionCajaId,
        'texto': t,
        'created_at': nowIso,
        'updated_at': nowIso,
      };
      await db.insert('cierre_caja_anotaciones', data);
      await SyncQueue.enqueue(
        tabla: 'cierre_caja_anotaciones',
        operacion: SyncOperation.insert,
        registroId: id,
        payload: data,
      );
    } else {
      final createdIso = existente.first['created_at']?.toString() ?? nowIso;
      await db.update(
        'cierre_caja_anotaciones',
        {'texto': t, 'updated_at': nowIso},
        where: 'id = ?',
        whereArgs: [id],
      );
      await SyncQueue.enqueue(
        tabla: 'cierre_caja_anotaciones',
        operacion: SyncOperation.update,
        registroId: id,
        payload: {
          'id': id,
          'fecha': f,
          'turno': turno.slug,
          'sesion_caja_id': sesionCajaId,
          'texto': t,
          'created_at': createdIso,
          'updated_at': nowIso,
        },
      );
    }
  }
}

final cierreCajaRepositoryProvider = Provider<CierreCajaRepository>((ref) {
  return CierreCajaRepository(
    ref.watch(connectivityServiceProvider),
    ref.watch(syncEngineProvider),
  );
});
