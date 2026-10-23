// "Tu fondo" (`lectura_del_fondo.dart`): lo que se lee de una imagen y la
// receta y los colores que salen. Las imágenes se arman acá, píxel por píxel:
// una rosa pastel, una oscura dorada, una casi blanca, una de fiesta y una de
// noche.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart' as mcu;

import 'package:arguello_events/features/totem/estilos/tu_fondo.dart';
import 'package:arguello_events/features/totem/services/lectura_del_fondo.dart';
import 'package:arguello_events/models/totem_config.dart';

const _ancho = 72, _alto = 128;

/// Una imagen de [_ancho] × [_alto], con el color de cada píxel.
Uint8List _imagen((int, int, int) Function(int x, int y) pixel) {
  final datos = Uint8List(_ancho * _alto * 4);
  for (var y = 0; y < _alto; y++) {
    for (var x = 0; x < _ancho; x++) {
      final (r, g, b) = pixel(x, y);
      final i = (y * _ancho + x) * 4;
      datos[i] = r.clamp(0, 255);
      datos[i + 1] = g.clamp(0, 255);
      datos[i + 2] = b.clamp(0, 255);
      datos[i + 3] = 255;
    }
  }
  return datos;
}

/// Un círculo suave de [radio] píxeles en ([cx], [cy]): 1 en el centro.
double _mancha(int x, int y, double cx, double cy, double radio) {
  final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
  return (1 - d / radio).clamp(0.0, 1.0);
}

final _azar = math.Random(7);

/// Rosa pastel, con luces blancas arriba.
final _rosa = _imagen((x, y) {
  final arriba = _mancha(x, y, 36, 30, 30);
  final t = y / _alto;
  return (
    (250 + 5 * arriba).round(),
    (205 - 8 * t + 40 * arriba).round(),
    (222 + 12 * t + 25 * arriba).round(),
  );
});

/// Casi negra, con un resplandor dorado y puntitos de oro al centro.
final _oroOscuro = _imagen((x, y) {
  final brillo = _mancha(x, y, 34, 70, 34);
  final punto = (x * 7 + y * 13) % 29 == 0 ? 0.5 * brillo : 0.0;
  final f = math.min(1.0, brillo * 0.8 + punto);
  return (
    (14 + 230 * f).round(),
    (10 + 170 * f).round(),
    (6 + 70 * f).round(),
  );
});

/// Casi blanca, apenas gris, sin ningún color.
final _casiBlanca = _imagen((x, y) {
  final v = 244 + _azar.nextInt(8);
  return (v, v, v - 1);
});

/// Oscura, con franjas de luz de colores: magenta, cian, amarillo y verde.
final _fiesta = _imagen((x, y) {
  const luces = [
    (255, 40, 200),
    (40, 220, 255),
    (255, 220, 40),
    (40, 255, 150),
  ];
  final franja = (x + y ~/ 3) ~/ 9;
  final enLuz = (x + y ~/ 3) % 9 < 4;
  if (!enLuz) return (12, 6, 22);
  final (r, g, b) = luces[franja % luces.length];
  return (r, g, b);
});

/// Azul de noche, con una ciudad de ventanitas abajo a la derecha.
final _noche = _imagen((x, y) {
  final t = y / _alto;
  final cielo = (8 + (20 * t).round(), 20 + (40 * t).round(), 60 + (70 * t).round());
  final enCiudad = x > 40 && y > 92;
  if (!enCiudad) return cielo;
  final ventana = x % 4 == 0 && y % 5 == 0;
  return ventana ? (170, 205, 255) : (6, 10, 24);
});

/// El detalle en la esquina de arriba a la izquierda; el resto liso.
final _detalleArribaIzquierda = _imagen((x, y) {
  if (x < 20 && y < 30) {
    final c = (x + y).isEven ? 230 : 30;
    return (c, c, c);
  }
  return (60, 64, 70);
});

Future<LecturaDelFondo> _leer(Uint8List rgba) =>
    LecturaDelFondo.deRgba(rgba, _ancho, _alto);

double _tono(Color c) => mcu.Hct.fromInt(c.toARGB32()).tone;

/// El contraste del saludo contra la luz del fondo detrás, con el oscurecido.
double _contrasteDelSaludo(LecturaDelFondo l, Color saludo, int oscurecer) {
  final y = mcu.ColorUtils.yFromLstar(l.luz * 100) * (1 - 0.5 * oscurecer / 100);
  return mcu.Contrast.ratioOfTones(_tono(saludo), mcu.ColorUtils.lstarFromY(y));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rosa pastel', () {
    test('clara y lisa: respira, con bokeh, sin oscurecer y el texto oscuro',
        () async {
      final l = await _leer(_rosa);
      expect(l.clara, isTrue);
      expect(l.palabras.first, 'Clara');
      final r = l.receta();
      expect(r.animacion, AnimacionFondo.respirar);
      expect(r.efectos, [EfectoFondo.bokeh]);
      expect(r.oscurecer, 0);
      expect(r.letras, LetrasFondo.suave);
      expect(textoOscuroSobre(luz: l.luzEntera, oscurecer: r.oscurecer), isTrue);
    });

    test('los colores: el saludo oscuro y que se lea; la tarjeta casi blanca',
        () async {
      final l = await _leer(_rosa);
      final p = l.paleta(oscurecer: 0);
      expect(_tono(p.saludo), lessThan(45));
      expect(_contrasteDelSaludo(l, p.saludo, 0), greaterThanOrEqualTo(4.5));
      expect(_tono(p.tarjeta), greaterThan(90));
      // El brillo sigue siendo rosado (matiz de rojo a magenta).
      final h = mcu.Hct.fromInt(p.brillo.toARGB32()).hue;
      expect(h < 40 || h > 300, isTrue, reason: 'matiz $h');
    });

    test('muy oscurecida, el texto vuelve a ir claro', () async {
      final l = await _leer(_rosa);
      expect(textoOscuroSobre(luz: l.luzEntera, oscurecer: 60), isFalse);
      final p = l.paleta(oscurecer: 60);
      expect(_tono(p.saludo), greaterThan(80));
    });
  });

  group('oscura dorada', () {
    test('cálida: se acerca, con polvo de luz y barrido, en letra clásica',
        () async {
      final l = await _leer(_oroOscuro);
      expect(l.oscura, isTrue);
      expect(l.calida, isTrue);
      expect(l.colorida, isFalse, reason: 'el dorado es un solo color');
      final r = l.receta();
      expect(r.animacion, AnimacionFondo.acercarse);
      expect(r.efectos, [EfectoFondo.polvo, EfectoFondo.barrido]);
      expect(r.letras, LetrasFondo.clasica);
      expect(r.oscurecer, inInclusiveRange(20, 40));
    });

    test('los colores: brillo dorado y claro, saludo claro que se lee',
        () async {
      final l = await _leer(_oroOscuro);
      final r = l.receta();
      final p = l.paleta(oscurecer: r.oscurecer);
      final brillo = mcu.Hct.fromInt(p.brillo.toARGB32());
      expect(brillo.hue, inInclusiveRange(40, 110), reason: 'dorado');
      expect(brillo.tone, greaterThanOrEqualTo(70));
      expect(_tono(p.saludo), greaterThanOrEqualTo(85));
      expect(_contrasteDelSaludo(l, p.saludo, r.oscurecer),
          greaterThanOrEqualTo(4.5));
      expect(_tono(p.tarjeta), lessThan(40));
      // Lo importante, al centro.
      expect((l.foco - const Offset(0.5, 0.55)).distance, lessThan(0.25));
    });
  });

  group('casi blanca', () {
    test('sin el azul de respaldo de Score: colores de la imagen, grises',
        () async {
      final l = await _leer(_casiBlanca);
      for (final c in l.colores) {
        expect(c.toARGB32(), isNot(0xFF4285F4));
        expect(mcu.Hct.fromInt(c.toARGB32()).chroma, lessThan(8));
      }
      final p = l.paleta(oscurecer: l.receta().oscurecer);
      for (final c in p.lista) {
        expect(c.toARGB32(), isNot(0xFF4285F4));
      }
      expect(l.clara, isTrue);
      expect(_contrasteDelSaludo(l, p.saludo, 0), greaterThanOrEqualTo(4.5));
    });

    test('tres colores distintos aunque la imagen tenga uno solo', () async {
      final l = await _leer(_casiBlanca);
      final p = l.paleta(oscurecer: 0);
      expect(p.lista.toSet(), hasLength(3));
    });
  });

  group('fiesta', () {
    test('muchos colores: flota, con destellos y el marco, en letra de fiesta',
        () async {
      final l = await _leer(_fiesta);
      expect(l.colorida, isTrue);
      expect(l.palabras, contains('Muy colorida'));
      final r = l.receta();
      expect(r.animacion, AnimacionFondo.flotar);
      expect(r.efectos, [EfectoFondo.destellos, EfectoFondo.marco]);
      expect(r.letras, LetrasFondo.fiesta);
      expect(r.intensidadEfectos, 70);
    });
  });

  group('noche', () {
    test('fría, con lo importante lejos del centro: recorre, titila y bruma',
        () async {
      final l = await _leer(_noche);
      expect(l.fria, isTrue);
      expect(l.foco.dx, greaterThan(0.5));
      expect(l.foco.dy, greaterThan(0.6));
      final r = l.receta();
      expect(r.animacion, AnimacionFondo.recorrer);
      expect(r.efectos, [EfectoFondo.titileo, EfectoFondo.bruma]);
      expect(r.letras, LetrasFondo.moderna);
    });
  });

  test('lo importante, donde está el detalle', () async {
    final l = await _leer(_detalleArribaIzquierda);
    expect(l.foco.dx, lessThan(0.36));
    expect(l.foco.dy, lessThan(0.36));
    expect(l.palabras.last, 'Lo importante arriba a la izquierda');
  });

  test('con mucho detalle se mueve menos; lisa, más', () async {
    final conDetalle = (await _leer(_fiesta)).receta();
    final lisa = (await _leer(_rosa)).receta();
    expect(conDetalle.intensidad, lessThan(lisa.intensidad));
  });

  group('lo que se guarda', () {
    const cfg = TotemConfig(
      eventoId: 'e0000000-0000-4000-8000-00000000000a',
      fondoUrl: 'https://x.test/fondo.jpg?v=1',
    );

    test('automática: la receta entera, los colores, el foco y la luz',
        () async {
      final l = await _leer(_oroOscuro);
      final r = l.receta();
      final con = conLaLectura(cfg, l, automatico: true);
      expect(con.fondoAutomatico, isTrue);
      expect(con.fondoAnimacion, r.animacion.clave);
      expect(con.fondoEfectos, [for (final e in r.efectos) e.clave]);
      expect(con.fondoIntensidad, r.intensidad);
      expect(con.fondoIntensidadEfectos, r.intensidadEfectos);
      expect(con.fondoOscurecer, r.oscurecer);
      expect(con.fondoLetras, r.letras.clave);
      expect(con.fondoPaleta, l.paleta(oscurecer: r.oscurecer).lista);
      expect(con.fondoFoco, l.foco);
      expect(con.fondoLuz, l.luzEntera);
      // Y se lee igual de la nube.
      expect(TotemConfig.fromJson(con.toJson()).toJson(), con.toJson());
    });

    test('a mano: queda lo elegido; los colores salen con su oscurecido',
        () async {
      final l = await _leer(_oroOscuro);
      final aMano = cfg.copyWith(
        fondoAutomatico: false,
        fondoAnimacion: 'ondular',
        fondoEfectos: const ['glitch'],
        fondoIntensidad: 90,
        fondoOscurecer: 70,
      );
      final con = conLaLectura(aMano, l, automatico: false);
      expect(con.fondoAutomatico, isFalse);
      expect(con.fondoAnimacion, 'ondular');
      expect(con.fondoEfectos, ['glitch']);
      expect(con.fondoIntensidad, 90);
      expect(con.fondoOscurecer, 70);
      expect(con.fondoPaleta, l.paleta(oscurecer: 70).lista);
    });

    test('el resumen se lee', () {
      const r = RecetaFondo(
        animacion: AnimacionFondo.acercarse,
        efectos: [EfectoFondo.polvo, EfectoFondo.barrido],
        intensidad: 40,
        intensidadEfectos: 50,
        oscurecer: 30,
        letras: LetrasFondo.clasica,
      );
      expect(r.resumen, 'Acercarse · Polvo de luz y Barrido de luz');
      const sin = RecetaFondo(
        animacion: AnimacionFondo.quieta,
        efectos: [],
        intensidad: 0,
        intensidadEfectos: 0,
        oscurecer: 0,
        letras: LetrasFondo.suave,
      );
      expect(sin.resumen, 'Quieta · sin efectos');
    });
  });

  // La imagen de verdad pasa por una copia chica: tiene que dar lo mismo que
  // leer los píxeles a mano.
  test('desde una imagen cargada, achicada, da la misma receta', () async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _oroOscuro,
      _ancho,
      _alto,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final imagen = await completer.future;
    final l = await LecturaDelFondo.deImagen(imagen);
    final directa = await _leer(_oroOscuro);
    expect(l.receta().animacion, directa.receta().animacion);
    expect(l.receta().efectos, directa.receta().efectos);
    expect((l.luz - directa.luz).abs(), lessThan(0.05));
    imagen.dispose();
  });
}
