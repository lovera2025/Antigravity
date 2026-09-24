import '../../../models/contrato_alumno.dart';
import '../../../models/mesa_extra_item.dart';
import '../../common/utils/currency_extensions.dart';

/// Resultado del diálogo de sorteo.
class SorteoMesasDialogResult {
  final int capacidadSalon;

  /// Alumno → cuántas de sus mesas van sueltas, lejos de su bloque.
  final Map<String, int> separaciones;

  /// "Solo a lo que tiene algo pagado" (true) o "a todo lo cargado" (false).
  final bool soloPagado;

  /// Casillas "sortear igual" de los que no pagaron nada de la base.
  final Set<String> incluirBase;

  /// Casillas "sortear igual" de los que no pagaron nada de sus mesas extra.
  final Set<String> incluirExtras;

  const SorteoMesasDialogResult({
    required this.capacidadSalon,
    this.separaciones = const {},
    this.soloPagado = false,
    this.incluirBase = const {},
    this.incluirExtras = const {},
  });
}

/// Pago de mesa legacy a renombrar tras reconciliar entregas colapsadas.
class RenombreConceptoMesa {
  final String pagoId;
  final String conceptoNuevo;

  const RenombreConceptoMesa({
    required this.pagoId,
    required this.conceptoNuevo,
  });
}

/// Resultado de inferir mesas desde entregas legacy (tipo Ojeda).
class InferenciaEntregasMesas {
  final int cantidad;
  final List<RenombreConceptoMesa> renombres;

  const InferenciaEntregasMesas({
    required this.cantidad,
    required this.renombres,
  });
}

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

  /// Pago guardado con "Mesa Extra N" explícito (no legacy "(2/7)" sin N).
  static bool pagoConceptoTieneMesaNumeradaExplicita(String? concepto) {
    if (concepto == null || concepto.trim().isEmpty) return false;
    if (!concepto.toLowerCase().contains('mesa')) return false;
    return RegExp(r'mesa\s*extra\s*\d+', caseSensitive: false)
        .hasMatch(concepto);
  }

  /// Garantiza número de mesa en el concepto persistido (alineado al preview/PDF).
  static String conceptoPagoPersistido({
    required Map<String, dynamic> previewLinea,
    required String conceptoOriginal,
    required int cantidadMesas,
  }) {
    final c = conceptoOriginal.trim();
    if (c.isEmpty) return c;
    if (!c.toLowerCase().contains('mesa')) return c;
    if (pagoConceptoTieneMesaNumeradaExplicita(c)) return c;

    final mesaN = (previewLinea['mesaN'] as int?) ??
        mesaNumeroDesdeTexto(c) ??
        numeroMesaDesdeConcepto(c);
    final prefix = labelCobro(mesaN, cantidadMesas > 0 ? cantidadMesas : 1);
    final cuotaSuf = RegExp(r'\(\d+/\d+\)').firstMatch(c)?.group(0);
    if (cuotaSuf != null) return '$prefix $cuotaSuf';
    return prefix;
  }

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

  /// Cantidad de mesas extra del contrato (campo + estado JSON).
  static int cantidadMesasContrato(
    ContratoAlumno c,
    List<MesaExtraItem> mesasEstado,
  ) {
    if (c.mesaExtraPrecio <= 0.01) return 0;
    final desdeCampo = c.mesaExtraCantidad > 0 ? c.mesaExtraCantidad : 0;
    final desdeEstado = mesasEstado.length;
    var cant = desdeCampo > desdeEstado ? desdeCampo : desdeEstado;
    if (cant < 1) cant = 1;
    return cant;
  }

  /// Mayor N en conceptos "Mesa Extra N" del historial de pagos.
  static int maxMesaNumeradaEnPagos(Iterable<Map<String, dynamic>> pagos) {
    var max = 0;
    for (final p in pagos) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
      final concepto = p['concepto'] as String? ?? '';
      if (!concepto.toLowerCase().contains('mesa')) continue;
      if (!pagoConceptoTieneMesaNumeradaExplicita(concepto)) continue;
      final n = numeroMesaDesdeConcepto(concepto);
      if (n > max) max = n;
    }
    return max;
  }

  /// Concepto de mesa en cuotas `(n/m)` — no confundir con entregas.
  static bool esConceptoMesaEnCuotas(String? concepto) {
    if (concepto == null || concepto.trim().isEmpty) return false;
    final c = concepto.toLowerCase();
    if (!c.contains('mesa')) return false;
    return RegExp(r'\(\s*\d+\s*/\s*\d+\s*\)').hasMatch(c);
  }

  /// Entrega de mesa sin número explícito (legacy).
  static bool esConceptoMesaEntregaLegacy(String? concepto) {
    if (concepto == null || concepto.trim().isEmpty) return false;
    final c = concepto.toLowerCase();
    if (!c.contains('mesa')) return false;
    if (esConceptoMoraOCanal(concepto)) return false;
    if (esConceptoMesaEnCuotas(concepto)) return false;
    return true;
  }

  static bool esConceptoMoraOCanal(String? concepto) {
    final c = (concepto ?? '').toLowerCase();
    return c.contains('mora') || c.contains('cargo canal');
  }

  static double _grossPago(Map<String, dynamic> p) =>
      (p['monto_gross'] as num?)?.toDouble() ??
      (p['monto'] as num?)?.toDouble() ??
      0.0;

  static DateTime? _fechaPago(Map<String, dynamic> p) {
    final raw = p['fecha_pago'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Detecta N mesas colapsadas en 1 cuando hay N entregas legacy en lotes distintos.
  ///
  /// No aplica si el plan es en cuotas (`mesa_extra_cuotas > 1`) o hay pagos `(n/m)`.
  /// Mixto de una sola mesa (varios medios en el mismo minuto) = 1 lote → no parte.
  static InferenciaEntregasMesas? inferirEntregasMesasColapsadas({
    required ContratoAlumno c,
    required Iterable<Map<String, dynamic>> pagos,
  }) {
    if (c.mesaExtraPrecio <= 0.01) return null;
    if (c.mesaExtraCuotas > 1) return null;

    final mesaPagos = pagos.where((p) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
      final concepto = p['concepto'] as String? ?? '';
      if (!concepto.toLowerCase().contains('mesa')) return false;
      if (esConceptoMoraOCanal(concepto)) return false;
      return true;
    }).toList();

    if (mesaPagos.any((p) => esConceptoMesaEnCuotas(p['concepto'] as String?))) {
      return null;
    }
    if (mesaPagos.any(
      (p) => pagoConceptoTieneMesaNumeradaExplicita(p['concepto'] as String?),
    )) {
      return null;
    }

    final entregas = mesaPagos
        .where((p) => esConceptoMesaEntregaLegacy(p['concepto'] as String?))
        .where((p) => _grossPago(p) > 0.01)
        .toList()
      ..sort((a, b) {
        final fa = _fechaPago(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final fb = _fechaPago(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return fa.compareTo(fb);
      });

    if (entregas.length < 2) return null;

    // Agrupar por lote: gap > 90s = nueva entrega (Ojeda 17:32 vs 17:35).
    final lotes = <List<Map<String, dynamic>>>[];
    for (final p in entregas) {
      if (lotes.isEmpty) {
        lotes.add([p]);
        continue;
      }
      final prev = lotes.last.last;
      final tPrev = _fechaPago(prev);
      final tCur = _fechaPago(p);
      if (tPrev != null &&
          tCur != null &&
          tCur.difference(tPrev).inSeconds.abs() <= 90) {
        lotes.last.add(p);
      } else {
        lotes.add([p]);
      }
    }

    if (lotes.length < 2) return null;

    final montosLote = lotes
        .map(
          (lote) => double.parse(
            lote.fold<double>(0, (s, p) => s + _grossPago(p)).toStringAsFixed(2),
          ),
        )
        .toList();
    final primero = montosLote.first;
    if (primero <= 0.01) return null;
    final mismosMontos = montosLote.every((m) => (m - primero).abs() <= 0.5);
    if (!mismosMontos) return null;

    final suma = double.parse(
      montosLote.fold<double>(0, (s, m) => s + m).toStringAsFixed(2),
    );
    if ((suma - c.mesaExtraPrecio).abs() > 1.0) return null;

    final k = lotes.length;
    final renombres = <RenombreConceptoMesa>[];
    for (var i = 0; i < lotes.length; i++) {
      final n = i + 1;
      final concepto = k > 1 ? 'Mesa Extra $n - Entrega' : 'Mesa Extra - Entrega';
      for (final p in lotes[i]) {
        final id = p['id'] as String?;
        if (id == null || id.isEmpty) continue;
        renombres.add(RenombreConceptoMesa(pagoId: id, conceptoNuevo: concepto));
      }
    }

    return InferenciaEntregasMesas(cantidad: k, renombres: renombres);
  }

  /// Cantidad extra inferida: campo, estado, pagos numerados y entregas colapsadas.
  static int inferirCantidadMesasExtraContrato(
    ContratoAlumno c, {
    Iterable<Map<String, dynamic>>? pagos,
  }) {
    if (c.mesaExtraPrecio <= 0.01) return 0;
    final estado = MesaExtraItem.listFromJson(c.mesasExtraEstadoRaw);
    final desdeCampo = c.mesaExtraCantidad > 0 ? c.mesaExtraCantidad : 0;
    final desdeEstado = estado.length;
    final desdePagos =
        pagos != null ? maxMesaNumeradaEnPagos(pagos) : 0;
    var cant = desdeCampo;
    if (desdeEstado > cant) cant = desdeEstado;
    if (desdePagos > cant) cant = desdePagos;

    if (pagos != null) {
      final entregas = inferirEntregasMesasColapsadas(c: c, pagos: pagos);
      if (entregas != null && entregas.cantidad > cant) {
        cant = entregas.cantidad;
      }
    }

    if (cant < 1) cant = 1;
    return cant;
  }

  /// Rangos como "40-42" o "40 al 42": como mucho esta cantidad de mesas, para
  /// que un número mal tipeado ("4-400") no se convierta en cientos de mesas.
  static const int _maxMesasPorRango = 20;

  /// Números de mesa de un texto, como los guarda el sorteo ("12, 13, 14") o
  /// como alguien los cargó a mano: "40-42", "40 al 42", "40 y 41", "40/41".
  ///
  /// Lo que está entre paréntesis no se lee: "12-14 (2 extra)" es 12, 13 y 14,
  /// no también la mesa 2.
  static Set<int> numerosMesaDesdeTexto(String? numeroMesa) {
    if (numeroMesa == null || numeroMesa.trim().isEmpty) return {};
    var texto = numeroMesa.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), ' ');
    final numeros = <int>{};
    texto = texto.replaceAllMapped(
      RegExp(r'(\d+)\s*(?:-|–|—|\bal\b|\ba\b)\s*(\d+)'),
      (m) {
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        if (b >= a && b - a < _maxMesasPorRango) {
          for (var n = a; n <= b; n++) {
            numeros.add(n);
          }
        } else {
          numeros
            ..add(a)
            ..add(b);
        }
        return ' ';
      },
    );
    for (final m in RegExp(r'\d+').allMatches(texto)) {
      numeros.add(int.parse(m.group(0)!));
    }
    numeros.remove(0);
    return numeros;
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
      if (tieneNumeroExplicito) {
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

  /// Cuántas mesas extra tiene el contrato y cuánto lleva pagado cada una,
  /// según sus pagos. Es la cuenta que guarda
  /// `ContratosRepository.reconciliarMesasEstadoContrato`, sin tocar la base:
  /// así un script de corrección calcula exactamente lo mismo que la app.
  ///
  /// [pagos] tienen que venir ya con los rótulos corregidos, si
  /// [inferirEntregasMesasColapsadas] pidió renombrar alguno.
  /// Sin precio de mesa extra devuelve `null`: no hay nada que reconciliar.
  static ({int cantidad, List<MesaExtraItem> mesas})? estadoMesasReconciliado({
    required ContratoAlumno contrato,
    required List<Map<String, dynamic>> pagos,
  }) {
    if (contrato.mesaExtraPrecio <= 0.01) return null;

    final cant = inferirCantidadMesasExtraContrato(contrato, pagos: pagos);
    final unit = cant > 0
        ? double.parse((contrato.mesaExtraPrecio / cant).toStringAsFixed(2))
        : contrato.mesaExtraPrecio;

    final tienePagosMesaNumerados = pagos.any((p) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
      return pagoConceptoTieneMesaNumeradaExplicita(p['concepto'] as String?);
    });

    final mesas = tienePagosMesaNumerados
        ? reconciliarDesdePagos(
            cantidad: cant,
            precioUnitario: unit,
            cuotasPlan: contrato.mesaExtraCuotas,
            pagos: pagos,
          )
        : repartirPagadoFifo(
            cantidad: cant,
            precioUnitario: unit,
            cuotasPlan: contrato.mesaExtraCuotas,
            pagadoTotal: _grossPagadoMesa(pagos),
            cuotasPagadasLegacy: 0,
          );
    return (cantidad: cant, mesas: mesas);
  }

  static double _grossPagadoMesa(Iterable<Map<String, dynamic>> pagos) {
    var total = 0.0;
    for (final p in pagos) {
      if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
      final concepto = (p['concepto'] as String? ?? '').toLowerCase();
      if (!concepto.contains('mesa')) continue;
      total += _grossPago(p);
    }
    return double.parse(total.toStringAsFixed(2));
  }

  static double totalPagado(List<MesaExtraItem> mesas) =>
      mesas.fold(0.0, (s, m) => s + m.pagado);

  static int maxCuotasPagadas(List<MesaExtraItem> mesas) {
    if (mesas.isEmpty) return 0;
    return mesas.map((m) => m.cuotasPagadas).reduce((a, b) => a > b ? a : b);
  }

  static List<MesaExtraItem> mesasActivas(List<MesaExtraItem> mesas) =>
      mesas.where((m) => m.activa).toList();

  /// Aplica montos del preview de cobro al estado por mesa (update optimista UI).
  static List<MesaExtraItem> aplicarCobroPreviewAEstado({
    required List<MesaExtraItem> estado,
    required Iterable<Map<String, dynamic>> lineasPreview,
    required int cuotasPlan,
  }) {
    if (estado.isEmpty) return estado;

    final byN = {for (final m in estado) m.n: m};
    var changed = false;

    for (final c in lineasPreview) {
      if (!esLineaPreviewMesa(c)) continue;
      final gross =
          (c['gross'] as num?)?.toDouble() ??
          (c['monto'] as num?)?.toDouble() ??
          0.0;
      if (gross <= 0.001) continue;

      final n = (c['mesaN'] as int?) ??
          numeroMesaDesdeConcepto(c['concepto'] as String?);
      final prev = byN[n];
      if (prev == null) continue;

      final clampedPagado = double.parse(
        (prev.pagado + gross).clamp(0.0, prev.precio).toStringAsFixed(2),
      );
      var cp = prev.cuotasPagadas;
      if (cuotasPlan > 0 && prev.precio > 0.01) {
        final cuota = prev.cuotaPura(cuotasPlan);
        if (cuota > 0.01) {
          final fromPag =
              (clampedPagado / cuota).floor().clamp(0, cuotasPlan);
          if (fromPag > cp) cp = fromPag;
        }
      }
      final liq = clampedPagado >= prev.precio - 0.01;
      if (liq && cuotasPlan > 0) cp = cuotasPlan;
      byN[n] = prev.copyWith(
        pagado: clampedPagado,
        cuotasPagadas: cp,
        liquidada: liq,
      );
      changed = true;
    }

    if (!changed) return estado;
    return _normalizar(byN.values.toList(), cuotasPlan);
  }

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

  /// Alejadas pedidas clampadas a `1..(fisicas-1)`; 0 si no aplica.
  static int cantidadAlejadasEfectivas(int fisicas, int pedidas) {
    if (fisicas < 2 || pedidas < 1) return 0;
    final max = fisicas - 1;
    return pedidas > max ? max : pedidas;
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
      return activas.map((m) {
        if (m.liquidada) {
          final label = numerar ? 'Mesa ${m.n}' : 'Mesa extra';
          return '$label · liquidada';
        }
        final label = numerar ? 'Mesa ${m.n}' : 'Mesa extra';
        return '$label · ${m.cuotasPagadas}/$cuotas · ${m.deuda.toCurrency()}';
      }).toList();
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
