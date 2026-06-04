import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../main.dart';
import '../../../models/contrato_alumno.dart';
import '../../../core/database/local_database.dart';
import '../../../core/database/sync_queue.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../core/utils/uuid_utils.dart';
import '../services/calculadora_financiera.dart';
import '../services/mora_cuota_calculator.dart';

/// Repositorio de Contratos de Alumnos (Eventos Masivos) ÔÇö Offline-First.
class ContratosRepository {
  final SupabaseClient _supabase;
  final ConnectivityService _connectivity;

  ContratosRepository(this._supabase, this._connectivity);

  /// Suma mora cobrada (no anulada) dentro de una transacci├│n, **antes** de insertar un nuevo pago.
  Future<double> _sumMoraCobradaHistorialTxn(
    dynamic txn,
    String contratoId,
  ) async {
    final rows = await txn.query(
      'pagos_contrato_alumno',
      columns: ['monto', 'line_kind', 'concepto', 'anulado'],
      where: 'contrato_alumno_id = ?',
      whereArgs: [contratoId],
    );
    double s = 0;
    for (final p in rows) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
      final lk = (p['line_kind'] as String?)?.trim();
      final concepto = p['concepto'] as String? ?? '';
      if (lk == kLineKindInteresMora ||
          esPagoInteresMoraPorConcepto(concepto)) {
        s += (p['monto'] as num).toDouble();
      }
    }
    return double.parse(s.toStringAsFixed(2));
  }

  // ÔöÇÔöÇ LECTURA ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ

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

  // ÔöÇÔöÇ ESCRITURA ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ

  /// Registra un nuevo contrato de alumno.
  Future<String> registrarContrato(ContratoAlumno contrato) async {
    final db = await LocalDatabase.instance;
    final data = _toLocalRow(contrato);
    
    // Validaci├│n de seguridad (NotNull en Supabase)
    if (contrato.eventoId.isEmpty || contrato.eventoId == 'null') {
      throw Exception('INTENTO_REGISTRO_CORRUPTO: El evento_id est├í vac├¡o o es inv├ílido.');
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
    
    // Serializar arr├®glos para DB Local
    final localUpdates = Map<String, dynamic>.from(updates);
    if (localUpdates.containsKey('nombres_acompanantes') && localUpdates['nombres_acompanantes'] is List) {
      localUpdates['nombres_acompanantes'] = jsonEncode(localUpdates['nombres_acompanantes']);
    }
    if (localUpdates.containsKey('nombres_acompa├▒antes') && localUpdates['nombres_acompa├▒antes'] is List) {
      localUpdates['nombres_acompanantes'] = jsonEncode(localUpdates['nombres_acompa├▒antes']);
      localUpdates.remove('nombres_acompa├▒antes');
    }
    // SQLite FFI no acepta bool en bindings; la columna es INTEGER.
    if (localUpdates.containsKey('contrato_firmado')) {
      final v = localUpdates['contrato_firmado'];
      if (v is bool) {
        localUpdates['contrato_firmado'] = v ? 1 : 0;
      }
    }

    await db.update('contratos_alumnos', localUpdates, where: 'id = ?', whereArgs: [id]);
    
    await SyncQueue.enqueue(
      tabla: 'contratos_alumnos',
      operacion: SyncOperation.update,
      registroId: id,
      payload: {'id': id, ...updates},
    );
  }

  /// Actualiza solo `contrato_firmado` para muchos contratos en una transacci├│n local
  /// y encola sync por registro (misma sem├íntica que [actualizarContrato]).
  Future<void> actualizarContratoFirmadoBulk(Map<String, bool> cambiosPorId) async {
    if (cambiosPorId.isEmpty) return;
    final db = await LocalDatabase.instance;
    await db.transaction((txn) async {
      for (final e in cambiosPorId.entries) {
        await txn.update(
          'contratos_alumnos',
          {'contrato_firmado': e.value ? 1 : 0},
          where: 'id = ?',
          whereArgs: [e.key],
        );
        await SyncQueue.enqueue(
          executor: txn,
          tabla: 'contratos_alumnos',
          operacion: SyncOperation.update,
          registroId: e.key,
          payload: {'id': e.key, 'contrato_firmado': e.value},
        );
      }
    });
  }

  /// Registra un pago de contrato de alumno.
  /// Retorna el [ContratoAlumno] con saldo actualizado post-transacci├│n.
  Future<ContratoAlumno> registrarPago({
    required String contratoId,
    required double monto,
    required String concepto,
    double? montoADescontarDeSaldo,
    double descuentoPorcentaje = 0,
    int cuotasLiquidadas = 1,
    String? medioPago,
    /// Solo SQLite local; no se env├¡a a Supabase hasta tener columna en nube.
    String? lineKind,
    /// Mora pendiente calculada ANTES de que este mismo recibo avance
    /// cuotas_pagadas. Si se provee, se usa directamente en vez de
    /// recalcular desde el contrato (que ya fue mutado por la l├¡nea base).
    double? moraPendienteAntesDeLote,
  }) async {
    final db = await LocalDatabase.instance;
    final id = UuidUtils.generate();
    // Sello temporal ESTRICTO del pago (instante UTC preciso). Se muestra en
    // huso America/Argentina/Buenos_Aires v├¡a ArTime.
    final now = ArTime.nowUtcIso();

    final lk = lineKind?.trim();
    final pagoData = <String, dynamic>{
      'id': id,
      'contrato_alumno_id': contratoId,
      'monto': monto,
      'monto_gross': montoADescontarDeSaldo ?? monto,
      'descuento_porcentaje': descuentoPorcentaje,
      'concepto': concepto,
      'fecha_pago': now,
      'created_at': now,
      'medio_pago': medioPago,
      if (lk != null && lk.isNotEmpty) 'line_kind': lk,
    };

    await db.transaction((txn) async {
      final conceptoLower = concepto.toLowerCase();

      final bool esInteres =
          lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(concepto);

      if (esInteres) {
        double pendienteAntes;
        if (moraPendienteAntesDeLote != null) {
          // Snapshot pre-lote: el caller nos pas├│ la mora que exist├¡a ANTES
          // de que este mismo recibo avanzara cuotas_pagadas.
          pendienteAntes = moraPendienteAntesDeLote;
        } else {
          // C├ílculo legacy (recibos que solo cobran mora sin cuota base).
          final cRows = await txn.query(
            'contratos_alumnos',
            where: 'id = ?',
            whereArgs: [contratoId],
            limit: 1,
          );
          if (cRows.isNotEmpty) {
            final ca = ContratoAlumno.fromJson(cRows.first);
            final cobradoAntes =
                await _sumMoraCobradaHistorialTxn(txn, contratoId);
            final mora = MoraCuotaCalculator.calcular(ca);
            final formula = (mora.interesAcumulado - cobradoAntes).clamp(
              0.0,
              double.infinity,
            );
            final tracked = double.parse(
              (cRows.first['mora_pendiente_tracked'] ?? 0.0).toString(),
            );
            pendienteAntes = math.max(formula, tracked);
          } else {
            pendienteAntes = 0;
          }
        }
        final nuevoTracked =
            (pendienteAntes - monto).clamp(0.0, double.infinity);
        await txn.update(
          'contratos_alumnos',
          {'mora_pendiente_tracked': nuevoTracked},
          where: 'id = ?',
          whereArgs: [contratoId],
        );
      }

      await txn.insert('pagos_contrato_alumno', pagoData);

      // Cargo canal (operador transferencia): solo ingreso contable,
      // no afecta saldo ni cuotas del alumno.
      final bool esCargoCanal = lk == kLineKindCargoCanal;

      if (esCargoCanal) {
        // Nada que actualizar en el contrato; solo se registra el pago.
      } else if (esInteres) {
        // Ya actualizamos mora_pendiente_tracked; saldo / cuotas no cambian.
      } else if (conceptoLower.contains('base')) {
        // ÔöÇÔöÇ Snapshot mora ANTES de avanzar cuotas_pagadas ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ
        // Al incrementar cuotas_pagadas, MoraCuotaCalculator mirar├í la
        // cuota siguiente; si a├║n no venci├│, interesAcumulado caer├í a 0
        // y la mora acumulada de la cuota anterior se perder├¡a.
        // Persistimos el valor actual en mora_pendiente_tracked para que
        // pendienteDisplay lo conserve.
        final snapRows = await txn.query(
          'contratos_alumnos',
          where: 'id = ?',
          whereArgs: [contratoId],
          limit: 1,
        );
        if (snapRows.isNotEmpty) {
          final caSnap = ContratoAlumno.fromJson(snapRows.first);
          final cobradoSnap =
              await _sumMoraCobradaHistorialTxn(txn, contratoId);
          final moraSnap = MoraCuotaCalculator.calcular(caSnap);
          final formulaSnap = (moraSnap.interesAcumulado - cobradoSnap)
              .clamp(0.0, double.infinity);
          final trackedSnap = caSnap.moraPendienteTracked;
          final pendienteAhora = math.max(formulaSnap, trackedSnap);
          if (pendienteAhora > trackedSnap + 0.01) {
            await txn.update(
              'contratos_alumnos',
              {'mora_pendiente_tracked': pendienteAhora},
              where: 'id = ?',
              whereArgs: [contratoId],
            );
          }
        }
        // ÔöÇÔöÇ Ahora s├¡, avanzar cuota ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ
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
        'mora_pendiente_tracked': contratoActualizado['mora_pendiente_tracked'] ?? 0.0,
      };

      // Encolar sync del contrato actualizado
      await SyncQueue.enqueue(
        tabla: 'contratos_alumnos',
        operacion: SyncOperation.update,
        registroId: contratoId,
        payload: {'id': contratoId, ...contratoUpdates},
      );
    }

    // Encolar sync del pago (sin columnas solo-locales).
    final syncPayload = Map<String, dynamic>.from(pagoData)..remove('line_kind');
    await SyncQueue.enqueue(
      tabla: 'pagos_contrato_alumno',
      operacion: SyncOperation.insert,
      registroId: id,
      payload: syncPayload,
    );

    // Retornar contrato actualizado post-transacci├│n
    await recalcularProgresoContrato(contratoId);
    
    final finalRows = await db.query('contratos_alumnos',
        where: 'id = ?', whereArgs: [contratoId], limit: 1);
    return _fromLocalRow(finalRows.first);
  }

  /// Recalcula los contadores de cuotas de un contrato bas├índose en el historial de pagos.
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
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;

      final monto = (p['monto'] as num).toDouble();
      final conceptoRaw = p['concepto'] as String? ?? '';
      final lkRow = (p['line_kind'] as String?)?.trim();
      if (lkRow == kLineKindInteresMora ||
          lkRow == kLineKindCargoCanal ||
          esPagoInteresMoraPorConcepto(conceptoRaw)) {
        continue;
      }
      final concepto = conceptoRaw.toLowerCase();
      
      final bool esEntregaParcial = concepto.contains('entrega') || 
                                     concepto.contains('adelanto') || 
                                     concepto.contains('parcial');

      double mgOriginal = (p['monto_gross'] as num? ?? monto).toDouble();
      double mgSanado = mgOriginal;

      if (concepto.contains('base')) {
        int cant = 0;
        if (!esEntregaParcial) {
          if (concepto.contains('liquidaci├│n de')) {
            final match = RegExp(r'liquidaci├│n de (\d+)').firstMatch(concepto);
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
          if (concepto.contains('liquidaci├│n de')) {
            final match = RegExp(r'liquidaci├│n de (\d+)').firstMatch(concepto);
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
          if (concepto.contains('liquidaci├│n de')) {
            final match = RegExp(r'liquidaci├│n de (\d+)').firstMatch(concepto);
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

    if (hasChanges) {
      await db.update('contratos_alumnos', finalUpdates, where: 'id = ?', whereArgs: [contratoId]);
    }

    // El enqueue se ejecuta SIEMPRE: tras una anulaci├│n los contadores locales pueden quedar
    // ya consistentes (hasChanges=false) pero la nube necesita el update igual para que
    // dashboards/cobros suscritos al realtime de contratos_alumnos vean el contador correcto.
    await SyncQueue.enqueue(
      tabla: 'contratos_alumnos',
      operacion: SyncOperation.update,
      registroId: contratoId,
      payload: {'id': contratoId, ...finalUpdates},
    );
  }

  /// Obtiene el ├║ltimo pago de un contrato.
  Future<Map<String, dynamic>?> getUltimoPago(String contratoId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'pagos_contrato_alumno',
      where: 'contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)',
      whereArgs: [contratoId],
      orderBy: 'fecha_pago DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Obtiene todos los pagos del ├║ltimo lote.
  Future<List<Map<String, dynamic>>> getUltimosPagosLote(String contratoId) async {
    final db = await LocalDatabase.instance;
    final ultimo = await db.query(
      'pagos_contrato_alumno',
      where: 'contrato_alumno_id = ? AND (anulado IS NULL OR anulado = 0)',
      whereArgs: [contratoId],
      orderBy: 'fecha_pago DESC',
      limit: 1,
    );
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

  /// Suma de ingresos registrados como inter├®s por mora (no afectan saldo del plan).
  Future<double> sumMoraCobradaHistorial(String contratoId) async {
    final m = await sumMoraCobradaHistorialPorContratos([contratoId]);
    return m[contratoId] ?? 0.0;
  }

  /// Misma regla que [esPagoInteresMoraPorConcepto] + [kLineKindInteresMora] en SQLite.
  Future<Map<String, double>> sumMoraCobradaHistorialPorContratos(
      List<String> contratoIds) async {
    final out = <String, double>{for (final id in contratoIds) id: 0.0};
    if (contratoIds.isEmpty) return out;
    final db = await LocalDatabase.instance;
    const chunk = 120;
    for (var i = 0; i < contratoIds.length; i += chunk) {
      final end =
          (i + chunk < contratoIds.length) ? i + chunk : contratoIds.length;
      final part = contratoIds.sublist(i, end);
      final ph = part.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($ph)',
        part,
      );
      for (final p in rows) {
        if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
        final cid = p['contrato_alumno_id'] as String?;
        if (cid == null) continue;
        final lk = (p['line_kind'] as String?)?.trim();
        final concepto = p['concepto'] as String? ?? '';
        if (lk == kLineKindInteresMora ||
            esPagoInteresMoraPorConcepto(concepto)) {
          out[cid] = (out[cid] ?? 0) + (p['monto'] as num).toDouble();
        }
      }
    }
    return out;
  }

  /// Todos los pagos locales para un conjunto de contratos (p. ej. tab Cobro en Mi Empresa).
  /// Orden: [fecha_pago] ascendente. Trocea la consulta para respetar l├¡mites de variables SQLite.
  Future<List<Map<String, dynamic>>> getPagosForContratoIds(List<String> contratoIds) async {
    if (contratoIds.isEmpty) return [];
    final db = await LocalDatabase.instance;
    const chunk = 200;
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < contratoIds.length; i += chunk) {
      final end = (i + chunk < contratoIds.length) ? i + chunk : contratoIds.length;
      final part = contratoIds.sublist(i, end);
      final ph = part.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($ph) ORDER BY fecha_pago ASC',
        part,
      );
      out.addAll(rows);
    }
    return out;
  }

  /// Repara contratos hu├®rfanos.
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

  // ÔöÇÔöÇ SYNC & REALTIME ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ
  
  /// Escucha cambios en tiempo real para alumnos y pagos de un evento.
  RealtimeChannel subscribeToChanges(String eventoId, void Function() onUpdate) {
    debugPrint('­ƒöö Suscribiendo a cambios en tiempo real para evento: $eventoId');
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
        debugPrint('­ƒöö Realtime: Cambio detectado en contrato_alumno');
        onUpdate();
      },
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'pagos_contrato_alumno',
      callback: (payload) {
        debugPrint('­ƒöö Realtime: Cambio detectado en pagos');
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
      debugPrint('ÔÜá´©Å Error pull contratos: $e');
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
          'medio_pago': row['medio_pago'],
          'anulado': row['anulado'] ?? 0,
          'motivo_anulacion': row['motivo_anulacion'],
          'fecha_anulacion': row['fecha_anulacion'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('ÔÜá´©Å Error pull pagos: $e');
    }
  }

  // ÔöÇÔöÇ HELPERS ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ

  ContratoAlumno _fromLocalRow(Map<String, dynamic> row) {
    return ContratoAlumno.fromJson(row);
  }

  Map<String, dynamic> _toLocalRow(ContratoAlumno contrato) {
    final data = contrato.toJson();
    if (data.containsKey('nombres_acompanantes')) {
      data['nombres_acompanantes'] = jsonEncode(data['nombres_acompanantes']);
    }
    if (data.containsKey('contrato_firmado')) {
      data['contrato_firmado'] = (data['contrato_firmado'] == true) ? 1 : 0;
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

  /// Busca contratos por nombre de alumno o instituci├│n (colegio) para restaurar mora.
  Future<List<ContratoAlumno>> buscarContratosParaMora(String consulta) async {
    final q = consulta.trim();
    if (q.length < 2) return [];
    final like = '%$q%';
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT * FROM contratos_alumnos
      WHERE nombre_alumno LIKE ? OR IFNULL(institucion, '') LIKE ?
      ORDER BY nombre_alumno COLLATE NOCASE ASC LIMIT 50
    ''', [like, like]);
    return rows.map(_fromLocalRow).toList();
  }

  /// Alumnos masivos con cuota vencida y mora neta a restaurar (1% cuota ├ù d├¡as atraso).
  Future<List<MoraRestauracionCandidato>> listarCandidatosRestauracionMora({
    bool excluirBuenaVista = true,
  }) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT ca.* FROM contratos_alumnos ca
      INNER JOIN eventos ev ON ca.evento_id = ev.id
      WHERE ev.modalidad = 'masivo'
        AND ev.estado IN ('Confirmado', 'Planificacion')
        AND ca.nombre_alumno NOT LIKE '[BAJA]%'
        AND ca.saldo_deudor > 0.01
        AND ca.created_at IS NOT NULL
        AND TRIM(ca.created_at) != ''
      ORDER BY IFNULL(ca.institucion, '') COLLATE NOCASE ASC,
               ca.nombre_alumno COLLATE NOCASE ASC
    ''');

    final contratos = rows.map(_fromLocalRow).toList();
    if (contratos.isEmpty) return [];

    final moraMap = await sumMoraCobradaHistorialPorContratos(
      contratos.map((c) => c.id).toList(),
    );
    final hoy = ArTime.nowAr();
    final out = <MoraRestauracionCandidato>[];

    for (final c in contratos) {
      if (excluirBuenaVista) {
        final inst = (c.institucion ?? '').trim().toUpperCase();
        if (inst == 'COLEGIO BUENA VISTA') continue;
      }

      final moraYaCobrada = moraMap[c.id] ?? 0.0;
      final calc = MoraCuotaCalculator.calcularRestauracionDesdeReg(
        c,
        ahoraAr: hoy,
        moraYaCobrada: moraYaCobrada,
      );
      if (calc == null) continue;

      out.add(MoraRestauracionCandidato(
        contrato: c,
        diasMora: calc.diasMora,
        cuotaBase: calc.cuotaBase,
        moraBruta: calc.moraBruta,
        moraYaCobrada: moraYaCobrada,
        moraActual: c.moraPendienteTracked,
        moraAplicar: calc.moraAplicar,
      ));
    }
    return out;
  }

  /// Persiste [mora_pendiente_tracked] en lote y encola sync por contrato.
  Future<int> restaurarMoraBulk(Map<String, double> moraPorContratoId) async {
    if (moraPorContratoId.isEmpty) return 0;

    final db = await LocalDatabase.instance;
    var count = 0;

    await db.transaction((txn) async {
      for (final e in moraPorContratoId.entries) {
        if (e.value <= 0.01) continue;
        await txn.update(
          'contratos_alumnos',
          {'mora_pendiente_tracked': e.value},
          where: 'id = ?',
          whereArgs: [e.key],
        );
        await SyncQueue.enqueue(
          executor: txn,
          tabla: 'contratos_alumnos',
          operacion: SyncOperation.update,
          registroId: e.key,
          payload: {
            'id': e.key,
            'mora_pendiente_tracked': e.value,
          },
        );
        count++;
      }
    });

    return count;
  }

  Future<void> forceRefresh(String eventoId) async {
    final db = await LocalDatabase.instance;
    await _pullByEvento(db, eventoId, prune: true);
    await _pullPagosByEvento(db, eventoId, prune: true);
  }

  Future<Map<String, double>> sumMoraCobradaPeriodoPorContratos(
      List<ContratoAlumno> alumnos) async {
    final contratoIds = alumnos.map((e) => e.id).toList();
    final out = <String, double>{for (final id in contratoIds) id: 0.0};
    if (contratoIds.isEmpty) return out;

    final alumnoMap = {for (final a in alumnos) a.id: a};

    final db = await LocalDatabase.instance;
    const chunk = 120;
    for (var i = 0; i < contratoIds.length; i += chunk) {
      final end =
          (i + chunk < contratoIds.length) ? i + chunk : contratoIds.length;
      final part = contratoIds.sublist(i, end);
      final ph = part.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT * FROM pagos_contrato_alumno WHERE contrato_alumno_id IN ($ph)',
        part,
      );
      for (final p in rows) {
        if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
        final cid = p['contrato_alumno_id'] as String?;
        if (cid == null) continue;
        final lk = (p['line_kind'] as String?)?.trim();
        final concepto = p['concepto'] as String? ?? '';

        if (lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(concepto)) {
          final alumno = alumnoMap[cid];
          if (alumno == null) continue;

          final fp = p['fecha_pago']?.toString();
          if (fp == null) continue;
          final d = DateTime.tryParse(fp);
          if (d == null) continue;

          final res = MoraCuotaCalculator.calcular(alumno);
          final inicioMora = inicioMoraPeriodoVigente(res.fechaVencimientoProximaCuota);

          if (d.isAfter(inicioMora) || d.isAtSameMomentAs(inicioMora)) {
            out[cid] = (out[cid] ?? 0.0) + (p['monto'] as num).toDouble();
          }
        }
      }
    }

    out.forEach((key, val) {
      out[key] = double.parse(val.toStringAsFixed(2));
    });
    return out;
  }

  Future<bool> ejecutarAuditoriaInteligente(String eventoId) async {
    final db = await LocalDatabase.instance;
    final alumnos = await db.query('contratos_alumnos', where: 'evento_id = ?', whereArgs: [eventoId]);

    bool huboCambios = false;
    for (final aRow in alumnos) {
      final id = aRow['id'] as String;
      final saldoAnt = (aRow['saldo_deudor'] as num?)?.toDouble() ?? 0.0;
      final cuotasAnt = (aRow['cuotas_pagadas'] as num?)?.toInt() ?? 0;
      final mesaAnt = (aRow['mesa_extra_cuotas_pagadas'] as num?)?.toInt() ?? 0;
      final sillasAnt = (aRow['sillas_extra_cuotas_pagadas'] as num?)?.toInt() ?? 0;

      await recalcularProgresoContrato(id);

      final freshRows = await db.query('contratos_alumnos', where: 'id = ?', whereArgs: [id], limit: 1);
      if (freshRows.isNotEmpty) {
        final fRow = freshRows.first;
        final saldoNew = (fRow['saldo_deudor'] as num?)?.toDouble() ?? 0.0;
        final cuotasNew = (fRow['cuotas_pagadas'] as num?)?.toInt() ?? 0;
        final mesaNew = (fRow['mesa_extra_cuotas_pagadas'] as num?)?.toInt() ?? 0;
        final sillasNew = (fRow['sillas_extra_cuotas_pagadas'] as num?)?.toInt() ?? 0;

        if ((saldoAnt - saldoNew).abs() > 0.01 ||
            cuotasAnt != cuotasNew ||
            mesaAnt != mesaNew ||
            sillasAnt != sillasNew) {
          huboCambios = true;
        }
      }
    }
    return huboCambios;
  }
}

// ÔöÇÔöÇ Provider ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ

final contratosRepositoryProvider = Provider<ContratosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return ContratosRepository(supabase, connectivity);
});
