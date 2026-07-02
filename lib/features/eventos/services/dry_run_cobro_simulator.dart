import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/mesa_extra_item.dart';
import 'cobro_abono_acumulado.dart';
import 'cobro_masivo_conceptos_pdf.dart';
import 'mesas_extra_utils.dart';
import 'mora_cuota_calculator.dart';

/// Resultado de una simulación de cobro (sin escribir en DB).
class DryRunEscenarioResult {
  final String nombre;
  final bool ok;
  final String? error;
  final double grossPlan;
  final double netPlan;
  final int lineasPreview;
  final int lineasPdf;

  const DryRunEscenarioResult({
    required this.nombre,
    required this.ok,
    this.error,
    this.grossPlan = 0,
    this.netPlan = 0,
    this.lineasPreview = 0,
    this.lineasPdf = 0,
  });
}

class DryRunContratoResult {
  final String contratoId;
  final String nombre;
  final double saldo;
  final List<DryRunEscenarioResult> escenarios;
  final List<String> advertenciasIntegridad;

  const DryRunContratoResult({
    required this.contratoId,
    required this.nombre,
    required this.saldo,
    required this.escenarios,
    this.advertenciasIntegridad = const [],
  });

  bool get ok =>
      advertenciasIntegridad.isEmpty &&
      escenarios.every((e) => e.ok);
}

class DryRunEventoResult {
  final String eventoId;
  final String etiqueta;
  final int contratosActivos;
  final int contratosProbados;
  final List<DryRunContratoResult> contratos;
  final List<String> fallos;

  const DryRunEventoResult({
    required this.eventoId,
    required this.etiqueta,
    required this.contratosActivos,
    required this.contratosProbados,
    required this.contratos,
    required this.fallos,
  });

  bool get ok => fallos.isEmpty && contratos.every((c) => c.ok);
}

bool esLineaInteresMoraDry(Map<String, dynamic> c) =>
    c['lineKind'] == kLineKindInteresMora;

bool esLineaCargoCanalDry(Map<String, dynamic> c) =>
    c['lineKind'] == kLineKindCargoCanal;

List<String> auditarIntegridadContrato(ContratoAlumno c) {
  final out = <String>[];
  if (c.saldoDeudor < -0.01) {
    out.add('saldo_deudor negativo (${c.saldoDeudor})');
  }
  if (c.saldoDeudor > c.montoTotalPactado + 0.02) {
    out.add('saldo > monto pactado');
  }
  if (c.cuotasPagadas > c.totalCuotas) {
    out.add('cuotas_pagadas > total_cuotas');
  }
  if (c.mesaExtraCuotasPagadas > c.mesaExtraCuotas && c.mesaExtraPrecio > 0.01) {
    out.add('mesa cuotas pagadas > plan');
  }
  if (c.sillasExtraCuotasPagadas > c.sillasExtraCuotas &&
      c.sillasExtraPrecioTotal > 0.01) {
    out.add('sillas cuotas pagadas > plan');
  }
  return out;
}

List<Map<String, dynamic>> _previewDesdePlan({
  required String label,
  required double gross,
  required double net,
  required double cuotaPura,
  required int totalCuotas,
  required double grossHistorico,
  int? mesaN,
}) {
  final lineas = lineasPreviewDesglosePlan(
    modo: ModoPagoConceptoTipo.total,
    cuotasSeleccionadas: null,
    grossTotal: gross,
    cuotaPura: cuotaPura,
    totalCuotas: totalCuotas,
    grossHistorico: grossHistorico,
    etiqueta: label,
  );
  if (lineas.isEmpty) {
    return [
      {
        'concepto': label,
        'monto': double.parse(net.toStringAsFixed(2)),
        'gross': double.parse(gross.toStringAsFixed(2)),
        'cuotas': 0,
        if (mesaN != null) 'mesaN': mesaN,
      },
    ];
  }
  if (lineas.length == 1) {
    final l = lineas.first;
    return [
      {
        'concepto': l.concepto,
        if (l.subtexto != null) 'subtexto': l.subtexto,
        'monto': double.parse(net.toStringAsFixed(2)),
        'gross': double.parse(gross.toStringAsFixed(2)),
        'cuotas': l.cuotasLiquidadas,
        if (mesaN != null) 'mesaN': mesaN,
      },
    ];
  }
  var netAcum = 0.0;
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < lineas.length; i++) {
    final l = lineas[i];
    double netLine;
    if (i == lineas.length - 1) {
      netLine = double.parse((net - netAcum).toStringAsFixed(2));
    } else if (gross > 0.011) {
      netLine = double.parse((net * (l.gross / gross)).toStringAsFixed(2));
      netAcum += netLine;
    } else {
      netLine = 0;
    }
    out.add({
      'concepto': l.concepto,
      if (l.subtexto != null) 'subtexto': l.subtexto,
      'monto': netLine,
      'gross': l.gross,
      'cuotas': l.cuotasLiquidadas,
      if (mesaN != null) 'mesaN': mesaN,
    });
  }
  return out;
}

DryRunEscenarioResult _simularPreviewPdf({
  required String nombre,
  required ContratoAlumno alumno,
  required List<Map<String, dynamic>> previewConceptos,
  required int cantMesas,
}) {
  try {
    if (previewConceptos.isEmpty) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error: 'preview vacío',
      );
    }

    final grossPlan = previewConceptos
        .where((c) => !esLineaCargoCanalDry(c) && !esLineaInteresMoraDry(c))
        .fold<double>(0, (s, c) => s + ((c['gross'] as num?)?.toDouble() ?? 0));
    final netPlan = previewConceptos
        .where((c) => !esLineaCargoCanalDry(c))
        .fold<double>(0, (s, c) => s + ((c['monto'] as num).toDouble()));

    if (grossPlan > alumno.saldoDeudor + 0.02) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error:
            'gross plan ${grossPlan.toStringAsFixed(2)} > saldo ${alumno.saldoDeudor.toStringAsFixed(2)}',
        grossPlan: grossPlan,
        netPlan: netPlan,
        lineasPreview: previewConceptos.length,
      );
    }

    final tCuotas = alumno.totalCuotas > 0 ? alumno.totalCuotas : 9;
    final mCuotas = alumno.mesaExtraCuotas > 0 ? alumno.mesaExtraCuotas : 1;
    final sCuotas = alumno.sillasExtraCuotas > 0 ? alumno.sillasExtraCuotas : 1;

    var nuevasBase = 0;
    var nuevasMesa = 0;
    var nuevasSillas = 0;
    for (final conc in previewConceptos) {
      if (esLineaCargoCanalDry(conc) || esLineaInteresMoraDry(conc)) continue;
      final cTexto = (conc['concepto'] as String).toUpperCase();
      final cCuotas = ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
      if (cTexto.contains('BASE')) nuevasBase += cCuotas;
      if (cTexto.contains('MESA')) nuevasMesa += cCuotas;
      if (cTexto.contains('SILLA')) nuevasSillas += cCuotas;
    }

    if (alumno.cuotasPagadas + nuevasBase > tCuotas) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error: 'cuotas base exceden plan',
        grossPlan: grossPlan,
        netPlan: netPlan,
        lineasPreview: previewConceptos.length,
      );
    }

    final conceptosPdf = conceptosFinalesDesdePreviewMasivo(
      previewConceptos: previewConceptos,
      esLineaCargoCanal: esLineaCargoCanalDry,
      esLineaInteresMora: esLineaInteresMoraDry,
      cPagadas: alumno.cuotasPagadas,
      tCuotas: tCuotas,
      mPagadas: alumno.mesaExtraCuotasPagadas,
      mCuotas: mCuotas,
      sPagadas: alumno.sillasExtraCuotasPagadas,
      sCuotas: sCuotas,
      cantMesas: cantMesas,
    );

    if (conceptosPdf.isEmpty) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error: 'PDF sin líneas',
        grossPlan: grossPlan,
        netPlan: netPlan,
        lineasPreview: previewConceptos.length,
      );
    }

    final sumPdf = conceptosPdf.fold<double>(
      0,
      (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
    );
    if ((sumPdf - netPlan).abs() > 0.05 &&
        !previewConceptos.any(esLineaInteresMoraDry)) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error:
            'PDF neto ${sumPdf.toStringAsFixed(2)} != preview ${netPlan.toStringAsFixed(2)}',
        grossPlan: grossPlan,
        netPlan: netPlan,
        lineasPreview: previewConceptos.length,
        lineasPdf: conceptosPdf.length,
      );
    }

    final agrupado = agruparConceptosMesasParaPdf(conceptosPdf, mCuotas);
    if (agrupado.isEmpty) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error: 'agrupación PDF vacía',
      );
    }

    totalesDescuentoPlanPdf(conceptosPdf);

    final saldoPost =
        double.parse((alumno.saldoDeudor - grossPlan).toStringAsFixed(2));
    if (saldoPost < -0.02) {
      return DryRunEscenarioResult(
        nombre: nombre,
        ok: false,
        error: 'saldo post-cobro negativo',
        grossPlan: grossPlan,
        netPlan: netPlan,
        lineasPreview: previewConceptos.length,
        lineasPdf: conceptosPdf.length,
      );
    }

    return DryRunEscenarioResult(
      nombre: nombre,
      ok: true,
      grossPlan: grossPlan,
      netPlan: netPlan,
      lineasPreview: previewConceptos.length,
      lineasPdf: conceptosPdf.length,
    );
  } catch (e) {
    return DryRunEscenarioResult(
      nombre: nombre,
      ok: false,
      error: '$e',
    );
  }
}

/// Simula cobros típicos (cuota / mesa / silla / mora) sin persistir.
DryRunContratoResult simularContratoDryRun({
  required ContratoAlumno alumno,
  required List<Map<String, dynamic>> pagos,
}) {
  final integridad = auditarIntegridadContrato(alumno);
  final escenarios = <DryRunEscenarioResult>[];

  if (alumno.saldoDeudor <= 0.01) {
    return DryRunContratoResult(
      contratoId: alumno.id,
      nombre: alumno.nombreAlumno,
      saldo: alumno.saldoDeudor,
      escenarios: const [
        DryRunEscenarioResult(
          nombre: 'sin_deuda',
          ok: true,
        ),
      ],
      advertenciasIntegridad: integridad,
    );
  }

  final historico = grossHistoricoPorConceptoKeyExtended(pagos);
  final tCuotas = alumno.totalCuotas > 0 ? alumno.totalCuotas : 9;
  final mCuotas = alumno.mesaExtraCuotas > 0 ? alumno.mesaExtraCuotas : 1;
  final sCuotas = alumno.sillasExtraCuotas > 0 ? alumno.sillasExtraCuotas : 1;

  final totalBase = (alumno.montoTotalPactado -
          alumno.mesaExtraPrecio -
          alumno.sillasExtraPrecioTotal)
      .clamp(0.0, double.infinity);
  final cuotaPura = tCuotas > 0
      ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
      : totalBase;

  final mesasList = MesasExtraUtils.estadoDesdeContrato(alumno);
  final mesasActivas = MesasExtraUtils.mesasActivas(mesasList);
  final cantMesas = MesasExtraUtils.cantidadMesasContrato(alumno, mesasList);

  final deudaBase = (totalBase -
          (alumno.montoTotalPactado -
              alumno.saldoDeudor -
              alumno.mesaExtraPagado -
              alumno.sillasExtraPagado))
      .clamp(0.0, double.infinity);
  final deudaMesa = mesasActivas.isEmpty
      ? (alumno.mesaExtraPrecio - alumno.mesaExtraPagado)
          .clamp(0.0, double.infinity)
      : mesasActivas.fold<double>(0, (s, m) => s + m.deuda);
  final deudaSillas =
      (alumno.sillasExtraPrecioTotal - alumno.sillasExtraPagado)
          .clamp(0.0, double.infinity);

  final grossBaseHist = historico['Base'] ?? 0.0;
  final grossSillasHist = historico['Sillas'] ?? 0.0;

  if (deudaBase > 0.01 && cuotaPura > 0.01) {
    final gross = double.parse(
      (cuotaPura > deudaBase ? deudaBase : cuotaPura).toStringAsFixed(2),
    );
    final preview = _previewDesdePlan(
      label: 'Cuota Base',
      gross: gross,
      net: gross,
      cuotaPura: cuotaPura,
      totalCuotas: tCuotas,
      grossHistorico: grossBaseHist,
    );
    escenarios.add(
      _simularPreviewPdf(
        nombre: 'cuota_base_1',
        alumno: alumno,
        previewConceptos: preview,
        cantMesas: cantMesas,
      ),
    );

    final parcial = double.parse((gross / 2).toStringAsFixed(2));
    if (parcial > 0.01) {
      final previewParcial = _previewDesdePlan(
        label: 'Cuota Base',
        gross: parcial,
        net: parcial,
        cuotaPura: cuotaPura,
        totalCuotas: tCuotas,
        grossHistorico: grossBaseHist,
      );
      escenarios.add(
        _simularPreviewPdf(
          nombre: 'cuota_base_parcial',
          alumno: alumno,
          previewConceptos: previewParcial,
          cantMesas: cantMesas,
        ),
      );
    }
  }

  if (deudaMesa > 0.01) {
    if (mesasActivas.isNotEmpty) {
      final m = mesasActivas.first;
      final cuotaMesa = mCuotas > 0
          ? double.parse((m.precio / mCuotas).toStringAsFixed(2))
          : m.precio;
      final gross = double.parse(
        (cuotaMesa > m.deuda ? m.deuda : cuotaMesa).toStringAsFixed(2),
      );
      final key = MesasExtraUtils.claveCobro(m.n);
      final hist = historico[key] ?? historico['Mesa'] ?? 0.0;
      final label = MesasExtraUtils.labelCobro(m.n, cantMesas);
      final preview = _previewDesdePlan(
        label: label,
        gross: gross,
        net: gross,
        cuotaPura: cuotaMesa,
        totalCuotas: mCuotas,
        grossHistorico: hist,
        mesaN: m.n,
      );
      escenarios.add(
        _simularPreviewPdf(
          nombre: 'mesa_${m.n}',
          alumno: alumno,
          previewConceptos: preview,
          cantMesas: cantMesas,
        ),
      );
    } else if (alumno.mesaExtraPrecio > 0.01) {
      final cuotaMesa = mCuotas > 0
          ? double.parse(
              (alumno.mesaExtraPrecio / mCuotas).toStringAsFixed(2),
            )
          : alumno.mesaExtraPrecio;
      final gross = double.parse(
        (cuotaMesa > deudaMesa ? deudaMesa : cuotaMesa).toStringAsFixed(2),
      );
      final preview = _previewDesdePlan(
        label: 'Mesa Extra',
        gross: gross,
        net: gross,
        cuotaPura: cuotaMesa,
        totalCuotas: mCuotas,
        grossHistorico: historico['Mesa'] ?? 0.0,
        mesaN: 1,
      );
      escenarios.add(
        _simularPreviewPdf(
          nombre: 'mesa_legacy',
          alumno: alumno,
          previewConceptos: preview,
          cantMesas: cantMesas,
        ),
      );
    }
  }

  if (deudaSillas > 0.01 && alumno.sillasExtraPrecioTotal > 0.01) {
    final cuotaSilla = sCuotas > 0
        ? double.parse(
            (alumno.sillasExtraPrecioTotal / sCuotas).toStringAsFixed(2),
          )
        : alumno.sillasExtraPrecioTotal;
    final gross = double.parse(
      (cuotaSilla > deudaSillas ? deudaSillas : cuotaSilla).toStringAsFixed(2),
    );
    final preview = _previewDesdePlan(
      label: sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
      gross: gross,
      net: gross,
      cuotaPura: cuotaSilla,
      totalCuotas: sCuotas,
      grossHistorico: grossSillasHist,
    );
    escenarios.add(
      _simularPreviewPdf(
        nombre: 'sillas_1',
        alumno: alumno,
        previewConceptos: preview,
        cantMesas: cantMesas,
      ),
    );
  }

  final moraHist = pagos.fold<double>(0, (s, p) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return s;
    final lk = (p['line_kind'] as String?)?.trim();
    final c = p['concepto']?.toString() ?? '';
    if (lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(c)) {
      return s + ((p['monto'] as num?)?.toDouble() ?? 0);
    }
    return s;
  });
  final moraPend = MoraCuotaCalculator.moraPendienteOperativa(
    contrato: alumno,
    moraCobradaHistorial: moraHist,
  );
  if (moraPend > 0.01) {
    final previewMora = [
      {
        'concepto': 'Interés mora (cuota base — este cobro)',
        'monto': moraPend,
        'gross': moraPend,
        'cuotas': 0,
        'lineKind': kLineKindInteresMora,
      },
    ];
    escenarios.add(
      _simularPreviewPdf(
        nombre: 'mora_pendiente',
        alumno: alumno,
        previewConceptos: previewMora,
        cantMesas: cantMesas,
      ),
    );
  }

  if (deudaBase > 0.01 && deudaMesa > 0.01 && mesasActivas.isNotEmpty) {
    final grossB = double.parse(
      (cuotaPura > deudaBase ? deudaBase : cuotaPura).toStringAsFixed(2),
    );
    final m = mesasActivas.first;
    final cuotaMesa = mCuotas > 0
        ? double.parse((m.precio / mCuotas).toStringAsFixed(2))
        : m.precio;
    final grossM = double.parse(
      (cuotaMesa > m.deuda ? m.deuda : cuotaMesa).toStringAsFixed(2),
    );
    final combo = <Map<String, dynamic>>[
      ..._previewDesdePlan(
        label: 'Cuota Base',
        gross: grossB,
        net: grossB,
        cuotaPura: cuotaPura,
        totalCuotas: tCuotas,
        grossHistorico: grossBaseHist,
      ),
      ..._previewDesdePlan(
        label: MesasExtraUtils.labelCobro(m.n, cantMesas),
        gross: grossM,
        net: grossM,
        cuotaPura: cuotaMesa,
        totalCuotas: mCuotas,
        grossHistorico: historico[MesasExtraUtils.claveCobro(m.n)] ?? 0.0,
        mesaN: m.n,
      ),
    ];
    final grossCombo = combo
        .where((c) => !esLineaInteresMoraDry(c))
        .fold<double>(0, (s, c) => s + ((c['gross'] as num?)?.toDouble() ?? 0));
    if (grossCombo <= alumno.saldoDeudor + 0.02) {
      escenarios.add(
        _simularPreviewPdf(
          nombre: 'combo_base_mesa',
          alumno: alumno,
          previewConceptos: combo,
          cantMesas: cantMesas,
        ),
      );
    }
  }

  if (escenarios.isEmpty) {
    escenarios.add(
      const DryRunEscenarioResult(
        nombre: 'sin_escenario_aplicable',
        ok: true,
      ),
    );
  }

  return DryRunContratoResult(
    contratoId: alumno.id,
    nombre: alumno.nombreAlumno,
    saldo: alumno.saldoDeudor,
    escenarios: escenarios,
    advertenciasIntegridad: integridad,
  );
}

DryRunEventoResult simularEventoDryRun({
  required String eventoId,
  required String etiqueta,
  required List<ContratoAlumno> contratos,
  required Map<String, List<Map<String, dynamic>>> pagosPorContrato,
}) {
  final activos =
      contratos.where((c) => c.saldoDeudor > 0.01 && !c.nombreAlumno.trim().startsWith('[BAJA]')).toList();
  final fallos = <String>[];
  final resultados = <DryRunContratoResult>[];

  for (final c in activos) {
    final pagos = pagosPorContrato[c.id] ?? const [];
    final r = simularContratoDryRun(alumno: c, pagos: pagos);
    resultados.add(r);
    if (!r.ok) {
      for (final adv in r.advertenciasIntegridad) {
        fallos.add('${c.nombreAlumno}: integridad — $adv');
      }
      for (final e in r.escenarios.where((x) => !x.ok)) {
        fallos.add('${c.nombreAlumno} [${e.nombre}]: ${e.error}');
      }
    }
  }

  return DryRunEventoResult(
    eventoId: eventoId,
    etiqueta: etiqueta,
    contratosActivos: activos.length,
    contratosProbados: resultados.length,
    contratos: resultados,
    fallos: fallos,
  );
}
