// "Tu fondo" en los tests: una imagen de mentira (una story de colores) y la
// config de un evento que la usa.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:arguello_events/models/totem_config.dart';

/// Una imagen de [ancho] × [alto]: arriba dorada, abajo azul, con un círculo
/// claro al medio. En PNG, como la elegiría el selector de archivos.
///
/// Arma la imagen con dart:ui: en un `testWidgets` va dentro de
/// `tester.runAsync`.
Future<Uint8List> pngDePrueba({int ancho = 90, int alto = 160}) async {
  final grabador = ui.PictureRecorder();
  final canvas = ui.Canvas(grabador);
  final rect = ui.Rect.fromLTWH(0, 0, ancho.toDouble(), alto.toDouble());
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        const [Color(0xFFE8B04A), Color(0xFF1B3C8C)],
      ),
  );
  canvas.drawCircle(
    rect.center,
    ancho / 4,
    ui.Paint()..color = const Color(0xFFFFF2D0),
  );
  final cuadro = grabador.endRecording();
  final imagen = await cuadro.toImage(ancho, alto);
  cuadro.dispose();
  final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
  imagen.dispose();
  return datos!.buffer.asUint8List();
}

/// Un evento masivo con "Tu fondo" elegido y su receta (la de una imagen
/// oscura y cálida).
TotemConfig conTuFondo(
  TotemConfig cfg, {
  String animacion = 'acercarse',
  List<String> efectos = const ['polvo', 'barrido'],
  int oscurecer = 30,
  int luz = 25,
}) =>
    cfg.copyWith(
      estilo: 'tu_fondo',
      fondoUrl: 'https://nube.test/totem/${cfg.eventoId}/fondo.png?v=1',
      fondoAnimacion: animacion,
      fondoEfectos: efectos,
      fondoIntensidad: 40,
      fondoIntensidadEfectos: 60,
      fondoOscurecer: oscurecer,
      fondoPaleta: const [Color(0xFFE5A363), Color(0xFFFDD475), Color(0xFF614018)],
      fondoFoco: const Offset(0.5, 0.55),
      fondoLetras: 'clasica',
      fondoLuz: luz,
    );
