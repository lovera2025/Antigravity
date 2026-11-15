import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../barra/cuentas/cierre_de_barra.dart' show diferenciaEnPalabras;
import '../../barra/cuentas/pesos.dart';
import '../cuentas/cierre_de_entradas.dart';
import '../datos/entradas_repositorio.dart';
import 'comprobante_entradas_pdf.dart';

/// Lo que lleva el papel del cierre de una caja de entradas.
class DatosDelCierreDeEntradas {
  /// La caja como quedó guardada al cerrar (lo contado y la diferencia salen de
  /// acá: no se vuelven a calcular).
  final CajaEntradas caja;
  final CierreDeEntradas cuentas;

  /// La escuela (la institución de la fiesta).
  final String fiesta;
  final DateTime? fechaFiesta;

  const DatosDelCierreDeEntradas({
    required this.caja,
    required this.cuentas,
    required this.fiesta,
    this.fechaFiesta,
  });
}

/// El papel del cierre de una caja de entradas (sección 9.1 del spec del
/// 13-nov): **media hoja A4**, una sola, como el comprobante. La fiesta, quién,
/// cuándo abrió y cerró, y las cuentas de la caja.
///
/// No hace ninguna cuenta propia: lo vendido sale de [CierreDeEntradas] y lo
/// contado y la diferencia, de la caja como se guardó al cerrar.
class CierreCajaEntradasPdf {
  CierreCajaEntradasPdf._();

  static PdfPageFormat get hoja => ComprobanteEntradasPdf.hoja;

  static String _dia(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  /// "Entradas vendidas: 26 (14 sueltas y 12 de lugares adicionales)".
  static String vendidas(CierreDeEntradas c) =>
      'Entradas vendidas: ${c.entradas} (${c.sueltas} sueltas y ${c.deLugar} de '
      'lugares adicionales${c.otras > 0 ? ', ${c.otras} otras' : ''})';

  /// [fuentes]: las Outfit de la app (`PdfService.fuentesOutfit`). Sin ellas va
  /// la letra de fábrica del paquete (los tests, para poder leer el texto).
  static Future<Uint8List> armar(
    DatosDelCierreDeEntradas d, {
    (pw.Font, pw.Font)? fuentes,
    pw.ImageProvider? logo,
  }) async {
    final caja = d.caja;
    final c = d.cuentas;
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
    final grande = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

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

    final quien = (caja.operadorNombre ?? '').isEmpty ? 'Jefe' : caja.operadorNombre!;
    final diferencia = caja.diferencia;
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
        pw.Text(
          'CIERRE DE CAJA DE ENTRADAS · $quien',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            'Abierta: ${ComprobanteEntradasPdf.cuando(caja.abiertaAt)}'
            '${caja.cerradaAt == null ? ' · sigue abierta' : ' · Cerrada: ${ComprobanteEntradasPdf.cuando(caja.cerradaAt!)}'}',
            style: chico,
          ),
        ),
        raya(),
        fila(vendidas(c), pesos(c.vendido)),
        if (c.descuentos > 0)
          fila(
            'Descuentos a mano (${c.conDescuento == 1 ? '1 venta' : '${c.conDescuento} ventas'})',
            pesos(c.descuentos),
          ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Text(
            'Ventas: ${c.ventas}'
            '${c.mixtos > 0 ? ' · ${c.mixtos == 1 ? '1 mixta' : '${c.mixtos} mixtas'}' : ''}'
            '${c.anuladas > 0 ? ' · ${c.anuladas == 1 ? '1 anulada' : '${c.anuladas} anuladas'} (no cuentan)' : ''}',
            style: normal,
          ),
        ),
        raya(),
        fila('Cambio inicial', pesos(c.cambioInicial)),
        fila('Efectivo', pesos(c.efectivo)),
        fila('Transferencia (con los recargos)', pesos(c.transferencia)),
        if (c.recargos > 0) fila('Recargos por transferencia', pesos(c.recargos)),
        fila('Total cobrado', pesos(c.total), estilo: fuerte),
        raya(),
        fila(
          'Tenía que haber (cambio y efectivo)',
          pesos(CierreDeEntradas.esperadoAlCerrar(caja) ?? c.efectivoEsperado),
        ),
        fila('Contó', caja.efectivoContado == null ? '—' : pesos(caja.efectivoContado!)),
        if (diferencia != null)
          fila('Diferencia', diferenciaEnPalabras(diferencia), estilo: grande),
        if ((caja.notaCierre ?? '').trim().isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('Nota: ${caja.notaCierre!.trim()}', style: normal),
          ),
        if (c.hayAnuladoDespues)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text(
              'Anulado después del cierre: ${pesos(c.anuladoDespues)} '
              '(el cierre no se corrige)',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red800,
              ),
            ),
          ),
      ],
    );

    doc.addPage(pw.Page(pageFormat: hoja, build: (_) => cuerpo));
    return doc.save();
  }

  /// Cómo se llama el archivo.
  static String nombreDelArchivo(DatosDelCierreDeEntradas d) {
    String limpio(String s) => s
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final quien = limpio(d.caja.operadorNombre ?? 'Jefe');
    return 'Cierre_entradas_${limpio(d.fiesta)}_$quien.pdf';
  }
}
