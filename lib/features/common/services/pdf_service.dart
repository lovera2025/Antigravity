import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/presupuesto.dart';
import '../../../models/prestamo_alquiler.dart';
import '../../../models/calculo_rentabilidad.dart';
import '../../../models/egreso.dart';
import '../../caja_sesiones/models/sesion_caja.dart';
import '../utils/texto_busqueda.dart';
import '../../cierre_caja/models/medio_pago_caja.dart';
import '../../cierre_caja/models/resumen_sesion_pdf.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../cierre_caja/services/cobro_agrupado.dart';
import '../../cierre_caja/services/datos_cierre_sesion.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../rentabilidad/services/calculador_rentabilidad_service.dart';
import '../../eventos/services/cobro_abono_acumulado.dart';
import '../../eventos/services/cobro_masivo_conceptos_pdf.dart';
import '../../eventos/services/concepto_pago_display.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/services/mora_concepto_rotulo.dart';
// `MoraPendientePreviaDetalle` llega reexportado por mora_concepto_rotulo.
import '../../eventos/services/mora_cuota_calculator.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../../eventos/utils/presupuesto_desde_evento.dart';
import '../utils/currency_extensions.dart';
import 'ajuste_pdf.dart';
import 'presupuesto_pdf_sections.dart';
import 'presupuesto_redaccion_llm_service.dart';

/// Un escalón del ajuste del detalle de la hoja de cierre.
class _PasoDetalleMedios {
  final int columnas;
  final AjustePdf ajuste;

  /// Piso de tamaño de letra para este escalón. Nunca baja de 6 pt.
  final double piso;

  const _PasoDetalleMedios(this.columnas, this.ajuste, this.piso);
}

// Paleta de colores del PDF (Rediseño Élite a pedido del Señor)
const _gold = PdfColor.fromInt(0xFFD4AF37);
const _headerBg = PdfColor.fromInt(0xFFF2F2F2); // Gris Perla Elegante
const _cardBg = PdfColor.fromInt(0xFFF9F9F9);
const _darkText = PdfColor.fromInt(0xFF2C3E50);
const _redAccent = PdfColor.fromInt(0xFFE74C3C);
const _greenAccent = PdfColor.fromInt(0xFF27AE60);
const _greyText = PdfColor.fromInt(0xFF7F8C8D);
const _greyLight = PdfColor.fromInt(0xFFE0E0E0);

const _kPdfPresupuestoIntroSegundoParrafoLegacy =
    'Es un gusto saludarte. Aquí te presentamos la propuesta integral diseñada para transformar tu visión en un recuerdo imborrable, respaldada por un equipo apasionado y tecnología de vanguardia al servicio de tu celebración.';

enum _PdfMenuAccion { ver, guardarComo, abrirCarpeta }

/// Fila para export PDF del listado Cobro por período (Mi Empresa).
class CobroPeriodoPdfFila {
  final String nombre;
  final String curso;
  final String contratoEstado;
  final String cuotasPagadas;
  final String ultimoPago;
  final String telefono;

  const CobroPeriodoPdfFila({
    required this.nombre,
    required this.curso,
    required this.contratoEstado,
    required this.cuotasPagadas,
    required this.ultimoPago,
    required this.telefono,
  });
}

/// Una fila de la planilla de mora. Los dos tipos de mora van separados: la de
/// cuotas vencidas impagas y la que quedó sin cobrar al pagar una cuota.
class MoraPdfFila {
  final String nombre;
  final String curso;
  final String telefono;

  /// `4/9`.
  final String cuotas;

  final double moraVencida;

  /// `C1 (Abr) 113d $30.400 · C2 (May) 45d $18.000`. Vacío si no hay.
  final String detalleVencida;

  final double moraNoCobrada;
  final String detalleNoCobrada;

  /// Lo que resta del plan. Va aparte de la mora y nunca sumado con ella.
  final double saldoPlan;

  const MoraPdfFila({
    required this.nombre,
    required this.curso,
    required this.telefono,
    required this.cuotas,
    required this.moraVencida,
    required this.moraNoCobrada,
    required this.saldoPlan,
    this.detalleVencida = '',
    this.detalleNoCobrada = '',
  });

  double get moraTotal =>
      double.parse((moraVencida + moraNoCobrada).toStringAsFixed(2));
}

class PdfService {
  /// Tablas más pequeñas evitan que un solo [pw.Table] dispare [TooManyPagesException] en [pw.MultiPage].
  static const int _kCierreCajaFilasPorBloque = 28;

  /// Mismo motivo, para los listados largos (planilla de mora).
  static const int _kFilasPorBloqueListado = 28;

  /// Caja objetivo de los papeles que se entregan por cobro: media hoja A4,
  /// para poder cortar dos por página.
  static double get _mediaA4 => PdfPageFormat.a4.height / 2;

  // ── Ajuste medido: "que entre" en vez de "que crezca" ─────────────────────

  /// Cuánto ocupa realmente [contenido], en puntos.
  ///
  /// Se arma una página con alto libre: el motor la recorta al alto exacto del
  /// contenido, así que la altura resultante **es** la medida. Es un cálculo en
  /// memoria (sin archivos ni impresión), del orden de milisegundos.
  static Future<double> _medirAlto({
    required pw.ThemeData? theme,
    required pw.Widget contenido,
  }) async {
    final doc = pw.Document(theme: theme);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(PdfPageFormat.a4.width, double.infinity),
        margin: const pw.EdgeInsets.all(0),
        build: (_) => contenido,
      ),
    );
    await doc.save();
    return doc.document.pdfPageList.pages.first.pageFormat.height;
  }

  /// **Ningún PDF de esta app usa `pw.Page` con alto fijo.**
  ///
  /// Es la única forma de perder datos en silencio: lo que no entra se recorta y
  /// no queda rastro. Las dos formas permitidas son:
  ///
  /// - `pw.MultiPage` — se desparrama en hojas, nunca recorta. Para listados.
  /// - `PdfPageFormat(width, double.infinity)` + `ConstrainedBox(minHeight: …)` +
  ///   [_ajustarParaEntrar] — entra en la medida buscada, y si no entra la hoja
  ///   crece. Para recibos y papeles de una hoja.
  ///
  /// Primer nivel de la escalera con el que el papel entra en [objetivo].
  ///
  /// Prueba de menos a más invasivo y **corta apenas entra**: si con juntar el
  /// aire alcanza, no abrevia; si con abreviar alcanza, no achica la letra. Un
  /// cobro común no pasa del nivel 0 y sale idéntico al de siempre.
  ///
  /// [construir] tiene que devolver un widget **nuevo** en cada llamada: los
  /// widgets del paquete guardan estado de layout y no se pueden reutilizar.
  /// Devuelve también el alto medido: es el único número que dice si el papel
  /// entró de verdad o si la hoja va a crecer, y sin él no hay forma de
  /// probarlo en un test (ver `test/recibo_alto_test.dart`).
  static Future<({AjustePdf ajuste, double alto})> _ajustarParaEntrar({
    required double objetivo,
    required pw.ThemeData? theme,
    required pw.Widget Function(AjustePdf) construir,
  }) async {
    var ultimoAlto = double.infinity;
    for (final a in AjustePdf.escalera) {
      try {
        final alto = await _medirAlto(theme: theme, contenido: construir(a));
        ultimoAlto = alto;
        if (alto <= objetivo + 0.5) return (ajuste: a, alto: alto);
      } catch (_) {
        // Si la medición falla por lo que sea, no se rompe el papel: se sigue
        // con el nivel siguiente y en el peor caso sale sin compactar.
        return (ajuste: a, alto: ultimoAlto);
      }
    }
    // Ni el nivel más compacto entra. Se usa igual: la hoja crecerá un poco,
    // que es preferible a imprimir el papel sin el total.
    return (ajuste: AjustePdf.escalera.last, alto: ultimoAlto);
  }

  /// Primer nivel con el que un documento paginado entra en [maxPaginas].
  ///
  /// Para el ticket de cierre de caja, que es `MultiPage`: ahí "que entre" no
  /// significa media hoja sino no desparramarse en páginas de más.
  ///
  /// [margin] tiene que ser **el mismo** con el que después se imprime: medir con
  /// márgenes distintos da un lugar disponible que no existe, y la escalera
  /// elegiría un nivel que en la hoja real no entra.
  static Future<AjustePdf> _ajustarParaPaginas({
    required int maxPaginas,
    required pw.ThemeData? theme,
    required List<pw.Widget> Function(AjustePdf) construir,
    pw.EdgeInsets margin = const pw.EdgeInsets.all(0),
  }) async {
    var mejor = AjustePdf.intacto;
    var mejorPaginas = 1 << 30;
    for (final a in AjustePdf.escalera) {
      try {
        final doc = pw.Document(theme: theme);
        doc.addPage(
          pw.MultiPage(
            maxPages: 10000,
            pageFormat: PdfPageFormat.a4,
            margin: margin,
            build: (_) => construir(a),
          ),
        );
        await doc.save();
        final paginas = doc.document.pdfPageList.pages.length;
        if (paginas <= maxPaginas) return a;
        // No entra, pero si mejoró respecto del nivel anterior vale la pena
        // seguir. Si dejó de mejorar, compactar más solo empeora la lectura.
        if (paginas < mejorPaginas) {
          mejor = a;
          mejorPaginas = paginas;
        }
      } catch (_) {
        return mejor;
      }
    }
    return mejor;
  }

  static String? _ultimaRutaPdfGuardado;

  static bool _fuentesPrecalentadas = false;
  static pw.Font? _outfitRegular;
  static pw.Font? _outfitBold;

  /// Las dos Outfit del papel, desde los assets de la app.
  ///
  /// `PdfGoogleFonts` resuelve por la convención del paquete `google_fonts`
  /// (`google_fonts/Outfit-Regular.ttf`), que no es donde viven acá
  /// (`assets/google_fonts/`), así que terminaba bajándolas de internet y
  /// cayendo a Helvetica cuando no había red. Helvetica no se ve distinta
  /// nomás: **mide** distinto, y todo el "que entre en media hoja" está medido
  /// con Outfit. Un recibo que sale con otra tipografía sale con otro alto.
  ///
  /// Se leen una sola vez y quedan en memoria.
  static Future<(pw.Font, pw.Font)?> _fuentesOutfit() async {
    final cacheR = _outfitRegular;
    final cacheB = _outfitBold;
    if (cacheR != null && cacheB != null) return (cacheR, cacheB);
    try {
      final regular = pw.Font.ttf(
        await rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'),
      );
      final bold = pw.Font.ttf(
        await rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'),
      );
      _outfitRegular = regular;
      _outfitBold = bold;
      return (regular, bold);
    } catch (e) {
      debugPrint('⚠️ No se pudieron leer las Outfit de assets: $e');
    }
    // Red de atrás: si el asset faltara, se intenta la descarga.
    try {
      final regular = await PdfGoogleFonts.outfitRegular();
      final bold = await PdfGoogleFonts.outfitBold();
      _outfitRegular = regular;
      _outfitBold = bold;
      return (regular, bold);
    } catch (_) {
      return null;
    }
  }

  /// Deja las fuentes de los PDF resueltas en memoria, apenas arranca la app.
  ///
  /// No lanza nunca: un problema de assets no debe impedir que arranque la app.
  static Future<void> precalentarFuentes() async {
    if (_fuentesPrecalentadas) return;
    _fuentesPrecalentadas = true;
    await _fuentesOutfit();
  }

  // ── Presupuesto de Élite con IA de Redacción ─────────────────────────────
  static Future<void> generarPresupuestoElite(
    Presupuesto p, {
    BuildContext? context,
    String tituloHeader = 'PRESUPUESTO',
    String nombreArchivoPrefix = 'Presupuesto',
  }) async {
    final secciones = buildPresupuestoPdfSecciones(p);
    final seccionesExtras = buildPresupuestoPdfSecciones(p, soloExtras: true);
    final llmTxt = await PresupuestoRedaccionLlmService.generarSiConfigurado(
      p,
      secciones,
    );
    final cuerpoOv =
        llmTxt?.cuerpoOverridesFor(secciones.length) ??
        List<String?>.filled(secciones.length, null);

    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();
    final fontItalic = await PdfGoogleFonts.outfitLight();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/2.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    // Instante y fechas en huso America/Argentina/Buenos_Aires (GMT-3).
    final now = ArTime.nowUtc();
    final fechaEmision = ArTime.formatFechaHora(now);
    final fechaVencimiento = ArTime.formatFechaCorta(p.fechaVencimiento);
    final motivoHeader = EventoPresentacion.encabezadoDesdePresupuesto(p);
    final subtituloHeader = EventoPresentacion.subtituloDesdePresupuesto(p);
    final fraseIntroPdf =
        llmTxt?.fraseIntroUsable() ??
        EventoPresentacion.fraseIntroPresupuesto(p);
    final segundoParrafoPdf =
        llmTxt?.parrafoPresentacionUsable() ??
        _kPdfPresupuestoIntroSegundoParrafoLegacy;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (context) => _buildHeaderElite(
          logoImage,
          tituloHeader,
          fechaEmision,
          motivoHeader,
          subtituloHeader,
          p.id,
        ),
        footer: (context) => _buildFooterPublicitario(p),
        build: (context) => [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 12, 36, 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  fraseIntroPdf,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _darkText,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  segundoParrafoPdf,
                  style: pw.TextStyle(
                    fontSize: 10,
                    lineSpacing: 1.25,
                    color: _darkText,
                  ),
                ),
                pw.SizedBox(height: 14),

                // Sección: Detalles del Plan (Se eliminó el título de sección por pedido del Señor)
                ...[
                  for (var i = 0; i < secciones.length; i++)
                    secciones[i].esGrupo
                        ? _buildGrupoServiciosRedactado(
                            secciones[i].grupoNombre,
                            secciones[i].lineasOrdenadas,
                            cuerpoOverride: cuerpoOv.length > i
                                ? cuerpoOv[i]
                                : null,
                          )
                        : _buildServicioRedactado(
                            secciones[i].lineasOrdenadas.single,
                            cuerpoOverride: cuerpoOv.length > i
                                ? cuerpoOv[i]
                                : null,
                          ),
                ],

                // Anclaje IA Extra
                if (p.detalleAnclaje != null &&
                    p.detalleAnclaje!.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(9),
                    decoration: pw.BoxDecoration(
                      color: _cardBg,
                      border: pw.Border.all(
                        color: const PdfColor(0.831, 0.686, 0.216, 0.3),
                        width: 0.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Text(
                      'Anotaciones Especiales: ${p.detalleAnclaje}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                  ),
                ],

                pw.SizedBox(height: 18),

                // Resumen de Inversión (cierra el plan; extras van abajo)
                _buildResumenInversion(p.total, fechaVencimiento),

                // Sección EXTRAS — después del total para que quede claro
                // que son opciones adicionales, no incluidas en la inversión
                if (seccionesExtras.isNotEmpty) ...[
                  pw.SizedBox(height: 20),
                  _buildExtrasPresupuestoHeader(),
                  pw.SizedBox(height: 10),
                  for (final sec in seccionesExtras)
                    sec.esGrupo
                        ? _buildGrupoServiciosRedactado(
                            sec.grupoNombre,
                            sec.lineasOrdenadas,
                          )
                        : _buildServicioRedactado(sec.lineasOrdenadas.single),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeCliente = (p.cliente?.nombreCompleto ?? 'Cliente').replaceAll(
      ' ',
      '_',
    );
    final fileName = '${nombreArchivoPrefix}_$safeCliente.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName, context: context);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  /// Regenera el PDF tipo presupuesto élite desde un evento particular activo (preview).
  static Future<void> generarPresupuestoPreviewDesdeEvento({
    required Evento evento,
    required List<EventosServicios> servicios,
    BuildContext? context,
  }) async {
    final p = presupuestoVirtualDesdeEvento(
      evento: evento,
      servicios: servicios,
    );
    await generarPresupuestoElite(
      p,
      context: context,
      tituloHeader: 'PROPUESTA ACTUALIZADA',
      nombreArchivoPrefix: 'Propuesta',
    );
  }

  /// PDF de préstamo / alquiler de ítems — mismo encabezado élite que presupuesto, contexto ALQUILER.
  static Future<void> generarPrestamoAlquilerPdf({
    required PrestamoAlquiler prestamo,
    required List<PrestamoAlquilerLinea> lineas,
    required String clienteNombre,
    String? clienteTelefono,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();
    final fontItalic = await PdfGoogleFonts.outfitLight();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/2.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    // Emisión sellada en huso AR (incluye hora y minuto del instante).
    final now = ArTime.nowUtc();
    final fechaEmision = ArTime.formatFechaHora(now);
    final periodo =
        '${ArTime.formatFechaCorta(prestamo.fechaInicio)}'
        ' — ${ArTime.formatFechaCorta(prestamo.fechaFin)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (context) => _buildHeaderElite(
          logoImage,
          'ALQUILER',
          fechaEmision,
          clienteNombre,
          'PERÍODO: $periodo',
          prestamo.id,
        ),
        footer: (context) => _buildFooterPrestamoAlquiler(clienteTelefono),
        build: (context) => [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 12, 36, 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ACTA DE PRÉSTAMO DE EQUIPAMIENTO',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                    color: _gold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  prestamo.textoRedaccion ?? '',
                  style: pw.TextStyle(
                    fontSize: 10,
                    lineSpacing: 1.25,
                    color: _darkText,
                  ),
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  'DETALLE',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 9,
                    color: _gold,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 6),
                _tablaLineasPrestamo(lineas),
                pw.SizedBox(height: 14),
                _buildResumenPrestamo(prestamo),
                pw.SizedBox(height: 14),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: _cardBg,
                    border: pw.Border.all(
                      color: const PdfColor(0.831, 0.686, 0.216, 0.35),
                      width: 0.5,
                    ),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'CONDICIONES Y RESPONSABILIDAD',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                          color: _redAccent,
                          letterSpacing: 0.8,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        prestamo.textoDisclaimer ?? '',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          lineSpacing: 1.2,
                          color: _darkText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeName = clienteNombre
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\-]'), '');
    final stampArchivo = ArTime.formatFechaCorta(now).replaceAll('/', '-');
    final fileName = 'Alquiler_${safeName}_$stampArchivo.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  static pw.Widget _tablaLineasPrestamo(List<PrestamoAlquilerLinea> lineas) {
    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.4),
      columnWidths: {
        0: const pw.FlexColumnWidth(3.2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerBg),
          children: [
            _cellHdr('Ítem'),
            _cellHdr('Cant.'),
            _cellHdr('P. unit.'),
            _cellHdr('Subtotal'),
          ],
        ),
        ...lineas.map((l) {
          return pw.TableRow(
            children: [
              _cellBody(l.descripcion),
              _cellBody(
                l.cantidad == l.cantidad.roundToDouble()
                    ? l.cantidad.toStringAsFixed(0)
                    : l.cantidad.toStringAsFixed(2),
              ),
              _cellBody(l.precioUnitario.toCurrency()),
              _cellBody(l.lineaTotal.toCurrency()),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _cellHdr(String t) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: _darkText,
      ),
    ),
  );

  static pw.Widget _cellBody(String t) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      t,
      style: const pw.TextStyle(fontSize: 8.5, color: _darkText),
    ),
  );

  static pw.Widget _buildResumenPrestamo(PrestamoAlquiler p) {
    final rows = <pw.Widget>[
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Subtotal',
            style: pw.TextStyle(fontSize: 9, color: _greyText),
          ),
          pw.Text(
            p.subtotalNeto.toCurrency(),
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ];
    if (p.aplicaIva && p.montoIva > 0) {
      rows.add(pw.SizedBox(height: 4));
      rows.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'IVA (${p.alicuotaIva.toStringAsFixed(0)}%)',
              style: pw.TextStyle(fontSize: 9, color: _greyText),
            ),
            pw.Text(
              p.montoIva.toCurrency(),
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      );
    }
    rows.add(pw.SizedBox(height: 8));
    rows.add(
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL',
            style: pw.TextStyle(
              fontSize: 10,
              color: _gold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            p.total.toCurrency(),
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
        ],
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _headerBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      child: pw.Column(children: rows),
    );
  }

  static pw.Widget _buildFooterPrestamoAlquiler(String? telefono) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(36, 10, 36, 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _greyLight, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'JUNIOR EVENTOS - ALQUILER DE EQUIPAMIENTO',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                'Documento de préstamo — conservar para fines operativos.',
                style: pw.TextStyle(fontSize: 8, color: _greyText),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'CONSULTAS',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                'WhatsApp / Cel: ${telefono ?? '—'}',
                style: pw.TextStyle(fontSize: 8, color: _greyText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildGrupoServiciosRedactado(
    String nombreGrupo,
    List<PresupuestoServicio> servicios, {
    String? cuerpoOverride,
  }) {
    final ordenados = List<PresupuestoServicio>.from(servicios)
      ..sort((a, b) {
        final c = a.comboOrden.compareTo(b.comboOrden);
        if (c != 0) return c;
        return (a.nombre ?? '').compareTo(b.nombre ?? '');
      });
    // Calculamos el total del grupo
    final totalGrupo = ordenados.fold<double>(
      0,
      (sum, s) => sum + (s.precioFinal * s.cantidad),
    );

    String titulo = ordenados
        .map((s) => s.nombre?.toUpperCase() ?? '')
        .where((n) => n.isNotEmpty)
        .join(' • ');
    if (titulo.isEmpty) titulo = nombreGrupo.toUpperCase();

    String narrativaFinal;
    if (cuerpoOverride != null && cuerpoOverride.isNotEmpty) {
      narrativaFinal = cuerpoOverride;
    } else {
      // Combinar narrativas e intros (plantilla legacy)
      final List<String> intros = [];
      final List<String> detalles = [];

      for (var s in ordenados) {
        final si = _introPorLineaServicio(s);
        if (!intros.contains(si)) intros.add(si);
        if (s.detalleServicio != null && s.detalleServicio!.isNotEmpty) {
          detalles.add(s.detalleServicio!);
        }
      }

      narrativaFinal = intros.join(' ');
      if (detalles.isNotEmpty) {
        narrativaFinal += ' La propuesta incluye: ${detalles.join(", ")}.';
      }
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 3, height: 12, color: _gold),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    titulo,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              pw.Text(
                totalGrupo.toCurrency(),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: _darkText,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            narrativaFinal,
            style: pw.TextStyle(
              fontSize: 9,
              lineSpacing: 1.15,
              color: _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildServicioRedactado(
    PresupuestoServicio s, {
    String? cuerpoOverride,
  }) {
    String titulo = s.nombre?.toUpperCase() ?? 'SERVICIO ESPECIAL';
    final String cuerpo;
    if (cuerpoOverride != null && cuerpoOverride.isNotEmpty) {
      cuerpo = cuerpoOverride;
    } else {
      final intro = _introPorLineaServicio(s);
      final detalleBase = s.detalleServicio ?? '';
      cuerpo = '$intro${detalleBase.isNotEmpty ? ' • $detalleBase.' : ''}';
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 3, height: 12, color: _gold),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    titulo,
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              pw.Text(
                (s.precioFinal * s.cantidad).toCurrency(),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                  color: _darkText,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            cuerpo,
            style: pw.TextStyle(
              fontSize: 9,
              lineSpacing: 1.15,
              color: _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static final Map<String, String> _introsPorServicio = {
    'sonido':
        'Arquitectura sonora de alta fidelidad, diseñada para una cobertura uniforme y nitidez cristalina en cada rincón del salón.',
    'iluminación':
        'Atmósferas dinámicas mediante un despliegue lumínico inteligente que resalta la arquitectura y acompaña cada etapa del evento.',
    'ambientación':
        'Propuesta estética integral que fusiona mobiliario de diseño y elementos decorativos para proyectar una identidad de lujo y máximo confort.',
    'pantallas led':
        'Superficies digitales de ultra-definición que aseguran un impacto visual cinematográfico y una experiencia inmersiva para los invitados.',
    'DJ':
        'Curaduría musical estratégica que evoluciona con la energía de la fiesta, garantizando una pista vibrante y una celebración inolvidable.',
    'fotografía':
        'Registro visual con estética editorial, capturando la elegancia de los momentos planificados y la magia de lo espontáneo.',
    'vajillas':
        'Selección exclusiva de cristalería, mantelería y piezas de diseño que configuran una experiencia táctil y visual de primer nivel.',
    'locutor':
        'Conducción profesional con dominio del protocolo y oratoria, guiando los hitos de la celebración con presencia y carisma.',
    'espejo mágico':
        'Estación interactiva Mirror-Touch que combina tecnología social y entretenimiento para generar recuerdos tangibles de la noche.',
    'catering':
        'Experiencia gastronómica de autor, integrando ingredientes de estación y técnicas de vanguardia en presentaciones de alta cocina.',
    'decoración':
        'Curaduría de estilo y armonía visual, desde arreglos florales de autor hasta instalaciones artísticas que definen la distinción del evento.',
    'seguridad':
        'Custodia profesional con trato cercano y presencia discreta: orden en accesos, acompañamiento ante lo imprevisto y tranquilidad para vos y tus invitados durante toda la celebración.',
    'personal de seguridad':
        'Custodia cercana para accesos fluidos y presencia tranquila ante imprevistos, sin endurecer el ambiente de la celebración.',
    'estructuras':
        'Sistemas de montaje y soportes técnicos de alta resistencia, garantizando la seguridad y estética en la arquitectura del evento.',
    'efectos especiales':
        'Despliegue de tecnologías visuales y sensoriales diseñadas para elevar el impacto emocional en los momentos clave.',
  };

  /// Texto cuando el ítem coincide con categoría pero no tanto el nombre libre del catálogo.
  static const Map<String, String> _introsPorCategoria = {
    'seguridad':
        'Custodia profesional con trato cercano y presencia discreta: orden en accesos, acompañamiento ante lo imprevisto y tranquilidad para vos y tus invitados durante toda la celebración.',
    'personal de seguridad':
        'Custodia cercana para accesos fluidos y presencia tranquila ante imprevistos, sin endurecer el ambiente de la celebración.',
    'sonido':
        'Arquitectura sonora de alta fidelidad, diseñada para una cobertura uniforme y nitidez cristalina en cada rincón del salón.',
    'audio':
        'Arquitectura sonora de alta fidelidad, diseñada para una cobertura uniforme y nitidez cristalina en cada rincón del salón.',
    'iluminación':
        'Atmósferas dinámicas mediante un despliegue lumínico inteligente que resalta la arquitectura y acompaña cada etapa del evento.',
    'decoración':
        'Curaduría de estilo y armonía visual, desde arreglos florales de autor hasta instalaciones artísticas que definen la distinción del evento.',
    'catering':
        'Experiencia gastronómica de autor, integrando ingredientes de estación y técnicas de vanguardia en presentaciones de alta cocina.',
    'ambientación':
        'Propuesta estética integral que fusiona mobiliario de diseño y elementos decorativos para proyectar una identidad de lujo y máximo confort.',
    'general': '',
  };

  static const String _introFallbackHumana =
      'Este ítem se trabaja dentro del mismo criterio de la propuesta integral: coordinación con el equipo Junior, cercanía con lo que pactamos para tu fiesta y el detalle concreto en la lista siguiente.';

  /// Cuando aparece antes en la lista tiene prioridad sobre reglas más generosas (orden de declaración).
  static const List<({String contieneNombreNorm, String claveExactaEnMap})>
  _reglasNombreContieneInteligente = [
    // Seguridad (variantes de catálogo / redacciones libres)
    (
      contieneNombreNorm: 'personal de seguridad',
      claveExactaEnMap: 'personal de seguridad',
    ),
    (contieneNombreNorm: 'guardia', claveExactaEnMap: 'seguridad'),
    (contieneNombreNorm: 'seguridad', claveExactaEnMap: 'seguridad'),
    (contieneNombreNorm: 'vigilancia', claveExactaEnMap: 'seguridad'),
    (contieneNombreNorm: 'custodia', claveExactaEnMap: 'seguridad'),
    (contieneNombreNorm: 'portero', claveExactaEnMap: 'seguridad'),
    // Sonido / música (después de seguridad para no pisar nombres raros que contengan ambas palabras)
    (contieneNombreNorm: 'cabina dj', claveExactaEnMap: 'DJ'),
    (contieneNombreNorm: 'disc jockey', claveExactaEnMap: 'DJ'),
    (contieneNombreNorm: 'cabina sonora', claveExactaEnMap: 'sonido'),
    (contieneNombreNorm: 'sonido', claveExactaEnMap: 'sonido'),
    (contieneNombreNorm: 'dj', claveExactaEnMap: 'DJ'),
    // Otros rubros frecuentes con nombres “creativos”
    (contieneNombreNorm: 'barra libre', claveExactaEnMap: 'catering'),
    (contieneNombreNorm: 'coctel', claveExactaEnMap: 'catering'),
    (contieneNombreNorm: 'brindis', claveExactaEnMap: 'catering'),
    (contieneNombreNorm: 'video', claveExactaEnMap: 'fotografía'),
    (contieneNombreNorm: 'filmacion', claveExactaEnMap: 'fotografía'),
    (contieneNombreNorm: 'fotograf', claveExactaEnMap: 'fotografía'),
    (contieneNombreNorm: 'audio', claveExactaEnMap: 'sonido'),
    (
      contieneNombreNorm: 'iluminaci',
      claveExactaEnMap: 'iluminación',
    ), // también sin tilde
    (contieneNombreNorm: 'luces ', claveExactaEnMap: 'iluminación'),
    (contieneNombreNorm: 'ambientacion', claveExactaEnMap: 'ambientación'),
    (contieneNombreNorm: 'neon', claveExactaEnMap: 'decoración'),
    (contieneNombreNorm: 'flores', claveExactaEnMap: 'decoración'),
    (contieneNombreNorm: 'estructura', claveExactaEnMap: 'estructuras'),
    (contieneNombreNorm: 'humo', claveExactaEnMap: 'efectos especiales'),
    (contieneNombreNorm: 'laser', claveExactaEnMap: 'efectos especiales'),
  ];

  /// Delegado al helper compartido: la misma regla que usan los buscadores.
  /// Vivía acá adentro, privado, siendo lo único del sistema que sabía ignorar
  /// tildes.
  static String _normalizarTextoMatch(String? raw) =>
      normalizarTextoBusqueda(raw);

  static String? _introMapaExacto(String nombreNorm) {
    if (nombreNorm.isEmpty) return null;
    if (_introsPorServicio.containsKey(nombreNorm))
      return _introsPorServicio[nombreNorm];
    for (final e in _introsPorServicio.entries) {
      if (_normalizarTextoMatch(e.key) == nombreNorm) return e.value;
    }
    return null;
  }

  static String? _introPorCategoriaResuelta(String catNorm) {
    if (catNorm.isEmpty) return null;
    if (_introsPorCategoria.containsKey(catNorm)) {
      final v = _introsPorCategoria[catNorm];
      if (v != null && v.isNotEmpty) return v;
    }
    for (final e in _introsPorCategoria.entries) {
      if (_normalizarTextoMatch(e.key) == catNorm && e.value.isNotEmpty)
        return e.value;
    }
    return null;
  }

  static String _introPorLineaServicio(PresupuestoServicio s) {
    final nombreNorm = _normalizarTextoMatch(s.nombre);
    final porExacto = _introMapaExacto(nombreNorm);
    if (porExacto != null) return porExacto;

    final catNorm = _normalizarTextoMatch(s.categoria);
    final porCat = _introPorCategoriaResuelta(catNorm);
    if (porCat != null) return porCat;

    for (final r in _reglasNombreContieneInteligente) {
      if (nombreNorm.contains(r.contieneNombreNorm)) {
        final t = _introsPorServicio[r.claveExactaEnMap];
        if (t != null) return t;
      }
    }

    return _introFallbackHumana;
  }

  static pw.Widget _buildExtrasPresupuestoHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Container(width: 3, height: 14, color: _gold),
            pw.SizedBox(width: 8),
            pw.Text(
              'EXTRAS',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
                letterSpacing: 2,
                color: _darkText,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Opciones adicionales disponibles (no incluidas en la inversión total)',
          style: pw.TextStyle(
            fontSize: 8,
            color: _greyText,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 0.5, color: _greyLight),
      ],
    );
  }

  static pw.Widget _buildResumenInversion(double total, String vencimiento) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: _headerBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'INVERSIÓN TOTAL DEL PROYECTO',
                style: pw.TextStyle(
                  color: _gold,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Pagando una seña del 30% ahora, se congela el precio total.',
                style: pw.TextStyle(
                  color: _greyText,
                  fontSize: 7,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                total.toCurrency(),
                style: pw.TextStyle(
                  color: _darkText,
                  fontSize: 21,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'VÁLIDO HASTA: $vencimiento',
                style: pw.TextStyle(
                  color: _greyText,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooterPublicitario(Presupuesto p) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(36, 10, 36, 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _greyLight, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'JUNIOR EVENTOS - EXPERIENCIAS INOLVIDABLES',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                'Seguinos en Instagram: @${p.instagram ?? 'junior_eventos_ok'}',
                style: pw.TextStyle(fontSize: 8, color: _greyText),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'CONSULTAS Y CONTRATACIONES',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                'Junior Eventos',
                style: pw.TextStyle(fontSize: 8, color: _greyText),
              ),
              pw.Text(
                'WhatsApp / Cel: ${p.telefono ?? '351...'}',
                style: pw.TextStyle(fontSize: 8, color: _greyText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Sobrecarga de buildHeader para presupuestos
  static pw.Widget _buildHeaderElite(
    pw.ImageProvider? logo,
    String titulo,
    String fechaEmision,
    String cliente,
    String tipoEvento,
    String id,
  ) {
    return pw.Container(
      color: _headerBg,
      padding: const pw.EdgeInsets.fromLTRB(40, 25, 40, 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              if (logo != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(1.5),
                  decoration: const pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    gradient: pw.LinearGradient(
                      colors: [_gold, PdfColor.fromInt(0xFFFFFFFF)],
                    ),
                  ),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColors.white,
                    ),
                    child: pw.ClipOval(
                      child: pw.Image(
                        logo,
                        width: 40,
                        height: 40,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'JUNIOR EVENTOS',
                    style: pw.TextStyle(
                      color: _darkText,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  pw.Text(
                    'SERVICIO INTEGRAL',
                    style: pw.TextStyle(
                      color: _gold,
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: const pw.BoxDecoration(
                  color: _gold,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'EMISIÓN: $fechaEmision',
                style: pw.TextStyle(color: _greyText, fontSize: 8),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                cliente,
                style: pw.TextStyle(
                  color: _darkText,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (tipoEvento.trim().isNotEmpty)
                pw.Text(
                  tipoEvento,
                  style: pw.TextStyle(color: _greyText, fontSize: 8),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Recibo completo (imprimir) ─────────────────────────────────────────────
  static Future<void> generarReciboCompacto({
    required Evento evento,
    double? montoEntregado,
    required double saldoActual,
    List<Transaccion>? transacciones,
    List<EventosServicios>? servicios,
    String? transaccionDestacadaId,
  }) async {
    final pdf = await _buildDocument(
      evento: evento,
      saldoActual: saldoActual,
      transacciones: transacciones ?? [],
      servicios: servicios ?? [],
      titulo: 'RECIBO DE CUENTA',
      transaccionDestacadaId: transaccionDestacadaId,
    );

    final bytes = await pdf.save();

    // En Windows desktop layoutPdf puede no mostrar nada si no hay impresora.
    // Guardamos el archivo y lo abrimos directamente con el visor del sistema.
    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(
        bytes,
        'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf',
      );
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf',
      );
    }
  }

  // ── Recibo completo (compartir) ────────────────────────────────────────────
  static Future<void> compartirRecibo({
    required Evento evento,
    double? montoEntregado,
    required double saldoActual,
    List<Transaccion>? transacciones,
    List<EventosServicios>? servicios,
    String? transaccionDestacadaId,
  }) async {
    final pdf = await _buildDocument(
      evento: evento,
      saldoActual: saldoActual,
      transacciones: transacciones ?? [],
      servicios: servicios ?? [],
      titulo: 'COMPROBANTE DIGITAL',
      transaccionDestacadaId: transaccionDestacadaId,
    );

    final bytes = await pdf.save();

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(
        bytes,
        'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf',
      );
    } else {
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf',
      );
    }
  }

  /// PDF para enviar al cliente (WhatsApp u otro canal) informando anulación de un cobro mal registrado.
  static Future<void> compartirComprobanteAnulacionCobro({
    required String nombrePagador,
    required String referenciaEvento,
    required String fuenteLabel,
    required double monto,
    required String? concepto,
    required DateTime? fechaCobroOriginalUtc,
    required String motivoAnulacion,
    required DateTime fechaAnulacionUtc,
    required String idRegistro,
  }) async {
    pw.Font? fontRegular;
    pw.Font? fontBold;
    try {
      fontRegular = await PdfGoogleFonts.outfitRegular();
      fontBold = await PdfGoogleFonts.outfitBold();
    } catch (_) {}

    final pdf = pw.Document(
      theme: fontRegular != null && fontBold != null
          ? pw.ThemeData.withFont(base: fontRegular, bold: fontBold)
          : null,
    );

    final fechaCobroTxt = fechaCobroOriginalUtc != null
        ? ArTime.formatFechaHora(fechaCobroOriginalUtc.toUtc())
        : '—';
    final fechaAnulTxt = ArTime.formatFechaHora(fechaAnulacionUtc.toUtc());
    final safeNombre = nombrePagador.trim().isEmpty
        ? 'Cliente'
        : nombrePagador.trim();
    final safeRef = referenciaEvento.trim().isEmpty
        ? '—'
        : referenciaEvento.trim();
    final shortId = idRegistro.length >= 8
        ? idRegistro.substring(0, 8)
        : idRegistro;

    // Alto libre con piso de A4, el mismo patrón que los recibos: si un motivo
    // es largo la hoja **crece** en vez de comerse el texto. Con A4 de alto fijo
    // el motivo había que truncarlo a 400 caracteres para que el pie no se cayera
    // fuera de la hoja, y eso es perder parte de la explicación que se le manda
    // al cliente.
    pw.Widget cuerpoAnulacion() => pw.ConstrainedBox(
      constraints: pw.BoxConstraints(minHeight: PdfPageFormat.a4.height),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(48),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'COMPROBANTE DE ANULACIÓN DE COBRO',
              style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Junior Eventos · Comunicación al cliente',
              style: const pw.TextStyle(fontSize: 10, color: _greyText),
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              'Pagador / alumno: $safeNombre',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '$fuenteLabel · $safeRef',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Divider(thickness: 0.7, color: _greyLight),
            pw.Text(
              'Monto del cobro original: ${monto.toCurrency()}',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Concepto registrado: ${concepto?.trim().isNotEmpty == true ? concepto!.trim() : '—'}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Fecha del cobro original: $fechaCobroTxt',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFFFF5F5),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _redAccent, width: 0.6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Motivo de la anulación',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _redAccent,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    // Único campo de largo libre del documento. Va **completo**:
                    // la hoja crece si hace falta. Antes se truncaba a 400
                    // caracteres porque el alto fijo no dejaba crecer.
                    motivoAnulacion.trim(),
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Registrado como anulado el $fechaAnulTxt',
              style: const pw.TextStyle(fontSize: 10, color: _greyText),
            ),
            pw.Text(
              'ID interno: $idRegistro',
              style: const pw.TextStyle(fontSize: 9, color: _greyText),
            ),
            // Antes era un pw.Spacer que empujaba el pie al fondo de la hoja.
            // Con alto libre no hay fondo fijo contra el que empujar, y un
            // Spacer sin límite superior rompe el layout.
            pw.SizedBox(height: 28),
            pw.Text(
              'Este documento informa que el cobro indicado fue anulado en el sistema por error operativo. '
              'El saldo fue recalculado y ya no incluye dicho importe.',
              style: const pw.TextStyle(
                fontSize: 9,
                color: _greyText,
                lineSpacing: 1.35,
              ),
            ),
          ],
        ),
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(PdfPageFormat.a4.width, double.infinity),
        margin: const pw.EdgeInsets.all(0),
        build: (_) => cuerpoAnulacion(),
      ),
    );

    final bytes = await pdf.save();
    final fname = 'Anulacion_cobro_$shortId.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: fname);
    }
  }

  // ── Recibo Unibloque Alumno (Ahorro de Papel) ─────────────────────────────
  static List<pw.Widget> _bloqueDescuentoLiquidacionPdf({
    required double porcentajeDescuento,
    required List<Map<String, dynamic>>? conceptos,
    double fontSize = 8,
  }) {
    if (porcentajeDescuento <= 0.01 || conceptos == null || conceptos.isEmpty) {
      return [];
    }
    final t = totalesDescuentoPlanPdf(conceptos);
    if (t.ahorro <= 0.01) return [];

    return [
      pw.SizedBox(height: 4),
      pw.Text(
        'DESCUENTO LIQUIDACIÓN: ${porcentajeDescuento.toStringAsFixed(0)}% '
        '(solo cuota base / mesa / sillas)',
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Subtotal nominal (deuda aplicada)',
            style: pw.TextStyle(fontSize: fontSize - 0.5, color: _greyText),
          ),
          pw.Text(
            t.nominal.toCurrency(),
            style: pw.TextStyle(fontSize: fontSize - 0.5, color: _greyText),
          ),
        ],
      ),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Descuento (${porcentajeDescuento.toStringAsFixed(0)}%)',
            style: pw.TextStyle(fontSize: fontSize - 0.5, color: _greyText),
          ),
          pw.Text(
            '− ${t.ahorro.toCurrency()}',
            style: pw.TextStyle(fontSize: fontSize - 0.5, color: _greyText),
          ),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Mora e intereses no incluyen descuento. El descuento reduce lo cobrado; '
        'la deuda del plan se reduce por el valor nominal de cada concepto.',
        style: pw.TextStyle(
          fontSize: fontSize - 1,
          fontStyle: pw.FontStyle.italic,
          color: _greyText,
        ),
      ),
      pw.SizedBox(height: 4),
    ];
  }

  /// Devuelve el nivel de compactación y el alto medido del papel: es lo que
  /// permite probar en un test que el recibo entra en media hoja **y** que
  /// entró sin tener que sacrificar el detalle de la mora. Los llamadores de la
  /// app lo ignoran.
  static Future<({AjustePdf ajuste, double alto})> generarReciboAlumno({
    required ContratoAlumno alumno,
    required Evento evento,
    required double montoPagado,
    required double saldoPendiente,
    String? conceptoCuotas,
    List<Map<String, dynamic>>? conceptosPagados,
    DateTime? fechaManual,
    String? medioPago,

    /// Si ambos > 0, el recibo detalla pago mixto (no suman al valor del recibo).
    double? montoEfectivoDetalle,
    double? montoTransferenciaDetalle,

    /// Solo leyenda informativa: cargo estimado que no está en el valor liquidado.
    bool informarCargoTransferenciaExterno = false,
    double? porcentajeCargoTransferenciaExterno,

    /// Si se informa, el PDF usa este monto fijo (pesos) en lugar de calcular desde [%].
    double? montoCargoTransferenciaInformado,

    /// Descuento de liquidación del plan (base/mesa/sillas). 0 = sin bloque.
    double porcentajeDescuentoLiquidacion = 0,

    /// Mora que sigue debiendo DESPUÉS de este cobro. Se imprime siempre que
    /// venga informada (incluso en 0) para que quede constancia. `null` solo en
    /// reimpresiones históricas, que no pueden afirmar la mora de hoy.
    double? moraPendienteRestante,

    /// Línea compacta de "de dónde viene" esa mora, para el aviso rojo.
    ///
    /// Es el **camino de atrás**: se imprime como prosa solo cuando no vienen
    /// [moraPendienteDesglose] ni [moraPendienteArrastre], que dan lo mismo en
    /// renglones y con los importes alineados. Vacía si no se pudo determinar
    /// (reimpresiones históricas).
    String? moraPendienteOrigen,

    /// Cuotas vencidas todavía impagas que componen [moraPendienteRestante].
    /// Con esto el aviso rojo lista una cuota por renglón en vez de aplastar
    /// todo en una línea corrida.
    List<MoraCuotaDetalle> moraPendienteDesglose = const [],

    /// Mora que quedó sin cobrar cuando la cuota se liquidó, atribuida a la
    /// cuota que la generó. Es la otra mitad de [moraPendienteRestante].
    List<MoraPendientePreviaDetalle> moraPendienteArrastre = const [],

    /// Cuándo se midió [moraPendienteRestante], cuando **no** es el día del
    /// recibo. En una reimpresión el número es el de hoy, no el de aquel día:
    /// se imprime fechado en vez de omitirse. Omitir era peor — el papel
    /// mostraba lo que entró y nada de lo que seguía debiéndose.
    DateTime? moraRestanteMedidaEl,

    /// `null` lo infiere desde [fechaManual]. El cobro original también manda
    /// fecha (la del momento del cobro), así que sin este flag todo recibo
    /// original salía rotulado como reimpresión.
    bool? esReimpresion,
  }) async {
    // Fuente TrueType con soporte Unicode completo (elimina warnings de
    // Helvetica). El tema se guarda aparte: la medición tiene que usar
    // exactamente las mismas fuentes, o el alto medido no sería el alto real.
    final fuentes = await _fuentesOutfit();
    final temaRecibo = fuentes != null
        ? pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2)
        : null;
    final pdf = pw.Document(theme: temaRecibo);

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/isotipo-ej.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error al cargar logo: $e');
    }

    // Anclaje temporal ESTRICTO en huso America/Argentina/Buenos_Aires (GMT-3).
    // Cada recibo lleva el instante exacto (día + hora + minuto) de la
    // operación para garantizar la validez legal y administrativa.
    final now = ArTime.nowUtc();
    final fechaTransaccion = fechaManual ?? now;
    final fechaStr = ArTime.formatFechaHora(fechaTransaccion);
    final fechaEmision = ArTime.formatFechaHora(now);

    // Calcular VALOR dinámicamente...
    final bool esReimpresionPdf = esReimpresion ?? (fechaManual != null);
    final valPago = (conceptosPagados != null && conceptosPagados.isNotEmpty)
        ? conceptosPagados.fold<double>(
            0,
            (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0),
          )
        : montoPagado;
    final valSaldo = saldoPendiente;

    // Contador del bloque "cómo queda la cuenta". En un cobro del día sale del
    // contrato, que es exacto. En una reimpresión no puede salir de ahí: el
    // contrato ya avanzó y el papel terminaba diciendo las cuotas de hoy al
    // lado del abonado de aquel día (reimprimir la cuota 1 mostraba "5/9
    // pagadas" junto a $30.000). Se deriva del mismo saldo histórico que se
    // imprime al lado, así el recuadro cierra consigo mismo.
    final int cuotasPagadasRecibo = () {
      if (!esReimpresionPdf || alumno.totalCuotas <= 0) {
        return alumno.cuotasPagadas;
      }
      final cuotaPura = alumno.montoTotalPactado / alumno.totalCuotas;
      if (cuotaPura <= 0.01) return alumno.cuotasPagadas;
      final abonado = (alumno.montoTotalPactado - valSaldo).clamp(
        0.0,
        double.infinity,
      );
      return cuotasCompletasDesdeGrossAcumulado(
        abonado,
        cuotaPura,
      ).clamp(0, alumno.totalCuotas);
    }();

    final mesasEstadoRecibo = MesasExtraUtils.estadoDesdeContrato(alumno);
    final cantMesasRecibo = MesasExtraUtils.cantidadMesasContrato(
      alumno,
      mesasEstadoRecibo,
    );
    final conceptosPagadosDisplay = conceptosPagados != null
        ? lineasDisplayParaPdf(
            // El recibo no compactaba cuotas base, cosa que el resumen sí hace
            // desde siempre: un cobro de 9 cuotas estiraba el papel mucho más
            // de lo necesario.
            compactarCuotasBaseParaPdf(
              agruparConceptosMesasParaPdf(
                // Antes de agrupar y compactar, no después: los dos deciden por
                // `esMora`, así que una línea de mora sin bandera se agrupaba
                // como si fuera del plan.
                normalizarBanderasLineasPdf(
                  conceptosPagados
                      .map((c) => Map<String, dynamic>.from(c))
                      .toList(),
                ),
                cantMesasRecibo,
              ),
            ),
            regAr: alumno.createdAt != null
                ? ArTime.toAr(alumno.createdAt!)
                : null,
            hoyAr: ArTime.toAr(fechaTransaccion),
          )
        : null;

    // Nivel de compactación del recibo. Lo decide la medición de más abajo; el
    // closure del contenido lee esta variable.
    var dRecibo = AjustePdf.intacto;

    // `Concepto:` queda con lo que se pagó del plan. **Toda** la mora —la de la
    // cuota que se está pagando y la que quedó de cuotas ya liquidadas— se
    // itemiza dentro del recuadro verde, que es el único lugar del papel donde
    // se explica de dónde sale ese número. Antes vivía en tres lados: colgada
    // de cada cuota, en un bloque suelto con su propio título, y sumada en el
    // recuadro; el mismo importe salía tres veces.
    final conceptosCobroDisplay = conceptosPagadosDisplay
        ?.where((c) => c['esMora'] != true)
        .toList();

    /// De qué cuotas salen los pesos de mora que entraron en este cobro.
    final filasMoraCobrada = conceptosPagadosDisplay != null
        ? filasMoraCobradaPdf(conceptosPagadosDisplay)
        : const <FilaMoraPdf>[];

    /// De qué cuotas sale la mora que queda debiendo. Dos orígenes: cuotas
    /// vencidas todavía impagas, y mora que no se cobró cuando la cuota se
    /// liquidó. Se ordena por número de cuota para que el papel se lea de la
    /// más vieja a la más nueva, sin importar de cuál de los dos venga.
    final filasMoraPendiente =
        <({int cuota, FilaMoraPdf fila})>[
          for (final d in moraPendienteDesglose)
            if (d.interesBruto > 0.01)
              (
                cuota: d.numeroCuota,
                fila: FilaMoraPdf(
                  rotulo: MoraConceptoRotulo.rotuloCuotaMora(
                    numeroCuota: d.numeroCuota,
                    mesLabel: d.mesLabel,
                    diasMora: d.diasMora,
                  ),
                  monto: d.interesBruto,
                ),
              ),
          for (final d in moraPendienteArrastre)
            if (d.montoAtribuido > 0.01)
              (
                cuota: d.numeroCuota,
                fila: FilaMoraPdf(
                  rotulo: MoraConceptoRotulo.rotuloCuotaMora(
                    numeroCuota: d.numeroCuota,
                    mesLabel: d.mesLabel,
                    diasMora: d.diasMora,
                  ),
                  monto: d.montoAtribuido,
                ),
              ),
        ]..sort((a, b) => a.cuota.compareTo(b.cuota));

    /// Las filas del aviso rojo tienen que sumar el número del título, igual
    /// que las del verde. Lo que la atribución no llegó a explicar va en un
    /// renglón bolsa: el papel puede no saber de qué cuota sale un peso, pero
    /// no puede dejar de nombrarlo.
    final filasPendienteRecibo = () {
      final filas = [for (final f in filasMoraPendiente) f.fila];
      final restante = moraPendienteRestante;
      if (filas.isEmpty || restante == null || restante <= 0.01) {
        return const <FilaMoraPdf>[];
      }
      final sum = filas.fold<double>(0, (s, f) => s + f.monto);
      final falta = double.parse((restante - sum).toStringAsFixed(2));
      // Se pasa del total: la atribución no coincide con el número que se
      // imprime. Un desglose que contradice su propio título es peor que no
      // tenerlo, así que se cae a la línea en prosa.
      if (falta < -0.01) return const <FilaMoraPdf>[];
      if (falta <= 0.01) return filas;
      return [
        ...filas,
        FilaMoraPdf(rotulo: rotuloMoraOtrasCuotasPdf, monto: falta),
      ];
    }();

    // Desglose del recibo por rubro. Se toman los netos (no el gross) para que
    // las partes sumen exactamente el total impreso aunque haya descuento.
    final double moraCobradaRecibo = conceptosPagadosDisplay != null
        ? moraSeleccionadaPdf(conceptosPagadosDisplay)
        : 0.0;
    final double cargoCobradoRecibo = conceptosPagadosDisplay != null
        ? cargoDesdeConceptosFinales(conceptosPagadosDisplay)
        : 0.0;
    final double planCobradoRecibo =
        valPago - moraCobradaRecibo - cargoCobradoRecibo;
    final partesDesgloseRecibo = <String>[
      if (planCobradoRecibo > 0.01)
        'Cuotas del plan ${planCobradoRecibo.toCurrency()}',
      if (moraCobradaRecibo > 0.01) 'Mora ${moraCobradaRecibo.toCurrency()}',
      if (cargoCobradoRecibo > 0.01)
        'Costo por transferencia ${cargoCobradoRecibo.toCurrency()}',
    ];

    // Estado de la mora en este cobro. El recuadro verde dice qué tipo de
    // operación fue —entera o parcial— y no de qué cuota salió cada peso: eso
    // es el detalle de las líneas de arriba, y enumerarlo dos veces era lo que
    // hacía ilegible el bloque.
    final bool moraQuedaSaldada =
        moraCobradaRecibo > 0.01 &&
        moraPendienteRestante != null &&
        moraPendienteRestante <= 0.01;

    /// Después de este cobro sigue habiendo mora. En una reimpresión es la de
    /// hoy, pero alcanza para afirmar que aquel pago no la saldó.
    final bool moraSigueDebiendo =
        moraPendienteRestante != null && moraPendienteRestante > 0.01;

    /// Mora que había antes de este cobro: lo que entró más lo que quedó.
    ///
    /// Solo vale cuando lo que quedó se midió **en este cobro**. En una
    /// reimpresión el restante es el de hoy, y sumarlo daría un total que nunca
    /// existió (acá coincidían, pero la mora sigue corriendo). Ahí el verde no
    /// puede dar el número: dice que fue parcial y el rojo, fechado, da el resto.
    final double? moraTotalPreCobro =
        moraRestanteMedidaEl == null &&
            moraPendienteRestante != null &&
            moraPendienteRestante > 0.01
        ? moraCobradaRecibo + moraPendienteRestante
        : null;

    /// Alguna cuota quedó cubierta a medias. Es un hecho del movimiento, así que
    /// tiene que sobrevivir a la reimpresión: por eso mira también el sufijo
    /// `(parcial)` del concepto guardado, que es lo único que queda escrito
    /// cuando el papel se rearma desde los pagos de la base.
    final bool moraCobroFueParcial =
        conceptosPagadosDisplay?.any((c) {
          if (c['esMora'] != true) return false;
          final pleno = (c['montoPleno'] as num?)?.toDouble() ?? 0;
          final monto = (c['monto'] as num?)?.toDouble() ?? 0;
          if (pleno > monto + 0.01) return true;
          return (c['concepto'] as String? ?? '').contains(
            MoraConceptoRotulo.sufijoParcial,
          );
        }) ??
        false;

    final double? efDet = montoEfectivoDetalle;
    final double? trDet = montoTransferenciaDetalle;
    final bool reciboMixto =
        efDet != null && trDet != null && efDet > 0.01 && trDet > 0.01;
    final double pctCargo = porcentajeCargoTransferenciaExterno ?? 0;
    double baseCargoMonto = valPago;
    if (reciboMixto) {
      baseCargoMonto = trDet;
    }
    final bool escenarioTransferencia =
        reciboMixto ||
        (medioPago?.trim().toLowerCase().contains('transfer') ?? false);
    final double? cargoInformado = montoCargoTransferenciaInformado;
    final bool usarMontoFijo = cargoInformado != null && cargoInformado > 0.01;
    final bool usarPct = pctCargo > 0.01;
    final bool mostrarCargoRef =
        informarCargoTransferenciaExterno &&
        escenarioTransferencia &&
        (usarMontoFijo || usarPct);

    late final double montoCargoEstimado;
    if (mostrarCargoRef) {
      final ci = cargoInformado;
      if (ci != null && ci > 0.01) {
        montoCargoEstimado = double.parse(ci.toStringAsFixed(2));
      } else {
        montoCargoEstimado = double.parse(
          (baseCargoMonto * (pctCargo / 100.0)).toStringAsFixed(2),
        );
      }
    } else {
      montoCargoEstimado = 0;
    }

    final String textoCargoReferenciaPdf = () {
      if (!mostrarCargoRef) return '';
      if (usarMontoFijo) {
        if (baseCargoMonto > 0.01) {
          final eqPct = 100.0 * montoCargoEstimado / baseCargoMonto;
          if (eqPct > 0.01 && eqPct <= 999.0) {
            return 'Referencia informativa (costo sobre transferencia): fuera de este valor liquidado ${montoCargoEstimado.toCurrency()} (~${eqPct.toStringAsFixed(1)}% de ${baseCargoMonto.toCurrency()}).';
          }
        }
        return 'Referencia informativa (costo sobre transferencia): fuera de este valor liquidado ${montoCargoEstimado.toCurrency()}.';
      }
      return 'Referencia informativa (${pctCargo.toStringAsFixed(1)}% sobre transferencia): costo estimado fuera de este valor liquidado ${montoCargoEstimado.toCurrency()}';
    }();

    String? lineaMixMedios;
    if (reciboMixto) {
      lineaMixMedios =
          'Medios: Efectivo ${efDet.toCurrency()} · Transferencia ${trDet.toCurrency()}';
    }

    // Un ítem del detalle de `Concepto:`.
    //
    // Ya no hay caso `anidada` (la mora colgada de su cuota con `↳`): toda la
    // mora se itemiza adentro del recuadro verde, así que acá solo llegan
    // líneas del plan.
    pw.Widget lineaConceptoRecibo(Map<String, dynamic> c) {
      // 'display' = rótulo de mostrador; 'concepto' queda intacto.
      final desc =
          (c['display'] as String?) ?? (c['concepto'] as String? ?? 'Pago');
      final montoItem = (c['monto'] as num?)?.toDouble() ?? 0;
      final grossItem = (c['gross'] as num?)?.toDouble();
      final subtexto = c['subtexto'] as String?;
      final bool plan = c['esPlanLiquidacion'] == true;
      final String? nominalHint =
          plan && grossItem != null && grossItem > montoItem + 0.01
          ? 'nom. ${grossItem.toCurrency()}'
          : null;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  '  • ${dRecibo.abreviar ? abreviarDisplayPdf(desc) : desc}',
                  style: pw.TextStyle(fontSize: dRecibo.fs(10)),
                ),
              ),
              pw.Text(
                montoItem.toCurrency(),
                style: pw.TextStyle(
                  fontSize: dRecibo.fs(10),
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          if (dRecibo.subtextos && subtexto != null && subtexto.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: pw.Text(
                subtexto,
                style: pw.TextStyle(
                  fontSize: dRecibo.fs(8, piso: 6.5),
                  fontStyle: pw.FontStyle.italic,
                  color: _greyText,
                ),
              ),
            ),
          if (dRecibo.subtextos && nominalHint != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: pw.Text(
                nominalHint,
                style: pw.TextStyle(
                  fontSize: dRecibo.fs(8, piso: 6.5),
                  fontStyle: pw.FontStyle.italic,
                  color: _greyText,
                ),
              ),
            ),
        ],
      );
    }

    // Recuadro de aviso (mora saldada en verde, mora pendiente en rojo).
    /// Recuadro de aviso (verde: lo que entró; rojo: lo que falta).
    ///
    /// Escala con [dRecibo] como el resto del papel. Antes tenía medidas fijas y
    /// era lo único que la escalera no podía tocar: un recibo con aviso rojo se
    /// pasaba de media hoja y ningún nivel de compactación lo bajaba.
    ///
    /// El **título** nunca se toca: lleva el monto, y en una reimpresión también
    /// la fecha a la que está medido.
    ///
    /// Las [filas] son de qué cuotas sale ese monto, y **siempre lo suman**. Se
    /// abrevian por escalones (`maxFilasMora`, con un renglón `y N cuotas más`
    /// que carga lo recortado) pero no se dan de baja: un papel que reclama
    /// plata sin decir de qué cuotas sale es lo que motivó todo esto.
    ///
    /// Las [lineas] son la explicación en prosa, y sí son lo que se apaga
    /// cuando el papel aprieta — igual que los subtextos del detalle.
    pw.Widget avisoRecibo({
      required PdfColor color,
      required String titulo,
      List<FilaMoraPdf> filas = const [],
      List<String> lineas = const [],
    }) {
      final d = dRecibo;
      final visibles = recortarFilasMoraPdf(filas, d.maxFilasMora);
      return pw.Container(
        width: double.infinity,
        margin: pw.EdgeInsets.only(top: d.sp(4)),
        padding: pw.EdgeInsets.all(d.sp(5)),
        decoration: pw.BoxDecoration(
          color: _cardBg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          border: pw.Border.all(color: color, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: d.fs(8, piso: 6.5),
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            ...visibles.map(
              (f) => pw.Padding(
                padding: pw.EdgeInsets.only(top: d.sp(1), left: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        f.rotulo,
                        style: pw.TextStyle(
                          fontSize: d.fs(8, piso: 6.5),
                          color: _darkText,
                        ),
                      ),
                    ),
                    pw.Text(
                      f.monto.toCurrency(),
                      style: pw.TextStyle(
                        fontSize: d.fs(8, piso: 6.5),
                        fontWeight: pw.FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (d.subtextos)
              ...lineas.map(
                (t) => pw.Text(
                  t,
                  style: pw.TextStyle(
                    fontSize: d.fs(7, piso: 6),
                    color: _greyText,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Objetivo: media hoja A4, para cortar dos por página. Se mide y se
    // compacta hasta que entre; el alto libre con piso de media hoja es la red
    // de seguridad para que nada se pueda recortar aunque ningún nivel alcance.
    final formatoRecibo = PdfPageFormat(
      PdfPageFormat.a4.width,
      double.infinity,
    );

    pw.Widget cuerpoRecibo() {
      final medioReciboStr = medioPago?.trim() ?? '';
      return pw.ConstrainedBox(
        constraints: pw.BoxConstraints(minHeight: _mediaA4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _greyLight, width: 0.5),
                ),
              ),
              padding: pw.EdgeInsets.fromLTRB(
                22,
                dRecibo.sp(8),
                22,
                dRecibo.sp(16),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header del Recibo
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (logoImage != null)
                            pw.Container(
                              // Con el alto fijo el logo marcaba el piso de la
                              // fila y el encabezado no bajaba de ahí por más
                              // que se achicara la letra.
                              height: dRecibo.fs(30, piso: 20),
                              margin: const pw.EdgeInsets.only(right: 12),
                              child: pw.Image(logoImage),
                            ),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Victor Adrián Argüello',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: dRecibo.fs(10),
                                  color: _darkText,
                                ),
                              ),
                              pw.Text(
                                'Dueño, Junior Eventos',
                                style: pw.TextStyle(
                                  fontSize: dRecibo.fs(8, piso: 6.5),
                                  color: _greyText,
                                ),
                              ),
                              pw.Text(
                                'CUIT 23-32837670-9',
                                style: pw.TextStyle(
                                  fontSize: dRecibo.fs(8, piso: 6.5),
                                  color: _greyText,
                                ),
                              ),
                              pw.Text(
                                'Responsable Inscripto',
                                style: pw.TextStyle(
                                  fontSize: dRecibo.fs(8, piso: 6.5),
                                  color: _greyText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'RECIBO DE PAGO',
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(13, piso: 10),
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                          pw.Text(
                            'N° ${alumno.id.substring(0, 8).toUpperCase()}',
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(8, piso: 6.5),
                              color: _greyText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: dRecibo.sp(4)),

                  // Cuerpo. El importe no va acá arriba: un recibo se lee
                  // "recibí de X la suma de Y", y el total va al pie.
                  //
                  // El sello temporal estricto (AR GMT-3) es esta línea y nada
                  // más: `ArTime.operacionGestionada` decía el mismo instante
                  // en palabras justo abajo, y lo único que agregaba era el
                  // nombre del día.
                  pw.Text(
                    'Fecha: $fechaStr',
                    style: pw.TextStyle(fontSize: dRecibo.fs(10)),
                  ),
                  pw.SizedBox(height: dRecibo.sp(3)),

                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'Recibí de: ',
                          style: pw.TextStyle(fontSize: dRecibo.fs(10)),
                        ),
                        pw.TextSpan(
                          text: alumno.nombreAlumno.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: dRecibo.fs(10),
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: dRecibo.sp(2)),

                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'La suma de pesos: ',
                          style: pw.TextStyle(fontSize: dRecibo.fs(10)),
                        ),
                        pw.TextSpan(
                          text: numeroALetras(valPago),
                          style: pw.TextStyle(
                            fontSize: dRecibo.fs(9),
                            fontStyle: pw.FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: dRecibo.sp(3)),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Concepto:',
                        style: pw.TextStyle(
                          fontSize: dRecibo.fs(10),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (alumno.numeroMesa != null &&
                          alumno.numeroMesa!.isNotEmpty)
                        pw.Text(
                          'MESA: ${alumno.numeroMesa}',
                          style: pw.TextStyle(
                            fontSize: dRecibo.fs(10),
                            fontWeight: pw.FontWeight.bold,
                            color: _greyText,
                          ),
                        ),
                    ],
                  ),
                  pw.SizedBox(height: dRecibo.sp(2)),

                  // Desglose itemizado de conceptos pagados
                  if (conceptosCobroDisplay != null &&
                      conceptosCobroDisplay.isNotEmpty)
                    ...conceptosCobroDisplay.map(lineaConceptoRecibo),
                  if (conceptosPagadosDisplay == null ||
                      conceptosPagadosDisplay.isEmpty)
                    // Fallback legacy o Estado de Cuenta inicial
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '  • ${conceptoCuotas ?? 'Cuota ${alumno.cuotasPagadas} de ${alumno.totalCuotas}'}',
                          style: pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          valPago.toCurrency(),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                  // Verde: lo que entró. Rojo: lo que falta. Un recuadro por
                  // cada cosa, cada uno con sus cuotas adentro.
                  if (moraCobradaRecibo > 0.01)
                    avisoRecibo(
                      color: _greenAccent,
                      titulo: moraQuedaSaldada
                          ? 'MORA SALDADA EN ESTE PAGO — '
                                '${moraCobradaRecibo.toCurrency()}'
                          : 'MORA COBRADA EN ESTE PAGO — '
                                '${moraCobradaRecibo.toCurrency()}',
                      filas: filasMoraCobrada,
                      lineas: [
                        if (moraQuedaSaldada)
                          'Con este pago no queda mora pendiente.'
                        else if (moraTotalPreCobro != null)
                          'Pago parcial: la mora era de '
                              '${moraTotalPreCobro.toCurrency()}.'
                        else if (moraCobroFueParcial || moraSigueDebiendo)
                          // Reimpresión: el total de aquel día no se puede
                          // reconstruir, pero que fue parcial sí se sabe —
                          // abajo está lo que todavía falta.
                          'Es un pago parcial de la mora.',
                      ],
                    ),

                  // La mora que queda debiendo tiene que quedar escrita en
                  // el papel, se haya tildado para cobrar o no.
                  if (moraPendienteRestante != null &&
                      moraPendienteRestante > 0.01)
                    avisoRecibo(
                      color: _redAccent,
                      titulo:
                          'FALTA PAGAR DE MORA'
                          '${moraRestanteMedidaEl != null ? ' AL ${ArTime.formatFechaCorta(moraRestanteMedidaEl)}' : ''}'
                          ' — ${moraPendienteRestante.toCurrency()}',
                      filas: filasPendienteRecibo,
                      lineas: [
                        // Que se cobró una parte ya lo dijo el recuadro verde,
                        // acá arriba. Qué es la mora se explica una sola vez,
                        // al pie de la tabla del plan. Que sigue sumando lo
                        // dice el "AL <fecha>" del título.
                        if (moraRestanteMedidaEl != null)
                          'Es la mora al día de hoy, no la del día de este '
                              'recibo.',
                        // Camino de atrás: sin filas que lo expliquen, el
                        // origen va en prosa. Con filas sería decir lo mismo
                        // dos veces.
                        if (filasPendienteRecibo.isEmpty &&
                            moraPendienteOrigen != null &&
                            moraPendienteOrigen.isNotEmpty)
                          moraPendienteOrigen,
                      ],
                    ),

                  ..._bloqueDescuentoLiquidacionPdf(
                    porcentajeDescuento: porcentajeDescuentoLiquidacion,
                    conceptos: conceptosPagadosDisplay,
                    fontSize: dRecibo.fs(9),
                  ),

                  // Franja de cierre: el importe se dice una sola vez, acá
                  // abajo, junto al medio de pago.
                  pw.Container(
                    width: double.infinity,
                    margin: pw.EdgeInsets.only(
                      top: dRecibo.sp(5),
                      bottom: dRecibo.sp(3),
                    ),
                    padding: pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: dRecibo.sp(6),
                    ),
                    decoration: pw.BoxDecoration(
                      color: _cardBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(4),
                      ),
                      border: pw.Border.all(color: _greyLight, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'TOTAL DE ESTE RECIBO',
                              style: pw.TextStyle(
                                fontSize: dRecibo.fs(9),
                                fontWeight: pw.FontWeight.bold,
                                color: _greyText,
                                letterSpacing: 0.6,
                              ),
                            ),
                            pw.Text(
                              valPago.toCurrency(),
                              style: pw.TextStyle(
                                fontSize: dRecibo.fs(14, piso: 11),
                                fontWeight: pw.FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                          ],
                        ),
                        if (partesDesgloseRecibo.length > 1)
                          pw.Text(
                            partesDesgloseRecibo.join(' · '),
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(8, piso: 6.5),
                              color: _greyText,
                            ),
                          ),
                        if (lineaMixMedios != null)
                          pw.Text(
                            lineaMixMedios,
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(8, piso: 6.5),
                              color: _greyText,
                            ),
                          )
                        else if (medioReciboStr.isNotEmpty)
                          pw.Text(
                            'Medio de pago: $medioReciboStr',
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(8, piso: 6.5),
                              color: _greyText,
                            ),
                          ),
                        if (mostrarCargoRef)
                          pw.Text(
                            textoCargoReferenciaPdf,
                            style: pw.TextStyle(
                              fontSize: dRecibo.fs(7, piso: 6),
                              fontStyle: pw.FontStyle.italic,
                              color: _greyText,
                            ),
                          ),
                      ],
                    ),
                  ),

                  pw.Text(
                    EventoPresentacion.institucionOEventoParaPdf(
                      evento: evento,
                      institucionAlumno: alumno.institucion,
                    ),
                    style: pw.TextStyle(
                      fontSize: dRecibo.fs(8, piso: 6.5),
                      color: _greyText,
                    ),
                  ),
                  pw.SizedBox(height: dRecibo.sp(3)),

                  // ─── RESUMEN DE CUENTA ───
                  pw.Text(
                    'CÓMO QUEDA LA CUENTA DESPUÉS DE ESTE PAGO',
                    style: pw.TextStyle(
                      fontSize: dRecibo.fs(8, piso: 6.5),
                      fontWeight: pw.FontWeight.bold,
                      color: _greyText,
                      letterSpacing: 1.0,
                    ),
                  ),
                  pw.SizedBox(height: dRecibo.sp(2)),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      color: _cardBg,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(5),
                      ),
                      border: pw.Border.all(color: _greyLight, width: 0.5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // Anchos flexibles, no fijos: con 160/70/120 la tabla
                        // medía 350 pt dentro de una tarjeta de 551 y dejaba
                        // 200 pt de gris vacío a la derecha, mientras la
                        // columna del contrato envolvía a tres renglones en
                        // 144 pt útiles. El mismo dato entra en uno usando el
                        // lugar que ya estaba ahí.
                        pw.Table(
                          columnWidths: {
                            0: const pw.FlexColumnWidth(2.9),
                            1: const pw.FlexColumnWidth(0.9),
                            2: const pw.FlexColumnWidth(2.0),
                          },
                          border: pw.TableBorder(
                            verticalInside: pw.BorderSide(
                              color: _greyLight,
                              width: 0.5,
                            ),
                          ),
                          children: [
                            // Header row
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(
                                color: _greyLight,
                              ),
                              children: [
                                for (final t in const [
                                  'QUÉ INCLUYE EL CONTRATO',
                                  'CUOTAS DEL PLAN',
                                  'CÓMO QUEDA LA CUENTA',
                                ])
                                  pw.Padding(
                                    padding: pw.EdgeInsets.fromLTRB(
                                      8,
                                      dRecibo.sp(4),
                                      8,
                                      dRecibo.sp(4),
                                    ),
                                    child: pw.Text(
                                      t,
                                      style: pw.TextStyle(
                                        fontSize: dRecibo.fs(6, piso: 5),
                                        color: _greyText,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            // Data row
                            pw.TableRow(
                              children: [
                                // Columna 1: Desglose contrato
                                pw.Padding(
                                  padding: pw.EdgeInsets.fromLTRB(
                                    8,
                                    dRecibo.sp(6),
                                    8,
                                    dRecibo.sp(6),
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Builder(
                                        builder: (ctx) {
                                          final double montoBase =
                                              alumno.montoTotalPactado -
                                              alumno.mesaExtraPrecio -
                                              alumno.sillasExtraPrecioTotal;

                                          // Cálculos de saldo restante por concepto
                                          final double saldoMesaRestante =
                                              (alumno.mesaExtraPrecio -
                                                      alumno.mesaExtraPagado)
                                                  .clamp(0.0, double.infinity);
                                          final double saldoSillasRestante =
                                              (alumno.sillasExtraPrecioTotal -
                                                      alumno.sillasExtraPagado)
                                                  .clamp(0.0, double.infinity);
                                          final double saldoBaseRestante =
                                              (valSaldo -
                                                      saldoMesaRestante -
                                                      saldoSillasRestante)
                                                  .clamp(0.0, double.infinity);

                                          return pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              pw.Text(
                                                '· Base: ${montoBase.toCurrency()}  (Resta: ${(saldoBaseRestante > 0.01 ? saldoBaseRestante : 0.0).toCurrency()})',
                                                style: pw.TextStyle(
                                                  fontSize: dRecibo.fs(
                                                    7,
                                                    piso: 6,
                                                  ),
                                                  fontWeight:
                                                      pw.FontWeight.bold,
                                                  color: _darkText,
                                                ),
                                              ),
                                              if (alumno.mesaExtraPrecio > 0.01)
                                                ...() {
                                                  final mesas =
                                                      MesasExtraUtils.estadoDesdeContrato(
                                                        alumno,
                                                      );
                                                  final lineasMesas =
                                                      lineasDetalleMesasContratoPdf(
                                                        mesas: mesas,
                                                        cuotasPlan: alumno
                                                            .mesaExtraCuotas,
                                                      );
                                                  return lineasMesas
                                                      .map(
                                                        (linea) => pw.Padding(
                                                          padding:
                                                              const pw.EdgeInsets.only(
                                                                top: 1,
                                                              ),
                                                          child: pw.Text(
                                                            linea.texto,
                                                            style: pw.TextStyle(
                                                              fontSize: dRecibo
                                                                  .fs(
                                                                    7,
                                                                    piso: 6,
                                                                  ),
                                                              color:
                                                                  linea
                                                                      .liquidada
                                                                  ? PdfColors
                                                                        .green800
                                                                  : _greyText,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList();
                                                }(),
                                              if (alumno
                                                      .sillasExtraPrecioTotal >
                                                  0.01)
                                                pw.Padding(
                                                  padding:
                                                      const pw.EdgeInsets.only(
                                                        top: 1,
                                                      ),
                                                  child: pw.Text(
                                                    '· Sillas Extras (${alumno.sillasExtraCantidad} sillas): ${alumno.sillasExtraPrecioTotal.toCurrency()}  (Resta: ${(saldoSillasRestante > 0.01 ? saldoSillasRestante : 0.0).toCurrency()} | Cuota ${alumno.sillasExtraCuotasPagadas}/${alumno.sillasExtraCuotas})',
                                                    style: pw.TextStyle(
                                                      fontSize: dRecibo.fs(
                                                        7,
                                                        piso: 6,
                                                      ),
                                                      color: _greyText,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                      pw.Padding(
                                        padding: pw.EdgeInsets.only(
                                          top: dRecibo.sp(3),
                                        ),
                                        child: pw.Text(
                                          'TOTAL DEL CONTRATO: ${alumno.montoTotalPactado.toCurrency()}',
                                          style: pw.TextStyle(
                                            fontSize: dRecibo.fs(7, piso: 6),
                                            fontWeight: pw.FontWeight.bold,
                                            color: _darkText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Columna 2: Cuotas
                                pw.Padding(
                                  padding: pw.EdgeInsets.fromLTRB(
                                    8,
                                    dRecibo.sp(6),
                                    8,
                                    dRecibo.sp(6),
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.center,
                                    children: [
                                      pw.Text(
                                        '$cuotasPagadasRecibo/${alumno.totalCuotas}',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(13, piso: 10),
                                          fontWeight: pw.FontWeight.bold,
                                          color:
                                              cuotasPagadasRecibo >=
                                                  alumno.totalCuotas
                                              ? _greenAccent
                                              : _gold,
                                        ),
                                      ),
                                      pw.Text(
                                        'pagadas',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(6, piso: 5),
                                          color: _greyText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Columna 3: Balance
                                pw.Padding(
                                  padding: pw.EdgeInsets.fromLTRB(
                                    8,
                                    dRecibo.sp(6),
                                    8,
                                    dRecibo.sp(6),
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        'Abonado del plan (acumulado)',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(6, piso: 5),
                                          color: _greyText,
                                        ),
                                      ),
                                      pw.Text(
                                        (alumno.montoTotalPactado - valSaldo)
                                            .toCurrency(),
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(8, piso: 6.5),
                                          fontWeight: pw.FontWeight.bold,
                                          color: _greenAccent,
                                        ),
                                      ),
                                      pw.Text(
                                        'todo el contrato, no solo hoy',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(5.5, piso: 5),
                                          fontStyle: pw.FontStyle.italic,
                                          color: _greyText,
                                        ),
                                      ),
                                      pw.SizedBox(height: dRecibo.sp(3)),
                                      pw.Text(
                                        'Falta del plan',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(6, piso: 5),
                                          color: _greyText,
                                        ),
                                      ),
                                      pw.Text(
                                        valSaldo.toCurrency(),
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(9, piso: 7),
                                          fontWeight: pw.FontWeight.bold,
                                          color: valSaldo < 0.01
                                              ? _greenAccent
                                              : (now.isAfter(evento.fechaEvento)
                                                    ? _redAccent
                                                    : _gold),
                                        ),
                                      ),
                                      pw.Text(
                                        'solo cuotas, sin mora',
                                        style: pw.TextStyle(
                                          fontSize: dRecibo.fs(5.5, piso: 5),
                                          fontStyle: pw.FontStyle.italic,
                                          color: _greyText,
                                        ),
                                      ),
                                      // La mora pendiente no se repite acá: el
                                      // recuadro rojo de arriba ya la grita,
                                      // fechada y con las cuotas de las que
                                      // sale. El mismo importe en dos lugares
                                      // del papel invita a sumarlo dos veces.
                                      //
                                      // La mora saldada tampoco: que no quede
                                      // nada pendiente lo dice el recuadro
                                      // verde, y sin recuadro rojo no hay
                                      // deuda que aclarar.
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Lo único de la tabla que no se explica solo. Qué es
                        // "abonado acumulado" y qué es "falta del plan" ya lo
                        // dicen los rótulos en cursiva de cada número ("todo
                        // el contrato, no solo hoy", "solo cuotas, sin mora"):
                        // el párrafo largo que estaba acá los repetía y comía
                        // cuatro renglones de una hoja que no sobraba.
                        if (dRecibo.subtextos)
                          pw.Padding(
                            padding: pw.EdgeInsets.fromLTRB(
                              8,
                              dRecibo.sp(4),
                              8,
                              dRecibo.sp(6),
                            ),
                            child: pw.Text(
                              'La mora es el interés por pagar fuera de '
                              'término: se cobra aparte y no baja el saldo '
                              'del plan.',
                              style: pw.TextStyle(
                                fontSize: dRecibo.fs(7, piso: 6),
                                fontStyle: pw.FontStyle.italic,
                                color: _greyText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (esReimpresionPdf)
                    pw.Padding(
                      padding: pw.EdgeInsets.only(top: dRecibo.sp(5)),
                      child: pw.Text(
                        'Reimpreso el: $fechaEmision (Original: $fechaStr)',
                        style: pw.TextStyle(
                          fontSize: dRecibo.fs(7, piso: 6),
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ),

                  // Firmas removidas por solicitud
                ],
              ),
            ),
          ],
        ),
      );
    }

    final ajusteRecibo = await _ajustarParaEntrar(
      objetivo: _mediaA4,
      theme: temaRecibo,
      construir: (a) {
        dRecibo = a;
        return cuerpoRecibo();
      },
    );
    dRecibo = ajusteRecibo.ajuste;

    pdf.addPage(
      pw.Page(
        pageFormat: formatoRecibo,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => cuerpoRecibo(),
      ),
    );

    final bytes = await pdf.save();
    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(
        bytes,
        'Recibo_${alumno.nombreAlumno.replaceAll(' ', '_')}.pdf',
      );
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Recibo_${alumno.nombreAlumno}.pdf',
      );
    }
    return ajusteRecibo;
  }

  // ── Resumen a abonar (informativo, pre-cobro) ────────────────────────────
  static Future<void> generarResumenAbonarAlumno({
    required ContratoAlumno alumno,
    required Evento evento,
    required double subtotalLiquidacion,
    required double totalAbonar,
    required List<Map<String, dynamic>> conceptosLineas,
    String? medioPago,
    double? montoEfectivoDetalle,
    double? montoTransferenciaDetalle,
    double? montoTransferenciaCanal,
    bool informarCargoTransferenciaExterno = false,
    double? porcentajeCargoTransferenciaExterno,
    double? montoCargoTransferenciaInformado,
    double? moraPendienteNoIncluida,
    double porcentajeDescuentoLiquidacion = 0,
  }) async {
    pw.Font? fontRegular;
    pw.Font? fontBold;
    try {
      fontRegular = await PdfGoogleFonts.outfitRegular();
      fontBold = await PdfGoogleFonts.outfitBold();
    } catch (_) {}

    // El tema se guarda aparte: la medición tiene que usar exactamente las
    // mismas fuentes, o el alto medido no sería el alto real.
    final temaResumen = fontRegular != null && fontBold != null
        ? pw.ThemeData.withFont(base: fontRegular, bold: fontBold)
        : null;
    final pdf = pw.Document(theme: temaResumen);

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/isotipo-ej.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error al cargar logo: $e');
    }

    final now = ArTime.nowUtc();
    final fechaStr = ArTime.formatFechaHora(now);
    final operacionStr = ArTime.operacionGestionada(now);

    final mesasEstadoResumen = MesasExtraUtils.estadoDesdeContrato(alumno);
    final cantMesasResumen = MesasExtraUtils.cantidadMesasContrato(
      alumno,
      mesasEstadoResumen,
    );
    final conceptosLineasDisplay = lineasDisplayParaPdf(
      compactarCuotasBaseParaPdf(
        agruparConceptosMesasParaPdf(
          normalizarBanderasLineasPdf(
            conceptosLineas.map((c) => Map<String, dynamic>.from(c)).toList(),
          ),
          cantMesasResumen,
        ),
      ),
      regAr: alumno.createdAt != null ? ArTime.toAr(alumno.createdAt!) : null,
      hoyAr: ArTime.toAr(now),
    );

    // Mora de cuotas ya pagadas en cobros anteriores: no cuelga de ninguna
    // línea de este cobro, va en su propio bloque al final del detalle.
    final lineasLiquidacion = conceptosLineasDisplay
        .where((c) => c['esCargoCanal'] != true && c['arrastre'] != true)
        .toList();
    final lineasArrastreMora = conceptosLineasDisplay
        .where((c) => c['arrastre'] == true)
        .toList();
    final lineasCargo = conceptosLineasDisplay
        .where((c) => c['esCargoCanal'] == true)
        .toList();
    final double cargoTotal = lineasCargo.fold<double>(
      0,
      (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
    );

    // Nivel de compactación del papel. Arranca intacto y lo decide la medición
    // de más abajo: se prueban escalones y se usa el primero con el que entra
    // en media hoja. El closure del contenido lee esta variable, así que
    // cambiarla acá cambia lo que se arma.
    var d = AjustePdf.intacto;

    final double planSeleccionado = grossPlanSeleccionadoPdf(
      conceptosLineasDisplay,
    );
    final double moraSeleccionada = moraSeleccionadaPdf(conceptosLineasDisplay);
    final double moraDespues = moraPendienteNoIncluida ?? 0;
    final bool hayDescuento = porcentajeDescuentoLiquidacion > 0.01;
    final bool mostrarSubtotalLiquido =
        cargoTotal > 0.01 ||
        hayDescuento ||
        (subtotalLiquidacion - totalAbonar).abs() > 0.03;

    final double? efDet = montoEfectivoDetalle;
    final double? trDet = montoTransferenciaDetalle;
    final bool esMixto =
        efDet != null && trDet != null && efDet > 0.01 && trDet > 0.01;
    final medioStr = medioPago?.trim() ?? '';
    final bool esTransferencia =
        esMixto || medioStr.toLowerCase().contains('transfer');

    final double pctCargo = porcentajeCargoTransferenciaExterno ?? 0;
    double baseCargoMonto = subtotalLiquidacion;
    if (esMixto) {
      baseCargoMonto = (subtotalLiquidacion - efDet!).clamp(
        0.0,
        double.infinity,
      );
    } else if (esTransferencia) {
      baseCargoMonto = subtotalLiquidacion;
    }
    final double? cargoInformado = montoCargoTransferenciaInformado;
    final bool usarMontoFijo = cargoInformado != null && cargoInformado > 0.01;
    final bool usarPct = pctCargo > 0.01;
    final bool mostrarLeyendaCargo =
        informarCargoTransferenciaExterno &&
        esTransferencia &&
        cargoTotal > 0.01 &&
        (usarMontoFijo || usarPct);

    String? textoLeyendaCargo;
    if (mostrarLeyendaCargo) {
      if (usarMontoFijo) {
        if (baseCargoMonto > 0.01) {
          final eqPct = 100.0 * cargoTotal / baseCargoMonto;
          if (eqPct > 0.01 && eqPct <= 999.0) {
            textoLeyendaCargo =
                'Referencia informativa (costo sobre transferencia): '
                '${cargoTotal.toCurrency()} (~${eqPct.toStringAsFixed(1)}% de '
                '${baseCargoMonto.toCurrency()}).';
          } else {
            textoLeyendaCargo =
                'Referencia informativa (costo sobre transferencia): '
                '${cargoTotal.toCurrency()}.';
          }
        } else {
          textoLeyendaCargo =
              'Referencia informativa (costo sobre transferencia): '
              '${cargoTotal.toCurrency()}.';
        }
      } else {
        textoLeyendaCargo =
            'Referencia informativa (${pctCargo.toStringAsFixed(1)}% sobre '
            'transferencia): costo estimado ${cargoTotal.toCurrency()}.';
      }
    }

    pw.Widget lineaConcepto(Map<String, dynamic> c) {
      // 'display' es el rótulo de mostrador; 'concepto' queda intacto porque es
      // el texto que reconocen los detectores de pago (pago_interes_mora).
      final desc =
          (c['display'] as String?) ?? (c['concepto'] as String? ?? 'Concepto');
      final monto = (c['monto'] as num?)?.toDouble() ?? 0;
      final sub = c['subtexto'] as String?;
      final gross = (c['gross'] as num?)?.toDouble();
      final bool plan = c['esPlanLiquidacion'] == true;
      // Mora anidada: sangrada bajo la cuota que la generó.
      final bool anidada = c['anidada'] == true;
      final String? subNominal = plan && gross != null && gross > monto + 0.01
          ? 'nom. ${gross.toCurrency()}'
          : null;
      final descFinal = d.abreviar ? abreviarDisplayPdf(desc) : desc;
      return pw.Padding(
        padding: pw.EdgeInsets.only(
          bottom: d.sp(4),
          left: anidada ? d.sp(16) : 0,
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    anidada ? '↳ $descFinal' : '· $descFinal',
                    style: pw.TextStyle(
                      fontSize: d.fs(anidada ? 8 : 9),
                      color: anidada ? _greyText : _darkText,
                    ),
                  ),
                  // Los subtextos son datos auxiliares: son lo primero que se
                  // saca cuando el papel no entra, antes que achicar la letra.
                  if (d.subtextos && sub != null && sub.isNotEmpty)
                    pw.Text(
                      sub,
                      style: pw.TextStyle(
                        fontSize: d.fs(7, piso: 6.5),
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                  if (d.subtextos && subNominal != null)
                    pw.Text(
                      subNominal,
                      style: pw.TextStyle(
                        fontSize: d.fs(7, piso: 6.5),
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                ],
              ),
            ),
            pw.Text(
              monto.toCurrency(),
              style: pw.TextStyle(
                fontSize: d.fs(anidada ? 8 : 9),
                fontWeight: pw.FontWeight.bold,
                color: anidada ? _greyText : _darkText,
              ),
            ),
          ],
        ),
      );
    }

    // Objetivo: media hoja A4, para cortar dos por página. Antes esto era una
    // `pw.Page` de A4 fijo y lo que no entraba en los 842 pt se caía del
    // MediaBox **sin error ni aviso**: como el total va al final del layout, lo
    // primero que desaparecía era "TOTAL A PAGAR AHORA" y "CÓMO QUEDA LA
    // CUENTA", o sea que el papel salía con el detalle y sin el total.
    //
    // Ahora se mide y se compacta hasta que entre (ver [_ajustarParaEntrar]).
    // El alto libre con piso de media hoja es la red de seguridad: garantiza
    // que nada se pueda recortar aunque ningún nivel alcance.
    final formatoResumen = PdfPageFormat(
      PdfPageFormat.a4.width,
      double.infinity,
    );

    pw.Widget cuerpoResumen() {
      return pw.ConstrainedBox(
        constraints: pw.BoxConstraints(minHeight: _mediaA4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: pw.EdgeInsets.fromLTRB(22, d.sp(16), 22, d.sp(14)),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _greyLight, width: 0.5),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (logoImage != null)
                            pw.Container(
                              height: 30,
                              margin: const pw.EdgeInsets.only(right: 12),
                              child: pw.Image(logoImage),
                            ),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Victor Adrián Argüello',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 10,
                                  color: _darkText,
                                ),
                              ),
                              pw.Text(
                                'Dueño, Junior Eventos',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: _greyText,
                                ),
                              ),
                              pw.Text(
                                'CUIT 23-32837670-9',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: _greyText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'DETALLE DE PAGO',
                            style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                          pw.Text(
                            'N° ${alumno.id.substring(0, 8).toUpperCase()}',
                            style: pw.TextStyle(fontSize: 8, color: _greyText),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Fecha: $fechaStr',
                    style: pw.TextStyle(fontSize: 9, color: _greyText),
                  ),
                  pw.Text(
                    operacionStr,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontStyle: pw.FontStyle.italic,
                      color: _greyText,
                    ),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.fromLTRB(22, d.sp(12), 22, d.sp(16)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    alumno.nombreAlumno.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  pw.Text(
                    EventoPresentacion.institucionOEventoParaPdf(
                      evento: evento,
                      institucionAlumno: alumno.institucion,
                    ),
                    style: pw.TextStyle(fontSize: 9, color: _greyText),
                  ),
                  if (alumno.cursoDivision != null &&
                      alumno.cursoDivision!.trim().isNotEmpty)
                    pw.Text(
                      alumno.cursoDivision!,
                      style: pw.TextStyle(fontSize: 9, color: _greyText),
                    ),
                  if (evento.modalidad != 'masivo' &&
                      evento.tipoParaMostrar.trim().isNotEmpty)
                    pw.Text(
                      evento.tipoParaMostrar,
                      style: pw.TextStyle(fontSize: 9, color: _greyText),
                    ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Este papel no es un recibo: todavía no se registró el pago.',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontStyle: pw.FontStyle.italic,
                      color: _greyText,
                    ),
                  ),
                  if (medioStr.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    if (esMixto)
                      pw.Text(
                        'Medio de pago: Mixto — Efectivo '
                        '${efDet.toCurrency()} · Transferencia '
                        '${trDet.toCurrency()}',
                        style: pw.TextStyle(fontSize: 9, color: _greyText),
                      )
                    else
                      pw.Text(
                        'Medio de pago: $medioStr',
                        style: pw.TextStyle(fontSize: 9, color: _greyText),
                      ),
                    if (montoTransferenciaCanal != null &&
                        montoTransferenciaCanal > 0.01 &&
                        cargoTotal > 0.01)
                      pw.Text(
                        'Transferencia total canal: '
                        '${montoTransferenciaCanal.toCurrency()} '
                        '(liquidación ${subtotalLiquidacion.toCurrency()} '
                        '+ cargo ${cargoTotal.toCurrency()})',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                  ],
                  pw.SizedBox(height: 12),
                  pw.Text(
                    'LO QUE SE PAGA HOY',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _greyText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  ...lineasLiquidacion.map(lineaConcepto),
                  if (lineasArrastreMora.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      tituloArrastreMoraPdf.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greyText,
                        letterSpacing: 0.8,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    ...lineasArrastreMora.map(lineaConcepto),
                  ],
                  if (planSeleccionado > 0.01 && moraSeleccionada > 0.01)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
                      child: pw.Text(
                        'Plan ${planSeleccionado.toCurrency()} · '
                        'Mora ${moraSeleccionada.toCurrency()}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ),
                  if (mostrarSubtotalLiquido)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2, bottom: 6),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Subtotal liquidación',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                          pw.Text(
                            subtotalLiquidacion.toCurrency(),
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    pw.SizedBox(height: 6),
                  ..._bloqueDescuentoLiquidacionPdf(
                    porcentajeDescuento: porcentajeDescuentoLiquidacion,
                    conceptos: conceptosLineasDisplay,
                    fontSize: 8,
                  ),
                  if (cargoTotal > 0.01) ...[
                    pw.Text(
                      'COSTO POR TRANSFERENCIA (referencia)',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greyText,
                        letterSpacing: 0.8,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    ...lineasCargo.map(lineaConcepto),
                    if (textoLeyendaCargo != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        textoLeyendaCargo,
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 6),
                  ],
                  // Aviso de mora no incluida: tiene que verse ANTES del
                  // total, para que nadie firme el pago creyendo que queda
                  // en cero.
                  if (moraDespues > 0.01) ...[
                    pw.Container(
                      width: double.infinity,
                      padding: pw.EdgeInsets.all(d.sp(10)),
                      margin: pw.EdgeInsets.only(bottom: d.sp(8)),
                      decoration: pw.BoxDecoration(
                        color: _cardBg,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(6),
                        ),
                        border: pw.Border.all(color: _redAccent, width: 1),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'ATENCIÓN: queda debiendo mora (interés por '
                            'pagar fuera de término) por '
                            '${moraDespues.toCurrency()}',
                            style: pw.TextStyle(
                              fontSize: d.fs(9.5),
                              fontWeight: pw.FontWeight.bold,
                              color: _redAccent,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'No se cobra en este pago. Sigue sumando hasta '
                            'que se abone.',
                            style: pw.TextStyle(
                              fontSize: d.fs(8, piso: 7),
                              color: _darkText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: _greyLight,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          esTransferencia && cargoTotal > 0.01
                              ? 'TOTAL A TRANSFERIR AHORA'
                              : 'TOTAL A PAGAR AHORA',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: _darkText,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.Text(
                          totalAbonar.toCurrency(),
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Acá NO va ninguna proyección de cómo quedaría la cuenta si
                  // se paga este total: el papel dice arriba que el pago todavía
                  // no se registró, y ese cálculo ya lo imprime el recibo al
                  // confirmar el cobro ('CÓMO QUEDA LA CUENTA DESPUÉS DE ESTE
                  // PAGO'). Con los dos números dando vueltas, las familias
                  // leían el proyectado como si fuera la deuda del día.
                  //
                  // La leyenda de la mora sale sólo si el papel habla de mora,
                  // sea la que se cobra o la que queda debiendo: en un cobro
                  // limpio no tiene nada que explicar.
                  if (moraSeleccionada > 0.01 || moraDespues > 0.01) ...[
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'La mora no forma parte del saldo del plan de cuotas; '
                      'sí suma al total a pagar ahora si está en la selección.',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Se prueba de menos a más invasivo y se corta apenas entra: si con juntar
    // el aire alcanza, no se abrevia; si con abreviar alcanza, no se achica la
    // letra. Un cobro común no pasa del nivel 0 y sale igual que siempre.
    d = (await _ajustarParaEntrar(
      objetivo: _mediaA4,
      theme: temaResumen,
      construir: (a) {
        d = a;
        return cuerpoResumen();
      },
    )).ajuste;

    pdf.addPage(
      pw.Page(
        pageFormat: formatoResumen,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => cuerpoResumen(),
      ),
    );

    final bytes = await pdf.save();
    final safeName = alumno.nombreAlumno
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim();
    final fname =
        'Detalle_de_pago_${safeName.isEmpty ? 'alumno' : safeName.replaceAll(' ', '_')}.pdf';
    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  // ── Planilla por Cursos (Para Eventos Masivos) ─────────────────────────
  // ── Estado de cuenta del alumno (historial + saldo + mora) ───────────────
  /// Resumen imprimible de la cuenta: qué se pagó, qué falta y de dónde viene
  /// la mora. [pagos] son las filas ya enriquecidas del historial.
  static Future<void> generarEstadoCuentaAlumno({
    required ContratoAlumno alumno,
    required Evento evento,
    required List<Map<String, dynamic>> pagos,

    /// Solo cuotas del plan: es lo único que baja el saldo. La mora y el costo
    /// por transferencia van aparte para que el total no confunda.
    required double totalPlanAbonado,
    required double totalMoraCobrada,
    required double moraPendiente,
    double totalCargoCanal = 0,
    List<MoraPendientePreviaDetalle> arrastreMora = const [],
  }) async {
    pw.Font? fontRegular;
    pw.Font? fontBold;
    try {
      fontRegular = await PdfGoogleFonts.outfitRegular();
      fontBold = await PdfGoogleFonts.outfitBold();
    } catch (_) {}

    final pdf = pw.Document(
      theme: fontRegular != null && fontBold != null
          ? pw.ThemeData.withFont(base: fontRegular, bold: fontBold)
          : null,
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/isotipo-ej.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error al cargar logo: $e');
    }

    final now = ArTime.nowUtc();
    final fechaStr = ArTime.formatFechaHora(now);
    final saldoPlan = alumno.saldoDeudor.clamp(0.0, double.infinity);
    // Valor nominal del plan ya cubierto. Cierra contra el saldo; puede diferir
    // de lo entregado cuando hubo descuento de liquidación.
    final cuotasCubiertas = (alumno.montoTotalPactado - saldoPlan).clamp(
      0.0,
      double.infinity,
    );
    final bool hayDescuentoEstado =
        (cuotasCubiertas - totalPlanAbonado).abs() > 1;

    pw.Widget filaResumen(String label, String valor, {PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(fontSize: 9, color: color ?? _darkText),
              ),
              pw.Text(
                valor,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: color ?? _darkText,
                ),
              ),
            ],
          ),
        );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      height: 30,
                      margin: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(logoImage),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Victor Adrián Argüello',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: _darkText,
                        ),
                      ),
                      pw.Text(
                        'Dueño, Junior Eventos',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                      pw.Text(
                        'CUIT 23-32837670-9',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ESTADO DE CUENTA',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  pw.Text(
                    'N° ${alumno.id.substring(0, 8).toUpperCase()}',
                    style: pw.TextStyle(fontSize: 8, color: _greyText),
                  ),
                  pw.Text(
                    'Al $fechaStr',
                    style: pw.TextStyle(fontSize: 8, color: _greyText),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(color: _greyLight, height: 16),
          pw.Text(
            alumno.nombreAlumno.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
          pw.Text(
            EventoPresentacion.institucionOEventoParaPdf(
              evento: evento,
              institucionAlumno: alumno.institucion,
            ),
            style: pw.TextStyle(fontSize: 9, color: _greyText),
          ),
          if (alumno.cursoDivision != null &&
              alumno.cursoDivision!.trim().isNotEmpty)
            pw.Text(
              alumno.cursoDivision!,
              style: pw.TextStyle(fontSize: 9, color: _greyText),
            ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _cardBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: _greyLight, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                filaResumen(
                  'Total del plan',
                  alumno.montoTotalPactado.toCurrency(),
                ),
                filaResumen(
                  'Cuotas cubiertas (${alumno.cuotasPagadas} de ${alumno.totalCuotas})',
                  cuotasCubiertas.toCurrency(),
                  color: _greenAccent,
                ),
                // Con descuento, lo entregado es menor al valor nominal que se
                // dio por cubierto: se muestran los dos para que la cuenta
                // cierre contra el saldo.
                if (hayDescuentoEstado) ...[
                  filaResumen(
                    '   descuento aplicado',
                    '− ${(cuotasCubiertas - totalPlanAbonado).toCurrency()}',
                    color: _greyText,
                  ),
                  filaResumen(
                    'Entregado por cuotas',
                    totalPlanAbonado.toCurrency(),
                    color: _greenAccent,
                  ),
                ],
                filaResumen('Saldo del plan', saldoPlan.toCurrency()),
                filaResumen(
                  'Mora pendiente (interés por pagar fuera de término)',
                  moraPendiente.toCurrency(),
                  color: moraPendiente > 0.01 ? _redAccent : _greenAccent,
                ),
              ],
            ),
          ),
          if (arrastreMora.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'DE DÓNDE VIENE LA MORA',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _greyText,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 4),
            ...arrastreMora.map(
              (d) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 5),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Text(
                            '· Cuota ${d.numeroCuota}'
                            '${d.mesLabel.isEmpty ? '' : ' (${d.mesLabel})'}',
                            style: pw.TextStyle(fontSize: 9, color: _darkText),
                          ),
                        ),
                        pw.Text(
                          d.montoAtribuido.toCurrency(),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                      ],
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8),
                      child: pw.Text(
                        d.subtextoDetalle,
                        style: pw.TextStyle(
                          fontSize: 7.5,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'PAGOS REGISTRADOS',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _greyText,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 4),
          if (pagos.isEmpty)
            pw.Text(
              'Todavía no hay pagos registrados.',
              style: pw.TextStyle(
                fontSize: 9,
                fontStyle: pw.FontStyle.italic,
                color: _greyText,
              ),
            )
          else
            ...pagos.map((p) {
              final fechaRaw = p['fecha_pago']?.toString();
              final fecha = fechaRaw != null
                  ? DateTime.tryParse(fechaRaw)
                  : null;
              final fechaTxt = fecha != null
                  ? ArTime.formatFechaCorta(fecha)
                  : (fechaRaw ?? '');
              // `concepto_ficha` es el rótulo legible de las filas de mora; el
              // resto sigue con el detallado de siempre.
              final concepto =
                  (p['concepto_ficha'] as String?)?.trim().isNotEmpty == true
                  ? p['concepto_ficha'] as String
                  : ((p['concepto_detallado'] as String?)?.trim().isNotEmpty ==
                          true
                      ? p['concepto_detallado'] as String
                      : (p['concepto']?.toString() ?? 'Pago'));
              final sub = ((p['subtexto_ficha'] as String?)?.trim().isNotEmpty ==
                      true
                  ? p['subtexto_ficha'] as String
                  : p['subtexto_concepto'] as String?)
                  ?.trim();
              final medio = (p['subtitulo_medio'] as String?)?.trim();
              final monto = (p['monto'] as num?)?.toDouble() ?? 0;
              // Las filas que no son del plan quedan marcadas: son las que no
              // entran en el total abonado de abajo.
              final bool esMoraFila = ConceptoPagoDisplay.esMora(p);
              final bool esCargoFila = ConceptoPagoDisplay.esCargoCanal(p);
              final String prefijo = esMoraFila
                  ? 'MORA · '
                  : (esCargoFila ? 'COSTO · ' : '');
              final PdfColor colorFila = esMoraFila
                  ? _redAccent
                  : (esCargoFila ? _greyText : _darkText);
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 58,
                          child: pw.Text(
                            fechaTxt,
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              color: _greyText,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            '$prefijo$concepto',
                            style: pw.TextStyle(fontSize: 9, color: colorFila),
                          ),
                        ),
                        pw.Text(
                          monto.toCurrency(),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: colorFila,
                          ),
                        ),
                      ],
                    ),
                    if ((sub != null && sub.isNotEmpty) ||
                        (medio != null && medio.isNotEmpty))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 58),
                        child: pw.Text(
                          [
                            if (sub != null && sub.isNotEmpty) sub,
                            if (medio != null && medio.isNotEmpty) medio,
                          ].join(' · '),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontStyle: pw.FontStyle.italic,
                            color: _greyText,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          pw.Divider(color: _greyLight, height: 14),
          // La mora cobrada va acá arriba, separada: no integra el total.
          filaResumen(
            'Mora cobrada',
            totalMoraCobrada.toCurrency(),
            color: totalMoraCobrada > 0.01 ? _redAccent : _greyText,
          ),
          if (totalCargoCanal > 0.01)
            filaResumen(
              'Costo por transferencia',
              totalCargoCanal.toCurrency(),
              color: _greyText,
            ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL ABONADO EN CUOTAS DEL PLAN',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                  letterSpacing: 0.5,
                ),
              ),
              pw.Text(
                totalPlanAbonado.toCurrency(),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'El "TOTAL ABONADO EN CUOTAS DEL PLAN" cuenta solo lo que se pagó '
            'de las cuotas: es lo único que baja el saldo del plan. La mora y '
            'el costo por transferencia se cobran '
            'aparte y se listan por separado. Documento informativo: no '
            'reemplaza al recibo de pago.',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontStyle: pw.FontStyle.italic,
              color: _greyText,
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeName = alumno.nombreAlumno
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim();
    final fname =
        'Estado_de_cuenta_${safeName.isEmpty ? 'alumno' : safeName.replaceAll(' ', '_')}.pdf';
    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  static Future<void> generarPlanillaCursos(
    Evento evento,
    List<ContratoAlumno> alumnos,
  ) async {
    // Si no es un evento masivo o no hay alumnos, podríamos abortar, pero asumimos que aquí ya llegamos con data válida.
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    // Agrupar alumnos por curso_division
    final alumnosPorCurso = <String, List<ContratoAlumno>>{};
    for (final alumno in alumnos) {
      // Ignorar alumnos dados de baja
      if (alumno.nombreAlumno.startsWith('[BAJA]')) continue;

      final curso = alumno.cursoDivision?.trim().isNotEmpty == true
          ? alumno.cursoDivision!.trim()
          : 'Sin Curso Asignado';
      if (!alumnosPorCurso.containsKey(curso)) {
        alumnosPorCurso[curso] = [];
      }
      alumnosPorCurso[curso]!.add(alumno);
    }

    // Ordenar los cursos alfabéticamente
    final cursos = alumnosPorCurso.keys.toList()..sort();

    // Crear una página (o más) por curso
    for (final curso in cursos) {
      final alumnosDelCurso = alumnosPorCurso[curso]!;
      // Ordenar alumnos por nombre
      alumnosDelCurso.sort((a, b) => a.nombreAlumno.compareTo(b.nombreAlumno));

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'PLANILLA DE INGRESO - ${evento.cliente?.nombreCompleto ?? 'EVENTO'}',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _gold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'CURSO / DIVISIÓN: $curso',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.Divider(color: _gold),
              pw.SizedBox(height: 10),
            ],
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: _greyLight),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
                fontSize: 10,
              ),
              headerDecoration: const pw.BoxDecoration(color: _headerBg),
              cellStyle: pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(2),
                5: const pw.FlexColumnWidth(2.5),
              },
              data: <List<String>>[
                <String>[
                  'ALUMNO',
                  'TELÉFONO',
                  'MESA',
                  'SILLAS',
                  'MÚSICA ELEGIDA',
                  'ACOMPAÑANTES',
                ],
                ...alumnosDelCurso.map((a) {
                  final acompanantes = a.nombresAcompanantes.join(', ');
                  final musica = a.musicaElegida?.isNotEmpty == true
                      ? a.musicaElegida!
                      : '-';
                  final mesa = a.numeroMesa?.isNotEmpty == true
                      ? a.numeroMesa!
                      : '-';
                  final sillas = a.sillasExtraCantidad > 0
                      ? a.sillasExtraCantidad.toString()
                      : '-';
                  final telefono = a.telefono?.isNotEmpty == true
                      ? a.telefono!
                      : '-';
                  return [
                    a.nombreAlumno,
                    telefono,
                    mesa,
                    sillas,
                    musica,
                    acompanantes,
                  ];
                }),
              ],
            ),
          ],
        ),
      );
    }

    final bytes = await pdf.save();

    // Normalizar titulo archivo
    final safeName = (evento.cliente?.nombreCompleto ?? 'Evento').replaceAll(
      RegExp(r'[^a-zA-Z0-9_\-\.]'),
      '_',
    );

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, 'Planilla_Cursos_$safeName.pdf');
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Planilla_Cursos_$safeName.pdf',
      );
    }
  }

  /// Listado de alumnos con estado de contrato firmado (export desde eventos masivos).
  /// [pendientes] y [firmados] deben estar mutuamente excluyentes y cubrir la lista deseada.
  static Future<void> generarListadoContratosFirmadosPdf({
    required String eventoTitulo,
    required DateTime generadoEn,
    required List<ContratoAlumno> pendientes,
    required List<ContratoAlumno> firmados,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    /// Solo campos con valor cargado (sin institución).
    String datosCargadosResumen(ContratoAlumno a) {
      final parts = <String>[];
      final curso = a.cursoDivision?.trim();
      if (curso != null && curso.isNotEmpty) {
        parts.add('Curso/div.: $curso');
      }
      final tel = a.telefono?.trim();
      if (tel != null && tel.isNotEmpty) {
        parts.add('Tel.: $tel');
      }
      final mesa = a.numeroMesa?.trim();
      if (mesa != null && mesa.isNotEmpty) {
        parts.add('Mesa: $mesa');
      }
      if (parts.isEmpty) {
        return 'Sin otros datos cargados';
      }
      return parts.join(' · ');
    }

    List<List<String>> filasAlumnos(List<ContratoAlumno> lista) {
      return lista.map((a) {
        return [a.nombreAlumno, datosCargadosResumen(a)];
      }).toList();
    }

    final fechaTxt = ArTime.formatFechaHora(generadoEn);
    final tituloSafe = eventoTitulo.trim().isEmpty
        ? 'Evento'
        : eventoTitulo.trim();
    final nPend = pendientes.length;
    final nFirm = firmados.length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ESTADO DE CONTRATOS — $tituloSafe',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _gold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Emitido: $fechaTxt',
              style: pw.TextStyle(fontSize: 9, color: _greyText),
            ),
            pw.Text(
              'Incluye el estado visualizado en pantalla (cambios aún no guardados con «Guardar»).',
              style: pw.TextStyle(
                fontSize: 8.5,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Listado en dos bloques: primero quienes no firmaron, después quienes sí firmaron el contrato.',
              style: pw.TextStyle(
                fontSize: 9,
                color: _darkText,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Divider(color: _gold),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) {
          const headers = <String>[
            'ALUMNO',
            'DATOS CARGADOS (curso, tel., mesa)',
          ];

          pw.Widget bloqueTitulo(String texto, PdfColor color) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12, bottom: 8),
              child: pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: pw.BoxDecoration(
                  color: color == _redAccent
                      ? PdfColor.fromInt(0xFFFFF0F0)
                      : color == _greenAccent
                      ? PdfColor.fromInt(0xFFF0FFF5)
                      : PdfColor.fromInt(0xFFF5F5F5),
                  border: pw.Border(
                    left: pw.BorderSide(color: color, width: 4),
                  ),
                ),
                child: pw.Text(
                  texto,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            );
          }

          final children = <pw.Widget>[];

          if (pendientes.isNotEmpty) {
            children.add(
              bloqueTitulo(
                'ESTOS NO FIRMARON EL CONTRATO — $nPend persona(s)',
                _redAccent,
              ),
            );
            children.add(
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: _greyLight),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                  fontSize: 9,
                ),
                headerDecoration: const pw.BoxDecoration(color: _headerBg),
                cellStyle: pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.all(5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.4),
                  1: const pw.FlexColumnWidth(2.2),
                },
                data: <List<String>>[headers, ...filasAlumnos(pendientes)],
              ),
            );
          } else {
            children.add(
              bloqueTitulo(
                'ESTOS NO FIRMARON EL CONTRATO — 0 persona(s)',
                _greyText,
              ),
            );
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '(Nadie pendiente de firma en este listado.)',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _greyText,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
            );
          }

          if (firmados.isNotEmpty) {
            children.add(
              bloqueTitulo(
                'ESTOS SÍ FIRMARON EL CONTRATO — $nFirm persona(s)',
                _greenAccent,
              ),
            );
            children.add(
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: _greyLight),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                  fontSize: 9,
                ),
                headerDecoration: const pw.BoxDecoration(color: _headerBg),
                cellStyle: pw.TextStyle(fontSize: 8.5),
                cellPadding: const pw.EdgeInsets.all(5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.4),
                  1: const pw.FlexColumnWidth(2.2),
                },
                data: <List<String>>[headers, ...filasAlumnos(firmados)],
              ),
            );
          } else {
            children.add(
              bloqueTitulo(
                'ESTOS SÍ FIRMARON EL CONTRATO — 0 persona(s)',
                _greyText,
              ),
            );
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '(Nadie figura con contrato firmado en este listado.)',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    color: _greyText,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ),
            );
          }

          return children;
        },
      ),
    );

    final bytes = await pdf.save();
    final safeName = tituloSafe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final fname = 'Contratos_${safeName}_$fechaTxt.pdf'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\\.]'), '_')
        .replaceAll('__', '_');

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  /// Encabezados de la planilla de mora, en el orden en que salen impresos.
  static const List<String> planillaMoraHeaders = <String>[
    '',
    'ALUMNO',
    'TEL.',
    'CUOTAS',
    'MORA DE CUOTAS VENCIDAS',
    'MORA NO COBRADA AL PAGAR',
    'TOTAL MORA',
    'SALDO DEL PLAN',
  ];

  /// Las filas de la planilla de mora, ya ordenadas de mayor a menor mora.
  ///
  /// Vive afuera del generador para que se pueda verificar lo único que no
  /// puede fallar: que salgan **todos**. La primera columna va vacía a
  /// propósito — el borde de la tabla la dibuja como casilla para tildar el
  /// llamado a mano.
  ///
  /// [conDetalle] es lo que decide la escalera de [AjustePdf]: cuando el papel
  /// aprieta, el desglose por cuota es lo primero que se va, y el total de cada
  /// columna queda igual.
  static List<List<String>> planillaMoraFilasTabla(
    List<MoraPdfFila> filas, {
    bool conDetalle = true,
  }) {
    String celda(double monto, String detalle) {
      if (monto <= 0.01) return '—';
      final base = monto.toCurrency();
      if (!conDetalle || detalle.trim().isEmpty) return base;
      return '$base\n${detalle.trim()}';
    }

    final ordenadas = [...filas]
      ..sort((a, b) => b.moraTotal.compareTo(a.moraTotal));
    return ordenadas
        .map(
          (f) => <String>[
            '',
            f.curso.trim().isEmpty ? f.nombre : '${f.nombre}\n${f.curso}',
            f.telefono.trim().isEmpty ? '—' : f.telefono.trim(),
            f.cuotas,
            celda(f.moraVencida, f.detalleVencida),
            celda(f.moraNoCobrada, f.detalleNoCobrada),
            f.moraTotal.toCurrency(),
            f.saldoPlan <= 0.01 ? '—' : f.saldoPlan.toCurrency(),
          ],
        )
        .toList();
  }

  /// Planilla de mora: la hoja que se usa para llamar a los que deben.
  ///
  /// Ordenada de mayor a menor mora, con el teléfono al lado y una casilla en
  /// blanco para ir tildando los llamados a mano.
  ///
  /// Los dos tipos de mora van en columnas separadas —la de cuotas vencidas
  /// impagas y la que quedó sin cobrar al pagar una cuota— y el saldo del plan
  /// va aparte: **la mora no forma parte del saldo del plan** y no se suman
  /// nunca en el mismo número.
  ///
  /// Salen **todos** los alumnos de [filas]: es `MultiPage`, que se desparrama
  /// en hojas y nunca recorta. Lo que ajusta [_ajustarParaPaginas] es cuántas
  /// hojas, no cuántos alumnos.
  static Future<void> generarPlanillaMoraPdf({
    required String eventoTitulo,
    required String filtroTitulo,
    required DateTime generadoEn,
    required List<MoraPdfFila> filas,

    /// Alumnos suspendidos con mora congelada. Van en su propio bloque al final
    /// y no se mezclan con los que sí hay que llamar.
    List<MoraPdfFila> bajas = const [],

    /// A cuántas hojas apuntar antes de empezar a compactar.
    ///
    /// Tres y no dos a propósito. Medido con 45 alumnos: en dos hojas entra,
    /// pero la escalera tiene que sacar el desglose por cuota, que es
    /// justamente el detalle por el que existe esta planilla. La hoja de más
    /// vale más que el desglose perdido — no es un recibo, es un papel de
    /// trabajo. Si el evento es más grande, la escalera compacta sola.
    int maxPaginasObjetivo = 3,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();
    final tema = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    // De mayor a menor mora: se llama de arriba hacia abajo.
    final activos = [...filas]
      ..sort((a, b) => b.moraTotal.compareTo(a.moraTotal));
    final suspendidos = [...bajas]
      ..sort((a, b) => b.moraTotal.compareTo(a.moraTotal));

    final fechaTxt = ArTime.formatFechaHora(generadoEn);
    final tituloSafe = eventoTitulo.trim().isEmpty
        ? 'Evento'
        : eventoTitulo.trim();
    final filtroSafe = filtroTitulo.trim().isEmpty
        ? 'Alumnos con mora'
        : filtroTitulo.trim();

    final totalVencida = activos.fold<double>(0, (s, f) => s + f.moraVencida);
    final totalNoCobrada = activos.fold<double>(
      0,
      (s, f) => s + f.moraNoCobrada,
    );
    final totalMora = totalVencida + totalNoCobrada;

    const margen = pw.EdgeInsets.all(28);
    const headers = planillaMoraHeaders;

    pw.Widget tabla(List<List<String>> data, AjustePdf d) {
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: _greyLight),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
          fontSize: d.fs(8, piso: 6.5),
        ),
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellStyle: pw.TextStyle(fontSize: d.fs(8, piso: 6.5)),
        cellPadding: pw.EdgeInsets.all(d.sp(4)),
        cellAlignments: const {
          0: pw.Alignment.center,
          2: pw.Alignment.centerLeft,
          3: pw.Alignment.center,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
          7: pw.Alignment.centerRight,
        },
        columnWidths: const {
          0: pw.FixedColumnWidth(16),
          1: pw.FlexColumnWidth(2.0),
          2: pw.FlexColumnWidth(1.0),
          3: pw.FlexColumnWidth(0.6),
          4: pw.FlexColumnWidth(2.1),
          5: pw.FlexColumnWidth(2.1),
          6: pw.FlexColumnWidth(1.0),
          7: pw.FlexColumnWidth(1.0),
        },
        data: <List<String>>[headers, ...data],
      );
    }

    /// Las tablas van en bloques: un solo [pw.Table] muy largo adentro de un
    /// [pw.MultiPage] puede disparar `TooManyPagesException`.
    List<pw.Widget> bloques(List<MoraPdfFila> lista, AjustePdf d) {
      final out = <pw.Widget>[];
      final data = planillaMoraFilasTabla(lista, conDetalle: d.subtextos);
      for (var i = 0; i < data.length; i += _kFilasPorBloqueListado) {
        final fin = math.min(i + _kFilasPorBloqueListado, data.length);
        if (i > 0) out.add(pw.SizedBox(height: d.sp(6)));
        out.add(tabla(data.sublist(i, fin), d));
      }
      return out;
    }

    List<pw.Widget> contenido(AjustePdf d) {
      if (activos.isEmpty && suspendidos.isEmpty) {
        return [
          pw.Text(
            'No hay alumnos con mora en este filtro.',
            style: pw.TextStyle(
              fontSize: d.fs(10),
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ];
      }
      return [
        ...bloques(activos, d),
        if (activos.isNotEmpty) ...[
          pw.SizedBox(height: d.sp(8)),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: d.sp(10),
              vertical: d.sp(7),
            ),
            decoration: const pw.BoxDecoration(color: _headerBg),
            child: pw.Text(
              '${activos.length} alumno(s) · '
              'Cuotas vencidas ${totalVencida.toCurrency()} · '
              'No cobrada al pagar ${totalNoCobrada.toCurrency()} · '
              'TOTAL MORA ${totalMora.toCurrency()}',
              style: pw.TextStyle(
                fontSize: d.fs(9.5, piso: 7),
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
          ),
        ],
        if (suspendidos.isNotEmpty) ...[
          pw.SizedBox(height: d.sp(12)),
          pw.Text(
            'BAJA TEMPORAL — MORA CONGELADA',
            style: pw.TextStyle(
              fontSize: d.fs(9.5, piso: 7),
              fontWeight: pw.FontWeight.bold,
              color: _greyText,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: d.sp(2)),
          pw.Text(
            'Suspendidos: su mora no crece. No entran en los totales de arriba.',
            style: pw.TextStyle(
              fontSize: d.fs(8, piso: 6.5),
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: d.sp(4)),
          ...bloques(suspendidos, d),
        ],
        pw.SizedBox(height: d.sp(10)),
        pw.Text(
          'La mora es el interés por pagar fuera de término: se cobra aparte y '
          'no forma parte del saldo del plan.',
          style: pw.TextStyle(
            fontSize: d.fs(8, piso: 6.5),
            color: _greyText,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ];
    }

    final ajuste = await _ajustarParaPaginas(
      maxPaginas: maxPaginasObjetivo,
      theme: tema,
      construir: contenido,
      margin: margen,
    );

    final pdf = pw.Document(theme: tema);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margen,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MORA — $tituloSafe',
              style: pw.TextStyle(
                fontSize: ajuste.fs(15, piso: 10),
                fontWeight: pw.FontWeight.bold,
                color: _gold,
              ),
            ),
            pw.SizedBox(height: ajuste.sp(3)),
            pw.Text(
              'Emitido: $fechaTxt · $filtroSafe · '
              '${activos.length} alumno(s) · ${totalMora.toCurrency()}',
              style: pw.TextStyle(
                fontSize: ajuste.fs(9, piso: 7),
                color: _greyText,
              ),
            ),
            pw.Divider(color: _gold),
            pw.SizedBox(height: ajuste.sp(4)),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _greyText),
          ),
        ),
        build: (context) => contenido(ajuste),
      ),
    );

    final bytes = await pdf.save();
    final safeName = tituloSafe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final fname = 'Mora_$safeName.pdf'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_')
        .replaceAll('__', '_');

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  /// Listado de alumnos filtrados por fecha de cobro de cuota base (Cobro — eventos masivos).
  static Future<void> generarListadoCobroPeriodoPdf({
    required String eventoTitulo,
    required String filtroTitulo,
    required DateTime generadoEn,
    required List<CobroPeriodoPdfFila> filas,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    final fechaTxt = ArTime.formatFechaHora(generadoEn);
    final tituloSafe = eventoTitulo.trim().isEmpty
        ? 'Evento'
        : eventoTitulo.trim();
    final filtroSafe = filtroTitulo.trim().isEmpty
        ? 'Listado'
        : filtroTitulo.trim();
    final n = filas.length;

    final tituloColor = filtroSafe.toLowerCase().startsWith('no pagaron')
        ? _redAccent
        : _greenAccent;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'COBRO — $tituloSafe',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _gold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Emitido: $fechaTxt',
              style: pw.TextStyle(fontSize: 9, color: _greyText),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: tituloColor == _redAccent
                    ? PdfColor.fromInt(0xFFFFF0F0)
                    : PdfColor.fromInt(0xFFF0FFF5),
                border: pw.Border(
                  left: pw.BorderSide(color: tituloColor, width: 4),
                ),
              ),
              child: pw.Text(
                '$filtroSafe — $n alumno(s)',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: tituloColor,
                ),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Solo cuotas base del plan (sin mora ni mesas). Coincide con el filtro activo en pantalla.',
              style: pw.TextStyle(
                fontSize: 8.5,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.Divider(color: _gold),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) {
          if (filas.isEmpty) {
            return [
              pw.Text(
                'No hay alumnos en este listado.',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: _greyText,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ];
          }

          const headers = <String>[
            'ALUMNO',
            'CURSO',
            'CONTRATO',
            'CUOTAS PAGADAS',
            'ÚLT. PAGO',
            'TELÉFONO',
          ];

          final data = filas
              .map(
                (f) => [
                  f.nombre,
                  f.curso,
                  f.contratoEstado,
                  f.cuotasPagadas,
                  f.ultimoPago,
                  f.telefono,
                ],
              )
              .toList();

          return [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: _greyLight),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
                fontSize: 8.5,
              ),
              headerDecoration: const pw.BoxDecoration(color: _headerBg),
              cellStyle: pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(4),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.6),
                1: const pw.FlexColumnWidth(1.1),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(0.9),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(0.9),
              },
              data: <List<String>>[headers, ...data],
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final safeName = tituloSafe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final filtroFile = filtroSafe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final fname = 'Cobro_${safeName}_$filtroFile.pdf'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\\.]'), '_')
        .replaceAll('__', '_');

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  /// PDF comparativo: pagaron + no pagaron en el mismo período (Cobro — eventos masivos).
  static Future<void> generarListadoCobroPeriodoComparativoPdf({
    required String eventoTitulo,
    required String resumenTitulo,
    required String bloquePagaronTitulo,
    required String bloqueNoPagaronTitulo,
    required DateTime generadoEn,
    required List<CobroPeriodoPdfFila> pagaron,
    required List<CobroPeriodoPdfFila> noPagaron,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    final fechaTxt = ArTime.formatFechaHora(generadoEn);
    final tituloSafe = eventoTitulo.trim().isEmpty
        ? 'Evento'
        : eventoTitulo.trim();
    final nPag = pagaron.length;
    final nNo = noPagaron.length;
    final total = nPag + nNo;

    int firmados(List<CobroPeriodoPdfFila> lista) =>
        lista.where((f) => f.contratoEstado == 'Firmado').length;

    final firmPag = firmados(pagaron);
    final firmNo = firmados(noPagaron);

    pw.Widget bloqueTitulo(String texto, PdfColor color) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 8),
        child: pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: color == _redAccent
                ? PdfColor.fromInt(0xFFFFF0F0)
                : color == _greenAccent
                ? PdfColor.fromInt(0xFFF0FFF5)
                : PdfColor.fromInt(0xFFF5F5F5),
            border: pw.Border(left: pw.BorderSide(color: color, width: 4)),
          ),
          child: pw.Text(
            texto,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        ),
      );
    }

    pw.Widget tablaAlumnos(List<CobroPeriodoPdfFila> lista) {
      if (lista.isEmpty) {
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            '(Nadie en este bloque.)',
            style: pw.TextStyle(
              fontSize: 9.5,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        );
      }

      const headers = <String>[
        'ALUMNO',
        'CURSO',
        'CONTRATO',
        'CUOTAS PAGADAS',
        'ÚLT. PAGO',
        'TELÉFONO',
      ];

      final data = lista
          .map(
            (f) => [
              f.nombre,
              f.curso,
              f.contratoEstado,
              f.cuotasPagadas,
              f.ultimoPago,
              f.telefono,
            ],
          )
          .toList();

      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: _greyLight),
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
          fontSize: 8.5,
        ),
        headerDecoration: const pw.BoxDecoration(color: _headerBg),
        cellStyle: pw.TextStyle(fontSize: 8),
        cellPadding: const pw.EdgeInsets.all(4),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.6),
          1: const pw.FlexColumnWidth(1.1),
          2: const pw.FlexColumnWidth(0.8),
          3: const pw.FlexColumnWidth(0.9),
          4: const pw.FlexColumnWidth(0.8),
          5: const pw.FlexColumnWidth(0.9),
        },
        data: <List<String>>[headers, ...data],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'COBRO — $tituloSafe',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _gold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Emitido: $fechaTxt',
              style: pw.TextStyle(fontSize: 9, color: _greyText),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              resumenTitulo.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              '· Pagaron: $nPag ($firmPag firmaron · ${nPag - firmPag} sin firmar)',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _greenAccent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              '· No pagaron: $nNo ($firmNo firmaron · ${nNo - firmNo} sin firmar)',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _redAccent,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              '· Total en listado: $total',
              style: pw.TextStyle(
                fontSize: 9.5,
                color: _darkText,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Solo cuotas base del plan (sin mora ni mesas). Columna CONTRATO: firmado o sin firmar.',
              style: pw.TextStyle(
                fontSize: 8.5,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.Divider(color: _gold),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) => [
          bloqueTitulo('$bloquePagaronTitulo — $nPag persona(s)', _greenAccent),
          tablaAlumnos(pagaron),
          bloqueTitulo('$bloqueNoPagaronTitulo — $nNo persona(s)', _redAccent),
          tablaAlumnos(noPagaron),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeName = tituloSafe.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final fname = 'Cobro_Comparativo_$safeName.pdf'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\\.]'), '_')
        .replaceAll('__', '_');

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
    }
  }

  /// PDF de análisis de rentabilidad (uso interno / gestión).
  static Future<void> generarRentabilidadPdf({
    required ResultadoRentabilidad resultado,
    required List<CostoItem> costosVariables,
    required List<CostoItem> costosFijos,
    required String honorarioModo,
    required double honorarioAdrianMonto,
    required double honorarioAdrianPct,
    String? presupuestoClienteNombre,
    String? tipoEventoLabel,
    String? notas,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/2.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final now = ArTime.nowUtc();
    final fechaEmision = ArTime.formatFechaHora(now);
    final cliente = presupuestoClienteNombre?.trim().isNotEmpty == true
        ? presupuestoClienteNombre!.trim()
        : 'Análisis interno';
    final tipo = tipoEventoLabel?.trim().isNotEmpty == true
        ? tipoEventoLabel!.trim()
        : 'Sin presupuesto vinculado';

    final estadoTxt = _estadoRentabilidadPdfLabel(resultado.estado);
    PdfColor estadoColor;
    switch (resultado.estado) {
      case EstadoRentabilidad.saludable:
        estadoColor = _greenAccent;
        break;
      case EstadoRentabilidad.ajustado:
        estadoColor = PdfColor.fromInt(0xFFF39C12);
        break;
      case EstadoRentabilidad.equilibrio:
        estadoColor = PdfColor.fromInt(0xFFF39C12);
        break;
      case EstadoRentabilidad.perdida:
        estadoColor = _redAccent;
        break;
    }

    final honorarioDetalle = honorarioModo == 'porcentaje'
        ? '${honorarioAdrianPct.toStringAsFixed(1)} % sobre precio → ${resultado.honorarioAdrian.toCurrency()}'
        : honorarioAdrianMonto.toCurrency();

    double baseRefCv = 0, descCv = 0;
    for (final c in costosVariables) {
      baseRefCv += c.montoBase < 0 ? 0.0 : c.montoBase;
      descCv += c.montoDescuento;
    }
    double baseRefCf = 0, descCf = 0;
    for (final c in costosFijos) {
      baseRefCf += c.montoBase < 0 ? 0.0 : c.montoBase;
      descCf += c.montoDescuento;
    }
    const epsDescRentPdf = 0.005;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (context) => _buildHeaderElite(
          logoImage,
          'RENTABILIDAD',
          fechaEmision,
          cliente,
          tipo,
          'INTERNO',
        ),
        footer: (context) => _buildFooter(),
        build: (context) => [
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 12, 36, 14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ANÁLISIS DE RENTABILIDAD (INTERNO)',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                    color: _gold,
                    letterSpacing: 1.1,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: pw.BoxDecoration(
                    color: _cardBg,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(6),
                    ),
                    border: pw.Border.all(color: estadoColor, width: 0.8),
                  ),
                  child: pw.Text(
                    'Estado: $estadoTxt',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: estadoColor,
                    ),
                  ),
                ),
                pw.SizedBox(height: 14),
                _buildSectionTitle('Precio y honorario'),
                pw.SizedBox(height: 6),
                _filaRentabilidadPdf(
                  'Precio al cliente',
                  resultado.precio.toCurrency(),
                  bold: true,
                ),
                _filaRentabilidadPdf(
                  'Honorario (${honorarioModo == 'porcentaje' ? '%' : 'monto'})',
                  honorarioDetalle,
                ),
                pw.SizedBox(height: 12),
                _buildSectionTitle('Costos variables'),
                pw.SizedBox(height: 6),
                if (costosVariables.isEmpty)
                  pw.Text(
                    '— Sin ítems —',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: _greyText,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  )
                else
                  ...costosVariables.map((c) => _bloqueCostoRentabilidadPdf(c)),
                pw.SizedBox(height: 10),
                _buildSectionTitle('Costos fijos / prorrateo'),
                pw.SizedBox(height: 6),
                if (costosFijos.isEmpty)
                  pw.Text(
                    '— Sin ítems —',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: _greyText,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  )
                else
                  ...costosFijos.map((c) => _bloqueCostoRentabilidadPdf(c)),
                pw.SizedBox(height: 14),
                _buildSectionTitle('Resultado'),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: _headerBg,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      if (descCv > epsDescRentPdf) ...[
                        _filaRentabilidadPdf(
                          'Base referencia (costos variables)',
                          baseRefCv.toCurrency(),
                        ),
                        _filaRentabilidadPdf(
                          'Descuentos (costos variables)',
                          '− ${descCv.toCurrency()}',
                        ),
                      ],
                      _filaRentabilidadPdf(
                        'Total costos variables',
                        resultado.costoVariableTotal.toCurrency(),
                      ),
                      if (descCf > epsDescRentPdf) ...[
                        _filaRentabilidadPdf(
                          'Base referencia (costos fijos)',
                          baseRefCf.toCurrency(),
                        ),
                        _filaRentabilidadPdf(
                          'Descuentos (costos fijos)',
                          '− ${descCf.toCurrency()}',
                        ),
                      ],
                      _filaRentabilidadPdf(
                        'Total costos fijos',
                        resultado.costoFijoTotal.toCurrency(),
                      ),
                      if (descCv > epsDescRentPdf && descCf > epsDescRentPdf)
                        _filaRentabilidadPdf(
                          'Total descuentos (CV + CF)',
                          '− ${(descCv + descCf).toCurrency()}',
                          bold: true,
                        ),
                      _filaRentabilidadPdf(
                        'Margen bruto (P − CV − CF)',
                        resultado.margenBruto.toCurrency(),
                        bold: true,
                      ),
                      _filaRentabilidadPdf(
                        'Honorario Adrián',
                        resultado.honorarioAdrian.toCurrency(),
                      ),
                      pw.Divider(color: _greyLight),
                      _filaRentabilidadPdf(
                        'GANANCIA NETA EMPRESA',
                        resultado.gananciaNetaEmpresa.toCurrency(),
                        bold: true,
                        color: resultado.gananciaNetaEmpresa >= 0
                            ? _greenAccent
                            : _redAccent,
                      ),
                      _filaRentabilidadPdf(
                        'Punto de equilibrio (referencia)',
                        resultado.puntoEquilibrio.toCurrency(),
                      ),
                      _filaRentabilidadPdf(
                        'Markup empresa (sobre costos)',
                        '${resultado.markupEmpresaPct.toStringAsFixed(1)} %',
                      ),
                    ],
                  ),
                ),
                if (notas != null && notas.isNotEmpty) ...[
                  pw.SizedBox(height: 14),
                  _buildSectionTitle('Notas'),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    notas,
                    style: pw.TextStyle(
                      fontSize: 9,
                      lineSpacing: 1.2,
                      color: _darkText,
                    ),
                  ),
                ],
                pw.SizedBox(height: 16),
                pw.Text(
                  'Documento de gestión interna. No constituye oferta comercial ni presupuesto al cliente.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: _greyText,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final safeCliente = cliente.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final fileName =
        'Rentabilidad_${safeCliente}_${DateTime.now().millisecondsSinceEpoch}.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  /// Bloques sueltos para [pw.MultiPage]: el paquete `pdf` pagina **cada widget de la lista**;
  /// un único [pw.Column] con una tabla enorme fuerza demasiadas iteraciones internas → [TooManyPagesException].
  static List<pw.Widget> _cierreCajaPdfFlatWidgets({
    required double totalIngresos,
    required double totalEgresos,
    required double ingresosEfectivo,
    required double ingresosTransferencia,
    required List<IngresoDetallado> ingresosDelDia,
    required List<Egreso> egresosDelDia,
    String? pieEmitido,
  }) {
    pw.Widget hp(pw.Widget child, {double top = 6, double bottom = 6}) =>
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(36, top, 36, bottom),
          child: child,
        );

    final neto = totalIngresos - totalEgresos;
    final out = <pw.Widget>[
      hp(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'RESUMEN DEL DÍA',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 13,
                color: _gold,
                letterSpacing: 1.0,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _headerBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _filaRentabilidadPdf(
                    'Total ingresos',
                    totalIngresos.toCurrency(),
                    bold: true,
                  ),
                  _filaRentabilidadPdf(
                    ' • Efectivo / otros medios (no transferencia)',
                    ingresosEfectivo.toCurrency(),
                  ),
                  _filaRentabilidadPdf(
                    ' • Transferencia',
                    ingresosTransferencia.toCurrency(),
                  ),
                  pw.SizedBox(height: 4),
                  _filaRentabilidadPdf(
                    'Total egresos',
                    totalEgresos.toCurrency(),
                    bold: true,
                    color: _redAccent,
                  ),
                  pw.Divider(color: _greyLight),
                  _filaRentabilidadPdf(
                    'NETO DEL DÍA',
                    neto.toCurrency(),
                    bold: true,
                    color: neto >= 0 ? _greenAccent : _redAccent,
                  ),
                ],
              ),
            ),
          ],
        ),
        top: 12,
        bottom: 8,
      ),
    ];

    if (pieEmitido != null) {
      out.add(
        hp(
          pw.Text(
            pieEmitido,
            style: pw.TextStyle(
              fontSize: 8.5,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          top: 0,
          bottom: 6,
        ),
      );
    }

    out.add(
      hp(_buildSectionTitle('Gráficos (referencia visual)'), top: 4, bottom: 4),
    );
    out.add(
      hp(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Ilustración a partir de los mismos totales del resumen; no sustituye los importes auditables.',
              style: pw.TextStyle(
                fontSize: 8,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
            pw.SizedBox(height: 10),
            _pwGraficoBarrasIngEgr(totalIngresos, totalEgresos),
            if (totalIngresos > 0) ...[
              pw.SizedBox(height: 14),
              pw.Text(
                'Composición de ingresos por medio',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                ),
              ),
              pw.SizedBox(height: 6),
              _pwBarraMediosIngresos(ingresosEfectivo, ingresosTransferencia),
            ],
          ],
        ),
        top: 2,
        bottom: 8,
      ),
    );

    out.add(hp(_buildSectionTitle('Detalle de ingresos'), top: 10, bottom: 4));
    if (ingresosDelDia.isEmpty) {
      out.add(
        hp(
          pw.Text(
            'Sin ingresos registrados este día.',
            style: pw.TextStyle(
              fontSize: 9,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          top: 2,
          bottom: 10,
        ),
      );
    } else {
      for (
        var i = 0;
        i < ingresosDelDia.length;
        i += _kCierreCajaFilasPorBloque
      ) {
        final end = math.min(
          i + _kCierreCajaFilasPorBloque,
          ingresosDelDia.length,
        );
        final slice = ingresosDelDia.sublist(i, end);
        out.add(
          hp(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (i > 0)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      'Ingresos — continuación (registros ${i + 1}–$end de ${ingresosDelDia.length})',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _greyText,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                _pwTablaIngresosCierre(slice),
              ],
            ),
            top: i == 0 ? 2 : 6,
            bottom: 8,
          ),
        );
      }
    }

    out.add(hp(_buildSectionTitle('Detalle de egresos'), top: 8, bottom: 4));
    if (egresosDelDia.isEmpty) {
      out.add(
        hp(
          pw.Text(
            'Sin egresos registrados este día.',
            style: pw.TextStyle(
              fontSize: 9,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          top: 2,
          bottom: 10,
        ),
      );
    } else {
      for (
        var i = 0;
        i < egresosDelDia.length;
        i += _kCierreCajaFilasPorBloque
      ) {
        final end = math.min(
          i + _kCierreCajaFilasPorBloque,
          egresosDelDia.length,
        );
        final slice = egresosDelDia.sublist(i, end);
        out.add(
          hp(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (i > 0)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      'Egresos — continuación (registros ${i + 1}–$end de ${egresosDelDia.length})',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _greyText,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ),
                _pwTablaEgresosCierre(slice),
              ],
            ),
            top: i == 0 ? 2 : 6,
            bottom: 8,
          ),
        );
      }
    }

    out.add(
      hp(
        pw.Text(
          'Documento operativo. Cifras según registros locales al momento de la emisión.',
          style: pw.TextStyle(
            fontSize: 8,
            color: _greyText,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        top: 12,
        bottom: 14,
      ),
    );

    return out;
  }

  /// Cierre de caja del día (calendario Argentina): totales, detalle y gráficos vectoriales.
  /// [diaCalendarioAr] debe ser un día normalizado (sin hora relevante); los listados ya filtrados a ese día.
  static Future<void> generarCierreCajaPdf({
    required DateTime diaCalendarioAr,
    required List<IngresoDetallado> ingresosDelDia,
    required List<Egreso> egresosDelDia,
    required double totalIngresos,
    required double totalEgresos,
    required double ingresosEfectivo,
    required double ingresosTransferencia,
    String? emitidoPor,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/2.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final now = ArTime.nowUtc();
    final fechaEmision = ArTime.formatFechaHora(now);
    final diaLargo = ArTime.formatFechaLarga(diaCalendarioAr);
    final diaCorto = ArTime.formatFechaCorta(diaCalendarioAr);

    final subtituloHud =
        'Totales alineados con Inteligencia financiera (SQLite local)';
    final pieEmitido = emitidoPor != null && emitidoPor.trim().isNotEmpty
        ? 'Generado por: ${emitidoPor.trim()}'
        : null;

    pdf.addPage(
      pw.MultiPage(
        maxPages: 10000,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (context) => _buildHeaderElite(
          logoImage,
          'CIERRE DE CAJA',
          fechaEmision,
          diaLargo,
          subtituloHud,
          diaCorto.replaceAll('/', '-'),
        ),
        footer: (context) => _buildFooter(),
        build: (context) => _cierreCajaPdfFlatWidgets(
          totalIngresos: totalIngresos,
          totalEgresos: totalEgresos,
          ingresosEfectivo: ingresosEfectivo,
          ingresosTransferencia: ingresosTransferencia,
          ingresosDelDia: ingresosDelDia,
          egresosDelDia: egresosDelDia,
          pieEmitido: pieEmitido,
        ),
      ),
    );

    final bytes = await pdf.save();
    final safeFecha = diaCorto.replaceAll(RegExp(r'[^0-9]'), '-');
    final fileName = 'CierreCaja_$safeFecha.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  /// Cierre de caja del turno en formato A4 compacto, alineado visualmente al recibo de pago.
  ///
  /// Por defecto ([incluirTablaIngresosDetallada] = false) genera un **comprobante corto**:
  /// totales del turno seleccionado + resumen de cantidad de ingresos + retiros (con detalle si hay).
  /// [otrosEgresosTurno] lista egresos del mismo rango horario que **no** son retiros de caja
  /// (mismas filas que Finanzas); se muestran solo como historial, sin duplicar montos.
  /// Con [incluirTablaIngresosDetallada] = true se incluye además la tabla línea a línea de ingresos.
  static Future<void> generarCierreCajaPdfTicket({
    required DateTime diaCalendarioAr,
    required TurnoCaja turno,
    required List<IngresoDetallado> ingresosTurno,
    required List<Egreso> retirosTurno,
    List<Egreso> otrosEgresosTurno = const [],
    required double efectivoBruto,
    required double transferenciaBruta,
    required double retirosEfectivo,
    required double retirosTransferencia,
    String? emitidoPor,
    String? anotacionTurno,
    double guiaCambioSaldo = 0,
    int guiaCantReposiciones = 0,
    int guiaCantUsos = 0,
    double guiaTotalReposiciones = 0,
    double guiaTotalUsos = 0,

    /// Si es `true`, lista cada ingreso del turno en tabla (PDF más largo).
    bool incluirTablaIngresosDetallada = false,

    /// Datos de la sesión cuando el alcance es una sola sesión: agrega el
    /// bloque "Cierre de sesión" (cambio inicial, arqueo, diferencia).
    double? sesionCambioInicial,
    double? sesionArqueo,
    String? sesionNotaCierre,
    DateTime? sesionAbiertaAt,
    DateTime? sesionCerradaAt,

    /// Desglose por sesión/operario para el PDF consolidado del día.
    List<ResumenSesionPdf> resumenSesiones = const [],
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final temaTicket = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
    final pdf = pw.Document(theme: temaTicket);

    // Nivel de compactación del ticket. Acá "que entre" significa no
    // desparramarse en páginas de más: se mide la cantidad de páginas y se usa
    // el primer nivel que entra en una sola. El closure lee esta variable.
    var dTicket = AjustePdf.intacto;

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/isotipo-ej.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final efectivoNeto = efectivoBruto - retirosEfectivo;
    final transferenciaNeta = transferenciaBruta - retirosTransferencia;
    final totalNeto = efectivoNeto + transferenciaNeta;

    final fechaEmision = ArTime.formatFechaHora(ArTime.nowUtc());
    final diaCorto = ArTime.formatFechaCorta(diaCalendarioAr);

    List<pw.Widget> cuerpoTicket() => [
      pw.Container(
        width: PdfPageFormat.a4.width,
        constraints: pw.BoxConstraints(minHeight: 9.5 * PdfPageFormat.cm),
        padding: pw.EdgeInsets.symmetric(
          horizontal: 22,
          vertical: dTicket.sp(8),
        ),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _greyLight, width: 0.5),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _ticketCajaHeaderReciboStyle(logoImage, turno, diaCorto),
            pw.SizedBox(height: 4),
            _ticketCajaFechaTotalNeto(fechaEmision, totalNeto),
            pw.SizedBox(height: 2),
            pw.Text(
              ArTime.operacionGestionada(ArTime.nowUtc()),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: _greyText,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'El total neto arriba es ingresos del turno menos solo retiros de caja. Otros egresos (personal, proveedores, etc.) se listan al final si corresponde.',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic,
                color: _greyText,
              ),
            ),
            pw.SizedBox(height: 6),
            _ticketCajaResumen(
              efectivoBruto: efectivoBruto,
              retirosEfectivo: retirosEfectivo,
              efectivoNeto: efectivoNeto,
              transferenciaBruta: transferenciaBruta,
              retirosTransferencia: retirosTransferencia,
              transferenciaNeta: transferenciaNeta,
            ),
            if (sesionCambioInicial != null) ...[
              pw.SizedBox(height: 10),
              _ticketCajaBloqueCierreSesion(
                cambioInicial: sesionCambioInicial,
                efectivoNeto: efectivoNeto,
                arqueo: sesionArqueo,
                notaCierre: sesionNotaCierre,
                abiertaAt: sesionAbiertaAt,
                cerradaAt: sesionCerradaAt,
              ),
            ],
            if (resumenSesiones.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _ticketCajaSeccionTitulo('POR SESIÓN / OPERARIO'),
              pw.SizedBox(height: 2),
              pw.Text(
                'Efectivo y transferencia son lo cobrado bruto por cada sesión. '
                'Dif. = arqueo declarado − efectivo esperado en el cajón.',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontStyle: pw.FontStyle.italic,
                  color: _greyText,
                ),
              ),
              pw.SizedBox(height: 4),
              _ticketCajaTablaResumenSesiones(resumenSesiones, ajuste: dTicket),
            ],
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _ticketCajaSeccionTitulo('INGRESOS DEL TURNO'),
                      pw.SizedBox(height: 3),
                      if (ingresosTurno.isEmpty)
                        pw.Text(
                          'Sin ingresos registrados para este turno.',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: _greyText,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        )
                      else if (incluirTablaIngresosDetallada)
                        _ticketCajaTablaIngresos(ingresosTurno, ajuste: dTicket)
                      else
                        _ticketCajaIngresosResumenCompacto(
                          cantidad: ingresosTurno.length,
                          brutoTotal: efectivoBruto + transferenciaBruta,
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _ticketCajaSeccionTitulo('RETIROS DEL TURNO'),
                      pw.SizedBox(height: 3),
                      if (retirosTurno.isEmpty)
                        pw.Text(
                          'No hubo retiros registrados en este turno.',
                          style: pw.TextStyle(
                            fontSize: 8,
                            color: _greyText,
                            fontStyle: pw.FontStyle.italic,
                          ),
                        )
                      else ...[
                        _ticketCajaRetirosIntro(
                          cantidad: retirosTurno.length,
                          totalRetirado: retirosEfectivo + retirosTransferencia,
                        ),
                        pw.SizedBox(height: 4),
                        _ticketCajaTablaRetiros(retirosTurno, ajuste: dTicket),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (otrosEgresosTurno.isNotEmpty) ...[
              pw.SizedBox(height: 12),
              _ticketCajaSeccionTitulo('OTROS EGRESOS DEL TURNO'),
              pw.SizedBox(height: 2),
              pw.Text(
                'Registros únicos ya contabilizados en Finanzas (no son retiros de caja; no se restan del total neto de arriba).',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontStyle: pw.FontStyle.italic,
                  color: _greyText,
                ),
              ),
              pw.SizedBox(height: 4),
              _ticketCajaTablaOtrosEgresos(otrosEgresosTurno, ajuste: dTicket),
            ],
            if ((anotacionTurno ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              _ticketCajaSeccionTitulo('OBSERVACIONES'),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _greyLight, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  anotacionTurno!.trim(),
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    color: _darkText,
                    lineSpacing: 1.35,
                  ),
                ),
              ),
            ],
            if (guiaCantReposiciones > 0 ||
                guiaCantUsos > 0 ||
                guiaCambioSaldo > 0) ...[
              pw.SizedBox(height: 12),
              _ticketCajaSeccionTitulo('GUÍA DE CAMBIO (DÍA)'),
              pw.SizedBox(height: 2),
              pw.Text(
                'Solo referencia operativa; no forma parte del total neto contable.',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontStyle: pw.FontStyle.italic,
                  color: _greyText,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Saldo: ${guiaCambioSaldo.toCurrency()}  ·  '
                'Reposiciones: $guiaCantReposiciones (+${guiaTotalReposiciones.toCurrency()})  ·  '
                'Usos: $guiaCantUsos (−${guiaTotalUsos.toCurrency()})',
                style: pw.TextStyle(fontSize: 8, color: _darkText),
              ),
            ],
            pw.SizedBox(height: 12),
            _ticketCajaPie(emitidoPor),
          ],
        ),
      ),
    ];

    // El cierre de un día con muchas sesiones se desparramaba en varias hojas.
    // Se compacta hasta que entre en una, y si ni así entra se queda con el
    // nivel que menos páginas usó: seguir apretando solo empeoraría la lectura
    // sin ahorrar papel.
    dTicket = await _ajustarParaPaginas(
      maxPaginas: 1,
      theme: temaTicket,
      construir: (a) {
        dTicket = a;
        return cuerpoTicket();
      },
    );

    pdf.addPage(
      pw.MultiPage(
        maxPages: 10000,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => cuerpoTicket(),
      ),
    );

    final bytes = await pdf.save();
    final safeFecha = diaCorto.replaceAll(RegExp(r'[^0-9]'), '-');
    final fileName = 'Cierre_${turno.slug}_$safeFecha.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  // ── Hoja de cierre de sesión: una A4, mitad resumen y mitad detalle ───────

  /// Un escalón del ajuste del detalle: cuántas columnas, qué nivel de escalera
  /// y hasta dónde se permite achicar la letra.
  ///
  /// Las columnas van **antes** que la letra chica, al revés del orden habitual
  /// de [AjustePdf]. Es deliberado: estas filas son cortas (hora + nombre +
  /// monto), así que dos columnas a tamaño completo se leen mejor que una columna
  /// al 76%. Acá lo que falta es alto, no ancho.
  static List<_PasoDetalleMedios> get _pasosDetalleMedios {
    final e = AjustePdf.escalera;
    return [
      _PasoDetalleMedios(1, e[0], 7),
      _PasoDetalleMedios(1, e[1], 7),
      _PasoDetalleMedios(1, e[2], 7),
      _PasoDetalleMedios(1, e[3], 7),
      _PasoDetalleMedios(2, e[2], 7),
      _PasoDetalleMedios(2, e[3], 7),
      _PasoDetalleMedios(2, e[4], 7),
      _PasoDetalleMedios(2, e[5], 7),
      _PasoDetalleMedios(2, e[6], 7),
      _PasoDetalleMedios(3, e[4], 7),
      _PasoDetalleMedios(3, e[5], 7),
      _PasoDetalleMedios(3, e[6], 7),
      // Último escalón: piso 6 pt. Más abajo no se baja — si ni así entra, lo
      // que cede es el tamaño de la hoja, nunca los datos ni la legibilidad.
      _PasoDetalleMedios(3, e[6], 6),
    ];
  }

  /// Desde qué escalón conviene empezar a medir, según cuántas filas hay.
  ///
  /// Cada medición es un `doc.save()` completo. Arrancar siempre de cero haría 13
  /// documentos para una sesión grande, y el cierre esperaría de más por
  /// impaciencia del código. Se arranca un escalón antes del estimado para no
  /// compactar de gancho.
  static int _pasoInicialDetalle(int filas) {
    final estimado = filas <= 15
        ? 0
        : filas <= 25
        ? 2
        : filas <= 50
        ? 4
        : filas <= 70
        ? 6
        : filas <= 105
        ? 9
        : 12;
    return math.max(0, estimado - 1);
  }

  /// Primer escalón con el que el detalle entra en [objetivo].
  static Future<_PasoDetalleMedios> _ajustarDetalleMedios({
    required double objetivo,
    required int filas,
    required pw.ThemeData? theme,
    required pw.Widget Function(_PasoDetalleMedios) construir,
  }) async {
    final pasos = _pasosDetalleMedios;
    for (var i = _pasoInicialDetalle(filas); i < pasos.length; i++) {
      try {
        final alto = await _medirAlto(
          theme: theme,
          contenido: construir(pasos[i]),
        );
        if (alto <= objetivo + 0.5) return pasos[i];
      } catch (_) {
        return pasos[i];
      }
    }
    return pasos.last;
  }

  /// Hoja de cierre de una sesión: **un solo A4**, resumen y arqueo arriba,
  /// detalle por alumno abajo.
  ///
  /// Dos garantías, en este orden:
  /// 1. **No se pierde ni un dato.** El formato es de alto libre con piso de A4,
  ///    el mismo patrón que los recibos: el contenido no tiene contra qué
  ///    chocar. Con una A4 de alto fijo, lo que no entrara se recortaría en
  ///    silencio.
  /// 2. **Nunca hay hoja 2.** Es una sola [pw.Page]: no existe paginación.
  ///
  /// Y una tercera, la que se cumple siempre en la práctica: la hoja mide
  /// exactamente una A4. Si un caso extremo no lo lograra, cede *esta* —la hoja
  /// se estira y el visor la escala al imprimir— y nunca las dos de arriba.
  static Future<void> generarHojaCierreSesionPdf({
    required SesionCaja sesion,
    required DatosCierreSesion datos,
    required TurnoCaja turno,
    String? emitidoPor,
    String? anotacion,
    double guiaCambioSaldo = 0,
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();
    final tema = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
    final pdf = pw.Document(theme: tema);

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/isotipo-ej.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final abierta = sesion.estaAbierta;
    final diaAr = ArTime.toAr(sesion.abiertaAt);
    final diaCorto = ArTime.formatFechaCorta(diaAr);
    final fechaEmision = ArTime.formatFechaHora(ArTime.nowUtc());

    final cobrosEf = cobrosDeMedio(datos.ingresos, transferencia: false);
    final cobrosTr = cobrosDeMedio(datos.ingresos, transferencia: true);
    final egresosEf = datos.egresos
        .where((e) => !esTransferenciaCaja(e.medioPago))
        .toList();
    final egresosTr = datos.egresos
        .where((e) => esTransferenciaCaja(e.medioPago))
        .toList();

    // El resumen nunca pasa de la mitad: si con el nivel 0 se pasa, se compacta
    // hasta entrar. Así no puede comerse el espacio del detalle.
    pw.Widget resumen(AjustePdf a) => _hojaCierreResumen(
      a,
      logo: logoImage,
      sesion: sesion,
      datos: datos,
      turno: turno,
      diaCorto: diaCorto,
      fechaEmision: fechaEmision,
      anotacion: anotacion,
      guiaCambioSaldo: guiaCambioSaldo,
      abierta: abierta,
    );

    final ajusteSup = await _ajustarParaEntrar(
      objetivo: _mediaA4 - _kAltoDivisorHoja,
      theme: tema,
      construir: resumen,
    );
    final aSup = ajusteSup.ajuste;
    final altoSup = ajusteSup.alto.isFinite
        ? ajusteSup.alto
        : _mediaA4 - _kAltoDivisorHoja;

    // El detalle recibe TODO lo que sobra: la mitad, o más. Un día normal el
    // resumen ocupa menos de su mitad y el detalle se queda con ~55-60%.
    final objetivoInf = PdfPageFormat.a4.height - altoSup - _kAltoDivisorHoja;

    pw.Widget detalle(_PasoDetalleMedios p) => _hojaCierreDetalle(
      p,
      cobrosEfectivo: cobrosEf,
      cobrosTransferencia: cobrosTr,
      egresosEfectivo: egresosEf,
      egresosTransferencia: egresosTr,
      datos: datos,
      emitidoPor: emitidoPor,
    );

    final pInf = await _ajustarDetalleMedios(
      objetivo: objetivoInf,
      filas:
          cobrosEf.length +
          cobrosTr.length +
          egresosEf.length +
          egresosTr.length,
      theme: tema,
      construir: detalle,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(PdfPageFormat.a4.width, double.infinity),
        margin: const pw.EdgeInsets.all(0),
        build: (_) => pw.ConstrainedBox(
          constraints: pw.BoxConstraints(minHeight: PdfPageFormat.a4.height),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [resumen(aSup), _hojaCierreDivisor(), detalle(pInf)],
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    final safeFecha = diaCorto.replaceAll(RegExp(r'[^0-9]'), '-');
    final instanteArchivo = sesion.cerradaAt ?? sesion.abiertaAt;
    final safeHora = ArTime.formatHora(
      instanteArchivo,
    ).replaceAll(RegExp(r'[^0-9]'), '-');
    final safeSesion = sesion.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final sesionCorta = safeSesion.length <= 8
        ? safeSesion
        : safeSesion.substring(0, 8);
    final fileName = abierta
        ? 'Caja_en_curso_${turno.slug}_${safeFecha}_${safeHora}_$sesionCorta.pdf'
        : 'Cierre_sesion_${turno.slug}_${safeFecha}_${safeHora}_$sesionCorta.pdf';

    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  /// Alto reservado para la línea divisoria entre las dos mitades.
  static const double _kAltoDivisorHoja = 14;

  static pw.Widget _hojaCierreDivisor() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 5),
    child: pw.Container(height: 0.7, color: _greyLight),
  );

  /// Mitad de arriba: resumen y arqueo. Deliberadamente **sin** las tablas de
  /// ingresos y retiros del ticket viejo: el detalle es la mitad de abajo, y
  /// repetirlo sería lo que impide que las dos mitades entren en una hoja.
  static pw.Widget _hojaCierreResumen(
    AjustePdf a, {
    pw.ImageProvider? logo,
    required SesionCaja sesion,
    required DatosCierreSesion datos,
    required TurnoCaja turno,
    required String diaCorto,
    required String fechaEmision,
    String? anotacion,
    double guiaCambioSaldo = 0,
    required bool abierta,
  }) {
    final nota = (anotacion ?? '').trim();
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(22, a.sp(14), 22, 0),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _ticketCajaHeaderReciboStyle(logo, turno, diaCorto),
          pw.SizedBox(height: a.sp(8)),
          // Solo cuando la caja sigue abierta: el bloque de abajo ya se titula
          // "CIERRE DE SESIÓN" y repetirlo era decir dos veces lo mismo. Acá lo
          // que hace falta avisar es que este papel NO es el del cierre.
          if (abierta) ...[
            pw.Text(
              'CAJA EN CURSO — no es el cierre',
              style: pw.TextStyle(
                fontSize: a.fs(11),
                fontWeight: pw.FontWeight.bold,
                color: _redAccent,
                letterSpacing: 1.2,
              ),
            ),
            pw.SizedBox(height: a.sp(4)),
          ],
          _ticketCajaFechaTotalNeto(fechaEmision, datos.totalNeto),
          pw.SizedBox(height: a.sp(6)),
          _ticketCajaResumen(
            efectivoBruto: datos.efectivoBruto,
            retirosEfectivo: datos.egresosEfectivo,
            efectivoNeto: datos.efectivoNeto,
            transferenciaBruta: datos.transferenciaBruta,
            retirosTransferencia: datos.egresosTransferencia,
            transferenciaNeta: datos.transferenciaNeta,
          ),
          pw.SizedBox(height: a.sp(6)),
          // El arqueo se compara contra el MISMO neto que muestra el resumen de
          // arriba y que suman las filas de abajo. Es lo que evita que la hoja
          // tenga dos números distintos para la misma plata.
          _ticketCajaBloqueCierreSesion(
            cambioInicial: sesion.cambioInicial,
            efectivoNeto: datos.efectivoNeto,
            arqueo: sesion.arqueoCierre,
            notaCierre: sesion.notaCierre,
            abiertaAt: sesion.abiertaAt,
            cerradaAt: sesion.cerradaAt,
          ),
          if (a.subtextos && (nota.isNotEmpty || guiaCambioSaldo.abs() > 0.001))
            pw.Padding(
              padding: pw.EdgeInsets.only(top: a.sp(6)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (guiaCambioSaldo.abs() > 0.001)
                    _ticketCajaResumenLine(
                      'Guía de cambio (no contable)',
                      guiaCambioSaldo.toCurrency(),
                    ),
                  if (nota.isNotEmpty) ...[
                    _ticketCajaSeccionTitulo('OBSERVACIONES'),
                    pw.Text(
                      nota,
                      style: pw.TextStyle(fontSize: a.fs(8), color: _darkText),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Mitad de abajo: el detalle por alumno, un bloque por medio de pago.
  static pw.Widget _hojaCierreDetalle(
    _PasoDetalleMedios p, {
    required List<CobroAgrupado> cobrosEfectivo,
    required List<CobroAgrupado> cobrosTransferencia,
    required List<Egreso> egresosEfectivo,
    required List<Egreso> egresosTransferencia,
    required DatosCierreSesion datos,
    String? emitidoPor,
  }) {
    final hayMixto =
        cobrosEfectivo.any((c) => c.parteDeMixto) ||
        cobrosTransferencia.any((c) => c.parteDeMixto);
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(22, 0, 22, p.ajuste.sp(12)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _hojaCierreBloqueMedio(
            p,
            titulo: 'EFECTIVO',
            color: _greenAccent,
            cobros: cobrosEfectivo,
            egresos: egresosEfectivo,
            neto: datos.efectivoNeto,
          ),
          pw.SizedBox(height: p.ajuste.sp(8)),
          _hojaCierreBloqueMedio(
            p,
            titulo: 'TRANSFERENCIA',
            color: _transferenciaColorPdf,
            cobros: cobrosTransferencia,
            egresos: egresosTransferencia,
            neto: datos.transferenciaNeta,
          ),
          if (hayMixto)
            pw.Padding(
              padding: pw.EdgeInsets.only(top: p.ajuste.sp(4)),
              child: pw.Text(
                '* parte de un cobro mixto',
                style: pw.TextStyle(
                  fontSize: p.ajuste.fs(7, piso: 6),
                  color: _greyText,
                ),
              ),
            ),
          pw.SizedBox(height: p.ajuste.sp(6)),
          _ticketCajaPie(emitidoPor),
          pw.SizedBox(height: 3),
          // No es decorativo: todos los demás papeles de esta app son de media
          // A4 para cortar dos por hoja, así que el reflejo aprendido es cortar
          // — y el corte caería justo en la línea divisoria, partiendo el arqueo
          // del detalle. Esta línea no se compacta en ningún escalón.
          pw.Center(
            child: pw.Text(
              'HOJA A4 COMPLETA · NO CORTAR',
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: _greyText,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _hojaCierreBloqueMedio(
    _PasoDetalleMedios p, {
    required String titulo,
    required PdfColor color,
    required List<CobroAgrupado> cobros,
    required List<Egreso> egresos,
    required double neto,
  }) {
    final a = p.ajuste;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: a.fs(9, piso: p.piso),
                fontWeight: pw.FontWeight.bold,
                color: color,
                letterSpacing: 1,
              ),
            ),
            pw.Text(
              'NETO ${neto.toCurrency()}',
              style: pw.TextStyle(
                fontSize: a.fs(9, piso: p.piso),
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: a.sp(3)),
        if (cobros.isEmpty)
          pw.Text(
            'Sin ingresos en este bucket.',
            style: pw.TextStyle(
              fontSize: a.fs(8, piso: p.piso),
              color: _greyText,
            ),
          )
        else
          _hojaCierreColumnas(
            p,
            filas: cobros.map((c) => _hojaCierreFilaCobro(p, c)).toList(),
          ),
        pw.SizedBox(height: a.sp(3)),
        if (egresos.isEmpty)
          pw.Text(
            'Sin egresos en este bucket.',
            style: pw.TextStyle(
              fontSize: a.fs(8, piso: p.piso),
              color: _greyText,
            ),
          )
        else
          _hojaCierreColumnas(
            p,
            filas: egresos.map((e) => _hojaCierreFilaEgreso(p, e)).toList(),
          ),
      ],
    );
  }

  /// Reparte las filas en 1, 2 o 3 columnas.
  static pw.Widget _hojaCierreColumnas(
    _PasoDetalleMedios p, {
    required List<pw.Widget> filas,
  }) {
    if (p.columnas <= 1) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: filas,
      );
    }
    final porColumna = (filas.length / p.columnas).ceil();
    final columnas = <pw.Widget>[];
    for (var c = 0; c < p.columnas; c++) {
      final desde = c * porColumna;
      if (desde >= filas.length) {
        columnas.add(pw.Expanded(child: pw.SizedBox()));
        continue;
      }
      final hasta = math.min(desde + porColumna, filas.length);
      columnas.add(
        pw.Expanded(
          child: pw.Padding(
            padding: pw.EdgeInsets.only(right: c == p.columnas - 1 ? 0 : 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: filas.sublist(desde, hasta),
            ),
          ),
        ),
      );
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: columnas,
    );
  }

  static pw.Widget _hojaCierreFilaCobro(_PasoDetalleMedios p, CobroAgrupado c) {
    final a = p.ajuste;
    // El nombre es lo único que se abrevia, y solo cuando hay más de una
    // columna. Hora y monto no se tocan en ningún escalón: son los dos datos con
    // los que se cotea la plata.
    final maxNombre = p.columnas >= 3
        ? 20
        : p.columnas == 2
        ? 28
        : 44;
    final nombre = _pdfCierreTrunc(c.alumno, maxNombre);
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: a.sp(3)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  '${ArTime.formatHora(c.fecha)}  $nombre'
                  '${c.parteDeMixto ? ' *' : ''}',
                  style: pw.TextStyle(
                    fontSize: a.fs(8, piso: p.piso),
                    fontWeight: pw.FontWeight.bold,
                    color: _darkText,
                  ),
                  maxLines: 1,
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Text(
                c.monto.toCurrency(),
                style: pw.TextStyle(
                  fontSize: a.fs(8, piso: p.piso),
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                ),
              ),
            ],
          ),
          if (a.subtextos)
            pw.Text(
              c.resumenConceptos,
              style: pw.TextStyle(
                fontSize: a.fs(7, piso: p.piso),
                color: _greyText,
              ),
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  static pw.Widget _hojaCierreFilaEgreso(_PasoDetalleMedios p, Egreso e) {
    final a = p.ajuste;
    final maxNombre = p.columnas >= 3
        ? 18
        : p.columnas == 2
        ? 26
        : 42;
    final hora = e.fecha != null ? ArTime.formatHora(e.fecha!) : '—';
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: a.sp(3)),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '$hora  ${_pdfCierreTrunc(e.proveedorVisible ?? 'Egreso', maxNombre)}',
              style: pw.TextStyle(
                fontSize: a.fs(8, piso: p.piso),
                color: _redAccent,
              ),
              maxLines: 1,
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            '− ${e.monto.toCurrency()}',
            style: pw.TextStyle(
              fontSize: a.fs(8, piso: p.piso),
              fontWeight: pw.FontWeight.bold,
              color: _redAccent,
            ),
          ),
        ],
      ),
    );
  }

  /// Encabezado alineado al recibo de pago: datos fiscales + logo a la izquierda, título del documento a la derecha.
  static pw.Widget _ticketCajaHeaderReciboStyle(
    pw.ImageProvider? logo,
    TurnoCaja turno,
    String diaCorto,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null)
                    pw.Container(
                      height: 30,
                      margin: const pw.EdgeInsets.only(right: 12),
                      child: pw.Image(logo),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Victor Adrián Argüello',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: _darkText,
                        ),
                      ),
                      pw.Text(
                        'Dueño, Junior Eventos',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                      pw.Text(
                        'CUIT 23-32837670-9',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                      pw.Text(
                        'Responsable Inscripto',
                        style: pw.TextStyle(fontSize: 8, color: _greyText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'CIERRE DE CAJA',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _darkText,
                  ),
                ),
                pw.Text(
                  'TURNO ${turno.label}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _greyText,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.Text(
                  'Día $diaCorto',
                  style: pw.TextStyle(fontSize: 8, color: _greyText),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 0.5, color: _greyLight),
      ],
    );
  }

  /// Misma lógica que la fila Fecha + recuadro VALOR del recibo de pago.
  static pw.Widget _ticketCajaFechaTotalNeto(
    String fechaEmision,
    double totalNeto,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            'Fecha: $fechaEmision',
            style: const pw.TextStyle(fontSize: 10, color: _darkText),
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: const pw.BoxDecoration(color: _greyLight),
          child: pw.Text(
            'TOTAL NETO: ${totalNeto.toCurrency()}',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: _darkText,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _ticketCajaSeccionTitulo(String titulo) {
    final t = titulo.endsWith(':') ? titulo : '$titulo:';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(
        t.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: _greyText,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  /// Línea tipo `clave..........valor` con tipografía mono para cuadre visual.
  static pw.Widget _ticketCajaResumenLine(
    String label,
    String valor, {
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color ?? _darkText,
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color ?? _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _ticketCajaResumen({
    required double efectivoBruto,
    required double retirosEfectivo,
    required double efectivoNeto,
    required double transferenciaBruta,
    required double retirosTransferencia,
    required double transferenciaNeta,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'RESUMEN POR MEDIO DE PAGO',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: _greyText,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 4),
          _ticketCajaResumenLine(
            'EFECTIVO',
            '',
            bold: true,
            color: _greenAccent,
          ),
          _ticketCajaResumenLine('  Bruto', efectivoBruto.toCurrency()),
          _ticketCajaResumenLine(
            '  Retirado',
            '− ${retirosEfectivo.toCurrency()}',
            color: _redAccent,
          ),
          _ticketCajaResumenLine(
            '  Neto',
            efectivoNeto.toCurrency(),
            bold: true,
          ),
          pw.SizedBox(height: 3),
          _ticketCajaResumenLine(
            'TRANSFERENCIA',
            '',
            bold: true,
            color: _transferenciaColorPdf,
          ),
          _ticketCajaResumenLine('  Bruto', transferenciaBruta.toCurrency()),
          _ticketCajaResumenLine(
            '  Retirado',
            '− ${retirosTransferencia.toCurrency()}',
            color: _redAccent,
          ),
          _ticketCajaResumenLine(
            '  Neto',
            transferenciaNeta.toCurrency(),
            bold: true,
          ),
        ],
      ),
    );
  }

  /// Resumen corto de ingresos (sin tabla línea a línea).
  static pw.Widget _ticketCajaIngresosResumenCompacto({
    required int cantidad,
    required double brutoTotal,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Resumen (detalle por medio arriba)',
            style: pw.TextStyle(
              fontSize: 8,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.SizedBox(height: 4),
          _ticketCajaResumenLine('Ingresos registrados', '$cantidad'),
          _ticketCajaResumenLine(
            'Total bruto del turno',
            brutoTotal.toCurrency(),
            bold: true,
          ),
        ],
      ),
    );
  }

  /// Línea previa a la tabla de retiros cuando hay movimientos.
  static pw.Widget _ticketCajaRetirosIntro({
    required int cantidad,
    required double totalRetirado,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFFF5F5),
        border: pw.Border.all(color: _redAccent, width: 0.35),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Hay retiros en este turno',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _redAccent,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '$cantidad retiro(s) · Total retirado: ${totalRetirado.toCurrency()}',
            style: const pw.TextStyle(fontSize: 8, color: _darkText),
          ),
        ],
      ),
    );
  }

  static pw.Widget _ticketCajaTablaIngresos(
    List<IngresoDetallado> rows, {
    AjustePdf ajuste = AjustePdf.intacto,
  }) {
    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: ajuste.sp(3)),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: ajuste.fs(7.5, piso: 6.5),
            fontWeight: header ? pw.FontWeight.bold : null,
            color: color ?? _darkText,
          ),
        ),
      );
    }

    final filas = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          cell('Hora', header: true),
          cell('Concepto', header: true),
          cell('Medio', header: true),
          cell('Monto', header: true, align: pw.TextAlign.right),
        ],
      ),
      ...rows.map((i) {
        final hora = ArTime.formatHora(i.fecha).replaceAll(' hs', '');
        return pw.TableRow(
          children: [
            cell(hora),
            cell(_pdfCierreTrunc(i.concepto, 22)),
            cell(_pdfCierreTrunc(i.medioPago, 12)),
            cell(i.monto.toCurrency(), align: pw.TextAlign.right),
          ],
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.3),
      columnWidths: const {
        0: pw.FixedColumnWidth(34),
        1: pw.FlexColumnWidth(2),
        2: pw.FixedColumnWidth(44),
        3: pw.FixedColumnWidth(58),
      },
      children: filas,
    );
  }

  static pw.Widget _ticketCajaTablaRetiros(
    List<Egreso> rows, {
    AjustePdf ajuste = AjustePdf.intacto,
  }) {
    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: ajuste.sp(3)),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: ajuste.fs(7.5, piso: 6.5),
            fontWeight: header ? pw.FontWeight.bold : null,
            color: color ?? _darkText,
          ),
        ),
      );
    }

    final filas = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          cell('Hora', header: true),
          cell('Concepto', header: true),
          cell('Medio', header: true),
          cell('Monto', header: true, align: pw.TextAlign.right),
        ],
      ),
      ...rows.map((e) {
        final hora = e.fecha != null
            ? ArTime.formatHora(e.fecha!).replaceAll(' hs', '')
            : '—';
        return pw.TableRow(
          children: [
            cell(hora, color: _redAccent),
            cell(_pdfCierreTrunc(e.proveedorVisible, 22), color: _redAccent),
            cell(_pdfCierreTrunc(e.medioPago, 12), color: _redAccent),
            cell(
              '−${e.monto.toCurrency()}',
              align: pw.TextAlign.right,
              color: _redAccent,
            ),
          ],
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.3),
      columnWidths: const {
        0: pw.FixedColumnWidth(34),
        1: pw.FlexColumnWidth(2),
        2: pw.FixedColumnWidth(44),
        3: pw.FixedColumnWidth(58),
      },
      children: filas,
    );
  }

  /// Egresos del turno que no son «Retiro de caja» (p. ej. personal). Misma fila en SQLite/Finanzas.
  static pw.Widget _ticketCajaTablaOtrosEgresos(
    List<Egreso> rows, {
    AjustePdf ajuste = AjustePdf.intacto,
  }) {
    const catColor = PdfColor(0.45, 0.35, 0.15);
    const montoColor = PdfColor(0.79, 0.44, 0.12);

    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: ajuste.sp(3)),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: ajuste.fs(7.5, piso: 6.5),
            fontWeight: header ? pw.FontWeight.bold : null,
            color: color ?? _darkText,
          ),
        ),
      );
    }

    final filas = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          cell('Hora', header: true),
          cell('Concepto', header: true),
          cell('Cat.', header: true),
          cell('Medio', header: true),
          cell('Monto', header: true, align: pw.TextAlign.right),
        ],
      ),
      ...rows.map((e) {
        final hora = e.fecha != null
            ? ArTime.formatHora(e.fecha!).replaceAll(' hs', '')
            : '—';
        return pw.TableRow(
          children: [
            cell(hora),
            cell(_pdfCierreTrunc(e.proveedorVisible, 28)),
            cell(_pdfCierreTrunc(e.categoria, 12), color: catColor),
            cell(_pdfCierreTrunc(e.medioPago, 12)),
            cell(
              '−${e.monto.toCurrency()}',
              align: pw.TextAlign.right,
              color: montoColor,
            ),
          ],
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.3),
      columnWidths: const {
        0: pw.FixedColumnWidth(34),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FixedColumnWidth(44),
        3: pw.FixedColumnWidth(46),
        4: pw.FixedColumnWidth(52),
      },
      children: filas,
    );
  }

  /// Bloque de cierre de una sesión: cambio inicial, efectivo esperado en el
  /// cajón, arqueo declarado por el operador y diferencia (sobrante/faltante).
  static pw.Widget _ticketCajaBloqueCierreSesion({
    required double cambioInicial,
    required double efectivoNeto,
    double? arqueo,
    String? notaCierre,
    DateTime? abiertaAt,
    DateTime? cerradaAt,
  }) {
    final esperado = cambioInicial + efectivoNeto;
    final diferencia = arqueo == null ? null : arqueo - esperado;

    pw.Widget linea(
      String label,
      String valor, {
      PdfColor? color,
      bool bold = false,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: _greyText)),
            pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 8,
                color: color ?? _darkText,
                fontWeight: bold ? pw.FontWeight.bold : null,
              ),
            ),
          ],
        ),
      );
    }

    final rango = [
      if (abiertaAt != null) 'Apertura ${ArTime.formatHora(abiertaAt)}',
      cerradaAt != null
          ? 'cierre ${ArTime.formatHora(cerradaAt)}'
          : 'sesión aún abierta',
    ].join(' · ');

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _greyLight, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _ticketCajaSeccionTitulo('CIERRE DE SESIÓN'),
          pw.SizedBox(height: 2),
          pw.Text(rango, style: pw.TextStyle(fontSize: 7.5, color: _greyText)),
          pw.SizedBox(height: 5),
          linea('Cambio inicial', cambioInicial.toCurrency()),
          linea(
            'Efectivo esperado en caja (cambio + efectivo neto)',
            esperado.toCurrency(),
            bold: true,
          ),
          if (arqueo == null)
            linea(
              'Arqueo declarado',
              cerradaAt == null ? 'pendiente (sesión abierta)' : 'sin arqueo',
            )
          else ...[
            linea('Arqueo declarado', arqueo.toCurrency(), bold: true),
            linea(
              diferencia! >= 0.01
                  ? 'Diferencia (sobrante)'
                  : diferencia <= -0.01
                  ? 'Diferencia (faltante)'
                  : 'Diferencia',
              diferencia.toCurrency(),
              color: diferencia.abs() < 0.01
                  ? _greenAccent
                  : diferencia > 0
                  ? _greenAccent
                  : _redAccent,
              bold: true,
            ),
          ],
          if ((notaCierre ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Nota de cierre: ${notaCierre!.trim()}',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontStyle: pw.FontStyle.italic,
                color: _greyText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Desglose del día por sesión/operario: cuánto cobró cada uno y cómo
  /// cerró su arqueo.
  static pw.Widget _ticketCajaTablaResumenSesiones(
    List<ResumenSesionPdf> rows, {
    AjustePdf ajuste = AjustePdf.intacto,
  }) {
    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
      bool bold = false,
    }) {
      return pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: ajuste.sp(3)),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: ajuste.fs(7.5, piso: 6.5),
            fontWeight: header || bold ? pw.FontWeight.bold : null,
            color: color ?? _darkText,
          ),
        ),
      );
    }

    String difTexto(ResumenSesionPdf r) {
      final d = r.diferencia;
      if (d == null) {
        if (r.horaCierre == null) return 'abierta';
        // Distingue al que se fue sin cerrar del que cerró y no declaró arqueo:
        // es el dato por el que el jefe mira esta tabla.
        return r.cierreAutomatico ? 'auto s/arq' : 's/arqueo';
      }
      if (d.abs() < 0.01) return 'OK';
      return d.toCurrency();
    }

    PdfColor? difColor(ResumenSesionPdf r) {
      final d = r.diferencia;
      if (d == null) return _greyText;
      if (d.abs() < 0.01 || d > 0) return _greenAccent;
      return _redAccent;
    }

    final totalEfectivo = rows.fold<double>(0, (s, r) => s + r.efectivo);
    final totalTransfer = rows.fold<double>(0, (s, r) => s + r.transferencia);

    final filas = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          cell('Operario', header: true),
          cell('Turno', header: true),
          cell('Horario', header: true),
          cell('Efectivo', header: true, align: pw.TextAlign.right),
          cell('Transf.', header: true, align: pw.TextAlign.right),
          cell('Total', header: true, align: pw.TextAlign.right),
          cell('Arqueo', header: true, align: pw.TextAlign.right),
          cell('Dif.', header: true, align: pw.TextAlign.right),
        ],
      ),
      ...rows.map(
        (r) => pw.TableRow(
          children: [
            cell(_pdfCierreTrunc(r.operador, 16)),
            cell(_pdfCierreTrunc(r.etiqueta, 10)),
            cell(
              '${r.horaApertura.replaceAll(' hs', '')}–'
              '${r.horaCierre?.replaceAll(' hs', '') ?? '…'}',
            ),
            cell(r.efectivo.toCurrency(), align: pw.TextAlign.right),
            cell(r.transferencia.toCurrency(), align: pw.TextAlign.right),
            cell(r.total.toCurrency(), align: pw.TextAlign.right, bold: true),
            cell(r.arqueo?.toCurrency() ?? '—', align: pw.TextAlign.right),
            cell(difTexto(r), align: pw.TextAlign.right, color: difColor(r)),
          ],
        ),
      ),
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _headerBg),
        children: [
          cell('TOTAL DÍA', header: true),
          cell(''),
          cell(''),
          cell(
            totalEfectivo.toCurrency(),
            header: true,
            align: pw.TextAlign.right,
          ),
          cell(
            totalTransfer.toCurrency(),
            header: true,
            align: pw.TextAlign.right,
          ),
          cell(
            (totalEfectivo + totalTransfer).toCurrency(),
            header: true,
            align: pw.TextAlign.right,
          ),
          cell(''),
          cell(''),
        ],
      ),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.3),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.6),
        1: pw.FixedColumnWidth(40),
        2: pw.FixedColumnWidth(58),
        3: pw.FixedColumnWidth(52),
        4: pw.FixedColumnWidth(52),
        5: pw.FixedColumnWidth(56),
        6: pw.FixedColumnWidth(52),
        7: pw.FixedColumnWidth(46),
      },
      children: filas,
    );
  }

  static pw.Widget _ticketCajaPie(String? emitidoPor) {
    final firma = (emitidoPor ?? '').trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 0.5, color: _greyLight),
        pw.SizedBox(height: 4),
        pw.Text(
          'Emitido por: ${firma.isEmpty ? '—' : firma}',
          style: pw.TextStyle(fontSize: 8, color: _greyText),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Junior Eventos · Documento operativo de cierre de caja.',
          style: pw.TextStyle(
            fontSize: 7,
            color: _greyText,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  static String _pdfCierreTrunc(String? s, int max) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return '—';
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  static pw.Widget _pwGraficoBarrasIngEgr(double ing, double egr) {
    final maxV = math.max(math.max(ing, egr), 1.0);
    const maxH = 80.0;
    final hIng = (ing / maxV) * maxH;
    final hEgr = (egr / maxV) * maxH;
    pw.Widget barra(double h, PdfColor color) {
      return pw.Container(
        width: 44,
        height: maxH,
        alignment: pw.Alignment.bottomCenter,
        child: pw.Container(
          width: 36,
          height: h.clamp(0.0, maxH),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: const pw.BorderRadius.vertical(
              top: pw.Radius.circular(4),
            ),
          ),
        ),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            barra(hIng, _greenAccent),
            pw.SizedBox(height: 6),
            pw.Text(
              'Ingresos',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
            pw.Text(
              ing.toCurrency(),
              style: pw.TextStyle(fontSize: 8, color: _darkText),
            ),
          ],
        ),
        pw.SizedBox(width: 28),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            barra(hEgr, _redAccent),
            pw.SizedBox(height: 6),
            pw.Text(
              'Egresos',
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
            pw.Text(
              egr.toCurrency(),
              style: pw.TextStyle(fontSize: 8, color: _darkText),
            ),
          ],
        ),
      ],
    );
  }

  static final PdfColor _transferenciaColorPdf = PdfColor.fromInt(0xFF3498DB);

  static pw.Widget _pwBarraMediosIngresos(
    double efectivo,
    double transferencia,
  ) {
    final t = efectivo + transferencia;
    if (t <= 0.0001) {
      return pw.Text('—', style: pw.TextStyle(fontSize: 9, color: _greyText));
    }
    final flexE = efectivo > 0 ? math.max(1, (efectivo / t * 1000).round()) : 0;
    final flexT = transferencia > 0
        ? math.max(1, (transferencia / t * 1000).round())
        : 0;
    final rowChildren = <pw.Widget>[];
    if (flexE > 0) {
      rowChildren.add(
        pw.Expanded(
          flex: flexE,
          child: pw.Container(height: 14, color: _greenAccent),
        ),
      );
    }
    if (flexT > 0) {
      rowChildren.add(
        pw.Expanded(
          flex: flexT,
          child: pw.Container(height: 14, color: _transferenciaColorPdf),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 220, child: pw.Row(children: rowChildren)),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Container(width: 10, height: 10, color: _greenAccent),
            pw.SizedBox(width: 6),
            pw.Text(
              'Efectivo / no transferencia: ${efectivo.toCurrency()}',
              style: const pw.TextStyle(fontSize: 8, color: _darkText),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Row(
          children: [
            pw.Container(width: 10, height: 10, color: _transferenciaColorPdf),
            pw.SizedBox(width: 6),
            pw.Text(
              'Transferencia: ${transferencia.toCurrency()}',
              style: const pw.TextStyle(fontSize: 8, color: _darkText),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _pwTablaIngresosCierre(List<IngresoDetallado> rows) {
    pw.Widget cell(String text, {bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 8 : 7.5,
            fontWeight: header ? pw.FontWeight.bold : null,
            color: _darkText,
          ),
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _cardBg),
        children: [
          cell('Hora (AR)', header: true),
          cell('Concepto', header: true),
          cell('Cliente / alumno', header: true),
          cell('Fuente', header: true),
          cell('Medio', header: true),
          cell('Monto', header: true),
        ],
      ),
      ...rows.map((i) {
        final hora = ArTime.formatFechaHora(i.fecha);
        return pw.TableRow(
          children: [
            cell(hora),
            cell(_pdfCierreTrunc(i.concepto, 42)),
            cell(_pdfCierreTrunc(i.alumnoOCliente, 28)),
            cell(_pdfCierreTrunc(i.fuente, 14)),
            cell(_pdfCierreTrunc(i.medioPago, 14)),
            cell(i.monto.toCurrency()),
          ],
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.4),
      columnWidths: {
        0: const pw.FixedColumnWidth(78),
        1: const pw.FlexColumnWidth(1.6),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FixedColumnWidth(52),
        4: const pw.FixedColumnWidth(52),
        5: const pw.FixedColumnWidth(62),
      },
      children: tableRows,
    );
  }

  static pw.Widget _pwTablaEgresosCierre(List<Egreso> rows) {
    pw.Widget cell(String text, {bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 8 : 7.5,
            fontWeight: header ? pw.FontWeight.bold : null,
            color: _darkText,
          ),
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _cardBg),
        children: [
          cell('Fecha / hora (AR)', header: true),
          cell('Proveedor / concepto', header: true),
          cell('Categoría', header: true),
          cell('Medio', header: true),
          cell('Monto', header: true),
        ],
      ),
      ...rows.map((e) {
        final when = e.fecha != null ? ArTime.formatFechaHora(e.fecha!) : '—';
        return pw.TableRow(
          children: [
            cell(when),
            cell(_pdfCierreTrunc(e.proveedorVisible, 48)),
            cell(_pdfCierreTrunc(e.categoria, 22)),
            cell(_pdfCierreTrunc(e.medioPago, 16)),
            cell(e.monto.toCurrency()),
          ],
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.4),
      columnWidths: {
        0: const pw.FixedColumnWidth(78),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FixedColumnWidth(48),
        4: const pw.FixedColumnWidth(58),
      },
      children: tableRows,
    );
  }

  static String _estadoRentabilidadPdfLabel(EstadoRentabilidad e) {
    switch (e) {
      case EstadoRentabilidad.saludable:
        return 'Saludable (margen alto)';
      case EstadoRentabilidad.ajustado:
        return 'Ajustado';
      case EstadoRentabilidad.equilibrio:
        return 'Punto de equilibrio';
      case EstadoRentabilidad.perdida:
        return 'Pérdida';
    }
  }

  static pw.Widget _filaRentabilidadPdf(
    String label,
    String valor, {
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : null,
                color: _darkText,
              ),
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color ?? _darkText,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtPctRentPdf(double p) {
    final x = p.clamp(0.0, 100.0);
    return x == x.roundToDouble()
        ? x.round().toString()
        : x.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// Un bloque legible por cada descuento guardado: modo, valor nominal, importe, detalle.
  static pw.Widget _pwBloqueRegistroDescuento(RegistroDescuentoRent r) {
    final esPct = r.modoAjuste == 'porcentaje';
    final tipo = esPct ? 'Porcentaje' : 'Pesos';
    final nominal = esPct
        ? '${_fmtPctRentPdf(r.sacarPorcentaje)} % sobre el saldo en ese momento'
        : '${r.sacarPesos.toCurrency()} descontados del saldo en ese momento';
    final det = r.detalle.trim();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6, left: 4),
      padding: const pw.EdgeInsets.only(left: 8, top: 4, bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: _gold, width: 1.2)),
        color: _cardBg,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Tipo de ajuste: $tipo',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            nominal,
            style: pw.TextStyle(fontSize: 8.5, color: _darkText, height: 1.25),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Importe descontado: − ${r.montoDescontado.toCurrency()}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
          if (det.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Detalle / motivo: $det',
              style: pw.TextStyle(
                fontSize: 8,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _pwBloqueAjustePendiente(CostoItem c) {
    final esPct = c.modoAjuste == 'porcentaje';
    final tipo = esPct ? 'Porcentaje' : 'Pesos';
    final nominal = esPct
        ? '${_fmtPctRentPdf(c.sacarPorcentaje)} % sobre el saldo restante actual'
        : '${c.sacarPesos.toCurrency()} a descontar en pesos del saldo actual';
    final det = c.detalleAjuste.trim();
    final m = c.montoDescuentoPendiente;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6, left: 4),
      padding: const pw.EdgeInsets.only(left: 8, top: 4, bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColor.fromInt(0xFFF39C12), width: 1),
        ),
        color: _headerBg,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Ajuste pendiente (no pulsaste «Guardar ajuste y seguir»)',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFB8860B),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Tipo: $tipo · $nominal',
            style: pw.TextStyle(fontSize: 8.5, color: _darkText, height: 1.25),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            'Efecto estimado: − ${m.toCurrency()}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _darkText,
            ),
          ),
          if (det.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              'Detalle / motivo: $det',
              style: pw.TextStyle(
                fontSize: 8,
                color: _greyText,
                fontStyle: pw.FontStyle.italic,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _bloqueCostoRentabilidadPdf(CostoItem c) {
    final children = <pw.Widget>[
      pw.Text(
        c.concepto,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
        ),
      ),
      _filaRentabilidadPdf('  Base referencia', c.montoBase.toCurrency()),
    ];
    if (c.registrosDescuento.isNotEmpty) {
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
          child: pw.Text(
            '  Descuentos aplicados (guardados)',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: _greyText,
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }
    for (final r in c.registrosDescuento) {
      children.add(_pwBloqueRegistroDescuento(r));
    }
    if (c.montoDescuentoPendiente > 0.005) {
      children.add(_pwBloqueAjustePendiente(c));
    }
    if (c.montoDescuento > 0.005) {
      children.add(
        _filaRentabilidadPdf(
          '  Descuento total (importe)',
          '− ${c.montoDescuento.toCurrency()}',
        ),
      );
    }
    children.add(
      _filaRentabilidadPdf(
        '  Neto (costo al cálculo)',
        c.montoEfectivo.toCurrency(),
        bold: true,
      ),
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // ── Entrega de PDF en Windows: menú o visor directo ───────────────────────
  static Future<void> _entregarPdfEnWindows(
    Uint8List bytes,
    String filename, {
    BuildContext? context,
  }) async {
    if (context != null) {
      await _mostrarMenuPdfWindows(context, bytes, filename);
      return;
    }
    await _verPdfEnWindows(bytes, filename);
  }

  static Future<String> _carpetaPdfDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}Junior Eventos${Platform.pathSeparator}PDFs',
    );
    await dir.create(recursive: true);
    return dir.path;
  }

  static Future<String> _guardarPdfEnDefault(
    Uint8List bytes,
    String filename,
  ) async {
    final dir = await _carpetaPdfDefault();
    final file = File('$dir${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes);
    _ultimaRutaPdfGuardado = file.path;
    debugPrint('PDF guardado: ${file.path}');
    return file.path;
  }

  static Future<void> _verPdfEnWindows(Uint8List bytes, String filename) async {
    try {
      final path = await _guardarPdfEnDefault(bytes, filename);
      await Process.run('cmd', ['/c', 'start', '', path]);
    } catch (e) {
      debugPrint('Error al abrir PDF en Windows: $e');
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    }
  }

  static Future<void> _abrirCarpetaPdf(String path) async {
    await Process.run('explorer', ['/select,$path']);
  }

  static Future<void> _guardarPdfComo(
    BuildContext context,
    Uint8List bytes,
    String filename,
  ) async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '¿Dónde guardar el PDF?',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputFile == null) return;

    if (!outputFile.toLowerCase().endsWith('.pdf')) {
      outputFile = '$outputFile.pdf';
    }

    final file = File(outputFile);
    await file.writeAsBytes(bytes);
    _ultimaRutaPdfGuardado = file.path;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF guardado: ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Future<void> _mostrarMenuPdfWindows(
    BuildContext context,
    Uint8List bytes,
    String filename,
  ) async {
    const gold = Color(0xFFD4AF37);

    final accion = await showModalBottomSheet<_PdfMenuAccion>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final carpetaHint = _ultimaRutaPdfGuardado != null
            ? _ultimaRutaPdfGuardado!.replaceAll('/', '\\')
            : 'Documents\\Junior Eventos\\PDFs';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'EXPORTAR PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  filename,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.visibility_outlined, color: gold),
                  title: const Text(
                    'VER PDF',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Abre el documento en el visor',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(ctx, _PdfMenuAccion.ver),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined, color: gold),
                  title: const Text(
                    'GUARDAR COMO...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Elegir carpeta y nombre del archivo',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(ctx, _PdfMenuAccion.guardarComo),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined, color: gold),
                  title: const Text(
                    'ABRIR CARPETA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    carpetaHint,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(ctx, _PdfMenuAccion.abrirCarpeta),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (accion == null) return;

    switch (accion) {
      case _PdfMenuAccion.ver:
        await _verPdfEnWindows(bytes, filename);
      case _PdfMenuAccion.guardarComo:
        await _guardarPdfComo(context, bytes, filename);
      case _PdfMenuAccion.abrirCarpeta:
        final path =
            _ultimaRutaPdfGuardado ??
            await _guardarPdfEnDefault(bytes, filename);
        await _abrirCarpetaPdf(path);
    }
  }

  // ── Constructor del documento ──────────────────────────────────────────────
  static Future<pw.Document> _buildDocument({
    required Evento evento,
    required double saldoActual,
    required List<Transaccion> transacciones,
    required List<EventosServicios> servicios,
    required String titulo,
    String? transaccionDestacadaId,
  }) async {
    // Cargar fuente TrueType con soporte Unicode completo (elimina warnings de Helvetica)
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();
    final fontItalic = await PdfGoogleFonts.outfitLight();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
      ),
    );

    pw.ImageProvider? logoImage;
    try {
      final logoData = await rootBundle.load('assets/icons/2.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error al cargar logo para PDF: $e');
    }

    final totalPresupuesto = servicios.fold<double>(
      0,
      (s, i) => s + (i.precioFinalAcordado * i.cantidad),
    );
    final transActivas = transacciones.where((t) => !t.esAnulada).toList();
    final totalPagado = transActivas.fold<double>(0, (s, i) => s + i.monto);
    final totalBonificaciones = transActivas
        .where((t) => t.esBonificacion)
        .fold<double>(0, (s, t) => s + t.monto);

    // Ordenar transacciones: más reciente primero
    final transOrdenadas = List<Transaccion>.from(transActivas)
      ..sort((a, b) {
        final fa = a.fechaPago ?? DateTime(2000);
        final fb = b.fechaPago ?? DateTime(2000);
        return fb.compareTo(fa);
      });

    // Si se especifica una transacción, destacar esa; si no, la más reciente
    Transaccion? pagoDestacado;
    String etiquetaPago = 'ÚLTIMO PAGO REGISTRADO';
    if (transaccionDestacadaId != null) {
      pagoDestacado = transOrdenadas.cast<Transaccion?>().firstWhere(
        (t) => t!.id == transaccionDestacadaId,
        orElse: () => null,
      );
      if (pagoDestacado != null) etiquetaPago = 'PAGO SELECCIONADO';
    }
    pagoDestacado ??= transOrdenadas.isNotEmpty ? transOrdenadas.first : null;

    // Sello temporal estricto en huso America/Argentina/Buenos_Aires (GMT-3).
    final now = ArTime.nowUtc();
    final fechaEmision = ArTime.formatFechaHora(now);
    final fechaEvento = ArTime.formatFechaCorta(evento.fechaEvento);
    final operacionGestionadaStr = ArTime.operacionGestionada(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => [
          // ── Página completa ──────────────────────────────────────────────
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header oscuro ──────────────────────────────────────────
              _buildHeader(
                logoImage,
                titulo,
                fechaEmision,
                evento,
                fechaEvento,
              ),

              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Sello temporal estricto — blindaje legal/administrativo.
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      margin: const pw.EdgeInsets.only(bottom: 10),
                      decoration: pw.BoxDecoration(
                        color: _cardBg,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(6),
                        ),
                        border: pw.Border.all(color: _greyLight, width: 0.5),
                      ),
                      child: pw.Text(
                        operacionGestionadaStr,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ),
                    // ── ESTADO DE CUENTA (Unificado) ──────────────────────
                    _buildEstadoCuenta(
                      pagado: totalPagado,
                      totalBonificaciones: totalBonificaciones,
                      saldo: saldoActual,
                      fechaEvento: evento.fechaEvento,
                      ultimoPago: pagoDestacado,
                      etiquetaPago: etiquetaPago,
                    ),
                    pw.SizedBox(height: 24),

                    // ── Historial de pagos ───────────────────────────────
                    if (transOrdenadas.isNotEmpty) ...[
                      _buildSectionTitle('HISTORIAL DE PAGOS'),
                      pw.SizedBox(height: 8),
                      _buildPagosTable(transOrdenadas),
                      pw.SizedBox(height: 24),
                    ],

                    // ── Detalle de servicios ─────────────────────────────
                    if (servicios.isNotEmpty) ...[
                      _buildSectionTitle('SERVICIOS CONTRATADOS'),
                      pw.SizedBox(height: 8),
                      _buildServiciosTable(servicios, totalPresupuesto),
                    ],
                  ],
                ),
              ),

              // ── Footer ──────────────────────────────────────────────────
              pw.SizedBox(height: 32),
              _buildFooter(),
            ],
          ),
        ],
      ),
    );

    return pdf;
  }

  // ── Header claro con logo (Rediseñado para el Señor) ───────────────────────────────
  static pw.Widget _buildHeader(
    pw.ImageProvider? logo,
    String titulo,
    String fecha,
    Evento evento,
    String fechaEvento,
  ) {
    return pw.Container(
      color: _headerBg,
      padding: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Logo + marca
          pw.Row(
            children: [
              if (logo != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(1.5),
                  decoration: const pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    gradient: pw.LinearGradient(
                      colors: [_gold, PdfColor.fromInt(0xFFFFFFFF)],
                    ),
                  ),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColors.white,
                    ),
                    child: pw.ClipOval(
                      child: pw.Image(
                        logo,
                        width: 38,
                        height: 38,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                )
              else
                pw.Text(
                  'JE',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    color: _gold,
                  ),
                ),
              pw.SizedBox(width: 14),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'JUNIOR EVENTOS',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _darkText,
                      letterSpacing: 2,
                    ),
                  ),
                  pw.Text(
                    'Sistema de Gestión Premium',
                    style: pw.TextStyle(fontSize: 8, color: _greyText),
                  ),
                ],
              ),
            ],
          ),
          // Título + fecha
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: pw.BoxDecoration(
                  color: _gold,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                ),
                child: pw.Text(
                  titulo,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Emitido: $fecha',
                style: pw.TextStyle(fontSize: 9, color: _greyText),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                EventoPresentacion.tituloPrincipal(evento),
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                EventoPresentacion.subtituloEvento(evento),
                style: pw.TextStyle(fontSize: 9, color: _greyText),
              ),
              if (EventoPresentacion.nombreFestejadoEfectivoEvento(evento) !=
                  null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  EventoPresentacion.fraseIntroEvento(evento),
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontStyle: pw.FontStyle.italic,
                    color: _greyText,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── ESTADO DE CUENTA (Rediseño Élite) ──────────────────────────────────────
  static pw.Widget _buildEstadoCuenta({
    required double pagado,
    required double totalBonificaciones,
    required double saldo,
    required DateTime fechaEvento,
    Transaccion? ultimoPago,
    String? etiquetaPago,
  }) {
    final bool esVencido = DateTime.now().isAfter(fechaEvento);
    final PdfColor statusColor = (saldo > 0.01 && esVencido)
        ? _redAccent
        : (saldo > 0.01 ? _gold : _greenAccent);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            children: [
              _resumenItem(
                'MONTO ABONADO',
                pagado.toCurrency(),
                _greenAccent,
                subtext: 'Efectivo + beneficio',
                valueFontSize: 12,
              ),
              _dividerV(height: 26),
              _resumenItem(
                'BENEFICIO',
                totalBonificaciones.toCurrency(),
                _gold,
                subtext: totalBonificaciones > 0.01
                    ? 'Descuento acordado'
                    : 'Sin beneficio',
                valueFontSize: 12,
              ),
              _dividerV(height: 26),
              _resumenItem(
                'SALDO',
                saldo.toCurrency(),
                statusColor,
                subtext: 'A liquidar',
                isHighlight: (saldo > 0.01 && esVencido),
                valueFontSize: 12,
              ),
            ],
          ),
          if (ultimoPago != null) ...[
            pw.SizedBox(height: 6),
            pw.Divider(color: _greyLight, height: 1),
            pw.SizedBox(height: 4),
            pw.Text(
              '${etiquetaPago ?? 'Último registro'}: ${ultimoPago.concepto ?? 'Pago'} · '
              '${ultimoPago.fechaPago != null ? ArTime.formatFechaHora(ultimoPago.fechaPago!) : '—'} · '
              '${ultimoPago.monto.toCurrency()}',
              style: pw.TextStyle(fontSize: 6.8, color: _greyText),
              textAlign: pw.TextAlign.center,
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            'El monto abonado suma lo pagado en mano más beneficios registrados.',
            style: pw.TextStyle(
              fontSize: 6.5,
              color: _greyText,
              fontStyle: pw.FontStyle.italic,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  static pw.Widget _resumenItem(
    String label,
    String value,
    PdfColor color, {
    String? subtext,
    bool isHighlight = false,
    double valueFontSize = 14,
  }) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 6.5,
              color: _greyText,
              letterSpacing: 0.6,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: valueFontSize,
              fontWeight: pw.FontWeight.bold,
              color: isHighlight ? _redAccent : color,
            ),
          ),
          if (subtext != null)
            pw.Text(
              subtext,
              style: pw.TextStyle(fontSize: 6, color: _greyText),
            ),
        ],
      ),
    );
  }

  static pw.Widget _dividerV({double height = 30}) {
    return pw.Container(
      height: height,
      width: 0.5,
      color: _greyLight,
      margin: const pw.EdgeInsets.symmetric(horizontal: 8),
    );
  }

  // ── Tabla de pagos ─────────────────────────────────────────────────────────
  static pw.Widget _buildPagosTable(List<Transaccion> transacciones) {
    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.45),
        1: const pw.FlexColumnWidth(1.1),
        2: const pw.FlexColumnWidth(1.8),
        3: const pw.FlexColumnWidth(0.95),
        4: const pw.FlexColumnWidth(1.2),
      },
      children: [
        // Encabezado
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerBg),
          children: [
            _tableHeader('#'),
            _tableHeader('FECHA'),
            _tableHeader('CONCEPTO'),
            _tableHeader('TIPO'),
            _tableHeader('MONTO'),
          ],
        ),
        // Filas
        ...transacciones.asMap().entries.map((entry) {
          final i = entry.key;
          final tr = entry.value;
          final isFirst = i == 0;
          final esBonif = tr.esBonificacion;
          // Fecha en huso AR con hora y minuto (sello temporal preciso).
          final fecha = tr.fechaPago != null
              ? ArTime.formatFechaHora(tr.fechaPago!)
              : '—';
          final PdfColor? rowAccent = isFirst
              ? (esBonif ? _gold : _greenAccent)
              : null;
          final PdfColor rowBg = isFirst
              ? (esBonif
                    ? PdfColor.fromInt(0xFFFFF8E7)
                    : PdfColor.fromInt(0xFFF0FFF4))
              : (i.isEven ? PdfColors.white : _cardBg);
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              _tableCell(
                '${transacciones.length - i}',
                bold: isFirst,
                color: rowAccent,
              ),
              _tableCell(fecha, bold: isFirst),
              _tableCell(tr.concepto ?? 'Pago', bold: isFirst),
              _tableCell(
                esBonif ? 'Bonificación' : (tr.medioPago ?? 'Efectivo'),
                bold: isFirst,
                color: esBonif ? _gold : _greyText,
              ),
              _tableCell(
                tr.monto.toCurrency(),
                bold: isFirst,
                color: rowAccent,
                align: pw.TextAlign.right,
              ),
            ],
          );
        }),
      ],
    );
  }

  // ── Tabla de servicios ─────────────────────────────────────────────────────
  static pw.Widget _buildServiciosTable(
    List<EventosServicios> servicios,
    double total,
  ) {
    return pw.Column(
      children: [
        pw.Table(
          border: pw.TableBorder.all(color: _greyLight, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _headerBg),
              children: [
                _tableHeader('SERVICIO'),
                _tableHeader('CANT.'),
                _tableHeader('PRECIO'),
                _tableHeader('SUBTOTAL'),
              ],
            ),
            ...servicios.asMap().entries.map((entry) {
              final i = entry.key;
              final srv = entry.value;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? PdfColors.white : _cardBg,
                ),
                children: [
                  _tableCell(srv.servicio?.nombre ?? 'Servicio'),
                  _tableCell(
                    srv.cantidad.toStringAsFixed(0),
                    align: pw.TextAlign.center,
                  ),
                  _tableCell(
                    srv.precioFinalAcordado.toCurrency(),
                    align: pw.TextAlign.right,
                  ),
                  _tableCell(
                    (srv.precioFinalAcordado * srv.cantidad).toCurrency(),
                    align: pw.TextAlign.right,
                  ),
                ],
              );
            }),
          ],
        ),
        // Total
        pw.Container(
          color: _headerBg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PRESUPUESTADO',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _darkText,
                  letterSpacing: 1,
                ),
              ),
              pw.Text(
                total.toCurrency(),
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _gold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter() {
    return pw.Container(
      color: _cardBg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'JUNIOR EVENTOS  ·  EXCELENCIA Y COMPROMISO',
            style: pw.TextStyle(
              fontSize: 8,
              color: _greyText,
              letterSpacing: 1,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Gestión personalizada para eventos inolvidables.',
            style: pw.TextStyle(
              fontSize: 8,
              fontStyle: pw.FontStyle.italic,
              color: _greyText,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers de tabla ───────────────────────────────────────────────────────
  static pw.Widget _buildSectionTitle(String text) {
    return pw.Row(
      children: [
        pw.Container(width: 3, height: 14, color: _gold),
        pw.SizedBox(width: 8),
        pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 1.2,
            color: _darkText,
          ),
        ),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: _darkText,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    bool bold = false,
    PdfColor? color,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : null,
          color: color ?? _darkText,
        ),
      ),
    );
  }
}
