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
      concepto: 'Abono a ${getConceptoDetallado(label, 1)}',
      cuotas: 0,
    );
  }

  final n = avance.cuotasLiquidadas;

  if (n > 1 && avance.cierraCuotaExacta) {
    return (concepto: '$n Cuotas ($label)', cuotas: n);
  }

  if (avance.cierraConAdelanto) {
    final proxCuota = conceptoKey == 'Base'
        ? avance.cuotasCompletasDespues + 1
        : cuotasPagadasActuales + n + 1;
    if (conceptoKey == 'Base') {
      return (
        concepto: '$n Cuotas Base + Adelanto (C$proxCuota)',
        cuotas: n,
      );
    }
    return (
      concepto: '$n Cuotas $label + Adelanto',
      cuotas: n,
    );
  }

  if (n == 1) {
    return (
      concepto: getConceptoDetallado(label, 1),
      cuotas: 1,
    );
  }

  return (concepto: '$n Cuotas ($label)', cuotas: n);
}
