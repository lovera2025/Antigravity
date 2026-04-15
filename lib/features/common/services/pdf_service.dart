import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/presupuesto.dart';
import '../utils/currency_extensions.dart';

// Paleta de colores del PDF (Rediseño Élite a pedido del Señor)
const _gold = PdfColor.fromInt(0xFFD4AF37);
const _headerBg = PdfColor.fromInt(0xFFF2F2F2); // Gris Perla Elegante
const _cardBg = PdfColor.fromInt(0xFFF9F9F9);
const _darkText = PdfColor.fromInt(0xFF2C3E50);
const _redAccent = PdfColor.fromInt(0xFFE74C3C);
const _greenAccent = PdfColor.fromInt(0xFF27AE60);
const _greyText = PdfColor.fromInt(0xFF7F8C8D);
const _greyLight = PdfColor.fromInt(0xFFE0E0E0);

class PdfService {
  // ── Presupuesto de Élite con IA de Redacción ─────────────────────────────
  static Future<void> generarPresupuestoElite(Presupuesto p) async {
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

    final now = DateTime.now();
    final fechaEmision = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final fechaVencimiento = '${p.fechaVencimiento.day.toString().padLeft(2, '0')}/${p.fechaVencimiento.month.toString().padLeft(2, '0')}/${p.fechaVencimiento.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        header: (context) => _buildHeaderElite(logoImage, 'PRESUPUESTO', fechaEmision, p.cliente?.nombreCompleto ?? 'Cliente', Evento.formatearTipo(p.tipoEvento), p.id),
        footer: (context) => _buildFooterPublicitario(p),
        build: (context) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Introducción Elegante y Humana
                pw.Text((p.tituloFestejado != null && p.tituloFestejado!.isNotEmpty)
                    ? p.tituloFestejado!.toUpperCase()
                    : '${Evento.formatearTipo(p.tipoEvento)} - ${p.cliente?.nombreCompleto ?? 'CLIENTE'}', 
                   style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: _gold, letterSpacing: 1.2)),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Esta propuesta ha sido diseñada para ${(p.tituloFestejado != null && p.tituloFestejado!.isNotEmpty) ? p.tituloFestejado : (p.cliente?.nombreCompleto ?? 'usted')}, a solicitud de ${p.cliente?.nombreCompleto ?? 'quien suscribe'}.',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _darkText),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Es un gusto saludarte. Aquí te presentamos la propuesta integral diseñada para transformar tu visión en un recuerdo imborrable, respaldada por un equipo apasionado y tecnología de vanguardia al servicio de tu celebración.',
                  style: pw.TextStyle(fontSize: 10, lineSpacing: 1.5, color: _darkText),
                ),
                pw.SizedBox(height: 24),

                // Sección: Detalles del Plan (Se eliminó el título de sección por pedido del Señor)
                pw.SizedBox(height: 4),
                
                ...(() {
                  final Map<String, List<PresupuestoServicio>> grouped = {};
                  final List<PresupuestoServicio> singles = [];
                  
                  for (var s in p.servicios) {
                    if (s.grupo != null && s.grupo!.isNotEmpty) {
                      grouped.putIfAbsent(s.grupo!, () => []).add(s);
                    } else {
                      singles.add(s);
                    }
                  }

                  return [
                    ...grouped.entries.map((e) => _buildGrupoServiciosRedactado(e.key, e.value)),
                    ...singles.map((s) => _buildServicioRedactado(s)),
                  ];
                })(),

                // Anclaje IA Extra
                if (p.detalleAnclaje != null && p.detalleAnclaje!.isNotEmpty) ...[
                   pw.SizedBox(height: 16),
                   pw.Container(
                     padding: const pw.EdgeInsets.all(12),
                     decoration: pw.BoxDecoration(
                       color: _cardBg,
                       border: pw.Border.all(color: const PdfColor(0.831, 0.686, 0.216, 0.3), width: 0.5),
                       borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                     ),
                     child: pw.Text(
                       'Anotaciones Especiales: ${p.detalleAnclaje}',
                       style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: _greyText),
                     ),
                   ),
                ],

                pw.SizedBox(height: 32),

                // Resumen de Inversión
                _buildResumenInversion(p.total, fechaVencimiento),
                
                pw.SizedBox(height: 32),
                
                // Cierre formal
                pw.Text(
                  'Quedamos a su entera disposición para cualquier ajuste o consulta técnica. El presente presupuesto cuenta con una validez de 7 días corridos a partir de la fecha de emisión para garantizar la disponibilidad de fecha y equipamiento.',
                  style: pw.TextStyle(fontSize: 9, color: _greyText),
                ),
              ],
            ),
          ),
        ],
      )
    );

    final bytes = await pdf.save();
    final fileName = 'Presupuesto_${p.cliente?.nombreCompleto.replaceAll(' ', '_')}.pdf';
    
    if (!kIsWeb && Platform.isWindows) {
      await _abrirEnWindows(bytes, fileName);
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName);
    }
  }

  static pw.Widget _buildGrupoServiciosRedactado(String nombreGrupo, List<PresupuestoServicio> servicios) {
    // Calculamos el total del grupo
    final totalGrupo = servicios.fold<double>(0, (sum, s) => sum + (s.precioFinal * s.cantidad));
    
    String titulo = servicios.map((s) => s.nombre?.toUpperCase() ?? '').where((n) => n.isNotEmpty).join(' • ');
    if (titulo.isEmpty) titulo = nombreGrupo.toUpperCase();
    if (titulo.isEmpty) titulo = nombreGrupo.toUpperCase();
    
    // Combinar narrativas e intros
    List<String> intros = [];
    List<String> detalles = [];
    
    for (var s in servicios) {
      String i = _introsPorServicio[s.nombre?.toLowerCase()] ?? 'Servicio especializado.';
      if (!intros.contains(i)) intros.add(i);
      if (s.detalleServicio != null && s.detalleServicio!.isNotEmpty) {
        detalles.add(s.detalleServicio!);
      }
    }

    String narrativaFinal = intros.join(' ');
    if (detalles.isNotEmpty) {
      narrativaFinal += ' La propuesta incluye: ${detalles.join(", ")}.';
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
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
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, letterSpacing: 1),
                  ),
                ]
              ),
              pw.Text(
                totalGrupo.toCurrency(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _darkText),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            narrativaFinal,
            style: pw.TextStyle(fontSize: 9, lineSpacing: 1.3, color: _darkText),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildServicioRedactado(PresupuestoServicio s) {
    String titulo = s.nombre?.toUpperCase() ?? 'SERVICIO ESPECIAL';
    String intro = _introsPorServicio[s.nombre?.toLowerCase()] ?? 'Servicio técnico de alta gama, configurado bajo estándares de excelencia para satisfacer los requerimientos del anfitrión.';
    String detalleBase = s.detalleServicio ?? '';
    
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
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
                   pw.Text(titulo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                ]
              ),
              pw.Text(
                (s.precioFinal * s.cantidad).toCurrency(),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: _darkText),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$intro${detalleBase.isNotEmpty ? ' • $detalleBase.' : ''}',
            style: pw.TextStyle(fontSize: 9, lineSpacing: 1.3, color: _darkText),
          ),
        ],
      ),
    );
  }

  static final Map<String, String> _introsPorServicio = {
    'sonido': 'Arquitectura sonora de alta fidelidad, diseñada para una cobertura uniforme y nitidez cristalina en cada rincón del salón.',
    'iluminación': 'Atmósferas dinámicas mediante un despliegue lumínico inteligente que resalta la arquitectura y acompaña cada etapa del evento.',
    'ambientación': 'Propuesta estética integral que fusiona mobiliario de diseño y elementos decorativos para proyectar una identidad de lujo y máximo confort.',
    'pantallas led': 'Superficies digitales de ultra-definición que aseguran un impacto visual cinematográfico y una experiencia inmersiva para los invitados.',
    'DJ': 'Curaduría musical estratégica que evoluciona con la energía de la fiesta, garantizando una pista vibrante y una celebración inolvidable.',
    'fotografía': 'Registro visual con estética editorial, capturando la elegancia de los momentos planificados y la magia de lo espontáneo.',
    'vajillas': 'Selección exclusiva de cristalería, mantelería y piezas de diseño que configuran una experiencia táctil y visual de primer nivel.',
    'locutor': 'Conducción profesional con dominio del protocolo y oratoria, guiando los hitos de la celebración con presencia y carisma.',
    'espejo mágico': 'Estación interactiva Mirror-Touch que combina tecnología social y entretenimiento para generar recuerdos tangibles de la noche.',
    'catering': 'Experiencia gastronómica de autor, integrando ingredientes de estación y técnicas de vanguardia en presentaciones de alta cocina.',
    'decoración': 'Curaduría de estilo y armonía visual, desde arreglos florales de autor hasta instalaciones artísticas que definen la distinción del evento.',
    'estructuras': 'Sistemas de montaje y soportes técnicos de alta resistencia, garantizando la seguridad y estética en la arquitectura del evento.',
    'efectos especiales': 'Despliegue de tecnologías visuales y sensoriales diseñadas para elevar el impacto emocional en los momentos clave.',
  };

  static pw.Widget _buildResumenInversion(double total, String vencimiento) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _headerBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('INVERSIÓN TOTAL DEL PROYECTO', style: pw.TextStyle(color: _gold, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
              pw.SizedBox(height: 4),
              pw.Text('Pagando una seña del 30% ahora, se congela el precio total.', style: pw.TextStyle(color: _greyText, fontSize: 7, fontStyle: pw.FontStyle.italic)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(total.toCurrency(), style: pw.TextStyle(color: _darkText, fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.Text('VÁLIDO HASTA: $vencimiento', style: pw.TextStyle(color: _greyText, fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooterPublicitario(Presupuesto p) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _greyLight, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('JUNIOR EVENTOS - EXPERIENCIAS INOLVIDABLES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              pw.Text('Seguinos en Instagram: @${p.instagram ?? 'junior_eventos_ok'}', style: pw.TextStyle(fontSize: 8, color: _greyText)),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('CONSULTAS Y CONTRATACIONES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              pw.Text('Junior Eventos', style: pw.TextStyle(fontSize: 8, color: _greyText)),
              pw.Text('WhatsApp / Cel: ${p.telefono ?? '351...'}', style: pw.TextStyle(fontSize: 8, color: _greyText)),
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
                      child: pw.Image(logo, width: 40, height: 40, fit: pw.BoxFit.contain),
                    ),
                  ),
                ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('JUNIOR EVENTOS', style: pw.TextStyle(color: _darkText, fontSize: 16, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                  pw.Text('SERVICIO INTEGRAL', style: pw.TextStyle(color: _gold, fontSize: 8, fontWeight: pw.FontWeight.bold, letterSpacing: 3)),
                ],
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
               pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: const pw.BoxDecoration(color: _gold, borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
                child: pw.Text(titulo, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
              ),
              pw.SizedBox(height: 8),
              pw.Text('EMISIÓN: $fechaEmision', style: pw.TextStyle(color: _greyText, fontSize: 8)),
              pw.SizedBox(height: 4),
              pw.Text(cliente, style: pw.TextStyle(color: _darkText, fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(tipoEvento.toUpperCase(), style: pw.TextStyle(color: _greyText, fontSize: 8)),
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
      await _abrirEnWindows(bytes, 'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf');
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
      await _abrirEnWindows(bytes, 'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf');
    } else {
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Recibo_${evento.cliente?.nombreCompleto ?? 'Cliente'}.pdf',
      );
    }
  }

  // ── Recibo Unibloque Alumno (Ahorro de Papel) ─────────────────────────────
  static Future<void> generarReciboAlumno({
    required ContratoAlumno alumno,
    required Evento evento,
    required double montoPagado,
    required double saldoPendiente,
    String? conceptoCuotas,
    List<Map<String, dynamic>>? conceptosPagados,
    DateTime? fechaManual,
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

    final now = DateTime.now();
    final fechaTransaccion = fechaManual ?? now;
    final fechaStr = '${fechaTransaccion.day.toString().padLeft(2, '0')}/${fechaTransaccion.month.toString().padLeft(2, '0')}/${fechaTransaccion.year}';
    final fechaEmision = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    
    // Calcular VALOR dinámicamente...
    final bool esReimpresion = fechaManual != null;
    final valPago = (conceptosPagados != null && conceptosPagados.isNotEmpty)
        ? conceptosPagados.fold<double>(0, (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0))
        : montoPagado;
    final valSaldo = saldoPendiente;
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) {
          return pw.Stack(
            children: [
              pw.Positioned(
                top: 0,
                left: 0,
                child: pw.Container(
                  width: PdfPageFormat.a4.width,
                  height: 9.5 * PdfPageFormat.cm,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: _greyLight, width: 0.5)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Header del Recibo
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          if (logoImage != null) pw.Container(height: 30, child: pw.Image(logoImage)),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('RECIBO DE PAGO', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _darkText)),
                              pw.Text('N° ${alumno.id.substring(0, 8).toUpperCase()}', style: pw.TextStyle(fontSize: 8, color: _greyText)),
                            ],
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      
                      // Cuerpo
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Fecha: $fechaStr', style: pw.TextStyle(fontSize: 10)),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: const pw.BoxDecoration(color: _greyLight),
                            child: pw.Text('VALOR: ${valPago.toCurrency()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),
                      
                      pw.RichText(text: pw.TextSpan(children: [
                        const pw.TextSpan(text: 'Recibí de: ', style: pw.TextStyle(fontSize: 10)),
                        pw.TextSpan(text: alumno.nombreAlumno.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ])),
                      pw.SizedBox(height: 2),
                      
                      pw.RichText(text: pw.TextSpan(children: [
                        const pw.TextSpan(text: 'La suma de pesos: ', style: pw.TextStyle(fontSize: 10)),
                        pw.TextSpan(text: numeroALetras(valPago), style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
                      ])),
                      pw.SizedBox(height: 3),

                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Concepto:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          if (alumno.numeroMesa != null && alumno.numeroMesa!.isNotEmpty)
                            pw.Text('MESA: ${alumno.numeroMesa}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _greyText)),
                        ],
                      ),
                      pw.SizedBox(height: 2),

                      // Desglose itemizado de conceptos pagados
                      if (conceptosPagados != null && conceptosPagados.isNotEmpty) ...[
                        ...conceptosPagados.map((c) {
                          final desc = c['concepto'] as String? ?? 'Pago';
                          final montoItem = (c['monto'] as num?)?.toDouble() ?? 0;
                          return pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('  • $desc', style: pw.TextStyle(fontSize: 10)),
                              pw.Text(montoItem.toCurrency(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            ],
                          );
                        }),
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
                            pw.Text('  • ${conceptoCuotas ?? 'Cuota ${alumno.cuotasPagadas} de ${alumno.totalCuotas}'}', style: pw.TextStyle(fontSize: 10)),
                            pw.Text(valPago.toCurrency(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _greyText, letterSpacing: 1.0),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Container(
                        decoration: pw.BoxDecoration(
                          color: _cardBg,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                          border: pw.Border.all(color: _greyLight, width: 0.5),
                        ),
                        child: pw.Table(
                          columnWidths: {
                            0: const pw.FixedColumnWidth(160),
                            1: const pw.FixedColumnWidth(70),
                            2: const pw.FixedColumnWidth(120),
                          },
                          border: pw.TableBorder(
                            verticalInside: pw.BorderSide(color: _greyLight, width: 0.5),
                          ),
                          children: [
                            // Header row
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(color: _greyLight),
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
                                  child: pw.Text('DETALLE DEL CONTRATO', style: pw.TextStyle(fontSize: 6, color: _greyText, letterSpacing: 0.6)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
                                  child: pw.Text('CUOTAS BASE', style: pw.TextStyle(fontSize: 6, color: _greyText, letterSpacing: 0.6)),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
                                  child: pw.Text('BALANCE FINANCIERO', style: pw.TextStyle(fontSize: 6, color: _greyText, letterSpacing: 0.6)),
                                ),
                              ],
                            ),
                            // Data row
                            pw.TableRow(
                              children: [
                                // Columna 1: Desglose contrato
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Builder(builder: (ctx) {
                                        final double montoBase = alumno.montoTotalPactado - alumno.mesaExtraPrecio - alumno.sillasExtraPrecioTotal;
                                        
                                        // Cálculos de saldo restante por concepto
                                        final double totalAbonado = alumno.montoTotalPactado - valSaldo;
                                        final double baseAbonado = totalAbonado - alumno.mesaExtraPagado - alumno.sillasExtraPagado;
                                        final double saldoBaseRestante = montoBase - baseAbonado;
                                        final double saldoMesaRestante = alumno.mesaExtraPrecio - alumno.mesaExtraPagado;
                                        final double saldoSillasRestante = alumno.sillasExtraPrecioTotal - alumno.sillasExtraPagado;

                                        return pw.Column(
                                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                                          children: [
                                            pw.Text(
                                              '· Base: ${montoBase.toCurrency()}  (Resta: ${(saldoBaseRestante > 0.01 ? saldoBaseRestante : 0.0).toCurrency()})',
                                              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _darkText),
                                            ),
                                            if (alumno.mesaExtraPrecio > 0.01) pw.Padding(
                                              padding: const pw.EdgeInsets.only(top: 1),
                                              child: pw.Text('· Mesa Extra: ${alumno.mesaExtraPrecio.toCurrency()}  (Resta: ${(saldoMesaRestante > 0.01 ? saldoMesaRestante : 0.0).toCurrency()})', style: pw.TextStyle(fontSize: 7, color: _greyText)),
                                            ),
                                            if (alumno.sillasExtraPrecioTotal > 0.01) pw.Padding(
                                              padding: const pw.EdgeInsets.only(top: 1),
                                              child: pw.Text('· Sillas Extras: ${alumno.sillasExtraPrecioTotal.toCurrency()}  (Resta: ${(saldoSillasRestante > 0.01 ? saldoSillasRestante : 0.0).toCurrency()})', style: pw.TextStyle(fontSize: 7, color: _greyText)),
                                            ),
                                          ],
                                        );
                                      }),
                                      pw.Padding(
                                        padding: const pw.EdgeInsets.only(top: 3),
                                        child: pw.Text('TOTAL: ${alumno.montoTotalPactado.toCurrency()}', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _darkText)),
                                      ),
                                    ],
                                  ),
                                ),
                                // Columna 2: Cuotas
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                                    children: [
                                      pw.Text(
                                        '${alumno.cuotasPagadas}/${alumno.totalCuotas}',
                                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: alumno.cuotasPagadas >= alumno.totalCuotas ? _greenAccent : _gold),
                                      ),
                                      pw.Text('pagadas', style: pw.TextStyle(fontSize: 6, color: _greyText)),
                                    ],
                                  ),
                                ),
                                // Columna 3: Balance
                                pw.Padding(
                                  padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text('Abonado:', style: pw.TextStyle(fontSize: 6, color: _greyText)),
                                      pw.Text(
                                        (alumno.montoTotalPactado - valSaldo).toCurrency(),
                                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _greenAccent),
                                      ),
                                      pw.SizedBox(height: 3),
                                      pw.Text('Saldo pendiente:', style: pw.TextStyle(fontSize: 6, color: _greyText)),
                                      pw.Text(
                                        valSaldo.toCurrency(),
                                        style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: valSaldo < 0.01
                                              ? _greenAccent
                                              : (now.isAfter(evento.fechaEvento) ? _redAccent : _gold),
                                        ),
                                      ),
                                    ],
                                  ),
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
                            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: _greyText),
                          ),
                        ),

                      pw.Spacer(),
                      
                      // Firmas
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                        children: [
                          pw.Column(children: [
                            pw.Container(width: 120, decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5)))),
                            pw.Text('Firma Pagador', style: pw.TextStyle(fontSize: 8)),
                          ]),
                          pw.Column(children: [
                            pw.Container(width: 120, decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.5)))),
                            pw.Text('Firma Receptor', style: pw.TextStyle(fontSize: 8)),
                          ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    if (!kIsWeb && Platform.isWindows) {
      await _abrirEnWindows(bytes, 'Recibo_${alumno.nombreAlumno.replaceAll(' ', '_')}.pdf');
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Recibo_${alumno.nombreAlumno}.pdf');
    }
  }

  // ── Planilla por Cursos (Para Eventos Masivos) ─────────────────────────
  static Future<void> generarPlanillaCursos(Evento evento, List<ContratoAlumno> alumnos) async {
    // Si no es un evento masivo o no hay alumnos, podríamos abortar, pero asumimos que aquí ya llegamos con data válida.
    final fontRegular = await PdfGoogleFonts.outfitRegular();
    final fontBold = await PdfGoogleFonts.outfitBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    // Agrupar alumnos por curso_division
    final alumnosPorCurso = <String, List<ContratoAlumno>>{};
    for (final alumno in alumnos) {
      // Ignorar alumnos dados de baja
      if (alumno.nombreAlumno.startsWith('[BAJA]')) continue;

      final curso = alumno.cursoDivision?.trim().isNotEmpty == true ? alumno.cursoDivision!.trim() : 'Sin Curso Asignado';
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
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _gold),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'CURSO / DIVISIÓN: $curso',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
              pw.Divider(color: _gold),
              pw.SizedBox(height: 10),
            ]
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: _greyLight),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _darkText, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: _headerBg),
              cellStyle: pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2.5),
              },
              data: <List<String>>[
                <String>['ALUMNO', 'TELÉFONO', 'MESA', 'MÚSICA ELEGIDA', 'ACOMPAÑANTES'],
                ...alumnosDelCurso.map((a) {
                  final acompanantes = a.nombresAcompanantes.join(', ');
                  final musica = a.musicaElegida?.isNotEmpty == true ? a.musicaElegida! : '-';
                  final mesa = a.numeroMesa?.isNotEmpty == true ? a.numeroMesa! : '-';
                  final telefono = a.telefono?.isNotEmpty == true ? a.telefono! : '-';
                  return [a.nombreAlumno, telefono, mesa, musica, acompanantes];
                }),
              ],
            ),
          ],
        ),
      );
    }

    final bytes = await pdf.save();
    
    // Normalizar titulo archivo
    final safeName = (evento.cliente?.nombreCompleto ?? 'Evento').replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');

    if (!kIsWeb && Platform.isWindows) {
      await _abrirEnWindows(bytes, 'Planilla_Cursos_$safeName.pdf');
    } else {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Planilla_Cursos_$safeName.pdf',
      );
    }
  }

  // ── Abrir PDF en Windows guardando en carpeta Documentos ──────────────────
  static Future<void> _abrirEnWindows(Uint8List bytes, String filename) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}\\$filename');
      await file.writeAsBytes(bytes);
      // Abre el PDF con el visor predeterminado de Windows
      await Process.run('cmd', ['/c', 'start', '', file.path]);
      debugPrint('PDF guardado y abierto: ${file.path}');
    } catch (e) {
      debugPrint('Error al abrir PDF en Windows: $e');
      // Fallback: intentar con Printing igual
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: filename,
      );
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

    final totalPresupuesto = servicios.fold<double>(0, (s, i) => s + (i.precioFinalAcordado * i.cantidad));
    final totalPagado = transacciones.fold<double>(0, (s, i) => s + i.monto);

    // Ordenar transacciones: más reciente primero
    final transOrdenadas = List<Transaccion>.from(transacciones)
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

    final now = DateTime.now();
    final fechaEmision = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final fechaEvento = '${evento.fechaEvento.day.toString().padLeft(2, '0')}/${evento.fechaEvento.month.toString().padLeft(2, '0')}/${evento.fechaEvento.year}';

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
              _buildHeader(logoImage, titulo, fechaEmision, evento, fechaEvento),

              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // ── ESTADO DE CUENTA (Unificado) ──────────────────────
                    _buildEstadoCuenta(
                      pagado: totalPagado,
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
                      child: pw.Image(logo, width: 38, height: 38, fit: pw.BoxFit.contain),
                    ),
                  ),
                )
              else
                pw.Text('JE', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: _gold)),
              pw.SizedBox(width: 14),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('JUNIOR EVENTOS',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _darkText, letterSpacing: 2)),
                  pw.Text('Sistema de Gestión Premium',
                      style: pw.TextStyle(fontSize: 8, color: _greyText)),
                ],
              ),
            ],
          ),
          // Título + fecha
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: _gold,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Text(titulo,
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 1)),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Emitido: $fecha', style: pw.TextStyle(fontSize: 9, color: _greyText)),
              pw.SizedBox(height: 4),
              pw.Text(evento.cliente?.nombreCompleto.toUpperCase() ?? 'CLIENTE',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _darkText)),
              pw.Text('${evento.tipoParaMostrar.toUpperCase()}  ·  Fecha evento: $fechaEvento',
                  style: pw.TextStyle(fontSize: 9, color: _greyText)),
            ],
          ),
        ],
      ),
    );
  }

  // ── ESTADO DE CUENTA (Rediseño Élite) ──────────────────────────────────────
  static pw.Widget _buildEstadoCuenta({
    required double pagado,
    required double saldo,
    required DateTime fechaEvento,
    Transaccion? ultimoPago,
    String? etiquetaPago,
  }) {
    final bool esVencido = DateTime.now().isAfter(fechaEvento);
    final PdfColor statusColor = (saldo > 0.01 && esVencido) ? _redAccent : (saldo > 0.01 ? _gold : _greenAccent);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: _cardBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _greyLight, width: 0.5),
      ),
      child: pw.Row(
        children: [
          _resumenItem('MONTO ABONADO', pagado.toCurrency(), _greenAccent),
          _dividerV(),
          if (ultimoPago != null) ...[
            _resumenItem(
              etiquetaPago ?? 'ÚLTIMO PAGO',
              ultimoPago.monto.toCurrency(),
              _greenAccent,
              subtext: ultimoPago.fechaPago != null 
                ? '${ultimoPago.fechaPago!.day}/${ultimoPago.fechaPago!.month}/${ultimoPago.fechaPago!.year}'
                : null
            ),
            _dividerV(),
          ],
          _resumenItem(
            'SALDO A LIQUIDAR',
            saldo.toCurrency(),
            statusColor,
            isHighlight: (saldo > 0.01 && esVencido)
          ),
        ],
      ),
    );
  }

  static pw.Widget _resumenItem(String label, String value, PdfColor color, {String? subtext, bool isHighlight = false}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 7, color: _greyText, letterSpacing: 0.8, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: isHighlight ? _redAccent : color)),
          if (subtext != null)
            pw.Text(subtext, style: pw.TextStyle(fontSize: 7, color: _greyText)),
        ],
      ),
    );
  }

  static pw.Widget _dividerV() {
    return pw.Container(
      height: 30,
      width: 0.5,
      color: _greyLight,
      margin: const pw.EdgeInsets.symmetric(horizontal: 10),
    );
  }

  // ── Tabla de pagos ─────────────────────────────────────────────────────────
  static pw.Widget _buildPagosTable(List<Transaccion> transacciones) {
    return pw.Table(
      border: pw.TableBorder.all(color: _greyLight, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        // Encabezado
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerBg),
          children: [
            _tableHeader('#'),
            _tableHeader('FECHA'),
            _tableHeader('MÉTODO'),
            _tableHeader('MONTO'),
          ],
        ),
        // Filas
        ...transacciones.asMap().entries.map((entry) {
          final i = entry.key;
          final tr = entry.value;
          final isFirst = i == 0;
          final fecha = tr.fechaPago != null
              ? '${tr.fechaPago!.day.toString().padLeft(2, '0')}/${tr.fechaPago!.month.toString().padLeft(2, '0')}/${tr.fechaPago!.year}'
              : '—';
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isFirst ? PdfColor.fromInt(0xFFF0FFF4) : (i.isEven ? PdfColors.white : _cardBg),
            ),
            children: [
              _tableCell('${transacciones.length - i}', bold: isFirst, color: isFirst ? _greenAccent : null),
              _tableCell(fecha, bold: isFirst),
                  _tableCell(tr.concepto ?? 'Pago', bold: isFirst),
              _tableCell(tr.monto.toCurrency(), bold: isFirst, color: isFirst ? _greenAccent : null, align: pw.TextAlign.right),
            ],
          );
        }),
      ],
    );
  }

  // ── Tabla de servicios ─────────────────────────────────────────────────────
  static pw.Widget _buildServiciosTable(List<EventosServicios> servicios, double total) {
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
                decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _cardBg),
                children: [
                   _tableCell(srv.servicio?.nombre ?? 'Servicio'),
                   _tableCell(srv.cantidad.toStringAsFixed(0), align: pw.TextAlign.center),
                   _tableCell(srv.precioFinalAcordado.toCurrency(), align: pw.TextAlign.right),
                   _tableCell((srv.precioFinalAcordado * srv.cantidad).toCurrency(), align: pw.TextAlign.right),
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
              pw.Text('TOTAL PRESUPUESTADO',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _darkText, letterSpacing: 1)),
              pw.Text(total.toCurrency(),
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _gold)),
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
          pw.Text('JUNIOR EVENTOS  ·  EXCELENCIA Y COMPROMISO',
              style: pw.TextStyle(fontSize: 8, color: _greyText, letterSpacing: 1, fontWeight: pw.FontWeight.bold)),
          pw.Text('Gestión personalizada para eventos inolvidables.',
              style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: _greyText)),
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
        pw.Text(text,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2, color: _darkText)),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _darkText, letterSpacing: 0.8)),
    );
  }

  static pw.Widget _tableCell(String text, {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
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
