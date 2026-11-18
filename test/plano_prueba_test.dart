// La ventana de prueba del plano (tool/plano_prueba.dart) anda: abre sin base ni
// nube y hace lo mismo que la app. Si deja de compilar o de guardar, salta acá.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';

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

  testWidgets('la barra reacomoda en vivo, y soltar deja deshacer',
      (tester) async {
    await abrir(tester);
    expect(find.text('DISTANCIA ENTRE MESAS'), findsOneWidget);
    expect(find.text('SEPARAR O JUNTAR'), findsNothing);
    final barra = find.byKey(const Key('distancia_mesas'));
    tester.widget<Slider>(barra).onChanged!(2.5);
    await tester.pump();
    expect(find.text('2,5 m'), findsOneWidget);
    expect(find.text('Entran las 35.'), findsOneWidget);
    tester.widget<Slider>(barra).onChangeEnd!(2.5);
    await tester.pump();
    expect(find.textContaining('Las mesas se acomodaron a 2,5 m'), findsOneWidget);

    final deshacer = find.byKey(const Key('acomodar_deshacer'));
    await tester.ensureVisible(deshacer);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(deshacer);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('3 m'), findsOneWidget, reason: 'la distancia de antes');
    expect(find.text('Entran las 35.'), findsNothing);
  });

  testWidgets('con familias con mesa, la barra estira', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('prueba_sentados')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SEPARAR O JUNTAR'), findsOneWidget);
    expect(find.text('DISTANCIA ENTRE MESAS'), findsNothing);
    expect(
      find.textContaining('se estira sin cambiar ninguna mesa'),
      findsOneWidget,
    );
  });

  testWidgets('con familias con mesa, los números no cambian', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('prueba_sentados')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('13 saltos'), findsOneWidget);
    expect(find.textContaining('Los números se ordenan'), findsNothing);
  });

  testWidgets('sortea de verdad sobre el salón ordenado, y se deshace',
      (tester) async {
    await abrir(tester);
    await guardar(tester);
    await tester.tap(find.byKey(const Key('prueba_sortear')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Sorteo en esta ventana: 29 familias'),
      findsOneWidget,
      reason: 'las familias piden justo las 35 mesas, con dos "lejos"',
    );
    expect(find.text('SEPARAR O JUNTAR'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prueba_deshacer')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('DISTANCIA ENTRE MESAS'), findsOneWidget);
  });

  // Lo encontró el recorrido con el mouse: en un salón con el playón entero, acercar
  // no traía nunca ni el apellido ni la flecha de las familias separadas.
  testWidgets('al acercar el plano aparecen los apellidos y las flechas',
      (tester) async {
    await abrir(tester);
    await guardar(tester);
    await tester.tap(find.byKey(const Key('prueba_sortear')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('salir_personalizar')));
    await tester.pump(const Duration(milliseconds: 400));

    PintorPlano pintor() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<PintorPlano>()
        .single;
    int textos() {
      final lienzo = _LienzoQueCuenta();
      pintor().paint(lienzo, tester.getSize(find.byType(VistaPlano)));
      return lienzo.textos;
    }

    final lejos = textos();
    final sinAcercar = pintor();
    await tester.tap(find.byKey(const Key('acercar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('acercar')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('acercar')));
    await tester.pump();
    expect(pintor().zoom, greaterThan(sinAcercar.zoom));
    expect(
      textos() - lejos,
      29 + 2 + 4 + 11,
      reason: 'el apellido de las 29 familias, el de las 2 mesas lejos, sus 4 '
          'flechas, y la P o la A de las 11 mesas de familias con adicional, '
          'que en este tamaño de ventana también aparecen al acercar',
    );
  });

  group('la mesa adicional "a confirmar" (6.9.2)', () {
    Future<void> sentar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PruebaDelPlano()));
      await tester.pump();
      await tester.tap(find.byKey(const Key('prueba_sentados')));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> elegir(WidgetTester tester, String id, String apellido) async {
      await tester.enterText(find.byKey(const Key('buscar')), apellido);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(Key('resultado_$id')));
      await tester.pump(const Duration(milliseconds: 400));
    }

    bool aConfirmar(WidgetTester tester, int mesa) => tester
        .widget<VistaPlano>(find.byType(VistaPlano))
        .estado
        .info(mesa)
        .aConfirmar;

    bool prendido(WidgetTester tester, String clave) =>
        tester.widget<OutlinedButton>(find.byKey(Key(clave))).onPressed != null;

    testWidgets('PEREZ (sin nada pagado) y SOSA (con una parte) la tienen '
        'punteada; las demás, no', (tester) async {
      await sentar(tester);
      expect(aConfirmar(tester, 6), isTrue);
      expect(aConfirmar(tester, 11), isTrue);
      expect(aConfirmar(tester, 2), isFalse);
      expect(aConfirmar(tester, 5), isFalse);
    });

    testWidgets('ANULAR la de PEREZ: deja la 6 y la adicional sale de su '
        'contrato', (tester) async {
      await sentar(tester);
      await elegir(tester, 'dos', 'PEREZ');
      expect(find.text('Mesa adicional 6 · a confirmar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('anular_a_confirmar_6')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Anular la mesa 6 de PEREZ'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(
        find.text('PEREZ dejó la 6. La mesa adicional se bajó de su contrato.'),
        findsOneWidget,
      );
      expect(aConfirmar(tester, 6), isFalse);
      expect(find.text('Mesa adicional 6 · a confirmar'), findsNothing);
      expect(find.byKey(const Key('sillas_mesa_5')), findsOneWidget);
      expect(find.byKey(const Key('sillas_mesa_6')), findsNothing);
    });

    testWidgets('sin internet no se anula', (tester) async {
      await sentar(tester);
      await tester.tap(find.byKey(const Key('prueba_internet')));
      await tester.pump(const Duration(milliseconds: 400));
      await elegir(tester, 'dos', 'PEREZ');
      await tester.tap(find.byKey(const Key('anular_a_confirmar_6')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('hace falta internet'), findsOneWidget);
      expect(aConfirmar(tester, 6), isTrue);
    });

    testWidgets('la de SOSA tiene algo pagado: no se anula, y al cobrarla '
        'vuelve sola a la normalidad', (tester) async {
      await sentar(tester);
      await elegir(tester, 'otra', 'SOSA');
      expect(prendido(tester, 'anular_a_confirmar_11'), isFalse);
      expect(find.textContaining('esta noche no se anula'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cobrar_a_confirmar_11')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(aConfirmar(tester, 11), isFalse);
      expect(find.byKey(const Key('sillas_mesa_11')), findsOneWidget);
    });

    testWidgets('sin modo jefe se ve "a confirmar" y nada más', (tester) async {
      await sentar(tester);
      await tester.tap(find.byKey(const Key('prueba_jefe')));
      await tester.pump(const Duration(milliseconds: 400));
      await elegir(tester, 'dos', 'PEREZ');
      expect(find.text('Mesa adicional 6 · a confirmar'), findsOneWidget);
      expect(find.byKey(const Key('a_pagar_6')), findsNothing);
      expect(prendido(tester, 'cobrar_a_confirmar_6'), isFalse);
      expect(prendido(tester, 'anular_a_confirmar_6'), isFalse);
    });
  });
}

/// Un lienzo que no dibuja nada y cuenta los textos que le piden.
class _LienzoQueCuenta implements Canvas {
  int textos = 0;

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => textos++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
