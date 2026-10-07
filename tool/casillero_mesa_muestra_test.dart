// Arnés manual: dibuja el casillero "N° de Mesa" de Editar alumno, en modo jefe
// y sin él, y guarda un PNG para mirarlo sin levantar la app ni tocar la base.
//
//   flutter test tool/casillero_mesa_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sale Casillero_numero_mesa.png. El casillero es el de la app; el marco de
// alrededor está copiado a mano de la pantalla.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/widgets/modal_alumno_premium.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

/// El mismo marco que arma `_premiumInputDecoration` en la pantalla.
InputDecoration _marco(String rotulo) => InputDecoration(
      labelText: rotulo,
      prefixIcon: const Icon(
        Icons.table_restaurant_outlined,
        size: 20,
        color: Colors.grey,
      ),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('el casillero, en modo jefe y sin él', (tester) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    final carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('casillero_muestra').path;
    final clave = GlobalKey();
    const tam = Size(900, 170);
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final jefe = TextEditingController(text: '44, 45');
    final operario = TextEditingController(text: '44, 45');
    addTearDown(jefe.dispose);
    addTearDown(operario.dispose);

    Widget columna(String titulo, TextEditingController c, bool esJefe) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              CasilleroNumeroMesa(
                controller: c,
                esJefe: esJefe,
                decoration: _marco('N° de Mesa Asignada / Contrato'),
              ),
            ],
          ),
        );

    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Scaffold(
            backgroundColor: const Color(0xFFF7F7F7),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  columna('EN MODO JEFE', jefe, true),
                  const SizedBox(width: 32),
                  columna('SIN MODO JEFE (OPERARIO)', operario, false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File(
        '$carpeta${Platform.pathSeparator}Casillero_numero_mesa.png',
      )..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  });
}
