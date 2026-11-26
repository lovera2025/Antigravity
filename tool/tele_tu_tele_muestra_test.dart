// Arnés manual: TU TELE en el celular de la puerta (25/26-nov-2026), en PNG,
// con dos escuelas inventadas. Sin la base, la nube ni una central.
//
//   flutter test tool/tele_tu_tele_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - TuTele_1_lista: la lista, con "Tu tele" y el ícono de TU TELE arriba.
// - TuTele_2_hoja: la hoja TU TELE (la escuela y el giro).
// - TuTele_3_elegir_escuela: CAMBIAR LA ESCUELA, las que vienen.
// - TuTele_4_cartel: el cartel que confirma, sin PIN.
// - TuTele_5_pregunta: "La Tele 1 cambió a … · MANTENER · CAMBIAR".
// - TuTele_6_sin_conexion: contestar sin conexión (la pregunta queda).

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_puesto.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../test/helpers/cliente_de_prueba.dart';
import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

final _nombres = [
  'CEIBO, MALENA',
  'HORNERO, BRUNO',
  'JACARANDÁ, SOFÍA',
  'ZORZAL, TOMÁS',
  'TALA, CATALINA',
  'CARDENAL, LUCAS',
];

ClienteDePrueba _cliente() => ClienteDePrueba()
  ..p = PuertaDelEvento.particular([
    for (var i = 0; i < _nombres.length; i++)
      Invitado(
        id: 'p$i',
        eventoId: eventoMasivo,
        nombreCompleto: _nombres[i],
        dni: '',
        numeroMesa: '${10 + i}',
        estadoIngreso: i < 2 ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
        updatedAt: i < 2 ? DateTime.utc(2026, 12, 13, 1, 30 + i) : null,
      ),
  ])
  ..tit = 'ESCUELA DEL CEIBO — Egresados (12/12) · masivo'
  ..tel = const [
    TeleDelCelular(numero: 1, conectada: true, evento: eventoMasivo, titulo: 'ESCUELA DEL CEIBO'),
    TeleDelCelular(numero: 2, conectada: true, evento: eventoMasivo, titulo: 'ESCUELA DEL CEIBO'),
  ]
  ..esc = const [
    EscuelaDelCelular(eventoMasivo, 'ESCUELA DEL CEIBO'),
    EscuelaDelCelular(eventoParticular, 'COLEGIO DEL HORNERO'),
  ]
  ..miTele = 1
  ..centralTele = 'Tele 1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('tu_tele_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  setUpAll(() async {
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

  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<GlobalKey> abrir(WidgetTester tester, ClienteDePrueba c) async {
    final clave = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: PantallaPuesto(cliente: c),
        ),
      ),
    );
    await asentar(tester);
    return clave;
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await asentar(tester);
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$nombre.png')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  testWidgets('TU TELE: la lista, la hoja, elegir la escuela y el cartel', (tester) async {
    final c = _cliente();
    final clave = await abrir(tester, c);
    await guardar(tester, clave, 'TuTele_1_lista');
    await tester.tap(find.byKey(const ValueKey('tu_tele_hoja')));
    await asentar(tester);
    await guardar(tester, clave, 'TuTele_2_hoja');
    await tester.tap(find.byKey(const ValueKey('cambiar_la_escuela')));
    await asentar(tester);
    await guardar(tester, clave, 'TuTele_3_elegir_escuela');
    await tester.tap(find.byKey(const ValueKey('escuela_$eventoParticular')));
    await asentar(tester);
    await guardar(tester, clave, 'TuTele_4_cartel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('la pregunta, y contestar sin conexión', (tester) async {
    final c = _cliente()
      ..miTele = 2
      ..preg = const PreguntaDeLaTele(
        id: 'p1',
        texto: 'La Tele 1 cambió a COLEGIO DEL HORNERO',
        evento: eventoParticular,
        tele: 2,
      );
    final clave = await abrir(tester, c);
    await guardar(tester, clave, 'TuTele_5_pregunta');
    c.contestarSale = false;
    await tester.tap(find.byKey(const ValueKey('pregunta_cambiar')));
    await asentar(tester);
    await guardar(tester, clave, 'TuTele_6_sin_conexion');
    expect(tester.takeException(), isNull);
  });
}
