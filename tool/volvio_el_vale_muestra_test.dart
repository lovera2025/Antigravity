// La ventana de anular con "¿Volvió el vale?" (28-nov-2026), para mirarla, sin base ni
// nube:
//
//   flutter test tool/volvio_el_vale_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Salen, en el diseño de la barra (Noche dorada), en una tablet y en un celular:
//   • Vale_1_pregunta.png: recién abierta, con el motivo escrito y sin contestar;
//   • Vale_2_no_volvio.png: con NO, YA SE ENTREGÓ elegido (lo que pasa, en naranja);
//   • Vale_3_celular.png: lo mismo en un celular de 390 de ancho.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/estilos/disenio_barra.dart';
import 'package:arguello_events/features/barra/widgets/anular_venta_dialog.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';

import '../test/helpers/tema_de_la_app.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty ? _salida : Directory.systemTemp.createTempSync('vale_muestra').path;
  Directory(carpeta).createSync(recursive: true);

  Future<void> letras() async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String nombre) async {
    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 1);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final archivo = File('$carpeta${Platform.pathSeparator}$nombre')..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${archivo.path}');
    });
  }

  Future<GlobalKey> abrir(WidgetTester tester, Size tamano) async {
    await letras();
    final clave = GlobalKey();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaDeVender(DisenioBarra.nocheDorada, base: temaClaroDeLaApp()),
        home: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Ventas · Caja 2')),
            body: Center(
              child: FilledButton(
                onPressed: () => pedirAnulacion(
                  context,
                  titulo: r'Anular la N° 0017 · $ 10.000',
                  explicacion: 'Deja de contar en la caja. No se puede deshacer, y queda anotado con tu '
                      'nombre y el motivo.',
                  preguntaPorElVale: true,
                ),
                child: const Text('ANULAR'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ANULAR'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('motivo_texto')), 'Se equivocó de bebida');
    await tester.pumpAndSettle();
    return clave;
  }

  testWidgets('en una tablet', (tester) async {
    final clave = await abrir(tester, const Size(1000, 760));
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Vale_1_pregunta.png');
    await tester.tap(find.byKey(const Key('anular_vale_no_volvio')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, 'Vale_2_no_volvio.png');
  });

  testWidgets('en un celular', (tester) async {
    final clave = await abrir(tester, const Size(390, 844));
    await tester.tap(find.byKey(const Key('anular_vale_no_volvio')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'en un celular angosto no se desborda');
    await guardar(tester, clave, 'Vale_3_celular.png');
  });
}
