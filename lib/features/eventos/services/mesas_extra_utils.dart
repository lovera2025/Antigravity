import '../../../models/contrato_alumno.dart';
import '../../../models/mesa_extra_item.dart';
import '../../common/utils/currency_extensions.dart';

/// Utilidades para mesas extra múltiples (local-first, no destructivo).
class MesasExtraUtils {
  MesasExtraUtils._();

  /// A partir de esta cantidad de mesas activas, el modal de cobro usa UI compacta.
  static const int kUmbralUiCompactaMesasCobro = 3;

  static bool usarUiCompactaMesasCobro(int mesasActivas) =>
      mesasActivas >= kUmbralUiCompactaMesasCobro;

  /// Línea del preview de desglose que corresponde a una mesa extra.
  static bool esLineaPreviewMesa(Map<String, dynamic> c) {
    if (c['lineKind'] == 'interes_mora' ||
        c['lineKind'] == 'cargo_canal_ref') {
      return false;
    }
    if (c['mesaN'] != null) return true;
    final concepto = (c['concepto'] as String? ?? '').toLowerCase();
    return concepto.contains('mesa extra');
  }

  static double sumaMontosPreview(List<Map<String, dynamic>> lineas) =>
      lineas.fold<double>(
        0,
        (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
      );

  /// Título agrupado para el desglose cuando hay varias mesas en UI compacta.
  static String tituloGrupoDesgloseMesas(
    List<Map<String, dynamic>> lineasMesas,
  ) {
    if (lineasMesas.isEmpty) return 'Mesas Extra';

    final nums = lineasMesas
        .map((c) => c['mesaN'] as int?)
        .whereType<int>()
        .toList()
      ..sort();
    final count = lineasMesas.length;
    final firstMonto = (lineasMesas.first['monto'] as num?)?.toDouble() ?? 0;
    final allSameMonto = lineasMesas.every(
      (c) => ((c['monto'] as num?)?.toDouble() ?? 0) == firstMonto,
    );

    String? sufijoCuota(String concepto) {
      final match = RegExp(r'\(\d+/\d+\)').firstMatch(concepto);
      return match?.group(0);
    }

    final sufijos = lineasMesas
        .map((c) => sufijoCuota((c['concepto'] as String? ?? '')))
        .toSet();
    final allSameSufijoCuota =
        sufijos.length == 1 && sufijos.first != null && sufijos.first!.isNotEmpty;

    String rangoNumeros() {
      if (nums.isEmpty) return '';
      if (nums.length == 1) return '${nums.first}';
      if (nums.first == nums.last) return '${nums.first}';
      return '${nums.first}–${nums.last}';
    }

    final rango = rangoNumeros();
    final sufijoCuotaComun = sufijos.first;

    if (rango.isNotEmpty && allSameSufijoCuota && allSameMonto && count > 1) {
      return 'Mesas Extra $rango $sufijoCuotaComun c/u';
    }
    if (count == 1) {
      final concepto = lineasMesas.first['concepto'] as String? ?? '';
      return concepto.isNotEmpty ? concepto : 'Mesas Extra $rango';
    }
    return 'Mesas Extra ($count seleccionadas)';
  }

  static int contarMesasSeleccionadasCobro(Map<String, double> montosManuales) =>
      montosManuales.keys.where((k) => k.startsWith('Mesa:')).length;

  static double sumaBrutaMesasSeleccionadasCobro(
    Map<String, double> montosManuales,
  ) =>
      montosManuales.entries
          .where((e) => e.key.startsWith('Mesa:'))
          .fold<double>(0, (s, e) => s + e.value);

  /// Claves `Mesa:N` → monto bruto en el modal de cobro.
  static Map<String, double> montosManualesMesasDesde(
    Map<String, double> montosManuales,
  ) =>
      Map.fromEntries(
        montosManuales.entries.where((e) => e.key.startsWith('Mesa:')),
      );

  static void limpiarClavesMesasEnMontosManuales(
    Map<String, double> montosManuales,
  ) {
    montosManuales.removeWhere(
      (k, _) => k == 'Mesa' || k.startsWith('Mesa:'),
    );
  }

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

  /// Clave interna del modal de cobro para mesa [n].
  static String claveCobro(int n) => 'Mesa:$n';

  static int? mesaNumeroDesdeClave(String key) {
    if (key.startsWith('Mesa:')) {
      return int.tryParse(key.split(':').last);
    }
    return null;
  }

  /// Extrae número de mesa de un label/concepto UI (null si no hay dígito).
  static int? mesaNumeroDesdeTexto(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;
    final match = RegExp(
      r'mesa\s*extra\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(texto);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static bool usarNumeracion(int cantidadMesas) => cantidadMesas > 1;

  static String labelCobro(int n, int cantidadMesas) =>
      usarNumeracion(cantidadMesas) ? 'Mesa Extra $n' : 'Mesa Extra';

  static String tituloCobro(int n, int cantidadMesas) =>
      usarNumeracion(cantidadMesas) ? 'MESA EXTRA $n' : 'MESA EXTRA';

  /// Cantidad de mesas del contrato (fallback a lista parseada).
  static int cantidadMesasContrato(
    ContratoAlumno c,
    List<MesaExtraItem> mesasEstado,
  ) {
    if (c.mesaExtraCantidad > 0) return c.mesaExtraCantidad;
    if (mesasEstado.length > 1) return mesasEstado.length;
    return mesasEstado.isEmpty ? 0 : 1;
  }

  /// Resuelve ítem de mesa desde clave de cobro; nunca asume mesa 1 si hay una sola activa distinta.
  static MesaExtraItem resolveMesa({
    required String conceptoKey,
    required List<MesaExtraItem> mesasEstado,
    required List<MesaExtraItem> mesasActivas,
    required double precioUnitarioFallback,
  }) {
    final fromKey = mesaNumeroDesdeClave(conceptoKey);
    if (fromKey != null) {
      for (final m in mesasEstado) {
        if (m.n == fromKey) return m;
      }
      return MesaExtraItem(n: fromKey, precio: precioUnitarioFallback);
    }
    if (mesasActivas.length == 1) return mesasActivas.first;
    if (mesasEstado.length == 1) return mesasEstado.first;
    return MesaExtraItem(n: 1, precio: precioUnitarioFallback);
  }

  /// Rotulo estándar de cuota/entrega para una mesa concreta.
  static String conceptoCuotaDetallado({
    required MesaExtraItem item,
    required int cuotasPlan,
    required int cantidadMesas,
    int cuotaOffset = 1,
  }) {
    final prefix = labelCobro(item.n, cantidadMesas);
    if (cuotasPlan <= 1) return '$prefix - Entrega';
    final num =
        (item.cuotasPagadas + cuotaOffset).clamp(1, cuotasPlan + 99);
    return '$prefix ($num/$cuotasPlan)';
  }

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

    // FIFO state para pagos legacy sin número de mesa explícito.
    // Los pagos con número ≥ 2 se atribuyen directamente; los demás
    // se distribuyen cronológicamente llenando mesa 1 primero.
    double acumuladoFifo = 0.0;
    int mesaFifoActual = 1;
    final _regNumero = RegExp(r'mesa\s*extra\s*\d+', caseSensitive: false);

    for (final p in sorted) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
      final concepto = p['concepto'] as String? ?? '';
      if (!concepto.toLowerCase().contains('mesa')) continue;
      final gross =
          (p['monto_gross'] as num?)?.toDouble() ??
          (p['monto'] as num?)?.toDouble() ??
          0.0;
      if (gross <= 0.001) continue;

      final mesaExplicita = numeroMesaDesdeConcepto(concepto);
      // Un pago tiene número explícito si el concepto menciona "Mesa Extra N"
      // con N dígito (ej: "Mesa Extra 2 (1/7)"). Legacy = "Mesa Extra (2/7)".
      final tieneNumeroExplicito = _regNumero.hasMatch(concepto);

      int n;
      if (tieneNumeroExplicito && mesaExplicita > 1) {
        // Número de mesa ≥ 2 claramente escrito → atribuir directo.
        n = mesaExplicita.clamp(1, cantidad);
      } else {
        // Legacy (sin número o "Mesa Extra 1" ambiguo) → FIFO cronológico.
        if (mesaFifoActual < cantidad &&
            acumuladoFifo + gross > unit + 0.01) {
          mesaFifoActual++;
          acumuladoFifo = gross;
        } else {
          acumuladoFifo += gross;
        }
        n = mesaFifoActual;
      }

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

  /// Mesas físicas a sortear: 1 base + N extras contratadas.
  static int cantidadMesasFisicasSorteo(ContratoAlumno c) {
    if (c.mesaExtraPrecio <= 0.01) return 1;
    final mesas = estadoDesdeContrato(c);
    return 1 + cantidadMesasContrato(c, mesas);
  }

  /// Quita de [disponibles] y devuelve [cantidad] números (preferible consecutivos).
  static List<int>? tomarMesasDisponibles(List<int> disponibles, int cantidad) {
    if (cantidad < 1 || disponibles.length < cantidad) return null;

    if (cantidad == 1) {
      disponibles.shuffle();
      return [disponibles.removeLast()];
    }

    disponibles.sort();
    for (var i = 0; i <= disponibles.length - cantidad; i++) {
      var consecutivas = true;
      for (var j = 0; j < cantidad - 1; j++) {
        if (disponibles[i + j + 1] != disponibles[i + j] + 1) {
          consecutivas = false;
          break;
        }
      }
      if (consecutivas) {
        final picked = [for (var j = 0; j < cantidad; j++) disponibles[i + j]];
        for (final p in picked) {
          disponibles.remove(p);
        }
        return picked;
      }
    }

    disponibles.shuffle();
    if (disponibles.length < cantidad) return null;
    final picked = <int>[];
    for (var k = 0; k < cantidad; k++) {
      picked.add(disponibles.removeLast());
    }
    picked.sort();
    return picked;
  }

  static String formatearAsignacionMesas(List<int> numeros) =>
      numeros.map((n) => '$n').join(', ');

  /// Líneas compactas para la grilla de alumnos (solo lectura).
  static List<String> lineasResumenGrilla(ContratoAlumno c) {
    if (c.mesaExtraPrecio <= 0.01) return [];
    final mesas = estadoDesdeContrato(c);
    final activas = mesasActivas(mesas);
    if (activas.isEmpty) return [];

    final cant = cantidadMesasContrato(c, mesas);
    final cuotas = c.mesaExtraCuotas > 0 ? c.mesaExtraCuotas : 1;
    final numerar = usarNumeracion(cant);

    if (usarUiCompactaMesasCobro(activas.length)) {
      final deudaTotal = activas.fold<double>(0, (s, m) => s + m.deuda);
      if (deudaTotal <= 0.01) {
        return ['Mesas extra · liquidadas'];
      }
      return [
        'Mesas extra ($cant) · deuda ${deudaTotal.toCurrency()}',
      ];
    }

    return activas.map((m) {
      if (m.liquidada) {
        final label = numerar ? 'Mesa ${m.n}' : 'Mesa extra';
        return '$label · liquidada';
      }
      final label = numerar ? 'Mesa ${m.n}' : 'Mesa extra';
      return '$label · ${m.cuotasPagadas}/$cuotas · ${m.deuda.toCurrency()}';
    }).toList();
  }
}
