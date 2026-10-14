// Arnés manual: dibuja el aviso "Sin internet" de la barra del operador del
// tótem y guarda un PNG para mirarlo sin levantar la app.
//
//   flutter test tool/totem_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sale Totem_sin_internet.png, con los dos textos: el de la ventana del tótem
// en la PC de Recepción y el de la web.
//
// El aviso es el de la app. El fondo es el negro del tótem, sin lo demás: la
// pantalla entera lee de la nube y todavía no se puede montar en una prueba.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/totem/widgets/aviso_sin_internet.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

Widget _renglon(String donde, bool conPuente) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 250,
            child: Text(
              donde,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          Flexible(child: AvisoSinInternet(conPuente: conPuente)),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin esto `google_fonts` intenta bajar la letra y la prueba se cuelga. La
  // negrita de Outfit viene con la app.
  GoogleFonts.config.allowRuntimeFetching = false;

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('totem_muestra').path;

  testWidgets('el aviso de que no hay internet', (tester) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    // La negrita de Outfit, con el nombre con que la pide `google_fonts`. En
    // la app la encuentra sola entre los archivos; acá hay que tenerla cargada
    // antes de dibujar, o el primer cuadro sale con la letra de prueba.
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();

    const tam = Size(680, 176);
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Scaffold(
            backgroundColor: const Color(0xFF050505),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _renglon('En la ventana del tótem, en la PC', true),
                  _renglon('En el tótem de la web', false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(AvisoSinInternet.sigueAvisando), findsOneWidget);
    expect(find.text(AvisoSinInternet.reconectando), findsOneWidget);

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}Totem_sin_internet.png')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  });
}
