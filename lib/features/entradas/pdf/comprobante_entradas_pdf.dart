import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../../models/entradas_retiro.dart';
import '../../barra/cuentas/pesos.dart';
import '../datos/entradas_repositorio.dart';

/// Lo que lleva el comprobante de una venta de entradas, además de la venta.
class DatosDelComprobante {
  final VentaEntradas venta;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  /// Si compra una familia de la fiesta: el alumno y su mesa ("14 y 15").
  final String? alumno;
  final String? mesa;

  /// Reimpreso: dice COPIA.
  final bool copia;

  /// Anulada: va ANULADA cruzado, con el motivo.
  final AnulacionEntradas? anulacion;

  const DatosDelComprobante({
    required this.venta,
    required this.fiesta,
    this.fechaFiesta,
    this.alumno,
    this.mesa,
    this.copia = false,
    this.anulacion,
  });
}

/// El comprobante de una venta de entradas: **media hoja A4**, con las pulseras
/// y los números del talonario (sección 7.4 del spec del 13-nov).
///
/// Todo lo que dice sale de la venta como quedó guardada: no hace ninguna
/// cuenta (el total, el recargo y el vuelto ya están en la fila).
class ComprobanteEntradasPdf {
  ComprobanteEntradasPdf._();

  /// Media A4, para cortar dos por hoja.
  static PdfPageFormat get hoja => PdfPageFormat(
        PdfPageFormat.a4.width,
        PdfPageFormat.a4.height / 2,
        marginAll: 26,
      );

  static String numero(VentaEntradas v) =>
      'N° ${v.numero.toString().padLeft(4, '0')}';

  /// "14/11/2026 11:32 hs", en hora de Argentina. Vacío si no se entiende.
  static String cuando(String iso) {
    final t = DateTime.tryParse(iso);
    return t == null
        ? ''
        : '${ArTime.formatFechaCorta(t)} ${ArTime.formatHora(t)}';
  }

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String _pct(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',');

  /// Lo que dice un renglón a la izquierda: "8 × Entrada · $ 10.000 c/u".
  static String renglon(RenglonEntradas r) {
    final descuento = r.tipo == TipoRenglonEntradas.suelta && r.descuentoPct > 0
        ? ' · descuento ${_pct(r.descuentoPct)} %'
        : '';
    return '${r.cantidad} × ${r.nombre} · ${pesos(r.precio)} c/u$descuento';
  }

  /// Cómo pagó, en palabras. En el mixto, cuánto de cada uno.
  static String comoPago(VentaEntradas v) => switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transferencia',
        MedioBarra.mixto =>
          'Mixto · efectivo ${pesos(v.efectivo)} · transferencia ${pesos(v.transferencia)}',
        MedioBarra.otro => '—',
      };

  /// Los números del talonario, o null si no se anotaron.
  static String? talonario(VentaEntradas v) {
    final tramos = TramoTalonario.deTexto(v.numeros);
    return tramos.isEmpty ? null : TramoTalonario.legible(tramos);
  }

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDelComprobante d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final v = d.venta;
    final doc = pw.Document(
      theme: fuentes == null
          ? null
          : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2),
    );
    const gris = PdfColor.fromInt(0xFF555555);
    const linea = PdfColor.fromInt(0xFF999999);
    final chico = pw.TextStyle(fontSize: 8.5, color: gris);
    final normal = const pw.TextStyle(fontSize: 9.5);
    final fuerte = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

    // Lo de la izquierda puede ser largo: va en Expanded para que baje de
    // renglón en vez de salirse de la hoja.
    pw.Widget fila(String a, String b, {pw.TextStyle? estilo}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Text(a, style: estilo ?? normal)),
              pw.SizedBox(width: 10),
              pw.Text(b, style: estilo ?? fuerte),
            ],
          ),
        );
    pw.Widget raya() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 5),
          height: 0.6,
          color: linea,
        );

    final numeros = talonario(v);
    final cuerpo = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 26, height: 26),
              pw.SizedBox(width: 8),
            ],
            pw.Expanded(
              child: pw.Text(
                d.fiesta.toUpperCase(),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (d.fechaFiesta != null)
              pw.Text('Fiesta: ${_dia(d.fechaFiesta!)}', style: normal),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                'COMPROBANTE DE ENTRADAS · ${numero(v)}',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (d.copia)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                margin: const pw.EdgeInsets.only(right: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: gris, width: 0.8),
                ),
                child: pw.Text('COPIA', style: fuerte),
              ),
            pw.Text(cuando(v.createdAt), style: normal),
          ],
        ),
        if ((v.hechoPor ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Vendió: ${v.hechoPor}', style: chico),
          ),
        raya(),
        fila(
          'Compra',
          v.compradorDni == null
              ? v.compradorNombre
              : '${v.compradorNombre} · DNI ${v.compradorDni}',
        ),
        if ((d.alumno ?? '').isNotEmpty)
          fila(
            'Familia',
            (d.mesa ?? '').isEmpty ? d.alumno! : '${d.alumno} · mesa ${d.mesa}',
          ),
        raya(),
        for (final r in v.renglones) fila(renglon(r), pesos(r.subtotal)),
        if (v.renglones.isEmpty)
          fila('${v.cantidad} entradas', pesos(v.total)),
        if (v.recargo > 0)
          fila(
            v.recargoPct == null
                ? 'Recargo por transferencia'
                : 'Recargo por transferencia (${_pct(v.recargoPct!)} %)',
            pesos(v.recargo),
          ),
        raya(),
        fila(
          'TOTAL',
          pesos(v.cobrado),
          estilo: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        fila('Pagó', comoPago(v)),
        if (v.recibe != null && v.vuelto > 0)
          fila('Entregó ${pesos(v.recibe!)}', 'Vuelto ${pesos(v.vuelto)}'),
        raya(),
        fila('Pulseras normales', '${v.cantidad}'),
        numeros == null
            ? pw.Text('Sin números del talonario anotados', style: chico)
            : fila('Talonario', numeros),
        if (d.anulacion != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              'ANULADA el ${cuando(d.anulacion!.createdAt)}'
              '${(d.anulacion!.hechoPor ?? '').isEmpty ? '' : ' por ${d.anulacion!.hechoPor}'}'
              ' · ${d.anulacion!.motivo} · '
              '${d.anulacion!.devueltas ? 'devolvieron las entradas y pulseras' : 'NO devolvieron las entradas'}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
      ],
    );

    doc.addPage(
      pw.Page(
        pageFormat: hoja,
        build: (_) => d.anulacion == null
            ? cuerpo
            : pw.Stack(
                children: [
                  cuerpo,
                  pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Transform.rotate(
                        angle: math.pi / 9,
                        child: pw.Opacity(
                          opacity: 0.22,
                          child: pw.Text(
                            'ANULADA',
                            style: pw.TextStyle(
                              fontSize: 64,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
    return doc.save();
  }

  /// Cómo se llama el archivo.
  static String nombreDelArchivo(DatosDelComprobante d) {
    final limpio = d.venta.compradorNombre
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'Entradas_${d.venta.numero.toString().padLeft(4, '0')}_$limpio.pdf';
  }
}
