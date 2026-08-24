import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';

/// Vencimiento de una cuota del plan base.
class ProximoVencimientoCuota {
  final int numeroCuota;
  final DateTime vencimiento;
  final bool yaVencida;

  const ProximoVencimientoCuota({
    required this.numeroCuota,
    required this.vencimiento,
    required this.yaVencida,
  });
}

/// Líneas informativas de cronograma para grilla / modal.
class CronogramaCuotaLineas {
  final String? cuotaPendiente;
  final String? proximoVencimiento;
  final String? moraCongeladaHasta;

  const CronogramaCuotaLineas({
    this.cuotaPendiente,
    this.proximoVencimiento,
    this.moraCongeladaHasta,
  });

  bool get tieneAlguna =>
      cuotaPendiente != null ||
      proximoVencimiento != null ||
      moraCongeladaHasta != null;
}

/// Estado de deuda en grilla (sin depender solo de mora en pesos).
enum ContratoEstadoDeudaKind {
  liquidado,
  cuotasAtrasadas,
  moraVencida,
  moraPendiente,

  /// Terminó de pagar las cuotas pero le quedó mora sin cobrar.
  ///
  /// No es [liquidado]: el plan está saldado, la deuda no. Mientras los dos
  /// estados eran el mismo, la ficha decía LIQUIDADO en verde y dos renglones
  /// más abajo "Mora pendiente: $X" — la misma celda contradiciéndose.
  planSaldadoConMora,
  alDia,
}

class ContratoEstadoDeudaUi {
  final ContratoEstadoDeudaKind kind;
  final String texto;
  final Color color;
  final IconData icono;

  const ContratoEstadoDeudaUi({
    required this.kind,
    required this.texto,
    required this.color,
    required this.icono,
  });
}

/// Cronograma de cuotas base (alta + mes k). No calcula montos de mora.
class CronogramaCuotasUtils {
  CronogramaCuotasUtils._();

  static const Color colorAlDia = Color(0xFFD4AF37);
  static const Color colorCuotasAtrasadas = Colors.redAccent;
  static const Color colorMoraVencida = Colors.redAccent;
  static const Color colorMoraPendiente = Colors.deepOrangeAccent;
  static const Color colorLiquidado = Colors.greenAccent;
  static const Color colorPlanSaldadoConMora = Colors.deepOrangeAccent;

  /// Eventos/colegios que conservan su [created_at] real (no Reg unificado).
  static bool excluidoDeRegUnificado({
    String? clienteNombre,
    String? eventoTipo,
    String? institucion,
  }) {
    final blob = [
      clienteNombre ?? '',
      eventoTipo ?? '',
      institucion ?? '',
    ].join(' ').toUpperCase();
    return blob.contains('BUENA VISTA') || blob.contains('PUERTO VIEJO');
  }

  static DateTime _hoySolo(DateTime? ahoraAr) {
    final hoy = ahoraAr ?? ArTime.nowAr();
    return DateTime(hoy.year, hoy.month, hoy.day);
  }

  static DateTime _inscripcionAr(ContratoAlumno c, DateTime hoySolo) {
    return c.createdAt != null ? ArTime.toAr(c.createdAt!) : hoySolo;
  }

  /// Último día del mes (inscripción.month + k). Misma regla que mora.
  static DateTime vencimientoCuotaK(DateTime inscripcionAr, int k) {
    var m = inscripcionAr.month + k;
    var y = inscripcionAr.year;
    while (m > 12) {
      m -= 12;
      y++;
    }
    return DateTime(y, m, DateTime(y, m + 1, 0).day);
  }

  /// Cuotas impagas cuyo vencimiento ya pasó.
  static int cuotasImpagasVencidas(ContratoAlumno c, [DateTime? ahoraAr]) {
    if (c.saldoDeudor <= 0.01) return 0;
    final hoySolo = _hoySolo(ahoraAr);
    final inscAr = _inscripcionAr(c, hoySolo);
    final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;
    final cPag = c.cuotasPagadas.clamp(0, tCuotas);

    var count = 0;
    for (var k = cPag + 1; k <= tCuotas; k++) {
      final v = vencimientoCuotaK(inscAr, k);
      final vKSolo = DateTime(v.year, v.month, v.day);
      if (hoySolo.isAfter(vKSolo)) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static bool cronogramaAlDia(ContratoAlumno c, [DateTime? ahoraAr]) =>
      cuotasImpagasVencidas(c, ahoraAr) == 0;

  /// Siguiente cuota a liquidar en orden (cPagadas + 1).
  static ProximoVencimientoCuota? proximaCuotaSecuencial(
    ContratoAlumno c, [
    DateTime? ahoraAr,
  ]) {
    if (c.saldoDeudor <= 0.01) return null;
    final hoySolo = _hoySolo(ahoraAr);
    final inscAr = _inscripcionAr(c, hoySolo);
    final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;
    final k = c.cuotasPagadas + 1;
    if (k > tCuotas) return null;
    final v = vencimientoCuotaK(inscAr, k);
    final vSolo = DateTime(v.year, v.month, v.day);
    return ProximoVencimientoCuota(
      numeroCuota: k,
      vencimiento: v,
      yaVencida: hoySolo.isAfter(vSolo),
    );
  }

  /// Primera cuota impaga con vencimiento hoy o futuro.
  static ProximoVencimientoCuota? proximoVencimientoFuturo(
    ContratoAlumno c, [
    DateTime? ahoraAr,
  ]) {
    if (c.saldoDeudor <= 0.01) return null;
    final hoySolo = _hoySolo(ahoraAr);
    final inscAr = _inscripcionAr(c, hoySolo);
    final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;

    for (var k = c.cuotasPagadas + 1; k <= tCuotas; k++) {
      final v = vencimientoCuotaK(inscAr, k);
      final vSolo = DateTime(v.year, v.month, v.day);
      if (!hoySolo.isAfter(vSolo)) {
        return ProximoVencimientoCuota(
          numeroCuota: k,
          vencimiento: v,
          yaVencida: false,
        );
      }
    }
    return null;
  }

  /// Fin de exención de mora o vencimiento secuencial si no hay exención.
  static DateTime? proximoLimiteMora(ContratoAlumno c, [DateTime? ahoraAr]) {
    if (c.saldoDeudor <= 0.01) return null;
    final hoySolo = _hoySolo(ahoraAr);
    if (c.moraExentaHasta != null) {
      final ex = DateTime(
        c.moraExentaHasta!.year,
        c.moraExentaHasta!.month,
        c.moraExentaHasta!.day,
      );
      if (!hoySolo.isAfter(ex)) return ex;
    }
    return proximaCuotaSecuencial(c, ahoraAr)?.vencimiento;
  }

  static CronogramaCuotaLineas lineasInformativas(
    ContratoAlumno c, {
    DateTime? ahoraAr,
    double moraPendientePesos = 0,
  }) {
    if (c.saldoDeudor <= 0.01) {
      return const CronogramaCuotaLineas();
    }
    final sec = proximaCuotaSecuencial(c, ahoraAr);
    final futuro = proximoVencimientoFuturo(c, ahoraAr);
    final limite = proximoLimiteMora(c, ahoraAr);
    final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;

    String? cuotaPendiente;
    if (sec != null) {
      final vto = ArTime.formatFechaCorta(sec.vencimiento);
      cuotaPendiente = sec.yaVencida
          ? 'Cuota pendiente: ${sec.numeroCuota}/$tCuotas (vto. $vto — vencida)'
          : 'Cuota pendiente: ${sec.numeroCuota}/$tCuotas (vto. $vto)';
    }

    String? proximoVencimiento;
    if (sec != null &&
        sec.yaVencida &&
        futuro != null &&
        futuro.numeroCuota != sec.numeroCuota) {
      proximoVencimiento =
          'Próx. vencimiento: ${ArTime.formatFechaCorta(futuro.vencimiento)} (cuota ${futuro.numeroCuota})';
    }

    String? moraCongelada;
    if (moraPendientePesos <= 0.01 &&
        c.moraExentaHasta != null &&
        limite != null) {
      final hoySolo = _hoySolo(ahoraAr);
      final ex = DateTime(
        c.moraExentaHasta!.year,
        c.moraExentaHasta!.month,
        c.moraExentaHasta!.day,
      );
      if (!hoySolo.isAfter(ex)) {
        moraCongelada =
            'Mora congelada hasta: ${ArTime.formatFechaCorta(ex)}';
      }
    }

    return CronogramaCuotaLineas(
      cuotaPendiente: cuotaPendiente,
      proximoVencimiento: proximoVencimiento,
      moraCongeladaHasta: moraCongelada,
    );
  }

  static ContratoEstadoDeudaUi resolverEstadoUi({
    required ContratoAlumno contrato,
    required bool moraEnMora,
    required double moraPendientePesos,
    DateTime? ahoraAr,
  }) {
    if (contrato.saldoDeudor <= 0.01) {
      // El plan saldado no implica que no deba nada: la mora que no se cobró al
      // liquidar queda en ficha y sobrevive al saldo cero.
      if (moraPendientePesos > 0.01) {
        return const ContratoEstadoDeudaUi(
          kind: ContratoEstadoDeudaKind.planSaldadoConMora,
          texto: 'PLAN SALDADO · DEBE MORA',
          color: colorPlanSaldadoConMora,
          icono: Icons.pending_actions_rounded,
        );
      }
      return const ContratoEstadoDeudaUi(
        kind: ContratoEstadoDeudaKind.liquidado,
        texto: 'LIQUIDADO',
        color: colorLiquidado,
        icono: Icons.verified_rounded,
      );
    }

    final cuotasAtrasadas = cuotasImpagasVencidas(contrato, ahoraAr) > 0;
    final moraPesos = moraPendientePesos > 0.01;

    if (moraEnMora) {
      return const ContratoEstadoDeudaUi(
        kind: ContratoEstadoDeudaKind.moraVencida,
        texto: 'MORA VENCIDA',
        color: colorMoraVencida,
        icono: Icons.warning_amber_rounded,
      );
    }

    if (cuotasAtrasadas) {
      return const ContratoEstadoDeudaUi(
        kind: ContratoEstadoDeudaKind.cuotasAtrasadas,
        texto: 'CUOTAS ATRASADAS',
        color: colorCuotasAtrasadas,
        icono: Icons.warning_amber_rounded,
      );
    }

    if (moraPesos) {
      return const ContratoEstadoDeudaUi(
        kind: ContratoEstadoDeudaKind.moraPendiente,
        texto: 'MORA PENDIENTE',
        color: colorMoraPendiente,
        icono: Icons.pending_actions_rounded,
      );
    }

    return const ContratoEstadoDeudaUi(
      kind: ContratoEstadoDeudaKind.alDia,
      texto: 'AL DÍA',
      color: colorAlDia,
      icono: Icons.info_outline_rounded,
    );
  }
}
