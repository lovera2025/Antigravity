import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Cuántas hojas tiene un PDF armado por la app.
int paginasDelPdf(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(latin1.decode(bytes)).length;

/// Lo que un PDF dibuja y escribe, hoja por hoja pegado en un solo texto: sus
/// contenidos sin comprimir.
///
/// Sirve para buscar un texto **solo si el PDF se armó sin las letras de la
/// app** (con la de fábrica del paquete): con una letra TTF el texto va
/// escrito en códigos de glifo y no se puede leer así.
String contenidoDelPdf(Uint8List bytes) {
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
  return partes.join('\n');
}
