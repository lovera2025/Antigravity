// Los cuatro botones de la fiesta (PLANO, SORTEO, PLANILLAS y ENTRADAS) que
// van a la vista en la barra del evento masivo, al lado de MÁS.
import 'package:arguello_events/features/eventos/widgets/grupo_fiesta_toolbar.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Dibuja el grupo en un lugar de [ancho] y anota qué se pidió.
  Future<List<String>> mostrar(
    WidgetTester tester, {
    double ancho = 800,
    bool compacto = false,
    bool conCopia = false,
    bool conPlano = true,
    bool conAlumnos = true,
    int conMora = 3,
    bool esJefe = true,
    String? letra,
  }) async {
    final pedidos = <String>[];
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: letra),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: ancho,
              child: GrupoFiestaToolbar(
                compacto: compacto,
                esJefe: esJefe,
                onPlano: () => pedidos.add('plano'),
                onSortear: () => pedidos.add('sortear'),
                onDeshacer: () => pedidos.add('deshacer'),
                onRestaurar: conCopia ? () => pedidos.add('restaurar') : null,
                onHistorial: () => pedidos.add('historial'),
                onPlanillaSorteo:
                    conAlumnos ? () => pedidos.add('planilla') : null,
                onPlanoImpreso:
                    conPlano ? () => pedidos.add('plano impreso') : null,
                onPlanillaEntrega: () => pedidos.add('entrega'),
                onPlanillaMora: conMora > 0 ? () => pedidos.add('mora') : null,
                alumnosConMora: conMora,
                onEntradas: () => pedidos.add('entradas'),
              ),
            ),
          ),
        ),
      ),
    );
    return pedidos;
  }

  const nombres = ['PLANO', 'SORTEO', 'PLANILLAS', 'ENTRADAS'];

  /// Abre un menú del grupo y toca un renglón.
  Future<void> elegir(WidgetTester tester, String menu, String renglon) async {
    await tester.tap(find.byKey(Key(menu)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(renglon));
    await tester.pumpAndSettle();
  }

  testWidgets('con lugar, los cuatro botones van con su nombre', (tester) async {
    await mostrar(tester);
    for (final n in nombres) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin lugar quedan los íconos, y el nombre al pasar el mouse',
      (tester) async {
    await mostrar(tester, ancho: 300);
    for (final n in nombres) {
      expect(find.text(n), findsNothing, reason: n);
    }
    for (final clave in [
      'fiesta_plano',
      'fiesta_sorteo',
      'fiesta_planillas',
      'fiesta_entradas',
    ]) {
      expect(find.byKey(Key(clave)), findsOneWidget, reason: clave);
    }
    expect(find.byTooltip('Sorteo de mesas'), findsOneWidget);
    expect(find.byTooltip('Planillas para imprimir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ni en una ventana muy angosta se desborda', (tester) async {
    await mostrar(tester, ancho: 90, compacto: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PLANO y ENTRADAS abren su pantalla de un toque', (tester) async {
    final pedidos = await mostrar(tester);
    await tester.tap(find.byKey(const Key('fiesta_plano')));
    await tester.tap(find.byKey(const Key('fiesta_entradas')));
    expect(pedidos, ['plano', 'entradas']);
  });

  testWidgets('SORTEO trae sortear, deshacer y el historial', (tester) async {
    final pedidos = await mostrar(tester);
    await tester.tap(find.byKey(const Key('fiesta_sorteo')));
    await tester.pumpAndSettle();
    expect(find.text('Sortear mesas'), findsOneWidget);
    expect(find.text('Deshacer sorteo de mesas'), findsOneWidget);
    expect(find.text('Historial de las mesas'), findsOneWidget);
    // Sin copia guardada no hay nada que restaurar.
    expect(find.text('Restaurar sorteo anterior'), findsNothing);
    await tester.tap(find.text('Sortear mesas'));
    await tester.pumpAndSettle();

    await elegir(tester, 'fiesta_sorteo', 'Deshacer sorteo de mesas');
    await elegir(tester, 'fiesta_sorteo', 'Historial de las mesas');
    expect(pedidos, ['sortear', 'deshacer', 'historial']);
  });

  testWidgets('Restaurar aparece solo si hay una copia guardada',
      (tester) async {
    final pedidos = await mostrar(tester, conCopia: true);
    await elegir(tester, 'fiesta_sorteo', 'Restaurar sorteo anterior');
    expect(pedidos, ['restaurar']);
  });

  testWidgets('PLANILLAS trae las cuatro, cada una con lo suyo',
      (tester) async {
    final pedidos = await mostrar(tester);
    await tester.tap(find.byKey(const Key('fiesta_planillas')));
    await tester.pumpAndSettle();
    expect(find.text('3 alumno(s) para llamar'), findsOneWidget);
    await tester.tap(find.text('Planilla del sorteo'));
    await tester.pumpAndSettle();

    await elegir(tester, 'fiesta_planillas', 'Plano impreso');
    await elegir(tester, 'fiesta_planillas', 'Planilla de entrega');
    await elegir(tester, 'fiesta_planillas', 'Planilla de mora');
    expect(pedidos, ['planilla', 'plano impreso', 'entrega', 'mora']);
  });

  testWidgets('lo que no se puede queda apagado y dice por qué',
      (tester) async {
    final pedidos = await mostrar(
      tester,
      conPlano: false,
      conAlumnos: false,
      conMora: 0,
    );
    await tester.tap(find.byKey(const Key('fiesta_planillas')));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay alumnos'), findsOneWidget);
    expect(find.text('Todavía no hay plano: armalo en PLANO'), findsOneWidget);
    expect(find.text('Nadie debe mora'), findsOneWidget);

    for (final apagado in [
      'Planilla del sorteo',
      'Plano impreso',
      'Planilla de mora',
    ]) {
      await tester.tap(find.text(apagado), warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(pedidos, isEmpty);
    // El menú sigue abierto: tocar algo apagado no hace nada.
    expect(find.text('Planilla de entrega'), findsOneWidget);
  });

  // Lo que cambia el salón lo hace solo el jefe. Sin modo jefe se ve, apagado
  // y con el motivo: así el operario sabe que existe y a quién pedírselo.
  group('sin modo jefe', () {
    testWidgets('sortear, deshacer y restaurar quedan apagados y dicen por qué',
        (tester) async {
      final pedidos = await mostrar(tester, esJefe: false, conCopia: true);
      await tester.tap(find.byKey(const Key('fiesta_sorteo')));
      await tester.pumpAndSettle();
      expect(find.text('Solo en modo jefe'), findsNWidgets(3));
      // El motivo reemplaza al detalle de siempre.
      expect(find.text('La copia guardada al deshacer'), findsNothing);

      for (final apagado in [
        'Sortear mesas',
        'Deshacer sorteo de mesas',
        'Restaurar sorteo anterior',
      ]) {
        await tester.tap(find.text(apagado), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(pedidos, isEmpty);
      // El menú sigue abierto: tocar algo apagado no hace nada.
      expect(find.text('Historial de las mesas'), findsOneWidget);
    });

    testWidgets('el Historial se sigue pudiendo abrir', (tester) async {
      final pedidos = await mostrar(tester, esJefe: false);
      await elegir(tester, 'fiesta_sorteo', 'Historial de las mesas');
      expect(pedidos, ['historial']);
    });

    testWidgets('PLANO, PLANILLAS y ENTRADAS andan igual', (tester) async {
      final pedidos = await mostrar(tester, esJefe: false);
      await tester.tap(find.byKey(const Key('fiesta_plano')));
      await tester.tap(find.byKey(const Key('fiesta_entradas')));
      await elegir(tester, 'fiesta_planillas', 'Planilla del sorteo');
      await elegir(tester, 'fiesta_planillas', 'Plano impreso');
      await elegir(tester, 'fiesta_planillas', 'Planilla de entrega');
      await elegir(tester, 'fiesta_planillas', 'Planilla de mora');
      expect(pedidos, [
        'plano',
        'entradas',
        'planilla',
        'plano impreso',
        'entrega',
        'mora',
      ]);
      expect(find.text('Solo en modo jefe'), findsNothing);
    });

    testWidgets('en modo jefe no aparece el motivo', (tester) async {
      await mostrar(tester, conCopia: true);
      await tester.tap(find.byKey(const Key('fiesta_sorteo')));
      await tester.pumpAndSettle();
      expect(find.text('Solo en modo jefe'), findsNothing);
      expect(find.text('La copia guardada al deshacer'), findsOneWidget);
    });
  });

  group('MÁS', () {
    Future<List<String>> mostrarMas(
      WidgetTester tester, {
      bool? listaPuertaHabilitada,
    }) async {
      final pedidos = <String>[];
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      BotonMasFiesta boton() => listaPuertaHabilitada == null
          ? BotonMasFiesta(
              compacto: false,
              ordenAlfabetico: true,
              modoSeleccion: false,
              onOrden: () => pedidos.add('orden'),
              onSeleccion: () => pedidos.add('seleccion'),
              onListaPuerta: () => pedidos.add('puerta'),
            )
          : BotonMasFiesta(
              compacto: false,
              ordenAlfabetico: true,
              modoSeleccion: false,
              onOrden: () => pedidos.add('orden'),
              onSeleccion: () => pedidos.add('seleccion'),
              onListaPuerta: () => pedidos.add('puerta'),
              listaPuertaHabilitada: listaPuertaHabilitada,
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: boton()),
          ),
        ),
      );
      return pedidos;
    }

    testWidgets('queda lo que no es de la fiesta, y nada de lo que se mudó',
        (tester) async {
      final pedidos = await mostrarMas(tester);
      await tester.tap(find.byKey(const Key('fiesta_mas')));
      await tester.pumpAndSettle();
      expect(find.text('Ordenar por fecha'), findsOneWidget);
      expect(find.text('Selección múltiple'), findsOneWidget);
      expect(find.text('Pasar a la lista de la puerta'), findsOneWidget);
      for (final mudado in [
        'Plano del salón',
        'Planilla del sorteo',
        'Retiro de entradas',
        'Planilla de mora',
        'Sortear mesas',
        'Deshacer sorteo de mesas',
        'Historial de las mesas',
      ]) {
        expect(find.text(mudado), findsNothing, reason: mudado);
      }
      await tester.tap(find.text('Ordenar por fecha'));
      await tester.pumpAndSettle();
      await elegir(tester, 'fiesta_mas', 'Selección múltiple');
      expect(pedidos, ['orden', 'seleccion']);
    });

    testWidgets('la lista de la puerta está trabada y dice hasta cuándo',
        (tester) async {
      // Sin decirle nada, el botón toma la bandera de la app.
      final pedidos = await mostrarMas(tester);
      await tester.tap(find.byKey(const Key('fiesta_mas')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Se habilita en diciembre, cuando se cierren los permisos de la '
          'lista',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.text('Pasar a la lista de la puerta'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(pedidos, isEmpty);
    });

    testWidgets('con la lista habilitada, el renglón vuelve a andar',
        (tester) async {
      final pedidos = await mostrarMas(tester, listaPuertaHabilitada: true);
      await elegir(tester, 'fiesta_mas', 'Pasar a la lista de la puerta');
      expect(pedidos, ['puerta']);
    });
  });

  group('con la letra de la app', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await cargarFuentesPlano();
    });

    for (final compacto in [false, true]) {
      testWidgets(
          'los cuatro nombres entran en el ancho que se les pide '
          '(${compacto ? 'barra chica' : 'barra grande'})', (tester) async {
        final pedido = GrupoFiestaToolbar.anchoConNombres(compacto: compacto);
        await mostrar(
          tester,
          ancho: pedido,
          compacto: compacto,
          letra: FuentesPlano.linea,
        );
        expect(find.text('PLANILLAS'), findsOneWidget);
        final grupo = tester.getSize(find.byKey(const Key('fiesta_grupo')));
        expect(grupo.width, lessThanOrEqualTo(pedido));
      });

      testWidgets(
          'solo con íconos entra en lo que la barra le reserva '
          '(${compacto ? 'barra chica' : 'barra grande'})', (tester) async {
        final reservado = GrupoFiestaToolbar.anchoSoloIconos(compacto: compacto);
        await mostrar(
          tester,
          ancho: reservado,
          compacto: compacto,
          letra: FuentesPlano.linea,
        );
        expect(find.text('PLANILLAS'), findsNothing);
        final grupo = tester.getSize(find.byKey(const Key('fiesta_grupo')));
        expect(grupo.width, lessThanOrEqualTo(reservado));
      });
    }
  });
}
