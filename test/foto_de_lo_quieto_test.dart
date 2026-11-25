import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/widgets/foto_de_lo_quieto.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart' show letraPorLetra;

/// Lo quieto, como foto (la tele es el tótem, 25-nov-2026): se dibuja una vez
/// y se pinta la foto; se ve igual; se da cuenta sola de cuándo cambió.

const _brillo = [
  Shadow(color: Colors.white, blurRadius: 2),
  Shadow(color: Colors.pink, blurRadius: 6),
  Shadow(color: Colors.pink, blurRadius: 14),
];

Widget _texto(String t) => Text(
      t,
      textDirection: TextDirection.ltr,
      style: const TextStyle(fontSize: 40, color: Colors.white, shadows: _brillo),
    );

Widget _en(Widget hijo) => Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.black,
        // Corrido un pedazo de píxel: la foto tiene que caer igual.
        child: Padding(padding: const EdgeInsets.fromLTRB(20.3, 30.7, 0, 0), child: Align(
          alignment: Alignment.topLeft,
          child: hijo,
        )),
      ),
    );

Future<Uint8List> _pixeles(WidgetTester tester, Widget w) async {
  final clave = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: clave, child: _en(w)));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final b = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: tester.view.devicePixelRatio);
    bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  });
  return bytes;
}

double _diferencia(Uint8List a, Uint8List b) {
  var s = 0;
  for (var i = 0; i < a.length; i++) {
    s += (a[i] - b[i]).abs();
  }
  return s / a.length;
}

void main() {
  setUp(() => FotoDeLoQuieto.fotosSacadas = 0);

  testWidgets('se ve igual que sin foto, también corrida un pedazo de píxel', (tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final sin = await _pixeles(tester, _texto('JUNIOR'));
    final con = await _pixeles(
      tester,
      FotoDeLoQuieto(margen: margenDelBrillo(const TextStyle(shadows: _brillo)), child: _texto('JUNIOR')),
    );
    expect(FotoDeLoQuieto.fotosSacadas, 1);
    // Con el brillo entero: el margen lo deja adentro de la foto.
    expect(_diferencia(sin, con), lessThan(0.2));
  });

  testWidgets('quieto, una sola foto aunque lo de arriba se arme en cada imagen', (tester) async {
    final tic = ValueNotifier(0);
    await tester.pumpWidget(_en(ValueListenableBuilder<int>(
      valueListenable: tic,
      builder: (_, v, _) => Opacity(
        opacity: v.isEven ? 1 : 0.9,
        child: FotoDeLoQuieto(child: _texto('JUNIOR')),
      ),
    )));
    for (var i = 0; i < 60; i++) {
      tic.value++;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(FotoDeLoQuieto.fotosSacadas, 1);
  });

  testWidgets('si lo de adentro cambia, saca otra; si cambia en cada imagen, va en vivo '
      'y la saca cuando se queda quieto', (tester) async {
    final texto = ValueNotifier('A');
    await tester.pumpWidget(_en(ValueListenableBuilder<String>(
      valueListenable: texto,
      builder: (_, t, _) => FotoDeLoQuieto(child: _texto(t)),
    )));
    expect(FotoDeLoQuieto.fotosSacadas, 1);
    await tester.pump(const Duration(seconds: 1));
    texto.value = 'B';
    await tester.pump(const Duration(milliseconds: 16));
    expect(FotoDeLoQuieto.fotosSacadas, 2, reason: 'un cambio suelto: otra foto');
    // Una animación: cambia en cada imagen. No una foto por imagen.
    for (var i = 0; i < 30; i++) {
      texto.value = 'C$i';
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(FotoDeLoQuieto.fotosSacadas, lessThanOrEqualTo(3));
    final enLaAnimacion = FotoDeLoQuieto.fotosSacadas;
    // Se queda quieta: al ratito, la foto.
    await tester.pump(RenderFotoDeLoQuieto.quietoDespuesDe + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 16));
    expect(FotoDeLoQuieto.fotosSacadas, enLaAnimacion + 1);
    // Y de ahí, nada más.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(FotoDeLoQuieto.fotosSacadas, enLaAnimacion + 1);
  });

  testWidgets('con huella: una foto por valor, y se pasa de una a la otra sin dibujar', (tester) async {
    final apagada = ValueNotifier(false);
    await tester.pumpWidget(_en(ValueListenableBuilder<bool>(
      valueListenable: apagada,
      builder: (_, a, _) => FotoDeLoQuieto(
        huella: a,
        child: _texto(a ? 'J NIOR' : 'JUNIOR'),
      ),
    )));
    for (var i = 0; i < 2; i++) {
      apagada.value = !apagada.value;
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(FotoDeLoQuieto.fotosSacadas, 2);
    // La letra floja de Neón: prende y apaga muchas veces.
    for (var i = 0; i < 20; i++) {
      apagada.value = !apagada.value;
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(FotoDeLoQuieto.fotosSacadas, 2);
  });

  group('el nombre que se enciende letra por letra, desde la foto', () {
    const estilo = TextStyle(fontSize: 40, color: Colors.white, shadows: _brillo);

    // Como en vivo en cada momento: las letras que no se prendieron ya
    // muestran su brillo, y se prenden en blanco una detrás de la otra.
    for (final p in [0.0, 0.2, 0.45, 0.7, 1.0]) {
      testWidgets('a $p, igual que en vivo', (tester) async {
        final vivo = await _pixeles(tester, letraPorLetra('PÉREZ, JUAN', estilo, p));
        final foto = await _pixeles(tester, letraPorLetra('PÉREZ, JUAN', estilo, p, enLaTele: true));
        expect(_diferencia(vivo, foto), lessThan(0.6));
      });
    }

    testWidgets('sin brillo (Gala), igual que en vivo a la mitad', (tester) async {
      const sinBrillo = TextStyle(fontSize: 40, color: Colors.white);
      final vivo = await _pixeles(tester, letraPorLetra('PÉREZ, JUAN', sinBrillo, 0.45));
      final foto = await _pixeles(tester, letraPorLetra('PÉREZ, JUAN', sinBrillo, 0.45, enLaTele: true));
      expect(_diferencia(vivo, foto), lessThan(0.6));
    });

    testWidgets('mientras se prende no saca fotos nuevas', (tester) async {
      final p = ValueNotifier(0.0);
      await tester.pumpWidget(_en(ValueListenableBuilder<double>(
        valueListenable: p,
        builder: (_, v, _) => letraPorLetra('PÉREZ, JUAN', estilo, v, enLaTele: true),
      )));
      final alPrincipio = FotoDeLoQuieto.fotosSacadas;
      for (var i = 1; i <= 40; i++) {
        p.value = i / 40;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(FotoDeLoQuieto.fotosSacadas, alPrincipio);
    });
  });

  testWidgets('el círculo se descubre como un barrido y al final está entero', (tester) async {
    Widget circulo(double p) => SizedBox(
          width: 100,
          height: 100,
          child: BarridoDeCirculo(
            progreso: p,
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        );
    final entero = await _pixeles(tester, const SizedBox(
      width: 100,
      height: 100,
      child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
    ));
    expect(_diferencia(await _pixeles(tester, circulo(1)), entero), lessThan(0.01));
    final cuarto = await _pixeles(tester, circulo(0.25));
    expect(_diferencia(cuarto, entero), greaterThan(0.5));
  });
}
