  Future<void> _mostrarModalPagoAlumno(ContratoAlumno alumno) async {
    if (alumno.saldoDeudor <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este alumno no tiene saldo pendiente.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    final prefsMedio = await SharedPreferences.getInstance();
    final cRepo = ref.read(contratosRepositoryProvider);
    final moraYaCobradaHist = await cRepo.sumMoraCobradaHistorial(alumno.id);
    final pagosAlumno = await cRepo.getHistorialPagosAlumno(alumno.id);
    final moraResumen = MoraCuotaCalculator.calcular(alumno);
    final moraPeriodo = moraCobradaDelPeriodoVigente(
      pagosAlumno,
      inicioMoraPeriodoVigente(moraResumen.fechaVencimientoProximaCuota),
    );
    final double moraPendienteUi = MoraCuotaCalculator.pendienteDisplay(
      interesAcumulado: moraResumen.interesAcumulado,
      moraCobradaHistorial: moraYaCobradaHist,
      moraPendienteTracked: alumno.moraPendienteTracked,
      moraCobradaOffset: alumno.moraCobradaOffset,
      moraCobradaPeriodo: moraPeriodo,
    );

    String modoMedioPago =
        prefsMedio.getString('medio_pago_cobro_masivo') ?? 'Efectivo';
    if (modoMedioPago != 'Efectivo' &&
        modoMedioPago != 'Transferencia' &&
        modoMedioPago != 'Mixto') {
      modoMedioPago = 'Efectivo';
    }

    final int tCuotas = alumno.totalCuotas ?? 9;
    final int cPagadas = alumno.cuotasPagadas ?? 0;
    final int mCuotas = alumno.mesaExtraCuotas ?? 1;
    final int mPagadas = alumno.mesaExtraCuotasPagadas ?? 0;
    final int sCuotas = alumno.sillasExtraCuotas ?? 1;
    final int sPagadas = alumno.sillasExtraCuotasPagadas ?? 0;

    final double deudaMesaTotal =
        (alumno.mesaExtraPrecio - (alumno.mesaExtraPagado ?? 0)).clamp(
          0.0,
          double.infinity,
        );
    final double deudaSillasTotal =
        (alumno.sillasExtraPrecioTotal - (alumno.sillasExtraPagado ?? 0)).clamp(
          0.0,
          double.infinity,
        );
    final double totalBase =
        (alumno.montoTotalPactado -
        alumno.mesaExtraPrecio -
        alumno.sillasExtraPrecioTotal);
    final double cuotaPura = tCuotas > 0
        ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
        : totalBase;

    final double deudaBaseTotal =
        (alumno.saldoDeudor - deudaMesaTotal - deudaSillasTotal).clamp(
          0.0,
          double.infinity,
        );

    final montoPagarCtrl = TextEditingController();
    final porcentajeDescuentoCtrl = TextEditingController();
    final moraMontoCobroCtrl = TextEditingController();
    final efectivoMixCtrl = TextEditingController();
    final transferMixCtrl = TextEditingController();
    final pctTransferInfoCtrl = TextEditingController(
      text: prefsMedio.getString('cobro_masivo_pct_transfer_info') ?? '0',
    );
    String transferCargoModoInit =
        prefsMedio.getString('cobro_masivo_transfer_cargo_modo') ?? 'pct';
    if (transferCargoModoInit != 'pct' && transferCargoModoInit != 'pesos') {
      transferCargoModoInit = 'pct';
    }
    final transferCargoMontoCtrl = TextEditingController(
      text: prefsMedio.getString('cobro_masivo_transfer_cargo_monto') ?? '',
    );
    final bool informarPctTransferExternoInit =
        prefsMedio.getBool('cobro_masivo_informar_pct_transfer') ?? false;
    if (moraPendienteUi > 0.01) {
      moraMontoCobroCtrl.text = moraPendienteUi.toFormattedNumber();
    }

    bool pagarBase = false;
    bool pagarMesa = false;
    bool pagarSillas = false;
    bool incluirInteresCuota = false;
    Map<String, double> montosManuales = {};
    List<Map<String, dynamic>> previewConceptos = [];

    bool esLineaInteresMora(Map<String, dynamic> c) =>
        c['lineKind'] == 'interes_mora';

    bool esLineaCargoCanal(Map<String, dynamic> c) =>
        c['lineKind'] == 'cargo_canal_ref';

    Map<String, dynamic> lineaPreviewInteresMora(double monto) {
      final g = double.parse(
        monto.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      return {
        'concepto': 'Interés mora (cuota base — este cobro)',
        'monto': g,
        'gross': g,
        'cuotas': 0,
        'lineKind': 'interes_mora',
      };
    }

    Map<String, dynamic> lineaPreviewCargoCanal(double monto) {
      final g = double.parse(
        monto.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
      return {
        'concepto': 'Cargo canal / operador (ref. MP u otro)',
        'monto': g,
        'gross': g,
        'cuotas': 0,
        'lineKind': 'cargo_canal_ref',
      };
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool informarPctTransferExterno = informarPctTransferExternoInit;
        String transferCargoModo = transferCargoModoInit;
        return StatefulBuilder(
          builder: (context, setModalState) {
            double montoMoraLineaIngresado() {
              double v = CurrencyInputFormatter.parse(moraMontoCobroCtrl.text);
              if (v < 0) v = 0;
              if (moraPendienteUi > 0.01 && v > moraPendienteUi + 0.01) {
                v = moraPendienteUi;
              }
              return double.parse(v.toStringAsFixed(2));
            }

            double pctCargoInformeDesdeCampo() {
              final s = pctTransferInfoCtrl.text.replaceAll(',', '.').trim();
              return double.tryParse(s) ?? 0.0;
            }

            double montoCargoInformeDesdeCampo() {
              return CurrencyInputFormatter.parse(transferCargoMontoCtrl.text);
            }

            /// Cargo del operador sobre la parte líquida transferida (MP/comisión ref.).
            double cargoSobreLiquidoTransferencia(double liquido) {
              if (!informarPctTransferExterno || liquido <= 0.001) {
                return 0;
              }
              if (transferCargoModo == 'pesos') {
                final c = montoCargoInformeDesdeCampo();
                return double.parse(
                  c.clamp(0.0, double.infinity).toStringAsFixed(2),
                );
              }
              final pct = pctCargoInformeDesdeCampo();
              if (pct <= 0.001) return 0;
              return double.parse((liquido * pct / 100.0).toStringAsFixed(2));
            }

            /// Total mostrado en Transferencia (mixto) incluye cargo; esto recupera la parte líquida.
            double liquidoTransferenciaDesdeTotalMixto(
              double transferTotalMostrado,
            ) {
              final T = double.parse(
                transferTotalMostrado
                    .clamp(0.0, double.infinity)
                    .toStringAsFixed(2),
              );
              if (!informarPctTransferExterno) return T;
              if (transferCargoModo == 'pesos') {
                final cFix = double.parse(
                  montoCargoInformeDesdeCampo()
                      .clamp(0.0, double.infinity)
                      .toStringAsFixed(2),
                );
                return double.parse(
                  (T - cFix).clamp(0.0, double.infinity).toStringAsFixed(2),
                );
              }
              final pct = pctCargoInformeDesdeCampo();
              if (pct <= 0.001) return T;
              final denom = 1.0 + pct / 100.0;
              return double.parse(
                (T / denom).clamp(0.0, double.infinity).toStringAsFixed(2),
              );
            }

            double sumPreviewLiquidoConceptos() {
              return previewConceptos
                  .where((c) => !esLineaCargoCanal(c))
                  .fold<double>(
                    0,
                    (s, c) => s + (c['monto'] as num).toDouble(),
                  );
            }

            double liquidoTransferenciaBaseParaCargoInforme() {
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) return 0;
              if (modoMedioPago == 'Transferencia') return sumL;
              if (modoMedioPago == 'Mixto') {
                var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
                if (e > sumL + 0.01) {
                  e = sumL;
                }
                return (sumL - e).clamp(0.0, double.infinity);
              }
              return 0;
            }

            void syncMixFieldsDesdeTotal() {
              if (modoMedioPago != 'Mixto') return;
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) {
                efectivoMixCtrl.clear();
                transferMixCtrl.clear();
                return;
              }
              var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
              if (e > sumL + 0.01) {
                e = sumL;
              }
              final liquidoTr =
                  (sumL - e).clamp(0.0, double.infinity);
              final cargo = informarPctTransferExterno
                  ? cargoSobreLiquidoTransferencia(liquidoTr)
                  : 0.0;
              transferMixCtrl.text =
                  double.parse((liquidoTr + cargo).toStringAsFixed(2))
                      .toFormattedNumber();
              montoPagarCtrl.text =
                  double.parse((sumL + cargo).toStringAsFixed(2))
                      .toFormattedNumber();
            }

            /// Inserta línea de cargo en preview y actualiza MONTO DE ENTREGA (y mixto).
            void finalizarPreviewConCargoCanal() {
              previewConceptos.removeWhere(esLineaCargoCanal);

              final double sumL = previewConceptos.fold<double>(
                0,
                (s, c) => s + (c['monto'] as num).toDouble(),
              );

              if (sumL <= 0.01) {
                montoPagarCtrl.clear();
                if (modoMedioPago == 'Mixto') {
                  efectivoMixCtrl.clear();
                  transferMixCtrl.clear();
                }
                return;
              }

              double liquidoTrParaCargo = sumL;
              if (modoMedioPago == 'Mixto') {
                var e = CurrencyInputFormatter.parse(efectivoMixCtrl.text);
                if (e > sumL + 0.01) {
                  e = sumL;
                }
                liquidoTrParaCargo =
                    (sumL - e).clamp(0.0, double.infinity);
              } else if (modoMedioPago != 'Transferencia') {
                montoPagarCtrl.text = sumL.toFormattedNumber();
                return;
              }

              final cargo = informarPctTransferExterno
                  ? cargoSobreLiquidoTransferencia(liquidoTrParaCargo)
                  : 0.0;

              if (cargo > 0.01) {
                previewConceptos.add(lineaPreviewCargoCanal(cargo));
              }

              final totalMostrar =
                  double.parse((sumL + cargo).toStringAsFixed(2));
              montoPagarCtrl.text = totalMostrar.toFormattedNumber();

              if (modoMedioPago == 'Mixto') {
                syncMixFieldsDesdeTotal();
              }
            }

            void aplicarEdicionTransferenciaMixto() {
              if (modoMedioPago != 'Mixto') return;
              final sumL = sumPreviewLiquidoConceptos();
              if (sumL <= 0.01) return;
              final T = CurrencyInputFormatter.parse(
                transferMixCtrl.text,
              ).clamp(0.0, double.infinity);
              final L = liquidoTransferenciaDesdeTotalMixto(T);
              final newE =
                  (sumL - L).clamp(0.0, double.infinity);
              efectivoMixCtrl.text = newE.toFormattedNumber();
              final cargoSync = cargoSobreLiquidoTransferencia(L);
              final totalEsperadoCanal =
                  double.parse((L + cargoSync).toStringAsFixed(2));
              if ((totalEsperadoCanal - T).abs() > 0.03) {
                transferMixCtrl.text =
                    totalEsperadoCanal.toFormattedNumber();
              }
              finalizarPreviewConCargoCanal();
            }

            double montoTransferenciaParaCargoInforme() {
              return liquidoTransferenciaBaseParaCargoInforme();
            }

            String getConceptoDetallado(String raw, int cuotaOffset) {
              if (raw == 'Cuota Base' || raw.contains('CUOTA BASE')) {
                final num = cPagadas + cuotaOffset;
                return 'Cuota Base ($num/$tCuotas)';
              }
              if (raw == 'Mesa Extra' || raw.contains('MESA EXTRA')) {
                if (mCuotas <= 1) return 'Mesa Extra - Entrega';
                final num = mPagadas + cuotaOffset;
                return 'Mesa Extra ($num/$mCuotas)';
              }
              if (raw == 'Sillas Extras' || raw.contains('SILLAS EXTRAS')) {
                if (sCuotas <= 1) return 'Sillas Extras - Entrega';
                final num = sPagadas + cuotaOffset;
                return 'Sillas Extras ($num/$sCuotas)';
              }
              return raw;
            }

            Map<String, dynamic> calcularDesgloseInteligente(
              String conceptoKey,
              String label,
              double gross,
              double net,
              double qPura,
            ) {
              int cuotasCompletas = 0;
              int cant = 0;
              String conceptoFinal = label;

              if (qPura > 0) {
                cuotasCompletas = (gross / qPura).floor();
                double resto = gross - (cuotasCompletas * qPura);
                bool esExacto = resto.abs() < 0.1;

                if (cuotasCompletas > 1 && esExacto) {
                  conceptoFinal = '$cuotasCompletas Cuotas (${label})';
                  cant = cuotasCompletas;
                } else if (cuotasCompletas >= 1 && !esExacto) {
                  int proxCuota = (conceptoKey == 'Base')
                      ? (cPagadas + cuotasCompletas + 1)
                      : 0;
                  if (conceptoKey == 'Base') {
                    conceptoFinal =
                        '$cuotasCompletas Cuotas + Adelanto (C$proxCuota)';
                  } else {
                    conceptoFinal = '$cuotasCompletas Enteras + Adelanto';
                  }
                  cant = cuotasCompletas;
                } else if (cuotasCompletas == 1 && esExacto) {
                  conceptoFinal = getConceptoDetallado(label, 1);
                  cant = 1;
                } else {
                  conceptoFinal = 'Abono a ${getConceptoDetallado(label, 1)}';
                  cant = 0;
                }
              } else {
                conceptoFinal = getConceptoDetallado(label, 1);
              }

              return {
                'concepto': conceptoFinal,
                'monto': double.parse(net.toStringAsFixed(2)),
                'gross': double.parse(gross.toStringAsFixed(2)),
                'cuotas': cant,
              };
            }

            Future<double?> preguntarMontoParcial(
              String titulo,
              double deudaMax,
            ) async {
              final ctrl = TextEditingController();
              return showDialog<double>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    'Entrega Parcial: $titulo',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deuda pendiente: ${deudaMax.toCurrency()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Monto a entregar',
                          prefixText: r'$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCELAR'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final val = CurrencyInputFormatter.parse(ctrl.text);
                        if (val > 0 &&
                            (val <= (deudaMax + 0.01) || deudaMax == 0)) {
                          Navigator.pop(ctx, val);
                        } else {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Monto inválido')),
                          );
                        }
                      },
                      child: const Text('ACEPTAR'),
                    ),
                  ],
                ),
              );
            }

            void recalcularDesdeMonto(double monto, {bool manually = false}) {
              previewConceptos.clear();
              if (!manually) montosManuales.clear();

              final double dtoPerc =
                  double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              if (manually && montosManuales.isNotEmpty) {
                montosManuales.forEach((key, gross) {
                  final double net = CalculadoraFinanciera.brutoANeto(
                    gross,
                    dtoPerc,
                  );
                  double qPura = 0;
                  String label = key;

                  if (key == 'Base') {
                    qPura = cuotaPura;
                    label = 'Cuota Base';
                  } else if (key == 'Mesa') {
                    qPura =
                        alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1);
                    label = 'Mesa Extra';
                  } else if (key == 'Sillas') {
                    qPura =
                        alumno.sillasExtraPrecioTotal /
                        (sCuotas > 0 ? sCuotas : 1);
                    label = 'Sillas Extras';
                  }

                  final desglose = calcularDesgloseInteligente(
                    key,
                    label,
                    gross,
                    net,
                    qPura,
                  );
                  previewConceptos.add(desglose);
                });
                final bool cobrandoBaseManual =
                    montosManuales.containsKey('Base') &&
                    ((montosManuales['Base'] ?? 0) > 0.01);
                if (incluirInteresCuota &&
                    cobrandoBaseManual &&
                    moraPendienteUi > 0.01) {
                  final mm = montoMoraLineaIngresado();
                  if (mm > 0.01) {
                    previewConceptos.add(lineaPreviewInteresMora(mm));
                  }
                }
              }

              pagarSillas = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Sillas'),
              );
              pagarMesa = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Mesa'),
              );
              pagarBase = previewConceptos.any(
                (c) =>
                    !esLineaInteresMora(c) &&
                    !esLineaCargoCanal(c) &&
                    c['concepto'].toString().contains('Cuota'),
              );

              if (incluirInteresCuota && !pagarBase) {
                incluirInteresCuota = false;
              }
              finalizarPreviewConCargoCanal();
            }

            void recalcularDesdeChecks() {
              previewConceptos.clear();
              double totalAcumuladoNeto = 0;
              final double dtoPerc =
                  double.tryParse(porcentajeDescuentoCtrl.text) ?? 0.0;

              void procesarConcepto(
                String key,
                String label,
                double deudaTotal,
                double qPura,
              ) {
                double gross = montosManuales[key] ?? deudaTotal;
                double net = CalculadoraFinanciera.brutoANeto(gross, dtoPerc);

                final desglose = calcularDesgloseInteligente(
                  key,
                  label,
                  gross,
                  net,
                  qPura,
                );
                previewConceptos.add(desglose);
                totalAcumuladoNeto += net;
              }

              if (pagarBase && deudaBaseTotal > 0.01) {
                procesarConcepto(
                  'Base',
                  'Cuota Base',
                  deudaBaseTotal,
                  cuotaPura,
                );
              }
              if (pagarMesa && deudaMesaTotal > 0.01) {
                procesarConcepto(
                  'Mesa',
                  'Mesa Extra',
                  deudaMesaTotal,
                  alumno.mesaExtraPrecio / (mCuotas > 0 ? mCuotas : 1),
                );
              }
              if (pagarSillas && deudaSillasTotal > 0.01) {
                procesarConcepto(
                  'Sillas',
                  'Sillas Extras',
                  deudaSillasTotal,
                  alumno.sillasExtraPrecioTotal / (sCuotas > 0 ? sCuotas : 1),
                );
              }

              if (incluirInteresCuota && pagarBase && moraPendienteUi > 0.01) {
                final mm = montoMoraLineaIngresado();
                if (mm > 0.01) {
                  previewConceptos.add(lineaPreviewInteresMora(mm));
                  totalAcumuladoNeto += mm;
                }
              }

              finalizarPreviewConCargoCanal();
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: Color(0xFFD4AF37)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cobro: ${alumno.nombreAlumno}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.withValues(alpha: 0.1),
                              Colors.blue.withValues(alpha: 0.02),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SALDO GLOBAL PENDIENTE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.blue,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(
                                  alumno.saldoDeudor.toCurrency(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.blue,
                              size: 32,
                            ),
                          ],
                        ),
                      ),
                      if (moraResumen.fechaVencimientoProximaCuota != null ||
                          moraResumen.enMora ||
                          moraResumen.diasMora > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'REFERENCIA MORA / INTERÉS (cuota base)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orange.shade900,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (moraResumen.fechaVencimientoProximaCuota !=
                                        null &&
                                    moraResumen.proximaCuotaNumero != null)
                                  Text(
                                    'Próx. venc.: ${ArTime.formatFechaCorta(moraResumen.fechaVencimientoProximaCuota!)} (cuota ${moraResumen.proximaCuotaNumero}/$tCuotas)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                Text(
                                  'Días de atraso: ${moraResumen.diasMora}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                if (moraResumen.interesAcumulado > 0.01)
                                  Text(
                                    'Interés teórico acum. (hoy): ${moraResumen.interesAcumulado.toCurrency()} · Mora ya cobrada: ${moraYaCobradaHist.toCurrency()}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                if (moraPendienteUi > 0.01)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Mora pendiente: ${moraPendienteUi.toCurrency()}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  )
                                else if (moraResumen.interesAcumulado > 0.01)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Sin mora pendiente respecto al cálculo de hoy.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  'Podés incluir mora en este cobro; no forma parte del saldo del plan ni liquida cuotas extra. Podés abonar un monto parcial; el resto sigue pendiente y se recalcula día a día.',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (moraPendienteUi > 0.01) ...[
                                  const SizedBox(height: 8),
                                  CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: incluirInteresCuota,
                                    onChanged: pagarBase
                                        ? (v) {
                                            setModalState(() {
                                              incluirInteresCuota = v ?? false;
                                              if (incluirInteresCuota) {
                                                moraMontoCobroCtrl.text =
                                                    moraPendienteUi
                                                        .toFormattedNumber();
                                              }
                                              recalcularDesdeChecks();
                                            });
                                          }
                                        : null,
                                    title: Text(
                                      'Incluir mora en este cobro (máx. ${moraPendienteUi.toCurrency()})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                    subtitle: pagarBase
                                        ? null
                                        : Text(
                                            'Marcá primero CUOTA BASE para aplicar mora a esta liquidación.',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                  ),
                                  if (incluirInteresCuota && pagarBase) ...[
                                    TextField(
                                      controller: moraMontoCobroCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        CurrencyInputFormatter(),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Monto mora a cobrar ahora',
                                        prefixIcon: Icon(
                                          Icons.percent_rounded,
                                          color: Colors.orange.shade800,
                                          size: 20,
                                        ),
                                        filled: true,
                                        fillColor: Colors.orange.withValues(
                                          alpha: 0.05,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onChanged: (_) {
                                        setModalState(
                                          () => recalcularDesdeChecks(),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      _buildConceptoTile(
                        titulo: 'CUOTA BASE (Mensualidad)',
                        deuda: deudaBaseTotal,
                        isDark: Theme.of(context).brightness == Brightness.dark,
                        selected: pagarBase,
                        montoManual: montosManuales['Base'],
                        onChanged: (v) async {
                          if (v == true) {
                            int restantes = tCuotas - cPagadas;
                            final choice = await _mostrarOpcionesPago(
                              context,
                              'Cuota Base',
                              deudaBaseTotal,
                              cuotaUnica: cuotaPura,
                              cuotasRestantes: restantes,
                            );
                            if (choice == 'TOTAL') {
                              setModalState(() {
                                pagarBase = true;
                                montosManuales['Base'] = deudaBaseTotal;
                              });
                            } else if (choice == 'UNICA') {
                              setModalState(() {
                                pagarBase = true;
                                montosManuales['Base'] = cuotaPura;
                              });
                            } else if (choice == 'VARIAS') {
                              final n = await _mostrarDialogoSeleccionCuotas(
                                context,
                                'Cuota Base',
                                restantes,
                              );
                              if (n != null) {
                                setModalState(() {
                                  pagarBase = true;
                                  montosManuales['Base'] = cuotaPura * n;
                                });
                              }
                            } else if (choice == 'PARTE') {
                              final m = await preguntarMontoParcial(
                                'Cuota Base',
                                deudaBaseTotal,
                              );
                              if (m != null) {
                                setModalState(() {
                                  pagarBase = true;
                                  montosManuales['Base'] = m;
                                });
                              }
                            }
                          } else {
                            setModalState(() {
                              pagarBase = false;
                              incluirInteresCuota = false;
                              montosManuales['Base'] = deudaBaseTotal;
                            });
                          }
                          recalcularDesdeChecks();
                        },
                      ),
                      if (deudaMesaTotal > 0.01)
                        _buildConceptoTile(
                          titulo: 'MESA EXTRA',
                          deuda: deudaMesaTotal,
                          isDark:
                              Theme.of(context).brightness == Brightness.dark,
                          selected: pagarMesa,
                          montoManual: montosManuales['Mesa'],
                          onChanged: (v) async {
                            if (v == true) {
                              double pureMesa =
                                  alumno.mesaExtraPrecio /
                                  (mCuotas > 0 ? mCuotas : 1);
                              int restMesa = mCuotas - mPagadas;
                              final choice = await _mostrarOpcionesPago(
                                context,
                                'Mesa Extra',
                                deudaMesaTotal,
                                cuotaUnica: pureMesa,
                                cuotasRestantes: restMesa,
                              );
                              if (choice == 'TOTAL') {
                                setModalState(() {
                                  pagarMesa = true;
                                  montosManuales['Mesa'] = deudaMesaTotal;
                                });
                              } else if (choice == 'UNICA') {
                                setModalState(() {
                                  pagarMesa = true;
                                  montosManuales['Mesa'] = pureMesa;
                                });
                              } else if (choice == 'VARIAS') {
                                final n = await _mostrarDialogoSeleccionCuotas(
                                  context,
                                  'Mesa Extra',
                                  restMesa,
                                );
                                if (n != null) {
                                  setModalState(() {
                                    pagarMesa = true;
                                    montosManuales['Mesa'] = pureMesa * n;
                                  });
                                }
                              } else if (choice == 'PARTE') {
                                final m = await preguntarMontoParcial(
                                  'Mesa Extra',
                                  deudaMesaTotal,
                                );
                                if (m != null) {
                                  setModalState(() {
                                    pagarMesa = true;
                                    montosManuales['Mesa'] = m;
                                  });
                                }
                              }
                            } else {
                              setModalState(() {
                                pagarMesa = false;
                                montosManuales.remove('Mesa');
                              });
                            }
                            recalcularDesdeChecks();
                          },
                        ),
                      if (deudaSillasTotal > 0.01)
                        _buildConceptoTile(
                          titulo: 'SILLAS EXTRAS',
                          deuda: deudaSillasTotal,
                          isDark:
                              Theme.of(context).brightness == Brightness.dark,
                          selected: pagarSillas,
                          montoManual: montosManuales['Sillas'],
                          onChanged: (v) async {
                            if (v == true) {
                              double pureSilla =
                                  alumno.sillasExtraPrecioTotal /
                                  (sCuotas > 0 ? sCuotas : 1);
                              int restSillas = sCuotas - sPagadas;

                              final choice = await _mostrarOpcionesPago(
                                context,
                                'Sillas Extras',
                                deudaSillasTotal,
                                cuotaUnica: pureSilla,
                                cuotasRestantes: restSillas,
                              );
                              if (choice == 'TOTAL') {
                                setModalState(() {
                                  pagarSillas = true;
                                  montosManuales['Sillas'] = deudaSillasTotal;
                                });
                              } else if (choice == 'UNICA') {
                                setModalState(() {
                                  pagarSillas = true;
                                  montosManuales['Sillas'] = pureSilla;
                                });
                              } else if (choice == 'VARIAS') {
                                final n = await _mostrarDialogoSeleccionCuotas(
                                  context,
                                  'Sillas Extras',
                                  restSillas,
                                );
                                if (n != null) {
                                  setModalState(() {
                                    pagarSillas = true;
                                    montosManuales['Sillas'] = pureSilla * n;
                                  });
                                }
                              } else if (choice == 'PARTE') {
                                final m = await preguntarMontoParcial(
                                  'Sillas Extras',
                                  deudaSillasTotal,
                                );
                                if (m != null) {
                                  setModalState(() {
                                    pagarSillas = true;
                                    montosManuales['Sillas'] = m;
                                  });
                                }
                              }
                            } else {
                              setModalState(() {
                                pagarSillas = false;
                                montosManuales.remove('Sillas');
                              });
                            }
                            recalcularDesdeChecks();
                          },
                        ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MONTO DE ENTREGA:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: Colors.grey,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: montoPagarCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [CurrencyInputFormatter()],
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFD4AF37),
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.attach_money_rounded,
                                      color: Color(0xFFD4AF37),
                                    ),
                                    hintText: '0,00',
                                    filled: true,
                                    fillColor: const Color(
                                      0xFFD4AF37,
                                    ).withValues(alpha: 0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    final m = CurrencyInputFormatter.parse(val);
                                    setModalState(() {
                                      recalcularDesdeMonto(m);
                                      pagarBase = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Cuota',
                                            ),
                                      );
                                      pagarMesa = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Mesa',
                                            ),
                                      );
                                      pagarSillas = previewConceptos.any(
                                        (c) =>
                                            !esLineaInteresMora(c) &&
                                            !esLineaCargoCanal(c) &&
                                            c['concepto'].toString().contains(
                                              'Sillas',
                                            ),
                                      );
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'DESC. LIQUIDACIÓN:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    color: Colors.blue,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: porcentajeDescuentoCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.percent_rounded,
                                      color: Colors.blue,
                                    ),
                                    hintText: '0',
                                    filled: true,
                                    fillColor: Colors.blue.withValues(
                                      alpha: 0.05,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onChanged: (val) {
                                    setModalState(() {
                                      recalcularDesdeChecks();
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (modoMedioPago == 'Transferencia' &&
                          informarPctTransferExterno)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Builder(
                            builder: (ctx) {
                              final liq = sumPreviewLiquidoConceptos();
                              if (liq <= 0.01) {
                                return const SizedBox.shrink();
                              }
                              final cargo =
                                  cargoSobreLiquidoTransferencia(liq);
                              if (cargo <= 0.01) {
                                return const SizedBox.shrink();
                              }
                              final canal = double.parse(
                                (liq + cargo).toStringAsFixed(2),
                              );
                              return Text(
                                'Transferencia total canal: ${canal.toCurrency()} '
                                '(liquidación ${liq.toCurrency()} + cargo '
                                '${cargo.toCurrency()}). Mismo total que MONTO DE ENTREGA.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue.shade800,
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: modoMedioPago,
                        decoration: InputDecoration(
                          labelText: 'Medio de pago',
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_rounded,
                          ),
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.black26
                              : Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Efectivo',
                            child: Text('Efectivo'),
                          ),
                          DropdownMenuItem(
                            value: 'Transferencia',
                            child: Text('Transferencia'),
                          ),
                          DropdownMenuItem(
                            value: 'Mixto',
                            child: Text('Mixto (efectivo + transferencia)'),
                          ),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          await prefsMedio.setString(
                            'medio_pago_cobro_masivo',
                            v,
                          );
                          setModalState(() {
                            modoMedioPago = v;
                            if (v == 'Mixto') {
                              previewConceptos.removeWhere(esLineaCargoCanal);
                              final sumL = previewConceptos.fold<double>(
                                0,
                                (s, c) =>
                                    s + (c['monto'] as num).toDouble(),
                              );
                              if (sumL > 0.01) {
                                final mitad = sumL / 2;
                                efectivoMixCtrl.text =
                                    mitad.toFormattedNumber();
                              } else {
                                final t = CurrencyInputFormatter.parse(
                                  montoPagarCtrl.text,
                                );
                                if (t > 0.01) {
                                  final mitad = t / 2;
                                  efectivoMixCtrl.text =
                                      mitad.toFormattedNumber();
                                } else {
                                  efectivoMixCtrl.clear();
                                  transferMixCtrl.clear();
                                }
                              }
                              finalizarPreviewConCargoCanal();
                            } else {
                              efectivoMixCtrl.clear();
                              transferMixCtrl.clear();
                              finalizarPreviewConCargoCanal();
                            }
                          });
                        },
                      ),
                      if (modoMedioPago == 'Mixto') ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: efectivoMixCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  labelText: 'Efectivo',
                                  prefixIcon: const Icon(
                                    Icons.payments_rounded,
                                    color: Color(0xFFD4AF37),
                                  ),
                                  filled: true,
                                  fillColor: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.06),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) => setModalState(
                                  finalizarPreviewConCargoCanal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: transferMixCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  labelText: 'Transferencia (total canal)',
                                  prefixIcon: const Icon(
                                    Icons.account_balance_rounded,
                                    color: Colors.blue,
                                  ),
                                  filled: true,
                                  fillColor: Colors.blue.withValues(
                                    alpha: 0.06,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) {
                                  setModalState(
                                    aplicarEdicionTransferenciaMixto,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Liquidación: efectivo + transferencia líquida = monto de entrega. '
                            'El campo Transferencia muestra el total por canal (líquido + cargo operador si aplica).',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                      if (modoMedioPago == 'Transferencia' ||
                          modoMedioPago == 'Mixto') ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: informarPctTransferExterno,
                          onChanged: (v) => setModalState(() {
                            informarPctTransferExterno = v ?? false;
                            recalcularDesdeChecks();
                          }),
                          title: const Text(
                            'Mostrar costo estimado del operador sobre transferencia',
                            style: TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            'En mixto, Transferencia = líquido + cargo ref. La liquidación sigue siendo el monto de entrega.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        if (informarPctTransferExterno) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment<String>(
                                    value: 'pct',
                                    label: Text('Por %'),
                                    icon: Icon(Icons.percent_rounded, size: 18),
                                  ),
                                  ButtonSegment<String>(
                                    value: 'pesos',
                                    label: Text(r'Por $'),
                                    icon: Icon(
                                      Icons.payments_outlined,
                                      size: 18,
                                    ),
                                  ),
                                ],
                                selected: {transferCargoModo},
                                onSelectionChanged: (Set<String> sel) {
                                  if (sel.isEmpty) return;
                                  setModalState(() {
                                    transferCargoModo = sel.first;
                                    recalcularDesdeChecks();
                                  });
                                },
                              ),
                            ),
                          ),
                          if (transferCargoModo == 'pct')
                            TextField(
                              controller: pctTransferInfoCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: '% informativo (p. ej. comisión MP)',
                                prefixIcon: const Icon(
                                  Icons.price_change_outlined,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black26
                                    : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) =>
                                  setModalState(recalcularDesdeChecks),
                            )
                          else
                            TextField(
                              controller: transferCargoMontoCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: InputDecoration(
                                labelText:
                                    'Monto estimado del cargo (referencia)',
                                hintText: '0,00',
                                prefixText: r'$ ',
                                prefixIcon: const Icon(
                                  Icons.attach_money_rounded,
                                  size: 20,
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black26
                                    : Colors.grey.shade50,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) =>
                                  setModalState(recalcularDesdeChecks),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Builder(
                              builder: (ctx) {
                                final mt = double.parse(
                                  montoTransferenciaParaCargoInforme()
                                      .clamp(0.0, double.infinity)
                                      .toStringAsFixed(2),
                                );
                                if (mt <= 0.01) {
                                  return Text(
                                    modoMedioPago == 'Mixto'
                                        ? 'Completá el monto en transferencia para ver la referencia en tiempo real.'
                                        : 'Completá el monto de entrega para ver la referencia en tiempo real.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                  );
                                }
                                if (transferCargoModo == 'pct') {
                                  final pctRaw = pctCargoInformeDesdeCampo();
                                  final pct = double.parse(
                                    pctRaw
                                        .clamp(0.0, 1000.0)
                                        .toStringAsFixed(4),
                                  );
                                  if (pct <= 0.001) {
                                    return Text(
                                      'Ingresá el % arriba para ver cuánto representa sobre ${mt.toCurrency()} en transferencia.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey.shade700,
                                      ),
                                    );
                                  }
                                  final estimado = double.parse(
                                    (mt * pct / 100.0).toStringAsFixed(2),
                                  );
                                  final pctStr =
                                      (pct - pct.round()).abs() < 0.001
                                      ? pct.round().toString()
                                      : pct.toStringAsFixed(2);
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(
                                        alpha: 0.06,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.blue.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Costo estimado sobre transferencia',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$pctStr% de ${mt.toCurrency()} ≈ ${estimado.toCurrency()}',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.blue.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Incluido en MONTO DE ENTREGA y en el desglose. '
                                          'Al confirmar, solo la liquidación actualiza saldos; el cargo es referencia de canal.',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                final montoFijo = double.parse(
                                  montoCargoInformeDesdeCampo()
                                      .clamp(0.0, double.infinity)
                                      .toStringAsFixed(2),
                                );
                                if (montoFijo <= 0.01) {
                                  return Text(
                                    'Ingresá el monto en pesos arriba para fijar la referencia (equivale a un % sobre ${mt.toCurrency()}).',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                  );
                                }
                                final eqPct = mt > 0.01
                                    ? (100.0 * montoFijo / mt)
                                    : 0.0;
                                final eqStr = eqPct > 0.01 && eqPct <= 999.0
                                    ? '~${eqPct.toStringAsFixed(1)}% de ${mt.toCurrency()}'
                                    : '';
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.blue.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Costo estimado sobre transferencia',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        eqStr.isNotEmpty
                                            ? '${montoFijo.toCurrency()} ($eqStr)'
                                            : montoFijo.toCurrency(),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Incluido en MONTO DE ENTREGA y en el desglose. '
                                        'Al confirmar, solo la liquidación actualiza saldos; el cargo es referencia de canal.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                      if (montoPagarCtrl.text.isNotEmpty &&
                          CurrencyInputFormatter.parse(montoPagarCtrl.text) >
                              0.01)
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'DESGLOSE LIMPIO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      color: Colors.grey,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final total =
                                          CurrencyInputFormatter.parse(
                                            montoPagarCtrl.text,
                                          );
                                      final double interesDist =
                                          (incluirInteresCuota &&
                                              moraPendienteUi > 0.01)
                                          ? montoMoraLineaIngresado()
                                          : 0.0;
                                      final capitalParaDialogo =
                                          (total - interesDist).clamp(
                                            0.0,
                                            double.infinity,
                                          );
                                      final result =
                                          await _mostrarDialogoDistribucionManual(
                                            context: context,
                                            total: capitalParaDialogo,
                                            deudaBase: deudaBaseTotal,
                                            deudaMesa: deudaMesaTotal,
                                            deudaSillas: deudaSillasTotal,
                                            currentBase: montosManuales['Base'],
                                            currentMesa: montosManuales['Mesa'],
                                            currentSillas:
                                                montosManuales['Sillas'],
                                          );
                                      if (result != null) {
                                        setModalState(() {
                                          if (result['Base']! > 0)
                                            montosManuales['Base'] =
                                                result['Base']!;
                                          else
                                            montosManuales['Base'] =
                                                deudaBaseTotal;
                                          if (result['Mesa']! > 0)
                                            montosManuales['Mesa'] =
                                                result['Mesa']!;
                                          else
                                            montosManuales.remove('Mesa');
                                          if (result['Sillas']! > 0)
                                            montosManuales['Sillas'] =
                                                result['Sillas']!;
                                          else
                                            montosManuales.remove('Sillas');
                                          recalcularDesdeMonto(
                                            total,
                                            manually: true,
                                          );
                                        });
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'EDITAR',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: const Color(0xFFD4AF37),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ...previewConceptos.map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '• ${c['concepto']}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        (c['monto'] as num)
                                            .toDouble()
                                            .toCurrency(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              (() {
                                final double sum = previewConceptos.fold(
                                  0,
                                  (s, c) => s + (c['monto'] as num).toDouble(),
                                );
                                final double totalTotal =
                                    CurrencyInputFormatter.parse(
                                      montoPagarCtrl.text,
                                    );
                                final double diff = totalTotal - sum;
                                if (diff.abs() > 0.01) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'REMANENTE:',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        Text(
                                          diff.toCurrency(),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              })(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final montoIngresado = CurrencyInputFormatter.parse(
                      montoPagarCtrl.text,
                    );
                    if (montoIngresado <= 0) return;
                    final double sumLiquidoCobro = previewConceptos
                        .where((c) => !esLineaCargoCanal(c))
                        .fold<double>(
                          0,
                          (s, c) => s + (c['monto'] as num).toDouble(),
                        );
                    final double interesIncluido = previewConceptos
                        .where(esLineaInteresMora)
                        .fold(
                          0.0,
                          (s, c) => s + (c['monto'] as num).toDouble(),
                        );
                    final double topePermitido =
                        alumno.saldoDeudor + interesIncluido;
                    if (sumLiquidoCobro > topePermitido + 0.01) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'ERROR: El monto excede lo permitido (${topePermitido.toCurrency()} = saldo ${alumno.saldoDeudor.toCurrency()}'
                            '${interesIncluido > 0.01 ? ' + interés ${interesIncluido.toCurrency()}' : ''}).',
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }

                    if (previewConceptos.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Seleccioná al menos un concepto de pago.',
                          ),
                          backgroundColor: Colors.orangeAccent,
                        ),
                      );
                      return;
                    }

                    double parteEfectivo = montoIngresado;
                    double parteTransferencia = 0;
                    double transferCanalMixtoPdf = 0;
                    if (modoMedioPago == 'Mixto') {
                      parteEfectivo = CurrencyInputFormatter.parse(
                        efectivoMixCtrl.text,
                      );
                      transferCanalMixtoPdf = CurrencyInputFormatter.parse(
                        transferMixCtrl.text,
                      ).clamp(0.0, double.infinity);
                      parteTransferencia = liquidoTransferenciaDesdeTotalMixto(
                        transferCanalMixtoPdf,
                      );
                      if ((parteEfectivo + parteTransferencia - sumLiquidoCobro)
                              .abs() >
                          0.03) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'La parte liquidada — efectivo (${parteEfectivo.toCurrency()}) '
                              '+ transferencia líquida (${parteTransferencia.toCurrency()}) — debe '
                              'coincidir con el desglose (${sumLiquidoCobro.toCurrency()}). '
                              'Monto total (con canal): ${montoIngresado.toCurrency()}; '
                              'transferencia canal: ${transferCanalMixtoPdf.toCurrency()}.',
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                    } else if (modoMedioPago == 'Transferencia') {
                      parteEfectivo = 0;
                      parteTransferencia = sumLiquidoCobro;
                    }

                    // 1. CALCULOS MATEMÁTICOS EXACTOS Y BLINDADOS
                    int nuevasBase = 0;
                    int nuevasMesa = 0;
                    int nuevasSillas = 0;
                    double totalDeducidoBruto = 0.0;

                    double grossMesaPagado = 0.0;
                    double grossSillasPagado = 0.0;

                    for (var conc in previewConceptos) {
                      if (esLineaCargoCanal(conc)) continue;
                      if (esLineaInteresMora(conc)) continue;
                      final String cTexto = conc['concepto'] as String;
                      final int cCuotas =
                          ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
                      final double cGross = (conc['gross'] as num).toDouble();
                      if (cTexto.toUpperCase().contains('BASE'))
                        nuevasBase += cCuotas;
                      if (cTexto.toUpperCase().contains('MESA')) {
                        nuevasMesa += cCuotas;
                        grossMesaPagado += cGross;
                      }
                      if (cTexto.toUpperCase().contains('SILLA')) {
                        nuevasSillas += cCuotas;
                        grossSillasPagado += cGross;
                      }

                      totalDeducidoBruto += cGross;
                    }

                    double saldoRestanteCalculado =
                        alumno.saldoDeudor - totalDeducidoBruto;
                    double saldoRestante = double.parse(
                      saldoRestanteCalculado.toStringAsFixed(2),
                    ).clamp(0.0, double.infinity);

                    int currentBasePagadas = (cPagadas + nuevasBase).clamp(
                      0,
                      tCuotas,
                    );
                    int currentMesaPagadas = (mPagadas + nuevasMesa).clamp(
                      0,
                      mCuotas > 0 ? mCuotas : 1,
                    );
                    int currentSillasPagadas = (sPagadas + nuevasSillas).clamp(
                      0,
                      sCuotas > 0 ? sCuotas : 1,
                    );

                    if (saldoRestante <= 0.01) {
                      currentBasePagadas = tCuotas;
                      currentMesaPagadas =
                          (alumno.mesaExtraPrecio > 0 && mCuotas > 0)
                          ? mCuotas
                          : 0;
                      currentSillasPagadas =
                          (alumno.sillasExtraPrecioTotal > 0 && sCuotas > 0)
                          ? sCuotas
                          : 0;
                    }

                    List<Map<String, dynamic>> conceptosFinales = [];
                    int contadorBaseFinal = 0;
                    int contadorMesaFinal = 0;
                    int contadorSillasFinal = 0;
                    for (var conc in previewConceptos) {
                      // Cargo canal: incluirlo como concepto visible en el PDF
                      if (esLineaCargoCanal(conc)) {
                        final double cargoMonto = double.parse(
                          ((conc['monto'] as num).toDouble())
                              .toStringAsFixed(2),
                        );
                        if (cargoMonto > 0.01) {
                          conceptosFinales.add({
                            'concepto':
                                'Cargo oper. transferencia (MP u otro)',
                            'monto': cargoMonto,
                          });
                        }
                        continue;
                      }
                      final String cTexto = conc['concepto'] as String;
                      final double cMontoRaw = (conc['monto'] as num)
                          .toDouble();
                      final double cMonto = double.parse(
                        cMontoRaw.toStringAsFixed(2),
                      );
                      final int cCuotasConc =
                          ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);

                      String cRico = cTexto;
                      if (esLineaInteresMora(conc)) {
                        cRico = 'Interés mora (cuota base — este cobro)';
                      } else if (cTexto.toUpperCase().contains('MESA')) {
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
                      } else if (cTexto.toUpperCase().contains('SILLA')) {
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
                      } else if (cTexto.toUpperCase().contains('BASE')) {
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

                      conceptosFinales.add({
                        'concepto': cRico,
                        'monto': cMonto,
                      });
                    }

                    // 2. CREACIÓN DEL CLON LOCAL INMEDIATO (copyWith directo)
                    final alumnoFresco = alumno.copyWith(
                      saldoDeudor: saldoRestante,
                      cuotasPagadas: currentBasePagadas,
                      mesaExtraCuotasPagadas: currentMesaPagadas,
                      sillasExtraCuotasPagadas: currentSillasPagadas,
                      mesaExtraPagado:
                          (alumno.mesaExtraPagado) + grossMesaPagado,
                      sillasExtraPagado:
                          (alumno.sillasExtraPagado) + grossSillasPagado,
                    );

                    // Actualizamos la pantalla de fondo al instante (sin esperar a Supabase)
                    final index = _alumnos.indexWhere((a) => a.id == alumno.id);
                    if (index != -1) {
                      final moraEste = previewConceptos
                          .where(esLineaInteresMora)
                          .fold<double>(
                            0,
                            (s, c) => s + (c['monto'] as num).toDouble(),
                          );
                      setState(() {
                        // Snapshot pre-lote: moraPendienteUi ya captura el
                        // interés acumulado ANTES de avanzar cuotas_pagadas.
                        // Equivale al snapshot que hace el repo en la rama base.
                        double trackedNuevo = moraPendienteUi;
                        if (moraEste > 0.01) {
                          trackedNuevo = (moraPendienteUi - moraEste)
                              .clamp(0.0, double.infinity);
                          _moraCobradaPorContrato[alumno.id] =
                              (_moraCobradaPorContrato[alumno.id] ?? 0.0) +
                                  moraEste;
                        }
                        _alumnos[index] = alumnoFresco.copyWith(
                          moraPendienteTracked: trackedNuevo,
                        );
                      });
                    }

                    await prefsMedio.setString(
                      'medio_pago_cobro_masivo',
                      modoMedioPago,
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_pct_transfer_info',
                      pctTransferInfoCtrl.text.trim(),
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_transfer_cargo_modo',
                      transferCargoModo,
                    );
                    await prefsMedio.setString(
                      'cobro_masivo_transfer_cargo_monto',
                      transferCargoMontoCtrl.text.trim(),
                    );
                    await prefsMedio.setBool(
                      'cobro_masivo_informar_pct_transfer',
                      informarPctTransferExterno,
                    );

                    final double pctCargoInforme =
                        double.tryParse(
                          pctTransferInfoCtrl.text.replaceAll(',', '.').trim(),
                        ) ??
                        0;
                    final double montoCargoInformeParsed =
                        CurrencyInputFormatter.parse(
                          transferCargoMontoCtrl.text,
                        );

                    // Cerramos la ventana de cobro y disparamos el recibo PDF con el CLON PERFECTO
                    if (context.mounted) {
                      Navigator.pop(context, true);

                      _imprimirReciboAlumno(
                        alumnoFresco,
                        montoPagado: montoIngresado,
                        saldoPendiente: saldoRestante,
                        conceptosPagados: conceptosFinales,
                        fechaManual: DateTime.now(),
                        medioPago: modoMedioPago == 'Mixto'
                            ? 'Mixto'
                            : modoMedioPago,
                        montoEfectivoDetalle: modoMedioPago == 'Mixto'
                            ? parteEfectivo
                            : null,
                        montoTransferenciaDetalle: modoMedioPago == 'Mixto'
                            ? transferCanalMixtoPdf
                            : null,
                        informarCargoTransferenciaExterno:
                            informarPctTransferExterno,
                        porcentajeCargoTransferenciaExterno:
                            informarPctTransferExterno &&
                                transferCargoModo == 'pct' &&
                                pctCargoInforme > 0.01
                            ? pctCargoInforme
                            : null,
                        montoCargoTransferenciaInformado:
                            informarPctTransferExterno &&
                                transferCargoModo == 'pesos' &&
                                montoCargoInformeParsed > 0.01
                            ? montoCargoInformeParsed
                            : null,
                        skipDbRefresh:
                            true, // EXIGE que se use el clon local, ignorando los tiempos de Supabase
                      );
                    }

                    // 3. SINCRONIZACIÓN DE LA BASE DE DATOS EN SEGUNDO PLANO (SILENCIOSA)
                    Future.microtask(() async {
                      try {
                        final repo = ref.read(contratosRepositoryProvider);
                        final descStr = porcentajeDescuentoCtrl.text;
                        final tIng = parteEfectivo + parteTransferencia;
                        final sumNetas = previewConceptos
                            .where((c) => !esLineaCargoCanal(c))
                            .fold<double>(
                              0,
                              (s, c) =>
                                  s + (c['monto'] as num).toDouble(),
                            );

                        Future<void> registrarLineaUna(
                          Map<String, dynamic> conc,
                        ) async {
                          final cTexto = conc['concepto'] as String;
                          final monto = (conc['monto'] as num).toDouble();
                          final gross =
                              (conc['gross'] as num?)?.toDouble() ?? monto;
                          final cCuotas =
                              ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(
                                0,
                                99,
                              );
                          final lineKind = conc['lineKind'] as String?;

                          // Cargo canal: se registra como ingreso real
                          // (Transferencia) para que figure en cierre de caja,
                          // pero con gross=0 para no afectar saldo del alumno.
                          if (lineKind == 'cargo_canal_ref') {
                            if (monto > 0.004) {
                              await repo.registrarPago(
                                contratoId: alumno.id,
                                monto: monto,
                                concepto: cTexto,
                                montoADescontarDeSaldo: 0,
                                descuentoPorcentaje: 0,
                                cuotasLiquidadas: 0,
                                medioPago: 'Transferencia',
                                lineKind: lineKind,
                              );
                            }
                            return;
                          }

                          if (tIng < 0.01 || sumNetas < 0.01) return;

                          double mE;
                          double mT;
                          double gE;
                          double gT;
                          if (modoMedioPago == 'Mixto') {
                            final rE = parteEfectivo / tIng;
                            mE = double.parse((monto * rE).toStringAsFixed(2));
                            mT = double.parse((monto - mE).toStringAsFixed(2));
                            gE = double.parse((gross * rE).toStringAsFixed(2));
                            gT = double.parse((gross - gE).toStringAsFixed(2));
                          } else if (modoMedioPago == 'Efectivo') {
                            mE = monto;
                            mT = 0;
                            gE = gross;
                            gT = 0;
                          } else {
                            mE = 0;
                            mT = monto;
                            gE = 0;
                            gT = gross;
                          }

                          Future<void> uno(
                            double m,
                            double mg,
                            String med,
                            int cq,
                          ) async {
                            if (m <= 0.004) return;
                            await repo.registrarPago(
                              contratoId: alumno.id,
                              monto: m,
                              concepto: cTexto,
                              montoADescontarDeSaldo: mg,
                              descuentoPorcentaje:
                                  double.tryParse(descStr) ?? 0,
                              cuotasLiquidadas: cq,
                              medioPago: med,
                              lineKind: lineKind,
                              // Snapshot pre-lote: evita que el avance de
                              // cuotas_pagadas (por la línea base ya
                              // persistida) borre el remanente de mora.
                              moraPendienteAntesDeLote:
                                  lineKind == kLineKindInteresMora
                                      ? moraPendienteUi
                                      : null,
                            );
                          }

                          if (mE <= 0.004 && mT > 0.004) {
                            await uno(mT, gT, 'Transferencia', cCuotas);
                          } else if (mT <= 0.004 && mE > 0.004) {
                            await uno(mE, gE, 'Efectivo', cCuotas);
                          } else if (mE >= mT) {
                            await uno(mE, gE, 'Efectivo', cCuotas);
                            await uno(mT, gT, 'Transferencia', 0);
                          } else {
                            await uno(mT, gT, 'Transferencia', cCuotas);
                            await uno(mE, gE, 'Efectivo', 0);
                          }
                        }

                        for (final conc in previewConceptos) {
                          await registrarLineaUna(conc);
                        }

                        final Map<String, dynamic> directUpdates = {
                          'saldo_deudor': saldoRestante,
                        };

                        if (saldoRestante <= 0.01) {
                          directUpdates['cuotas_pagadas'] = currentBasePagadas;
                          directUpdates['mesa_extra_cuotas_pagadas'] =
                              currentMesaPagadas;
                          directUpdates['sillas_extra_cuotas_pagadas'] =
                              currentSillasPagadas;
                        } else {
                          if (nuevasBase > 0)
                            directUpdates['cuotas_pagadas'] =
                                currentBasePagadas;
                          if (nuevasMesa > 0)
                            directUpdates['mesa_extra_cuotas_pagadas'] =
                                currentMesaPagadas;
                          if (nuevasSillas > 0)
                            directUpdates['sillas_extra_cuotas_pagadas'] =
                                currentSillasPagadas;
                        }

                        // Persistir montos pagados de extras para mantener sync exacto
                        if (grossMesaPagado > 0.01) {
                          directUpdates['mesa_extra_pagado'] =
                              double.parse(((alumno.mesaExtraPagado ?? 0) + grossMesaPagado).toStringAsFixed(2));
                        }
                        if (grossSillasPagado > 0.01) {
                          directUpdates['sillas_extra_pagado'] =
                              double.parse(((alumno.sillasExtraPagado ?? 0) + grossSillasPagado).toStringAsFixed(2));
                        }

                        // Persistir mora snapshot para que no se pierda al sincronizar
                        directUpdates['mora_pendiente_tracked'] =
                            double.parse(moraPendienteUi.toStringAsFixed(2));

                        await repo.actualizarContrato(alumno.id, directUpdates);

                        // Escaneo final automático sin interrumpir al usuario
                        await _forzarAuditoriaInteligente(silencioso: true);
                      } catch (e) {
                        debugPrint('Registro asíncrono demorado: $e');
                      }
                    });
                  },
                  label: const Text(
                    'CONFIRMAR PAGO',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    moraMontoCobroCtrl.dispose();
    efectivoMixCtrl.dispose();
    transferMixCtrl.dispose();
    pctTransferInfoCtrl.dispose();
    transferCargoMontoCtrl.dispose();

    if (mounted && result == true) {
      _refreshAlumnos();
    }
  }
