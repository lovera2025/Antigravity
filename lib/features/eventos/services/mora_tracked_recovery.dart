import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/sync_queue.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mora_cuota_calculator.dart';

/// Recalcula [mora_pendiente_tracked] y [mora_cobrada_offset] desde el
/// historial de pagos (reglas post-fix v50). No borra pagos ni cuotas.
class MoraTrackedRecovery {
  MoraTrackedRecovery._();

  /// Universo de contratos que recorre la reconciliación.
  static Future<List<Map<String, Object?>>> _contratosParaReconciliar(
    DatabaseExecutor db,
    bool soloEventosMasivosActivos,
  ) =>
      soloEventosMasivosActivos
          ? db.rawQuery('''
            SELECT c.*
            FROM contratos_alumnos c
            INNER JOIN eventos e ON e.id = c.evento_id
            WHERE e.modalidad = 'masivo'
              AND e.estado IN ('Confirmado', 'Planificacion')
              AND c.nombre_alumno NOT LIKE '[BAJA]%'
          ''')
          : db.query('contratos_alumnos');

  static bool _esMora(Map<String, dynamic> p) {
    final lk = (p['line_kind'] as String?)?.trim();
    final c = p['concepto']?.toString() ?? '';
    return lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(c);
  }

  static bool _esBaseCuota(Map<String, dynamic> p) {
    if (_esMora(p)) return false;
    final lk = (p['line_kind'] as String?)?.trim();
    if (lk == kLineKindCargoCanal ||
        esPagoCargoCanalPorConcepto(p['concepto']?.toString())) {
      return false;
    }
    final c = (p['concepto']?.toString() ?? '').toLowerCase();
    if (c.contains('abono')) return true;
    if (c.contains('completada') || c.contains('entrega parcial')) return true;
    return c.contains('cuota base') ||
        c.contains('cuota ') ||
        c.contains('cuotas ');
  }

  static int _cuotasLiquidadasEnLinea(Map<String, dynamic> p) {
    final c = (p['concepto']?.toString() ?? '').toLowerCase();
    if (c.contains('abono') || c.contains('entrega parcial')) return 0;
    if (c.contains('cuotas ')) {
      final m = RegExp(r'cuotas?\s+(\d+)').firstMatch(c);
      if (m != null) return int.tryParse(m.group(1)!) ?? 1;
    }
    return _esBaseCuota(p) ? 1 : 0;
  }

  static List<List<Map<String, dynamic>>> _lotesCronologicos(
    List<Map<String, dynamic>> pagos,
  ) {
    final activos = pagos
        .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
        .toList()
      ..sort((a, b) {
        final fa = a['fecha_pago']?.toString() ?? '';
        final fb = b['fecha_pago']?.toString() ?? '';
        return fa.compareTo(fb);
      });

    final lotes = <List<Map<String, dynamic>>>[];
    String? ultimaClave;
    for (final p in activos) {
      final clave = _claveLoteDia(p);
      if (lotes.isEmpty || clave != ultimaClave) {
        lotes.add([p]);
        ultimaClave = clave;
      } else {
        lotes.last.add(p);
      }
    }
    return lotes;
  }

  /// Agrupa pagos del mismo día calendario (AR), aunque difieran en hora ISO.
  static String _claveLoteDia(Map<String, dynamic> p) {
    final f = p['fecha_pago']?.toString() ?? '';
    final parsed = DateTime.tryParse(f);
    if (parsed != null) {
      final ar = ArTime.toAr(parsed);
      return '${ar.year}-'
          '${ar.month.toString().padLeft(2, '0')}-'
          '${ar.day.toString().padLeft(2, '0')}';
    }
    return f.length >= 10 ? f.substring(0, 10) : f;
  }

  static DateTime? _fechaArDelLote(List<Map<String, dynamic>> lote) {
    final f = lote.first['fecha_pago']?.toString();
    if (f == null || f.isEmpty) return null;
    final parsed = DateTime.tryParse(f);
    if (parsed == null) return null;
    return ArTime.toAr(parsed);
  }

  static int _cuotasBaseDesdePagosAcumulados({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagosHasta,
  }) {
    return recalcularSaldoDesdePagos(
      montoTotalPactado: contratoBase.montoTotalPactado,
      totalCuotas: contratoBase.totalCuotas,
      mesaExtraPrecio: contratoBase.mesaExtraPrecio,
      sillasExtraPrecioTotal: contratoBase.sillasExtraPrecioTotal,
      precioUnitarioMesaExtra: contratoBase.precioUnitarioMesaExtra,
      mesaExtraCuotas: contratoBase.mesaExtraCuotas,
      mesaExtraCantidad: contratoBase.mesaExtraCantidad,
      sillasExtraCuotas: contratoBase.sillasExtraCuotas,
      pagos: pagosHasta,
    ).cuotasBase;
  }

  /// Simula tracked/offset aplicando las reglas actuales sobre el historial.
  static ({double tracked, double offset}) recomputarDesdeHistorial({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,
  }) {
    var tracked = 0.0;
    var offset = 0.0;
    var cuotasPagadas = 0;
    var moraHistAcum = 0.0;
    DateTime? ultimaExencion;
    var ultimaReinicia = true;
    final pagosAcum = <Map<String, dynamic>>[];

    for (final lote in _lotesCronologicos(pagos)) {
      final moraEsteCobro = lote
          .where(_esMora)
          .fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

      // Heurística de concepto (líneas "N Cuotas") + abonos vía gross acumulado.
      final cuotasPorConcepto = lote
          .where(_esBaseCuota)
          .fold<int>(0, (s, p) => s + _cuotasLiquidadasEnLinea(p));

      pagosAcum.addAll(lote);
      final cuotasPost = _cuotasBaseDesdePagosAcumulados(
        contratoBase: contratoBase,
        pagosHasta: pagosAcum,
      );
      final cuotasLiquidadas =
          math.max(cuotasPorConcepto, cuotasPost - cuotasPagadas);

      final alumnoPre = contratoBase.copyWith(
        cuotasPagadas: cuotasPagadas,
        moraPendienteTracked: tracked,
        moraCobradaOffset: offset,
        moraExentaHasta: ultimaExencion,
        moraExencionReinicia: ultimaReinicia,
      );

      final fechaLote = _fechaArDelLote(lote);
      final moraDesgloseBruto =
          MoraCuotaCalculator.calcularDesglose(alumnoPre, fechaLote);
      final moraDesgloseNeto = MoraCuotaCalculator.desglosePendiente(
        moraDesgloseBruto,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: moraHistAcum,
          moraCobradaOffset: offset,
        ),
      );
      final moraDesgloseNetoTotal =
          moraDesgloseNeto.fold<double>(0, (s, d) => s + d.interesBruto);

      final post = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: tracked,
        moraCobradaOffsetActual: offset,
        moraEsteCobro: moraEsteCobro,
        cuotasBaseLiquidadasEnCobro: cuotasLiquidadas,
        cuotasBasePagadasPostCobro: cuotasPagadas + cuotasLiquidadas,
        moraDesglosePreCobro: moraDesgloseBruto,
        moraDesgloseNetoPreCobro: moraDesgloseNeto,
        moraDesgloseNetoTotal: moraDesgloseNetoTotal,
        saldoDeudorPost: contratoBase.saldoDeudor,
        fechaCobroAr: fechaLote,
        exencionActual: ultimaExencion,
        reiniciaActual: ultimaReinicia,
      );

      tracked = post.tracked;
      offset = post.offset;
      ultimaExencion = post.exentaHasta;
      ultimaReinicia = post.reinicia;
      moraHistAcum += moraEsteCobro;
      cuotasPagadas = (cuotasPagadas + cuotasLiquidadas)
          .clamp(0, contratoBase.totalCuotas > 0 ? contratoBase.totalCuotas : 9);
    }

    return (
      tracked: double.parse(tracked.toStringAsFixed(2)),
      offset: double.parse(offset.toStringAsFixed(2)),
    );
  }

  static bool tieneMoraEnHistorial(List<Map<String, dynamic>> pagos) =>
      pagos.any((p) {
        if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
        return _esMora(p);
      });

  static bool trackedPareceInflado({
    required double tracked,
    required List<Map<String, dynamic>> pagos,
  }) =>
      tracked > 0.01 && !tieneMoraEnHistorial(pagos);

  /// Tracked/offset objetivo: siempre desde historial (v52+).
  /// No usa [trackedPareceInflado]: el tracked legítimo de "cuota sin mora"
  /// no requiere pagos `interes_mora` en el historial.
  static ({double tracked, double offset}) objetivoDesdeHistorial({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> pagos,
  }) {
    return recomputarDesdeHistorial(
      contratoBase: contrato.copyWith(
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
      ),
      pagos: pagos,
    );
  }

  /// Hay liquidación de cuota base en historial (aunque no haya líneas de mora).
  static bool tienePagosCuotaBaseEnHistorial(List<Map<String, dynamic>> pagos) =>
      pagos.any((p) {
        if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
        return _esBaseCuota(p) && _cuotasLiquidadasEnLinea(p) > 0;
      });

  /// Si conviene recalcular tracked/offset desde historial.
  static bool necesitaReconciliar(
    ContratoAlumno contrato,
    List<Map<String, dynamic>> pagos,
  ) {
    if (contrato.moraPendienteTracked > 0.01) return true;
    if (contrato.moraCobradaOffset > 0.01) return true;
    if (tieneMoraEnHistorial(pagos)) return true;
    // v53: cuota pagada sin mora → tracked legítimo sin líneas interes_mora.
    return tienePagosCuotaBaseEnHistorial(pagos);
  }

  /// Fusiona exención local con la inferida del historial **sin degradar**
  /// un perdón admin (fecha más lejana o `reinicia=false`).
  ///
  /// - Sin historial: conserva local (no fuerza `reinicia=true`).
  /// - Sin local: aplica historial.
  /// - Ambos: `hasta = max(local, hist)`; `reinicia = false` gana.
  static ({DateTime? hasta, bool reinicia, bool escribir})
      resolverExencionPreservandoLocal({
    required DateTime? localHasta,
    required bool localReinicia,
    required ({DateTime hasta, bool reinicia})? desdeHistorial,
  }) {
    final hist = desdeHistorial;
    if (localHasta == null && hist == null) {
      return (hasta: null, reinicia: true, escribir: false);
    }
    if (localHasta == null && hist != null) {
      return (hasta: hist.hasta, reinicia: hist.reinicia, escribir: true);
    }
    if (localHasta != null && hist == null) {
      // Perdón admin / exención local sin cobro que la justifique: no tocar.
      return (hasta: localHasta, reinicia: localReinicia, escribir: false);
    }

    final localDay = DateTime(
      localHasta!.year,
      localHasta.month,
      localHasta.day,
    );
    final histDay = DateTime(
      hist!.hasta.year,
      hist.hasta.month,
      hist.hasta.day,
    );
    final mergedHasta =
        histDay.isAfter(localDay) ? hist.hasta : localHasta;
    // Permanente (false) gana: no regenerar mora ya perdonada.
    final mergedReinicia = localReinicia && hist.reinicia;

    final mismoHasta = mergedHasta.year == localHasta.year &&
        mergedHasta.month == localHasta.month &&
        mergedHasta.day == localHasta.day;
    final mismoReinicia = mergedReinicia == localReinicia;
    if (mismoHasta && mismoReinicia) {
      return (hasta: localHasta, reinicia: localReinicia, escribir: false);
    }
    return (hasta: mergedHasta, reinicia: mergedReinicia, escribir: true);
  }

  static String _exentaHastaIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Detecta alumnos cuyo último cobro de mora saldó toda la pendiente en ese
  /// momento y les asigna [mora_exenta_hasta] + [mora_exencion_reinicia].
  /// No acorta ni vuelve `reinicia=true` sobre una exención local más protectora.
  static Future<int> repararExencionDesdeHistorial({
    required DatabaseExecutor db,
    bool soloEventosMasivosActivos = false,
  }) async {
    final contratos =
        await _contratosParaReconciliar(db, soloEventosMasivosActivos);

    var reparados = 0;
    for (final row in contratos) {
      final contrato = ContratoAlumno.fromJson(row);
      if (contrato.saldoDeudor <= 0.01) continue;

      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contrato.id],
      );

      final exencion = _calcularExencionDesdeHistorial(
        contratoBase: contrato,
        pagos: pagos,
      );

      final resolved = resolverExencionPreservandoLocal(
        localHasta: contrato.moraExentaHasta,
        localReinicia: contrato.moraExencionReinicia,
        desdeHistorial: exencion,
      );
      if (!resolved.escribir || resolved.hasta == null) continue;

      await db.update(
        'contratos_alumnos',
        {
          'mora_exenta_hasta': _exentaHastaIso(resolved.hasta!),
          'mora_exencion_reinicia': resolved.reinicia ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [contrato.id],
      );
      reparados++;
    }
    return reparados;
  }

  /// Calcula exención (fecha + modalidad reinicia) desde el historial de pagos.
  /// Público para tools/auditoría; misma lógica que [repararExencionDesdeHistorial].
  static ({DateTime hasta, bool reinicia})? calcularExencionDesdeHistorial({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,
  }) =>
      _calcularExencionDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagos,
      );

  /// Calcula la fecha de exención para un contrato dado su historial.
  /// Retorna la fecha si el último lote con mora saldó toda la pendiente.
  static ({DateTime hasta, bool reinicia})? _calcularExencionDesdeHistorial({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,
  }) {
    var tracked = 0.0;
    var offset = 0.0;
    var cuotasPagadas = 0;
    var moraHistAcum = 0.0;
    DateTime? ultimaExencion;
    var ultimaReinicia = true;
    final pagosAcum = <Map<String, dynamic>>[];

    final lotes = _lotesCronologicos(pagos);
    for (final lote in lotes) {
      final moraEsteCobro = lote
          .where(_esMora)
          .fold<double>(0, (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0));

      final cuotasPorConcepto = lote
          .where(_esBaseCuota)
          .fold<int>(0, (s, p) => s + _cuotasLiquidadasEnLinea(p));

      pagosAcum.addAll(lote);
      final cuotasPost = _cuotasBaseDesdePagosAcumulados(
        contratoBase: contratoBase,
        pagosHasta: pagosAcum,
      );
      final cuotasLiquidadas =
          math.max(cuotasPorConcepto, cuotasPost - cuotasPagadas);

      final alumnoPre = contratoBase.copyWith(
        cuotasPagadas: cuotasPagadas,
        moraPendienteTracked: tracked,
        moraCobradaOffset: offset,
        moraExentaHasta: ultimaExencion,
        moraExencionReinicia: ultimaReinicia,
      );

      final fechaLote = _fechaArDelLote(lote);
      final moraDesgloseBruto =
          MoraCuotaCalculator.calcularDesglose(alumnoPre, fechaLote);
      final moraDesgloseNeto = MoraCuotaCalculator.desglosePendiente(
        moraDesgloseBruto,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: moraHistAcum,
          moraCobradaOffset: offset,
        ),
      );
      final moraDesgloseNetoTotal =
          moraDesgloseNeto.fold<double>(0, (s, d) => s + d.interesBruto);

      final post = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: tracked,
        moraCobradaOffsetActual: offset,
        moraEsteCobro: moraEsteCobro,
        cuotasBaseLiquidadasEnCobro: cuotasLiquidadas,
        cuotasBasePagadasPostCobro: cuotasPagadas + cuotasLiquidadas,
        moraDesglosePreCobro: moraDesgloseBruto,
        moraDesgloseNetoPreCobro: moraDesgloseNeto,
        moraDesgloseNetoTotal: moraDesgloseNetoTotal,
        saldoDeudorPost: contratoBase.saldoDeudor,
        fechaCobroAr: fechaLote,
        exencionActual: ultimaExencion,
        reiniciaActual: ultimaReinicia,
      );

      tracked = post.tracked;
      offset = post.offset;
      ultimaExencion = post.exentaHasta;
      ultimaReinicia = post.reinicia;
      moraHistAcum += moraEsteCobro;
      cuotasPagadas = (cuotasPagadas + cuotasLiquidadas)
          .clamp(0, contratoBase.totalCuotas > 0 ? contratoBase.totalCuotas : 9);
    }
    if (ultimaExencion == null) return null;
    return (hasta: ultimaExencion, reinicia: ultimaReinicia);
  }

  /// Recalibración masiva local: solo actualiza tracked/offset; no toca pagos.
  /// [encolarSync]: sube [mora_pendiente_tracked] corregido a Supabase.
  /// [soloEventosMasivosActivos]: limita a eventos masivos Confirmado/Planificacion.
  static Future<int> reconciliarTodos({
    required DatabaseExecutor db,
    bool encolarSync = false,
    bool soloEventosMasivosActivos = false,
  }) async {
    final contratos =
        await _contratosParaReconciliar(db, soloEventosMasivosActivos);
    var actualizados = 0;
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    for (final row in contratos) {
      final contrato = ContratoAlumno.fromJson(row);
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contrato.id],
      );
      if (!necesitaReconciliar(contrato, pagos)) continue;

      final objetivo = objetivoDesdeHistorial(
        contrato: contrato,
        pagos: pagos,
      );
      final exencion = calcularExencionDesdeHistorial(
        contratoBase: contrato,
        pagos: pagos,
      );
      final trackedActual = contrato.moraPendienteTracked;
      final offsetActual = contrato.moraCobradaOffset;

      final resolved = resolverExencionPreservandoLocal(
        localHasta: contrato.moraExentaHasta,
        localReinicia: contrato.moraExencionReinicia,
        desdeHistorial: exencion,
      );

      final trackedDiff = (objetivo.tracked - trackedActual).abs() > 0.01;
      final offsetDiff = (objetivo.offset - offsetActual).abs() > 0.01;

      if (!trackedDiff && !offsetDiff && !resolved.escribir) {
        continue;
      }

      final updates = <String, Object?>{
        'mora_pendiente_tracked': objetivo.tracked,
        'mora_cobrada_offset': objetivo.offset,
        'updated_at': nowUtc,
      };
      // Solo escribe exención si el merge la mejora; nunca degrada admin.
      if (resolved.escribir && resolved.hasta != null) {
        updates['mora_exenta_hasta'] = _exentaHastaIso(resolved.hasta!);
        updates['mora_exencion_reinicia'] = resolved.reinicia ? 1 : 0;
      }

      await db.update(
        'contratos_alumnos',
        updates,
        where: 'id = ?',
        whereArgs: [contrato.id],
      );
      actualizados++;

      if (encolarSync && trackedDiff) {
        await SyncQueue.enqueue(
          executor: db,
          tabla: 'contratos_alumnos',
          operacion: SyncOperation.update,
          registroId: contrato.id,
          payload: {
            'id': contrato.id,
            'mora_pendiente_tracked': objetivo.tracked,
          },
        );
      }
    }

    return actualizados;
  }
}
