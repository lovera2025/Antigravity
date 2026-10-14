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
// - Recepcion_PC.png: la pantalla entera en la PC, la lista y la vista del
//   tótem con una familia llegando.
// - Recepcion_tablet_totem.png: en la tablet, la pestaña TÓTEM saludando.
// - Recepcion_celular.png: en el celular, la lista sola con la paleta arriba.
//
// Es el panel de la app (`PanelPuerta`) y la pantalla de Recepción, con los
// reemplazos en memoria de `test/helpers/puerta_en_memoria.dart`. Las tres
// últimas dibujan el tótem con los fondos de verdad.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/recepcion_unified_screen.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/totem/estilos/fondo_totem.dart';
import 'package:arguello_events/features/totem/estilos/fuentes_totem.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/totem_config.dart';

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

  group('la pantalla entera, con la vista del tótem', () {
    setUpAll(() async {
      await cargarFuentesTotem();
      // Oswald negrita, con el nombre con que la pide `google_fonts` (el
      // título y las pestañas).
      final oswald = FontLoader('Oswald_700')
        ..addFont(rootBundle.load('assets/google_fonts/Oswald-Bold.ttf'));
      await oswald.load();
      await FondoTotem.precargar();
    });

    Future<GlobalKey> abrirPantalla(
      WidgetTester tester,
      PuertaEnMemoria mundo,
      Size tam,
    ) async {
      final clave = GlobalKey();
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(mundo.motor.bajo.close);
      await tester.pumpWidget(
        RepaintBoundary(
          key: clave,
          child: mundo.recepcion(
            const RecepcionUnifiedScreen(),
            elegido: eventoMasivo,
            config: const {
              eventoMasivo: TotemConfig(
                eventoId: eventoMasivo,
                titulo: 'PROMOCIÓN 2026',
                subtitulo: 'Escuela Normal',
              ),
            },
            tema: ThemeData(
              brightness: Brightness.dark,
              fontFamily: FuentesTotem.linea,
              useMaterial3: true,
            ),
          ),
        ),
      );
      await _asentar(tester);
      return clave;
    }

    /// Lo que hace "Ingresar" en la lista, en la base de esta PC.
    Future<void> ingresar(PuertaEnMemoria mundo, String alumno, int lugar,
            String nombre) =>
        mundo.invitados.ingresarDesdeLaPuerta(
          eventoId: eventoMasivo,
          id: idInvitadoPuerta(alumno, lugar),
          nombre: nombre,
        );

    /// Espera la llegada y las imágenes (el logo), y falla si algo no entra.
    Future<void> asentarLlegada(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          await precacheImage((e.widget as Image).image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }

    testWidgets('en la PC, con una familia llegando', (tester) async {
      final mundo = PuertaEnMemoria(
        _supabase,
        alumnos: _institucion(sorteada: true).cast(),
      );
      final clave = await abrirPantalla(tester, mundo, const Size(1366, 768));
      await ingresar(mundo, 'perez', 0, 'PÉREZ, JUAN MARTÍN');
      await ingresar(mundo, 'perez', 1, 'GÓMEZ, ANA');
      await ingresar(mundo, 'perez', 2, 'PÉREZ, LUIS');
      await asentarLlegada(tester);
      expect(find.text('con GÓMEZ, ANA y PÉREZ, LUIS'), findsOneWidget);
      await _guardar(tester, clave, 'Recepcion_PC.png', carpeta);
    });

    testWidgets('en la tablet, la pestaña TÓTEM', (tester) async {
      final mundo = PuertaEnMemoria(
        _supabase,
        alumnos: _institucion(sorteada: true).cast(),
      );
      final clave = await abrirPantalla(tester, mundo, const Size(800, 1280));
      await tester.tap(find.text('TÓTEM'));
      await _asentar(tester);
      await ingresar(mundo, 'acosta', 0, 'ACOSTA, LUCÍA');
      await asentarLlegada(tester);
      await _guardar(tester, clave, 'Recepcion_tablet_totem.png', carpeta);
    });

    testWidgets('en el celular, la lista sola', (tester) async {
      final mundo = PuertaEnMemoria(
        _supabase,
        alumnos: _institucion(sorteada: true).cast(),
      );
      final clave = await abrirPantalla(tester, mundo, const Size(390, 844));
      await asentarLlegada(tester);
      await _guardar(tester, clave, 'Recepcion_celular.png', carpeta);
    });
  });
}
