import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Pinta [dibujar] en una imagen de [escala] del tamaño de [rect] (en píxeles
/// de verdad, con [pixeles] por punto) y la estira hasta [rect]. [dibujar]
/// recibe el lienzo de la imagen, lo que mide y cuántos píxeles de la imagen
/// son un punto.
///
/// La tele es el tótem (25-nov-2026): lo que es borroso por naturaleza (el
/// fondo animado, el resplandor del camino, los efectos de "Tu fondo") se
/// calcula en menos píxeles y se estira, y se ve igual.
void pintarEnChico(
  Canvas canvas,
  Rect rect, {
  required double escala,
  required double pixeles,
  required void Function(Canvas lienzo, Size mide, double porPunto) dibujar,
}) {
  final porPunto = pixeles * escala;
  final w = math.max(1, (rect.width * porPunto).round());
  final h = math.max(1, (rect.height * porPunto).round());
  final grabador = ui.PictureRecorder();
  dibujar(Canvas(grabador), Size(w.toDouble(), h.toDouble()), porPunto);
  final cuadro = grabador.endRecording();
  final imagen = cuadro.toImageSync(w, h);
  cuadro.dispose();
  canvas.drawImageRect(
    imagen,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    rect,
    Paint()..filterQuality = FilterQuality.low,
  );
  // Lo dibujado se queda con su copia: soltar la nuestra no la borra.
  imagen.dispose();
}
