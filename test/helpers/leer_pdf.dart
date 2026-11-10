import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

/// Cuántas hojas tiene un PDF armado por la app.
int paginasDelPdf(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;

/// Lo que un PDF dibuja y escribe, hoja por hoja pegado en un solo texto: sus
/// contenidos sin comprimir.
///
/// Sirve para buscar un texto **solo si el PDF se armó sin las letras de la
/// app** (con la de fábrica del paquete): con una letra TTF el texto va
/// escrito en códigos de glifo y no se puede leer así.
String contenidoDelPdf(Uint8List bytes) => _contenidos(bytes).join('\n');

/// Los contenidos sin comprimir de un PDF, uno por hoja (y alguno más que no
/// es de una hoja: no molesta, no trae texto escrito).
List<String> _contenidos(Uint8List bytes) {
  final crudo = latin1.decode(bytes);
  final partes = <String>[];
  final tramo = RegExp(r'stream\r?\n(.*?)\r?\nendstream', dotAll: true);
  for (final m in tramo.allMatches(crudo)) {
    try {
      partes.add(latin1.decode(zlib.decode(latin1.encode(m.group(1)!))));
    } catch (_) {
      // No era un contenido comprimido (una letra incrustada, por ejemplo).
    }
  }
  return partes;
}

/// Una palabra escrita en un PDF: dónde empieza en la hoja (en puntos, desde
/// abajo a la izquierda, como el PDF) y cuánto mide de ancho.
typedef PalabraDelPdf = ({
  String texto,
  double x,
  double y,
  double ancho,
  double cuerpo,
});

/// Las palabras que un PDF escribe, con su lugar en la hoja. Sirve para
/// comprobar que **nada quede fuera de la hoja o del margen**: un texto que se
/// sale no da error, y a simple vista en un test no se ve.
///
/// Como [contenidoDelPdf], **solo con la letra de fábrica del paquete**
/// (Helvetica): con una TTF el texto va en códigos de glifo. El ancho sale de
/// las medidas de Helvetica que trae el paquete, en negrita o no según la letra
/// con la que se escribió cada palabra.
///
/// El paquete escribe palabra por palabra (`BT /F5 14 Tf 2 Tc x y Td
/// [(HOLA)]TJ ET`) y mueve cada cosa con `cm` entre `q` y `Q`: se sigue esa
/// cuenta para saber dónde cae cada palabra en la hoja.
List<PalabraDelPdf> palabrasDelPdf(Uint8List bytes) {
  final crudo = latin1.decode(bytes);
  // Qué letra es cada /F: el objeto de la letra dice su nombre y su base.
  final negritas = <String>{};
  for (final m in RegExp(r'<<[^<>]*?/BaseFont\s*/([\w-]+)[^<>]*?>>')
      .allMatches(crudo)) {
    final nombre = RegExp(r'/Name\s*/(F\d+)').firstMatch(m.group(0)!);
    if (nombre != null && m.group(1)!.contains('Bold')) {
      negritas.add(nombre.group(1)!);
    }
  }
  final doc = PdfDocument();
  final regular = PdfFont.helvetica(doc);
  final negrita = PdfFont.helveticaBold(doc);

  const n = r'(-?\d*\.?\d+)';
  final paso = RegExp(
    [
      r'\[((?:[^\]\\]|\\.)*)\]\s*TJ', // 1: lo que se escribe
      '$n\\s+$n\\s+$n\\s+$n\\s+$n\\s+$n\\s+cm', // 2-7
      r'/(F\d+)\s+' '$n' r'\s+Tf', // 8, 9
      '$n\\s+Tc', // 10
      '$n\\s+$n\\s+Td', // 11, 12
      r'(?<![\w/.])(q|Q|BT)(?![\w.])', // 13
    ].join('|'),
  );
  final entreParentesis = RegExp(r'\(((?:\\.|[^\\)])*)\)');

  final palabras = <PalabraDelPdf>[];
  for (final contenido in _contenidos(bytes)) {
    // La cuenta de dónde está parado: [a, b, c, d, e, f], como en el PDF.
    var ctm = <double>[1, 0, 0, 1, 0, 0];
    final pila = <List<double>>[];
    var letra = '';
    var cuerpo = 0.0;
    var espaciado = 0.0;
    var tx = 0.0, ty = 0.0;
    for (final m in paso.allMatches(contenido)) {
      if (m.group(1) != null) {
        final texto = entreParentesis
            .allMatches(m.group(1)!)
            .map((s) => s.group(1)!.replaceAllMapped(
                  RegExp(r'\\(.)'),
                  (e) => e.group(1)!,
                ))
            .join();
        if (texto.trim().isEmpty) continue;
        double ancho;
        try {
          ancho = (negritas.contains(letra) ? negrita : regular)
                      .stringMetrics(texto)
                      .width *
                  cuerpo +
              espaciado * texto.length;
        } catch (_) {
          // Una letra que Helvetica no tiene: se estima de más.
          ancho = texto.length * cuerpo * 0.7;
        }
        palabras.add((
          texto: texto,
          x: ctm[0] * tx + ctm[2] * ty + ctm[4],
          y: ctm[1] * tx + ctm[3] * ty + ctm[5],
          ancho: ancho * ctm[0].abs(),
          cuerpo: cuerpo,
        ));
      } else if (m.group(2) != null) {
        final k = [for (var i = 2; i <= 7; i++) double.parse(m.group(i)!)];
        ctm = [
          k[0] * ctm[0] + k[1] * ctm[2],
          k[0] * ctm[1] + k[1] * ctm[3],
          k[2] * ctm[0] + k[3] * ctm[2],
          k[2] * ctm[1] + k[3] * ctm[3],
          k[4] * ctm[0] + k[5] * ctm[2] + ctm[4],
          k[4] * ctm[1] + k[5] * ctm[3] + ctm[5],
        ];
      } else if (m.group(8) != null) {
        letra = m.group(8)!;
        cuerpo = double.parse(m.group(9)!);
      } else if (m.group(10) != null) {
        espaciado = double.parse(m.group(10)!);
      } else if (m.group(11) != null) {
        tx = double.parse(m.group(11)!);
        ty = double.parse(m.group(12)!);
      } else {
        switch (m.group(13)) {
          case 'q':
            pila.add(ctm);
          case 'Q':
            if (pila.isNotEmpty) ctm = pila.removeLast();
          case 'BT':
            tx = 0;
            ty = 0;
        }
      }
    }
  }
  return palabras;
}
