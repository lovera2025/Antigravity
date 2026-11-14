import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/ar_time.dart';
import '../../barra/cuentas/pesos.dart';
import '../cuentas/historial_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import 'comprobante_entradas_pdf.dart';

/// Lo que lleva el historial de ventas impreso.
class DatosDelHistorial {
  final HistorialDeEntradas historial;
  final String fiesta;
  final DateTime? fechaFiesta;

  /// "Todas las cajas", o "La caja de Carla".
  final String alcance;
  final DateTime emitido;

  const DatosDelHistorial({
    required this.historial,
    required this.fiesta,
    this.fechaFiesta,
    required this.alcance,
    required this.emitido,
  });
}

/// El historial de ventas de entradas de una fiesta, en A4 (sección 8 del spec
/// del 13-nov): todas las ventas con la tilde de "Pago verificado" en cada
/// renglón, las anuladas tachadas con su motivo, y los totales abajo.
///
/// La tabla va como hija directa del `MultiPage`, así se parte entre hojas; y
/// lo que puede ser largo (el comprador) baja de renglón en su columna.
class HistorialEntradasPdf {
  HistorialEntradasPdf._();

  static PdfPageFormat get hoja => PdfPageFormat.a4.copyWith(
        marginLeft: 28,
        marginRight: 28,
        marginTop: 26,
        marginBottom: 26,
      );

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  static String _medio(VentaEntradas v) => switch (v.medio) {
        MedioBarra.efectivo => 'Efectivo',
        MedioBarra.transferencia => 'Transferencia',
        MedioBarra.mixto => 'Mixto',
        MedioBarra.otro => '—',
      };

  /// La casilla de "Pago verificado": dibujada, no escrita (la letra de la app
  /// no trae el signo de la tilde).
  static pw.Widget _tilde(bool si) => pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.8),
        ),
        child: !si
            ? null
            : pw.CustomPaint(
                size: const PdfPoint(9, 9),
                painter: (canvas, size) {
                  canvas
                    ..setStrokeColor(PdfColors.black)
                    ..setLineWidth(1.3)
                    ..moveTo(1.8, 4.6)
                    ..lineTo(3.8, 2.2)
                    ..lineTo(7.4, 7.2)
                    ..strokePath();
                },
              ),
      );

  static Future<Uint8List> armar(
    DatosDelHistorial d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final h = d.historial;
    final t = h.totales;
    final doc = pw.Document(
      theme: fuentes == null
          ? null
          : pw.ThemeData.withFont(base: fuentes.$1, bold: fuentes.$2),
    );
    const gris = PdfColor.fromInt(0xFF555555);
    const linea = PdfColor.fromInt(0xFF999999);
    final chico = pw.TextStyle(fontSize: 8, color: gris);
    const normal = pw.TextStyle(fontSize: 8.5);
    final fuerte = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);
    final cabeza = pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: gris,
    );

    pw.Widget celda(String texto,
            {pw.TextStyle? estilo, bool derecha = false, bool tachada = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: pw.Text(
            texto,
            textAlign: derecha ? pw.TextAlign.right : pw.TextAlign.left,
            style: (estilo ?? normal).copyWith(
              decoration: tachada ? pw.TextDecoration.lineThrough : null,
              color: tachada ? gris : null,
            ),
          ),
        );

    // En el papel, en el orden en que se vendieron.
    final enOrden = h.ventas.reversed.toList();
    final anuladas = [for (final v in enOrden) if (v.anulada) v];

    pw.Widget total(String a, String b, {bool grande = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(child: pw.Text(a, style: grande ? fuerte : normal)),
              pw.SizedBox(width: 10),
              pw.Text(b, style: fuerte),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: hoja,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Hoja ${context.pageNumber} de ${context.pagesCount}',
            style: chico,
          ),
        ),
        build: (_) => [
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
                pw.Text(
                  'Fiesta: ${_dia(d.fechaFiesta!)}',
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'HISTORIAL DE VENTAS DE ENTRADAS · ${d.alcance}',
                  style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text(
                'Emitido: ${ArTime.formatFechaCorta(d.emitido)} '
                '${ArTime.formatHora(d.emitido)}',
                style: chico,
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          if (enOrden.isEmpty)
            pw.Text('Todavía no hay ventas.', style: normal)
          else
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: linea, width: 0.4),
                bottom: pw.BorderSide(color: linea, width: 0.4),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.1),
                1: pw.FlexColumnWidth(2.1),
                2: pw.FlexColumnWidth(3.6),
                3: pw.FlexColumnWidth(0.9),
                4: pw.FlexColumnWidth(1.7),
                5: pw.FlexColumnWidth(1.9),
                6: pw.FlexColumnWidth(1.6),
                7: pw.FlexColumnWidth(1.3),
              },
              children: [
                pw.TableRow(
                  repeat: true,
                  children: [
                    celda('N°', estilo: cabeza),
                    celda('CUÁNDO', estilo: cabeza),
                    celda('COMPRADOR', estilo: cabeza),
                    celda('CANT.', estilo: cabeza, derecha: true),
                    celda('TOTAL', estilo: cabeza, derecha: true),
                    celda('PAGÓ', estilo: cabeza),
                    celda('VENDIÓ', estilo: cabeza),
                    celda('VERIF.', estilo: cabeza),
                  ],
                ),
                for (final v in enOrden)
                  pw.TableRow(
                    children: [
                      celda(v.venta.numero.toString().padLeft(4, '0'),
                          tachada: v.anulada),
                      celda(ComprobanteEntradasPdf.cuando(v.venta.createdAt),
                          tachada: v.anulada),
                      celda(v.venta.compradorNombre, tachada: v.anulada),
                      celda('${v.venta.cantidad}', derecha: true, tachada: v.anulada),
                      celda(pesos(v.venta.cobrado),
                          estilo: fuerte, derecha: true, tachada: v.anulada),
                      celda(_medio(v.venta), tachada: v.anulada),
                      celda(v.vendio, tachada: v.anulada),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(3),
                        child: v.anulada
                            ? pw.Text('Anulada', style: fuerte.copyWith(fontSize: 7))
                            : pw.Align(
                                alignment: pw.Alignment.centerLeft,
                                child: _tilde(v.verificada),
                              ),
                      ),
                    ],
                  ),
              ],
            ),
          if (anuladas.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('ANULADAS', style: cabeza),
            for (final v in anuladas)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  '${ComprobanteEntradasPdf.numero(v.venta)} · ${v.venta.compradorNombre} · '
                  '${v.anulacion!.motivo} · '
                  '${v.anulacion!.devueltas ? 'devolvieron las entradas y pulseras' : 'NO devolvieron las entradas'}'
                  '${(v.anulacion!.hechoPor ?? '').isEmpty ? '' : ' · anuló ${v.anulacion!.hechoPor}'}',
                  style: normal,
                ),
              ),
          ],
          pw.SizedBox(height: 10),
          pw.Container(height: 0.8, color: linea),
          pw.SizedBox(height: 4),
          total(
            'Entradas vendidas: ${t.entradas} (${t.sueltas} sueltas y ${t.deLugar} '
            'de lugares adicionales${t.otras > 0 ? ', ${t.otras} otras' : ''})',
            pesos(t.vendido),
            grande: true,
          ),
          total('Efectivo', pesos(t.efectivo)),
          total('Transferencia (con los recargos)', pesos(t.transferencia)),
          if (t.recargos > 0) total('Recargos por transferencia', pesos(t.recargos)),
          if (t.descuentos > 0)
            total('Descuentos a mano (${t.conDescuento})', pesos(t.descuentos)),
          total('Total cobrado', pesos(t.total), grande: true),
          total('Ventas', '${t.ventas}'),
          if (t.anuladas > 0) total('Anuladas (no cuentan)', '${t.anuladas}'),
          total(
            'Pago verificado',
            '${h.verificadas} de ${h.verificadas + h.sinVerificar}',
          ),
          for (final r in h.repetidos)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 3),
              child: pw.Text(r.texto, style: fuerte),
            ),
        ],
      ),
    );
    return doc.save();
  }

  static String nombreDelArchivo(DatosDelHistorial d) {
    final limpio = d.fiesta
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'Ventas_de_entradas_$limpio.pdf';
  }
}
