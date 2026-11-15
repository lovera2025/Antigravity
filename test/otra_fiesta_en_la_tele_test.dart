// Cambiar de evento en Recepción con el tótem abierto en otra fiesta: antes de
// mover la tele del salón, se pregunta (revisión del 13-nov). Con el lanzador
// del tótem de verdad y ventanas de mentira, como `kiosk_launcher_test.dart`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/services/kiosk_launcher.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/widgets/otra_fiesta_en_la_tele.dart';

import 'helpers/puerta_en_memoria.dart';

class _Ventanas implements VentanasTotem {
  final llegaron = <String>[];
  final argumentos = <dynamic>[];
  final abiertasAhora = <int>[];

  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) async {
    llegaron.add(metodo);
    argumentos.add(args);
    return null;
  }

  @override
  Future<List<int>> abiertas() async => List.of(abiertasAhora);

  @override
  Future<int> crear(
    String argumentos, {
    required Size tamanio,
    required String titulo,
  }) async {
    abiertasAhora.add(1);
    return 1;
  }

  @override
  Future<void> mostrar(int id) async {}

  @override
  Future<void> esconder(int id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('¿hay que preguntar?', () {
    bool pregunta({bool hayTotem = true, String? enLaTele, String? nuevo}) =>
        hayQuePreguntarPorLaTele(
          hayTotem: hayTotem,
          enLaTele: enLaTele,
          nuevo: nuevo,
        );

    test('solo con el tótem abierto y en otra fiesta', () {
      expect(pregunta(enLaTele: 'a', nuevo: 'b'), isTrue);
      expect(pregunta(enLaTele: 'a', nuevo: 'a'), isFalse);
      expect(pregunta(hayTotem: false, enLaTele: 'a', nuevo: 'b'), isFalse);
      expect(pregunta(enLaTele: null, nuevo: 'b'), isFalse);
      expect(pregunta(enLaTele: 'a', nuevo: null), isFalse,
          reason: 'limpiar la selección no toca el tótem');
    });
  });

  group('en Recepción', () {
    late _Ventanas ventanas;
    late ProviderContainer c;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      KioskLauncher.reiniciar();
      ventanas = _Ventanas();
      KioskLauncher.ventanas = ventanas;
      KioskLauncher.esperaEntreIntentos = Duration.zero;
    });

    tearDown(KioskLauncher.reiniciar);

    /// Una pantalla con un botón que elige [eventoParticular], como el
    /// desplegable de Recepción.
    Future<void> montar(WidgetTester tester) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: FilledButton(
                  onPressed: () => elegirEventoEnRecepcion(
                    context,
                    ref,
                    eventoParticular,
                    eventos: [
                      eventoDePrueba(eventoMasivo, 'masivo'),
                      eventoDePrueba(eventoParticular, 'particular'),
                    ],
                  ),
                  child: const Text('ELEGIR LA OTRA'),
                ),
              ),
            ),
          ),
        ),
      ));
      c = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    }

    Future<void> elegirLaOtra(WidgetTester tester) async {
      await tester.tap(find.text('ELEGIR LA OTRA'));
      await tester.pumpAndSettle();
    }

    /// El tótem abierto con la fiesta de esta noche, y Recepción mirándola.
    Future<void> conElTotemEnLaDeHoy(WidgetTester tester) async {
      await tester.runAsync(() => KioskLauncher.launch(eventoMasivo));
      await montar(tester);
      c.read(selectedEventProvider.notifier).select(eventoMasivo);
      ventanas.llegaron.clear();
      ventanas.argumentos.clear();
    }

    final cartel = find.byKey(const Key('otra_fiesta_en_la_tele'));

    testWidgets('sin tótem abierto, cambia sin preguntar', (tester) async {
      await montar(tester);
      await elegirLaOtra(tester);
      expect(cartel, findsNothing);
      expect(c.read(selectedEventProvider), eventoParticular);
    });

    testWidgets('con el tótem en otra fiesta, pregunta antes de moverlo',
        (tester) async {
      await conElTotemEnLaDeHoy(tester);
      await elegirLaOtra(tester);

      expect(cartel, findsOneWidget);
      expect(find.text('El tótem está con otra fiesta'), findsOneWidget);
      // Todavía no cambió nada: ni lo que se mira acá ni la tele.
      expect(c.read(selectedEventProvider), eventoMasivo);
      expect(KioskLauncher.totemEventoId, eventoMasivo);
      expect(ventanas.llegaron, isEmpty);
    });

    testWidgets('SOLO MIRAR ACÁ: cambia esta pantalla y la tele queda como está',
        (tester) async {
      await conElTotemEnLaDeHoy(tester);
      await elegirLaOtra(tester);
      await tester.tap(find.byKey(const Key('tele_solo_mirar')));
      await tester.pumpAndSettle();

      expect(cartel, findsNothing);
      expect(c.read(selectedEventProvider), eventoParticular);
      expect(KioskLauncher.totemEventoId, eventoMasivo);
      expect(ventanas.llegaron, isNot(contains('set_evento')));
    });

    testWidgets('PASAR EL TÓTEM: cambia las dos', (tester) async {
      await conElTotemEnLaDeHoy(tester);
      await elegirLaOtra(tester);
      await tester.tap(find.byKey(const Key('tele_pasarla')));
      await tester.pumpAndSettle();

      expect(c.read(selectedEventProvider), eventoParticular);
      expect(KioskLauncher.totemEventoId, eventoParticular);
      expect(ventanas.llegaron, contains('set_evento'));
      expect(ventanas.argumentos, contains(eventoParticular));
    });

    testWidgets('cerrar la pregunta sin elegir no cambia nada', (tester) async {
      await conElTotemEnLaDeHoy(tester);
      await elegirLaOtra(tester);
      await tester.tapAt(const Offset(5, 5)); // afuera del cartel
      await tester.pumpAndSettle();

      expect(cartel, findsNothing);
      expect(c.read(selectedEventProvider), eventoMasivo);
      expect(KioskLauncher.totemEventoId, eventoMasivo);
      expect(ventanas.llegaron, isEmpty);
    });

    testWidgets('con el tótem ya en esa fiesta, no pregunta', (tester) async {
      await tester.runAsync(() => KioskLauncher.launch(eventoParticular));
      await montar(tester);
      await elegirLaOtra(tester);
      expect(cartel, findsNothing);
      expect(c.read(selectedEventProvider), eventoParticular);
    });
  });

  // Revisión final de la 6.9.0: después de un SOLO MIRAR ACÁ, el botón TÓTEM
  // del Centro de Comando pasaba la tele a la fiesta de Recepción sin avisar.
  group('al volver a mostrar la tele desde el Centro de Comando', () {
    late _Ventanas ventanas;
    String? laQueVa;
    var contesto = false;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      KioskLauncher.reiniciar();
      ventanas = _Ventanas();
      KioskLauncher.ventanas = ventanas;
      KioskLauncher.esperaEntreIntentos = Duration.zero;
      laQueVa = null;
      contesto = false;
    });

    tearDown(KioskLauncher.reiniciar);

    Future<void> tocarTotem(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  laQueVa = await fiestaParaAbrirLaTele(
                    context,
                    elegido: eventoParticular,
                    eventos: [
                      eventoDePrueba(eventoMasivo, 'masivo'),
                      eventoDePrueba(eventoParticular, 'particular'),
                    ],
                  );
                  contesto = true;
                },
                child: const Text('TÓTEM'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('TÓTEM'));
      await tester.pumpAndSettle();
    }

    final cartel = find.byKey(const Key('otra_fiesta_al_abrir_la_tele'));

    testWidgets('sin tótem abierto, abre con la de Recepción sin preguntar',
        (tester) async {
      await tocarTotem(tester);
      expect(cartel, findsNothing);
      expect(laQueVa, eventoParticular);
    });

    testWidgets('con la tele en otra fiesta, pregunta; SEGUIR la deja con la suya',
        (tester) async {
      await tester.runAsync(() => KioskLauncher.launch(eventoMasivo));
      await tocarTotem(tester);
      expect(cartel, findsOneWidget);
      expect(contesto, isFalse);
      await tester.tap(find.byKey(const Key('tele_seguir_con_la_suya')));
      await tester.pumpAndSettle();
      expect(laQueVa, eventoMasivo);
    });

    testWidgets('PASAR EL TÓTEM la pasa a la de Recepción', (tester) async {
      await tester.runAsync(() => KioskLauncher.launch(eventoMasivo));
      await tocarTotem(tester);
      await tester.tap(find.byKey(const Key('tele_pasarla_al_abrir')));
      await tester.pumpAndSettle();
      expect(laQueVa, eventoParticular);
    });

    testWidgets('cerrar la pregunta sin elegir no abre nada', (tester) async {
      await tester.runAsync(() => KioskLauncher.launch(eventoMasivo));
      await tocarTotem(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(contesto, isTrue);
      expect(laQueVa, isNull);
    });
  });

  test('el botón TÓTEM del Centro de Comando pasa por la pregunta', () {
    final fuente = File('lib/features/dashboard/dashboard_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final i = fuente.indexOf('Future<void> _abrirTotem() async {');
    expect(i, greaterThanOrEqualTo(0));
    final cuerpo = fuente.substring(i, fuente.indexOf('\n  }\n', i));
    final pregunta = cuerpo.indexOf('fiestaParaAbrirLaTele(');
    expect(pregunta, greaterThanOrEqualTo(0),
        reason: 'con un evento elegido, el botón TÓTEM tiene que preguntar');
    expect(cuerpo.indexOf('KioskLauncher.launch(eventoId)'), greaterThan(pregunta));
  });

  test('el desplegable de Recepción pasa por la pregunta', () {
    // Si volviera a llamar a `select` derecho, la tele se movería sin avisar.
    final fuente =
        File('lib/features/recepcion/recepcion_unified_screen.dart')
            .readAsStringSync();
    expect(fuente, contains('elegirEventoEnRecepcion(context, ref, value'));
    expect(
      fuente,
      isNot(contains('selectedEventProvider.notifier).select(value)')),
    );
  });
}
