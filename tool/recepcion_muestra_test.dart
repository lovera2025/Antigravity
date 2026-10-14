// Arnés manual: dibuja el panel de Recepción con datos inventados y guarda un
// PNG de cada caso, para mirarlo sin levantar la app.
//
//   flutter test tool/recepcion_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
// - Recepcion_1_masivo_sin_sortear.png: la institución con sus alumnos, el
//   aviso, sin mesa ni sillas.
// - Recepcion_2_masivo_sorteado.png: con mesa, sillas debajo, acompañantes y
//   música, y alguien adentro.
// - Recepcion_3_buscar_y_enter.png: buscando "12" (la mesa de una familia) y
//   apretando Enter: son tres, no ingresa a nadie y lo dice.
// - Recepcion_4_particular.png: nombre, DNI y mesa, con Agregar.
//
// Es el panel de la app (`PanelPuerta`), con los reemplazos en memoria de
// `test/helpers/puerta_en_memoria.dart`. A la izquierda de Recepción va el
// selector del evento y a la derecha la vista del tótem: no salen acá.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

late SupabaseClient _supabase;

/// Una institución inventada, con o sin las mesas del sorteo.
List<dynamic> _institucion({required bool sorteada}) {
  List<int> m(List<int> mesas) => sorteada ? mesas : const [];
  return [
    alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
        mesas: m([14, 15]), extras: 1, sillas: 3, division: '5° A',
        musica: 'Despechá · Rosalía'),
    alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS',
        mesas: m([13]), acomp: ['BENÍTEZ, SOL']),
    alumnoDePrueba('fernandez', 'FERNÁNDEZ, MÍA',
        mesas: m([16]), sillas: 1, division: '5° A',
        acomp: ['FERNÁNDEZ, JUAN'], musica: 'Ella · Callejero Fino'),
    alumnoDePrueba('garcia', 'GARCÍA, BRUNO', mesas: m([17])),
    alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
        mesas: m([12]), sillas: 2, acomp: ['GÓMEZ, ANA', 'PÉREZ, LUIS'],
        musica: 'Tusa · Karol G'),
    alumnoDePrueba('romero', 'ROMERO, ABRIL', mesas: m([18]), division: '5° A'),
    alumnoDePrueba('baja1', '[BAJA] RÍOS, MARTA'),
    alumnoDePrueba('baja2', '[BAJA] SOSA, LEO'),
  ];
}

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
      : Directory.systemTemp.createTempSync('recepcion_muestra').path;

  setUpAll(() async {
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    // Outfit, con los nombres con que la pide `google_fonts`. En la app la
    // encuentra sola entre los archivos; acá hay que tenerla cargada antes de
    // dibujar.
    final regular = FontLoader('Outfit_regular')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'));
    await regular.load();
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();
  });

  Future<GlobalKey> abrir(
    WidgetTester tester,
    PuertaEnMemoria mundo,
    String eventoId,
  ) async {
    const tam = Size(620, 860);
    final clave = GlobalKey();
    tester.view.physicalSize = tam;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(mundo.motor.bajo.close);
    await tester.pumpWidget(
      RepaintBoundary(key: clave, child: mundo.panel(eventoId)),
    );
    await _asentar(tester);
    expect(tester.takeException(), isNull);
    return clave;
  }

  testWidgets('masivo sin sortear', (tester) async {
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: _institucion(sorteada: false).cast(),
    );
    final clave = await abrir(tester, mundo, eventoMasivo);
    expect(find.textContaining('Todavía no se sorteó'), findsOneWidget);
    await _guardar(tester, clave, 'Recepcion_1_masivo_sin_sortear.png', carpeta);
  });

  testWidgets('masivo sorteado', (tester) async {
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: _institucion(sorteada: true).cast(),
      repartos: {
        'fernandez': SillasReparto(
          id: 'r-fernandez',
          contratoAlumnoId: 'fernandez',
          sillasPrincipal: 1,
          sillasExtra: 1,
          mesas: 1,
          createdAt: horaDeIngreso,
          updatedAt: horaDeIngreso,
        ),
      },
      filas: [
        Invitado(
          id: idInvitadoPuerta('benitez', 0),
          eventoId: eventoMasivo,
          nombreCompleto: 'BENÍTEZ, TOMÁS',
          dni: '',
          numeroMesa: '13',
          estadoIngreso: EstadoIngreso.ingresado,
          updatedAt: horaDeIngreso,
        ),
      ],
    );
    final clave = await abrir(tester, mundo, eventoMasivo);
    expect(find.text('Mesa 12'), findsOneWidget);
    await _guardar(tester, clave, 'Recepcion_2_masivo_sorteado.png', carpeta);
  });

  testWidgets('buscar y Enter', (tester) async {
    final mundo = PuertaEnMemoria(
      _supabase,
      alumnos: _institucion(sorteada: true).cast(),
    );
    final clave = await abrir(tester, mundo, eventoMasivo);
    await tester.enterText(find.byType(TextField), '12');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _asentar(tester);
    expect(find.textContaining('Hay 3 sin ingresar'), findsOneWidget);
    await _guardar(tester, clave, 'Recepcion_3_buscar_y_enter.png', carpeta);
  });

  testWidgets('particular', (tester) async {
    Invitado fila(String n, String nombre, String dni, String mesa,
            {bool adentro = false}) =>
        Invitado(
          id: 'i0000000-0000-4000-8000-00000000000$n',
          eventoId: eventoParticular,
          nombreCompleto: nombre,
          dni: dni,
          numeroMesa: mesa,
          estadoIngreso:
              adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
          updatedAt: horaDeIngreso,
        );
    final mundo = PuertaEnMemoria(_supabase, alumnos: const [], filas: [
      fila('1', 'LÓPEZ, MARTA', '30123456', '4', adentro: true),
      fila('2', 'RÍOS, PABLO', '28555111', '7'),
      fila('3', 'SOSA, ELENA', '33000222', '4'),
      fila('4', 'VEGA, CARLOS', '25444333', '2'),
    ]);
    final clave = await abrir(tester, mundo, eventoParticular);
    expect(find.text('AGREGAR'), findsOneWidget);
    await _guardar(tester, clave, 'Recepcion_4_particular.png', carpeta);
  });
}
