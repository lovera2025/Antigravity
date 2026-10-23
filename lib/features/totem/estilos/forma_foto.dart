import 'dart:ui';

/// La forma de la foto del evento en la espera del tótem (6.2.1). Se elige en
/// Personalizar; la de siempre es el círculo.
///
/// La clave es lo que se guarda en `totem_config.foto_forma`. Una clave que
/// esta versión no conoce (la eligió una más nueva) se dibuja como círculo,
/// pero se guarda como vino: ver `TotemConfig.fotoForma`.
enum FormaFoto {
  circulo('circulo', 'Círculo', 1),
  ovalo('ovalo', 'Óvalo', 4 / 3),
  cuadrado('cuadrado', 'Cuadrado', 1),
  arco('arco', 'Arco', 4 / 3),
  corazon('corazon', 'Corazón', 0.92),
  hexagono('hexagono', 'Hexágono', 0.87),
  rombo('rombo', 'Rombo', 1.2),
  triangulo('triangulo', 'Triángulo', 0.87),

  /// La imagen sin recortar ni marco, entera: para un logo sin fondo.
  talCual('tal_cual', 'Tal cual', 1 / 1.6);

  final String clave;
  final String nombre;

  /// El alto sobre el ancho.
  final double proporcion;

  const FormaFoto(this.clave, this.nombre, this.proporcion);

  /// La de [clave]; vacía o desconocida, el círculo.
  static FormaFoto de(String? clave) {
    for (final f in values) {
      if (f.clave == clave) return f;
    }
    return circulo;
  }

  /// Lo que ocupa con [lado], el ancho de la foto al 100 % en cada apariencia.
  /// "Tal cual" es más ancha: los logos suelen ser apaisados.
  Size medida(double lado) => this == talCual
      ? Size(lado * 1.6, lado)
      : Size(lado, lado * proporcion);

  /// El contorno dentro de [r]. "Tal cual" no tiene: es el rectángulo.
  Path camino(Rect r) {
    Offset p(double x, double y) =>
        Offset(r.left + r.width * x, r.top + r.height * y);
    Path poligono(List<(double, double)> puntos) =>
        Path()..addPolygon([for (final (x, y) in puntos) p(x, y)], true);

    switch (this) {
      case circulo:
      case ovalo:
        return Path()..addOval(r);
      case cuadrado:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width * 0.14)));
      case arco:
        final arriba = Radius.elliptical(r.width / 2, r.height * 0.38);
        final abajo = Radius.circular(r.width * 0.06);
        return Path()
          ..addRRect(RRect.fromRectAndCorners(
            r,
            topLeft: arriba,
            topRight: arriba,
            bottomLeft: abajo,
            bottomRight: abajo,
          ));
      case corazon:
        return Path()
          ..moveTo(p(0.5, 0.97).dx, p(0.5, 0.97).dy)
          ..cubicTo(p(0.2, 0.74).dx, p(0.2, 0.74).dy, p(0, 0.54).dx,
              p(0, 0.54).dy, p(0, 0.3).dx, p(0, 0.3).dy)
          ..cubicTo(p(0, 0.12).dx, p(0, 0.12).dy, p(0.13, 0.01).dx,
              p(0.13, 0.01).dy, p(0.28, 0.01).dx, p(0.28, 0.01).dy)
          ..cubicTo(p(0.38, 0.01).dx, p(0.38, 0.01).dy, p(0.46, 0.07).dx,
              p(0.46, 0.07).dy, p(0.5, 0.16).dx, p(0.5, 0.16).dy)
          ..cubicTo(p(0.54, 0.07).dx, p(0.54, 0.07).dy, p(0.62, 0.01).dx,
              p(0.62, 0.01).dy, p(0.72, 0.01).dx, p(0.72, 0.01).dy)
          ..cubicTo(p(0.87, 0.01).dx, p(0.87, 0.01).dy, p(1, 0.12).dx,
              p(1, 0.12).dy, p(1, 0.3).dx, p(1, 0.3).dy)
          ..cubicTo(p(1, 0.54).dx, p(1, 0.54).dy, p(0.8, 0.74).dx,
              p(0.8, 0.74).dy, p(0.5, 0.97).dx, p(0.5, 0.97).dy)
          ..close();
      case hexagono:
        return poligono(const [
          (0.25, 0), (0.75, 0), (1, 0.5), (0.75, 1), (0.25, 1), (0, 0.5),
        ]);
      case rombo:
        return poligono(const [(0.5, 0), (1, 0.5), (0.5, 1), (0, 0.5)]);
      case triangulo:
        return poligono(const [(0.5, 0), (1, 1), (0, 1)]);
      case talCual:
        return Path()..addRect(r);
    }
  }
}
