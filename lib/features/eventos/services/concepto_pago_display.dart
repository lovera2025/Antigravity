import '../../../core/utils/ar_time.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import 'cobro_abono_acumulado.dart';
import 'cobro_masivo_conceptos_pdf.dart';
import 'mesas_extra_utils.dart';
import 'mora_concepto_rotulo.dart';
import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';
import 'mora_tracked_recovery.dart';

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

  /// De qué cuotas fue el arrastre que cobró una fila de mora, para nombrarlas
  /// en el Estado de cuenta con la misma cuenta que la reimpresión (Anexo D de
  /// la spec del 14-nov). Null si la fila no es del arrastre o si la
  /// reconstrucción no alcanza: ahí se usan los números del texto, como antes.
  ///
  /// Si la línea nombra sus cuotas, son esas, menos las que se prueba que ya
  /// estaban cobradas ([cuotasNombradasDelArrastre]). Una genérica ("de cuotas
  /// ya pagadas") toma la reconstrucción solo si cubre todo su monto.
  static List<int>? _cuotasDelArrastreDeLaFila(
    ContratoAlumno contrato,
    Map<String, dynamic> p,
    List<Map<String, dynamic>> pagos,
  ) {
    final concepto = p['concepto']?.toString() ?? '';
    if (!mencionaArrastre(concepto)) return null;
    final nombradas = cuotasNombradasDelArrastre(
      contrato: contrato,
      pago: p,
      historial: pagos,
    );
    if (nombradas.isNotEmpty) return nombradas;
    // Genérica: las más viejas del arrastre vivo hasta el monto, si alcanzan.
    final monto = (p['monto'] as num?)?.toDouble() ?? 0;
    final vivo = arrastreDeUnaLinea(contrato: contrato, pago: p, historial: pagos);
    var resto = monto;
    final cuotas = <int>[];
    for (final d in vivo) {
      if (resto <= 0.01) break;
      cuotas.add(d.numeroCuota);
      resto -= d.montoAtribuido < resto ? d.montoAtribuido : resto;
    }
    if (cuotas.isEmpty) return null;
    final sola = cuotasDeCalendarioEnConcepto(concepto).isEmpty;
    if (sola && resto > 0.01) return null;
    return cuotas;
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

    String? medioNorm(Map<String, dynamic> p) {
      final m = (p['medio_pago'] as String?)?.trim().toLowerCase() ?? '';
      if (m == 'efectivo') return 'E';
      if (m.contains('transfer')) return 'T';
      return null;
    }

    String loteClave(Map<String, dynamic> p) {
      final raw = p['fecha_pago']?.toString() ?? '';
      final f = DateTime.tryParse(raw);
      if (f == null) return raw;
      final u = f.toUtc();
      return '${u.year}-${u.month}-${u.day}T${u.hour}:${u.minute}';
    }

    bool esParMixtoPlan(Map<String, dynamic> a, Map<String, dynamic> b) {
      if (esMora(a) || esMora(b) || esCargoCanal(a) || esCargoCanal(b)) {
        return false;
      }
      final ma = medioNorm(a);
      final mb = medioNorm(b);
      if (ma == null || mb == null || ma == mb) return false;
      if (loteClave(a) != loteClave(b)) return false;
      if (esPlanBase(a) && esPlanBase(b)) return true;
      if (esPlanSillas(a) && esPlanSillas(b)) return true;
      if (esPlanMesa(a) && esPlanMesa(b)) return true;
      return false;
    }

    void appendEnriquecido(
      Map<String, dynamic> p, {
      required String conceptoDisplay,
      String? subtextoConcepto,
    }) {
      final pCpy = Map<String, dynamic>.from(p);
      pCpy['concepto_detallado'] = conceptoDisplay;
      if (subtextoConcepto != null) {
        pCpy['subtexto_concepto'] = subtextoConcepto;
      }
      // Rótulo para la ficha (diálogo + PDF de Estado de cuenta). Va en claves
      // aparte a propósito: `concepto_detallado` lo leen el motor de reimpresión
      // (`_repartirMoraMixtoSiAplica`) y `_displayMora`, que parsean la gramática
      // persistida. Si el texto de display entrara ahí, el recibo dejaría de
      // reconocer la línea.
      if (esMora(p)) {
        final ficha = MoraConceptoRotulo.rotuloFichaMora(
          conceptoDisplay,
          contrato: contrato,
          cuotasArrastre: _cuotasDelArrastreDeLaFila(contrato, p, pagos),
        );
        pCpy['concepto_ficha'] = ficha.titulo;
        if (ficha.subtexto != null) pCpy['subtexto_ficha'] = ficha.subtexto;
      }
      pCpy['subtitulo_medio'] = subtituloMedio(p);
      if ((p['descuento_porcentaje'] as num? ?? 0) > 0.01) {
        pCpy['label_descuento'] =
            '${(p['descuento_porcentaje'] as num).toStringAsFixed(0)}% OFF';
      }
      enriquecidos.add(pCpy);
    }

    for (var i = 0; i < activos.length; i++) {
      final p = activos[i];
      final next = i + 1 < activos.length ? activos[i + 1] : null;

      if (next != null && esParMixtoPlan(p, next)) {
        final g1 = grossPago(p);
        final g2 = grossPago(next);
        final combined = double.parse((g1 + g2).toStringAsFixed(2));
        String conceptoDisplay;
        String? subtexto;

        if (esPlanBase(p)) {
          final rot = rotularPlanDesdeGross(
            grossHistorico: grossBaseHist,
            grossActual: combined,
            cuotaPura: cuotaBase,
            totalCuotas: tCuotas,
            etiqueta: 'Cuota Base',
          );
          conceptoDisplay = rot.concepto;
          subtexto = rot.subtexto;
          grossBaseHist += combined;
        } else if (esPlanSillas(p)) {
          final rot = rotularPlanDesdeGross(
            grossHistorico: grossSillasHist,
            grossActual: combined,
            cuotaPura: cuotaSillas,
            totalCuotas: sCuotas,
            etiqueta:
                sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
          );
          conceptoDisplay = rot.concepto;
          subtexto = rot.subtexto;
          grossSillasHist += combined;
        } else {
          // Mesa: usar número de la primera pata.
          final conceptoOriginal = p['concepto'] as String? ?? '';
          final mesaN =
              MesasExtraUtils.numeroMesaDesdeConcepto(conceptoOriginal)
                  .clamp(1, 99);
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
              grossActual: combined,
              cuotaPura: cuotaPuraMesaN,
              totalCuotas: mCuotas,
              etiqueta: prefix,
            );
            conceptoDisplay = rot.concepto;
            subtexto = rot.subtexto;
          }
          grossMesaPorN[mesaN] = histMesa + combined;
        }

        // Mayor gross primero en la lista temporal (orden cronológico de entrada).
        appendEnriquecido(p,
            conceptoDisplay: conceptoDisplay, subtextoConcepto: subtexto);
        appendEnriquecido(next,
            conceptoDisplay: conceptoDisplay, subtextoConcepto: subtexto);
        i++; // skip next
        continue;
      }

      final gross = grossPago(p);
      String conceptoDisplay = p['concepto'] as String? ?? 'Pago';
      String? subtexto;

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
        subtexto = rot.subtexto;
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
          subtexto = rot.subtexto;
        }
        grossMesaPorN[mesaN] = histMesa + gross;
      } else if (esPlanSillas(p)) {
        final rot = rotularPlanDesdeGross(
          grossHistorico: grossSillasHist,
          grossActual: gross,
          cuotaPura: cuotaSillas,
          totalCuotas: sCuotas,
          etiqueta: sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
        );
        conceptoDisplay = rot.concepto;
        subtexto = rot.subtexto;
        grossSillasHist += gross;
      }

      appendEnriquecido(p,
          conceptoDisplay: conceptoDisplay, subtextoConcepto: subtexto);
    }

    return enriquecidos.reversed.toList();
  }

  /// Arma el registro de un cobro **mixto** agregado por clase (Base / Mesa / Sillas / Mora).
  ///
  /// Montos de efectivo/transferencia son los exactos del operador (waterfill:
  /// primero Efectivo por clase en orden Base → Mesa → Sillas → Mora).
  /// Un solo rótulo por clase (gross combinado), aplicado a ambas patas.
  static List<
      ({
        String concepto,
        double net,
        double gross,
        String medio,
        int cuotasLiquidadas,
        String? lineKind,
        String? subtexto,
      })> armarRegistroMixtoAgregado({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> previewLineas,
    required double parteEfectivo,
    required double parteTransferencia,
    required Map<String, double> historicoGrossPorClave,
    bool Function(Map<String, dynamic> c)? esLineaCargoCanal,
    bool Function(Map<String, dynamic> c)? esLineaInteresMora,
  }) {
    bool isCargo(Map<String, dynamic> c) {
      if (esLineaCargoCanal != null) return esLineaCargoCanal(c);
      return c['lineKind'] == kLineKindCargoCanal;
    }

    bool isMora(Map<String, dynamic> c) {
      if (esLineaInteresMora != null) return esLineaInteresMora(c);
      return c['lineKind'] == kLineKindInteresMora;
    }

    final grupos = <String, _MixtoClaseAcum>{};
    final ordenClaves = <String>[];

    void addToGroup(String key, Map<String, dynamic> conc) {
      final net = (conc['monto'] as num).toDouble();
      final gross = (conc['gross'] as num?)?.toDouble() ?? net;
      final existing = grupos[key];
      if (existing == null) {
        ordenClaves.add(key);
        grupos[key] = _MixtoClaseAcum(
          key: key,
          net: net,
          gross: gross,
          lineKind: isMora(conc) ? kLineKindInteresMora : null,
          conceptoMora: isMora(conc)
              ? (conc['concepto'] as String? ?? 'Interés mora')
              : null,
          previewSample: conc,
          cuotasSum: ((conc['cuotas'] as num?)?.toInt() ?? 0),
        );
      } else {
        existing.net =
            double.parse((existing.net + net).toStringAsFixed(2));
        existing.gross =
            double.parse((existing.gross + gross).toStringAsFixed(2));
        existing.cuotasSum += ((conc['cuotas'] as num?)?.toInt() ?? 0);
      }
    }

    for (final conc in previewLineas) {
      if (isCargo(conc)) continue;
      if (isMora(conc)) {
        addToGroup('Mora', conc);
        continue;
      }
      addToGroup(_claseKeyDesdePreview(conc), conc);
    }

    // Orden determinístico: Base, Mesa*, Sillas, Mora.
    int rank(String k) {
      if (k == 'Base') return 0;
      if (k.startsWith('Mesa')) return 1;
      if (k == 'Sillas') return 2;
      if (k == 'Mora') return 3;
      return 9;
    }

    ordenClaves.sort((a, b) {
      final ra = rank(a);
      final rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return a.compareTo(b);
    });

    var remE = double.parse(parteEfectivo.toStringAsFixed(2));
    var remT = double.parse(parteTransferencia.toStringAsFixed(2));
    final histLocal = Map<String, double>.from(historicoGrossPorClave);
    final out = <
        ({
          String concepto,
          double net,
          double gross,
          String medio,
          int cuotasLiquidadas,
          String? lineKind,
          String? subtexto,
        })>[];

    for (var i = 0; i < ordenClaves.length; i++) {
      final key = ordenClaves[i];
      final g = grupos[key]!;
      if (g.net <= 0.004) continue;

      final isLast = i == ordenClaves.length - 1;
      double mE;
      double mT;
      if (isLast) {
        // Cierra exacto con lo que queda (evita deriva de centavos).
        mE = remE;
        mT = remT;
        // Si la clase es menor que remE+remT por cargo ya separado, clamp a g.net
        final sum = double.parse((mE + mT).toStringAsFixed(2));
        if ((sum - g.net).abs() > 0.02) {
          mE = remE >= g.net ? g.net : remE;
          mT = double.parse((g.net - mE).toStringAsFixed(2));
        }
      } else {
        mE = remE >= g.net
            ? g.net
            : (remE > 0.004 ? remE : 0.0);
        mE = double.parse(mE.toStringAsFixed(2));
        if (mE > g.net) mE = g.net;
        mT = double.parse((g.net - mE).toStringAsFixed(2));
      }
      remE = double.parse((remE - mE).toStringAsFixed(2));
      remT = double.parse((remT - mT).toStringAsFixed(2));
      if (remE < 0) remE = 0;
      if (remT < 0) remT = 0;

      double gE = 0;
      double gT = 0;
      if (g.net > 0.01) {
        gE = mE > 0.004
            ? double.parse((g.gross * (mE / g.net)).toStringAsFixed(2))
            : 0;
        gT = double.parse((g.gross - gE).toStringAsFixed(2));
      }

      late final String concepto;
      late final int cuotasLiq;
      String? subtexto;
      if (key == 'Mora') {
        concepto = g.conceptoMora ?? 'Interés mora';
        cuotasLiq = 0;
      } else {
        final hist = key.startsWith('Mesa:')
            ? (histLocal[key] ?? histLocal['Mesa'] ?? 0.0)
            : (histLocal[key] ?? 0.0);
        final params = _planParamsDesdePreview(contrato, g.previewSample);
        if (params == null) {
          concepto = g.previewSample['concepto'] as String? ?? 'Pago';
          cuotasLiq = g.cuotasSum;
        } else {
          final rot = rotularPlanDesdeGross(
            grossHistorico: hist,
            grossActual: g.gross,
            cuotaPura: params.cuotaPura,
            totalCuotas: params.totalCuotas,
            etiqueta: params.etiqueta,
          );
          concepto = rot.concepto;
          cuotasLiq = rot.cuotasLiquidadas;
          subtexto = rot.subtexto;
        }
        histLocal[key] = double.parse(
          ((histLocal[key] ?? 0) + g.gross).toStringAsFixed(2),
        );
        if (key.startsWith('Mesa:')) {
          histLocal['Mesa'] = double.parse(
            ((histLocal['Mesa'] ?? 0) + g.gross).toStringAsFixed(2),
          );
        }
      }

      final partes = <({double net, double gross, String medio})>[
        if (mT > 0.004) (net: mT, gross: gT, medio: 'Transferencia'),
        if (mE > 0.004) (net: mE, gross: gE, medio: 'Efectivo'),
      ]..sort((a, b) => b.gross.compareTo(a.gross));

      var cuotasAsignadas = false;
      for (final p in partes) {
        final cq = !cuotasAsignadas ? cuotasLiq : 0;
        cuotasAsignadas = true;
        out.add((
          concepto: concepto,
          net: p.net,
          gross: p.gross,
          medio: p.medio,
          cuotasLiquidadas: cq,
          lineKind: g.lineKind,
          subtexto: subtexto,
        ));
      }
    }

    return out;
  }

  /// Rotula partes de un cobro mixto al registrar (legacy: split proporcional por línea).
  /// Preferir [armarRegistroMixtoAgregado] para cobros nuevos.
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

    // Nuevo comportamiento prolijo: un solo rótulo con gross combinado.
    final rot = rotularPlanDesdeGross(
      grossHistorico: grossHistoricoClase,
      grossActual: grossLinea,
      cuotaPura: params.cuotaPura,
      totalCuotas: params.totalCuotas,
      etiqueta: params.etiqueta,
    );
    final partes = <({double gross, double net, String medio})>[
      if (gT > 0.004) (gross: gT, net: mT, medio: 'Transferencia'),
      if (gE > 0.004) (gross: gE, net: mE, medio: 'Efectivo'),
    ]..sort((a, b) => b.gross.compareTo(a.gross));

    var assigned = false;
    return partes.map((part) {
      final cq = !assigned ? rot.cuotasLiquidadas : 0;
      assigned = true;
      return (
        gross: part.gross,
        net: part.net,
        medio: part.medio,
        rotulo: RotuloPlanPago(
          concepto: rot.concepto,
          cuotasLiquidadas: cq,
          subtexto: rot.subtexto,
        ),
      );
    }).toList();
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
  ///
  /// Si [historialCompleto] está disponible:
  /// - se usa para rotular cuotas con el gross previo (ej. `Cuota Base (3/9)`);
  /// - los conceptos de mora mixtos se re-parten (Opción B).
  static List<Map<String, dynamic>> conceptosPdfDesdePagosLote(
    ContratoAlumno contrato,
    List<Map<String, dynamic>> lote, {
    List<Map<String, dynamic>>? historialCompleto,
  }) {
    final idsLote = lote
        .map((p) => p['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    // Con historial completo: enriquecer todo (gross correcto) y quedarse
    // solo con las filas del lote del recibo.
    final List<Map<String, dynamic>> enriquecidos;
    if (historialCompleto != null &&
        historialCompleto.isNotEmpty &&
        idsLote.isNotEmpty) {
      final todos = enriquecerPagosHistorial(contrato, historialCompleto);
      enriquecidos =
          todos.where((p) => idsLote.contains(p['id']?.toString())).toList();
    } else {
      enriquecidos = enriquecerPagosHistorial(contrato, lote);
    }

    final out = <Map<String, dynamic>>[];
    for (final p in _juntarMoraPartida(enriquecidos)) {
      if (esMora(p)) {
        final repartido = _repartirMoraMixtoSiAplica(
          contrato: contrato,
          pago: p,
          historialCompleto: historialCompleto,
        );
        if (repartido != null && repartido.isNotEmpty) {
          out.addAll(repartido);
          continue;
        }
      }

      final net = (p['monto'] as num?)?.toDouble() ?? 0.0;
      final gross = grossPago(p);
      final line = <String, dynamic>{
        'concepto': p['concepto_detallado'] as String? ??
            p['concepto'] as String? ??
            'Pago',
        'monto': net,
      };
      if (esMora(p)) {
        line['esMora'] = true;
        anexarMetadatosMoraDisplay(line);
        _confirmarParcialDeUnaCuota(line, contrato, p, historialCompleto);
      } else if (esCargoCanal(p)) {
        line['esCargoCanal'] = true;
      } else {
        line['gross'] = gross;
        line['esPlanLiquidacion'] = true;
      }
      final subConcepto = p['subtexto_concepto'] as String?;
      final subMedio = p['subtitulo_medio'] as String?;
      if (line['montoPleno'] != null) {
        // Una mora cobrada a medias ya dice de cuánto era.
      } else if (subConcepto != null && subConcepto.isNotEmpty) {
        line['subtexto'] = subConcepto;
      } else if (subMedio != null && subMedio.isNotEmpty) {
        line['subtexto'] = subMedio.replaceFirst('· ', '');
      }
      out.add(line);
    }
    _ordenarLineasReciboPorCuota(out);
    return out;
  }

  static final _reCuotaRangoRecibo = RegExp(r'\((\d+)[-–](\d+)/(\d+)\)');
  static final _reCuotaSimpleRecibo = RegExp(r'\((\d+)/(\d+)\)');
  static final _reCuotaEnTextoRecibo = RegExp(
    r'cuota\s+(\d+)',
    caseSensitive: false,
  );

  /// Clave de orden del recibo: plan de la cuota más vieja a la más nueva.
  /// El arrastre y el cargo van después; el historial de la ficha no usa esto.
  static int _claveOrdenReciboPdf(Map<String, dynamic> c) {
    if (c['esCargoCanal'] == true) return 500000;
    final texto = (c['concepto'] as String? ?? '').trim();
    final folded = texto.toLowerCase();
    final esMora = c['esMora'] == true;
    final nMeta = (c['cuotaBaseDesde'] as num?)?.toInt() ??
        (c['numeroCuota'] as num?)?.toInt() ??
        (c['cuotaPrevia'] as num?)?.toInt();
    final nTexto = () {
      final rango = _reCuotaRangoRecibo.firstMatch(texto);
      if (rango != null) return int.tryParse(rango.group(1)!);
      final simple = _reCuotaSimpleRecibo.firstMatch(texto);
      if (simple != null) return int.tryParse(simple.group(1)!);
      return int.tryParse(
        _reCuotaEnTextoRecibo.firstMatch(folded)?.group(1) ?? '',
      );
    }();
    final n = nMeta ?? nTexto ?? 0;
    if (esMora) {
      final arrastre = c['cuotaPrevia'] != null ||
          c['arrastreGenerico'] == true ||
          folded.contains('mora pendiente') ||
          folded.contains('cuotas ya pagadas');
      // El arrastre sin cuota reconstruible va al final de su bloque: puesto
      // antes de una cuota identificada se lee como si fuera más viejo, y el
      // orden del recibo es justamente de la más vieja a la más nueva.
      if (arrastre && n <= 0) return 409999;
      return (arrastre ? 400000 : 300000) + n;
    }
    if (folded.contains('silla')) return 200000 + n;
    if (folded.contains('mesa')) return 100000 + n;
    return n;
  }

  static void _ordenarLineasReciboPorCuota(List<Map<String, dynamic>> lineas) {
    final indexed = [
      for (var i = 0; i < lineas.length; i++) (i, lineas[i]),
    ];
    indexed.sort((a, b) {
      final c = _claveOrdenReciboPdf(a.$2).compareTo(_claveOrdenReciboPdf(b.$2));
      if (c != 0) return c;
      return a.$1.compareTo(b.$1);
    });
    for (var i = 0; i < indexed.length; i++) {
      lineas[i] = indexed[i].$2;
    }
  }

  static bool _esConceptoMoraMixtoOPendiente(String concepto) {
    final cl = foldDiacriticosLatin(concepto.toLowerCase());
    if (cl.contains('+ mora pendiente')) return true;
    if (cl.contains('+ mora cuotas ya pagadas')) return true;
    if (cl.contains('+ remanente')) return true;
    if (cl.contains('mora pendiente cuota')) return true;
    if (cl.contains('mora de cuotas ya pagadas')) return true;
    if (cl.contains('mora pendiente de cuotas')) return true;
    return false;
  }

  static String? _mesLabelDesdeConceptoMora(String concepto) {
    final m = RegExp(
      r'\(\s*(?:vto\s*)?([^)]+)\)',
      caseSensitive: false,
    ).firstMatch(concepto);
    if (m == null) return null;
    return m.group(1)!.trim();
  }

  /// Último recurso para saber de qué cuota es un arrastre: el propio concepto
  /// persistido, que lo dice ("Mora pendiente cuota 3").
  ///
  /// `MoraTrackedOrigen.inferir` reconstruye el origen replayando el historial y
  /// a veces no llega (contrato sin Reg, historial incompleto). Ahí el recibo
  /// caía en el genérico "Mora pendiente de cuotas ya pagadas" mientras la ficha,
  /// leyendo el mismo texto, nombraba la cuota 3: dos papeles, un solo cobro.
  ///
  /// Solo actúa si el concepto nombra **una** cuota: ahí todo el monto es de esa
  /// cuota y no se inventa nada. Con varias, repartir sería fabricar un desglose
  /// que nadie calculó, así que se deja el rótulo genérico.
  static List<MoraPendientePreviaDetalle> _detalleDesdeElConcepto(
    String concepto,
    double monto,
    List<MoraPendientePreviaDetalle> inferido,
  ) {
    final cubierto = inferido.fold<double>(0, (s, d) => s + d.montoAtribuido);
    if (cubierto > 0.01) return inferido;

    final nums = MoraConceptoRotulo.numerosCuotaPendienteDesdeConcepto(concepto);
    if (nums.length != 1) return inferido;

    return [
      MoraPendientePreviaDetalle(
        numeroCuota: nums.first,
        mesLabel: '',
        montoAtribuido: monto,
      ),
    ];
  }

  /// Desde la v4.9 (21-ago-2026) una línea mixta que no alcanza para todo
  /// paga primero el arrastre; antes, el calendario. Es la misma regla que
  /// `MoraTrackedOrigen.inferir` usa para la ficha.
  static const _desdeArrastrePrimero = '2026-08-21';

  /// El inicio del día (en Argentina) del cobro de [pago]: lo de antes es el
  /// historial que se usa para saber de qué cuotas era su mora.
  static DateTime? _inicioDelDiaDelCobro(Map<String, dynamic> pago) {
    final fechaRaw = pago['fecha_pago']?.toString();
    final fecha = fechaRaw != null ? DateTime.tryParse(fechaRaw) : null;
    if (fecha == null) return null;
    final ar = ArTime.toAr(fecha);
    return DateTime.utc(ar.year, ar.month, ar.day, 3);
  }

  /// Todo el arrastre vivo antes del día del cobro de [pago], reconstruido
  /// desde el historial: una entrada por cuota, con lo que se debía de ella
  /// (`montoAtribuido`), de la más vieja a la más nueva.
  static List<MoraPendientePreviaDetalle> _arrastreVivoAntesDe(
    ContratoAlumno contrato,
    Map<String, dynamic> pago,
    List<Map<String, dynamic>> historial,
  ) {
    return MoraTrackedOrigen.inferir(
      // Sin la exención de hoy, y con saldo aunque la familia ya haya
      // terminado de pagar: con saldo 0 la cuenta de la mora no devuelve nada
      // y el cobro quedaba sin sus cuotas (lo encontró la revisión del 14-nov).
      contratoBase: contrato.copyWith(
        moraExentaHasta: null,
        moraFechaReferencia: null,
        saldoDeudor: contrato.saldoDeudor > 0.01
            ? contrato.saldoDeudor
            : contrato.montoTotalPactado,
      ),
      pagos: historial,
      trackedMonto: 1e12,
      antesDe: _inicioDelDiaDelCobro(pago),
      excluirPagoId: pago['id']?.toString(),
    );
  }

  /// De qué cuotas ya pagadas es el arrastre que cobró una línea de mora, y
  /// cuánto se debía de cada una antes de ese cobro (`montoAtribuido`: lo
  /// pleno, sin recortar a lo que se cobró; el recorte lo hace quien arma el
  /// papel, y así sabe si una cuota quedó a medias).
  ///
  /// Una sola cuenta para el Estado de cuenta y para la reimpresión del recibo
  /// (Anexo D de la spec del 14-nov).
  ///
  /// **Las cuotas son las que la línea guardada nombra** (ver
  /// [cuotasNombradasDelArrastre]): el texto lo escribió la app en el momento
  /// del cobro, sabiendo los perdones y las exenciones, y la reconstrucción no.
  /// Solo vienen las que la reconstrucción respalda; las demás las nombra el
  /// papel sin inventar cuánto fue de cada una.
  ///
  /// Una línea genérica, que no nombra cuotas ("Mora pendiente de cuotas ya
  /// pagadas"), toma todo el arrastre vivo, como siempre. Ordenadas por cuota.
  /// Vacía si no hay historial.
  static List<MoraPendientePreviaDetalle> arrastreDeUnaLinea({
    required ContratoAlumno contrato,
    required Map<String, dynamic> pago,
    required List<Map<String, dynamic>> historial,
  }) {
    if (historial.isEmpty) return const [];
    final vivo = _arrastreVivoAntesDe(contrato, pago, historial);
    final nombres = _nombresConVivo(contrato, pago, historial, vivo);
    if (nombres == null) return vivo;
    return [
      for (final d in vivo)
        if (nombres.contains(d.numeroCuota)) d,
    ];
  }

  /// Las cuotas del arrastre que nombra una línea guardada, menos las que se
  /// prueba que ya estaban cobradas: otra línea de un día anterior las nombró
  /// y la reconstrucción dice que ya no se debían (el cobro reclamado el
  /// 14-nov nombraba la cuota 2, cobrada el día antes). Si no queda ninguna, o
  /// la ficha tiene un perdón, las guardadas.
  static List<int> _nombresDelArrastre({
    required List<int> guardadas,
    required Set<int> vivas,
    required Set<int> yaCobradas,
    required bool conPerdon,
  }) {
    // Con un perdón en la ficha la reconstrucción no sabe qué se perdonó ni
    // cuándo: no se saca ninguna (el comparador mostró una así el 14-nov).
    if (conPerdon) return guardadas;
    final nombres = [
      for (final n in guardadas)
        if (vivas.contains(n) || !yaCobradas.contains(n)) n,
    ];
    return nombres.isEmpty ? guardadas : nombres;
  }

  /// Null si la línea no nombra cuotas (la genérica).
  static List<int>? _nombresConVivo(
    ContratoAlumno contrato,
    Map<String, dynamic> pago,
    List<Map<String, dynamic>> historial,
    List<MoraPendientePreviaDetalle> vivo,
  ) {
    final concepto = (pago['concepto_detallado'] as String?) ??
        (pago['concepto'] as String?) ??
        '';
    final guardadas =
        MoraConceptoRotulo.numerosCuotaPendienteDesdeConcepto(concepto);
    if (guardadas.isEmpty) return null;
    return _nombresDelArrastre(
      guardadas: guardadas,
      vivas: {
        for (final d in vivo)
          if (d.montoAtribuido > 0.01) d.numeroCuota,
      },
      yaCobradas: _arrastreNombradoAntes(
        historial,
        _inicioDelDiaDelCobro(pago),
      ),
      conPerdon: MoraTrackedRecovery.tienePerdon(
        contrato: contrato,
        pagos: historial,
      ),
    )..sort();
  }

  /// Las cuotas que el Estado de cuenta y el recibo reimpreso nombran para el
  /// arrastre de una línea (ver [arrastreDeUnaLinea]). Vacía si la línea no
  /// nombra cuotas (la genérica) o no hay historial.
  static List<int> cuotasNombradasDelArrastre({
    required ContratoAlumno contrato,
    required Map<String, dynamic> pago,
    required List<Map<String, dynamic>> historial,
  }) {
    if (historial.isEmpty) return const [];
    final vivo = _arrastreVivoAntesDe(contrato, pago, historial);
    return _nombresConVivo(contrato, pago, historial, vivo) ?? const [];
  }

  /// Las cuotas que alguna línea de mora de un día anterior a [antesDe]
  /// nombró como arrastre ("… mora pendiente cuota 2").
  static Set<int> _arrastreNombradoAntes(
    List<Map<String, dynamic>> historial,
    DateTime? antesDe,
  ) {
    final out = <int>{};
    if (antesDe == null) return out;
    for (final p in historial) {
      if (esAnulado(p) || !esMora(p)) continue;
      final f = DateTime.tryParse(p['fecha_pago']?.toString() ?? '');
      if (f == null || !f.isBefore(antesDe)) continue;
      out.addAll(
        MoraConceptoRotulo.numerosCuotaPendienteDesdeConcepto(
          p['concepto']?.toString() ?? '',
        ),
      );
    }
    return out;
  }

  static List<Map<String, dynamic>>? _repartirMoraMixtoSiAplica({
    required ContratoAlumno contrato,
    required Map<String, dynamic> pago,
    List<Map<String, dynamic>>? historialCompleto,
  }) {
    final concepto = (pago['concepto_detallado'] as String?) ??
        (pago['concepto'] as String?) ??
        '';
    final esArrastre = _esConceptoMoraMixtoOPendiente(concepto);
    final calNums = cuotasDeCalendarioEnConcepto(concepto);
    // Una línea de calendario de una sola cuota sigue el camino de siempre.
    if (!esArrastre && calNums.length < 2) return null;

    final monto = double.parse(
      ((pago['monto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
    );
    if (monto <= 0.01) return null;

    final fechaRaw = pago['fecha_pago']?.toString();
    final fecha = fechaRaw != null ? DateTime.tryParse(fechaRaw) : null;
    final fechaAr = fecha != null ? ArTime.toAr(fecha) : null;

    final hist = historialCompleto ?? const <Map<String, dynamic>>[];
    final arrastrePrimero = fechaAr == null ||
        _claveDiaAr(fechaAr).compareTo(_desdeArrastrePrimero) >= 0;

    // Lo que se debía ese día por cada cuota del calendario que nombra (sin la
    // exención de hoy; con saldo aunque ya haya terminado de pagar).
    final desg = <Map<String, dynamic>>[];
    if (calNums.isNotEmpty && fechaAr != null) {
      final orden = calNums.toSet().toList()..sort();
      final pre = contrato.copyWith(
        moraExentaHasta: null,
        moraFechaReferencia: null,
        cuotasPagadas: orden.first - 1,
        saldoDeudor: contrato.saldoDeudor > 0.01
            ? contrato.saldoDeudor
            : contrato.montoTotalPactado,
      );
      final bruto = MoraCuotaCalculator.calcularDesglose(pre, fechaAr);
      for (final n in orden) {
        final d = bruto.where((x) => x.numeroCuota == n).toList();
        if (d.isEmpty || d.first.interesBruto <= 0.01) continue;
        desg.add({
          'numeroCuota': d.first.numeroCuota,
          'mesLabel': d.first.mesLabel,
          'monto': d.first.interesBruto,
          'diasMora': d.first.diasMora,
        });
      }
    }
    final sumCal = desg.fold<double>(
      0,
      (s, d) => s + ((d['monto'] as num?)?.toDouble() ?? 0),
    );

    // Calendario puro de varias cuotas ("Interés mora cuotas 3, 4"). Se reparte
    // solo si lo que se debía ese día da justo lo cobrado: si no, la cuenta de
    // aquel día tenía un crédito o una exención que la reimpresión no ve, y
    // repartir marcaría "(parcial)" y sacaría una cuota del papel (lo encontró
    // la revisión del 14-nov). Ahí va un renglón que las nombra a todas.
    if (!esArrastre) {
      if (desg.length == calNums.toSet().length && (sumCal - monto).abs() <= 0.01) {
        return MoraConceptoRotulo.lineasPdfDesdePreviewMora(
          montoTotal: monto,
          moraDesglose: desg,
          moraPendientePrevias: 0,
          detallePendiente: const [],
          conceptoFallback: concepto,
        );
      }
      return [_renglonDeVariasCuotas(calNums, monto, arrastre: false)];
    }

    final vivo = hist.isEmpty
        ? const <MoraPendientePreviaDetalle>[]
        : arrastreDeUnaLinea(contrato: contrato, pago: pago, historial: hist);
    final respaldado = vivo.fold<double>(0, (s, d) => s + d.montoAtribuido);
    final nombradas = cuotasNombradasDelArrastre(
      contrato: contrato,
      pago: pago,
      historial: hist,
    );

    // Mixta cuyo calendario no se pudo rearmar: el arrastre primero y el resto
    // al calendario, con el mes que dice el texto (el camino de siempre).
    if (desg.isEmpty && calNums.isNotEmpty && fechaAr != null) {
      final nCal = calNums.first;
      final mes = _mesLabelDesdeConceptoMora(concepto) ?? '';
      final calEst = double.parse(
        (monto - (respaldado < monto ? respaldado : monto))
            .clamp(0.0, double.infinity)
            .toStringAsFixed(2),
      );
      if (calEst > 0.01) {
        desg.add({
          'numeroCuota': nCal,
          'mesLabel': mes.isNotEmpty ? mes : 'cuota $nCal',
          'monto': calEst,
        });
      }
    }

    // Solo pendiente (sin parte calendario en el texto).
    if (desg.isEmpty) {
      final detalle = _detalleDesdeElConcepto(concepto, monto, vivo);
      return _conLasCuotasNombradas(
        MoraConceptoRotulo.lineasPdfDesdePreviewMora(
          montoTotal: monto,
          moraDesglose: const [],
          moraPendientePrevias: monto,
          detallePendiente: detalle,
          conceptoFallback: concepto,
        ),
        nombradas,
      );
    }

    // Mixta: cuánto de la línea fue arrastre.
    final calTope = desg.fold<double>(
      0,
      (s, d) => s + ((d['monto'] as num?)?.toDouble() ?? 0),
    );
    double pendiente;
    if (arrastrePrimero) {
      // Lo que la reconstrucción respalda; el resto es calendario.
      pendiente = respaldado < monto ? respaldado : monto;
      // Lo que no entra en el calendario no se puede perder: es arrastre.
      final resto = monto - pendiente;
      if (resto > calTope + 0.01) pendiente += resto - calTope;
    } else {
      pendiente = monto - (calTope < monto ? calTope : monto);
    }
    pendiente = double.parse(
      pendiente.clamp(0.0, double.infinity).toStringAsFixed(2),
    );

    final lineas = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
      montoTotal: monto,
      moraDesglose: desg,
      moraPendientePrevias: pendiente,
      detallePendiente: pendiente > 0.01 ? vivo : const [],
      conceptoFallback: concepto,
    );
    return _conLasCuotasNombradas(
      _parcialesConfirmados(lineas, contrato, pago, hist),
      nombradas,
    );
  }

  /// Las filas de mora de un mismo cobro con el mismo concepto, juntas en una
  /// (revisión final de la 6.9.0). En un Mixto la mora puede quedar partida en
  /// una fila de efectivo y otra de transferencia con el mismo concepto:
  /// repartida cada una por su lado, las dos tomaban la misma cuota del arrastre
  /// (el papel decía el doble de lo que se debía) y la del calendario no salía.
  /// La ficha ya las reparte juntas (`MoraTrackedOrigen._repartirMoraDelLote`).
  static List<Map<String, dynamic>> _juntarMoraPartida(
    List<Map<String, dynamic>> filas,
  ) {
    double plata(Object? v) => (v as num?)?.toDouble() ?? 0;
    final out = <Map<String, dynamic>>[];
    final dondeVa = <String, int>{};
    for (final p in filas) {
      final concepto = ((p['concepto_detallado'] as String?) ??
              (p['concepto'] as String?) ??
              '')
          .trim();
      if (!esMora(p) || esAnulado(p) || concepto.isEmpty) {
        out.add(p);
        continue;
      }
      final i = dondeVa[concepto];
      if (i == null) {
        dondeVa[concepto] = out.length;
        out.add(p);
        continue;
      }
      final junta = Map<String, dynamic>.from(out[i]);
      final grossJunta = plata(junta['monto_gross'] ?? junta['monto']);
      final grossOtra = plata(p['monto_gross'] ?? p['monto']);
      junta['monto'] = plata(junta['monto']) + plata(p['monto']);
      junta['monto_gross'] = grossJunta + grossOtra;
      // Ya no es de un solo medio.
      junta.remove('subtitulo_medio');
      out[i] = junta;
    }
    return out;
  }

  /// Lo que le quedó de mora a cada cuota pagada el día del cobro [pago], según
  /// la reconstrucción con los pagos hasta el fin de ese día. Solo las cuotas
  /// cuyo pago se completó ese día; vacío si no se puede saber.
  static Map<int, double> _moraQueQuedoElDia(
    ContratoAlumno contrato,
    Map<String, dynamic> pago,
    List<Map<String, dynamic>> historial,
  ) {
    final inicio = _inicioDelDiaDelCobro(pago);
    final quedo = <int, double>{};
    if (inicio == null || historial.isEmpty) return quedo;
    final despues = MoraTrackedOrigen.inferir(
      contratoBase: contrato.copyWith(
        moraExentaHasta: null,
        moraFechaReferencia: null,
        saldoDeudor: contrato.saldoDeudor > 0.01
            ? contrato.saldoDeudor
            : contrato.montoTotalPactado,
      ),
      pagos: historial,
      trackedMonto: 1e12,
      antesDe: inicio.add(const Duration(days: 1)),
    );
    final dia = ArTime.toAr(inicio);
    for (final d in despues) {
      final f = d.fechaPagoCuota;
      if (f != null && f.year == dia.year && f.month == dia.month && f.day == dia.day) {
        quedo[d.numeroCuota] = d.montoAtribuido;
      }
    }
    return quedo;
  }

  /// Una línea de calendario de una sola cuota ("Interés mora cuota 4 (vto …)")
  /// se guarda sin "(parcial)" aunque ese día se haya cobrado solo una parte de
  /// su mora (revisión final de la 6.9.0): reimpresa, la tabla decía "Debía
  /// $5.000 · Quedó $0" cuando se debían $8.000 y quedaron $3.000. Como
  /// [_parcialesConfirmados] con las mixtas: si la reconstrucción confirma que a
  /// la cuota le quedó mora después de ese día, lo que se debía es lo cobrado más
  /// lo que quedó, y la línea va "(parcial)".
  static void _confirmarParcialDeUnaCuota(
    Map<String, dynamic> line,
    ContratoAlumno contrato,
    Map<String, dynamic> pago,
    List<Map<String, dynamic>>? historial,
  ) {
    if (historial == null || historial.isEmpty) return;
    if (line['cuotaPrevia'] != null || line['montoPleno'] != null) return;
    final n = (line['numeroCuota'] as num?)?.toInt();
    if (n == null) return;
    final concepto = line['concepto'] as String? ?? '';
    if (_esConceptoMoraMixtoOPendiente(concepto) ||
        cuotasDeCalendarioEnConcepto(concepto).length != 1) {
      return;
    }
    final resta = _moraQueQuedoElDia(contrato, pago, historial)[n];
    if (resta == null || resta <= 0.01) return;
    final m = (line['monto'] as num?)?.toDouble() ?? 0;
    final pleno = double.parse((m + resta).toStringAsFixed(2));
    line['montoPleno'] = pleno;
    line['subtexto'] = MoraConceptoRotulo.subtextoParcialMora(pleno);
    if (!concepto.contains(MoraConceptoRotulo.sufijoParcial)) {
      line['concepto'] = '$concepto${MoraConceptoRotulo.sufijoParcial}';
    }
  }

  /// Una línea de mora que nombra varias cuotas, con la suma y sin repartir:
  /// la reimpresión no pudo decir cuánto fue de cada una.
  static Map<String, dynamic> _renglonDeVariasCuotas(
    List<int> cuotas,
    double monto, {
    required bool arrastre,
  }) {
    final orden = cuotas.toSet().toList()..sort();
    final lista = orden.length == 1
        ? 'cuota ${orden.first}'
        : 'cuotas ${orden.sublist(0, orden.length - 1).join(', ')} y ${orden.last}';
    return {
      'concepto': arrastre ? 'Mora pendiente $lista' : 'Interés mora $lista',
      'monto': double.parse(monto.toStringAsFixed(2)),
      'esMora': true,
      if (arrastre) 'cuotasPrevias': orden else 'cuotasDeLaLinea': orden,
    };
  }

  /// Una cuota del calendario que el reparto marca "(parcial)" lo es solo si la
  /// reconstrucción confirma que, después de ese día, le quedó mora por pagar.
  /// Si lo confirma, lo que se debía de ella es lo cobrado más lo que quedó
  /// (así la nota dice cuánto quedó de verdad); si no, la mora de ese día se
  /// calculó sin un crédito o una exención que la reimpresión no ve, y la
  /// línea sale entera, sin "(parcial)".
  static List<Map<String, dynamic>> _parcialesConfirmados(
    List<Map<String, dynamic>> lineas,
    ContratoAlumno contrato,
    Map<String, dynamic> pago,
    List<Map<String, dynamic>> historial,
  ) {
    final parciales = lineas.where(
      (l) =>
          l['numeroCuota'] != null &&
          l['cuotaPrevia'] == null &&
          l['montoPleno'] != null,
    );
    if (parciales.isEmpty) return lineas;
    final quedo = _moraQueQuedoElDia(contrato, pago, historial);
    return [
      for (final l in lineas)
        if (!parciales.contains(l))
          l
        else
          () {
            final n = (l['numeroCuota'] as num).toInt();
            final m = (l['monto'] as num).toDouble();
            final c = Map<String, dynamic>.from(l);
            final resta = quedo[n];
            if (resta != null && resta > 0.01) {
              final pleno = double.parse((m + resta).toStringAsFixed(2));
              c['montoPleno'] = pleno;
              c['subtexto'] = MoraConceptoRotulo.subtextoParcialMora(pleno);
            } else {
              c.remove('montoPleno');
              c.remove('subtexto');
              c['concepto'] = (c['concepto'] as String)
                  .replaceAll(MoraConceptoRotulo.sufijoParcial, '');
            }
            return c;
          }(),
    ];
  }

  /// Si las líneas del arrastre no nombran exactamente las cuotas que nombra
  /// el Estado de cuenta ([nombradas]), las junta en un solo renglón que las
  /// nombra a todas ("Mora pendiente cuotas 2, 3 y 4"), con la suma: la
  /// reconstrucción no alcanzó para decir cuánto fue de cada una, y repartirlo
  /// a ojo sería inventar. Así el papel y la pantalla nombran lo mismo.
  static List<Map<String, dynamic>> _conLasCuotasNombradas(
    List<Map<String, dynamic>> lineas,
    List<int> nombradas,
  ) {
    if (nombradas.isEmpty) return lineas;
    bool esArrastre(Map<String, dynamic> l) =>
        l['cuotaPrevia'] != null || l['arrastreGenerico'] == true;
    final arrastre = lineas.where(esArrastre).toList();
    if (arrastre.isEmpty) return lineas;
    final reimpresas = {
      for (final l in arrastre)
        if (l['cuotaPrevia'] != null) (l['cuotaPrevia'] as num).toInt(),
    };
    final iguales = arrastre.every((l) => l['cuotaPrevia'] != null) &&
        reimpresas.length == nombradas.length &&
        nombradas.every(reimpresas.contains);
    if (iguales) return lineas;
    final suma = arrastre.fold<double>(
      0,
      (s, l) => s + ((l['monto'] as num?)?.toDouble() ?? 0),
    );
    return [
      ...lineas.where((l) => !esArrastre(l)),
      _renglonDeVariasCuotas(nombradas, suma, arrastre: true),
    ];
  }

  static String _claveDiaAr(DateTime ar) =>
      '${ar.year}-${ar.month.toString().padLeft(2, '0')}-'
      '${ar.day.toString().padLeft(2, '0')}';
}

class _MixtoClaseAcum {
  final String key;
  double net;
  double gross;
  final String? lineKind;
  final String? conceptoMora;
  final Map<String, dynamic> previewSample;
  int cuotasSum;

  _MixtoClaseAcum({
    required this.key,
    required this.net,
    required this.gross,
    required this.lineKind,
    required this.conceptoMora,
    required this.previewSample,
    required this.cuotasSum,
  });
}
