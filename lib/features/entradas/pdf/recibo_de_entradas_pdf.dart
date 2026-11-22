import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../common/services/ajuste_pdf.dart';
import '../../common/services/emisor_del_recibo.dart';

/// Un renglón del "Concepto:" ("  • 2 × Entrada · $ 10.000 c/u   $ 20.000"),
/// con su nota en gris debajo si hace falta.
class RenglonDelRecibo {
  final String texto;

  /// A la derecha, en negrita. Null: el renglón no lleva monto.
  final String? monto;

  /// Debajo, en gris y cursiva, como los subtextos del recibo de las cuotas.
  final String? nota;

  const RenglonDelRecibo(this.texto, {this.monto, this.nota});
}

/// Lo que dice un papel de entradas armado con la forma del "RECIBO DE PAGO"
/// de las cuotas. Cada papel (la venta, la rendición, el cierre de la caja)
/// decide **qué** dice; [ReciboDeEntradasPdf] decide **cómo** se ve.
class ContenidoDelRecibo {
  /// Arriba a la derecha, en negrita: "RECIBO DE PAGO", "RECIBO DE CAJA".
  final String titulo;

  /// Debajo del título, en gris: "N° 0017", "Entradas · Carla".
  final String bajoElTitulo;

  /// Reimpreso: va COPIA debajo del número.
  final bool copia;

  /// "Fecha: 14/11/2026 11:32 hs".
  final String fecha;

  /// Debajo de la fecha, en gris ("Abierta: … · Cerrada: …"). Null: nada.
  final String? debajoDeLaFecha;

  /// "Recibí de: GOMEZ, CARLA": el nombre en negrita y en mayúsculas.
  final String recibiDe;

  /// Al lado del nombre, en gris (" · DNI 30111222"). Null: nada.
  final String? alLadoDelNombre;

  /// "La suma de pesos: SESENTA MIL PESOS": en letras y en cursiva.
  final String sumaEnLetras;

  /// Al lado de "Concepto:" ("Entradas · INSTITUTO … · fiesta 04/12/2026").
  final String concepto;

  /// Debajo del concepto, antes de los renglones ("Familia: … · mesa 14").
  final List<String> debajoDelConcepto;

  final List<RenglonDelRecibo> renglones;

  /// Debajo de los renglones, en gris y cursiva ("10 entradas · Talonario: …").
  final List<String> notas;

  /// El monto de "TOTAL DE ESTE RECIBO".
  final String total;

  /// Adentro del recuadro del total, en gris ("Medio de pago: Efectivo").
  final List<String> enElTotal;

  /// Debajo del recuadro, en gris ("Vendió: Romi").
  final List<String> pie;

  /// Al final, en rojo y negrita (ANULADA, lo anulado después del cierre).
  final List<String> enRojo;

  /// Cruzado sobre la hoja, en rojo claro ("ANULADA"). Null: nada.
  final String? marcaDeAgua;

  const ContenidoDelRecibo({
    required this.titulo,
    required this.bajoElTitulo,
    this.copia = false,
    required this.fecha,
    this.debajoDeLaFecha,
    required this.recibiDe,
    this.alLadoDelNombre,
    required this.sumaEnLetras,
    required this.concepto,
    this.debajoDelConcepto = const [],
    required this.renglones,
    this.notas = const [],
    required this.total,
    this.enElTotal = const [],
    this.pie = const [],
    this.enRojo = const [],
    this.marcaDeAgua,
  });
}

/// Los papeles de entradas **con la forma del recibo de las cuotas**
/// (`PdfService.generarReciboAlumno`), tal cual (el usuario, 22-nov-2026:
/// "hacelo como un recibo tal cual"; imprime en media hoja A4 y esos recibos
/// salen perfectos): el logo y el dueño arriba a la izquierda, el título y el
/// número a la derecha, "Fecha", "Recibí de", "La suma de pesos", "Concepto:"
/// con sus renglones, el recuadro "TOTAL DE ESTE RECIBO" y el pie en gris.
///
/// **La hoja es media A4 y nunca recorta:** el ancho de una A4 con el alto
/// libre y un piso de media hoja. Lo común entra justo en media hoja (595 ×
/// 421 pt); si no entra, primero se junta el aire y después se achica la letra
/// con piso, como el recibo de las cuotas ([AjustePdf]); y si ni así, la hoja
/// crece: nunca se pierde un renglón. **Nunca se esconde un dato para que
/// entre** (de [AjustePdf] se usan solo la letra y el aire).
class ReciboDeEntradasPdf {
  ReciboDeEntradasPdf._();

  /// Los colores del recibo de las cuotas.
  static const oscuro = PdfColor.fromInt(0xFF2C3E50);
  static const gris = PdfColor.fromInt(0xFF7F8C8D);
  static const fondo = PdfColor.fromInt(0xFFF9F9F9);
  static const grisClaro = PdfColor.fromInt(0xFFE0E0E0);
  static const rojo = PdfColor.fromInt(0xFFE74C3C);

  /// A los costados, como el recibo de las cuotas.
  static const double costado = 22;

  /// El ancho de una A4 y el alto libre: la hoja mide lo que mide lo escrito,
  /// con un piso de [mediaA4].
  static PdfPageFormat get formato =>
      PdfPageFormat(PdfPageFormat.a4.width, double.infinity);

  /// Media hoja A4, para cortar dos por hoja.
  static double get mediaA4 => PdfPageFormat.a4.height / 2;

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    ContenidoDelRecibo c, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final tema = fuentes == null
        ? null
        : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2);
    // La letra de fábrica del paquete no tiene el "•": sin las Outfit va un
    // guion, que sí tiene (si no, sale un hueco donde va la viñeta).
    final vineta = fuentes == null ? '-' : '•';

    // Como el recibo de las cuotas: se mide y se prueba de menos a más
    // invasivo hasta que entre en media hoja. Cada medición arma el cuerpo de
    // nuevo (los widgets del paquete guardan su layout).
    var ajuste = AjustePdf.intacto;
    for (final a in AjustePdf.escalera) {
      ajuste = a;
      try {
        final alto = await _medirAlto(tema, _cuerpo(c, a, logo, vineta));
        if (alto <= mediaA4 + 0.5) break;
      } catch (_) {
        // Si la medición falla, el papel sale igual con este nivel: la hoja
        // crece si hace falta, nunca recorta.
        break;
      }
    }

    final doc = pw.Document(theme: tema);
    doc.addPage(
      pw.Page(
        pageFormat: formato,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          final cuerpo = _cuerpo(c, ajuste, logo, vineta);
          final marca = c.marcaDeAgua;
          if (marca == null) return cuerpo;
          return pw.Stack(
            children: [
              cuerpo,
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Transform.rotate(
                    angle: math.pi / 9,
                    child: pw.Opacity(
                      opacity: 0.22,
                      child: pw.Text(
                        marca,
                        style: pw.TextStyle(
                          fontSize: 64,
                          fontWeight: pw.FontWeight.bold,
                          color: rojo,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// Cuánto ocupa [contenido], en puntos: una hoja de alto libre mide lo que
  /// mide lo escrito.
  static Future<double> _medirAlto(pw.ThemeData? tema, pw.Widget contenido) async {
    final doc = pw.Document(theme: tema);
    doc.addPage(
      pw.Page(
        pageFormat: formato,
        margin: pw.EdgeInsets.zero,
        build: (_) => contenido,
      ),
    );
    await doc.save();
    return doc.document.pdfPageList.pages.first.pageFormat.height;
  }

  static pw.Widget _cuerpo(
    ContenidoDelRecibo c,
    AjustePdf d,
    pw.ImageProvider? logo,
    String vineta,
  ) {
    pw.TextStyle grisChico({bool cursiva = false}) => pw.TextStyle(
          fontSize: d.fs(8, piso: 6.5),
          color: gris,
          fontStyle: cursiva ? pw.FontStyle.italic : pw.FontStyle.normal,
        );

    pw.Widget renglon(RenglonDelRecibo r) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Lo de la izquierda puede ser largo: en Expanded baja de renglón
            // en vez de salirse de la hoja.
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    '  $vineta ${r.texto}',
                    style: pw.TextStyle(fontSize: d.fs(10)),
                  ),
                ),
                if (r.monto != null) ...[
                  pw.SizedBox(width: 10),
                  pw.Text(
                    r.monto!,
                    style: pw.TextStyle(
                      fontSize: d.fs(10),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            if (r.nota != null && r.nota!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12),
                child: pw.Text(r.nota!, style: grisChico(cursiva: true)),
              ),
          ],
        );

    return pw.ConstrainedBox(
      constraints: pw.BoxConstraints(minHeight: mediaA4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: grisClaro, width: 0.5),
              ),
            ),
            padding: pw.EdgeInsets.fromLTRB(costado, d.sp(8), costado, d.sp(16)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // El encabezado: el logo y el dueño a la izquierda; el título,
                // el número y la COPIA a la derecha.
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null)
                      pw.Container(
                        height: d.fs(30, piso: 20),
                        margin: const pw.EdgeInsets.only(right: 12),
                        child: pw.Image(logo),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            EmisorDelRecibo.nombre,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: d.fs(10),
                              color: oscuro,
                            ),
                          ),
                          pw.Text(EmisorDelRecibo.cargo, style: grisChico()),
                          pw.Text(EmisorDelRecibo.cuit, style: grisChico()),
                          pw.Text(EmisorDelRecibo.condicion, style: grisChico()),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          c.titulo,
                          style: pw.TextStyle(
                            fontSize: d.fs(13, piso: 10),
                            fontWeight: pw.FontWeight.bold,
                            color: oscuro,
                          ),
                        ),
                        pw.Text(c.bajoElTitulo, style: grisChico()),
                        if (c.copia)
                          pw.Container(
                            margin: pw.EdgeInsets.only(top: d.sp(3)),
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: gris, width: 0.8),
                            ),
                            child: pw.Text(
                              'COPIA',
                              style: pw.TextStyle(
                                fontSize: d.fs(8, piso: 6.5),
                                fontWeight: pw.FontWeight.bold,
                                color: oscuro,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: d.sp(4)),

                // El cuerpo: "recibí de X la suma de Y"; el total va al pie.
                pw.Text('Fecha: ${c.fecha}', style: pw.TextStyle(fontSize: d.fs(10))),
                if (c.debajoDeLaFecha != null)
                  pw.Text(c.debajoDeLaFecha!, style: grisChico()),
                pw.SizedBox(height: d.sp(3)),
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'Recibí de: ',
                        style: pw.TextStyle(fontSize: d.fs(10)),
                      ),
                      pw.TextSpan(
                        text: c.recibiDe.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: d.fs(10),
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (c.alLadoDelNombre != null)
                        pw.TextSpan(
                          text: c.alLadoDelNombre,
                          style: pw.TextStyle(fontSize: d.fs(9), color: gris),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: d.sp(2)),
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'La suma de pesos: ',
                        style: pw.TextStyle(fontSize: d.fs(10)),
                      ),
                      pw.TextSpan(
                        text: c.sumaEnLetras,
                        style: pw.TextStyle(
                          fontSize: d.fs(9),
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: d.sp(3)),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Concepto:',
                      style: pw.TextStyle(
                        fontSize: d.fs(10),
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Text(c.concepto, style: pw.TextStyle(fontSize: d.fs(10))),
                    ),
                  ],
                ),
                for (final t in c.debajoDelConcepto)
                  pw.Text(t, style: pw.TextStyle(fontSize: d.fs(10))),
                pw.SizedBox(height: d.sp(2)),
                for (final r in c.renglones) renglon(r),
                for (final t in c.notas)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 12),
                    child: pw.Text(t, style: grisChico(cursiva: true)),
                  ),

                // El recuadro del total: el importe se dice una sola vez, acá
                // abajo, junto al medio de pago.
                pw.Container(
                  width: double.infinity,
                  margin: pw.EdgeInsets.only(top: d.sp(5), bottom: d.sp(3)),
                  padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: d.sp(6)),
                  decoration: pw.BoxDecoration(
                    color: fondo,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: grisClaro, width: 0.5),
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
                              fontSize: d.fs(9),
                              fontWeight: pw.FontWeight.bold,
                              color: gris,
                              letterSpacing: 0.6,
                            ),
                          ),
                          pw.Text(
                            c.total,
                            style: pw.TextStyle(
                              fontSize: d.fs(14, piso: 11),
                              fontWeight: pw.FontWeight.bold,
                              color: oscuro,
                            ),
                          ),
                        ],
                      ),
                      for (final t in c.enElTotal) pw.Text(t, style: grisChico()),
                    ],
                  ),
                ),
                for (final t in c.pie) pw.Text(t, style: grisChico()),
                for (final t in c.enRojo)
                  pw.Padding(
                    padding: pw.EdgeInsets.only(top: d.sp(4)),
                    child: pw.Text(
                      t,
                      style: pw.TextStyle(
                        fontSize: d.fs(9),
                        fontWeight: pw.FontWeight.bold,
                        color: rojo,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
