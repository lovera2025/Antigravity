// La ventana de prueba del plano (tool/plano_prueba.dart) anda: abre sin base ni
// nube y hace lo mismo que la app. Si deja de compilar o de guardar, salta acá.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/plano_prueba.dart';

void main() {
  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PruebaDelPlano()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('personalizar')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('pestana_acomodar')));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> guardar(WidgetTester tester) async {
    final boton = find.byKey(const Key('guardar_acomodo'));
    await tester.ensureVisible(boton);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(boton);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('el plano mezclado se ordena al guardar', (tester) async {
    await abrir(tester);
    expect(find.text('13 saltos'), findsOneWidget);
    await guardar(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('1 salto'), findsOneWidget);
    expect(find.textContaining('con los números en orden'), findsOneWidget);
  });

  testWidgets('con familias con mesa, los números no cambian', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('prueba_sentados')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('13 saltos'), findsOneWidget);
    expect(find.textContaining('Los números se ordenan'), findsNothing);
  });
}
