// Arnés manual: el menú de la tele (la tele es el tótem, 25/26-nov-2026), en
// PNG, acostada y parada, con dos escuelas inventadas. Sin la base ni la nube.
//
//   flutter test tool/tele_menu_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen, cada una acostada (`_acostada`) y parada (`_parada`):
// - Tele_1_menu: el menú del control.
// - Tele_2_girar: Horizontal · Vertical · Dar vuelta.
// - Tele_3_pin: el teclado de la tele para el PIN del jefe (Salir del modo tele).
// - Tele_4_la_fiesta: las escuelas que vienen, con cómo quedó cada una.
// - Tele_5_cartel_cambiar_escuela: el cartel que confirma, sin PIN.
// - Tele_6_dos_qr: pasó a principal con la Tele 1 apagada, un QR por escuela.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/features/tele/pantalla_tele.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

class _ModoFijo extends ModoTeleNotifier {
  @override
  ModoTele? build() => const ModoTele(PapelDeLaTele.principal);

  @override
  Future<void> poner(ModoTele? modo) async => state = modo;
}

class _GiroFijo extends GiroDeLaTeleNotifier {
  _GiroFijo(this.inicial);
  final int inicial;

  @override
  int build() => inicial;

  @override
  Future<void> poner(int cuartos) async => state = Giro.normal(cuartos);
}

class _FiestaFija extends FiestaDeLaTeleNotifier {
  @override
  String? build() => eventoMasivo;

  @override
  Future<void> elegir(String eventoId) async => state = eventoId;
}

class _CentralQuieta extends CentralDeLaPuerta {
  _CentralQuieta({this.conLaOtra = false});
  final bool conLaOtra;

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
      atiende: [eventoId, if (conLaOtra) eventoParticular],
    );
  }

  @override
  Future<void> apagar() async => state = const EstadoCentral();
}

final _hoy = DateTime(2026, 12, 12, 21, 40);

Evento _escuela(String id, String nombre, DateTime fecha) => Evento(
      id: id,
      clienteId: 'c0000000-0000-4000-8000-0000000000${id.substring(id.length - 2)}',
      cliente: Cliente(id: 'c0000000-0000-4000-8000-0000000000${id.substring(id.length - 2)}', nombreCompleto: nombre),
      tipo: 'Egresados',
      fechaEvento: fecha,
      estado: EstadoEvento.confirmado,
      modalidad: 'masivo',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  late SupabaseClient supabase;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('tele_menu_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  setUpAll(() async {
    supabase = SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba');
    LocalDatabase.cerrarParaLaPrueba();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    final regular = FontLoader('Outfit_regular')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'));
    await regular.load();
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();
    await cargarFuentesTotem();
  });

  Future<GlobalKey> abrir(WidgetTester tester, int cuartos, {bool conLaOtra = false}) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mundo = PuertaEnMemoria(
      supabase,
      alumnos: [alumnoDePrueba('c1000000-0000-4000-8000-000000000001', 'CEIBO, MALENA', mesas: [12])],
    );
    await tester.pumpWidget(mundo.recepcion(
      PantallaTele(ahora: () => _hoy),
      eventos: [
        _escuela(eventoMasivo, 'ESCUELA DEL CEIBO', DateTime(2026, 12, 12)),
        _escuela(eventoParticular, 'COLEGIO DEL HORNERO', DateTime(2026, 12, 12)),
      ],
      builder: (context, child) => RepaintBoundary(key: clave, child: GiroDeLaApp(child: child!)),
      extra: [
        modoTeleProvider.overrideWith(_ModoFijo.new),
        giroDeLaTeleProvider.overrideWith(() => _GiroFijo(cuartos)),
        fiestaDeLaTeleProvider.overrideWith(_FiestaFija.new),
        centralDeLaPuertaProvider.overrideWith(() => _CentralQuieta(conLaOtra: conLaOtra)),
      ],
    ));
    // La tele prepara sola las escuelas que vienen (LA FIESTA dice cómo quedó
    // cada una).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await asentar(tester);
    return clave;
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await asentar(tester);
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$nombre.png')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  Future<void> tocar(WidgetTester tester, String clave) async {
    await tester.tap(find.byKey(ValueKey(clave)));
    await asentar(tester);
  }

  for (final (cuartos, como) in [(0, 'acostada'), (1, 'parada')]) {
    testWidgets('el menú, $como', (tester) async {
      final clave = await abrir(tester, cuartos);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await guardar(tester, clave, 'Tele_1_menu_$como');
      await tocar(tester, 'tele_girar');
      await guardar(tester, clave, 'Tele_2_girar_$como');
      await tocar(tester, 'tele_girar_volver');
      await tocar(tester, 'tele_fiesta');
      await guardar(tester, clave, 'Tele_4_la_fiesta_$como');
      await tocar(tester, 'tele_fiesta_$eventoParticular');
      await guardar(tester, clave, 'Tele_5_cartel_cambiar_escuela_$como');
      await tocar(tester, 'tele_escuela_volver');
      await tocar(tester, 'tele_fiestas_volver');
      await tocar(tester, 'tele_salir');
      for (final n in ['2', '0']) {
        await tocar(tester, 'tecla_$n');
      }
      await guardar(tester, clave, 'Tele_3_pin_$como');
      await tocar(tester, 'tecla_cancelar');
      expect(tester.takeException(), isNull);
    });

    testWidgets('los dos QR, $como', (tester) async {
      final clave = await abrir(tester, cuartos, conLaOtra: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await asentar(tester);
      await tocar(tester, 'tele_sumar_celular');
      await guardar(tester, clave, 'Tele_6_dos_qr_$como');
      expect(find.byKey(const ValueKey('tele_qr_otra')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
