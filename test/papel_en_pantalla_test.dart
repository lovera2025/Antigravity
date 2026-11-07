import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/impresion/papel_en_pantalla.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';

/// Un papel de la barra en la pantalla: cada clase de línea como en la térmica, y que
/// entre en un celular sin desbordar.
void main() {
  const lineas = <LineaTicket>[
    TituloTicket('JUNIOR EVENTOS'),
    TextoTicket('CIERRE DE CAJA - BARRA', negrita: true),
    TextoTicket('Nota: faltó un billete de 500', centrado: false),
    SeparadorTicket(),
    RenglonTicket('23 x Cerveza lata', r'$ 80.500'),
    RenglonTicket('Efectivo esperado', r'$ 36.000', negrita: true),
    GrandeTicket(r'Faltan $ 500'),
  ];

  Future<void> montar(WidgetTester tester, double ancho) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PapelEnPantalla(lineas))),
    ));
  }

  testWidgets('cada línea se ve, y un renglón lleva lo suyo a la izquierda y la plata a la derecha',
      (tester) async {
    await montar(tester, 1280);
    for (final t in [
      'JUNIOR EVENTOS',
      'CIERRE DE CAJA - BARRA',
      'Nota: faltó un billete de 500',
      '23 x Cerveza lata',
      r'$ 80.500',
      r'Faltan $ 500',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    final izq = tester.getTopLeft(find.text('23 x Cerveza lata'));
    final der = tester.getTopRight(find.text(r'$ 80.500'));
    expect(der.dy, izq.dy, reason: 'en el mismo renglón');
    expect(der.dx, greaterThan(izq.dx + 150), reason: 'la plata va contra el borde derecho');

    final grande = tester.widget<Text>(find.text(r'Faltan $ 500'));
    final chica = tester.widget<Text>(find.text('23 x Cerveza lata'));
    expect(grande.style!.fontSize, greaterThan(14), reason: 'lo grande, en grande');
    expect(chica.style?.fontSize, anyOf(isNull, 14));
  });

  testWidgets('en un celular entra sin desbordar', (tester) async {
    await montar(tester, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('es papel: blanco, también sobre un tema oscuro', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(body: SingleChildScrollView(child: PapelEnPantalla(lineas))),
    ));
    final caja = tester.widget<DecoratedBox>(find.descendant(
      of: find.byType(PapelEnPantalla),
      matching: find.byType(DecoratedBox),
    ).first);
    expect((caja.decoration as BoxDecoration).color, Colors.white);
    final texto = tester.widget<RichText>(find.descendant(
      of: find.byType(PapelEnPantalla),
      matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == '23 x Cerveza lata'),
    ));
    expect(texto.text.style?.color, const Color(0xFF1D1B20), reason: 'letra oscura sobre el papel');
  });
}
