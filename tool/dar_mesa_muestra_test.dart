// Muestras de la 6.9.4 para mirar sin levantar la app: la celda MESA de la
// grilla con DAR MESA (en modo jefe y sin él), el cartel de DAR MESA A TODOS y
// el cartel de la planilla con "Orden: Por número de mesa".
//
//   flutter test tool/dar_mesa_muestra_test.dart --dart-define=salida=C:\carpeta
//
// Los nombres son inventados. No vive en test/: guarda imágenes.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/celda_mesa_alumno.dart';
import 'package:arguello_events/features/eventos/widgets/dar_mesa_a_todos_dialog.dart';
import 'package:arguello_events/features/eventos/widgets/opciones_planilla_sorteo_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

ContratoAlumno _alumno(String id, String nombre, {String? mesa, int extras = 0}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 1,
      montoTotalPactado: 315000,
      saldoDeudor: 315000,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      cursoDivision: '2DA',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('dar_mesa').path;

  Future<void> preparar(WidgetTester tester, Size tam) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  Future<void> guardar(WidgetTester tester, GlobalKey clave, String archivo) =>
      tester.runAsync(() async {
        final boundary =
            clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final imagen = await boundary.toImage(pixelRatio: 2);
        final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
        final f = File('$carpeta${Platform.pathSeparator}$archivo')
          ..writeAsBytesSync(datos!.buffer.asUint8List());
        print('── PNG en: ${f.path}');
      });

  Future<void> cartel(
    WidgetTester tester, {
    required String archivo,
    required Future<void> Function(BuildContext context) abrir,
    Future<void> Function()? despues,
    Size tam = const Size(760, 720),
  }) async {
    await preparar(tester, tam);
    final clave = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: clave,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: Colors.white,
              body: TextButton(
                onPressed: () => abrir(context),
                child: const Text(' '),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    if (despues != null) {
      await despues();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await guardar(tester, clave, archivo);
  }

  for (final (archivo, jefe) in [
    ('DarMesa_celdas_modo_jefe.png', true),
    ('DarMesa_celdas_sin_modo_jefe.png', false),
  ]) {
    testWidgets('las celdas de la grilla, ${jefe ? 'en' : 'sin'} modo jefe',
        (tester) async {
      await preparar(tester, const Size(520, 330));
      final clave = GlobalKey();
      final filas = [
        (
          _alumno('a', 'CABRERA, JOSÉ'),
          PagoAlumno.nada,
          true,
        ),
        (
          _alumno('b', 'QUIROGA, MARCOS', mesa: '107', extras: 1),
          const PagoAlumno(base: 200000),
          true,
        ),
        (
          _alumno('c', 'ROMERO, ANA', mesa: '43, 44', extras: 1),
          const PagoAlumno(base: 315000, mesas: 70000),
          false,
        ),
      ];
      await tester.pumpWidget(
        RepaintBoundary(
          key: clave,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
            home: Scaffold(
              backgroundColor: Colors.white,
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(240),
                    1: FixedColumnWidth(200),
                  },
                  border: TableBorder.all(color: Colors.grey.shade300),
                  children: [
                    const TableRow(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'ALUMNO',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'MESA',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    for (final (a, pago, falta) in filas)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(a.nombreAlumno),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: CeldaMesaAlumno(
                              alumno: a,
                              extras: ExtrasSegunPago.de(a, pago),
                              sorteoHecho: true,
                              darMesa: falta,
                              onDarMesa: jefe ? () {} : null,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await guardar(tester, clave, archivo);
    });
  }

  testWidgets('DAR MESA A TODOS', (tester) async {
    await cartel(
      tester,
      archivo: 'DarMesa_a_todos.png',
      abrir: (context) => mostrarDarMesaATodosDialog(
        context: context,
        familias: [
          (alumno: _alumno('a', 'BENÍTEZ, FABIÁN'), noPago: true),
          (alumno: _alumno('b', 'BRITEZ, MARIANO'), noPago: true),
          (alumno: _alumno('c', 'CABRERA, JOSÉ'), noPago: true),
          (
            alumno: _alumno('d', 'QUIROGA, MARCOS', mesa: '107', extras: 1),
            noPago: false,
          ),
          (alumno: _alumno('e', 'SOSA, MARCOS'), noPago: true),
        ],
        previa: (ids) => {
          if (ids.contains('a')) 'a': [47],
          if (ids.contains('b')) 'b': [52],
          if (ids.contains('c')) 'c': [42],
          if (ids.contains('d')) 'd': [106],
          if (ids.contains('e')) 'e': [54],
        },
      ),
    );
  });

  testWidgets('el cartel de la planilla, por número de mesa', (tester) async {
    await cartel(
      tester,
      archivo: 'Planilla_orden_por_mesa.png',
      tam: const Size(760, 860),
      abrir: (context) => elegirOpcionesPlanillaSorteo(context: context),
      despues: () async {
        await tester.tap(find.text('Por número de mesa'));
      },
    );
  });
}
