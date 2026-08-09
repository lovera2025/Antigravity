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

  /// Días de atraso que tenía la cuota cuando se liquidó. Es el dato que
  /// explica el monto ("27 días de junio"), no un recálculo al día de hoy:
  /// el arrastre queda congelado en el momento del cobro.
  final int diasMora;

  /// Vencimiento original de la cuota que generó esta mora.
  final DateTime? vencimiento;

  const MoraPendientePreviaDetalle({
    required this.numeroCuota,
    required this.mesLabel,
    required this.montoAtribuido,
    this.fechaPagoCuota,
    this.moraDebida = 0,
    this.moraCobrada = 0,
    this.diasMora = 0,
    this.vencimiento,
  });

  /// Ej: `C2 (May) · 23 días` — para la grilla, sin monto.
  String get etiquetaCorta {
    final mes = mesLabel.split(' ').first;
    final base = mes.isEmpty ? 'C$numeroCuota' : 'C$numeroCuota ($mes)';
    return diasMora > 0 ? '$base ${diasMora}d' : base;
  }

  /// Explica de dónde sale esta mora, para que se entienda leyendo el recibo:
  /// cuándo venció la cuota, cuánto tardó en pagarse y qué quedó sin cobrar.
  ///
  /// Ej: `Venció el 31/05/2026 · se pagó el 23/06/2026, 23 días tarde · no se
  /// cobró nada de los $6.900,00 de mora`
  String get subtextoDetalle {
    final debida = moraDebida > 0.01 ? moraDebida : montoAtribuido + moraCobrada;
    final partes = <String>[];

    final venc = vencimiento;
    if (venc != null) partes.add('Venció el ${_fmtFecha(venc)}');

    final fecha = fechaPagoCuota;
    if (fecha != null) {
      final tarde = diasMora > 0
          ? ', $diasMora ${diasMora == 1 ? 'día' : 'días'} tarde'
          : '';
      partes.add('se pagó el ${_fmtFecha(fecha)}$tarde');
    } else if (diasMora > 0) {
      partes.add('$diasMora ${diasMora == 1 ? 'día' : 'días'} de atraso');
    }

    if (moraCobrada > 0.01) {
      partes.add('se cobró \$${_fmtPesos(moraCobrada)} de los '
          '\$${_fmtPesos(debida)} de mora');
    } else {
      partes.add('no se cobró nada de los \$${_fmtPesos(debida)} de mora');
    }

    final texto = partes.join(' · ');
    if (texto.isEmpty) return texto;
    return texto[0].toUpperCase() + texto.substring(1);
  }
}

String _fmtFecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

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
