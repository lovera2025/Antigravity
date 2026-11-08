import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/linea_de_la_caja.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';

/// La línea de arriba de VENDER, en lo angosto. En el recorrido del 7-nov, en la tablet,
/// salía "Sin central desde las 23:36 · 1 …": no se leía cuánto faltaba mandar. Ahora,
/// si no entra en un renglón, la central baja al segundo, y nada se corta.
void main() {
  final textos = TextosDeLaCaja.de(
    DatosSinInternetBarra(
      hayInternet: false,
      alDia: DateTime(2026, 12, 4, 21, 40),
      pendientes: const PendientesDeLaBarra(ventas: 12, otros: 3),
    ),
    central: EstadoDeLaCentral.sinCentral,
    desde: DateTime(2026, 12, 4, 23, 36),
    porMandar: 15,
  );

  Future<void> armar(WidgetTester tester, double ancho) async {
    tester.view.physicalSize = Size(ancho, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [LineaDeLaCajaVista(textos: textos, alTocarLaCentral: () {})]),
      ),
    ));
  }

  /// El texto entra entero en lo que mide: un renglón que se corta mide menos que su texto.
  void entero(WidgetTester tester, String key) {
    final caja = tester.renderObject<RenderParagraph>(find.byKey(Key(key)));
    expect(caja.didExceedMaxLines, isFalse, reason: '$key se corta');
  }

  for (final (nombre, ancho) in [('una tablet', 800.0), ('una tablet parada', 600.0), ('un celular', 360.0)]) {
    testWidgets('en $nombre se lee entera, sin cortes ni desbordes', (tester) async {
      await armar(tester, ancho);
      expect(tester.takeException(), isNull);
      expect(find.text('Sin internet · 12 ventas y 3 cambios por subir'), findsOneWidget);
      expect(find.text('Sin central desde las 23:36 · 15 por mandar'), findsOneWidget);
      entero(tester, 'caja_subida');
      entero(tester, 'caja_central_texto');
    });
  }

  testWidgets('si no entran juntas, la central va abajo', (tester) async {
    await armar(tester, 360);
    final subida = tester.getTopLeft(find.byKey(const Key('caja_subida')));
    final central = tester.getTopLeft(find.byKey(const Key('caja_central_texto')));
    expect(central.dy, greaterThan(subida.dy));
  });

  testWidgets('si entran, van en el mismo renglón', (tester) async {
    await armar(tester, 1280);
    final subida = tester.getTopLeft(find.byKey(const Key('caja_subida')));
    final central = tester.getTopLeft(find.byKey(const Key('caja_central_texto')));
    expect(central.dy, subida.dy);
    expect(central.dx, greaterThan(subida.dx));
  });

  testWidgets('tocar la central abre cómo está', (tester) async {
    var tocada = false;
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LineaDeLaCajaVista(textos: textos, alTocarLaCentral: () => tocada = true)),
    ));
    await tester.tap(find.byKey(const Key('caja_central')));
    expect(tocada, isTrue);
  });
}
