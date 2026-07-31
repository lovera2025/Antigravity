import '../../../models/mesa_extra_item.dart';
import '../../common/utils/currency_extensions.dart';
import 'mesas_extra_utils.dart';
import 'mora_concepto_rotulo.dart';
import 'mora_cuota_calculator.dart';

bool esConceptoPlanLiquidacionPdf(Map<String, dynamic> c) =>
    c['esPlanLiquidacion'] == true;

/// Línea de concepto del recibo/resumen que corresponde a mesa(s) extra.
bool esLineaMesaConceptoPdf(Map<String, dynamic> c) {
  if (c['esMora'] == true || c['esCargoCanal'] == true) return false;
  final t = (c['concepto'] as String? ?? '').toLowerCase();
  return t.contains('mesa extra') || t.contains('mesas extra');
}

Map<String, dynamic> _enriquecerMesaNConceptoPdf(Map<String, dynamic> c) {
  if (c['mesaN'] != null) return c;
  final n = MesasExtraUtils.mesaNumeroDesdeTexto(c['concepto'] as String?);
  if (n == null) return Map<String, dynamic>.from(c);
  return {...c, 'mesaN': n};
}

Map<String, dynamic> _fusionarLineasMesasConceptoPdf(
  List<Map<String, dynamic>> lineas,
) {
  final enriched = lineas.map(_enriquecerMesaNConceptoPdf).toList();
  final titulo = MesasExtraUtils.tituloGrupoDesgloseMesas(enriched);

  var monto = 0.0;
  var gross = 0.0;
  for (final c in lineas) {
    monto += (c['monto'] as num?)?.toDouble() ?? 0;
    gross += (c['gross'] as num?)?.toDouble() ??
        (c['monto'] as num?)?.toDouble() ??
        0;
  }
  monto = double.parse(monto.toStringAsFixed(2));
  gross = double.parse(gross.toStringAsFixed(2));

  final nums = enriched
      .map((c) => c['mesaN'] as int?)
      .whereType<int>()
      .toList()
    ..sort();

  String? subtexto;
  if (nums.length >= 2) {
    subtexto = 'incluye mesas ${nums.join(', ')}';
  } else if (lineas.length >= 2) {
    subtexto = 'incluye ${lineas.length} mesas';
  }

  return {
    'concepto': titulo,
    'monto': monto,
    'gross': gross,
    'esPlanLiquidacion': true,
    if (subtexto != null) 'subtexto': subtexto,
  };
}

/// Agrupa líneas de mesas extra en el PDF cuando el contrato tiene 3+ mesas.
List<Map<String, dynamic>> agruparConceptosMesasParaPdf(
  List<Map<String, dynamic>> conceptos,
  int cantMesasContrato,
) {
  if (!MesasExtraUtils.usarUiCompactaMesasCobro(cantMesasContrato)) {
    return conceptos;
  }
  if (!conceptos.any(esLineaMesaConceptoPdf)) return conceptos;

  final out = <Map<String, dynamic>>[];
  var grupoMesasEmitido = false;

  for (final c in conceptos) {
    if (esLineaMesaConceptoPdf(c)) {
      if (grupoMesasEmitido) continue;
      grupoMesasEmitido = true;
      final lineasMesas =
          conceptos.where(esLineaMesaConceptoPdf).toList();
      out.add(_fusionarLineasMesasConceptoPdf(lineasMesas));
    } else {
      out.add(Map<String, dynamic>.from(c));
    }
  }
  return out;
}

/// Detalle compacto de mesas en "DETALLE DEL CONTRATO" del recibo (3+ mesas).
List<({String texto, bool liquidada})> lineasDetalleMesasContratoPdf({
  required List<MesaExtraItem> mesas,
  required int cuotasPlan,
}) {
  if (mesas.isEmpty) return [];

  if (!MesasExtraUtils.usarUiCompactaMesasCobro(mesas.length)) {
    return mesas
        .map(
          (m) => (
            texto: _textoLineaMesaContratoPdf(m, cuotasPlan, numerada: true),
            liquidada: m.liquidada,
          ),
        )
        .toList();
  }

  final buckets = <String, List<MesaExtraItem>>{};
  for (final m in mesas) {
    final restaKey = m.liquidada ? 'liq' : m.deuda.toStringAsFixed(0);
    final key =
        '${m.liquidada}_${m.cuotasPagadas}_${m.precio.toStringAsFixed(2)}_$restaKey';
    buckets.putIfAbsent(key, () => []).add(m);
  }

  final results = <({String texto, bool liquidada, int minN})>[];
  for (final group in buckets.values) {
    group.sort((a, b) => a.n.compareTo(b.n));
    final m = group.first;
    final nums = group.map((x) => x.n).toList()..sort();
    final rango = nums.length == 1
        ? '${nums.first}'
        : '${nums.first}–${nums.last}';

    if (m.liquidada) {
      results.add((
        texto:
            '· Mesas Extra $rango: ${m.precio.toCurrency()}  (Liquidadas | Cuota $cuotasPlan/$cuotasPlan)',
        liquidada: true,
        minN: nums.first,
      ));
    } else {
      final resta = m.deuda.clamp(0.0, double.infinity);
      final cuotaPart = cuotasPlan <= 1
          ? ''
          : ' | Cuota ${m.cuotasPagadas}/$cuotasPlan';
      if (group.length >= 2) {
        results.add((
          texto:
              '· Mesas Extra $rango: ${m.precio.toCurrency()} c/u  (Resta: ${resta.toCurrency()} c/u$cuotaPart)',
          liquidada: false,
          minN: nums.first,
        ));
      } else {
        results.add((
          texto: _textoLineaMesaContratoPdf(m, cuotasPlan, numerada: true),
          liquidada: false,
          minN: m.n,
        ));
      }
    }
  }

  results.sort((a, b) => a.minN.compareTo(b.minN));
  return results
      .map((r) => (texto: r.texto, liquidada: r.liquidada))
      .toList();
}

String _textoLineaMesaContratoPdf(
  MesaExtraItem m,
  int cuotasPlan, {
  required bool numerada,
}) {
  final resta = m.deuda.clamp(0.0, double.infinity);
  final label = numerada ? 'Mesa Extra ${m.n}' : 'Mesa Extra';
  if (m.liquidada) {
    return '· $label: ${m.precio.toCurrency()}  (Liquidada | Cuota $cuotasPlan/$cuotasPlan)';
  }
  final cuotaPart =
      cuotasPlan <= 1 ? '' : ' | Cuota ${m.cuotasPagadas}/$cuotasPlan';
  return '· $label: ${m.precio.toCurrency()}  (Resta: ${resta.toCurrency()}$cuotaPart)';
}

/// Totales del plan (base/mesa/sillas) para bloque de descuento en PDF.
({double nominal, double neto, double ahorro}) totalesDescuentoPlanPdf(
  Iterable<Map<String, dynamic>> conceptos,
) {
  var nominal = 0.0;
  var neto = 0.0;
  for (final c in conceptos) {
    if (!esConceptoPlanLiquidacionPdf(c)) continue;
    final m = (c['monto'] as num?)?.toDouble() ?? 0.0;
    final g = (c['gross'] as num?)?.toDouble() ?? m;
    nominal += g;
    neto += m;
  }
  nominal = double.parse(nominal.toStringAsFixed(2));
  neto = double.parse(neto.toStringAsFixed(2));
  final ahorro =
      double.parse((nominal - neto).clamp(0.0, double.infinity).toStringAsFixed(2));
  return (nominal: nominal, neto: neto, ahorro: ahorro);
}

/// Transforma [previewConceptos] del modal de cobro masivo en líneas listas
/// para PDF (recibo post-cobro o resumen a abonar). Una sola fuente de verdad.
List<Map<String, dynamic>> conceptosFinalesDesdePreviewMasivo({
  required List<Map<String, dynamic>> previewConceptos,
  required bool Function(Map<String, dynamic>) esLineaCargoCanal,
  required bool Function(Map<String, dynamic>) esLineaInteresMora,
  required int cPagadas,
  required int tCuotas,
  required int mPagadas,
  required int mCuotas,
  required int sPagadas,
  required int sCuotas,
  int cantMesas = 1,
}) {
  final conceptosFinales = <Map<String, dynamic>>[];
  var contadorBaseFinal = 0;
  var contadorMesaFinal = 0;
  var contadorSillasFinal = 0;

  for (final conc in previewConceptos) {
    if (esLineaCargoCanal(conc)) {
      final cargoMonto = double.parse(
        ((conc['monto'] as num).toDouble()).toStringAsFixed(2),
      );
      if (cargoMonto > 0.01) {
        conceptosFinales.add({
          'concepto': 'Cargo oper. transferencia (MP u otro)',
          'monto': cargoMonto,
          'esCargoCanal': true,
        });
      }
      continue;
    }

    final cTexto = conc['concepto'] as String;
    final cMonto = double.parse(
      ((conc['monto'] as num).toDouble()).toStringAsFixed(2),
    );
    final cCuotasConc =
        ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);

    var cRico = cTexto;
    // Rango de cuotas base que liquida esta línea: permite anidar su mora
    // debajo en el PDF. Solo metadato de presentación.
    int? nBaseDesde;
    int? nBaseHasta;
    if (esLineaInteresMora(conc)) {
      final desg =
          conc['moraDesglose'] as List<Map<String, dynamic>>?;
      final pendiente = (conc['moraPendientePrevias'] as num?)?.toDouble();
      final detRaw =
          (conc['moraPendientePreviasDetalle'] as List?)
              ?.cast<Map<String, dynamic>>();
      final detalle = detRaw == null
          ? const <MoraPendientePreviaDetalle>[]
          : detRaw.map((m) {
              DateTime? fp;
              final fs = m['fechaPagoCuota']?.toString();
              if (fs != null && fs.isNotEmpty) {
                fp = DateTime.tryParse(fs);
              }
              return MoraPendientePreviaDetalle(
                numeroCuota: (m['numeroCuota'] as num?)?.toInt() ?? 0,
                mesLabel: (m['mesLabel'] as String?) ?? '',
                montoAtribuido: (m['monto'] as num?)?.toDouble() ?? 0,
                fechaPagoCuota: fp,
                moraDebida: (m['moraDebida'] as num?)?.toDouble() ?? 0,
                moraCobrada: (m['moraCobrada'] as num?)?.toDouble() ?? 0,
              );
            }).toList();
      final lineasMora = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: cMonto,
        moraDesglose: desg,
        moraPendientePrevias: pendiente,
        detallePendiente: detalle,
        conceptoFallback: cTexto,
      );
      conceptosFinales.addAll(lineasMora);
      continue;
    } else if (cTexto.toUpperCase().contains('MESA') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO') &&
        !cTexto.toUpperCase().contains('ENTREGA PARCIAL')) {
      final mesaNPreview = conc['mesaN'] as int?;
      final mesaEnTexto = mesaNPreview ??
          MesasExtraUtils.mesaNumeroDesdeTexto(cTexto);
      final totalMesas = cantMesas > 1
          ? cantMesas
          : (mesaEnTexto != null && mesaEnTexto > 1 ? 2 : 1);
      final prefix = mesaEnTexto != null
          ? MesasExtraUtils.labelCobro(mesaEnTexto, totalMesas)
          : 'Mesa Extra';
      final yaRotuladoPorMesa = mesaEnTexto != null &&
          RegExp(r'\(\d+/\d+\)').hasMatch(cTexto);
      if (yaRotuladoPorMesa) {
        cRico = cTexto;
      } else if (mCuotas <= 1) {
        cRico = '$prefix - Entrega';
      } else if (cCuotasConc == 1) {
        cRico = '$prefix (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
      } else if (cCuotasConc > 1) {
        cRico =
            '$cCuotasConc Cuotas $prefix (${mPagadas + contadorMesaFinal + 1}-${mPagadas + contadorMesaFinal + cCuotasConc}/$mCuotas)';
      } else {
        cRico = 'Entrega parcial — $prefix (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
      }
      contadorMesaFinal += cCuotasConc;
    } else if (cTexto.toUpperCase().contains('SILLA') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO') &&
        !cTexto.toUpperCase().contains('ENTREGA PARCIAL')) {
      if (sCuotas <= 1) {
        cRico = 'Sillas Extras - Entrega';
      } else if (cCuotasConc == 1) {
        cRico =
            'Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
      } else if (cCuotasConc > 1) {
        cRico =
            '$cCuotasConc Cuotas Sillas Extras (${sPagadas + contadorSillasFinal + 1}-${sPagadas + contadorSillasFinal + cCuotasConc}/$sCuotas)';
      } else {
        cRico =
            'Entrega parcial — Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
      }
      contadorSillasFinal += cCuotasConc;
    } else if (cTexto.toUpperCase().contains('BASE') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO') &&
        !cTexto.toUpperCase().contains('ENTREGA PARCIAL')) {
      final yaRotulado = RegExp(r'\(\d+/\d+\)').hasMatch(cTexto);
      if (yaRotulado) {
        cRico = cTexto;
        final m = RegExp(r'\((\d+)/\d+\)').firstMatch(cTexto);
        if (m != null) {
          nBaseDesde = int.tryParse(m.group(1)!);
          nBaseHasta = nBaseDesde;
        }
      } else if (cCuotasConc == 1) {
        cRico =
            'Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
        nBaseDesde = cPagadas + contadorBaseFinal + 1;
        nBaseHasta = nBaseDesde;
      } else if (cCuotasConc > 1) {
        cRico =
            '$cCuotasConc Cuotas Base (${cPagadas + contadorBaseFinal + 1}-${cPagadas + contadorBaseFinal + cCuotasConc}/$tCuotas)';
        nBaseDesde = cPagadas + contadorBaseFinal + 1;
        nBaseHasta = cPagadas + contadorBaseFinal + cCuotasConc;
      } else {
        cRico =
            'Entrega parcial — Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
      }
      contadorBaseFinal += cCuotasConc;
    }

    final gross = (conc['gross'] as num?)?.toDouble() ?? cMonto;
    if (esLineaInteresMora(conc)) {
      conceptosFinales.add({
        'concepto': cRico,
        'monto': cMonto,
        'esMora': true,
      });
    } else {
      conceptosFinales.add({
        'concepto': cRico,
        'monto': cMonto,
        if (conc['subtexto'] != null) 'subtexto': conc['subtexto'],
        'gross': double.parse(gross.toStringAsFixed(2)),
        'esPlanLiquidacion': true,
        if (nBaseDesde != null) ...{
          'cuotaBaseDesde': nBaseDesde,
          'cuotaBaseHasta': nBaseHasta ?? nBaseDesde,
          'totalCuotasBase': tCuotas,
        },
      });
    }
  }

  return agruparConceptosMesasParaPdf(conceptosFinales, cantMesas);
}

final _reCuotaBaseSimple = RegExp(
  r'^Cuota Base \((\d+)/(\d+)\)$',
  caseSensitive: false,
);

/// Compacta cuotas base consecutivas del mismo monto (resumen a abonar).
/// Ej.: 9× "Cuota Base (n/9)" → "Cuotas base (1–9/9)".
///
/// No compacta un tramo que tenga mora anidada: fusionar esas cuotas dejaría
/// al interés colgando de una línea que ya no lo nombra.
List<Map<String, dynamic>> compactarCuotasBaseParaResumenPdf(
  List<Map<String, dynamic>> lineas,
) {
  final cuotasConMora = lineas
      .where((c) => c['esMora'] == true)
      .map((c) => (c['numeroCuota'] as num?)?.toInt())
      .whereType<int>()
      .toSet();
  final out = <Map<String, dynamic>>[];
  var i = 0;
  while (i < lineas.length) {
    final c = Map<String, dynamic>.from(lineas[i]);
    final concepto = (c['concepto'] as String? ?? '').trim();
    final match = _reCuotaBaseSimple.firstMatch(concepto);
    if (c['esPlanLiquidacion'] != true ||
        c['esMora'] == true ||
        c['esCargoCanal'] == true ||
        match == null) {
      out.add(c);
      i++;
      continue;
    }

    final nums = <int>[int.parse(match.group(1)!)];
    final totalCuotas = int.parse(match.group(2)!);
    if (cuotasConMora.contains(nums.first)) {
      out.add(c);
      i++;
      continue;
    }
    final unitMonto = (c['monto'] as num?)?.toDouble() ?? 0;
    var sumMonto = unitMonto;
    var sumGross = (c['gross'] as num?)?.toDouble() ?? unitMonto;
    var j = i + 1;

    while (j < lineas.length) {
      final n = lineas[j];
      if (n['esPlanLiquidacion'] != true ||
          n['esMora'] == true ||
          n['esCargoCanal'] == true) {
        break;
      }
      final mj = _reCuotaBaseSimple.firstMatch(
        (n['concepto'] as String? ?? '').trim(),
      );
      if (mj == null) break;
      if (int.parse(mj.group(2)!) != totalCuotas) break;
      final nNum = int.parse(mj.group(1)!);
      if (nNum != nums.last + 1) break;
      final nMonto = (n['monto'] as num?)?.toDouble() ?? 0;
      if ((nMonto - unitMonto).abs() > 0.02) break;
      nums.add(nNum);
      sumMonto += nMonto;
      sumGross += (n['gross'] as num?)?.toDouble() ?? nMonto;
      j++;
    }

    if (nums.length >= 2) {
      out.add({
        'concepto':
            'Cuotas base (${nums.first}–${nums.last}/$totalCuotas)',
        'monto': double.parse(sumMonto.toStringAsFixed(2)),
        'gross': double.parse(sumGross.toStringAsFixed(2)),
        'esPlanLiquidacion': true,
      });
      i = j;
    } else {
      out.add(c);
      i++;
    }
  }
  return out;
}

/// Gross del plan en la selección (reduce saldo_deudor; excluye mora/cargo).
double grossPlanSeleccionadoPdf(Iterable<Map<String, dynamic>> conceptos) {
  var sum = 0.0;
  for (final c in conceptos) {
    if (c['esPlanLiquidacion'] != true) continue;
    if (c['esMora'] == true || c['esCargoCanal'] == true) continue;
    final g = (c['gross'] as num?)?.toDouble() ??
        (c['monto'] as num?)?.toDouble() ??
        0;
    sum += g;
  }
  return double.parse(sum.toStringAsFixed(2));
}

double moraSeleccionadaPdf(Iterable<Map<String, dynamic>> conceptos) {
  return conceptos
      .where((c) => c['esMora'] == true)
      .fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );
}

/// Cuotas cuyo interés se cobra en este recibo, ordenadas y sin repetir.
/// Vacía si las líneas de mora no traen metadata (recibos viejos).
List<int> cuotasConMoraCobradaPdf(Iterable<Map<String, dynamic>> conceptos) {
  final ns = <int>{};
  for (final c in conceptos) {
    if (c['esMora'] != true) continue;
    final n = (c['numeroCuota'] as num?)?.toInt() ??
        (c['cuotaPrevia'] as num?)?.toInt();
    if (n != null && n > 0) ns.add(n);
  }
  return ns.toList()..sort();
}

/// "cuota 3" · "cuotas 2 y 3" · "cuotas 2, 3 y 5". Vacío si no hay cuotas.
String fraseCuotasEs(List<int> ns) {
  if (ns.isEmpty) return '';
  if (ns.length == 1) return 'cuota ${ns.first}';
  final previas = ns.sublist(0, ns.length - 1).join(', ');
  return 'cuotas $previas y ${ns.last}';
}

/// Suma líneas de liquidación (excluye cargo canal).
double sumLiquidoConceptosFinales(List<Map<String, dynamic>> conceptos) {
  return conceptos
      .where((c) => c['esCargoCanal'] != true)
      .fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );
}

// ── Capa de presentación del PDF ────────────────────────────────────────────
// Agrega 'display' (texto para el papel), 'anidada' y 'arrastre'. NUNCA toca
// 'concepto': ese texto es el que reconocen esPagoInteresMoraPorConcepto,
// MoraTrackedRecovery._esBaseCuota y recalcularSaldoDesdePagos.

String _dosDigitos(int v) => v.toString().padLeft(2, '0');

String _fechaCorta(DateTime d) =>
    '${_dosDigitos(d.day)}/${_dosDigitos(d.month)}/${d.year}';

final _reCuotaRango = RegExp(r'\((\d+)[-–](\d+)/(\d+)\)');
final _reCuotaSimple = RegExp(r'\((\d+)/(\d+)\)');

/// Rótulo familiar para una línea de plan (cuota base, mesa, sillas, cargo).
String _displayPlan(Map<String, dynamic> c, DateTime? regAr, DateTime? hoyAr) {
  final texto = (c['concepto'] as String? ?? '').trim();

  if (c['esCargoCanal'] == true) return 'Costo por transferencia';

  final desde = (c['cuotaBaseDesde'] as num?)?.toInt();
  final hasta = (c['cuotaBaseHasta'] as num?)?.toInt();
  final total = (c['totalCuotasBase'] as num?)?.toInt();
  if (desde != null && total != null) {
    if (hasta != null && hasta > desde) {
      return 'Cuotas $desde a $hasta de $total';
    }
    final base = 'Cuota $desde de $total';
    if (regAr == null) return base;
    final venc = MoraCuotaCalculator.vencimientoCuotaDesdeRegAr(regAr, desde);
    final ref = hoyAr ?? DateTime.now();
    final vencida = DateTime(ref.year, ref.month, ref.day).isAfter(venc);
    return '$base — ${vencida ? 'venció' : 'vence'} ${_fechaCorta(venc)}';
  }

  // "Cuotas base (1–9/9)" (ya compactada) y demás rubros del plan.
  final rango = _reCuotaRango.firstMatch(texto);
  if (rango != null && texto.toLowerCase().contains('cuotas base')) {
    return 'Cuotas ${rango.group(1)} a ${rango.group(2)} de ${rango.group(3)}';
  }

  final simple = _reCuotaSimple.firstMatch(texto);
  final upper = texto.toUpperCase();
  if (simple != null && upper.contains('SILLA')) {
    return 'Sillas extra — cuota ${simple.group(1)} de ${simple.group(2)}';
  }
  if (simple != null && upper.contains('MESA')) {
    final n = MesasExtraUtils.mesaNumeroDesdeTexto(texto);
    final etiqueta = n != null ? 'Mesa extra $n' : 'Mesa extra';
    return '$etiqueta — cuota ${simple.group(1)} de ${simple.group(2)}';
  }
  if (simple != null && upper.contains('BASE')) {
    return 'Cuota ${simple.group(1)} de ${simple.group(2)}';
  }
  return texto;
}

/// Rótulo familiar para una línea de mora.
///
/// El rótulo identifica la línea; el detalle (vencimiento, días, montos) lo
/// dice el subtexto. Cuando la línea trae subtexto, el rótulo no repite nada
/// de eso: en el papel salían los mismos días y el mismo mes dos veces.
String _displayMora(Map<String, dynamic> c) {
  final conSubtexto = ((c['subtexto'] as String?) ?? '').trim().isNotEmpty;

  final previa = (c['cuotaPrevia'] as num?)?.toInt();
  if (previa != null) {
    // Arrastre: dice de qué cuota viene y de cuándo, para que se entienda
    // leyendo el papel sin tener que preguntar.
    if (conSubtexto) return 'Mora de la cuota $previa';
    final mes = (c['mesCuotaPrevia'] as String?)?.trim() ?? '';
    final dias = (c['diasMora'] as num?)?.toInt() ?? 0;
    final cuando = mes.isEmpty ? '' : ' de $mes';
    final atraso = dias > 0
        ? ' — $dias ${dias == 1 ? 'día' : 'días'} fuera de término'
        : '';
    return 'Mora de la cuota $previa$cuando$atraso, no cobrada en su momento';
  }
  final dias = (c['diasMora'] as num?)?.toInt();
  if (dias != null && dias > 0) {
    // Va anidada bajo su cuota y se repite por línea: rótulo corto. Qué es la
    // mora lo explica el pie del recibo, una sola vez.
    return 'Mora — $dias ${dias == 1 ? 'día' : 'días'} fuera de término';
  }
  final texto = (c['concepto'] as String? ?? '').trim();
  if (texto.toLowerCase().contains('mora pendiente') ||
      texto.toLowerCase().contains('cuotas ya pagadas')) {
    return 'Mora de cuotas anteriores, no cobrada en su momento';
  }
  return 'Mora por pagar fuera de término';
}

/// Reordena las líneas para el PDF: cada mora del calendario queda pegada a la
/// cuota que la generó (`anidada`), y la mora de cuotas ya pagadas en cobros
/// anteriores cae al final (`arrastre`), bajo su propio subtítulo.
///
/// [regAr] es el Reg del contrato en hora AR: se usa solo para imprimir el
/// vencimiento de cada cuota (`vencimientoCuotaDesdeRegAr`).
List<Map<String, dynamic>> lineasDisplayParaPdf(
  List<Map<String, dynamic>> lineas, {
  DateTime? regAr,
  DateTime? hoyAr,
}) {
  final moras = lineas.where((c) => c['esMora'] == true).toList();
  final resto = lineas.where((c) => c['esMora'] != true).toList();
  final usadas = <int>{};

  final out = <Map<String, dynamic>>[];
  for (final c in resto) {
    out.add({...c, 'display': _displayPlan(c, regAr, hoyAr)});

    final desde = (c['cuotaBaseDesde'] as num?)?.toInt();
    final hasta = (c['cuotaBaseHasta'] as num?)?.toInt() ?? desde;
    if (desde == null) continue;
    for (var k = 0; k < moras.length; k++) {
      if (usadas.contains(k)) continue;
      final n = (moras[k]['numeroCuota'] as num?)?.toInt();
      if (n == null || n < desde || n > hasta!) continue;
      usadas.add(k);
      out.add({
        ...moras[k],
        'display': _displayMora(moras[k]),
        'anidada': true,
      });
    }
  }

  for (var k = 0; k < moras.length; k++) {
    if (usadas.contains(k)) continue;
    out.add({
      ...moras[k],
      'display': _displayMora(moras[k]),
      'arrastre': true,
    });
  }

  return out;
}

/// Subtítulo del bloque de moras que no corresponden a este cobro.
const String tituloArrastreMoraPdf = 'Intereses de cuotas ya pagadas';

double cargoDesdeConceptosFinales(List<Map<String, dynamic>> conceptos) {
  return conceptos
      .where((c) => c['esCargoCanal'] == true)
      .fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );
}
