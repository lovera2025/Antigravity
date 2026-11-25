import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/features/tele/pantalla_tele.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> abrir(WidgetTester tester, {PapelDeLaTele papel = PapelDeLaTele.principal}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    modo = _ModoFijo(ModoTele(papel));
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: [alumnoDePrueba('c1000000-0000-4000-8000-000000000001', 'PÉREZ, JUAN', mesas: [12])],
    );
    await tester.pumpWidget(mundo.recepcion(
      PantallaTele(ahora: () => _hoy),
      eventos: [eventoDePrueba(eventoMasivo, 'masivo')],
      extra: [
        modoTeleProvider.overrideWith(() => modo),
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

  testWidgets('salir del modo tele pide el PIN del jefe: con otro, la tele sigue', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_salir')));
    await tester.tap(find.byKey(const ValueKey('tele_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PIN del jefe'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('LISTO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ese no es el PIN del jefe.'), findsOneWidget);
    expect(modo.puestos, isEmpty);
  });

  testWidgets('con el PIN del jefe sale del modo tele', (tester) async {
    await abrir(tester);
    await tecla(tester, LogicalKeyboardKey.select);
    await tester.ensureVisible(find.byKey(const ValueKey('tele_salir')));
    await tester.tap(find.byKey(const ValueKey('tele_salir')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '2026');
    await tester.tap(find.text('LISTO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(modo.puestos, [null]);
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
