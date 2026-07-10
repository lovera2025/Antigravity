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
import '../../cierre_caja/models/turno_caja.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../rentabilidad/services/calculador_rentabilidad_service.dart';
import '../../eventos/services/cobro_masivo_conceptos_pdf.dart';
import '../../eventos/services/mesas_extra_utils.dart';
import '../../eventos/utils/evento_presentacion.dart';
import '../../eventos/utils/presupuesto_desde_evento.dart';
import '../utils/currency_extensions.dart';
import 'presupuesto_pdf_sections.dart';
import 'presupuesto_redaccion_llm_service.dart';

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

class PdfService {
  /// Tablas más pequeñas evitan que un solo [pw.Table] dispare [TooManyPagesException] en [pw.MultiPage].
  static const int _kCierreCajaFilasPorBloque = 28;

  static String? _ultimaRutaPdfGuardado;

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
    final fraseIntroPdf = llmTxt?.fraseIntroUsable() ??
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
    final safeCliente =
        (p.cliente?.nombreCompleto ?? 'Cliente').replaceAll(' ', '_');
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
    final p = presupuestoVirtualDesdeEvento(evento: evento, servicios: servicios);
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

  static String _normalizarTextoMatch(String? raw) {
    if (raw == null) return '';
    var s = raw.toLowerCase().trim();
    const pares = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      b.write(pares[ch] ?? ch);
    }
    return b.toString();
  }

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
        pw.Container(
          height: 0.5,
          color: _greyLight,
        ),
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

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (ctx) => pw.Column(
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
            pw.Spacer(),
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

  static Future<void> generarReciboAlumno({
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
  }) async {
    // Cargar fuente TrueType con soporte Unicode completo (elimina warnings de Helvetica)
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

    // Anclaje temporal ESTRICTO en huso America/Argentina/Buenos_Aires (GMT-3).
    // Cada recibo lleva el instante exacto (día + hora + minuto) de la
    // operación para garantizar la validez legal y administrativa.
    final now = ArTime.nowUtc();
    final fechaTransaccion = fechaManual ?? now;
    final fechaStr = ArTime.formatFechaHora(fechaTransaccion);
    final fechaEmision = ArTime.formatFechaHora(now);
    final operacionGestionadaStr = ArTime.operacionGestionada(fechaTransaccion);

    // Calcular VALOR dinámicamente...
    final bool esReimpresion = fechaManual != null;
    final valPago = (conceptosPagados != null && conceptosPagados.isNotEmpty)
        ? conceptosPagados.fold<double>(
            0,
            (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0),
          )
        : montoPagado;
    final valSaldo = saldoPendiente;

    final mesasEstadoRecibo = MesasExtraUtils.estadoDesdeContrato(alumno);
    final cantMesasRecibo = MesasExtraUtils.cantidadMesasContrato(
      alumno,
      mesasEstadoRecibo,
    );
    final conceptosPagadosDisplay = conceptosPagados != null
        ? agruparConceptosMesasParaPdf(
            conceptosPagados
                .map((c) => Map<String, dynamic>.from(c))
                .toList(),
            cantMesasRecibo,
          )
        : null;

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
    final bool usarMontoFijo =
        cargoInformado != null && cargoInformado > 0.01;
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

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) {
          final medioReciboStr = medioPago?.trim() ?? '';
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _greyLight, width: 0.5),
                  ),
                ),
                padding: const pw.EdgeInsets.fromLTRB(22, 8, 22, 16),
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
                                  pw.Text(
                                    'Responsable Inscripto',
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
                                'RECIBO DE PAGO',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _darkText,
                                ),
                              ),
                              pw.Text(
                                'N° ${alumno.id.substring(0, 8).toUpperCase()}',
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: _greyText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),

                      // Cuerpo
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Fecha: $fechaStr',
                            style: pw.TextStyle(fontSize: 10),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: const pw.BoxDecoration(
                              color: _greyLight,
                            ),
                            child: pw.Text(
                              'VALOR: ${valPago.toCurrency()}',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      if (lineaMixMedios != null) ...[
                        pw.Text(
                          lineaMixMedios,
                          style: pw.TextStyle(fontSize: 9, color: _greyText),
                        ),
                        pw.SizedBox(height: 2),
                      ] else if (medioReciboStr.isNotEmpty)
                        pw.Text(
                          'Medio de pago: $medioReciboStr',
                          style: pw.TextStyle(fontSize: 9, color: _greyText),
                        ),
                      if (!reciboMixto && medioReciboStr.isNotEmpty)
                        pw.SizedBox(height: 2),
                      if (mostrarCargoRef)
                        pw.Text(
                          textoCargoReferenciaPdf,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontStyle: pw.FontStyle.italic,
                            color: _greyText,
                          ),
                        ),
                      if (mostrarCargoRef) pw.SizedBox(height: 2),
                      // Sello temporal estricto (AR GMT-3): día + hora + minuto.
                      pw.Text(
                        operacionGestionadaStr,
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                      pw.SizedBox(height: 3),

                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            const pw.TextSpan(
                              text: 'Recibí de: ',
                              style: pw.TextStyle(fontSize: 10),
                            ),
                            pw.TextSpan(
                              text: alumno.nombreAlumno.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 2),

                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            const pw.TextSpan(
                              text: 'La suma de pesos: ',
                              style: pw.TextStyle(fontSize: 10),
                            ),
                            pw.TextSpan(
                              text: numeroALetras(valPago),
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontStyle: pw.FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 3),

                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Concepto:',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (alumno.numeroMesa != null &&
                              alumno.numeroMesa!.isNotEmpty)
                            pw.Text(
                              'MESA: ${alumno.numeroMesa}',
                              style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: _greyText,
                              ),
                            ),
                        ],
                      ),
                      pw.SizedBox(height: 2),

                      // Desglose itemizado de conceptos pagados
                      if (conceptosPagadosDisplay != null &&
                          conceptosPagadosDisplay.isNotEmpty) ...[
                        ...conceptosPagadosDisplay.map((c) {
                          final desc = c['concepto'] as String? ?? 'Pago';
                          final montoItem =
                              (c['monto'] as num?)?.toDouble() ?? 0;
                          final grossItem =
                              (c['gross'] as num?)?.toDouble();
                          final subtexto = c['subtexto'] as String?;
                          final bool plan =
                              c['esPlanLiquidacion'] == true;
                          final String? nominalHint = plan &&
                                  grossItem != null &&
                                  grossItem > montoItem + 0.01
                              ? 'nom. ${grossItem.toCurrency()}'
                              : null;
                          return pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                            children: [
                              pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Expanded(
                                    child: pw.Text(
                                      '  • $desc',
                                      style: pw.TextStyle(fontSize: 10),
                                    ),
                                  ),
                                  pw.Text(
                                    montoItem.toCurrency(),
                                    style: pw.TextStyle(
                                      fontSize: 10,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (subtexto != null && subtexto.isNotEmpty)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 12),
                                  child: pw.Text(
                                    subtexto,
                                    style: pw.TextStyle(
                                      fontSize: 8,
                                      fontStyle: pw.FontStyle.italic,
                                      color: _greyText,
                                    ),
                                  ),
                                ),
                              if (nominalHint != null)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 12),
                                  child: pw.Text(
                                    nominalHint,
                                    style: pw.TextStyle(
                                      fontSize: 8,
                                      fontStyle: pw.FontStyle.italic,
                                      color: _greyText,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }),
                        ..._bloqueDescuentoLiquidacionPdf(
                          porcentajeDescuento: porcentajeDescuentoLiquidacion,
                          conceptos: conceptosPagadosDisplay,
                          fontSize: 9,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          alumno.institucion ?? evento.tipoParaMostrar,
                          style: pw.TextStyle(fontSize: 8, color: _greyText),
                        ),
                        pw.SizedBox(height: 3),
                      ] else ...[
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
                        pw.SizedBox(height: 2),
                        pw.Text(
                          alumno.institucion ?? evento.tipoParaMostrar,
                          style: pw.TextStyle(fontSize: 8, color: _greyText),
                        ),
                        pw.SizedBox(height: 3),
                      ],

                      // ─── RESUMEN DE CUENTA ───
                      pw.Text(
                        'RESUMEN DE CUENTA:',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: _greyText,
                          letterSpacing: 1.0,
                        ),
                      ),
                      pw.SizedBox(height: 2),
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
                            pw.Padding(
                              padding: const pw.EdgeInsets.fromLTRB(
                                8,
                                8,
                                8,
                                4,
                              ),
                              child: pw.Column(
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'ESTE RECIBO',
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      fontWeight: pw.FontWeight.bold,
                                      color: _greyText,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  pw.SizedBox(height: 3),
                                  if (reciboMixto) ...[
                                    pw.Text(
                                      '· Efectivo: ${efDet.toCurrency()}',
                                      style: pw.TextStyle(
                                        fontSize: 7,
                                        color: _darkText,
                                      ),
                                    ),
                                    pw.Text(
                                      '· Transferencia: '
                                      '${trDet.toCurrency()}',
                                      style: pw.TextStyle(
                                        fontSize: 7,
                                        color: _darkText,
                                      ),
                                    ),
                                  ] else if (medioReciboStr.isNotEmpty)
                                    pw.Text(
                                      '· Medio: $medioReciboStr',
                                      style: pw.TextStyle(
                                        fontSize: 7,
                                        color: _darkText,
                                      ),
                                    ),
                                  if (conceptosPagadosDisplay != null &&
                                      conceptosPagadosDisplay.isNotEmpty) ...[
                                    ...conceptosPagadosDisplay.map((c) {
                                      final desc =
                                          c['concepto'] as String? ?? 'Pago';
                                      final montoItem =
                                          (c['monto'] as num?)?.toDouble() ??
                                          0;
                                      final subtexto =
                                          c['subtexto'] as String?;
                                      return pw.Padding(
                                        padding: const pw.EdgeInsets.only(
                                          top: 2,
                                        ),
                                        child: pw.Column(
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Row(
                                              mainAxisAlignment:
                                                  pw.MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                pw.Expanded(
                                                  child: pw.Text(
                                                    '· $desc',
                                                    style: pw.TextStyle(
                                                      fontSize: 7,
                                                      color: _darkText,
                                                    ),
                                                  ),
                                                ),
                                                pw.Text(
                                                  montoItem.toCurrency(),
                                                  style: pw.TextStyle(
                                                    fontSize: 7,
                                                    fontWeight:
                                                        pw.FontWeight.bold,
                                                    color: _darkText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (subtexto != null &&
                                                subtexto.isNotEmpty)
                                              pw.Text(
                                                subtexto,
                                                style: pw.TextStyle(
                                                  fontSize: 6,
                                                  fontStyle:
                                                      pw.FontStyle.italic,
                                                  color: _greyText,
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ] else
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.only(
                                        top: 2,
                                      ),
                                      child: pw.Row(
                                        mainAxisAlignment:
                                            pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Expanded(
                                            child: pw.Text(
                                              '· ${conceptoCuotas ?? 'Cuota ${alumno.cuotasPagadas} de ${alumno.totalCuotas}'}',
                                              style: pw.TextStyle(
                                                fontSize: 7,
                                                color: _darkText,
                                              ),
                                            ),
                                          ),
                                          pw.Text(
                                            valPago.toCurrency(),
                                            style: pw.TextStyle(
                                              fontSize: 7,
                                              fontWeight: pw.FontWeight.bold,
                                              color: _darkText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (mostrarCargoRef)
                                    pw.Padding(
                                      padding: const pw.EdgeInsets.only(
                                        top: 4,
                                      ),
                                      child: pw.Text(
                                        textoCargoReferenciaPdf,
                                        style: pw.TextStyle(
                                          fontSize: 6,
                                          fontStyle: pw.FontStyle.italic,
                                          color: _greyText,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            pw.Container(
                              margin: const pw.EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              height: 0.5,
                              color: _greyLight,
                            ),
                            pw.Table(
                          columnWidths: {
                            0: const pw.FixedColumnWidth(160),
                            1: const pw.FixedColumnWidth(70),
                            2: const pw.FixedColumnWidth(120),
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
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    8,
                                    4,
                                  ),
                                  child: pw.Text(
                                    'DETALLE DEL CONTRATO',
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      color: _greyText,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    8,
                                    4,
                                  ),
                                  child: pw.Text(
                                    'CUOTAS BASE',
                                    style: pw.TextStyle(
                                      fontSize: 6,
                                      color: _greyText,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    4,
                                    8,
                                    4,
                                  ),
                                  child: pw.Text(
                                    'BALANCE FINANCIERO',
                                    style: pw.TextStyle(
                                      fontSize: 6,
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
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    8,
                                    6,
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
                                              alumno.mesaExtraPagado).clamp(0.0, double.infinity);
                                          final double saldoSillasRestante =
                                              (alumno.sillasExtraPrecioTotal -
                                              alumno.sillasExtraPagado).clamp(0.0, double.infinity);
                                          final double saldoBaseRestante =
                                              (valSaldo - saldoMesaRestante - saldoSillasRestante).clamp(0.0, double.infinity);

                                          return pw.Column(
                                            crossAxisAlignment:
                                                pw.CrossAxisAlignment.start,
                                            children: [
                                              pw.Text(
                                                '· Base: ${montoBase.toCurrency()}  (Resta: ${(saldoBaseRestante > 0.01 ? saldoBaseRestante : 0.0).toCurrency()})',
                                                style: pw.TextStyle(
                                                  fontSize: 7,
                                                  fontWeight:
                                                      pw.FontWeight.bold,
                                                  color: _darkText,
                                                ),
                                              ),
                                              if (alumno.mesaExtraPrecio > 0.01)
                                                ...() {
                                                  final mesas =
                                                      MesasExtraUtils
                                                          .estadoDesdeContrato(
                                                    alumno,
                                                  );
                                                  final lineasMesas =
                                                      lineasDetalleMesasContratoPdf(
                                                    mesas: mesas,
                                                    cuotasPlan:
                                                        alumno.mesaExtraCuotas,
                                                  );
                                                  return lineasMesas
                                                      .map(
                                                        (linea) => pw.Padding(
                                                          padding:
                                                              const pw.EdgeInsets
                                                                  .only(
                                                            top: 1,
                                                          ),
                                                          child: pw.Text(
                                                            linea.texto,
                                                            style: pw.TextStyle(
                                                              fontSize: 7,
                                                              color: linea
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
                                                      fontSize: 7,
                                                      color: _greyText,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      ),
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.only(
                                          top: 3,
                                        ),
                                        child: pw.Text(
                                          'TOTAL: ${alumno.montoTotalPactado.toCurrency()}',
                                          style: pw.TextStyle(
                                            fontSize: 7,
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
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    8,
                                    6,
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.center,
                                    children: [
                                      pw.Text(
                                        '${alumno.cuotasPagadas}/${alumno.totalCuotas}',
                                        style: pw.TextStyle(
                                          fontSize: 13,
                                          fontWeight: pw.FontWeight.bold,
                                          color:
                                              alumno.cuotasPagadas >=
                                                  alumno.totalCuotas
                                              ? _greenAccent
                                              : _gold,
                                        ),
                                      ),
                                      pw.Text(
                                        'pagadas',
                                        style: pw.TextStyle(
                                          fontSize: 6,
                                          color: _greyText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Columna 3: Balance
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(
                                    8,
                                    6,
                                    8,
                                    6,
                                  ),
                                  child: pw.Column(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        'Abonado:',
                                        style: pw.TextStyle(
                                          fontSize: 6,
                                          color: _greyText,
                                        ),
                                      ),
                                      pw.Text(
                                        (alumno.montoTotalPactado - valSaldo)
                                            .toCurrency(),
                                        style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: _greenAccent,
                                        ),
                                      ),
                                      pw.SizedBox(height: 3),
                                      pw.Text(
                                        'Saldo pendiente:',
                                        style: pw.TextStyle(
                                          fontSize: 6,
                                          color: _greyText,
                                        ),
                                      ),
                                      pw.Text(
                                        valSaldo.toCurrency(),
                                        style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: valSaldo < 0.01
                                              ? _greenAccent
                                              : (now.isAfter(evento.fechaEvento)
                                                    ? _redAccent
                                                    : _gold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                          ],
                        ),
                      ),

                      if (esReimpresion)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 5),
                          child: pw.Text(
                            'Reimpreso el: $fechaEmision (Original: $fechaStr)',
                            style: pw.TextStyle(
                              fontSize: 7,
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
          );
        },
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
  }

  // ── Resumen a abonar (informativo, pre-cobro) ────────────────────────────
  static Future<void> generarResumenAbonarAlumno({
    required ContratoAlumno alumno,
    required Evento evento,
    required double saldoActualPlan,
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
    final operacionStr = ArTime.operacionGestionada(now);

    final mesasEstadoResumen = MesasExtraUtils.estadoDesdeContrato(alumno);
    final cantMesasResumen = MesasExtraUtils.cantidadMesasContrato(
      alumno,
      mesasEstadoResumen,
    );
    final conceptosLineasDisplay = agruparConceptosMesasParaPdf(
      conceptosLineas.map((c) => Map<String, dynamic>.from(c)).toList(),
      cantMesasResumen,
    );

    final lineasLiquidacion = conceptosLineasDisplay
        .where((c) => c['esCargoCanal'] != true)
        .toList();
    final lineasCargo =
        conceptosLineasDisplay.where((c) => c['esCargoCanal'] == true).toList();
    final double cargoTotal = lineasCargo.fold<double>(
      0,
      (s, c) => s + ((c['monto'] as num?)?.toDouble() ?? 0),
    );

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
      baseCargoMonto =
          (subtotalLiquidacion - efDet!).clamp(0.0, double.infinity);
    } else if (esTransferencia) {
      baseCargoMonto = subtotalLiquidacion;
    }
    final double? cargoInformado = montoCargoTransferenciaInformado;
    final bool usarMontoFijo =
        cargoInformado != null && cargoInformado > 0.01;
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
      final desc = c['concepto'] as String? ?? 'Concepto';
      final monto = (c['monto'] as num?)?.toDouble() ?? 0;
      final sub = c['subtexto'] as String?;
      final gross = (c['gross'] as num?)?.toDouble();
      final bool plan = c['esPlanLiquidacion'] == true;
      final String? subNominal = plan &&
              gross != null &&
              gross > monto + 0.01
          ? 'nom. ${gross.toCurrency()}'
          : null;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '· $desc',
                    style: pw.TextStyle(fontSize: 9, color: _darkText),
                  ),
                  if (sub != null && sub.isNotEmpty)
                    pw.Text(
                      sub,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                  if (subNominal != null)
                    pw.Text(
                      subNominal,
                      style: pw.TextStyle(
                        fontSize: 7,
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
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _darkText,
              ),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(22, 16, 22, 14),
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
                              'RESUMEN A ABONAR',
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            pw.Text(
                              'N° ${alumno.id.substring(0, 8).toUpperCase()}',
                              style: pw.TextStyle(
                                fontSize: 8,
                                color: _greyText,
                              ),
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
                padding: const pw.EdgeInsets.fromLTRB(22, 12, 22, 16),
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
                    if (alumno.institucion != null &&
                        alumno.institucion!.trim().isNotEmpty)
                      pw.Text(
                        alumno.institucion!,
                        style: pw.TextStyle(fontSize: 9, color: _greyText),
                      ),
                    if (alumno.cursoDivision != null &&
                        alumno.cursoDivision!.trim().isNotEmpty)
                      pw.Text(
                        alumno.cursoDivision!,
                        style: pw.TextStyle(fontSize: 9, color: _greyText),
                      ),
                    pw.Text(
                      evento.tipoParaMostrar,
                      style: pw.TextStyle(fontSize: 9, color: _greyText),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: _cardBg,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(6),
                        ),
                        border: pw.Border.all(color: _greyLight, width: 0.5),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'SALDO ACTUAL DEL PLAN',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: _greyText,
                              letterSpacing: 0.6,
                            ),
                          ),
                          pw.Text(
                            saldoActualPlan.toCurrency(),
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (medioStr.isNotEmpty) ...[
                      pw.SizedBox(height: 8),
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
                      'LIQUIDACIÓN DEL PLAN',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greyText,
                        letterSpacing: 0.8,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    ...lineasLiquidacion.map(lineaConcepto),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2, bottom: 8),
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
                    ),
                    ..._bloqueDescuentoLiquidacionPdf(
                      porcentajeDescuento: porcentajeDescuentoLiquidacion,
                      conceptos: conceptosLineasDisplay,
                      fontSize: 8,
                    ),
                    if (cargoTotal > 0.01) ...[
                      pw.Text(
                        'RECARGO TRANSFERENCIA (referencia)',
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
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(10),
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
                                ? 'TOTAL A TRANSFERIR'
                                : 'TOTAL A ABONAR',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.Text(
                            totalAbonar.toCurrency(),
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: _darkText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (moraPendienteNoIncluida != null &&
                        moraPendienteNoIncluida > 0.01) ...[
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Interés por mora no incluido en este resumen: '
                        '${moraPendienteNoIncluida.toCurrency()}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontStyle: pw.FontStyle.italic,
                          color: _greyText,
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'El interés por mora no forma parte del saldo del plan '
                      'de cuotas.',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Documento informativo. No implica cobro registrado.',
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontStyle: pw.FontStyle.italic,
                        color: _greyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final safeName = alumno.nombreAlumno.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final fname = 'Resumen_abonar_${safeName.isEmpty ? 'alumno' : safeName.replaceAll(' ', '_')}.pdf';
    if (!kIsWeb && Platform.isWindows) {
      await _entregarPdfEnWindows(bytes, fname);
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fname,
      );
    }
  }

  // ── Planilla por Cursos (Para Eventos Masivos) ─────────────────────────
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
    final tituloSafe = eventoTitulo.trim().isEmpty ? 'Evento' : eventoTitulo.trim();
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
              style: pw.TextStyle(fontSize: 8.5, color: _greyText, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Listado en dos bloques: primero quienes no firmaron, después quienes sí firmaron el contrato.',
              style: pw.TextStyle(fontSize: 9, color: _darkText, fontWeight: pw.FontWeight.bold),
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
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                data: <List<String>>[
                  headers,
                  ...filasAlumnos(pendientes),
                ],
              ),
            );
          } else {
            children.add(
              bloqueTitulo('ESTOS NO FIRMARON EL CONTRATO — 0 persona(s)', _greyText),
            );
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '(Nadie pendiente de firma en este listado.)',
                  style: pw.TextStyle(fontSize: 9.5, color: _greyText, fontStyle: pw.FontStyle.italic),
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
                data: <List<String>>[
                  headers,
                  ...filasAlumnos(firmados),
                ],
              ),
            );
          } else {
            children.add(
              bloqueTitulo('ESTOS SÍ FIRMARON EL CONTRATO — 0 persona(s)', _greyText),
            );
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  '(Nadie figura con contrato firmado en este listado.)',
                  style: pw.TextStyle(fontSize: 9.5, color: _greyText, fontStyle: pw.FontStyle.italic),
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
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fname,
      );
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
    final tituloSafe = eventoTitulo.trim().isEmpty ? 'Evento' : eventoTitulo.trim();
    final filtroSafe = filtroTitulo.trim().isEmpty ? 'Listado' : filtroTitulo.trim();
    final n = filas.length;

    final tituloColor =
        filtroSafe.toLowerCase().startsWith('no pagaron') ? _redAccent : _greenAccent;

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
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: pw.BoxDecoration(
                color: tituloColor == _redAccent
                    ? PdfColor.fromInt(0xFFFFF0F0)
                    : PdfColor.fromInt(0xFFF0FFF5),
                border: pw.Border(left: pw.BorderSide(color: tituloColor, width: 4)),
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
              style: pw.TextStyle(fontSize: 8.5, color: _greyText, fontStyle: pw.FontStyle.italic),
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
                style: pw.TextStyle(fontSize: 10, color: _greyText, fontStyle: pw.FontStyle.italic),
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
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fname,
      );
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
    final tituloSafe = eventoTitulo.trim().isEmpty ? 'Evento' : eventoTitulo.trim();
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
            style: pw.TextStyle(fontSize: 9.5, color: _greyText, fontStyle: pw.FontStyle.italic),
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
              style: pw.TextStyle(fontSize: 9.5, color: _greenAccent, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '· No pagaron: $nNo ($firmNo firmaron · ${nNo - firmNo} sin firmar)',
              style: pw.TextStyle(fontSize: 9.5, color: _redAccent, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '· Total en listado: $total',
              style: pw.TextStyle(fontSize: 9.5, color: _darkText, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Solo cuotas base del plan (sin mora ni mesas). Columna CONTRATO: firmado o sin firmar.',
              style: pw.TextStyle(fontSize: 8.5, color: _greyText, fontStyle: pw.FontStyle.italic),
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
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: fname,
      );
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
  }) async {
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

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

    pdf.addPage(
      pw.MultiPage(
        maxPages: 10000,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) => [
          pw.Container(
            width: PdfPageFormat.a4.width,
            constraints: pw.BoxConstraints(minHeight: 9.5 * PdfPageFormat.cm),
            padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 8),
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
                            _ticketCajaTablaIngresos(ingresosTurno)
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
                              totalRetirado:
                                  retirosEfectivo + retirosTransferencia,
                            ),
                            pw.SizedBox(height: 4),
                            _ticketCajaTablaRetiros(retirosTurno),
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
                  _ticketCajaTablaOtrosEgresos(otrosEgresosTurno),
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
                      style: pw.TextStyle(fontSize: 8.5, color: _darkText, lineSpacing: 1.35),
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
        ],
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

  static pw.Widget _ticketCajaTablaIngresos(List<IngresoDetallado> rows) {
    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: header ? 7.5 : 7.5,
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

  static pw.Widget _ticketCajaTablaRetiros(List<Egreso> rows) {
    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 7.5,
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
            cell(_pdfCierreTrunc(e.proveedor, 22), color: _redAccent),
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
  static pw.Widget _ticketCajaTablaOtrosEgresos(List<Egreso> rows) {
    const catColor = PdfColor(0.45, 0.35, 0.15);
    const montoColor = PdfColor(0.79, 0.44, 0.12);

    pw.Widget cell(
      String text, {
      bool header = false,
      PdfColor? color,
      pw.TextAlign align = pw.TextAlign.left,
    }) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: 7.5,
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
            cell(_pdfCierreTrunc(e.proveedor, 28)),
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
            cell(_pdfCierreTrunc(e.proveedor, 48)),
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

  static Future<String> _guardarPdfEnDefault(Uint8List bytes, String filename) async {
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        final path = _ultimaRutaPdfGuardado ?? await _guardarPdfEnDefault(bytes, filename);
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
              if (EventoPresentacion.nombreFestejadoEfectivoEvento(evento) != null) ...[
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
