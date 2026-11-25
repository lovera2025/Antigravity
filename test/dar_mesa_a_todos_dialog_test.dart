// El cartel de DAR MESA A TODOS (6.9.4): todas las familias vienen tildadas,
// se ve qué mesa recibiría cada una, y un solo DAR MESA se las da a las que
// quedaron tildadas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/widgets/dar_mesa_a_todos_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

ContratoAlumno _alumno(String id, {String? mesa, int extras = 0}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 315000,
      saldoDeudor: 315000,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      cursoDivision: '2DA',
    );

void main() {
  final familias = <FamiliaSinMesa>[
    (alumno: _alumno('luna'), noPago: true),
    (alumno: _alumno('rivas', mesa: '107', extras: 1), noPago: false),
  ];

  Future<List<Set<String>?>> abrir(
    WidgetTester tester, {
    Map<String, List<int>>? Function(Set<String>)? previa,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final elegido = <Set<String>?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => elegido.add(
                await mostrarDarMesaATodosDialog(
                  context: context,
                  familias: familias,
                  previa: previa,
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return elegido;
  }

  testWidgets('vienen todas tildadas, con lo que le falta a cada una',
      (tester) async {
    final elegido = await abrir(tester);
    expect(find.text('Dar mesa a todos'), findsOneWidget);
    expect(find.text('2DA · Sin mesa · no pagó'), findsOneWidget);
    expect(find.text('2DA · le falta 1 mesa'), findsOneWidget);
    expect(find.text('DAR MESA A LAS 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dar_mesa_confirmar')));
    await tester.pumpAndSettle();
    expect(elegido.single, {'luna', 'rivas'});
  });

  testWidgets('destildar una la saca, y la cuenta se vuelve a hacer',
      (tester) async {
    final pedidas = <Set<String>>[];
    final elegido = await abrir(
      tester,
      previa: (ids) {
        pedidas.add({...ids});
        return {
          if (ids.contains('luna')) 'luna': [42],
          // Sola, RIVAS recibe la 106; con LUNA, también.
          if (ids.contains('rivas')) 'rivas': [106],
        };
      },
    );
    expect(find.text('Mesa 42'), findsOneWidget);
    expect(find.text('Mesa 106'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dar_mesa_luna')));
    await tester.pumpAndSettle();
    expect(find.text('Mesa 42'), findsNothing);
    expect(find.text('DAR MESA'), findsOneWidget);
    expect(pedidas.last, {'rivas'});

    await tester.tap(find.byKey(const Key('dar_mesa_confirmar')));
    await tester.pumpAndSettle();
    expect(elegido.single, {'rivas'});
  });

  testWidgets('sin ninguna tildada no se puede dar', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('dar_mesa_luna')));
    await tester.tap(find.byKey(const Key('dar_mesa_rivas')));
    await tester.pumpAndSettle();
    final boton =
        tester.widget<FilledButton>(find.byKey(const Key('dar_mesa_confirmar')));
    expect(boton.onPressed, isNull);
  });

  testWidgets('si la cuenta falla, se puede dar igual: sin números a la vista',
      (tester) async {
    final elegido = await abrir(tester, previa: (_) => throw StateError('x'));
    expect(find.textContaining('Mesa '), findsNothing);
    await tester.tap(find.byKey(const Key('dar_mesa_confirmar')));
    await tester.pumpAndSettle();
    expect(elegido.single, {'luna', 'rivas'});
  });

  testWidgets('cancelar no da nada', (tester) async {
    final elegido = await abrir(tester);
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    expect(elegido.single, isNull);
  });
}
