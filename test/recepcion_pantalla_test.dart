// Recepción entera (paso 3c de la 6.0.0): la lista y la vista del tótem según
// la pantalla. En la PC, lado a lado; en una tablet, en pestañas; en el
// celular, la lista sola con la paleta arriba. Sobre la vista, un solo botón.
// Con la puerta en memoria y sin internet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';
import 'package:arguello_events/features/recepcion/widgets/panel_puerta.dart';
import 'package:arguello_events/features/recepcion/widgets/vista_del_totem.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/features/totem/widgets/totem_local.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/ficha_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

/// Se crea en `setUpAll`: creado adentro de un test deja un reloj suyo andando.
late SupabaseClient _supabase;

const _celular = Size(360, 740);
const _tablet = Size(800, 1280);
const _pc = Size(1366, 768);

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<PuertaEnMemoria> _abrir(
  WidgetTester tester, {
  Size tamano = _pc,
  String? elegido = eventoMasivo,
  bool puedeTotem = true,
}) async {
  final mundo = PuertaEnMemoria(_supabase, alumnos: alumnosDeLaFicha());
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  // Si ya había una abierta, que se vaya con sus providers: un ProviderScope
  // nuevo en el mismo lugar se queda con los de antes.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    mundo.recepcion(
      const RecepcionUnifiedScreen(),
      elegido: elegido,
      puedeTotem: puedeTotem,
      config: const {
        eventoMasivo: TotemConfig(
          eventoId: eventoMasivo,
          titulo: 'PROMOCIÓN 2026',
        ),
      },
      // Outfit, como la app: con la letra de prueba cada letra mide lo que su
      // tamaño.
      tema: ThemeData(
        brightness: Brightness.dark,
        fontFamily: FuentesTotem.linea,
        useMaterial3: true,
      ),
    ),
  );
  await _asentar(tester);
  return mundo;
}

final _paleta = find.byTooltip(BotonPersonalizarTotem.ayuda);
Finder _enLaBarra(Finder f) =>
    find.descendant(of: find.byType(AppBar), matching: f);
Finder _enLaVista(Finder f) =>
    find.descendant(of: find.byType(VistaDelTotem), matching: f);

/// Cualquier botón. Sin `ButtonStyleButton` a secas: el `IconButton` de
/// Material 3 lleva uno adentro y se contaría dos veces.
final _botones = find.byWidgetPredicate(
  (w) =>
      w is IconButton ||
      w is FloatingActionButton ||
      w is TextButton ||
      w is OutlinedButton ||
      w is ElevatedButton ||
      w is FilledButton,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    await cargarFuentesTotem();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FondoTotem.precargar();
  });

  tearDown(FondoTotem.olvidar);

  group('según la pantalla', () {
    testWidgets('en el celular, la lista sola y la paleta arriba',
        (tester) async {
      await _abrir(tester, tamano: _celular);
      expect(tester.takeException(), isNull);
      expect(find.byType(PanelPuerta), findsOneWidget);
      expect(find.byType(TotemLocal), findsNothing);
      expect(find.text('TÓTEM'), findsNothing);
      expect(_enLaBarra(_paleta), findsOneWidget);
    });

    testWidgets('a 599 px todavía es celular, a 600 ya es tablet',
        (tester) async {
      await _abrir(tester, tamano: const Size(599, 900));
      expect(find.text('TÓTEM'), findsNothing);
      await _abrir(tester, tamano: const Size(600, 900));
      expect(find.text('TÓTEM'), findsOneWidget);
    });

    testWidgets('en la tablet, pestañas: RECEPCIÓN y TÓTEM', (tester) async {
      await _abrir(tester, tamano: _tablet);
      expect(find.text('RECEPCIÓN'), findsOneWidget);
      expect(find.byType(PanelPuerta), findsOneWidget);
      expect(find.byType(TotemLocal), findsNothing);
      expect(_enLaBarra(_paleta), findsNothing);

      await tester.tap(find.text('TÓTEM'));
      await _asentar(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PanelPuerta), findsNothing);
      expect(find.byType(TotemLocal), findsOneWidget);
      expect(find.text('VISTA DEL TÓTEM · NEÓN'), findsOneWidget);
      expect(_enLaVista(_paleta), findsOneWidget);
    });

    testWidgets('a 1.024 px todavía es tablet, a 1.025 ya es PC',
        (tester) async {
      await _abrir(tester, tamano: const Size(1024, 768));
      expect(find.byType(TotemLocal), findsNothing);
      await _abrir(tester, tamano: const Size(1025, 768));
      expect(find.byType(TotemLocal), findsOneWidget);
    });

    testWidgets('en la PC, la lista y la vista lado a lado', (tester) async {
      await _abrir(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(PanelPuerta), findsOneWidget);
      expect(find.byType(TotemLocal), findsOneWidget);
      expect(find.text('TÓTEM'), findsNothing);
      expect(
        tester.getCenter(find.byType(TotemLocal)).dx,
        greaterThan(tester.getCenter(find.byType(PanelPuerta)).dx),
      );
      // La lista se lleva el 60 %.
      expect(
        tester.getSize(find.byType(VistaDelTotem)).width,
        moreOrLessEquals(_pc.width * 0.4, epsilon: 2),
      );
      expect(find.text('VISTA DEL TÓTEM · NEÓN'), findsOneWidget);
    });
  });

  group('sobre la vista', () {
    testWidgets('un solo botón, la paleta, y ningún botón flotante',
        (tester) async {
      await _abrir(tester);
      expect(_enLaVista(_botones), findsOneWidget);
      expect(_enLaVista(_paleta), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(_enLaBarra(_paleta), findsNothing);
    });

    testWidgets('sin el permiso del tótem, sin paleta', (tester) async {
      await _abrir(tester, puedeTotem: false);
      expect(_paleta, findsNothing);
      expect(_enLaVista(_botones), findsNothing);
      await _abrir(tester, tamano: _celular, puedeTotem: false);
      expect(_paleta, findsNothing);
    });

    testWidgets('la paleta abre Personalizar', (tester) async {
      await _abrir(tester);
      await tester.tap(_enLaVista(_paleta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PERSONALIZAR TÓTEM'), findsOneWidget);
    });

    testWidgets('sin evento elegido, la vista lo pide', (tester) async {
      await _abrir(tester, elegido: null);
      expect(find.byType(TotemLocal), findsNothing);
      expect(find.text('Seleccioná un evento para comenzar'), findsWidgets);
    });
  });

  testWidgets('de punta a punta: Enter en la lista y la vista saluda',
      (tester) async {
    final mundo = await _abrir(tester);
    await tester.enterText(find.byType(TextField), 'bruno');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump(EscenaTotem.entrada);

    expect(mundo.invitados.creados, [idDe('garcia')]);
    expect(_enLaVista(find.text('GARCÍA, BRUNO')), findsOneWidget);
    expect(
      tester.widget<EscenaTotem>(find.byType(EscenaTotem)).llegada!.mesa,
      '17',
    );
    expect(tester.takeException(), isNull);
  });

  for (final tamano in [_celular, _tablet, _pc]) {
    testWidgets('sin desbordes a ${tamano.width.toInt()} px, masivo y '
        'particular', (tester) async {
      for (final evento in [eventoMasivo, eventoParticular]) {
        await _abrir(tester, tamano: tamano, elegido: evento);
        expect(tester.takeException(), isNull);
        if (find.text('TÓTEM').evaluate().isNotEmpty) {
          await tester.tap(find.text('TÓTEM'));
          await _asentar(tester);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
