import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/tele/calidad_de_la_tele.dart';
import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/features/tele/pantalla_tele.dart';
import 'package:arguello_events/features/totem/widgets/totem_local.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/puerta_en_memoria.dart';

/// La pantalla de la tele (24-nov-2026), entera, con la fiesta y la lista en
/// memoria y manejada con las teclas del control.
class _ModoFijo extends ModoTeleNotifier {
  _ModoFijo(this.inicial);
  final ModoTele inicial;
  final puestos = <ModoTele?>[];

  @override
  ModoTele? build() => inicial;

  @override
  Future<void> poner(ModoTele? modo) async {
    puestos.add(modo);
    state = modo;
  }
}

/// La escuela de la tele, sin escribir las preferencias.
class _FiestaFija extends FiestaDeLaTeleNotifier {
  _FiestaFija(this.inicial);
  final String? inicial;

  @override
  String? build() => inicial;

  @override
  Future<void> elegir(String eventoId) async => state = eventoId;
}

/// El giro de la tele, sin escribir las preferencias.
class _GiroFijo extends GiroDeLaTeleNotifier {
  _GiroFijo(this.inicial);
  final int inicial;

  @override
  int build() => inicial;

  @override
  Future<void> poner(int cuartos) async => state = Giro.normal(cuartos);
}

final _hoy = DateTime(2026, 12, 12, 21, 40);
late SupabaseClient _supabase;

void main() {
  setUpAll(() {
    // Fuera de la zona de cada prueba: el reloj de su sesión no queda pendiente.
    _supabase = SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba');
    GoogleFonts.config.allowRuntimeFetching = false;
    LocalDatabase.cerrarParaLaPrueba();
  });

  late _ModoFijo modo;
  late _GiroFijo giro;
  late _FiestaFija fiestaFija;
  late PuertaEnMemoria mundo;

  Future<void> abrir(
    WidgetTester tester, {
    PapelDeLaTele papel = PapelDeLaTele.principal,
    bool conDiagnostico = false,
    Map<String, Object> preferencias = const {},
    int cuartos = 0,
    List<Evento>? eventos,
    String? fiesta,
  }) async {
    SharedPreferences.setMockInitialValues(preferencias);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    modo = _ModoFijo(ModoTele(papel));
    giro = _GiroFijo(cuartos);
    fiestaFija = _FiestaFija(fiesta);
    mundo = PuertaEnMemoria(
      _supabase,
      alumnos: [alumnoDePrueba('c1000000-0000-4000-8000-000000000001', 'PÉREZ, JUAN', mesas: [12])],
    );
    await tester.pumpWidget(mundo.recepcion(
      PantallaTele(ahora: () => _hoy, conDiagnostico: conDiagnostico),
      eventos: eventos ?? [eventoDePrueba(eventoMasivo, 'masivo')],
      // Como en la app: todo girado como la tele.
      builder: (context, child) => GiroDeLaApp(child: child!),
      extra: [
        modoTeleProvider.overrideWith(() => modo),
        giroDeLaTeleProvider.overrideWith(() => giro),
        fiestaDeLaTeleProvider.overrideWith(() => fiestaFija),
        // La central de verdad no se prende acá (eso lo prueba
        // `tele_central_test`): solo se mira lo que la tele muestra.
        centralDeLaPuertaProvider.overrideWith(_CentralQuieta.new),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tecla(WidgetTester tester, LogicalKeyboardKey k) async {
    // Atrás del control de una tele Android llega como "volver" del sistema,
    // no como tecla: lo atiende el PopScope de la pantalla.
    if (k == LogicalKeyboardKey.goBack) {
      await tester.binding.handlePopRoute();
    } else {
      await tester.sendKeyEvent(k);
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('OK del control abre el menú; Atrás lo cierra', (tester) async {
    await abrir(tester);
    expect(find.text('TELE 1'), findsNothing);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.text('TELE 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('tele_sumar_celular')), findsOneWidget);
    await tecla(tester, LogicalKeyboardKey.goBack);
    expect(find.text('TELE 1'), findsNothing);
    // Esc del teclado, igual.
    await tecla(tester, LogicalKeyboardKey.enter);
    expect(find.text('TELE 1'), findsOneWidget);
    await tecla(tester, LogicalKeyboardKey.escape);
    expect(find.text('TELE 1'), findsNothing);
  });

  testWidgets('con el control se recorre el menú y se elige con OK', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    // Arranca en "Sumar un celular"; flecha abajo va a "La fiesta".
    await tecla(tester, LogicalKeyboardKey.arrowDown);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.text('LA FIESTA'), findsOneWidget);
    await tecla(tester, LogicalKeyboardKey.goBack);
    expect(find.text('TELE 1'), findsOneWidget);
  });

  /// Escribe [texto] con el teclado de la tele (tocando sus teclas).
  Future<void> escribir(WidgetTester tester, String texto) async {
    for (final c in texto.split('')) {
      final k = switch (c) {
        '.' => 'tecla_punto',
        ':' => 'tecla_dos_puntos',
        _ => 'tecla_$c',
      };
      await tester.ensureVisible(find.byKey(ValueKey(k)));
      await tester.tap(find.byKey(ValueKey(k)));
      await tester.pump();
    }
  }

  Future<void> listo(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('tecla_listo')));
    await tester.tap(find.byKey(const ValueKey('tecla_listo')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('salir del modo tele pide el PIN del jefe: con otro, la tele sigue', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_salir')));
    await tester.tap(find.byKey(const ValueKey('tele_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PIN del jefe'), findsOneWidget);
    // Con el teclado de la tele, no el del sistema (el de Google TV no gira).
    expect(find.byType(TextField), findsNothing);
    await escribir(tester, '1111');
    expect(find.text('••••'), findsOneWidget, reason: 'el PIN no se ve');
    await listo(tester);
    expect(find.text('Ese no es el PIN del jefe.'), findsOneWidget);
    expect(modo.puestos, isEmpty);
    // Atrás vuelve al menú, sin salir.
    await tecla(tester, LogicalKeyboardKey.goBack);
    expect(find.text('TELE 1'), findsOneWidget);
    expect(modo.puestos, isEmpty);
  });

  testWidgets('con el PIN del jefe sale del modo tele', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_salir')));
    await tester.tap(find.byKey(const ValueKey('tele_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    await escribir(tester, '2026');
    await listo(tester);
    expect(modo.puestos, [null]);
  });

  testWidgets('el PIN se escribe también con las flechas y OK del control', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_salir')));
    await tester.tap(find.byKey(const ValueKey('tele_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    // Arranca en el 1: OK, derecha (2), abajo (5), OK.
    await tecla(tester, LogicalKeyboardKey.select);
    await tecla(tester, LogicalKeyboardKey.arrowRight);
    await tecla(tester, LogicalKeyboardKey.arrowDown);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.text('••'), findsOneWidget);
  });

  group('girar la pantalla, sin PIN', () {
    testWidgets('Vertical gira todo y deja la tele parada (540 × 960)', (tester) async {
      await abrir(tester);
      expect(giro.state, 0);
      expect(MediaQuery.sizeOf(tester.element(find.byType(PantallaTele))), const Size(960, 540));
      await tecla(tester, LogicalKeyboardKey.select);
      await tester.ensureVisible(find.byKey(const ValueKey('tele_girar')));
      await tester.tap(find.byKey(const ValueKey('tele_girar')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('GIRAR LA PANTALLA'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tele_giro_vertical')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(giro.state, 1);
      // Quien mira la ve parada: 540 de ancho y 960 de alto.
      expect(MediaQuery.sizeOf(tester.element(find.byType(PantallaTele))), const Size(540, 960));
      // El panel sigue abierto y entra entero en lo parado.
      expect(find.text('GIRAR LA PANTALLA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Dar vuelta: para el otro lado.
      await tester.tap(find.byKey(const ValueKey('tele_giro_dar_vuelta')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(giro.state, 3);
      // Vertical otra vez no la cambia: ya está parada.
      await tester.tap(find.byKey(const ValueKey('tele_giro_vertical')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(giro.state, 3);
      await tester.tap(find.byKey(const ValueKey('tele_giro_horizontal')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(giro.state, 0);
      expect(MediaQuery.sizeOf(tester.element(find.byType(PantallaTele))), const Size(960, 540));
    });

    testWidgets('parada, la flecha de abajo baja en lo que se ve', (tester) async {
      await abrir(tester, cuartos: 1);
      await tecla(tester, LogicalKeyboardKey.select);
      // Arranca en "Sumar un celular"; abajo es "La fiesta", como acostada.
      await tecla(tester, LogicalKeyboardKey.arrowDown);
      await tecla(tester, LogicalKeyboardKey.select);
      expect(find.text('LA FIESTA'), findsOneWidget);
    });

    testWidgets('dada vuelta del otro lado (3), también', (tester) async {
      await abrir(tester, cuartos: 3);
      await tecla(tester, LogicalKeyboardKey.select);
      await tecla(tester, LogicalKeyboardKey.arrowDown);
      await tecla(tester, LogicalKeyboardKey.arrowDown);
      await tecla(tester, LogicalKeyboardKey.select);
      expect(find.text('GIRAR LA PANTALLA'), findsOneWidget);
    });

    testWidgets('parada, todos los paneles entran sin desbordar', (tester) async {
      await abrir(tester, cuartos: 1, papel: PapelDeLaTele.segunda);
      await tecla(tester, LogicalKeyboardKey.select);
      for (final k in ['tele_sumar_celular', 'tele_fiesta', 'tele_girar', 'tele_direccion', 'tele_salir']) {
        await tester.ensureVisible(find.byKey(ValueKey(k)));
        await tester.tap(find.byKey(ValueKey(k)));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: k);
        await tecla(tester, LogicalKeyboardKey.goBack);
        expect(find.text('TELE 2'), findsOneWidget, reason: k);
      }
    });
  });

  group('cada tele con su escuela, con el control', () {
    Future<void> conDos(WidgetTester tester) async {
      await abrir(tester,
          eventos: [eventoDePrueba(eventoMasivo, 'masivo'), eventoDePrueba(eventoParticular, 'masivo')],
          fiesta: eventoMasivo);
    }

    testWidgets('cambiar la escuela no pide PIN, pero sí un cartel que confirma', (tester) async {
      await conDos(tester);
      expect(tester.widget<TotemLocal>(find.byType(TotemLocal)).eventoId, eventoMasivo);
      await tecla(tester, LogicalKeyboardKey.select);
      await tester.tap(find.byKey(const ValueKey('tele_fiesta')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('tele_fiesta_$eventoParticular')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CAMBIAR LA ESCUELA'), findsOneWidget);
      expect(find.textContaining('¿Pasar la Tele 1 a'), findsOneWidget);
      expect(find.text('PIN del jefe'), findsNothing);
      // Volver: no cambia nada.
      await tester.tap(find.byKey(const ValueKey('tele_escuela_volver')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fiestaFija.state, eventoMasivo);
      await tester.tap(find.byKey(const ValueKey('tele_fiesta_$eventoParticular')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('tele_escuela_cambiar')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fiestaFija.state, eventoParticular);
      expect(tester.widget<TotemLocal>(find.byType(TotemLocal)).eventoId, eventoParticular);
    });

    testWidgets('lo que cambian desde un celular se dice en un cartel chico', (tester) async {
      await conDos(tester);
      final contenedor = ProviderScope.containerOf(tester.element(find.byType(PantallaTele)));
      contenedor.read(avisoEnLaTeleProvider.notifier).decir('Caro pasó la Tele 1 a ESCUELA B');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Caro pasó la Tele 1 a ESCUELA B'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Caro pasó la Tele 1 a ESCUELA B'), findsNothing);
    });

    testWidgets('el menú explica las dos teles en routers separados', (tester) async {
      await abrir(tester);
      await tecla(tester, LogicalKeyboardKey.select);
      await tester.ensureVisible(find.byKey(const ValueKey('tele_dos_redes')));
      await tester.tap(find.byKey(const ValueKey('tele_dos_redes')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('poné las dos como Tele 1'), findsOneWidget);
      expect(find.textContaining('no se ven'), findsWidgets);
    });
  });

  group('todas las escuelas listas sin internet', () {
    testWidgets('LA FIESTA dice cómo quedó cada una', (tester) async {
      await abrir(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      // Se preparó sola al abrir, con internet.
      expect(mundo.sinInternet.listasDeFiestas, [eventoMasivo]);
      await tecla(tester, LogicalKeyboardKey.select);
      await tester.tap(find.byKey(const ValueKey('tele_fiesta')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Lista sin internet · al día'), findsOneWidget);
    });

    testWidgets('lo guardado en Personalizar en otra PC se vuelve a leer al momento', (tester) async {
      await abrir(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(mundo.sinInternet.aparienciasLeidas, 1);
      mundo.motor.apariencias.add({eventoMasivo});
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(mundo.sinInternet.aparienciasLeidas, 2);
    });
  });

  testWidgets('la dirección de la Tele 1 se escribe con el teclado de la tele', (tester) async {
    await abrir(tester, papel: PapelDeLaTele.segunda);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_direccion')));
    await tester.tap(find.byKey(const ValueKey('tele_direccion')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TextField), findsNothing);
    await escribir(tester, '192.168.0.10:8787');
    await listo(tester);
    expect(modo.puestos.single?.direccionAMano, '192.168.0.10:8787');
    // VACIAR: que la busque sola.
    await tester.ensureVisible(find.byKey(const ValueKey('tele_direccion')));
    await tester.tap(find.byKey(const ValueKey('tele_direccion')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const ValueKey('tecla_vaciar')));
    await tester.tap(find.byKey(const ValueKey('tecla_vaciar')));
    await tester.pump();
    await listo(tester);
    expect(modo.puestos.last?.direccionAMano, isNull);
  });

  testWidgets('en la app de verdad el menú no muestra ningún número (25-nov)', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.text('TELE 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('tele_como_anda')), findsNothing);
    expect(find.textContaining('Cómo anda'), findsNothing);
    expect(find.textContaining('por segundo'), findsNothing);
  });

  testWidgets('la app de prueba sí dice cómo anda, con los números', (tester) async {
    await abrir(tester, conDiagnostico: true);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tele_como_anda')), findsOneWidget);
    expect(find.textContaining('Cómo anda'), findsOneWidget);
    expect(find.textContaining('fondo a la mitad'), findsOneWidget);
  });

  testWidgets('el tótem de la tele va con lo quieto en foto y el fondo a la mitad', (tester) async {
    await abrir(tester);
    final totem = tester.widget<TotemLocal>(find.byType(TotemLocal));
    expect(totem.enLaTele, isTrue);
    expect(totem.escalaDelFondo, FondoDeLaTele.mitad.escala);
    expect(totem.fondoQuieto, isFalse);
  });

  testWidgets('la tele recuerda que tuvo que bajar el fondo', (tester) async {
    await abrir(tester, preferencias: {AjusteDeLaTele.clave: 'quieto'});
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    final totem = tester.widget<TotemLocal>(find.byType(TotemLocal));
    expect(totem.fondoQuieto, isTrue);
    // Desde el menú se vuelve a animar (en chico).
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.tap(find.byKey(const ValueKey('tele_fondo')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<TotemLocal>(find.byType(TotemLocal)).escalaDelFondo,
        FondoDeLaTele.tercio.escala);
  });

  testWidgets('el fondo quieto se elige desde el menú y queda en la tele', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.tap(find.byKey(const ValueKey('tele_fondo')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(modo.puestos.single?.fondoQuieto, isTrue);
  });

  testWidgets('la Tele 2 tiene "Pasar a principal" y escribir la dirección; la 1 no',
      (tester) async {
    await abrir(tester, papel: PapelDeLaTele.segunda);
    await tecla(tester, LogicalKeyboardKey.select);
    expect(find.text('TELE 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('tele_pasar_a_principal')), findsOneWidget);
    expect(find.byKey(const ValueKey('tele_direccion')), findsOneWidget);
  });

  testWidgets('sin fiesta que venga, lo dice', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    modo = _ModoFijo(const ModoTele(PapelDeLaTele.principal));
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: const [],
    );
    await tester.pumpWidget(mundo.recepcion(
      PantallaTele(ahora: () => _hoy),
      eventos: const <Evento>[],
      extra: [
        modoTeleProvider.overrideWith(() => modo),
        centralDeLaPuertaProvider.overrideWith(_CentralQuieta.new),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No hay ninguna fiesta que venga en esta tele.'), findsOneWidget);
  });
}

/// La central, sin abrir puertos: anota que se pidió prenderla.
class _CentralQuieta extends CentralDeLaPuerta {
  @override
  EstadoCentral build() => const EstadoCentral();

  @override
  Future<void> prender(String eventoId, {bool comoTele = false}) async {
    state = EstadoCentral(
      eventoId: eventoId,
      codigo: '4821',
      puerto: 8787,
      direcciones: const ['192.168.0.10'],
      esTele: comoTele,
    );
  }

  @override
  Future<void> apagar() async => state = const EstadoCentral();
}
