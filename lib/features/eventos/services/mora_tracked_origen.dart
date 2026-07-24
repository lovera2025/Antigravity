import 'dart:math' as math;

import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mora_cuota_calculator.dart';

/// Origen atribuido de [mora_pendiente_tracked] a cuotas ya liquidadas.
class MoraPendientePreviaDetalle {
  final int numeroCuota;
  final String mesLabel;
  final double montoAtribuido;
  final DateTime? fechaPagoCuota;
  final double moraDebida;
  final double moraCobrada;

  const MoraPendientePreviaDetalle({
    required this.numeroCuota,
    required this.mesLabel,
    required this.montoAtribuido,
    this.fechaPagoCuota,
    this.moraDebida = 0,
    this.moraCobrada = 0,
  });

  /// Ej: `Al pagar el 24/06 se cobró $300 de $7.200`
  String get subtextoDetalle {
    final debida = moraDebida > 0.01 ? moraDebida : montoAtribuido + moraCobrada;
    final cobrada = moraCobrada;
    final fecha = fechaPagoCuota;
    final montoDeb = _fmtPesos(debida);
    final montoCob = _fmtPesos(cobrada);
    if (fecha != null) {
      final dd = fecha.day.toString().padLeft(2, '0');
      final mm = fecha.month.toString().padLeft(2, '0');
      return 'Al pagar el $dd/$mm se cobró \$$montoCob de \$$montoDeb';
    }
    return 'No cobrada al pagar la cuota (se cobró \$$montoCob de \$$montoDeb)';
  }
}

String _fmtPesos(double v) {
  final n = double.parse(v.toStringAsFixed(2));
  final neg = n < 0;
  final abs = n.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final enteros = parts[0];
  final dec = parts[1];
  final buf = StringBuffer();
  for (var i = 0; i < enteros.length; i++) {
    final fromEnd = enteros.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write('.');
    buf.write(enteros[i]);
  }
  final body = '$buf,$dec';
  return neg ? '-$body' : body;
}

class _OrigenAcc {
  final int numeroCuota;
  final String mesLabel;
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
  });
}

/// Infierre qué cuotas ya pagadas alimentan el tracked (rótulos Opción B).
class MoraTrackedOrigen {
  MoraTrackedOrigen._();

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
  static List<MoraPendientePreviaDetalle> inferir({
    required ContratoAlumno contratoBase,
    required List<Map<String, dynamic>> pagos,
    required double trackedMonto,
    DateTime? antesDe,
    String? excluirPagoId,
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
                fechaPagoCuota: fechaLote,
                moraDebida: d.interesBruto,
                moraCobrada: double.parse(aplicado.toStringAsFixed(2)),
                remanente: rem,
              ),
            );
          }
        }
        // Regla postCobro: tracked se resetea a liquidadas − mora (no arrastra).
        origenes = nuevos;
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
      moraHistAcum += moraEsteCobro;
      cuotasPagadas = (cuotasPagadas + cuotasLiquidadas)
          .clamp(0, contratoBase.totalCuotas > 0 ? contratoBase.totalCuotas : 9);
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
          montoAtribuido: parte,
          fechaPagoCuota: o.fechaPagoCuota,
          moraDebida: o.moraDebida,
          moraCobrada: o.moraCobrada,
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
