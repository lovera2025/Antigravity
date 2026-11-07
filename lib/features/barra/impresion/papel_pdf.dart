import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ticket_esc_pos.dart';

/// Un papel de la barra como PDF de **58 mm de ancho**, como el de la térmica, en una
/// sola hoja tan larga como haga falta (pedido del usuario, 7-nov: "A4 es muy grande; si
/// tiene que ser largo que sea"). Lo mismo que sale por la impresora, de la misma lista de
/// líneas: lo grande en grande, los renglones a dos columnas, las rayas.
///
/// Sin logo ni QR: nada de la barra los lleva.
abstract final class PapelPdf {
  /// El ancho del papel.
  static const ancho = 58 * PdfPageFormat.mm;
  static const _margen = 3 * PdfPageFormat.mm;

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas, la letra
  /// de fábrica del paquete (sin acentos raros, pero otra forma).
  static Future<Uint8List> armar(
    List<LineaTicket> lineas, {
    required String titulo,
    (pw.Font, pw.Font)? fuentes,
  }) async {
    final doc = pw.Document(title: titulo, author: 'Junior Eventos');
    final tema = fuentes == null
        ? pw.ThemeData.base()
        : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2);
    doc.addPage(pw.Page(
      theme: tema,
      // Alto infinito: la hoja mide lo que mide lo escrito.
      pageFormat: const PdfPageFormat(ancho, double.infinity, marginAll: _margen),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [for (final l in lineas) _linea(l)],
      ),
    ));
    return doc.save();
  }

  static const _chica = 7.5;
  static const _grande = 13.0;

  static pw.Widget _linea(LineaTicket l) => switch (l) {
        TituloTicket() => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              l.texto,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: _grande, fontWeight: pw.FontWeight.bold),
            ),
          ),
        TextoTicket() => pw.Text(
            l.texto,
            textAlign: l.centrado ? pw.TextAlign.center : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: _chica,
              fontWeight: l.negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        GrandeTicket() => pw.Text(
            l.texto,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: l.soloAlto ? _chica * 1.5 : _grande,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        RenglonTicket() => pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  l.izquierda,
                  style: pw.TextStyle(
                    fontSize: _chica,
                    fontWeight: l.negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
              if (l.derecha.trim().isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 4),
                  child: pw.Text(
                    l.derecha,
                    style: pw.TextStyle(
                      fontSize: _chica,
                      fontWeight: l.negrita ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
        SeparadorTicket() => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
          ),
        // Ningún papel de la barra los lleva hoy; si alguno volviera, no se pierde.
        QrTicket() => pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: l.dato,
              width: 25 * PdfPageFormat.mm,
              height: 25 * PdfPageFormat.mm,
            ),
          ),
        LogoTicket() => pw.SizedBox(),
      };
}
