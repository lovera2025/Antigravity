import 'package:arguello_events/features/eventos/services/dry_run_cobro_simulator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// Totales del modal de cobro según medio de pago (réplica read-only del modal).
class ModalMedioPagoTotales {
  final String medio;
  final double sumLiquido;
  final double cargoCanal;
  final double totalMostrar;
  final double? efectivoMix;
  final double? transferMixMostrado;

  const ModalMedioPagoTotales({
    required this.medio,
    required this.sumLiquido,
    required this.cargoCanal,
    required this.totalMostrar,
    this.efectivoMix,
    this.transferMixMostrado,
  });

  static const empty = ModalMedioPagoTotales(
    medio: '',
    sumLiquido: 0,
    cargoCanal: 0,
    totalMostrar: 0,
  );
}

/// Réplica simplificada de `finalizarPreviewConCargoCanal` + totales PDF.
ModalMedioPagoTotales calcularTotalesModalReadonly({
  required String modoMedioPago,
  required double sumLiquido,
  bool informarPctTransferExterno = false,
  double pctCargo = 10.0,
}) {
  if (sumLiquido <= 0.01) return ModalMedioPagoTotales.empty;

  if (modoMedioPago == 'Efectivo') {
    return ModalMedioPagoTotales(
      medio: modoMedioPago,
      sumLiquido: sumLiquido,
      cargoCanal: 0,
      totalMostrar: double.parse(sumLiquido.toStringAsFixed(2)),
    );
  }

  var liquidoTr = sumLiquido;
  double? efectivoMix;
  if (modoMedioPago == 'Mixto') {
    efectivoMix = double.parse((sumLiquido / 2).toStringAsFixed(2));
    liquidoTr = double.parse((sumLiquido - efectivoMix).toStringAsFixed(2));
  }

  final cargo = informarPctTransferExterno
      ? double.parse((liquidoTr * pctCargo / 100).toStringAsFixed(2))
      : 0.0;
  final totalMostrar =
      double.parse((sumLiquido + cargo).toStringAsFixed(2));

  double? transferMix;
  if (modoMedioPago == 'Mixto') {
    transferMix = double.parse((liquidoTr + cargo).toStringAsFixed(2));
  }

  return ModalMedioPagoTotales(
    medio: modoMedioPago,
    sumLiquido: sumLiquido,
    cargoCanal: cargo,
    totalMostrar: totalMostrar,
    efectivoMix: efectivoMix,
    transferMixMostrado: transferMix,
  );
}

/// Simula el estado del alumno tras confirmar un cobro (solo lectura, sin DB).
ContratoAlumno aplicarCobroSimuladoReadonly({
  required ContratoAlumno alumno,
  required DryRunEscenarioResult escenario,
}) {
  if (!escenario.ok || escenario.grossPlan <= 0.01) return alumno;

  var nuevasBase = 0;
  var nuevasMesa = 0;
  var nuevasSillas = 0;

  switch (escenario.nombre) {
    case 'cuota_base_1':
    case 'cuota_base_parcial':
      nuevasBase = escenario.nombre == 'cuota_base_parcial' ? 0 : 1;
      break;
    case 'mesa_legacy':
    case String s when s.startsWith('mesa_'):
      nuevasMesa = 1;
      break;
    case 'sillas_1':
      nuevasSillas = 1;
      break;
    case 'combo_base_mesa':
      nuevasBase = 1;
      nuevasMesa = 1;
      break;
    case 'mora_pendiente':
      return alumno;
    default:
      break;
  }

  final saldoNuevo = double.parse(
    (alumno.saldoDeudor - escenario.grossPlan)
        .clamp(0.0, double.infinity)
        .toStringAsFixed(2),
  );

  return alumno.copyWith(
    saldoDeudor: saldoNuevo,
    cuotasPagadas: (alumno.cuotasPagadas + nuevasBase).clamp(0, alumno.totalCuotas),
    mesaExtraCuotasPagadas:
        (alumno.mesaExtraCuotasPagadas + nuevasMesa).clamp(0, alumno.mesaExtraCuotas),
    sillasExtraCuotasPagadas:
        (alumno.sillasExtraCuotasPagadas + nuevasSillas).clamp(0, alumno.sillasExtraCuotas),
  );
}

List<String> validarMediosPagoEscenario({
  required DryRunEscenarioResult escenario,
  bool conCargoTransfer = true,
}) {
  final fallos = <String>[];
  if (!escenario.ok || escenario.netPlan <= 0.01) return fallos;

  const medios = ['Efectivo', 'Transferencia', 'Mixto'];
  for (final medio in medios) {
    final informarCargo =
        conCargoTransfer && (medio == 'Transferencia' || medio == 'Mixto');
    final t = calcularTotalesModalReadonly(
      modoMedioPago: medio,
      sumLiquido: escenario.netPlan,
      informarPctTransferExterno: informarCargo,
    );

    if (medio == 'Efectivo') {
      if ((t.totalMostrar - escenario.netPlan).abs() > 0.03) {
        fallos.add(
          '$medio/${escenario.nombre}: total ${t.totalMostrar} != líquido ${escenario.netPlan}',
        );
      }
      if (t.cargoCanal > 0.01) {
        fallos.add('$medio/${escenario.nombre}: no debe tener cargo canal');
      }
    }

    if (medio == 'Transferencia' && informarCargo) {
      if (t.cargoCanal <= 0.01) {
        fallos.add('$medio/${escenario.nombre}: falta cargo canal');
      }
      if ((t.sumLiquido + t.cargoCanal - t.totalMostrar).abs() > 0.03) {
        fallos.add('$medio/${escenario.nombre}: total no cierra con cargo');
      }
    }

    if (medio == 'Mixto') {
      if (t.efectivoMix == null || t.transferMixMostrado == null) {
        fallos.add('$medio/${escenario.nombre}: faltan campos mixto');
        continue;
      }
      if ((t.efectivoMix! + t.transferMixMostrado! - t.totalMostrar).abs() > 0.03) {
        fallos.add('$medio/${escenario.nombre}: efectivo+transfer ≠ total');
      }
      if (informarCargo && t.cargoCanal <= 0.01) {
        fallos.add('$medio/${escenario.nombre}: mixto sin cargo en parte transfer');
      }
    }

    // PDF: líneas de concepto no cambian por medio de pago; el neto del plan es fijo.
    if (escenario.lineasPdf <= 0) {
      fallos.add('$medio/${escenario.nombre}: PDF sin líneas');
    }
    if ((escenario.netPlan - t.sumLiquido).abs() > 0.03) {
      fallos.add('$medio/${escenario.nombre}: líquido PDF ≠ preview');
    }
  }

  return fallos;
}

List<String> validarUiPostCobroSecuencial({
  required ContratoAlumno alumno,
  required List<Map<String, dynamic>> pagos,
}) {
  final fallos = <String>[];
  final antes = simularContratoDryRun(alumno: alumno, pagos: pagos);
  final esc = antes.escenarios
      .where((e) => e.ok && e.nombre == 'cuota_base_1' && e.grossPlan > 0.01)
      .toList();
  if (esc.isEmpty) return fallos;

  final e = esc.first;
  final despuesAlumno = aplicarCobroSimuladoReadonly(
    alumno: alumno,
    escenario: e,
  );

  if (despuesAlumno.saldoDeudor >= alumno.saldoDeudor - 0.01) {
    fallos.add(
      'UI: saldo no bajó tras cobro (${alumno.saldoDeudor} → ${despuesAlumno.saldoDeudor})',
    );
  }

  final despues = simularContratoDryRun(alumno: despuesAlumno, pagos: pagos);
  if (!despues.ok) {
    fallos.add('UI: dry-run falla tras simular cobro de ${alumno.nombreAlumno}');
  }

  if (despuesAlumno.cuotasPagadas <= alumno.cuotasPagadas &&
      e.nombre == 'cuota_base_1') {
    fallos.add('UI: cuotas_pagadas no avanzó tras cuota base');
  }

  return fallos;
}
