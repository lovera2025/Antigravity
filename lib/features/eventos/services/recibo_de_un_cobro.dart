import '../../../core/utils/pago_interes_mora.dart';
import '../../../models/contrato_alumno.dart';
import '../../cierre_caja/services/cobro_agrupado.dart';
import '../../common/utils/currency_extensions.dart';
import 'concepto_pago_display.dart';
import 'mora_concepto_rotulo.dart';
import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';
import 'mora_tracked_recovery.dart';

/// Lo que el recibo necesita de un cobro ya guardado, para reimprimirlo.
typedef CobroParaElRecibo = ({
  List<Map<String, dynamic>> conceptos,
  double montoPagado,
  String? medioPago,
  double? montoEfectivo,
  double? montoTransferencia,
  double porcentajeDescuento,
  DateTime? fecha,
});

/// La mora de hoy, para el recuadro rojo de un recibo reimpreso (fechado).
typedef MoraDeHoyParaElRecibo = ({
  double total,
  List<MoraCuotaDetalle> desglose,
  List<MoraPendientePreviaDetalle> arrastre,
  String origen,
});

/// Una sola regla para armar el recibo de un cobro que ya está guardado.
///
/// El jefe avisó el 14-nov-2026 que al reimprimir los recibos salían con menos
/// datos. Había tres caminos y cada uno armaba el papel a su manera:
/// - REIMPRIMIR de cada renglón del Estado de cuenta mandaba **solo ese
///   renglón**: un cobro de cuota + mora salía con una sola línea, y si era la
///   de la mora, el recuadro verde decía "Mora por pagar fuera de término" sin
///   cuota ni mes;
/// - "Generar recibo" de la grilla juntaba el último cobro, pero sumaba
///   también los renglones anulados;
/// - Mi Empresa → Finanzas no traía el recuadro rojo de la mora.
///
/// Ahora los tres juntan el cobro entero con [lineasDelCobro] y lo arman con
/// [armar]; la mora de hoy sale de [moraDeHoy]. Sin pantalla ni base: la
/// pantalla lee y le pasa los pagos.
class ReciboDeUnCobro {
  ReciboDeUnCobro._();

  static bool _anulado(Map<String, dynamic> p) =>
      ((p['anulado'] as num?)?.toInt() ?? 0) != 0;

  /// Las líneas del cobro al que pertenece [fila]: mismo contrato, misma caja,
  /// escritas a menos de [kVentanaCobro] una de otra (`esDelMismoCobro`, lo
  /// mismo que usa "anular todo el cobro"). **Sin anuladas.** De la más vieja
  /// a la más nueva.
  ///
  /// Se encadena: una línea entra si está cerca de alguna que ya entró, así un
  /// cobro largo no se parte según qué renglón se tocó.
  static List<Map<String, dynamic>> lineasDelCobro(
    List<Map<String, dynamic>> historial,
    Map<String, dynamic> fila,
  ) {
    final candidatas = historial.where((p) => !_anulado(p)).toList();
    final idFila = fila['id']?.toString();
    final dentro = <Map<String, dynamic>>[
      candidatas.firstWhere(
        (p) => idFila != null && p['id']?.toString() == idFila,
        orElse: () => fila,
      ),
    ];
    if (_anulado(dentro.first)) return const [];
    var agrego = true;
    while (agrego) {
      agrego = false;
      for (final p in candidatas) {
        if (dentro.any((d) => identical(d, p) || _mismoId(d, p))) continue;
        if (dentro.any((d) => esDelMismoCobro(d, p))) {
          dentro.add(p);
          agrego = true;
        }
      }
    }
    dentro.sort((a, b) => (a['fecha_pago']?.toString() ?? '')
        .compareTo(b['fecha_pago']?.toString() ?? ''));
    return dentro;
  }

  static bool _mismoId(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ia = a['id']?.toString();
    return ia != null && ia.isNotEmpty && ia == b['id']?.toString();
  }

  /// Lo que el recibo dice de ese cobro: sus líneas, el total, el medio (y el
  /// mixto), el descuento y la fecha. Las anuladas no cuentan.
  static CobroParaElRecibo armar({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> lote,
    required List<Map<String, dynamic>> historial,
  }) {
    final vivas = lote.where((p) => !_anulado(p)).toList();
    var efectivo = 0.0;
    var transferencia = 0.0;
    var descuento = 0.0;
    for (final p in vivas) {
      final m = (p['monto'] as num?)?.toDouble() ?? 0.0;
      final mp = ((p['medio_pago'] as String?)?.trim() ?? '').toLowerCase();
      if (mp == 'efectivo') {
        efectivo += m;
      } else if (mp.contains('transfer')) {
        transferencia += m;
      }
      final d = (p['descuento_porcentaje'] as num?)?.toDouble() ?? 0;
      if (d > descuento) descuento = d;
    }

    String? medio;
    double? montoEfectivo;
    double? montoTransferencia;
    if (efectivo > 0.01 && transferencia > 0.01) {
      medio = 'Mixto';
      montoEfectivo = efectivo;
      montoTransferencia = transferencia;
    } else if (efectivo > 0.01) {
      medio = 'Efectivo';
    } else if (transferencia > 0.01) {
      medio = 'Transferencia';
    }

    final conceptos = vivas.isEmpty
        ? <Map<String, dynamic>>[]
        : ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
            contrato,
            vivas,
            historialCompleto: historial,
          );
    final total = conceptos.fold<double>(
      0,
      (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0.0),
    );
    final fechaStr = vivas.isEmpty ? null : vivas.first['fecha_pago']?.toString();

    return (
      conceptos: conceptos,
      montoPagado: total,
      medioPago: medio,
      montoEfectivo: montoEfectivo,
      montoTransferencia: montoTransferencia,
      porcentajeDescuento: descuento,
      fecha: fechaStr == null ? null : DateTime.tryParse(fechaStr),
    );
  }

  /// La mora cobrada en todo el historial (lo mismo que
  /// `ContratosRepository.sumMoraCobradaHistorial`, sobre los pagos que ya se
  /// leyeron).
  static double moraCobradaHistorial(List<Map<String, dynamic>> historial) {
    var s = 0.0;
    for (final p in historial) {
      if (_anulado(p)) continue;
      final lk = (p['line_kind'] as String?)?.trim();
      final concepto = p['concepto'] as String? ?? '';
      if (lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(concepto)) {
        s += (p['monto'] as num?)?.toDouble() ?? 0;
      }
    }
    return double.parse(s.toStringAsFixed(2));
  }

  /// La mora que se debe hoy, cuota por cuota, para el recuadro rojo. En una
  /// reimpresión va fechada: no es la de aquel día, que no está guardada.
  static MoraDeHoyParaElRecibo moraDeHoy({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> historial,
    double? moraCobradaHistorial,
  }) {
    final detalle = MoraCuotaCalculator.moraPendienteOperativaDetallada(
      contrato: contrato,
      moraCobradaHistorial:
          moraCobradaHistorial ?? ReciboDeUnCobro.moraCobradaHistorial(historial),
    );
    final arrastre = detalle.tracked > 0.01
        ? MoraTrackedOrigen.inferir(
            contratoBase: contrato,
            pagos: historial,
            trackedMonto: detalle.tracked,
            recorte: MoraOrigenRecorte.loQueQueda,
          )
        : const <MoraPendientePreviaDetalle>[];
    final origen = MoraConceptoRotulo.origenMoraPendienteLinea(
      desglose: detalle.desglose,
      tracked: detalle.tracked,
      trackedDetalle: arrastre,
      formatoMonto: (v) => v.toCurrency(),
    );
    return (
      total: detalle.total,
      desglose: detalle.desglose,
      arrastre: arrastre,
      origen: origen,
    );
  }

  /// Si el recibo lleva la nota de la cuota pagada en partes. No con un perdón
  /// en la ficha: los perdones no tienen fecha y la nota podría contar mal lo
  /// que se pagó antes.
  static bool conNotas({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> historial,
  }) =>
      !MoraTrackedRecovery.tienePerdon(contrato: contrato, pagos: historial);
}
