import 'dart:ui' show Offset;

import '../modelo/armado_salon.dart';
import 'editar_armado.dart';

/// Dónde van las manijas para armar el espacio sobre el dibujo (6.1.0, "el
/// salón primero"), y cuál hay bajo el dedo. Todo en coordenadas del plano:
/// la pantalla pasa la tolerancia ya convertida.
///
/// Las cuentas de qué pasa al arrastrarlas son de [EditarArmado]
/// (`estirarSector`, `estirarPlayon`, `moverPlayon`).
class ManijasPlano {
  ManijasPlano._();

  /// Cuánto lugar tiene el dedo alrededor de una manija, en píxeles de
  /// pantalla. Es un poco más que lo que se dibuja: cuesta acertarle a un
  /// cuadradito de 10 px.
  static const double toleranciaPx = 9;

  /// Lo que mide de lado el cuadradito de una manija, en píxeles de pantalla.
  static const double ladoPx = 10;

  /// Las ocho de un sector: las esquinas y el medio de cada lado.
  static Map<Manija, Offset> deSector(RectPlano c) => {
        Manija.no: Offset(c.x, c.y),
        Manija.n: Offset(c.centroX, c.y),
        Manija.ne: Offset(c.derecha, c.y),
        Manija.e: Offset(c.derecha, c.centroY),
        Manija.se: Offset(c.derecha, c.abajo),
        Manija.s: Offset(c.centroX, c.abajo),
        Manija.so: Offset(c.x, c.abajo),
        Manija.o: Offset(c.x, c.centroY),
      };

  /// Las ocho del playón: sus cuatro esquinas y el medio de cada lado. Null si
  /// el borde no es de cuatro puntos (un armado del Canva no tiene borde).
  static Map<Manija, Offset>? dePlayon(ContornoPlano? c) {
    if (c == null || c.puntos.length != 4) return null;
    final p = [for (final q in c.puntos) Offset(q.x, q.y)];
    // Arriba a la izquierda, arriba a la derecha, abajo a la derecha, abajo a
    // la izquierda: como lo dibuja el salón a medida.
    final (ai, ad, bd, bi) = (p[0], p[1], p[2], p[3]);
    Offset medio(Offset a, Offset b) => Offset.lerp(a, b, 0.5)!;
    return {
      Manija.no: ai,
      Manija.n: medio(ai, ad),
      Manija.ne: ad,
      Manija.e: medio(ad, bd),
      Manija.se: bd,
      Manija.s: medio(bd, bi),
      Manija.so: bi,
      Manija.o: medio(bi, ai),
    };
  }

  /// La manija del medio del playón, para moverlo entero. Arrastrar desde
  /// cualquier lugar de adentro le quitaría al jefe mover la vista con el
  /// plano acercado.
  static Offset? centroPlayon(ContornoPlano? c) {
    if (c == null || c.puntos.length != 4) return null;
    var x = 0.0, y = 0.0;
    for (final p in c.puntos) {
      x += p.x;
      y += p.y;
    }
    return Offset(x / 4, y / 4);
  }

  /// La manija bajo [p], o null: la más cercana a menos de [radio] (en
  /// unidades del plano).
  static Manija? en(Map<Manija, Offset> manijas, Offset p, double radio) {
    Manija? mejor;
    var cerca = double.infinity;
    for (final e in manijas.entries) {
      final d = (e.value - p).distance;
      if (d <= radio && d < cerca) {
        mejor = e.key;
        cerca = d;
      }
    }
    return mejor;
  }
}
