import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Estilo común de las planillas nuevas: la del sorteo y las que vengan (plano
/// A4, entrega de entradas, lista de emergencia de la puerta).
///
/// Las planillas que ya existen (caja, mora, cobros, contratos) **no** lo usan
/// y no se tocan sin que el usuario lo pida.
///
/// Dos reglas mandan:
/// - **El color es acento y nunca el único dato.** Cada marca de color lleva su
///   palabra ("AVISAR", "sin mesa", "Pendiente"), así que [blancoYNegro] solo
///   saca los rellenos: la planilla se lee igual.
/// - **Cuerpo de [cuerpo] pt como mínimo**, porque también se manda por WhatsApp
///   y se lee en el celular.
class PlanillaTema {
  final bool blancoYNegro;

  const PlanillaTema({this.blancoYNegro = false});

  static const double cuerpo = 9;
  static const double secundario = 8;
  static const double margen = 20;

  /// Dorado de la marca, un tono más oscuro que el de pantalla para que se lea
  /// impreso.
  PdfColor get acento =>
      blancoYNegro ? PdfColors.black : const PdfColor.fromInt(0xFFB08A2E);

  PdfColor get texto => const PdfColor.fromInt(0xFF1F2328);

  PdfColor get textoSuave => blancoYNegro
      ? const PdfColor.fromInt(0xFF3A3A3A)
      : const PdfColor.fromInt(0xFF5C6370);

  PdfColor get linea => blancoYNegro
      ? const PdfColor.fromInt(0xFF8C8C8C)
      : const PdfColor.fromInt(0xFFD6DAE0);

  PdfColor get fondoEncabezadoTabla => blancoYNegro
      ? const PdfColor.fromInt(0xFFE4E4E4)
      : const PdfColor.fromInt(0xFFEEF0F3);

  PdfColor? get filaAlterna =>
      blancoYNegro ? null : const PdfColor.fromInt(0xFFF8F9FB);

  /// La mesa principal, como en el Excel del jefe.
  PdfColor? get verdeMesa =>
      blancoYNegro ? null : const PdfColor.fromInt(0xFFDDF2E3);

  /// No tiene mesa.
  PdfColor? get rojoSinMesa =>
      blancoYNegro ? null : const PdfColor.fromInt(0xFFFBE1E1);

  PdfColor get naranja =>
      blancoYNegro ? PdfColors.black : const PdfColor.fromInt(0xFFC8741F);

  PdfColor get verde =>
      blancoYNegro ? PdfColors.black : const PdfColor.fromInt(0xFF2A8C52);

  PdfColor get rojo =>
      blancoYNegro ? PdfColors.black : const PdfColor.fromInt(0xFFB3261E);

  pw.TextStyle estilo({
    double size = cuerpo,
    bool negrita = false,
    PdfColor? color,
    double? espaciado,
  }) =>
      pw.TextStyle(
        fontSize: size,
        fontWeight: negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? texto,
        letterSpacing: espaciado,
      );

  /// Encabezado de cada hoja: barra de acento, título, institución, y a la
  /// derecha la versión y cuándo se generó. [control] es la línea de totales.
  pw.Widget encabezado({
    required String titulo,
    required String institucion,
    required String version,
    required String generada,
    String? control,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 3, color: acento),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    titulo.toUpperCase(),
                    style: estilo(
                      size: secundario,
                      negrita: true,
                      color: acento,
                      espaciado: 1.6,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(institucion, style: estilo(size: 15, negrita: true)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  version.toUpperCase(),
                  style: estilo(
                    size: secundario,
                    negrita: true,
                    color: textoSuave,
                    espaciado: 1.2,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  generada,
                  style: estilo(size: secundario, color: textoSuave),
                ),
              ],
            ),
          ],
        ),
        if (control != null) ...[
          pw.SizedBox(height: 3),
          pw.Text(control, style: estilo(size: cuerpo, color: textoSuave)),
        ],
        pw.SizedBox(height: 4),
        pw.Container(height: 0.6, color: linea),
        pw.SizedBox(height: 6),
      ],
    );
  }

  /// Pie de cada hoja: la leyenda de las marcas y la numeración.
  ///
  /// [paginacion] la arma quien llama ("5° A · hoja 1 de 2"): `pagesCount` del
  /// contexto solo cuenta las hojas que ya se armaron, y en un documento con
  /// varias secciones daba "Página 2 de 1".
  pw.Widget pie({
    required List<(PdfColor?, String)> leyenda,
    required String paginacion,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                for (final (color, texto) in leyenda)
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      if (color != null) ...[
                        pw.Container(
                          width: 7,
                          height: 7,
                          decoration: pw.BoxDecoration(
                            color: color,
                            border: pw.Border.all(color: linea, width: 0.4),
                          ),
                        ),
                        pw.SizedBox(width: 3),
                      ],
                      pw.Text(
                        texto,
                        style: estilo(size: 7.5, color: textoSuave),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          pw.Text(paginacion, style: estilo(size: 7.5, color: textoSuave)),
        ],
      ),
    );
  }

  /// Celda de encabezado de tabla.
  pw.Widget celdaTitulo(String texto, {pw.TextAlign align = pw.TextAlign.left}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          texto.toUpperCase(),
          textAlign: align,
          style: estilo(size: 7.5, negrita: true, espaciado: 0.6),
        ),
      );

  /// Bordes de las tablas: solo líneas horizontales finas.
  pw.TableBorder get bordeTabla => pw.TableBorder(
        top: pw.BorderSide(color: linea, width: 0.6),
        bottom: pw.BorderSide(color: linea, width: 0.6),
        horizontalInside: pw.BorderSide(color: linea, width: 0.4),
      );

  /// Un número grande con su rótulo, para la hoja de resumen.
  pw.Widget tarjeta(String rotulo, String valor, {String? detalle}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: linea, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            rotulo.toUpperCase(),
            style: estilo(size: 7, negrita: true, color: textoSuave, espaciado: 0.8),
          ),
          pw.SizedBox(height: 2),
          pw.Text(valor, style: estilo(size: 16, negrita: true)),
          if (detalle != null)
            pw.Text(detalle, style: estilo(size: 7.5, color: textoSuave)),
        ],
      ),
    );
  }
}
