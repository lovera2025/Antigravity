import 'dart:io';

import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Girar la tele (25-nov-2026): la tele colgada parada.
void main() {
  group('Horizontal · Vertical · Dar vuelta', () {
    test('elegir la que ya tiene no la cambia; cambiar va a la de siempre', () {
      expect(Giro.vertical(0), 1);
      expect(Giro.vertical(2), 1);
      expect(Giro.vertical(1), 1);
      expect(Giro.vertical(3), 3, reason: 'parada para el otro lado: queda');
      expect(Giro.horizontal(1), 0);
      expect(Giro.horizontal(3), 0);
      expect(Giro.horizontal(2), 2, reason: 'acostada dada vuelta: queda');
      expect(Giro.darVuelta(0), 2);
      expect(Giro.darVuelta(1), 3);
      expect(Giro.darVuelta(3), 1);
      expect(Giro.nombre(1), 'Vertical');
      expect(Giro.nombre(2), 'Horizontal');
    });

    test('cada tele recuerda la suya (tele_giro_v1)', () async {
      SharedPreferences.setMockInitialValues({});
      await GiroGuardado.guardar(3);
      expect((await SharedPreferences.getInstance()).getInt('tele_giro_v1'), 3);
      await GiroGuardado.cargar();
      expect(GiroGuardado.leido, 3);
      // Acostada, como siempre: no deja nada guardado.
      await GiroGuardado.guardar(0);
      expect((await SharedPreferences.getInstance()).containsKey('tele_giro_v1'), isFalse);
      SharedPreferences.setMockInitialValues({'tele_giro_v1': 6});
      await GiroGuardado.cargar();
      expect(GiroGuardado.leido, 2);
      await GiroGuardado.guardar(0);
    });
  });

  group('las flechas del control, como las ve quien mira', () {
    test('parada (1): arriba en lo que se ve es derecha en la pantalla acostada', () {
      expect(TeleGirada.enLaPantalla(TraversalDirection.up, 1), TraversalDirection.right);
      expect(TeleGirada.enLaPantalla(TraversalDirection.down, 1), TraversalDirection.left);
      expect(TeleGirada.enLaPantalla(TraversalDirection.right, 1), TraversalDirection.down);
      expect(TeleGirada.enLaPantalla(TraversalDirection.left, 1), TraversalDirection.up);
      expect(TeleGirada.enLaPantalla(TraversalDirection.up, 3), TraversalDirection.left);
      expect(TeleGirada.enLaPantalla(TraversalDirection.up, 2), TraversalDirection.down);
      for (final d in TraversalDirection.values) {
        expect(TeleGirada.enLaPantalla(d, 0), d);
      }
    });

    test('acostada, las flechas son las de Flutter, como siempre', () {
      expect(TeleGirada.flechasGiradas(0), isEmpty);
      expect(TeleGirada.flechasGiradas(1), hasLength(4));
    });

    test('la que sigue: en un teclado de 3 × 4, la de al lado y la de abajo', () {
      // Teclas de 80 × 50, con 10 de hueco.
      final teclas = {
        for (var f = 0; f < 4; f++)
          for (var c = 0; c < 3; c++) '${f * 3 + c + 1}': Rect.fromLTWH(c * 90.0, f * 60.0, 80, 50),
      };
      Rect de(String t) => teclas[t]!;
      Map<String, Rect> menos(String t) => Map.of(teclas)..remove(t);
      expect(TeleGirada.siguiente(de('1'), TraversalDirection.right, menos('1')), '2');
      expect(TeleGirada.siguiente(de('1'), TraversalDirection.down, menos('1')), '4');
      expect(TeleGirada.siguiente(de('5'), TraversalDirection.up, menos('5')), '2');
      expect(TeleGirada.siguiente(de('5'), TraversalDirection.left, menos('5')), '4');
      expect(TeleGirada.siguiente(de('1'), TraversalDirection.up, menos('1')), isNull);
      expect(TeleGirada.siguiente(de('3'), TraversalDirection.right, menos('3')), isNull);
      // Una tecla ancha abajo (CANCELAR): se llega desde cualquiera.
      final conAncha = {...menos('11'), 'CANCELAR': const Rect.fromLTWH(0, 240, 260, 50)};
      expect(TeleGirada.siguiente(de('12'), TraversalDirection.down, conAncha), 'CANCELAR');
    });

    testWidgets('la flecha de abajo va a la opción de abajo, en los cuatro giros', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      for (final cuartos in [0, 1, 2, 3]) {
        final focos = [for (var i = 0; i < 3; i++) FocusNode(debugLabel: 'opción $i')];
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(cuartos),
          builder: (context, child) => TeleGirada(cuartos: cuartos, child: child!),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, f) in focos.indexed)
                    TextButton(focusNode: f, onPressed: () {}, child: Text('Opción $i')),
                ],
              ),
            ),
          ),
        ));
        focos.first.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(focos[1].hasPrimaryFocus, isTrue, reason: 'giro $cuartos: abajo');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(focos[2].hasPrimaryFocus, isTrue, reason: 'giro $cuartos: abajo otra vez');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(focos[1].hasPrimaryFocus, isTrue, reason: 'giro $cuartos: arriba');
        for (final f in focos) {
          f.dispose();
        }
      }
    });
  });

  group('las medidas', () {
    testWidgets('parada, quien mira ve 540 × 960', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late Size vista;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => TeleGirada(cuartos: 1, child: child!),
        home: Builder(builder: (context) {
          vista = MediaQuery.sizeOf(context);
          return const SizedBox.expand();
        }),
      ));
      expect(vista, const Size(540, 960));
      expect(tester.getSize(find.byType(SizedBox).last), const Size(540, 960));
    });

    test('los bordes giran con la pantalla', () {
      const m = MediaQueryData(
        size: Size(960, 540),
        padding: EdgeInsets.fromLTRB(1, 2, 3, 4),
      );
      // Lo de arriba de lo girado queda a la derecha de la pantalla.
      expect(TeleGirada.medidasGiradas(m, 1).padding, const EdgeInsets.fromLTRB(2, 3, 4, 1));
      expect(TeleGirada.medidasGiradas(m, 2).padding, const EdgeInsets.fromLTRB(3, 4, 1, 2));
      expect(TeleGirada.medidasGiradas(m, 3).padding, const EdgeInsets.fromLTRB(4, 1, 2, 3));
      expect(TeleGirada.medidasGiradas(m, 2).size, const Size(960, 540));
      expect(TeleGirada.medidasGiradas(m, 0), same(m));
    });
  });

  group('en la PC no cambia nada', () {
    testWidgets('sin modo tele, el hijo tal cual (aunque haya un giro guardado)', (tester) async {
      const hijo = SizedBox(key: ValueKey('hijo'));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          modoTeleProvider.overrideWith(_SinModoTele.new),
          giroDeLaTeleProvider.overrideWith(_GiroUno.new),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: GiroDeLaApp(child: hijo),
        ),
      ));
      expect(find.byType(RotatedBox), findsNothing);
      expect(find.byType(Shortcuts), findsNothing);
      expect(find.byKey(const ValueKey('hijo')), findsOneWidget);
    });

    testWidgets('en modo tele, girada', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          modoTeleProvider.overrideWith(_ConModoTele.new),
          giroDeLaTeleProvider.overrideWith(_GiroUno.new),
        ],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: GiroDeLaApp(child: SizedBox()),
        ),
      ));
      expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    });

    test('main.dart gira con GiroDeLaApp en el builder y lee el giro antes de abrir', () {
      final main = File('lib/main.dart').readAsStringSync();
      final builder = main.substring(main.indexOf('class JuniorEventsApp'));
      expect(builder, contains('GiroDeLaApp(child:'));
      expect(main, contains('await GiroGuardado.cargar()'));
    });
  });
}

class _SinModoTele extends ModoTeleNotifier {
  @override
  ModoTele? build() => null;
}

class _ConModoTele extends ModoTeleNotifier {
  @override
  ModoTele? build() => const ModoTele(PapelDeLaTele.principal);
}

class _GiroUno extends GiroDeLaTeleNotifier {
  @override
  int build() => 1;
}
