// Muestras del chat de la puerta (6.5.0), con mensajes inventados.
//
//   flutter test tool/chat_puerta_muestra_test.dart --dart-define=salida=<carpeta>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/chat/chat_del_puesto.dart';
import 'package:arguello_events/features/recepcion/chat/hoja_chat.dart';
import 'package:arguello_events/features/recepcion/chat/mensaje_de_puesto.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('chat_puerta').path;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  });

  ChatDelPuesto armar() {
    final chat = ChatDelPuesto(yo: 'juli', nombre: 'Juli', enviar: (_) {})
      ..ponerPuestos(const [
        PuestoDelChat(id: kPuestoDeLaPc, nombre: 'Pato', conectado: true),
        PuestoDelChat(id: 'vero', nombre: 'Vero', conectado: true),
        PuestoDelChat(id: 'romi', nombre: 'Romi', conectado: false),
      ]);
    var n = 0;
    void llega(String de, String nombre, String? para, String texto, int min) =>
        chat.recibir(MensajeDePuesto(
          id: '${n++}',
          de: de,
          deNombre: nombre,
          para: para,
          texto: texto,
          hora: DateTime(2026, 12, 12, 22, min),
        ));
    llega(kPuestoDeLaPc, 'Pato', null, 'Arrancamos. Los masivos entran por la puerta de la izquierda.', 5);
    llega('vero', 'Vero', null, 'Llegó el micro de 5° A', 18);
    llega(kPuestoDeLaPc, 'Pato', 'juli', '¿Alguien vio a GÓMEZ? Preguntan por la mesa 12', 31);
    return chat;
  }

  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    required Size tam,
    String? abierta,
  }) async {
    final chat = armar();
    chat.mandar('Ya los busco, están en la fila', kPuestoDeLaPc);
    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF0B0B0D),
            appBar: AppBar(
              title: const Text('RECEPCIÓN'),
              actions: [BotonChat(chat: chat)],
            ),
            body: Center(
              child: TextButton(
                key: const ValueKey('abrir'),
                onPressed: () => abrirChat(context, chat, conversacion: abierta),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('abrir')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(GoogleFonts.pendingFonts);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      // ignore: avoid_print
      print('── PNG en: ${f.path}');
    });
    chat.dispose();
  }

  testWidgets('en la PC', (tester) async {
    await sacar(
      tester,
      archivo: '1_chat_PC.png',
      tam: const Size(1366, 820),
      abierta: kPuestoDeLaPc,
    );
  });

  testWidgets('en el celular, la lista', (tester) async {
    await sacar(tester, archivo: '2_chat_celular_lista.png', tam: const Size(390, 844));
  });

  testWidgets('en el celular, con Pato', (tester) async {
    await sacar(
      tester,
      archivo: '3_chat_celular_conversacion.png',
      tam: const Size(390, 844),
      abierta: kPuestoDeLaPc,
    );
  });
}
