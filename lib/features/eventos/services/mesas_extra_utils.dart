import '../../../models/contrato_alumno.dart';
import '../../../models/mesa_extra_item.dart';

/// Utilidades para mesas extra múltiples (local-first, no destructivo).
class MesasExtraUtils {
  MesasExtraUtils._();

  /// Extrae número de mesa del concepto de pago. Legacy sin número → 1.
  static int numeroMesaDesdeConcepto(String? concepto) {
    if (concepto == null || concepto.trim().isEmpty) return 1;
    final c = concepto.toLowerCase();
    if (!c.contains('mesa')) return 1;
    final match = RegExp(r'mesa\s*extra\s*(\d+)').firstMatch(c);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 1;
    }
    return 1;
  }

  /// Concepto estándar para registrar un pago sobre mesa [n].
  static String conceptoPagoMesa(int n) => 'Mesa Extra $n';

  /// Estado por mesa a partir del contrato; migra legacy si JSON vacío.
  static List<MesaExtraItem> estadoDesdeContrato(ContratoAlumno c) {
    final parsed = MesaExtraItem.listFromJson(c.mesasExtraEstadoRaw);
    if (parsed.isNotEmpty) {
      return _normalizar(parsed, c.mesaExtraCuotas);
    }
    if (c.mesaExtraPrecio <= 0.01) return [];

    final cant = c.mesaExtraCantidad > 0 ? c.mesaExtraCantidad : 1;
    if (cant == 1) {
      return [
        MesaExtraItem(
          n: 1,
          precio: c.mesaExtraPrecio,
          pagado: c.mesaExtraPagado,
          cuotasPagadas: c.mesaExtraCuotasPagadas,
          liquidada: c.mesaExtraPagado >= c.mesaExtraPrecio - 0.01,
        ),
      ];
    }

    return repartirPagadoFifo(
      cantidad: cant,
      precioUnitario: c.mesaExtraPrecio / cant,
      cuotasPlan: c.mesaExtraCuotas,
      pagadoTotal: c.mesaExtraPagado,
      cuotasPagadasLegacy: c.mesaExtraCuotasPagadas,
    );
  }

  static List<MesaExtraItem> _normalizar(
    List<MesaExtraItem> items,
    int cuotasPlan,
  ) {
    return items
        .map((m) {
          final liq = m.liquidada || m.pagado >= m.precio - 0.01;
          var cp = m.cuotasPagadas;
          if (cuotasPlan > 0 && m.precio > 0.01) {
            final cuota = m.cuotaPura(cuotasPlan);
            if (cuota > 0.01) {
              final fromMonto =
                  (m.pagado / cuota).floor().clamp(0, cuotasPlan);
              if (fromMonto > cp) cp = fromMonto;
            }
          }
          if (liq && cuotasPlan > 0) cp = cuotasPlan;
          return m.copyWith(cuotasPagadas: cp, liquidada: liq);
        })
        .toList()
      ..sort((a, b) => a.n.compareTo(b.n));
  }

  /// Reparte pagado total FIFO: llena mesa 1, luego mesa 2, etc.
  static List<MesaExtraItem> repartirPagadoFifo({
    required int cantidad,
    required double precioUnitario,
    required int cuotasPlan,
    required double pagadoTotal,
    int cuotasPagadasLegacy = 0,
  }) {
    if (cantidad < 1) return [];
    final unit = double.parse(precioUnitario.toStringAsFixed(2));
    var restante = double.parse(pagadoTotal.toStringAsFixed(2));
    var cuotasRestantesLegacy = cuotasPagadasLegacy;

    final out = <MesaExtraItem>[];
    for (var i = 1; i <= cantidad; i++) {
      final asignado = restante.clamp(0.0, unit);
      restante = double.parse((restante - asignado).toStringAsFixed(2));
      final cuota = cuotasPlan > 0 ? unit / cuotasPlan : unit;
      int cp = 0;
      if (cuota > 0.01) {
        cp = (asignado / cuota).floor().clamp(0, cuotasPlan);
      }
      if (cuotasRestantesLegacy > 0) {
        final use = cuotasRestantesLegacy.clamp(0, cuotasPlan);
        if (use > cp) cp = use;
        cuotasRestantesLegacy -= use;
      }
      final liq = asignado >= unit - 0.01;
      if (liq && cuotasPlan > 0) cp = cuotasPlan;
      out.add(
        MesaExtraItem(
          n: i,
          precio: unit,
          pagado: asignado,
          cuotasPagadas: cp,
          liquidada: liq,
        ),
      );
    }
    return out;
  }

  /// Construye estado al guardar edición: conserva pagos en mesas existentes.
  static List<MesaExtraItem> construirParaGuardar({
    required int cantidadNueva,
    required double precioUnitario,
    required int cuotasPlan,
    required List<MesaExtraItem> estadoAnterior,
    double? pagadoTotalFallback,
  }) {
    if (cantidadNueva < 1) return [];
    final unit = double.parse(precioUnitario.toStringAsFixed(2));
    final prevByN = {for (final m in estadoAnterior) m.n: m};
    final out = <MesaExtraItem>[];

    for (var i = 1; i <= cantidadNueva; i++) {
      final prev = prevByN[i];
      if (prev != null) {
        final nuevoPrecio = unit;
        final pagado = prev.pagado.clamp(0.0, nuevoPrecio);
        final liq = prev.liquidada || pagado >= nuevoPrecio - 0.01;
        var cp = prev.cuotasPagadas;
        if (cuotasPlan > 0 && unit > 0) {
          final cuota = unit / cuotasPlan;
          if (cuota > 0.01) {
            final fromPag = (pagado / cuota).floor().clamp(0, cuotasPlan);
            if (fromPag > cp) cp = fromPag;
          }
        }
        if (liq && cuotasPlan > 0) cp = cuotasPlan;
        out.add(
          MesaExtraItem(
            n: i,
            precio: nuevoPrecio,
            pagado: pagado,
            cuotasPagadas: cp,
            liquidada: liq,
          ),
        );
      } else {
        out.add(
          MesaExtraItem(
            n: i,
            precio: unit,
            pagado: 0,
            cuotasPagadas: 0,
            liquidada: false,
          ),
        );
      }
    }

    if (out.isEmpty && pagadoTotalFallback != null && pagadoTotalFallback > 0) {
      return repartirPagadoFifo(
        cantidad: cantidadNueva,
        precioUnitario: unit,
        cuotasPlan: cuotasPlan,
        pagadoTotal: pagadoTotalFallback,
      );
    }

    return out;
  }

  /// Reconstruye estado desde historial de pagos (solo lectura de pagos).
  static List<MesaExtraItem> reconciliarDesdePagos({
    required int cantidad,
    required double precioUnitario,
    required int cuotasPlan,
    required Iterable<Map<String, dynamic>> pagos,
  }) {
    if (cantidad < 1 || precioUnitario <= 0.01) return [];

    final unit = double.parse(precioUnitario.toStringAsFixed(2));
    final pagadoPorMesa = <int, double>{};
    for (var i = 1; i <= cantidad; i++) {
      pagadoPorMesa[i] = 0.0;
    }

    final sorted = pagos.toList()
      ..sort((a, b) {
        final fa = DateTime.tryParse(a['fecha_pago'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final fb = DateTime.tryParse(b['fecha_pago'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return fa.compareTo(fb);
      });

    for (final p in sorted) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
      final concepto = p['concepto'] as String? ?? '';
      if (!concepto.toLowerCase().contains('mesa')) continue;
      final n = numeroMesaDesdeConcepto(concepto).clamp(1, cantidad);
      final gross =
          (p['monto_gross'] as num?)?.toDouble() ??
          (p['monto'] as num?)?.toDouble() ??
          0.0;
      pagadoPorMesa[n] = (pagadoPorMesa[n] ?? 0) + gross;
    }

    return List.generate(cantidad, (i) {
      final n = i + 1;
      final pagado =
          double.parse((pagadoPorMesa[n] ?? 0).toStringAsFixed(2));
      final liq = pagado >= unit - 0.01;
      var cp = 0;
      if (cuotasPlan > 0 && unit > 0) {
        final cuota = unit / cuotasPlan;
        if (cuota > 0.01) {
          cp = (pagado / cuota).floor().clamp(0, cuotasPlan);
        }
      }
      if (liq && cuotasPlan > 0) cp = cuotasPlan;
      return MesaExtraItem(
        n: n,
        precio: unit,
        pagado: pagado.clamp(0.0, unit),
        cuotasPagadas: cp,
        liquidada: liq,
      );
    });
  }

  static double totalPagado(List<MesaExtraItem> mesas) =>
      mesas.fold(0.0, (s, m) => s + m.pagado);

  static int maxCuotasPagadas(List<MesaExtraItem> mesas) {
    if (mesas.isEmpty) return 0;
    return mesas.map((m) => m.cuotasPagadas).reduce((a, b) => a > b ? a : b);
  }

  static List<MesaExtraItem> mesasActivas(List<MesaExtraItem> mesas) =>
      mesas.where((m) => m.activa).toList();

  /// ¿Se puede bajar la cantidad a [nuevaCantidad]?
  static bool puedeReducirCantidad(
    List<MesaExtraItem> estado,
    int nuevaCantidad,
  ) {
    for (final m in estado) {
      if (m.n > nuevaCantidad && m.pagado > 0.01) return false;
    }
    return true;
  }
}
