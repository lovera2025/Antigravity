import 'dart:io';

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

  // Revisión del 27-nov-2026: lo que la central rechazaba y el PIN que no reconocía no se
  // veían en ninguna pantalla; VENDER decía "Buscando la central…" toda la noche.
  group('lo que la central no acepta se dice', () {
    final datos = DatosSinInternetBarra(
      hayInternet: false,
      alDia: DateTime(2026, 12, 4, 21, 40),
      pendientes: const PendientesDeLaBarra(),
    );
    const delPin = 'La central no reconoce tu PIN: la notebook tiene que bajar los operadores con internet';

    test('con el PIN que la central no reconoce, la línea dice eso y no "Buscando…"', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.buscando, problema: delPin);
      expect(t.central, delPin);
      expect(t.central, isNot(contains('Buscando')));
      expect(t.tonoCentral, TonoDeLaLinea.atencion);
    });

    test('y dice cuánto falta mandar', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.sinCentral, problema: delPin, porMandar: 4);
      expect(t.central, '$delPin · 4 por mandar');
    });

    test('sin problema, buscando dice "Buscando la central…" como siempre', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.buscando);
      expect(t.central, 'Buscando la central…');
      expect(t.tonoCentral, TonoDeLaLinea.quieto);
    });

    test('conectada y con cosas que la central no guardó: lo dice, en amarillo', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.conectada, cajas: 3, rechazadas: 2);
      expect(t.central, 'Central · 3 cajas · la central no aceptó 2');
      expect(t.tonoCentral, TonoDeLaLinea.atencion);
    });

    test('conectada y sin rechazos: en verde, sin nada de más', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.conectada, cajas: 3);
      expect(t.central, 'Central · 3 cajas');
      expect(t.tonoCentral, TonoDeLaLinea.bien);
    });

    test('ya conectada, un problema viejo del PIN no se muestra', () {
      final t = TextosDeLaCaja.de(datos, central: EstadoDeLaCentral.conectada, problema: delPin);
      expect(t.central, 'Central conectada');
    });

    test('VENDER le pasa a la línea el problema y los rechazos del cliente', () {
      final linea = File('lib/features/barra/central/linea_de_la_caja.dart').readAsStringSync();
      expect(linea, contains('problema: cliente?.problema'));
      expect(linea, contains('rechazadas: cliente?.rechazadas.length'));
      expect(linea, contains("Key('central_rechazos')"), reason: 'el cartel de la central los lista');
    });
  });

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
