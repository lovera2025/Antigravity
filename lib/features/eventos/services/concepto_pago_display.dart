import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'mesas_extra_utils.dart';

/// Resultado de rotular un pago del plan (base / mesa / sillas).
class RotuloPlanPago {
  final String concepto;
  final int cuotasLiquidadas;
  final String? subtexto;

  const RotuloPlanPago({
    required this.concepto,
    required this.cuotasLiquidadas,
    this.subtexto,
  });
}

/// Motor global de lectura de conceptos de pago (no modifica DB).
class ConceptoPagoDisplay {
  ConceptoPagoDisplay._();

  static double grossPago(Map<String, dynamic> p) {
    return (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num?)?.toDouble() ??
        0.0;
  }

  static bool esAnulado(Map<String, dynamic> p) =>
      ((p['anulado'] as num?)?.toInt() ?? 0) != 0;

  static bool esMora(Map<String, dynamic> p) {
    final lk = (p['line_kind'] as String?)?.trim();
    return lk == kLineKindInteresMora ||
        esPagoInteresMoraPorConcepto(p['concepto']?.toString());
  }

  static bool esCargoCanal(Map<String, dynamic> p) {
    final lk = (p['line_kind'] as String?)?.trim();
    return lk == kLineKindCargoCanal ||
        esPagoCargoCanalPorConcepto(p['concepto']?.toString());
  }

  static bool esPlanBase(Map<String, dynamic> p) {
    if (esMora(p) || esCargoCanal(p) || esAnulado(p)) return false;
    final c = (p['concepto'] as String? ?? '').toLowerCase();
    return !c.contains('mesa') && !c.contains('silla');
  }

  static bool esPlanMesa(Map<String, dynamic> p) {
    if (esMora(p) || esCargoCanal(p) || esAnulado(p)) return false;
    return (p['concepto'] as String? ?? '').toLowerCase().contains('mesa');
  }

  static bool esPlanSillas(Map<String, dynamic> p) {
    if (esMora(p) || esCargoCanal(p) || esAnulado(p)) return false;
    return (p['concepto'] as String? ?? '').toLowerCase().contains('silla');
  }

  static String? subtituloMedio(Map<String, dynamic> p) {
    final med = (p['medio_pago'] as String?)?.trim();
    if (med == null || med.isEmpty) return null;
    if (med.toLowerCase() == 'mixto') return null;
    return '· $med';
  }

  /// Rotula un pago del plan según gross histórico + gross de esta línea.
  static RotuloPlanPago rotularPlanDesdeGross({
    required double grossHistorico,
    required double grossActual,
    required double cuotaPura,
    required int totalCuotas,
    required String etiqueta,
  }) {
    if (cuotaPura <= 0.001) {
      return RotuloPlanPago(
        concepto: etiqueta.contains('Entrega') ? etiqueta : '$etiqueta - Entrega',
        cuotasLiquidadas: grossActual > 0.01 ? 1 : 0,
      );
    }

    final cuotasAntes =
        cuotasCompletasDesdeGrossAcumulado(grossHistorico, cuotaPura);
    final avance = evaluarAvanceCuotaConAbonos(
      grossHistoricoClase: grossHistorico,
      grossActual: grossActual,
      cuotaPura: cuotaPura,
    );
    final primera = cuotasAntes + 1;
    final ultima = avance.cuotasCompletasDespues;
    final n = avance.cuotasLiquidadas;
    final corto = _etiquetaCorto(etiqueta);

    if (avance.esAbonoSolo) {
      return RotuloPlanPago(
        concepto: rotuloEntregaParcial('$etiqueta ($primera/$totalCuotas)'),
        cuotasLiquidadas: 0,
      );
    }

    if (n > 1 && avance.cierraCuotaExacta) {
      return RotuloPlanPago(
        concepto: 'Cuotas $corto ($primera–$ultima/$totalCuotas)',
        cuotasLiquidadas: n,
      );
    }

    if (avance.cierraConAdelanto) {
      final prox = ultima + 1;
      final habiaParcial = habiaEntregaParcialEnCurso(
        grossHistorico: grossHistorico,
        cuotaPura: cuotaPura,
      );
      final subCompletada = habiaParcial
          ? subtextoSiCierraEntregaParcial(
              grossHistorico: grossHistorico,
              grossEsteCobro: grossActual,
              cuotaPura: cuotaPura,
            )
          : null;
      if (n == 1) {
        final rotuloPrimera = rotuloCuotaLiquidada(
          etiqueta: etiqueta,
          numeroCuota: ultima,
          totalCuotas: totalCuotas,
          cierraEntregaParcialPrevio: habiaParcial,
        );
        return RotuloPlanPago(
          concepto:
              '$rotuloPrimera + $etiqueta ($prox/$totalCuotas) · \$${fmtMontoRotuloCobro(avance.restoAbono)}',
          cuotasLiquidadas: 1,
          subtexto: subCompletada,
        );
      }
      return RotuloPlanPago(
        concepto:
            '$n Cuotas $corto ($primera–$ultima/$totalCuotas) + $etiqueta ($prox/$totalCuotas)',
        cuotasLiquidadas: n,
      );
    }

    if (n == 1) {
      final habiaParcial = habiaEntregaParcialEnCurso(
        grossHistorico: grossHistorico,
        cuotaPura: cuotaPura,
      );
      return RotuloPlanPago(
        concepto: rotuloCuotaLiquidada(
          etiqueta: etiqueta,
          numeroCuota: ultima,
          totalCuotas: totalCuotas,
          cierraEntregaParcialPrevio: habiaParcial,
        ),
        cuotasLiquidadas: 1,
        subtexto: habiaParcial
            ? subtextoSiCierraEntregaParcial(
                grossHistorico: grossHistorico,
                grossEsteCobro: grossActual,
                cuotaPura: cuotaPura,
              )
            : null,
      );
    }

    return RotuloPlanPago(
      concepto: '$n Cuotas ($etiqueta)',
      cuotasLiquidadas: n,
    );
  }

  static String _etiquetaCorto(String etiqueta) {
    if (etiqueta == 'Cuota Base') return 'Base';
    if (etiqueta.startsWith('Mesa Extra')) return etiqueta;
    if (etiqueta == 'Sillas Extras') return 'Sillas Extras';
    return etiqueta;
  }

  static double cuotaPuraBase(ContratoAlumno c) {
    final totalBase = (c.montoTotalPactado -
            c.mesaExtraPrecio -
            c.sillasExtraPrecioTotal)
        .clamp(0.0, double.infinity);
    final t = c.totalCuotas > 0 ? c.totalCuotas : 9;
    return t > 0
        ? double.parse((totalBase / t).toStringAsFixed(2))
        : totalBase;
  }

  static double cuotaPuraMesa(ContratoAlumno c) {
    final cuotas = c.mesaExtraCuotas > 0 ? c.mesaExtraCuotas : 1;
    if (c.mesaExtraPrecio <= 0.01) return 0;
    return double.parse((c.mesaExtraPrecio / cuotas).toStringAsFixed(2));
  }

  static double cuotaPuraSillas(ContratoAlumno c) {
    final cuotas = c.sillasExtraCuotas > 0 ? c.sillasExtraCuotas : 1;
    if (c.sillasExtraPrecioTotal <= 0.01) return 0;
    return double.parse(
      (c.sillasExtraPrecioTotal / cuotas).toStringAsFixed(2),
    );
  }

  static int _compareCronologico(Map<String, dynamic> a, Map<String, dynamic> b) {
    final fa = DateTime.tryParse(a['fecha_pago'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final fb = DateTime.tryParse(b['fecha_pago'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final cmp = fa.compareTo(fb);
    if (cmp != 0) return cmp;
    final ga = grossPago(b);
    final gb = grossPago(a);
    final cmpG = ga.compareTo(gb);
    if (cmpG != 0) return cmpG;
    final ia = a['id'] as String? ?? '';
    final ib = b['id'] as String? ?? '';
    return ia.compareTo(ib);
  }

  /// Enriquece pagos para Estado de Cuenta / reimpresión (más reciente primero).
  static List<Map<String, dynamic>> enriquecerPagosHistorial(
    ContratoAlumno contrato,
    List<Map<String, dynamic>> pagos,
  ) {
    final activos = pagos.where((p) => !esAnulado(p)).toList()
      ..sort(_compareCronologico);

    final tCuotas = contrato.totalCuotas > 0 ? contrato.totalCuotas : 9;
    final mCuotas = contrato.mesaExtraCuotas > 0 ? contrato.mesaExtraCuotas : 1;
    final sCuotas =
        contrato.sillasExtraCuotas > 0 ? contrato.sillasExtraCuotas : 1;

    final cuotaBase = cuotaPuraBase(contrato);
    final cuotaSillas = cuotaPuraSillas(contrato);

    final mesasResumen = MesasExtraUtils.estadoDesdeContrato(contrato);
    final cantMesasHist = mesasResumen.length;
    final precioUnitMesaHist = cantMesasHist > 1
        ? (mesasResumen.first.precio > 0.01
            ? mesasResumen.first.precio
            : contrato.precioUnitarioMesaExtra)
        : contrato.mesaExtraPrecio;

    var grossBaseHist = 0.0;
    var grossSillasHist = 0.0;
    final grossMesaPorN = <int, double>{};
    var mesaFifoActual = 1;
    var acumuladoFifoMesa = 0.0;

    final enriquecidos = <Map<String, dynamic>>[];

    for (final p in activos) {
      final pCpy = Map<String, dynamic>.from(p);
      final gross = grossPago(p);
      String conceptoDisplay = p['concepto'] as String? ?? 'Pago';

      if (esMora(p) || esCargoCanal(p)) {
        conceptoDisplay = conceptoDisplay.trim().isEmpty
            ? 'Interés mora (cuota base — este cobro)'
            : conceptoDisplay;
      } else if (esPlanBase(p)) {
        final rot = rotularPlanDesdeGross(
          grossHistorico: grossBaseHist,
          grossActual: gross,
          cuotaPura: cuotaBase,
          totalCuotas: tCuotas,
          etiqueta: 'Cuota Base',
        );
        conceptoDisplay = rot.concepto;
        if (rot.subtexto != null) {
          pCpy['subtexto_concepto'] = rot.subtexto;
        }
        grossBaseHist += gross;
      } else if (esPlanMesa(p)) {
        final conceptoOriginal = p['concepto'] as String? ?? '';
        final mesaExplicita =
            MesasExtraUtils.numeroMesaDesdeConcepto(conceptoOriginal);
        int mesaN;
        if (mesaExplicita > 1 || cantMesasHist <= 1) {
          mesaN = mesaExplicita;
        } else {
          if (mesaFifoActual < cantMesasHist &&
              acumuladoFifoMesa + gross > precioUnitMesaHist + 0.01) {
            mesaFifoActual++;
            acumuladoFifoMesa = gross;
          } else {
            acumuladoFifoMesa += gross;
          }
          mesaN = mesaFifoActual;
        }

        final unitMesa = cantMesasHist > 0 && precioUnitMesaHist > 0.01
            ? precioUnitMesaHist
            : (contrato.mesaExtraCantidad > 0
                ? contrato.precioUnitarioMesaExtra
                : contrato.mesaExtraPrecio);
        final cuotaPuraMesaN = mCuotas > 0 && unitMesa > 0.01
            ? double.parse((unitMesa / mCuotas).toStringAsFixed(2))
            : unitMesa;

        final histMesa = grossMesaPorN[mesaN] ?? 0.0;
        final prefix = MesasExtraUtils.labelCobro(
          mesaN,
          cantMesasHist > 0 ? cantMesasHist : 1,
        );
        if (mCuotas <= 1) {
          conceptoDisplay = '$prefix - Entrega';
        } else {
          final rot = rotularPlanDesdeGross(
            grossHistorico: histMesa,
            grossActual: gross,
            cuotaPura: cuotaPuraMesaN,
            totalCuotas: mCuotas,
            etiqueta: prefix,
          );
          conceptoDisplay = rot.concepto;
          if (rot.subtexto != null) {
            pCpy['subtexto_concepto'] = rot.subtexto;
          }
        }
        grossMesaPorN[mesaN] = histMesa + gross;

        if (unitMesa > 0.01 && gross >= unitMesa - 0.01) {
          pCpy['es_liquidacion_mesa'] = true;
        }
      } else if (esPlanSillas(p)) {
        final rot = rotularPlanDesdeGross(
          grossHistorico: grossSillasHist,
          grossActual: gross,
          cuotaPura: cuotaSillas,
          totalCuotas: sCuotas,
          etiqueta: sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
        );
        conceptoDisplay = rot.concepto;
        if (rot.subtexto != null) {
          pCpy['subtexto_concepto'] = rot.subtexto;
        }
        grossSillasHist += gross;
      }

      pCpy['concepto_detallado'] = conceptoDisplay;
      pCpy['subtitulo_medio'] = subtituloMedio(p);

      if ((p['descuento_porcentaje'] as num? ?? 0) > 0.01) {
        pCpy['label_descuento'] =
            '${(p['descuento_porcentaje'] as num).toStringAsFixed(0)}% OFF';
      }

      enriquecidos.add(pCpy);
    }

    return enriquecidos.reversed.toList();
  }

  /// Rotula partes de un cobro mixto al registrar (futuros cobros más claros).
  static List<({double gross, double net, String medio, RotuloPlanPago rotulo})>
      rotularPartesMixtoPlan({
    required ContratoAlumno contrato,
    required Map<String, dynamic> previewLinea,
    required double grossHistoricoClase,
    required double grossLinea,
    required double netLinea,
    required double parteEfectivo,
    required double totalIngresado,
  }) {
    final mE = totalIngresado > 0.01
        ? double.parse(
            (netLinea * (parteEfectivo / totalIngresado)).toStringAsFixed(2),
          )
        : 0.0;
    final mT = double.parse((netLinea - mE).toStringAsFixed(2));
    final gE = totalIngresado > 0.01
        ? double.parse(
            (grossLinea * (parteEfectivo / totalIngresado)).toStringAsFixed(2),
          )
        : 0.0;
    final gT = double.parse((grossLinea - gE).toStringAsFixed(2));

    final params = _planParamsDesdePreview(contrato, previewLinea);
    if (params == null) {
      final c = previewLinea['concepto'] as String? ?? 'Pago';
      return [
        if (gT > 0.004)
          (
            gross: gT,
            net: mT,
            medio: 'Transferencia',
            rotulo: RotuloPlanPago(concepto: c, cuotasLiquidadas: 0),
          ),
        if (gE > 0.004)
          (
            gross: gE,
            net: mE,
            medio: 'Efectivo',
            rotulo: RotuloPlanPago(concepto: c, cuotasLiquidadas: 0),
          ),
      ];
    }

    final partes = <({double gross, double net, String medio})>[
      if (gT > 0.004) (gross: gT, net: mT, medio: 'Transferencia'),
      if (gE > 0.004) (gross: gE, net: mE, medio: 'Efectivo'),
    ]..sort((a, b) => b.gross.compareTo(a.gross));

    var hist = grossHistoricoClase;
    final out =
        <({double gross, double net, String medio, RotuloPlanPago rotulo})>[];
    for (final part in partes) {
      final rot = rotularPlanDesdeGross(
        grossHistorico: hist,
        grossActual: part.gross,
        cuotaPura: params.cuotaPura,
        totalCuotas: params.totalCuotas,
        etiqueta: params.etiqueta,
      );
      out.add((
        gross: part.gross,
        net: part.net,
        medio: part.medio,
        rotulo: rot,
      ));
      hist += part.gross;
    }
    return out;
  }

  static double grossHistoricoClasePreview(
    Map<String, double> historicoPorClave,
    Map<String, dynamic> previewLinea,
  ) {
    final key = _claseKeyDesdePreview(previewLinea);
    if (key.startsWith('Mesa:')) {
      return historicoPorClave[key] ?? historicoPorClave['Mesa'] ?? 0.0;
    }
    return historicoPorClave[key] ?? 0.0;
  }

  static void acumularGrossLoteEnHistorial(
    Map<String, double> historicoPorClave,
    Map<String, dynamic> previewLinea,
    double grossLinea,
  ) {
    final key = _claseKeyDesdePreview(previewLinea);
    historicoPorClave[key] =
        double.parse(((historicoPorClave[key] ?? 0) + grossLinea).toStringAsFixed(2));
    if (key.startsWith('Mesa:')) {
      historicoPorClave['Mesa'] =
          double.parse(((historicoPorClave['Mesa'] ?? 0) + grossLinea).toStringAsFixed(2));
    }
  }

  static String _claseKeyDesdePreview(Map<String, dynamic> conc) {
    final mesaN = conc['mesaN'] as int?;
    if (mesaN != null) return 'Mesa:$mesaN';
    final c = (conc['concepto'] as String? ?? '').toUpperCase();
    if (c.contains('MESA')) return 'Mesa';
    if (c.contains('SILLA')) return 'Sillas';
    return 'Base';
  }

  static ({double cuotaPura, int totalCuotas, String etiqueta})?
      _planParamsDesdePreview(
    ContratoAlumno contrato,
    Map<String, dynamic> conc,
  ) {
    final key = _claseKeyDesdePreview(conc);
    final mesaN = conc['mesaN'] as int?;
    if (key == 'Base') {
      return (
        cuotaPura: cuotaPuraBase(contrato),
        totalCuotas: contrato.totalCuotas > 0 ? contrato.totalCuotas : 9,
        etiqueta: 'Cuota Base',
      );
    }
    if (key.startsWith('Mesa') || key == 'Mesa') {
      final mCuotas = contrato.mesaExtraCuotas > 0 ? contrato.mesaExtraCuotas : 1;
      final cant = contrato.mesaExtraCantidad > 0 ? contrato.mesaExtraCantidad : 1;
      final unit = contrato.precioUnitarioMesaExtra;
      final cuotaPura = mCuotas > 0 && unit > 0.01
          ? double.parse((unit / mCuotas).toStringAsFixed(2))
          : unit;
      final n = mesaN ?? 1;
      final prefix = MesasExtraUtils.labelCobro(n, cant);
      return (
        cuotaPura: cuotaPura,
        totalCuotas: mCuotas,
        etiqueta: mCuotas <= 1 ? '$prefix - Entrega' : prefix,
      );
    }
    if (key == 'Sillas') {
      final sCuotas =
          contrato.sillasExtraCuotas > 0 ? contrato.sillasExtraCuotas : 1;
      return (
        cuotaPura: cuotaPuraSillas(contrato),
        totalCuotas: sCuotas,
        etiqueta: sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
      );
    }
    return null;
  }

  /// Líneas PDF desde un lote de pagos ya registrados (reimprimir recibo).
  static List<Map<String, dynamic>> conceptosPdfDesdePagosLote(
    ContratoAlumno contrato,
    List<Map<String, dynamic>> lote,
  ) {
    final enriquecidos = enriquecerPagosHistorial(contrato, lote);
    return enriquecidos.map((p) {
      final net = (p['monto'] as num?)?.toDouble() ?? 0.0;
      final gross = grossPago(p);
      final out = <String, dynamic>{
        'concepto': p['concepto_detallado'] as String? ??
            p['concepto'] as String? ??
            'Pago',
        'monto': net,
      };
      if (esMora(p)) {
        out['esMora'] = true;
      } else if (esCargoCanal(p)) {
        out['esCargoCanal'] = true;
      } else {
        out['gross'] = gross;
        out['esPlanLiquidacion'] = true;
      }
      final subConcepto = p['subtexto_concepto'] as String?;
      final subMedio = p['subtitulo_medio'] as String?;
      if (subConcepto != null && subConcepto.isNotEmpty) {
        out['subtexto'] = subConcepto;
      } else if (subMedio != null && subMedio.isNotEmpty) {
        out['subtexto'] = subMedio.replaceFirst('· ', '');
      }
      return out;
    }).toList();
  }
}
