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

  Future<double> _saldoActualDia(String fechaIso) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'cierre_caja_guia_movimientos',
      columns: ['saldo_despues'],
      where: 'fecha = ?',
      whereArgs: [fechaIso],
      orderBy: 'fecha_mov DESC, created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['saldo_despues'] as num?)?.toDouble() ?? 0;
  }

  Future<GuiaCambioResumen> obtenerGuiaCambioDia(DateTime dia) async {
    final fechaIso = fechaIsoDia(dia);
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'cierre_caja_guia_movimientos',
      where: 'fecha = ?',
      whereArgs: [fechaIso],
      orderBy: 'fecha_mov DESC, created_at DESC',
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

    final saldo = movs.isEmpty ? 0.0 : movs.first.saldoDespues;
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
    required double monto,
    String? nota,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualDia(f);
    await _insertarMovimientoGuia(
      fechaIso: f,
      tipo: TipoGuiaCambioMovimiento.reposicion,
      monto: monto,
      saldoAntes: antes,
      saldoDespues: antes + monto,
      nota: nota,
    );
  }

  Future<void> registrarUso({
    required DateTime dia,
    required double monto,
    String? nota,
  }) async {
    if (monto <= 0) {
      throw ArgumentError('El monto debe ser mayor a cero.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualDia(f);
    final despues = (antes - monto).clamp(0.0, double.infinity);
    await _insertarMovimientoGuia(
      fechaIso: f,
      tipo: TipoGuiaCambioMovimiento.uso,
      monto: monto,
      saldoAntes: antes,
      saldoDespues: despues,
      nota: nota,
    );
  }

  Future<void> registrarAjuste({
    required DateTime dia,
    required double saldoReal,
    String? nota,
  }) async {
    if (saldoReal < 0) {
      throw ArgumentError('El saldo no puede ser negativo.');
    }
    final f = fechaIsoDia(dia);
    final antes = await _saldoActualDia(f);
    if ((antes - saldoReal).abs() < 0.001) return;
    await _insertarMovimientoGuia(
      fechaIso: f,
      tipo: TipoGuiaCambioMovimiento.ajuste,
      monto: (saldoReal - antes).abs(),
      saldoAntes: antes,
      saldoDespues: saldoReal,
      nota: nota,
    );
  }

  Future<String?> obtenerAnotacionTexto(DateTime dia, TurnoCaja turno) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'cierre_caja_anotaciones',
      where: 'fecha = ? AND turno = ?',
      whereArgs: [fechaIsoDia(dia), turno.slug],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['texto']?.toString();
  }

  Future<void> guardarAnotacion({
    required DateTime dia,
    required TurnoCaja turno,
    required String texto,
  }) async {
    final f = fechaIsoDia(dia);
    _validarFechaSync(f);
    final t = texto.trim();
    final id = UuidUtils.cierreCajaAnotacionId(f, turno.slug);
    final db = await LocalDatabase.instance;
    final nowIso = ArTime.nowUtcIso();
    final existente = await db.query(
      'cierre_caja_anotaciones',
      where: 'fecha = ? AND turno = ?',
      whereArgs: [f, turno.slug],
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
      final createdIso =
          existente.first['created_at']?.toString() ?? nowIso;
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
