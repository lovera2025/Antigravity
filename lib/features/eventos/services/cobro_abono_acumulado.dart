import '../../../core/utils/pago_interes_mora.dart';

import 'mesas_extra_utils.dart';

/// Clase de concepto del plan (alineado a [ContratosRepository.recalcularProgresoContrato]).
enum CobroConceptoClase { base, mesa, sillas }

/// Resultado de evaluar un cobro con abonos parciales previos acumulados.
class AvanceCuotaConAbonos {
  /// Cuotas **nuevas** que liquida [grossActual] (delta, no total histórico).
  final int cuotasLiquidadas;
  final double restoAbono;

  /// Cuotas completas totales tras sumar este cobro (solo para rotulado).
  final int cuotasCompletasDespues;

  const AvanceCuotaConAbonos({
    required this.cuotasLiquidadas,
    required this.restoAbono,
    required this.cuotasCompletasDespues,
  });

  bool get esAbonoSolo => cuotasLiquidadas == 0;
  bool get cierraCuotaExacta =>
      cuotasLiquidadas >= 1 && restoAbono.abs() < 0.1;
  bool get cierraConAdelanto =>
      cuotasLiquidadas >= 1 && restoAbono >= 0.1;
}

/// Tolerancia alineada a [ContratosRepository.recalcularProgresoContrato].
const double kToleranciaCuotaPura = 0.1;

enum EstadoCuotaPlan { pagada, parcial, pendiente }

/// Estado de una cuota del plan (base / mesa / sillas) derivado del acumulado FIFO.
class CuotaPlanDetalle {
  final int numero;
  final double montoCuota;
  final double pagadoEnCuota;
  final EstadoCuotaPlan estado;

  const CuotaPlanDetalle({
    required this.numero,
    required this.montoCuota,
    required this.pagadoEnCuota,
    required this.estado,
  });

  double get faltante =>
      (montoCuota - pagadoEnCuota).clamp(0.0, montoCuota);

  bool get seleccionable => estado != EstadoCuotaPlan.pagada;
}

/// Desglose cuota a cuota desde el gross histórico (sin tocar DB).
List<CuotaPlanDetalle> desgloseCuotasPlan({
  required double grossHistorico,
  required double cuotaPura,
  required int totalCuotas,
}) {
  if (totalCuotas <= 0) return const [];

  if (cuotaPura <= 0.001) {
    if (grossHistorico <= 0.01) return const [];
    return [
      CuotaPlanDetalle(
        numero: 1,
        montoCuota: grossHistorico,
        pagadoEnCuota: grossHistorico,
        estado: EstadoCuotaPlan.pagada,
      ),
    ];
  }

  final completas =
      cuotasCompletasDesdeGrossAcumulado(grossHistorico, cuotaPura);
  final resto = double.parse(
    (grossHistorico - completas * cuotaPura).toStringAsFixed(4),
  );

  return List.generate(totalCuotas, (i) {
    final n = i + 1;
    if (n <= completas) {
      return CuotaPlanDetalle(
        numero: n,
        montoCuota: cuotaPura,
        pagadoEnCuota: cuotaPura,
        estado: EstadoCuotaPlan.pagada,
      );
    }
    if (n == completas + 1 && resto > kToleranciaCuotaPura) {
      return CuotaPlanDetalle(
        numero: n,
        montoCuota: cuotaPura,
        pagadoEnCuota: resto,
        estado: EstadoCuotaPlan.parcial,
      );
    }
    return CuotaPlanDetalle(
      numero: n,
      montoCuota: cuotaPura,
      pagadoEnCuota: 0,
      estado: EstadoCuotaPlan.pendiente,
    );
  });
}

/// Primera cuota con entrega parcial en curso, si existe.
CuotaPlanDetalle? cuotaParcialEnCurso({
  required double grossHistorico,
  required double cuotaPura,
  required int totalCuotas,
}) {
  for (final c in desgloseCuotasPlan(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
    totalCuotas: totalCuotas,
  )) {
    if (c.estado == EstadoCuotaPlan.parcial) return c;
  }
  return null;
}

bool tieneEntregaParcialEnCurso({
  required double grossHistorico,
  required double cuotaPura,
  required int totalCuotas,
}) =>
    cuotaParcialEnCurso(
      grossHistorico: grossHistorico,
      cuotaPura: cuotaPura,
      totalCuotas: totalCuotas,
    ) !=
    null;

/// Suma faltantes de cuotas seleccionadas (consecutivas desde la primera incompleta).
double montoFaltanteCuotasSeleccionadas(
  Set<int> seleccionadas,
  List<CuotaPlanDetalle> desglose,
) {
  var sum = 0.0;
  for (final c in desglose) {
    if (seleccionadas.contains(c.numero)) {
      sum += c.faltante;
    }
  }
  return double.parse(sum.toStringAsFixed(2));
}

int? primeraCuotaSeleccionable(List<CuotaPlanDetalle> desglose) {
  for (final c in desglose) {
    if (c.seleccionable) return c.numero;
  }
  return null;
}

/// Marca / desmarca respetando bloque consecutivo desde la primera incompleta.
Set<int> alternarSeleccionCuotaPlan({
  required int numero,
  required Set<int> seleccionActual,
  required List<CuotaPlanDetalle> desglose,
}) {
  final primera = primeraCuotaSeleccionable(desglose);
  if (primera == null || numero < primera) return seleccionActual;

  final out = Set<int>.from(seleccionActual);
  if (out.contains(numero)) {
    out.removeWhere((n) => n >= numero);
  } else {
    for (final c in desglose) {
      if (c.numero >= primera && c.numero <= numero && c.seleccionable) {
        out.add(c.numero);
      }
    }
  }
  return out;
}

String rotuloEntregaParcial(String detalleCuota) =>
    'Entrega parcial — $detalleCuota';

/// Rotulo de cuota liquidada. [cierraEntregaParcialPrevio] agrega "— Completada"
/// solo cuando este cobro cierra una entrega parcial previa (no cuota entera de una).
/// Sin palabras entrega/parcial/abono/adelanto para no romper recalcularProgresoContrato.
String rotuloCuotaLiquidada({
  required String etiqueta,
  required int numeroCuota,
  required int totalCuotas,
  required bool cierraEntregaParcialPrevio,
}) {
  final base = '$etiqueta ($numeroCuota/$totalCuotas)';
  return cierraEntregaParcialPrevio ? '$base — Completada' : base;
}

bool habiaEntregaParcialEnCurso({
  required double grossHistorico,
  required double cuotaPura,
}) {
  if (cuotaPura <= 0.001 || grossHistorico <= 0.01) return false;
  return montoAcumuladoCuotaIncompleta(
        grossHistorico: grossHistorico,
        cuotaPura: cuotaPura,
      ) >
      kToleranciaCuotaPura;
}

/// Monto ya abonado en la cuota incompleta vigente (antes del cobro actual).
double montoAcumuladoCuotaIncompleta({
  required double grossHistorico,
  required double cuotaPura,
}) {
  if (cuotaPura <= 0.001 || grossHistorico <= 0.01) return 0;
  final completas =
      cuotasCompletasDesdeGrossAcumulado(grossHistorico, cuotaPura);
  return double.parse(
    (grossHistorico - completas * cuotaPura).toStringAsFixed(2),
  );
}

double montoSaldoRestanteCuotaIncompleta({
  required double grossHistorico,
  required double cuotaPura,
}) {
  final acum = montoAcumuladoCuotaIncompleta(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
  );
  return double.parse(
    (cuotaPura - acum).clamp(0.0, cuotaPura).toStringAsFixed(2),
  );
}

/// Leyenda PDF/preview al cerrar una entrega parcial (opción D).
String subtextoCuotaCompletadaEntregaParcial({
  required double montoEntregaParcialPrevia,
  required double montoEsteCobro,
}) {
  return 'Entrega parcial previa: \$${_fmtMonto(montoEntregaParcialPrevia)}. '
      'Este cobro: \$${_fmtMonto(montoEsteCobro)} (saldo restante). Cuota al día.';
}

String? subtextoSiCierraEntregaParcial({
  required double grossHistorico,
  required double grossEsteCobro,
  required double cuotaPura,
}) {
  if (!habiaEntregaParcialEnCurso(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
  )) {
    return null;
  }
  final previa = montoAcumuladoCuotaIncompleta(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
  );
  final saldo = montoSaldoRestanteCuotaIncompleta(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
  );
  final este = double.parse(
    (grossEsteCobro <= saldo + 0.01 ? grossEsteCobro : saldo).toStringAsFixed(2),
  );
  if (este <= 0.01) return null;
  return subtextoCuotaCompletadaEntregaParcial(
    montoEntregaParcialPrevia: previa,
    montoEsteCobro: este,
  );
}

/// Cómo eligió el operador liquidar este concepto en el modal de cobro.
enum ModoPagoConceptoTipo { total, cuotas, parcialLibre }

class ModoPagoConcepto {
  final ModoPagoConceptoTipo tipo;
  final Set<int>? cuotasSeleccionadas;

  const ModoPagoConcepto({
    required this.tipo,
    this.cuotasSeleccionadas,
  });
}

class LineaRepartoCuota {
  final int numeroCuota;
  final double gross;
  final bool cierraCuota;
  final double faltanteDespues;

  const LineaRepartoCuota({
    required this.numeroCuota,
    required this.gross,
    required this.cierraCuota,
    required this.faltanteDespues,
  });
}

class LineaPreviewDesglose {
  final String concepto;
  final String? subtexto;
  final double gross;
  final int cuotasLiquidadas;

  const LineaPreviewDesglose({
    required this.concepto,
    this.subtexto,
    required this.gross,
    required this.cuotasLiquidadas,
  });
}

/// Reparte [gross] en cuotas del plan (FIFO). [soloEstasCuotas] limita el reparto al modo checkbox.
List<LineaRepartoCuota> repartirGrossEnCuotasPlan({
  required double gross,
  required List<CuotaPlanDetalle> desglose,
  Set<int>? soloEstasCuotas,
}) {
  if (gross <= 0.011) return const [];

  var resto = double.parse(gross.toStringAsFixed(2));
  final out = <LineaRepartoCuota>[];

  Iterable<CuotaPlanDetalle> objetivos;
  if (soloEstasCuotas != null && soloEstasCuotas.isNotEmpty) {
    objetivos = desglose.where(
      (c) => soloEstasCuotas.contains(c.numero) && c.seleccionable,
    );
  } else {
    objetivos = desglose.where((c) => c.seleccionable);
  }

  for (final c in objetivos) {
    if (resto <= 0.011) break;
    final falt = c.faltante;
    if (falt <= 0.011) continue;
    // Cada cuota usa solo su faltante vigente; no arrastrar parciales previos.
    final aplica = resto >= falt - 0.01 ? falt : resto;
    final aplicaR = double.parse(aplica.toStringAsFixed(2));
    final faltDespues = double.parse(
      (falt - aplicaR).clamp(0.0, falt).toStringAsFixed(2),
    );
    out.add(
      LineaRepartoCuota(
        numeroCuota: c.numero,
        gross: aplicaR,
        cierraCuota: faltDespues <= 0.01,
        faltanteDespues: faltDespues,
      ),
    );
    resto = double.parse((resto - aplicaR).toStringAsFixed(2));
  }
  return out;
}

String _subtextoCuotaIncompleta({
  required double grossLinea,
  required double montoCuota,
  required double faltanteDespues,
}) {
  final acum = double.parse((montoCuota - faltanteDespues).toStringAsFixed(2));
  return 'Acumulado \$${_fmtMonto(acum)} de \$${_fmtMonto(montoCuota)} · '
      'faltan \$${_fmtMonto(faltanteDespues)}';
}

String _fmtMonto(double v) {
  return fmtMontoRotuloCobro(v);
}

/// Formato AR simple para rotulos de cobro (sin depender de UI).
String fmtMontoRotuloCobro(double v) {
  final abs = v.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${v < 0 ? '-' : ''}${buf},${parts[1]}';
}

/// Arma líneas de desglose según modo del operador (cuotas / parcial libre / total).
List<LineaPreviewDesglose> lineasPreviewDesglosePlan({
  required ModoPagoConceptoTipo modo,
  required Set<int>? cuotasSeleccionadas,
  required double grossTotal,
  required double cuotaPura,
  required int totalCuotas,
  required double grossHistorico,
  required String etiqueta,
}) {
  if (grossTotal <= 0.011) return const [];

  if (cuotaPura <= 0.001) {
    return [
      LineaPreviewDesglose(
        concepto: etiqueta,
        gross: grossTotal,
        cuotasLiquidadas: 1,
      ),
    ];
  }

  final desglose = desgloseCuotasPlan(
    grossHistorico: grossHistorico,
    cuotaPura: cuotaPura,
    totalCuotas: totalCuotas,
  );

  if (modo == ModoPagoConceptoTipo.parcialLibre) {
    CuotaPlanDetalle? objetivo;
    for (final c in desglose) {
      if (c.seleccionable) {
        objetivo = c;
        break;
      }
    }
    objetivo ??= desglose.isNotEmpty ? desglose.last : null;
    if (objetivo == null) {
      return [
        LineaPreviewDesglose(
          concepto: rotuloEntregaParcial(etiqueta),
          gross: grossTotal,
          cuotasLiquidadas: 0,
        ),
      ];
    }
    // Si el parcial supera el faltante de la cuota en curso, repartir FIFO
    // (completada + parcial/adelanto siguientes). Antes se etiquetaba todo
    // el monto como una sola línea "— Completada".
    if (grossTotal > objetivo.faltante + 0.01) {
      // cae al reparto compartido abajo (sin limitar a una sola cuota)
    } else {
      final faltDespues = double.parse(
        (objetivo.faltante - grossTotal)
            .clamp(0.0, objetivo.faltante)
            .toStringAsFixed(2),
      );
      final cierra = faltDespues <= 0.01;
      final habiaParcial = objetivo.estado == EstadoCuotaPlan.parcial;
      final concepto = cierra
          ? rotuloCuotaLiquidada(
              etiqueta: etiqueta,
              numeroCuota: objetivo.numero,
              totalCuotas: totalCuotas,
              cierraEntregaParcialPrevio: habiaParcial,
            )
          : rotuloEntregaParcial(
              '$etiqueta (${objetivo.numero}/$totalCuotas)',
            );
      String? subtexto;
      if (cierra && habiaParcial) {
        subtexto = subtextoCuotaCompletadaEntregaParcial(
          montoEntregaParcialPrevia: objetivo.pagadoEnCuota,
          montoEsteCobro: grossTotal,
        );
      } else if (!cierra) {
        subtexto = 'Faltan \$${_fmtMonto(faltDespues)} para completar';
      }
      return [
        LineaPreviewDesglose(
          concepto: concepto,
          subtexto: subtexto,
          gross: grossTotal,
          cuotasLiquidadas: cierra ? 1 : 0,
        ),
      ];
    }
  }

  final soloCuotas = modo == ModoPagoConceptoTipo.cuotas
      ? cuotasSeleccionadas
      : null;
  final reparto = repartirGrossEnCuotasPlan(
    gross: grossTotal,
    desglose: desglose,
    soloEstasCuotas: soloCuotas,
  );

  if (reparto.isEmpty) {
    return [
      LineaPreviewDesglose(
        concepto: etiqueta,
        gross: grossTotal,
        cuotasLiquidadas: 0,
      ),
    ];
  }

  return reparto.map((r) {
    final cuotaAntes = desglose.firstWhere((c) => c.numero == r.numeroCuota);
    final habiaParcial = cuotaAntes.estado == EstadoCuotaPlan.parcial;
    final concepto = r.cierraCuota
        ? rotuloCuotaLiquidada(
            etiqueta: etiqueta,
            numeroCuota: r.numeroCuota,
            totalCuotas: totalCuotas,
            cierraEntregaParcialPrevio: habiaParcial,
          )
        : rotuloEntregaParcial(
            '$etiqueta (${r.numeroCuota}/$totalCuotas)',
          );
    String? subtexto;
    if (r.cierraCuota && habiaParcial) {
      subtexto = subtextoCuotaCompletadaEntregaParcial(
        montoEntregaParcialPrevia: cuotaAntes.pagadoEnCuota,
        montoEsteCobro: r.gross,
      );
    } else if (!r.cierraCuota) {
      subtexto = _subtextoCuotaIncompleta(
        grossLinea: r.gross,
        montoCuota: cuotaPura,
        faltanteDespues: r.faltanteDespues,
      );
    }
    return LineaPreviewDesglose(
      concepto: concepto,
      subtexto: subtexto,
      gross: r.gross,
      cuotasLiquidadas: r.cierraCuota ? 1 : 0,
    );
  }).toList();
}

int cuotasCompletasDesdeGrossAcumulado(double gross, double cuotaPura) {
  if (cuotaPura <= 0.001) {
    return gross > 0.01 ? 1 : 0;
  }
  return ((gross + kToleranciaCuotaPura) / cuotaPura).floor().clamp(0, 99);
}

bool pagoCuentaParaClaseCobro(
  Map<String, dynamic> pago,
  CobroConceptoClase clase,
) {
  if (((pago['anulado'] as num?)?.toInt() ?? 0) != 0) return false;

  final lk = (pago['line_kind'] as String?)?.trim();
  final concepto = pago['concepto']?.toString() ?? '';

  if (lk == kLineKindInteresMora ||
      lk == kLineKindCargoCanal ||
      esPagoInteresMoraPorConcepto(concepto) ||
      esPagoCargoCanalPorConcepto(concepto)) {
    return false;
  }

  final c = concepto.toLowerCase();
  switch (clase) {
    case CobroConceptoClase.mesa:
      return c.contains('mesa');
    case CobroConceptoClase.sillas:
      return c.contains('silla');
    case CobroConceptoClase.base:
      return !c.contains('mesa') && !c.contains('silla');
  }
}

double grossHistoricoClaseCobro(
  Iterable<Map<String, dynamic>> pagos,
  CobroConceptoClase clase,
) {
  var sum = 0.0;
  for (final p in pagos) {
    if (!pagoCuentaParaClaseCobro(p, clase)) continue;
    final mg =
        (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num?)?.toDouble() ??
        0.0;
    sum += mg;
  }
  return double.parse(sum.toStringAsFixed(4));
}

/// Resultado de recalcular saldo/cuotas desde pagos (sin inflar monto_gross).
class RecalculoContratoDesdePagos {
  final double grossBase;
  final double grossMesa;
  final double grossSillas;
  final double saldoDeudor;
  final int cuotasBase;
  final int cuotasMesa;
  final int cuotasSillas;

  const RecalculoContratoDesdePagos({
    required this.grossBase,
    required this.grossMesa,
    required this.grossSillas,
    required this.saldoDeudor,
    required this.cuotasBase,
    required this.cuotasMesa,
    required this.cuotasSillas,
  });

  double get totalRecaudado => grossBase + grossMesa + grossSillas;
}

/// Suma simple de [monto_gross] por clase — fuente de verdad para saldo y cuotas.
/// Alineado a [tool/recalcular_contrato.dart]; no agrupa ni infla por heurística.
RecalculoContratoDesdePagos recalcularSaldoDesdePagos({
  required double montoTotalPactado,
  required int totalCuotas,
  required double mesaExtraPrecio,
  required double sillasExtraPrecioTotal,
  required double precioUnitarioMesaExtra,
  required int mesaExtraCuotas,
  required int mesaExtraCantidad,
  required int sillasExtraCuotas,
  required Iterable<Map<String, dynamic>> pagos,
}) {
  final grossBase = grossHistoricoClaseCobro(pagos, CobroConceptoClase.base);
  final grossMesa = grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa);
  final grossSillas =
      grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas);
  final totalRecaudado = grossBase + grossMesa + grossSillas;
  final saldoDeudor = double.parse(
    (montoTotalPactado - totalRecaudado)
        .clamp(0.0, double.infinity)
        .toStringAsFixed(2),
  );

  final basePlan = (montoTotalPactado - mesaExtraPrecio - sillasExtraPrecioTotal)
      .clamp(0.0, double.infinity);
  final cuotaPuraBase =
      totalCuotas > 0 ? basePlan / totalCuotas : basePlan;
  final cuotaPuraMesa =
      mesaExtraCuotas > 0 ? precioUnitarioMesaExtra / mesaExtraCuotas : 0.0;
  final cuotaPuraSilla = sillasExtraCuotas > 0
      ? sillasExtraPrecioTotal / sillasExtraCuotas
      : 0.0;

  final cuotasBase = cuotaPuraBase > 0
      ? ((grossBase + kToleranciaCuotaPura) / cuotaPuraBase)
          .floor()
          .clamp(0, totalCuotas)
      : 0;
  final cuotasMesa = cuotaPuraMesa > 0
      ? ((grossMesa + kToleranciaCuotaPura) / cuotaPuraMesa)
          .floor()
          .clamp(
            0,
            mesaExtraCuotas *
                (mesaExtraCantidad > 0 ? mesaExtraCantidad : 1),
          )
      : 0;
  final cuotasSilla = cuotaPuraSilla > 0
      ? ((grossSillas + kToleranciaCuotaPura) / cuotaPuraSilla)
          .floor()
          .clamp(0, sillasExtraCuotas > 0 ? sillasExtraCuotas : 99)
      : 0;

  return RecalculoContratoDesdePagos(
    grossBase: grossBase,
    grossMesa: grossMesa,
    grossSillas: grossSillas,
    saldoDeudor: saldoDeudor,
    cuotasBase: cuotasBase,
    cuotasMesa: cuotasMesa,
    cuotasSillas: cuotasSilla,
  );
}

/// Cuántas cuotas **nuevas** liquida [grossActual] sumado al historial bruto.
AvanceCuotaConAbonos evaluarAvanceCuotaConAbonos({
  required double grossHistoricoClase,
  required double grossActual,
  required double cuotaPura,
}) {
  if (cuotaPura <= 0.001) {
    return AvanceCuotaConAbonos(
      cuotasLiquidadas: grossActual > 0.01 ? 1 : 0,
      restoAbono: 0,
      cuotasCompletasDespues: grossActual > 0.01 ? 1 : 0,
    );
  }

  final cuotasAntes =
      cuotasCompletasDesdeGrossAcumulado(grossHistoricoClase, cuotaPura);
  final acumuladoDespues = grossHistoricoClase + grossActual;
  final cuotasDespues =
      cuotasCompletasDesdeGrossAcumulado(acumuladoDespues, cuotaPura);
  final cuotasNuevas = (cuotasDespues - cuotasAntes).clamp(0, 99);
  final resto = acumuladoDespues - cuotasDespues * cuotaPura;

  return AvanceCuotaConAbonos(
    cuotasLiquidadas: cuotasNuevas,
    restoAbono: double.parse(resto.toStringAsFixed(4)),
    cuotasCompletasDespues: cuotasDespues,
  );
}

CobroConceptoClase cobroClaseDesdeConceptoKey(String conceptoKey) {
  switch (conceptoKey) {
    case 'Mesa':
      return CobroConceptoClase.mesa;
    case 'Sillas':
      return CobroConceptoClase.sillas;
    default:
      return CobroConceptoClase.base;
  }
}

Map<String, double> grossHistoricoPorConceptoKey(
  Iterable<Map<String, dynamic>> pagos,
) {
  return {
    'Base': grossHistoricoClaseCobro(pagos, CobroConceptoClase.base),
    'Mesa': grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
    'Sillas': grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
  };
}

/// Igual que [grossHistoricoPorConceptoKey] + claves `Mesa:1`, `Mesa:2`, …
Map<String, double> grossHistoricoPorConceptoKeyExtended(
  Iterable<Map<String, dynamic>> pagos,
) {
  final out = Map<String, double>.from(grossHistoricoPorConceptoKey(pagos));
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final concepto = p['concepto'] as String? ?? '';
    if (!concepto.toLowerCase().contains('mesa')) continue;
    final gross =
        (p['monto_gross'] as num?)?.toDouble() ??
        (p['monto'] as num?)?.toDouble() ??
        0.0;
    final n = MesasExtraUtils.numeroMesaDesdeConcepto(concepto);
    final key = 'Mesa:$n';
    out[key] = double.parse(((out[key] ?? 0) + gross).toStringAsFixed(2));
  }
  return out;
}

/// Rotula concepto y cuotas liquidadas cuando el cobro solo alcanza abono
/// pero los abonos previos + este cobro cierran una o más cuotas.
({String concepto, int cuotas}) rotularDesgloseConAbonosAcumulados({
  required String conceptoKey,
  required String label,
  required double grossActual,
  required double cuotaPura,
  required double grossHistoricoClase,
  required String Function(String raw, int cuotaOffset) getConceptoDetallado,
  required int cuotasPagadasActuales,
}) {
  final avance = evaluarAvanceCuotaConAbonos(
    grossHistoricoClase: grossHistoricoClase,
    grossActual: grossActual,
    cuotaPura: cuotaPura,
  );

  if (avance.esAbonoSolo) {
    return (
      concepto: rotuloEntregaParcial(getConceptoDetallado(label, 1)),
      cuotas: 0,
    );
  }

  final n = avance.cuotasLiquidadas;

  if (n > 1 && avance.cierraCuotaExacta) {
    return (concepto: '$n Cuotas ($label)', cuotas: n);
  }

  final habiaParcial = habiaEntregaParcialEnCurso(
    grossHistorico: grossHistoricoClase,
    cuotaPura: cuotaPura,
  );

  if (avance.cierraConAdelanto) {
    final resto = avance.restoAbono;
    if (n == 1) {
      final primera = getConceptoDetallado(label, 1);
      final rotuloPrimera = habiaParcial ? '$primera — Completada' : primera;
      return (
        concepto:
            '$rotuloPrimera + ${getConceptoDetallado(label, 2)} · \$${_fmtMonto(resto)}',
        cuotas: 1,
      );
    }
    return (
      concepto:
          '$n Cuotas ($label) + ${getConceptoDetallado(label, n + 1)} · \$${_fmtMonto(resto)}',
      cuotas: n,
    );
  }

  if (n == 1) {
    final detalle = getConceptoDetallado(label, 1);
    return (
      concepto: habiaParcial ? '$detalle — Completada' : detalle,
      cuotas: 1,
    );
  }

  return (concepto: '$n Cuotas ($label)', cuotas: n);
}

/// Extrae etiqueta de un concepto tipo `Cuota Base (5/9) — Completada`.
String? etiquetaDesdeConceptoCuotaCompletada(String concepto) {
  final m = RegExp(r'^(.+?)\s*\(\d+\s*/\s*\d+\)').firstMatch(concepto.trim());
  return m?.group(1)?.trim();
}

/// Si un pago guardado como "— Completada" debió partirse (excedente),
/// devuelve el desglose correcto; si no aplica, `null`.
List<LineaPreviewDesglose>? lineasReparacionCompletadaConExcedente({
  required String concepto,
  required double montoGross,
  required double grossHistoricoAntes,
  required double cuotaPura,
  required int totalCuotas,
}) {
  final c = concepto.toLowerCase();
  if (!c.contains('completada')) return null;
  // Mesas/sillas: planes por ítem; fuera de alcance de esta reparación.
  if (c.contains('mesa') || c.contains('silla')) return null;
  if (montoGross <= 0.01 || cuotaPura <= 0.001 || totalCuotas <= 0) {
    return null;
  }

  final etiqueta = etiquetaDesdeConceptoCuotaCompletada(concepto) ?? 'Cuota Base';
  final lineas = lineasPreviewDesglosePlan(
    modo: ModoPagoConceptoTipo.parcialLibre,
    cuotasSeleccionadas: null,
    grossTotal: montoGross,
    cuotaPura: cuotaPura,
    totalCuotas: totalCuotas,
    grossHistorico: grossHistoricoAntes,
    etiqueta: etiqueta,
  );
  if (lineas.length < 2) return null;

  final suma = double.parse(
    lineas.fold<double>(0, (a, l) => a + l.gross).toStringAsFixed(2),
  );
  if ((suma - montoGross).abs() > 0.05) return null;
  // Síntoma del bug: una sola línea con todo el monto.
  if (lineas.first.gross >= montoGross - 0.01) return null;
  return lineas;
}
