// La regla de la 6.8.0 para repartir la mora de un lote que liquida cuotas,
// copiada tal cual del tag v6.8.0 (`MoraTrackedOrigen.inferir`). Vive acá, y
// solo acá, para comparar: las pruebas y el comparador sobre la copia de la base
// la corren al lado de la de hoy para ver qué cambió. La app nunca la usa.
//
// No tocar: si se corrige algo acá, la comparación deja de decir la verdad.
// ignore_for_file: unused_element

import 'dart:math' as math;

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

class _OrigenAcc {
  final int numeroCuota;
  final String mesLabel;
  final int diasMora;
  final DateTime? vencimiento;
  final DateTime? fechaPagoCuota;
  final double moraDebida;
  final double moraCobrada;
  double remanente;

  _OrigenAcc({
    required this.numeroCuota,
    required this.mesLabel,
    required this.fechaPagoCuota,
    required this.moraDebida,
    required this.moraCobrada,
    required this.remanente,
    this.diasMora = 0,
    this.vencimiento,
  });
}

/// Infierre qué cuotas ya pagadas alimentan el tracked (rótulos Opción B).
class InferirDeLa680 {
  InferirDeLa680._();

  /// Cuánto de la mora de la ficha ([tracked]) no se explica cuota por cuota
  /// con lo que reconstruyó [inferir] ([origen]). 0 si se explica entera (un
  /// peso de diferencia por redondeos no cuenta).
  ///
  /// La ventana de cobro y el perdón muestran la ficha cuota por cuota con esa
  /// reconstrucción; lo que no se explica sale como un renglón genérico ("sin
  /// origen identificado"). El 18-oct eran 50 de 51 fichas explicadas: la otra,
  /// GUATAMBU, DENIS AIMARA, tenía $87.600 que la 6.0.0 había inventado (ver
  /// `MoraTrackedRecovery.reconciliarTodos`). Esto avisa si vuelve a pasar.
  static double sinExplicar({
    required double tracked,
    required List<MoraPendientePreviaDetalle> origen,
  }) {
    if (tracked <= 0.01) return 0;
    final explicado = origen
        .where((d) => d.numeroCuota > 0)
        .fold<double>(0, (s, d) => s + d.montoAtribuido);
    final falta = tracked - explicado;
    return falta > 1 ? double.parse(falta.toStringAsFixed(2)) : 0;
  }

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

  /// Filtra pagos estrictamente anteriores a [antesDe] (si se indica).
  static List<Map<String, dynamic>> _pagosHasta(
    List<Map<String, dynamic>> pagos, {
    DateTime? antesDe,
    String? excluirPagoId,
  }) {
    return pagos.where((p) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
      if (excluirPagoId != null && p['id']?.toString() == excluirPagoId) {
        return false;
      }
      if (antesDe == null) return true;
      final f = p['fecha_pago']?.toString();
      if (f == null) return true;
      final parsed = DateTime.tryParse(f);
      if (parsed == null) return true;
      return parsed.isBefore(antesDe);
    }).toList();
  }

  /// Simula orígenes del tracked aplicando las mismas reglas que el cobro.
  ///
  /// [trackedMonto]: monto a etiquetar (FIFO sobre orígenes vivos).
  /// [antesDe] / [excluirPagoId]: historial previo al cobro que se está rotulando.
  /// [recorte]: qué punta de la cola se descarta. Ver [MoraOrigenRecorte].
  static List<MoraPendientePreviaDetalle> inferir({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,
    required double trackedMonto,
    DateTime? antesDe,
    String? excluirPagoId,
    MoraOrigenRecorte recorte = MoraOrigenRecorte.loQueSeCobra,
  }) {
    final monto = double.parse(
      trackedMonto.clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    if (monto <= 0.01) return const [];

    final pagosFiltrados = _pagosHasta(
      pagos,
      antesDe: antesDe,
      excluirPagoId: excluirPagoId,
    );

    var tracked = 0.0;
    var offset = 0.0;
    var cuotasPagadas = 0;
    var moraHistAcum = 0.0;
    // La exención se reconstruye cronológicamente, igual que en
    // [MoraTrackedRecovery.recomputarDesdeHistorial]: aplicar la de hoy al
    // pasado borra el desglose de aquel momento y deja el tracked sin origen
    // que atribuirle (el recibo terminaba diciendo "de cuotas ya pagadas").
    DateTime? ultimaExencion;
    var ultimaReinicia = true;
    final pagosAcum = <Map<String, dynamic>>[];
    var origenes = <_OrigenAcc>[];

    for (final lote in _lotesCronologicos(pagosFiltrados)) {
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

      if (cuotasLiquidadas > 0) {
        final cuotasPre = cuotasPagadas;
        final cuotasPostCobro = cuotasPagadas + cuotasLiquidadas;
        final liquidadas = moraDesgloseNeto
            .where(
              (d) =>
                  d.numeroCuota > cuotasPre &&
                  d.numeroCuota <= cuotasPostCobro,
            )
            .toList();
        // FIFO: aplicar moraEsteCobro a las liquidadas; remanente = origen nuevo.
        var moraRestante = moraEsteCobro;
        final nuevos = <_OrigenAcc>[];
        for (final d in liquidadas) {
          final aplicado = math.min(d.interesBruto, moraRestante);
          moraRestante = (moraRestante - aplicado).clamp(0.0, double.infinity);
          final rem = double.parse(
            (d.interesBruto - aplicado).clamp(0.0, double.infinity).toStringAsFixed(2),
          );
          if (rem > 0.01) {
            nuevos.add(
              _OrigenAcc(
                numeroCuota: d.numeroCuota,
                mesLabel: d.mesLabel,
                diasMora: d.diasMora,
                vencimiento: d.vencimiento,
                fechaPagoCuota: fechaLote,
                moraDebida: d.interesBruto,
                moraCobrada: double.parse(aplicado.toStringAsFixed(2)),
                remanente: rem,
              ),
            );
          }
        }
        // Lo que sobre de la mora cobrada baja el arrastre viejo, FIFO.
        final previos = <_OrigenAcc>[];
        for (final o in origenes) {
          if (moraRestante <= 0.01) {
            previos.add(o);
            continue;
          }
          final toma = math.min(o.remanente, moraRestante);
          moraRestante = (moraRestante - toma).clamp(0.0, double.infinity);
          final nuevoRem = double.parse(
            (o.remanente - toma).clamp(0.0, double.infinity).toStringAsFixed(2),
          );
          if (nuevoRem > 0.01) {
            previos.add(
              _OrigenAcc(
                numeroCuota: o.numeroCuota,
                mesLabel: o.mesLabel,
                vencimiento: o.vencimiento,
                diasMora: o.diasMora,
                fechaPagoCuota: o.fechaPagoCuota,
                moraDebida: o.moraDebida,
                moraCobrada: double.parse(
                  (o.moraCobrada + toma).toStringAsFixed(2),
                ),
                remanente: nuevoRem,
              ),
            );
          }
        }
        // Espejo de postCobroTrackedOffset: el arrastre se acumula. Los previos
        // son de cuotas liquidadas en cobros anteriores y los nuevos de las que
        // se liquidan ahora — disjuntos por construcción. Con cuotasPre == 0 no
        // puede haber arrastre legítimo (misma guarda que el tracked).
        origenes = [if (cuotasPre > 0) ...previos, ...nuevos];
      } else if (moraEsteCobro > 0.01) {
        // Solo mora: reduce tracked / orígenes FIFO.
        var rest = moraEsteCobro;
        final vivos = <_OrigenAcc>[];
        for (final o in origenes) {
          if (rest <= 0.01) {
            vivos.add(o);
            continue;
          }
          final toma = math.min(o.remanente, rest);
          rest = (rest - toma).clamp(0.0, double.infinity);
          final nuevoRem = double.parse(
            (o.remanente - toma).clamp(0.0, double.infinity).toStringAsFixed(2),
          );
          if (nuevoRem > 0.01) {
            vivos.add(
              _OrigenAcc(
                numeroCuota: o.numeroCuota,
                mesLabel: o.mesLabel,
                vencimiento: o.vencimiento,
                diasMora: o.diasMora,
                fechaPagoCuota: o.fechaPagoCuota,
                moraDebida: o.moraDebida,
                moraCobrada: double.parse(
                  (o.moraCobrada + toma).toStringAsFixed(2),
                ),
                remanente: nuevoRem,
              ),
            );
          }
        }
        origenes = vivos;
      }

      tracked = post.tracked;
      offset = post.offset;
      ultimaExencion = post.exentaHasta;
      ultimaReinicia = post.reinicia;
      moraHistAcum += moraEsteCobro;
      cuotasPagadas = (cuotasPagadas + cuotasLiquidadas)
          .clamp(0, contratoBase.totalCuotas > 0 ? contratoBase.totalCuotas : 9);
    }

    // "Qué queda debiéndose": lo que la cola suma de más que la ficha es plata
    // que ya se saldó o se perdonó, y se saldó/perdonó de la más vieja a la más
    // nueva. Se descuenta desde la cabeza para que el mes viejo se caiga del
    // rótulo; recortarlo por la cola dejaba nombrado justo el que se perdonó.
    if (recorte == MoraOrigenRecorte.loQueQueda) {
      final totalVivo = origenes.fold<double>(0, (s, o) => s + o.remanente);
      var brecha = double.parse(
        (totalVivo - monto).clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      if (brecha > 0.01) {
        final quedan = <_OrigenAcc>[];
        for (final o in origenes) {
          if (brecha <= 0.01) {
            quedan.add(o);
            continue;
          }
          final toma = math.min(o.remanente, brecha);
          brecha = double.parse((brecha - toma).toStringAsFixed(2));
          final nuevoRem = double.parse(
            (o.remanente - toma).clamp(0.0, double.infinity).toStringAsFixed(2),
          );
          if (nuevoRem <= 0.01) continue;
          // Solo baja el remanente: [moraDebida] y [moraCobrada] describen qué
          // pasó cuando se liquidó la cuota. Un perdón no es plata que entró.
          quedan.add(
            _OrigenAcc(
              numeroCuota: o.numeroCuota,
              mesLabel: o.mesLabel,
              vencimiento: o.vencimiento,
              diasMora: o.diasMora,
              fechaPagoCuota: o.fechaPagoCuota,
              moraDebida: o.moraDebida,
              moraCobrada: o.moraCobrada,
              remanente: nuevoRem,
            ),
          );
        }
        origenes = quedan;
      }
    }

    // Atribuir [monto] FIFO sobre orígenes vivos.
    var restante = monto;
    final out = <MoraPendientePreviaDetalle>[];
    for (final o in origenes) {
      if (restante <= 0.01) break;
      final parte = double.parse(
        math.min(o.remanente, restante).toStringAsFixed(2),
      );
      if (parte <= 0.01) continue;
      restante = double.parse((restante - parte).toStringAsFixed(2));
      out.add(
        MoraPendientePreviaDetalle(
          numeroCuota: o.numeroCuota,
          mesLabel: o.mesLabel,
          vencimiento: o.vencimiento,
          montoAtribuido: parte,
          fechaPagoCuota: o.fechaPagoCuota,
          moraDebida: o.moraDebida,
          moraCobrada: o.moraCobrada,
          diasMora: o.diasMora,
        ),
      );
    }

    // Fallback: tracked sin orígenes reconstruibles → cuota genérica no inventamos número.
    if (out.isEmpty && monto > 0.01) {
      return const [];
    }
    return out;
  }
}
