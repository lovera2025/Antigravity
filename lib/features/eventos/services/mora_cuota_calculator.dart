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

  /// Interés acumulado: 1% de la cuota base × [diasMora] (crece por día de atraso).
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

/// Detalle de mora por cada cuota individualmente vencida.
class MoraCuotaDetalle {
  final int numeroCuota;
  final DateTime vencimiento;
  final int diasMora;
  final double interesBruto;
  final String mesLabel;

  const MoraCuotaDetalle({
    required this.numeroCuota,
    required this.vencimiento,
    required this.diasMora,
    required this.interesBruto,
    required this.mesLabel,
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

/// Vista previa al restaurar mora: monto, días (mes vencido) y Reg sugerido.
class MoraRestauracionSimulacion {
  final int diasMoraSolicitados;
  final int diasMoraEfectivos;
  final double cuotaBase;
  final double tasaDiaria;
  final double montoMora;
  final int? proximaCuotaNumero;
  final DateTime? vencimientoActual;
  final DateTime? vencimientoCoherente;
  final DateTime? regActual;
  final DateTime? regSugerido;

  const MoraRestauracionSimulacion({
    this.diasMoraSolicitados = 0,
    required this.diasMoraEfectivos,
    required this.cuotaBase,
    required this.tasaDiaria,
    required this.montoMora,
    this.proximaCuotaNumero,
    this.vencimientoActual,
    this.vencimientoCoherente,
    this.regActual,
    this.regSugerido,
  });

  bool get puedeAjustarReg =>
      diasMoraEfectivos > 0 &&
      regSugerido != null &&
      vencimientoCoherente != null;
}

/// Resultado del cálculo de mora a restaurar (1% cuota × días atraso; [calcular]).
class MoraRestauracionCalculo {
  final int diasMora;
  final double cuotaBase;
  final double moraBruta;
  final double moraAplicar;

  const MoraRestauracionCalculo({
    required this.diasMora,
    required this.cuotaBase,
    required this.moraBruta,
    required this.moraAplicar,
  });
}

/// Candidato listo para restauración masiva de mora persistida.
class MoraRestauracionCandidato {
  final ContratoAlumno contrato;
  final int diasMora;
  final double cuotaBase;
  final double moraBruta;
  final double moraYaCobrada;
  final double moraActual;
  final double moraAplicar;

  const MoraRestauracionCandidato({
    required this.contrato,
    required this.diasMora,
    required this.cuotaBase,
    required this.moraBruta,
    required this.moraYaCobrada,
    required this.moraActual,
    required this.moraAplicar,
  });

  String get institucionLabel =>
      (contrato.institucion ?? 'Sin colegio').trim();

  /// 1% de la cuota base (mora por día de atraso).
  double get tasaDiariaMora =>
      double.parse((cuotaBase * 0.01).toStringAsFixed(2));
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

  /// Mora operativa a mostrar / cobrar para este contrato.
  ///
  /// - **Fórmula del día** (`interés acum. − historial cobros mora`): lógica real
  ///   (1% cuota × días); sigue visible como “sugerido” en UI admin.
  /// - **`moraPendienteTracked`**: remanente persistido. Si el admin lo fijó
  ///   **por debajo** de la fórmula (caso particular), ese monto manda.
  /// - Si tracked ≥ fórmula, se usa el máximo (piso automático tras pagos parciales
  ///   o snapshot al liquidar cuota sin mora).
  static double pendienteDisplay({
    required double interesAcumulado,
    required double moraCobradaHistorial,
    double moraPendienteTracked = 0,
    /// Offset persistido al avanzar cuota base (fallback si no hay pagos).
    double moraCobradaOffset = 0,
    /// Mora cobrada solo en el período vigente (desde el último pago de cuota base).
    /// Si se provee, tiene prioridad sobre historial − offset.
    double? moraCobradaPeriodo,
  }) {
    final cobradaEnPeriodo = moraCobradaPeriodo ??
        (moraCobradaHistorial - moraCobradaOffset).clamp(0.0, double.infinity);
    final f = (interesAcumulado - cobradaEnPeriodo)
        .clamp(0.0, double.infinity);
    final t = moraPendienteTracked.clamp(0.0, double.infinity);

    // Carry-over: próxima cuota aún no venció (interés calendario = 0).
    // [moraPendienteTracked] se reduce en cada cobro vía registrarPago; solo
    // restamos del historial si tracked parece un snapshot legacy no actualizado.
    // Usamos (historial − offset), no moraCobradaPeriodo: pagos antes del
    // vencimiento de la próxima cuota quedan fuera del filtro de período.
    if (t > 0.01 && interesAcumulado <= 0.01) {
      final cobradaDesdeOffset =
          (moraCobradaHistorial - moraCobradaOffset).clamp(0.0, double.infinity);
      if (cobradaDesdeOffset <= 0.01) {
        return double.parse(t.toStringAsFixed(2));
      }
      // Pagó todo pero tracked quedó con el monto original (datos legacy).
      if ((t - cobradaDesdeOffset).abs() <= 0.01) {
        return 0.0;
      }
      // Tracked no bajó con pagos parciales (legacy).
      if (t > cobradaDesdeOffset + 0.01) {
        return double.parse(
          (t - cobradaDesdeOffset)
              .clamp(0.0, double.infinity)
              .toStringAsFixed(2),
        );
      }
      // Tracked ya refleja el remanente real (flujo actual post-cobro).
      return double.parse(t.toStringAsFixed(2));
    }

    if (t > 0.01 && t < f - 0.01) {
      return double.parse(t.toStringAsFixed(2));
    }
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
    final double interes = mora
        ? interesSugeridoSimpleSobreMonto(
            cuotaPuraR,
            porcentajeDiario: 1.0,
            diasMora: dias,
          )
        : 0.0;

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

  /// Etiqueta legible de institución para UI admin.
  static String institucionDisplay(ContratoAlumno a) {
    final inst = (a.institucion ?? '').trim();
    return inst.isNotEmpty ? inst : 'Sin institución';
  }

  static double cuotaBaseDe(ContratoAlumno a) {
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;
    final totalBase = (a.montoTotalPactado -
            a.mesaExtraPrecio -
            a.sillasExtraPrecioTotal)
        .clamp(0.0, double.infinity);
    return double.parse(
      (tCuotas > 0 ? totalBase / tCuotas : 0.0).toStringAsFixed(2),
    );
  }

  /// Último día del mes de [aprox] que ya venció respecto a [hoySolo].
  static DateTime _vencimientoMesVencidoParaDias(
    DateTime hoySolo,
    int diasMora,
  ) {
    final vApprox = hoySolo.subtract(Duration(days: diasMora));
    var y = vApprox.year;
    var m = vApprox.month;
    var vEnd = DateTime(y, m, _diasEnMes(y, m));
    if (!vEnd.isBefore(hoySolo)) {
      m--;
      if (m <= 0) {
        m = 12;
        y--;
      }
      vEnd = DateTime(y, m, _diasEnMes(y, m));
    }
    return vEnd;
  }

  /// Reg (día 1 del mes de inscripción AR) para que la cuota [proxN] venza en [venc].
  static DateTime _inscripcionParaVencimientoCuota(
    DateTime venc,
    int proxN,
  ) {
    var m = venc.month - proxN;
    var y = venc.year;
    while (m <= 0) {
      m += 12;
      y--;
    }
    return DateTime(y, m, 1);
  }

  /// Reg sugerido para que la próxima cuota pendiente tenga [diasMora] días de atraso.
  static DateTime? regSugeridoParaDiasMora(
    ContratoAlumno a,
    int diasMora, [
    DateTime? ahoraAr,
  ]) {
    if (diasMora <= 0 || a.saldoDeudor <= 0.01) return null;
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;
    final cPag = a.cuotasPagadas.clamp(0, tCuotas);
    if (cPag >= tCuotas) return null;
    final proxN = cPag + 1;
    final hoy = ahoraAr ?? ArTime.nowAr();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
    final vCoherente = _vencimientoMesVencidoParaDias(hoySolo, diasMora);
    return _inscripcionParaVencimientoCuota(vCoherente, proxN);
  }

  /// Reg sugerido para dejar la próxima cuota **al día** (sin mora calendario).
  static DateTime? regSugeridoParaAlDia(ContratoAlumno a, [DateTime? ahoraAr]) {
    if (a.saldoDeudor <= 0.01) {
      return a.createdAt != null ? ArTime.toAr(a.createdAt!) : null;
    }
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;
    final cPag = a.cuotasPagadas.clamp(0, tCuotas);
    if (cPag >= tCuotas) return null;

    final proxN = cPag + 1;
    final hoy = ahoraAr ?? ArTime.nowAr();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    var y = hoySolo.year;
    var m = hoySolo.month;
    var vEnd = DateTime(y, m, _diasEnMes(y, m));
    if (hoySolo.isAfter(vEnd)) {
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
      vEnd = DateTime(y, m, _diasEnMes(y, m));
    }
    return _inscripcionParaVencimientoCuota(vEnd, proxN);
  }

  /// Vencimiento (mes vencido) de la cuota [numeroCuota] dado un Reg AR.
  static DateTime vencimientoCuotaDesdeRegAr(
    DateTime regAr,
    int numeroCuota,
  ) =>
      _ultimoDiaMesK(regAr, numeroCuota);

  /// Simula quitar mora persistida y recolocar Reg al día.
  static MoraRestauracionSimulacion simularQuitarMora(
    ContratoAlumno a, {
    DateTime? ahoraAr,
  }) {
    final hoy = ahoraAr ?? ArTime.nowAr();
    final resumenActual = calcular(a, hoy);
    final cuota = cuotaBaseDe(a);
    final tasa = double.parse((cuota * 0.01).toStringAsFixed(2));
    final regSug = regSugeridoParaAlDia(a, hoy);
    DateTime? vCoherente;
    if (regSug != null && resumenActual.proximaCuotaNumero != null) {
      vCoherente = vencimientoCuotaDesdeRegAr(
        regSug,
        resumenActual.proximaCuotaNumero!,
      );
    }

    return MoraRestauracionSimulacion(
      diasMoraEfectivos: 0,
      cuotaBase: cuota,
      tasaDiaria: tasa,
      montoMora: 0,
      proximaCuotaNumero: resumenActual.proximaCuotaNumero,
      vencimientoActual: resumenActual.fechaVencimientoProximaCuota,
      vencimientoCoherente: vCoherente,
      regActual: a.createdAt != null ? ArTime.toAr(a.createdAt!) : null,
      regSugerido: regSug,
    );
  }

  /// ISO UTC para persistir [regAr] (día de alta en huso AR).
  static String regArAUtcIso(DateTime regAr) {
    return DateTime.utc(regAr.year, regAr.month, regAr.day, 3, 0, 0)
        .toIso8601String();
  }

  static MoraRestauracionSimulacion simularPorDias(
    ContratoAlumno a,
    int diasMora, {
    DateTime? ahoraAr,
  }) {
    final hoy = ahoraAr ?? ArTime.nowAr();
    final resumenActual = calcular(a, hoy);
    final cuota = cuotaBaseDe(a);
    final tasa = double.parse((cuota * 0.01).toStringAsFixed(2));
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    if (diasMora <= 0 || cuota <= 0.01) {
      return MoraRestauracionSimulacion(
        diasMoraEfectivos: 0,
        cuotaBase: cuota,
        tasaDiaria: tasa,
        montoMora: 0,
        proximaCuotaNumero: resumenActual.proximaCuotaNumero,
        vencimientoActual: resumenActual.fechaVencimientoProximaCuota,
        regActual: a.createdAt != null ? ArTime.toAr(a.createdAt!) : null,
      );
    }

    final vCoherente = _vencimientoMesVencidoParaDias(hoySolo, diasMora);
    final diasEfectivos = hoySolo.difference(vCoherente).inDays;
    final monto = interesSugeridoSimpleSobreMonto(
      cuota,
      porcentajeDiario: 1.0,
      diasMora: diasEfectivos,
    );
    final regSug = regSugeridoParaDiasMora(a, diasMora, hoy);

    return MoraRestauracionSimulacion(
      diasMoraSolicitados: diasMora,
      diasMoraEfectivos: diasEfectivos,
      cuotaBase: cuota,
      tasaDiaria: tasa,
      montoMora: double.parse(monto.toStringAsFixed(2)),
      proximaCuotaNumero: resumenActual.proximaCuotaNumero,
      vencimientoActual: resumenActual.fechaVencimientoProximaCuota,
      vencimientoCoherente: vCoherente,
      regActual: a.createdAt != null ? ArTime.toAr(a.createdAt!) : null,
      regSugerido: regSug,
    );
  }

  static MoraRestauracionSimulacion simularPorMonto(
    ContratoAlumno a,
    double montoMora, {
    DateTime? ahoraAr,
  }) {
    final cuota = cuotaBaseDe(a);
    final tasa = double.parse((cuota * 0.01).toStringAsFixed(2));
    if (montoMora <= 0.01 || tasa <= 0.01) {
      return simularPorDias(a, 0, ahoraAr: ahoraAr);
    }
    final diasAprox = (montoMora / tasa).round().clamp(1, 9999);
    final sim = simularPorDias(a, diasAprox, ahoraAr: ahoraAr);
    return MoraRestauracionSimulacion(
      diasMoraSolicitados: diasAprox,
      diasMoraEfectivos: sim.diasMoraEfectivos,
      cuotaBase: sim.cuotaBase,
      tasaDiaria: sim.tasaDiaria,
      montoMora: double.parse(montoMora.toStringAsFixed(2)),
      proximaCuotaNumero: sim.proximaCuotaNumero,
      vencimientoActual: sim.vencimientoActual,
      vencimientoCoherente: sim.vencimientoCoherente,
      regActual: sim.regActual,
      regSugerido: sim.regSugerido,
    );
  }

  static const _mesesCortos = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  /// Resta [moraCobradaHistorial] del desglose bruto (FIFO por número de cuota).
  /// Cuotas totalmente cubiertas se omiten; la última puede quedar parcial.
  static List<MoraCuotaDetalle> desglosePendiente(
    List<MoraCuotaDetalle> desgloseBruto,
    double moraCobradaHistorial,
  ) {
    if (desgloseBruto.isEmpty) return const [];
    if (moraCobradaHistorial <= 0.01) {
      return List<MoraCuotaDetalle>.from(desgloseBruto);
    }

    var restante = moraCobradaHistorial;
    final out = <MoraCuotaDetalle>[];

    for (final d in desgloseBruto) {
      if (restante >= d.interesBruto - 0.01) {
        restante = (restante - d.interesBruto).clamp(0.0, double.infinity);
        continue;
      }
      final pendiente = (d.interesBruto - restante).clamp(0.0, double.infinity);
      restante = 0;
      if (pendiente <= 0.01) continue;
      out.add(MoraCuotaDetalle(
        numeroCuota: d.numeroCuota,
        vencimiento: d.vencimiento,
        diasMora: d.diasMora,
        interesBruto: double.parse(pendiente.toStringAsFixed(2)),
        mesLabel: d.mesLabel,
      ));
    }

    return out;
  }

  /// Mora operativa del modal: máximo entre [moraPendienteUi] y el desglose neto.
  static double pendienteEfectivoConDesglose({
    required double moraPendienteUi,
    required List<MoraCuotaDetalle> desgloseBruto,
    required double moraCobradaHistorial,
  }) {
    if (desgloseBruto.isEmpty) {
      return double.parse(
        moraPendienteUi.clamp(0.0, double.infinity).toStringAsFixed(2),
      );
    }
    final desglosePend = desglosePendiente(desgloseBruto, moraCobradaHistorial);
    final totalNeta =
        desglosePend.fold<double>(0, (s, d) => s + d.interesBruto);
    return double.parse(
      math.max(moraPendienteUi, totalNeta).toStringAsFixed(2),
    );
  }

  /// Desglose de mora por cada cuota individualmente vencida.
  /// Retorna una entrada por cuota cuyo vencimiento ya pasó, con su interés bruto.
  static List<MoraCuotaDetalle> calcularDesglose(ContratoAlumno a, [DateTime? ahoraAr]) {
    final hoy = ahoraAr ?? ArTime.nowAr();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    if (a.saldoDeudor <= 0.01) return [];

    final inscAr = a.createdAt != null ? ArTime.toAr(a.createdAt!) : hoy;
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 1;
    final totalBase = (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal)
        .clamp(0.0, double.infinity);
    final cuotaPura = tCuotas > 0
        ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
        : 0.0;
    final cPag = a.cuotasPagadas.clamp(0, tCuotas);

    if (cPag >= tCuotas || cuotaPura <= 0.01) return [];

    final result = <MoraCuotaDetalle>[];

    for (int n = cPag + 1; n <= tCuotas; n++) {
      final venc = _ultimoDiaMesK(inscAr, n);
      final vSolo = DateTime(venc.year, venc.month, venc.day);

      if (!hoySolo.isAfter(vSolo)) break;

      final dias = hoySolo.difference(vSolo).inDays;
      if (dias <= 0) break;

      final interes = interesSugeridoSimpleSobreMonto(
        cuotaPura,
        porcentajeDiario: 1.0,
        diasMora: dias,
      );

      result.add(MoraCuotaDetalle(
        numeroCuota: n,
        vencimiento: venc,
        diasMora: dias,
        interesBruto: double.parse(interes.toStringAsFixed(2)),
        mesLabel: '${_mesesCortos[venc.month - 1]} ${venc.year}',
      ));
    }

    return result;
  }

  /// Mora a restaurar en bulk: misma regla que [calcular] (1% cuota × días atraso),
  /// menos [moraYaCobrada].
  static MoraRestauracionCalculo? calcularRestauracionDesdeReg(
    ContratoAlumno a, {
    DateTime? ahoraAr,
    double moraYaCobrada = 0,
  }) {
    final resumen = calcular(a, ahoraAr);
    if (!resumen.enMora || resumen.interesAcumulado <= 0.01) return null;

    final moraBruta = resumen.interesAcumulado;
    final moraAplicar = double.parse(
      (moraBruta - moraYaCobrada).clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    if (moraAplicar <= 0.01) return null;

    return MoraRestauracionCalculo(
      diasMora: resumen.diasMora,
      cuotaBase: resumen.montoCuotaBaseAprox,
      moraBruta: moraBruta,
      moraAplicar: moraAplicar,
    );
  }
}
