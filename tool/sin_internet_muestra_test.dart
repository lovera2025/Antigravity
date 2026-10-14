// Arnés manual: dibuja la línea "Lista para trabajar sin internet" de
// Recepción (sección 5 de la 6.0.0) en sus cuatro estados, con datos
// inventados, y guarda un PNG de cada uno.
//
//   flutter test tool/sin_internet_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - SinInternet_1_lista.png: con internet y todo en la PC, con el detalle
//   abierto.
// - SinInternet_2_falta_la_foto.png: con internet, pero la foto del tótem no
//   bajó.
// - SinInternet_3_sin_internet.png: sin internet, con 12 ingresos sin subir y
//   el detalle abierto.
// - SinInternet_4_sin_la_lista.png: sin internet, y la PC no tiene la lista.
//
// Es el panel de la app (`PanelPuerta`) con los reemplazos en memoria de
// `test/helpers/puerta_en_memoria.dart`.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _foto = 'https://nube.test/totem/foto.png';

late SupabaseClient _supabase;

List<ContratoAlumno> _institucion() => [
      alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
          mesas: [14, 15], extras: 1, sillas: 3, division: '5° A'),
      alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS',
          mesas: [13], acomp: ['BENÍTEZ, SOL']),
      alumnoDePrueba('garcia', 'GARCÍA, BRUNO', mesas: [17]),
      alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
          mesas: [12], sillas: 2, acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS']),
    ];

Future<void> _guardar(WidgetTester tester, GlobalKey clave, String nombre,
    String carpeta) async {
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 1.5);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$carpeta${Platform.pathSeparator}$nombre')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('sin_internet_muestra').path;

  setUpAll(() async {
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    final regular = FontLoader('Outfit_regular')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'));
    await regular.load();
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();
  });

  Future<void> muestra(
    WidgetTester tester,
    String nombre, {
    AppConnectivity conexion = AppConnectivity.online,
    bool conAlumnos = true,
    bool abrirDetalle = false,
    void Function(SinInternetEnMemoria)? antes,
    String esperado = '',
  }) async {
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: conAlumnos ? _institucion() : const [],
    );
    mundo.conexion.estado = conexion;
    mundo.sinInternet.alDia[eventoMasivo] = DateTime(2026, 12, 12, 21, 32);
    antes?.call(mundo.sinInternet);
    const tam = Size(620, 520);
    final clave = GlobalKey();
    tester.view.physicalSize = tam;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(mundo.motor.bajo.close);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: mundo.panel(eventoMasivo, config: {
        eventoMasivo:
            TotemConfig.defaults(eventoMasivo).copyWith(imagenUrl: _foto),
      }),
    ));
    await _asentar(tester);
    // Pasa la cuenta de lo que espera subir.
    await tester.pump(const Duration(seconds: 10));
    await _asentar(tester);
    expect(find.textContaining(esperado), findsOneWidget);
    if (abrirDetalle) {
      await tester.tap(find.textContaining(esperado));
      await _asentar(tester);
    }
    expect(tester.takeException(), isNull);
    await _guardar(tester, clave, nombre, carpeta);
  }

  testWidgets('lista', (tester) async {
    await muestra(tester, 'SinInternet_1_lista.png',
        abrirDetalle: true, esperado: 'Lista para trabajar sin internet');
  });

  testWidgets('falta la foto', (tester) async {
    await muestra(tester, 'SinInternet_2_falta_la_foto.png',
        antes: (s) => s.bajaFoto = false,
        esperado: 'falta guardar la foto del tótem');
  });

  testWidgets('sin internet', (tester) async {
    await muestra(tester, 'SinInternet_3_sin_internet.png',
        conexion: AppConnectivity.offline,
        abrirDetalle: true,
        antes: (s) => s
          ..sinSubir = 12
          ..fotosGuardadas.add(_foto),
        esperado: '12 ingresos sin subir');
  });

  testWidgets('sin la lista', (tester) async {
    await muestra(tester, 'SinInternet_4_sin_la_lista.png',
        conexion: AppConnectivity.offline,
        conAlumnos: false,
        esperado: 'no tiene la lista de este evento');
  });
}
