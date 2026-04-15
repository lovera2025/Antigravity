import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/contrato_alumno.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/uuid_utils.dart';
import '../services/calculadora_financiera.dart';

/// Repositorio de Contratos de Alumnos (Eventos Masivos) — Offline-First.
class ContratosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  ContratosRepository(this._supabase, this._connectivity);

  // ── LECTURA ────────────────────────────────────────────────────────────────

  /// Obtiene todos los contratos de un evento.
  Future<List<ContratoAlumno>> getByEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('contratos_alumnos',
      where: 'evento_id = ?',
      whereArgs: [eventoId],
      orderBy: 'nombre_alumno COLLATE NOCASE ASC',
    );

    if (_connectivity.currentStatus == AppConnectivity.online) {
      await _pullByEvento(db, eventoId, prune: true);
      await _pullPagosByEvento(db, eventoId, prune: true);
      final freshRows = await db.query('contratos_alumnos',
        where: 'evento_id = ?', whereArgs: [eventoId], orderBy: 'nombre_alumno COLLATE NOCASE ASC');
      return freshRows.map(_fromLocalRow).toList();
    }

    return rows.map(_fromLocalRow).toList();
  }

  /// Obtiene todos los contratos (global) para verificaciones de unicidad.
  Future<List<ContratoAlumno>> getAllContratos() async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('contratos_alumnos');
    return rows.map(_fromLocalRow).toList();
  }

  // ── ESCRITURA ─────────────────────────────────────────────────────────────

  /// Registra un nuevo contrato de alumno.
  Future<String> registrarContrato(ContratoAlumno contrato) async {
    final db = await LocalDatabase.instance;
    final data = _toLocalRow(contrato);
    
    // Validación de seguridad (NotNull en Supabase)
    if (contrato.eventoId.isEmpty || contrato.eventoId == 'null') {
      throw Exception('INTENTO_REGISTRO_CORRUPTO: El evento_id está vacío o es inválido.');
    }

    await db.insert('contratos_alumnos', data, conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueue.enqueue(
      tabla: 'contratos_alumnos',
      operacion: SyncOperation.insert,
      registroId: contrato.id,
      payload: contrato.toJson(),
    );

    return contrato.id;
  }

  /// Actualiza un contrato (ej: dar de baja o editar datos).
  Future<void> actualizarContrato(String id, Map<String, dynamic> updates) async {
    final db = await LocalDatabase.instance;
    
    // Serializar arréglos para DB Local
    final localUpdates = Map<String, dynamic>.from(updates);
    if (localUpdates.containsKey('nombres_acompanantes') && localUpdates['nombres_acompanantes'] is List) {
      localUpdates['nombres_acompanantes'] = jsonEncode(localUpdates['nombres_acompanantes']);
    }
    if (localUpdates.containsKey('nombres_acompañantes') && localUpdates['nombres_acompañantes'] is List) {
      localUpdates['nombres_acompanantes'] = jsonEncode(localUpdates['nombres_acompañantes']);
      localUpdates.remove('nombres_acompañantes');
    }

    await db.update('contratos_alumnos', localUpdates, where: 'id = ?', whereArgs: [id]);
    
    await SyncQueue.enqueue(
      tabla: 'contratos_alumnos',
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, ...updates},
    );
  }

  /// Registra un pago de contrato de alumno.
  /// Retorna el [ContratoAlumno] con saldo actualizado post-transacción.
  Future<ContratoAlumno> registrarPago({
    required String contratoId,
    required double monto,
    required String concepto,
    double? montoADescontarDeSaldo,
    double descuentoPorcentaje = 0,
    int cuotasLiquidadas = 1,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();

    final pagoData = {
      'id': id,
      'contrato_alumno_id': contratoId,
      'monto': monto,
      'monto_gross': montoADescontarDeSaldo ?? monto,
      'descuento_porcentaje': descuentoPorcentaje,
      'concepto': concepto,
      'fecha_pago': now,
      'created_at': now,
    };

    await db.transaction((txn) async {
      // 1. Insertar pago
      await txn.insert('pagos_contrato_alumno', pagoData);
      
      // 2. Actualizar saldo y cuotas en el contrato (Localmente)
      final conceptoLower = concepto.toLowerCase();
      
      if (conceptoLower.contains('base')) {
        await txn.rawUpdate('''
          UPDATE contratos_alumnos 
          SET saldo_deudor = saldo_deudor - ?, 
              cuotas_pagadas = cuotas_pagadas + ?
          WHERE id = ?
        ''', [montoADescontarDeSaldo ?? monto, cuotasLiquidadas, contratoId]);
      } else if (conceptoLower.contains('mesa')) {
        await txn.rawUpdate('''
          UPDATE contratos_alumnos 
          SET saldo_deudor = saldo_deudor - ?,
              mesa_extra_pagado = mesa_extra_pagado + ?,
              mesa_extra_cuotas_pagadas = mesa_extra_cuotas_pagadas + ?
          WHERE id = ?
        ''', [montoADescontarDeSaldo ?? monto, monto, cuotasLiquidadas, contratoId]);
      } else if (conceptoLower.contains('silla')) {
        await txn.rawUpdate('''
          UPDATE contratos_alumnos 
          SET saldo_deudor = saldo_deudor - ?,
              sillas_extra_pagado = sillas_extra_pagado + ?,
              sillas_extra_cuotas_pagadas = sillas_extra_cuotas_pagadas + ?
          WHERE id = ?
        ''', [montoADescontarDeSaldo ?? monto, monto, cuotasLiquidadas, contratoId]);

      } else {
        await txn.rawUpdate('''
          UPDATE contratos_alumnos 
          SET saldo_deudor = saldo_deudor - ?
          WHERE id = ?
        ''', [monto, contratoId]);
      }
    });

    // Leer los valores actualizados del contrato para sincronizar al cloud
    final updatedRows = await db.query('contratos_alumnos',
        where: 'id = ?', whereArgs: [contratoId], limit: 1);
    if (updatedRows.isNotEmpty) {
      final contratoActualizado = updatedRows.first;
      final contratoUpdates = {
        'saldo_deudor': contratoActualizado['saldo_deudor'],
        'cuotas_pagadas': contratoActualizado['cuotas_pagadas'],
        'mesa_extra_cuotas_pagadas': contratoActualizado['mesa_extra_cuotas_pagadas'],
        'sillas_extra_cuotas_pagadas': contratoActualizado['sillas_extra_cuotas_pagadas'],
        'mesa_extra_pagado': contratoActualizado['mesa_extra_pagado'],
        'sillas_extra_pagado': contratoActualizado['sillas_extra_pagado'],
      };

      // Encolar sync del contrato actualizado
      await SyncQueue.enqueue(
        tabla: 'contratos_alumnos',
        operacion: SyncOperation.update,
        registroId: contratoId,
        payload: {'id': contratoId, ...contratoUpdates},
      );
    }

    // Encolar sync del pago
    await SyncQueue.enqueue(
      tabla: 'pagos_contrato_alumno',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: pagoData,
    );

    // Retornar contrato actualizado post-transacción
    await recalcularProgresoContrato(contratoId);
    
    final finalRows = await db.query('contratos_alumnos',
        where: 'id = ?', whereArgs: [contratoId], limit: 1);
    return _fromLocalRow(finalRows.first);
  }

  /// Recalcula los contadores de cuotas de un contrato basándose en el historial de pagos.
  Future<void> recalcularProgresoContrato(String contratoId) async {
    final db = await LocalDatabase.instance;
    
    // 1. Obtener contrato para saber precios base
    final cRows = await db.query('contratos_alumnos', where: 'id = ?', whereArgs: [contratoId]);
    if (cRows.isEmpty) return;
    final row = cRows.first;
    final contrato = _fromLocalRow(row);

    // Calcular cuotas puras para saneamiento
    final cuotaPuraBase = CalculadoraFinanciera.calcularCuotaPura(
      contrato.montoTotalPactado - contrato.mesaExtraPrecio - contrato.sillasExtraPrecioTotal, 
      contrato.totalCuotas
    );
    final cuotaPuraMesa = contrato.mesaExtraCuotas > 0 ? contrato.mesaExtraPrecio / contrato.mesaExtraCuotas : 0.0;
    final cuotaPuraSilla = contrato.sillasExtraCuotas > 0 ? contrato.sillasExtraPrecioTotal / contrato.sillasExtraCuotas : 0.0;

    // 2. Obtener todos los pagos
    final pagos = await db.query('pagos_contrato_alumno', 
        where: 'contrato_alumno_id = ?', whereArgs: [contratoId]);
    
    int cuotasBaseCount = 0;
    int cuotasMesaCount = 0;
    int cuotasSillaCount = 0;
    double pagadoMesa = 0;
    double pagadoSilla = 0;
    double totalRecaudadoReal = 0;

    for (final p in pagos) {
      final monto = (p['monto'] as num).toDouble();
      final concepto = (p['concepto'] as String? ?? '').toLowerCase();
      
      final bool esEntregaParcial = concepto.contains('entrega') || 
                                     concepto.contains('adelanto') || 
                                     concepto.contains('parcial');

      double mgOriginal = (p['monto_gross'] as num? ?? monto).toDouble();
      double mgSanado = mgOriginal;

      if (concepto.contains('base')) {
        int cant = 0;
        if (!esEntregaParcial) {
          if (concepto.contains('liquidación de')) {
            final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
            cant = match != null ? int.parse(match.group(1)!) : 1;
          } else if (concepto.contains('cuota')) {
            cant = 1;
          }
        }
        
        if (cant > 0 && mgOriginal == monto && monto < (cuotaPuraBase * cant - 0.1) && cuotaPuraBase > 0) {
          mgSanado = cuotaPuraBase * cant;
        }
        cuotasBaseCount += cant;
      } else if (concepto.contains('mesa')) {
        int cant = 0;
        if (!esEntregaParcial) {
          if (concepto.contains('liquidación de')) {
            final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
            cant = match != null ? int.parse(match.group(1)!) : 1;
          } else if (concepto.contains('mesa extra')) {
            cant = 1;
          }
        }
        if (cant > 0 && mgOriginal == monto && monto < (cuotaPuraMesa * cant - 0.1) && cuotaPuraMesa > 0) {
          mgSanado = cuotaPuraMesa * cant;
        }
        cuotasMesaCount += cant;
        pagadoMesa += mgSanado;
      } else if (concepto.contains('silla')) {
        int cant = 0;
        if (!esEntregaParcial) {
          if (concepto.contains('liquidación de')) {
            final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
            cant = match != null ? int.parse(match.group(1)!) : 1;
          } else if (concepto.contains('sillas extra')) {
            cant = 1;
          }
        }
        if (cant > 0 && mgOriginal == monto && monto < (cuotaPuraSilla * cant - 0.1) && cuotaPuraSilla > 0) {
          mgSanado = cuotaPuraSilla * cant;
        }
        cuotasSillaCount += cant;
        pagadoSilla += mgSanado;
      }

      totalRecaudadoReal += mgSanado;
      
      if (mgSanado != mgOriginal) {
        await db.update('pagos_contrato_alumno', {'monto_gross': mgSanado}, where: 'id = ?', whereArgs: [p['id']]);
      }
    }

    final double saldoReal = (contrato.montoTotalPactado - totalRecaudadoReal).clamp(0, double.infinity);
    
    bool hasChanges = false;
    final currentData = row;
    
    final finalUpdates = {
      'cuotas_pagadas': cuotasBaseCount.clamp(0, contrato.totalCuotas),
      'mesa_extra_cuotas_pagadas': cuotasMesaCount.clamp(0, contrato.mesaExtraCuotas),
      'sillas_extra_cuotas_pagadas': cuotasSillaCount.clamp(0, contrato.sillasExtraCuotas > 0 ? contrato.sillasExtraCuotas : 99),
      'mesa_extra_pagado': pagadoMesa,
      'sillas_extra_pagado': pagadoSilla,
      'saldo_deudor': saldoReal.clamp(0, double.infinity),
    };

    for (final key in finalUpdates.keys) {
      final newVal = finalUpdates[key];
      final oldVal = currentData[key];
      
      if (newVal is num && oldVal is num) {
        if ((newVal.toDouble() - oldVal.toDouble()).abs() > 0.01) {
          hasChanges = true;
          break;
        }
      } else if (newVal != oldVal) {
        hasChanges = true;
        break;
      }
    }

    if (!hasChanges) return;

    await db.update('contratos_alumnos', finalUpdates, where: 'id = ?', whereArgs: [contratoId]);

    await SyncQueue.enqueue(
      tabla: 'contratos_alumnos',
      operacion: SyncOperation.update,
      registroId: contratoId,
      payload: {'id': contratoId, ...finalUpdates},
    );
  }

  /// Obtiene el último pago de un contrato.
  Future<Map<String, dynamic>?> getUltimoPago(String contratoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query('pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contratoId],
        orderBy: 'fecha_pago DESC',
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Obtiene todos los pagos del último lote.
  Future<List<Map<String, dynamic>>> getUltimosPagosLote(String contratoId) async {
    final db = await LocalDatabase.instance;
    final ultimo = await db.query('pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contratoId],
        orderBy: 'fecha_pago DESC',
        limit: 1);
    if (ultimo.isEmpty) return [];

    final ultimaFechaStr = ultimo.first['fecha_pago'] as String?;
    if (ultimaFechaStr == null) return [ultimo.first];

    final ultimaFecha = DateTime.parse(ultimaFechaStr);
    final umbralInferior = ultimaFecha.subtract(const Duration(seconds: 10)).toIso8601String();

    final lote = await db.query('pagos_contrato_alumno',
        where: 'contrato_alumno_id = ? AND fecha_pago >= ?',
        whereArgs: [contratoId, umbralInferior],
        orderBy: 'fecha_pago ASC');
    return lote;
  }

  /// Obtiene historial de pagos.
  Future<List<Map<String, dynamic>>> getHistorialPagosAlumno(String contratoId) async {
    final db = await LocalDatabase.instance;
    return await db.query('pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contratoId],
        orderBy: 'fecha_pago DESC');
  }

  /// Repara contratos huérfanos.
  Future<int> repararContratosHuerfanos(String eventoId) async {
    final db = await LocalDatabase.instance;
    final huerfanos = await db.query('contratos_alumnos', 
      where: "evento_id IS NULL OR evento_id = '' OR evento_id = 'null'");
    
    if (huerfanos.isEmpty) return 0;
    
    int corregidos = 0;
    for (final row in huerfanos) {
      final id = row['id'] as String;
      await db.update('contratos_alumnos', {'evento_id': eventoId}, where: 'id = ?', whereArgs: [id]);
      await SyncQueue.enqueue(
        tabla: 'contratos_alumnos',
        operacion: SyncOperation.update,
        registroId: id,
        payload: {'evento_id': eventoId},
      );
      corregidos++;
    }
    return corregidos;
  }

  // ── SYNC & REALTIME ────────────────────────────────────────────────────────
  
  /// Escucha cambios en tiempo real para alumnos y pagos de un evento.
  RealtimeChannel subscribeToChanges(String eventoId, void Function() onUpdate) {
    debugPrint('🔔 Suscribiendo a cambios en tiempo real para evento: $eventoId');
    final channel = _supabase.channel('public:contratos_repo_$eventoId');
    
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'contratos_alumnos',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'evento_id',
        value: eventoId,
      ),
      callback: (payload) {
        debugPrint('🔔 Realtime: Cambio detectado en contrato_alumno');
        onUpdate();
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pagos_contrato_alumno',
      callback: (payload) {
        debugPrint('🔔 Realtime: Cambio detectado en pagos');
        onUpdate();
      },
    );

    channel.subscribe();
    return channel;
  }

  Future<void> _pullByEvento(Database db, String eventoId, {bool prune = false}) async {
    try {
      final response = await _supabase.from('contratos_alumnos')
          .select()
          .eq('evento_id', eventoId);

      final List<dynamic> list = response as List;
      final cloudIds = list.map((r) => r['id'] as String).toSet();

      final pendingRows = await db.query('_sync_queue', 
        columns: ['registro_id'], 
        where: "tabla = 'contratos_alumnos'");
      final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

      if (prune) {
        final localRows = await db.query('contratos_alumnos', columns: ['id'], where: 'evento_id = ?', whereArgs: [eventoId]);
        final localIds = localRows.map((r) => r['id'] as String).toList();
        final orphans = localIds.where((id) => !cloudIds.contains(id)).toList();

        if (orphans.isNotEmpty) {
          final List<String> toDelete = [];
          for (final id in orphans) {
            final inQueue = await db.query('_sync_queue', where: "tabla = 'contratos_alumnos' AND registro_id = ?", whereArgs: [id]);
            if (inQueue.isEmpty) toDelete.add(id);
          }
          if (toDelete.isNotEmpty) {
            await db.delete('contratos_alumnos', where: "id IN (${toDelete.map((_) => '?').join(',')})", whereArgs: toDelete);
          }
        }
      }

      final batch = db.batch();
      for (final row in list) {
        final id = row['id'] as String;
        if (pendingIds.contains(id)) continue;

        batch.insert('contratos_alumnos', _toLocalRow(ContratoAlumno.fromJson(row)), 
          conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull contratos: $e');
    }
  }

  Future<void> _pullPagosByEvento(Database db, String eventoId, {bool prune = false}) async {
    try {
      final contratosRows = await db.query('contratos_alumnos', columns: ['id'], where: 'evento_id = ?', whereArgs: [eventoId]);
      final contratoIds = contratosRows.map((r) => r['id'] as String).toList();

      if (contratoIds.isEmpty) return;

      final response = await _supabase.from('pagos_contrato_alumno')
          .select()
          .inFilter('contrato_alumno_id', contratoIds);

      final List<dynamic> list = response as List;
      final cloudIds = list.map((r) => r['id'] as String).toSet();

      final pendingRows = await db.query('_sync_queue', 
        columns: ['registro_id'], 
        where: "tabla = 'pagos_contrato_alumno'");
      final pendingIds = pendingRows.map((r) => r['registro_id'] as String).toSet();

      if (prune) {
        final localRows = await db.query('pagos_contrato_alumno', 
          columns: ['id'], 
          where: "contrato_alumno_id IN (${contratoIds.map((_) => '?').join(',')})", 
          whereArgs: contratoIds
        );
        final localIds = localRows.map((r) => r['id'] as String).toList();
        final orphans = localIds.where((id) => !cloudIds.contains(id)).toList();

        if (orphans.isNotEmpty) {
          final List<String> toDelete = [];
          for (final id in orphans) {
            final inQueue = await db.query('_sync_queue', where: "tabla = 'pagos_contrato_alumno' AND registro_id = ?", whereArgs: [id]);
            if (inQueue.isEmpty) toDelete.add(id);
          }
          if (toDelete.isNotEmpty) {
            await db.delete('pagos_contrato_alumno', where: "id IN (${toDelete.map((_) => '?').join(',')})", whereArgs: toDelete);
          }
        }
      }

      final batch = db.batch();
      for (final row in list) {
        final id = row['id'] as String;
        if (pendingIds.contains(id)) continue;

        batch.insert('pagos_contrato_alumno', {
          'id': row['id'],
          'contrato_alumno_id': row['contrato_alumno_id'],
          'monto': row['monto'],
          'monto_gross': row['monto_gross'],
          'descuento_porcentaje': row['descuento_porcentaje'],
          'concepto': row['concepto'],
          'fecha_pago': row['fecha_pago'],
          'created_at': row['created_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('⚠️ Error pull pagos: $e');
    }
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  ContratoAlumno _fromLocalRow(Map<String, dynamic> row) {
    return ContratoAlumno.fromJson(row);
  }

  Map<String, dynamic> _toLocalRow(ContratoAlumno contrato) {
    final data = contrato.toJson();
    if (data.containsKey('nombres_acompanantes')) {
      data['nombres_acompanantes'] = jsonEncode(data['nombres_acompanantes']);
    }
    return data;
  }

  Future<void> recalcularTodoElEvento(String eventoId) async {
    final db = await LocalDatabase.instance;
    final alumnos = await db.query('contratos_alumnos', where: 'evento_id = ?', whereArgs: [eventoId]);
    
    for (final aRow in alumnos) {
      final id = aRow['id'] as String;
      await recalcularProgresoContrato(id);
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final contratosRepositoryProvider = Provider<ContratosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return ContratosRepository(supabase, connectivity);
});
