import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../../../core/database/sync_queue.dart';
import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';

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
        moraCobradaHistorialPreCobro: moraHistAcum,
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

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  /// `ajuste` tal que [trackedEfectivo] reproduce [deseado] dado el replay.
  static double ajusteParaDeseado({
    required double objetivo,
    required double deseado,
  }) =>
      _round2(deseado - objetivo);

  /// Tracked que debe quedar en ficha tras reconciliar: historial + perdón/poner.
  static double trackedEfectivo({
    required double objetivo,
    required double ajuste,
  }) =>
      _round2(math.max(0.0, objetivo + ajuste));

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
  ///
  /// [encolarSync]: sube la exención reparada. Sin eso quedaba solo en la PC
  /// que la reparó, y las demás seguían calculando otra mora.
  static Future<int> repararExencionDesdeHistorial({
    required DatabaseExecutor db,
    bool soloEventosMasivosActivos = false,
    bool encolarSync = false,
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

      // La misma regla que la revisión ([resolverExencion]): un perdón no se
      // toca, y la de un cobro anulado se va.
      final resolved = resolverExencion(contrato: contrato, pagos: pagos);
      if (!resolved.escribir) continue;

      final cambios = {
        'mora_exenta_hasta':
            resolved.hasta == null ? null : _exentaHastaIso(resolved.hasta!),
        'mora_exencion_reinicia': resolved.reinicia ? 1 : 0,
      };
      await db.update(
        'contratos_alumnos',
        cambios,
        where: 'id = ?',
        whereArgs: [contrato.id],
      );
      if (encolarSync) {
        await SyncQueue.enqueue(
          executor: db,
          tabla: 'contratos_alumnos',
          operacion: SyncOperation.update,
          registroId: contrato.id,
          payload: {'id': contrato.id, ...cambios},
        );
      }
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

  /// La exención que dejó un cobro **que después se anuló**, y la que
  /// corresponde sin él.
  ///
  /// Anular un cobro rehacía tracked y offset desde los pagos que quedan, pero
  /// la exención que ese cobro había dado quedaba: MONTENEGRO, FRANCISCO NAHUEL
  /// siguió eximido hasta el 30/09 aunque el cobro del 19/09, el que la dio, se
  /// anuló entero.
  ///
  /// Es de un cobro anulado cuando el historial **con** las líneas anuladas da
  /// exactamente la exención que tiene el contrato, y el historial sin ellas da
  /// otra o ninguna. **Un perdón no se toca:** deja su ajuste de ficha
  /// (`mora_tracked_ajuste`), y si no lo dejó, ningún historial reproduce su
  /// fecha y su permanencia.
  ///
  /// `null`: no es de un cobro anulado, no se toca. Si lo es, la que
  /// corresponde sin las anuladas (`hasta: null` = ninguna).
  static ({DateTime? hasta, bool reinicia})? exencionDeCobroAnulado({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> pagos,
  }) {
    final local = contrato.moraExentaHasta;
    if (local == null) return null;
    if (contrato.moraTrackedAjuste.abs() > 0.01) return null;
    final hayAnuladas =
        pagos.any((p) => ((p['anulado'] as num?)?.toInt() ?? 0) != 0);
    if (!hayAnuladas) return null;

    bool esLaLocal(({DateTime hasta, bool reinicia})? e) =>
        e != null &&
        _mismoDia(e.hasta, local) &&
        e.reinicia == contrato.moraExencionReinicia;

    final conAnuladas = _calcularExencionDesdeHistorial(
      contratoBase: contrato,
      pagos: [
        for (final p in pagos) {...p, 'anulado': 0},
      ],
    );
    if (!esLaLocal(conAnuladas)) return null;

    final sinAnuladas = _calcularExencionDesdeHistorial(
      contratoBase: contrato,
      pagos: pagos,
    );
    if (esLaLocal(sinAnuladas)) return null;
    return (hasta: sinAnuladas?.hasta, reinicia: sinAnuladas?.reinicia ?? true);
  }

  static bool _mismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// La eximición que tiene que quedar. Una sola regla para la revisión y la
  /// reparación:
  ///
  /// - la de un cobro anulado se deshace ([exencionDeCobroAnulado]);
  /// - la que vino de cobros la reemplaza la del último cobro que dio una: una
  ///   eximición vieja no le pasa su "permanente" a una nueva. MONTENEGRO,
  ///   GISEL tenía la del 24/07, permanente (ese cobro no completó cuota), y el
  ///   21/08 saldó la mora completando la cuota 3 (esa vuelve a contar). Con
  ///   "la permanente gana", su cuota 4 dejaba de sumar mora para siempre;
  /// - la de un perdón (la que ningún cobro da, o con ajuste de ficha) se
  ///   protege como siempre: la fecha más lejana, y la permanente gana.
  ///
  /// `escribir`: si hay que guardar algo distinto de lo que tiene el contrato.
  static ({DateTime? hasta, bool reinicia, bool escribir}) resolverExencion({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> pagos,
  }) {
    final deAnulado = exencionDeCobroAnulado(contrato: contrato, pagos: pagos);
    if (deAnulado != null) {
      return (
        hasta: deAnulado.hasta,
        reinicia: deAnulado.reinicia,
        escribir: true,
      );
    }
    final otorgadas = <({DateTime hasta, bool reinicia})>[];
    final hist = _calcularExencionDesdeHistorial(
      contratoBase: contrato,
      pagos: pagos,
      otorgadas: otorgadas,
    );
    final local = contrato.moraExentaHasta;
    final localDeCobro = local != null &&
        contrato.moraTrackedAjuste.abs() <= 0.01 &&
        otorgadas.any(
          (e) =>
              _mismoDia(e.hasta, local) &&
              e.reinicia == contrato.moraExencionReinicia,
        );
    if (localDeCobro && hist != null) {
      final igual = _mismoDia(hist.hasta, local) &&
          hist.reinicia == contrato.moraExencionReinicia;
      return (hasta: hist.hasta, reinicia: hist.reinicia, escribir: !igual);
    }
    final r = resolverExencionPreservandoLocal(
      localHasta: local,
      localReinicia: contrato.moraExencionReinicia,
      desdeHistorial: hist,
    );
    return (
      hasta: r.hasta,
      reinicia: r.reinicia,
      escribir: r.escribir && r.hasta != null,
    );
  }

  /// Mora cobrada (sin anuladas): lo que la cuenta descuenta por FIFO.
  static double moraCobradaDelHistorial(List<Map<String, dynamic>> pagos) =>
      _round2(
        pagos
            .where((p) => ((p['anulado'] as num?)?.toInt() ?? 0) == 0)
            .where(_esMora)
            .fold<double>(
              0,
              (s, p) => s + ((p['monto'] as num?)?.toDouble() ?? 0),
            ),
      );

  /// Calcula la fecha de exención para un contrato dado su historial.
  /// Retorna la fecha si el último lote con mora saldó toda la pendiente.
  static ({DateTime hasta, bool reinicia})? _calcularExencionDesdeHistorial({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,

    /// Si viene, se llena con cada exención que dio un cobro, en orden.
    List<({DateTime hasta, bool reinicia})>? otorgadas,
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
        moraCobradaHistorialPreCobro: moraHistAcum,
      );

      final nueva = post.exentaHasta;
      if (otorgadas != null &&
          nueva != null &&
          (ultimaExencion == null ||
              !_mismoDia(nueva, ultimaExencion) ||
              post.reinicia != ultimaReinicia)) {
        otorgadas.add((hasta: nueva, reinicia: post.reinicia));
      }
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

  /// Recalibración masiva local: actualiza tracked, offset y exención desde el
  /// historial de pagos; no toca pagos.
  ///
  /// [encolarSync]: sube **todo** lo que corrigió (tracked, offset y la
  /// exención). Antes subía solo el tracked: un offset corregido quedaba en la
  /// PC, y la próxima bajada del evento (donde la nube manda) lo volvía a
  /// pisar. Así 13 alumnos con cobros de agosto quedaron con el offset en 0 en
  /// todas las PCs y la mora que ya habían pagado se les descontaba de nuevo de
  /// la de los meses siguientes (VERON, DALMA: $1.100 en vez de $33.000).
  ///
  /// [soloEventosMasivosActivos]: limita a eventos masivos Confirmado/Planificacion.
  ///
  /// [constancia]: recibe un renglón por alumno corregido, con el antes y el
  /// después (la app lo guarda en `revision_mora.txt`, junto a la base).
  ///
  /// [soloContratos]: revisa solo esos. Lo usa reincorporar una baja temporal
  /// (6.1.0): la 6.0.0 rehacía la ficha de una baja contando la mora hasta el
  /// día de la baja también para los pagos viejos, y ESPINOZA, DENIS AIMARA
  /// quedó con $87.600 de ficha por tres cuotas que había pagado antes de que
  /// vencieran. Al volver se rehace en el momento, sin esperar a la próxima vez
  /// que se abra el programa.
  static Future<int> reconciliarTodos({
    required DatabaseExecutor db,
    bool encolarSync = false,
    bool soloEventosMasivosActivos = false,
    Future<void> Function(List<String> renglones)? constancia,
    DateTime? ahoraAr,
    Set<String>? soloContratos,
  }) async {
    final todos =
        await _contratosParaReconciliar(db, soloEventosMasivosActivos);
    final contratos = soloContratos == null
        ? todos
        : [
            for (final r in todos)
              if (soloContratos.contains(r['id'])) r,
          ];
    var actualizados = 0;
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final renglones = <String>[];

    for (final row in contratos) {
      final contrato = ContratoAlumno.fromJson(row);
      // Quien ya terminó de pagar no se revisa, como en
      // [repararExencionDesdeHistorial]. Sin saldo no corre mora: queda solo la
      // ficha, y la dejó el cobro o el perdón del jefe. Rehecha desde los pagos
      // da siempre $0, porque el repaso usa el saldo de hoy. ALTAMIRANO,
      // CELESTE ABIGAIL pagó el 15/10 los $407.000 acordados sin la mora; el
      // cobro dejó $683.760 en la ficha para que el jefe los perdone como
      // liquidación, y la revisión se los borraba sola.
      if (contrato.saldoDeudor <= 0.01) continue;
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
      final trackedActual = contrato.moraPendienteTracked;
      final offsetActual = contrato.moraCobradaOffset;
      final trackedFinal = trackedEfectivo(
        objetivo: objetivo.tracked,
        ajuste: contrato.moraTrackedAjuste,
      );

      // La exención: ver [resolverExencion] (un perdón no se toca).
      DateTime? hastaFinal = contrato.moraExentaHasta;
      var reiniciaFinal = contrato.moraExencionReinicia;
      var exencionCambio = false;
      final resuelta = resolverExencion(contrato: contrato, pagos: pagos);
      if (resuelta.escribir) {
        hastaFinal = resuelta.hasta;
        reiniciaFinal = resuelta.reinicia;
        exencionCambio = true;
      }

      final trackedDiff = (trackedFinal - trackedActual).abs() > 0.01;
      final offsetDiff = (objetivo.offset - offsetActual).abs() > 0.01;

      if (!trackedDiff && !offsetDiff && !exencionCambio) {
        continue;
      }

      final hastaIso = hastaFinal == null ? null : _exentaHastaIso(hastaFinal);
      final updates = <String, Object?>{
        'mora_pendiente_tracked': trackedFinal,
        'mora_cobrada_offset': objetivo.offset,
        'updated_at': nowUtc,
      };
      // No toca mora_tracked_ajuste: el perdón/poner admin tiene que sobrevivir.
      if (exencionCambio) {
        updates['mora_exenta_hasta'] = hastaIso;
        updates['mora_exencion_reinicia'] = reiniciaFinal ? 1 : 0;
      }

      await db.update(
        'contratos_alumnos',
        updates,
        where: 'id = ?',
        whereArgs: [contrato.id],
      );
      actualizados++;

      if (encolarSync) {
        // Va todo junto: la exención como par (hasta + reinicia) aunque no
        // haya cambiado acá, porque puede ser la única copia (las de antes del
        // 28/08 no llegaron nunca a la nube).
        await SyncQueue.enqueue(
          executor: db,
          tabla: 'contratos_alumnos',
          operacion: SyncOperation.update,
          registroId: contrato.id,
          payload: {
            'id': contrato.id,
            'mora_pendiente_tracked': trackedFinal,
            'mora_cobrada_offset': objetivo.offset,
            'mora_exenta_hasta': hastaIso,
            'mora_exencion_reinicia': reiniciaFinal ? 1 : 0,
          },
        );
      }

      if (constancia != null) {
        final cobrada = moraCobradaDelHistorial(pagos);
        final despues = contrato.copyWith(
          moraPendienteTracked: trackedFinal,
          moraCobradaOffset: objetivo.offset,
          moraExentaHasta: hastaFinal,
          moraExencionReinicia: reiniciaFinal,
        );
        final moraAntes = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: contrato,
          moraCobradaHistorial: cobrada,
          ahoraAr: ahoraAr,
        );
        final moraDespues = MoraCuotaCalculator.moraPendienteOperativa(
          contrato: despues,
          moraCobradaHistorial: cobrada,
          ahoraAr: ahoraAr,
        );
        String f(double v) => '\$${v.toStringAsFixed(0)}';
        String ex(DateTime? d, bool r) =>
            d == null ? 'sin' : '${_exentaHastaIso(d)}${r ? '' : ' permanente'}';
        renglones.add(
          '${contrato.nombreAlumno}: mora ${f(moraAntes)} -> ${f(moraDespues)}'
          ' · ya usado ${f(offsetActual)} -> ${f(objetivo.offset)}'
          ' · de ficha ${f(trackedActual)} -> ${f(trackedFinal)}'
          ' · eximición ${ex(contrato.moraExentaHasta, contrato.moraExencionReinicia)}'
          ' -> ${ex(hastaFinal, reiniciaFinal)}',
        );
      }
    }

    if (constancia != null && renglones.isNotEmpty) {
      try {
        await constancia(renglones);
      } catch (_) {
        // La constancia es un aviso, no puede frenar la revisión.
      }
    }
    return actualizados;
  }

  /// Encabezado de [fichasSinExplicar] en `revision_mora.txt`.
  static const queHizoFichasSinExplicar =
      'la mora de la ficha no se explica cuota por cuota en';

  /// Las fichas con mora que no se explica cuota por cuota (6.1.0): un renglón
  /// por alumno, con la ficha y lo que falta explicar. La revisión que corre al
  /// abrir el programa los anota en `revision_mora.txt`; en la grilla salen con
  /// el filtro de mora "Revisar la ficha".
  ///
  /// La cuenta es la misma de la ventana de cobro: lo que reconstruye
  /// [MoraTrackedOrigen.inferir] desde los pagos (ver
  /// [MoraTrackedOrigen.sinExplicar]). Incluye a las bajas: ESPINOZA, DENIS
  /// AIMARA estaba de baja cuando apareció.
  static Future<List<String>> fichasSinExplicar(DatabaseExecutor db) async {
    final contratos = await db.query(
      'contratos_alumnos',
      where: 'mora_pendiente_tracked > 0.01',
    );
    final renglones = <String>[];
    for (final row in contratos) {
      final contrato = ContratoAlumno.fromJson(row);
      final pagos = await db.query(
        'pagos_contrato_alumno',
        where: 'contrato_alumno_id = ?',
        whereArgs: [contrato.id],
        orderBy: 'fecha_pago ASC',
      );
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: contrato.moraPendienteTracked,
        recorte: MoraOrigenRecorte.loQueQueda,
      );
      final falta = MoraTrackedOrigen.sinExplicar(
        tracked: contrato.moraPendienteTracked,
        origen: origen,
      );
      if (falta <= 0.01) continue;
      renglones.add(
        '${contrato.nombreAlumno}: mora en la ficha '
        '\$${contrato.moraPendienteTracked.toStringAsFixed(0)}, '
        'sin explicar \$${falta.toStringAsFixed(0)}',
      );
    }
    return renglones;
  }
}
