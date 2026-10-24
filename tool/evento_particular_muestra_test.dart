// Arnés manual: la lista de servicios de un evento particular como queda en la
// 6.2.1 (el detalle de cada servicio, el combo junto, el extra marcado y la
// cantidad tal cual), con datos inventados. No abre la base.
//
//   flutter test tool/evento_particular_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sale Evento_servicios.png.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/widgets/servicios_del_evento.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/servicio.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

EventosServicios _l(String id, String nombre, double precio,
        {double cantidad = 1, String? grupo, int orden = 0, bool extra = false, String? detalle}) =>
    EventosServicios(
      id: id,
      eventoId: 'e',
      servicioId: 's$id',
      precioFinalAcordado: precio,
      cantidad: cantidad,
      grupo: grupo,
      comboOrden: orden,
      esExtra: extra,
      detalleServicio: detalle,
      servicio: Servicio.fromJson({'id': 's$id', 'nombre': nombre}),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('los servicios de un evento particular', (tester) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    final carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('evento_muestra').path;
    Directory(carpeta).createSync(recursive: true);

    final servicios = [
      _l('1', 'Barra libre', 450000, detalle: '4 hs · fernet, cerveza, gaseosas y agua'),
      _l('2', 'DJ', 500000, grupo: 'Combo Fiesta', detalle: '5 hs con pantalla LED y humo'),
      _l('3', 'Iluminación', 0, grupo: 'Combo Fiesta', orden: 1, detalle: 'Robóticas y luz cálida en la pista'),
      _l('4', 'Hora extra de DJ', 60000, cantidad: 1.5),
      _l('5', 'Mesa dulce', 150000, extra: true, detalle: 'Para 120 personas, temática pastel'),
    ];

    final clave = GlobalKey();
    const tam = Size(560, 720);
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
            backgroundColor: const Color(0xFFF4F1EA),
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: ServiciosDelEvento(servicios: servicios, onEditar: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}Evento_servicios.png')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  });
}
