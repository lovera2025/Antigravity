// La foto del evento en el tótem vuelve a intentar si no cargó (revisión del
// 13-nov): hasta la 6.8.0, una foto que no bajaba la primera vez quedaba con el
// logo toda la noche, aunque volviera internet.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/totem/widgets/imagen_que_reintenta.dart';

/// Una foto que nunca carga, y cuenta cuántas veces se la pidió.
class _NoBaja extends ImageProvider<_NoBaja> {
  int pedidos = 0;

  @override
  Future<_NoBaja> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NoBaja>(this);

  @override
  ImageStreamCompleter loadImage(_NoBaja key, ImageDecoderCallback decode) {
    pedidos++;
    return MultiFrameImageStreamCompleter(
      codec: Future<ui.Codec>.error(StateError('sin internet')),
      scale: 1,
    );
  }
}

void main() {
  Future<void> montar(WidgetTester tester, ImageProvider foto) async {
    await tester.pumpWidget(MaterialApp(
      home: ImagenQueReintenta(
        imagen: foto,
        fit: BoxFit.cover,
        siFalla: const Text('EL LOGO'),
      ),
    ));
    // Que el fallo llegue y se dibuje lo que va en su lugar.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('si no carga, muestra lo que va en su lugar', (tester) async {
    final foto = _NoBaja();
    await montar(tester, foto);
    expect(find.text('EL LOGO'), findsOneWidget);
    expect(foto.pedidos, 1);
  });

  testWidgets('y la vuelve a pedir: a los 15 s, a los 30 y después cada minuto',
      (tester) async {
    final foto = _NoBaja();
    await montar(tester, foto);

    Future<void> pasan(int segundos) async {
      await tester.pump(Duration(seconds: segundos));
      await tester.pump();
      await tester.pump();
    }

    await pasan(14);
    expect(foto.pedidos, 1, reason: 'todavía no pasaron los 15 s');
    await pasan(1);
    expect(foto.pedidos, 2);
    await pasan(29);
    expect(foto.pedidos, 2);
    await pasan(1);
    expect(foto.pedidos, 3);
    await pasan(60);
    expect(foto.pedidos, 4);
    await pasan(60);
    expect(foto.pedidos, 5);
    expect(find.text('EL LOGO'), findsOneWidget, reason: 'mientras, el logo');
  });

  testWidgets('con otra foto empieza de cero', (tester) async {
    final vieja = _NoBaja();
    await montar(tester, vieja);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(vieja.pedidos, 2);

    final nueva = _NoBaja();
    await montar(tester, nueva);
    expect(nueva.pedidos, 1);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    await tester.pump();
    expect(nueva.pedidos, 2, reason: 'el primer reintento de la nueva, a los 15 s');
    expect(vieja.pedidos, 2, reason: 'la vieja no se pide más');
  });

  testWidgets('al sacarla de la pantalla deja de pedirla', (tester) async {
    final foto = _NoBaja();
    await montar(tester, foto);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    expect(foto.pedidos, 1);
  });
}
