// La pregunta de IMPRIMIR en el plano: en color o en blanco y negro.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/widgets/imprimir_plano_dialog.dart';

void main() {
  Future<Object?> elegir(
    WidgetTester tester,
    String boton, {
    int hojas = 1,
  }) async {
    Object? respuesta = 'sin contestar';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                respuesta = await elegirComoImprimirPlano(context, hojas: hojas);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(boton)));
    await tester.pumpAndSettle();
    return respuesta;
  }

  testWidgets('BLANCO Y NEGRO devuelve true', (tester) async {
    final r = await elegir(tester, 'imprimir_bn') as ComoImprimirPlano;
    expect(r.blancoYNegro, isTrue);
  });

  testWidgets('EN COLOR devuelve false', (tester) async {
    final r = await elegir(tester, 'imprimir_color') as ComoImprimirPlano;
    expect(r.blancoYNegro, isFalse);
  });

  testWidgets('CANCELAR no imprime nada', (tester) async {
    expect(await elegir(tester, 'imprimir_cancelar'), isNull);
  });

  testWidgets('dice cuántas hojas salen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => elegirComoImprimirPlano(context, hojas: 2),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Salen 2 hojas A4 acostadas'), findsOneWidget);
  });
}
