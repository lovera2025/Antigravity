import 'dart:math' as math;

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';

/// Resultado de la lectura "inteligente" de mora sobre el **plan de cuota base** (excl. mesa/sillas).
class MoraCuotaResumen {
  /// Días de atraso respecto al vencimiento de la próxima cuota a pagar; 0 si no aplica o está al día.
  final int diasMora;

  /// Vencimiento de la cuota base número [proximaCuotaNumero] (1…totalCuotas), si aplica.
  final DateTime? fechaVencimientoProximaCuota;

  /// Número de cuota base que define el calendario (1-based): la siguiente que falta o la última si ya pasó.
  final int? proximaCuotaNumero;

  /// Aprox. cuota de plan base: (total − mesa − silla) / total_cuotas. Base para un futuro interés.
  final double montoCuotaBaseAprox;

  /// Misma condición de UI: hay saldo, y venció el plazo de la cuota a pagar.
  final bool enMora;

  /// Marca (primer registro / alta) usada para armar vencimientos; solo informativo.
  final DateTime? fechaInscripcionUsada;

  /// Interés acumulado: montoCuotaBaseAprox * 1% * diasMora. Listo para cobro real.
  final double interesAcumulado;

  const MoraCuotaResumen({
    required this.diasMora,
    this.fechaVencimientoProximaCuota,
    this.proximaCuotaNumero,
    this.montoCuotaBaseAprox = 0,
    this.enMora = false,
    this.fechaInscripcionUsada,
    this.interesAcumulado = 0,
  });
}

int _diasEnMes(int year, int month) => DateTime(year, month + 1, 0).day;

/// Último día del mes (inscripción.month + k).
/// Cuota 1 = mes_inscripción + 1, cuota 2 = mes_inscripción + 2, etc.
DateTime _ultimoDiaMesK(DateTime inscripcion, int k) {
  var m = inscripcion.month + k;
  var y = inscripcion.year;
  while (m > 12) {
    m -= 12;
    y++;
  }
  return DateTime(y, m, _diasEnMes(y, m));
}

/// Primer vencimiento de cuota 1: último día del mes siguiente al de inscripción.
/// El campo [diaVenc] se conserva por compatibilidad pero ya no se usa.
DateTime vencimientoPrimeraCuotaBase(DateTime inscripcionAr, int diaVenc) {
  return _ultimoDiaMesK(inscripcionAr, 1);
}

/// [porcentajeDiario] 1.0 = 1% / día. Interés lineal simple (solo proyección; no contable).
double interesSugeridoSimpleSobreMonto(
  double monto, {
  required double porcentajeDiario,
  required int diasMora,
}) {
  if (diasMora <= 0 || monto <= 0 || porcentajeDiario <= 0) return 0;
  return monto * (porcentajeDiario / 100.0) * diasMora;
}

class MoraCuotaCalculator {
  MoraCuotaCalculator._();

  /// Mora a mostrar / cobrar: max entre el saldo teórico del día
  /// (`interés acum. − historial de cobros mora`) y el remanente persistido
  /// en [ContratoAlumno.moraPendienteTracked] (p. ej. pago parcial cuando
  /// después el calendario pone `interesAcumulado` en 0).
  static double pendienteDisplay({
    required double interesAcumulado,
    required double moraCobradaHistorial,
    double moraPendienteTracked = 0,
  }) {
    final f = (interesAcumulado - moraCobradaHistorial)
        .clamp(0.0, double.infinity);
    final t = moraPendienteTracked.clamp(0.0, double.infinity);
    return double.parse(math.max(f, t).toStringAsFixed(2));
  }

  /// Cálculo basado en el **alta** (primer registro: [ContratoAlumno.createdAt]).
  /// Vencimiento = último día del mes (inscripción.month + cuotaNumero).
  /// Mora arranca el día 1 del mes siguiente al de vencimiento (= día después del último día).
  static MoraCuotaResumen calcular(ContratoAlumno a, [DateTime? ahoraAr]) {
    final hoy = ahoraAr ?? ArTime.nowAr();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    if (a.saldoDeudor <= 0.01) {
      return MoraCuotaResumen(
        diasMora: 0,
        montoCuotaBaseAprox: 0,
        enMora: false,
        fechaInscripcionUsada: a.createdAt,
      );
    }

    // `hoy` ya viene en huso AR (ArTime.nowAr() / [ahoraAr]); solo `createdAt` necesita conversión
    // desde UTC. Aplicar `toAr` sobre `hoy` provoca un -3 h adicional que mueve el cálculo de cuotas.
    final inscAr = a.createdAt != null ? ArTime.toAr(a.createdAt!) : hoy;
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;

    final totalBase = (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
    final cuotaPura = tCuotas > 0 ? totalBase / tCuotas : 0.0;
    final cuotaPuraR = double.parse(cuotaPura.toStringAsFixed(2));

    final cPag = a.cuotasPagadas.clamp(0, tCuotas);
    if (cPag >= tCuotas) {
      return MoraCuotaResumen(
        diasMora: 0,
        montoCuotaBaseAprox: cuotaPuraR,
        enMora: a.saldoDeudor > 0.01,
        fechaInscripcionUsada: inscAr,
      );
    }

    final proxN = cPag + 1;
    final vProx = _ultimoDiaMesK(inscAr, proxN);
    final vSolo = DateTime(vProx.year, vProx.month, vProx.day);

    int dias = 0;
    if (hoySolo.isAfter(vSolo)) {
      dias = hoySolo.difference(vSolo).inDays;
    }

    final bool mora = a.saldoDeudor > 0.01 && dias > 0;
    final double interes = mora ? cuotaPuraR * 0.01 * dias : 0.0;

    return MoraCuotaResumen(
      diasMora: dias,
      fechaVencimientoProximaCuota: vProx,
      proximaCuotaNumero: proxN,
      montoCuotaBaseAprox: cuotaPuraR,
      enMora: mora,
      fechaInscripcionUsada: inscAr,
      interesAcumulado: double.parse(interes.toStringAsFixed(2)),
    );
  }
}
