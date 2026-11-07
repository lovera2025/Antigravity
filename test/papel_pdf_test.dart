import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/impresion/papel_pdf.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';

import 'helpers/leer_pdf.dart';

/// El PDF de un papel de la barra: 58 mm de ancho como la térmica, una sola hoja tan
/// larga como haga falta (pedido del usuario, 7-nov), con las letras de la app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// El ancho y el alto de la hoja, en puntos, del `MediaBox` del PDF.
  (double, double) medidas(Uint8List bytes) {
    final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(latin1.decode(bytes));
    expect(m, isNotNull, reason: 'el PDF no tiene MediaBox');
    return (double.parse(m!.group(1)!), double.parse(m.group(2)!));
  }

  List<LineaTicket> papel(int renglones) => [
        const TituloTicket('JUNIOR EVENTOS'),
        const TextoTicket('CIERRE DE CAJA - BARRA', negrita: true),
        const SeparadorTicket(),
        for (var i = 1; i <= renglones; i++) RenglonTicket('$i x Cerveza lata', '\$ ${i * 3500}'),
        const GrandeTicket('Faltan \$ 500'),
      ];

  test('una sola hoja de 58 mm de ancho, más larga cuanto más se escribe', () async {
    final fuentes = await PdfService.fuentesOutfit();
    expect(fuentes, isNotNull, reason: 'las Outfit vienen con la app');
    final corto = await PapelPdf.armar(papel(3), titulo: 'Cierre', fuentes: fuentes);
    final largo = await PapelPdf.armar(papel(120), titulo: 'Cierre', fuentes: fuentes);

    expect(paginasDelPdf(corto), 1);
    expect(paginasDelPdf(largo), 1, reason: 'con muchas ventas, la hoja se alarga: nada de cortar en hojas');
    final (anchoCorto, altoCorto) = medidas(corto);
    final (anchoLargo, altoLargo) = medidas(largo);
    expect(anchoCorto, closeTo(PapelPdf.ancho, 0.01));
    expect(anchoLargo, closeTo(PapelPdf.ancho, 0.01));
    expect(altoLargo, greaterThan(altoCorto * 5));
  });

  test('lo escrito está en el PDF', () async {
    // Con la letra de fábrica el texto se puede leer en los bytes (con una TTF no).
    final bytes = await PapelPdf.armar(papel(2), titulo: 'Cierre');
    // El paquete escribe palabra por palabra: "(JUNIOR)" y "(EVENTOS)".
    final palabras = {
      for (final m in RegExp(r'\[\((.*?)\)\]TJ').allMatches(contenidoDelPdf(bytes))) m.group(1)!,
    };
    for (final p in ['JUNIOR', 'EVENTOS', 'CIERRE', 'BARRA', 'Cerveza', 'lata', '7000', 'Faltan', '500']) {
      expect(palabras, contains(p), reason: p);
    }
  });
}
