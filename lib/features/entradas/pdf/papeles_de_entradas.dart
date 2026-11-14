import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../common/services/pdf_service.dart';
import 'comprobante_entradas_pdf.dart';

/// El isotipo de la cabecera de los papeles. Null si no se pudo leer: el papel
/// sale igual, sin él.
Future<pw.ImageProvider?> isotipoDeLosPapeles() async {
  try {
    final datos = await rootBundle.load('assets/icons/isotipo-ej.png');
    return pw.MemoryImage(datos.buffer.asUint8List());
  } catch (e) {
    debugPrint('⚠️ Entradas: el isotipo no se pudo leer: $e');
    return null;
  }
}

/// Arma el comprobante de una venta de entradas con las letras de la app y lo
/// entrega como los demás papeles: en Windows, el menú de ver o guardar; en
/// Android, compartir. Los tests lo reemplazan.
typedef AbrirComprobanteDeEntradas = Future<void> Function(
  DatosDelComprobante datos, {
  BuildContext? context,
});

final abrirComprobanteDeEntradasProvider =
    Provider<AbrirComprobanteDeEntradas>((ref) {
  return (datos, {context}) async {
    final bytes = await ComprobanteEntradasPdf.armar(
      datos,
      fuentes: await PdfService.fuentesOutfit(),
      logo: await isotipoDeLosPapeles(),
    );
    if (context != null && !context.mounted) return;
    await PdfService.entregarPdf(
      bytes,
      ComprobanteEntradasPdf.nombreDelArchivo(datos),
      context: context,
    );
  };
});
