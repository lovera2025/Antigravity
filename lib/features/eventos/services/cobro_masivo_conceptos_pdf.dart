bool esConceptoPlanLiquidacionPdf(Map<String, dynamic> c) =>
    c['esPlanLiquidacion'] == true;

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
    if (esLineaInteresMora(conc)) {
      final desg =
          conc['moraDesglose'] as List<Map<String, dynamic>>?;
      if (desg != null && desg.isNotEmpty) {
        final totalBrutoDesg = desg.fold<double>(
          0,
          (s, d) => s + (d['monto'] as num).toDouble(),
        );
        for (final d in desg) {
          final proportion = totalBrutoDesg > 0.01
              ? (d['monto'] as num).toDouble() / totalBrutoDesg
              : 1.0 / desg.length;
          final montoLinea = double.parse(
            (cMonto * proportion).toStringAsFixed(2),
          );
          final dias = d['diasMora'] as int?;
          conceptosFinales.add({
            'concepto':
                'Interés mora cuota ${d['numeroCuota']} (${d['mesLabel']})',
            'monto': montoLinea,
            'esMora': true,
            if (dias != null && dias > 0) 'subtexto': '$dias días de mora',
          });
        }
        continue;
      }
      cRico = 'Interés mora (cuota base — este cobro)';
    } else if (cTexto.toUpperCase().contains('MESA') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO')) {
      if (mCuotas <= 1) {
        cRico = 'Mesa Extra - Entrega';
      } else if (cCuotasConc == 1) {
        cRico =
            'Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
      } else if (cCuotasConc > 1) {
        cRico =
            '$cCuotasConc Cuotas Mesa Extra (${mPagadas + contadorMesaFinal + 1}-${mPagadas + contadorMesaFinal + cCuotasConc}/$mCuotas)';
      } else {
        cRico =
            'Abono Mesa Extra (${mPagadas + contadorMesaFinal + 1}/$mCuotas)';
      }
      contadorMesaFinal += cCuotasConc;
    } else if (cTexto.toUpperCase().contains('SILLA') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO')) {
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
            'Abono Sillas Extras (${sPagadas + contadorSillasFinal + 1}/$sCuotas)';
      }
      contadorSillasFinal += cCuotasConc;
    } else if (cTexto.toUpperCase().contains('BASE') &&
        !cTexto.toUpperCase().contains('ADELANTO') &&
        !cTexto.toUpperCase().contains('ABONO')) {
      if (cCuotasConc == 1) {
        cRico =
            'Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
      } else if (cCuotasConc > 1) {
        cRico =
            '$cCuotasConc Cuotas Base (${cPagadas + contadorBaseFinal + 1}-${cPagadas + contadorBaseFinal + cCuotasConc}/$tCuotas)';
      } else {
        cRico =
            'Abono Cuota Base (${cPagadas + contadorBaseFinal + 1}/$tCuotas)';
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
        'gross': double.parse(gross.toStringAsFixed(2)),
        'esPlanLiquidacion': true,
      });
    }
  }

  return conceptosFinales;
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

double cargoDesdeConceptosFinales(List<Map<String, dynamic>> conceptos) {
  return conceptos
      .where((c) => c['esCargoCanal'] == true)
      .fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );
}
