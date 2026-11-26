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
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/widgets/celda_mesa_alumno.dart';
import 'package:arguello_events/features/eventos/widgets/chip_dar_mesa.dart';
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

  // La grilla de la fiesta con las piezas de verdad (la columna MESA y el botón
  // de la barra), antes y después de DAR MESA A TODOS, con modo jefe y sin él.
  // La pantalla entera no se puede montar sin la base: el resto de las
  // columnas va resumido.
  final antes = [
    (_alumno('a1', 'ACOSTA, LUCÍA', mesa: '41'), const PagoAlumno(base: 315000)),
    (_alumno('a2', 'LUNA, JOSÉ'), PagoAlumno.nada),
    (_alumno('a3', 'MORALES, FABIÁN'), PagoAlumno.nada),
    (_alumno('a4', 'NAVARRO, MARIANO'), PagoAlumno.nada),
    (_alumno('a5', 'OLIVERA, MARCOS'), PagoAlumno.nada),
    (
      _alumno('a6', 'RIVAS, TOMÁS', mesa: '107', extras: 1),
      const PagoAlumno(base: 200000),
    ),
    (
      _alumno('a7', 'ROMERO, ANA', mesa: '43, 44', extras: 1),
      const PagoAlumno(base: 315000, mesas: 70000),
    ),
  ];
  const dadas = {
    'a2': '42',
    'a3': '47',
    'a4': '52',
    'a5': '54',
    'a6': '107, 106',
  };
  final despues = [
    for (final (a, pago) in antes)
      (
        dadas.containsKey(a.id) ? a.copyWith(numeroMesa: dadas[a.id]) : a,
        pago,
      ),
  ];

  for (final (archivo, filas, jefe) in [
    ('DarMesa_grilla_ANTES_modo_jefe.png', antes, true),
    ('DarMesa_grilla_ANTES_sin_modo_jefe.png', antes, false),
    ('DarMesa_grilla_DESPUES.png', despues, true),
  ]) {
    testWidgets('la grilla: $archivo', (tester) async {
      await preparar(tester, const Size(760, 560));
      final clave = GlobalKey();
      final sinMesa = [
        for (final (a, _) in filas)
          if (a.numeroMesa == null || a.mesaExtraCantidad + 1 >
              MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length)
            a,
      ];
      TextStyle titulo() =>
          const TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          jefe ? 'ALUMNOS · modo jefe' : 'ALUMNOS · sin modo jefe',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        if (sinMesa.isNotEmpty)
                          ChipDarMesa(
                            cantidad: sinMesa.length,
                            onTap: jefe ? () {} : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Table(
                      columnWidths: const {
                        0: FixedColumnWidth(40),
                        1: FixedColumnWidth(240),
                        2: FixedColumnWidth(70),
                        3: FixedColumnWidth(220),
                      },
                      border: TableBorder.all(color: Colors.grey.shade300),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade100),
                          children: [
                            for (final t in ['N°', 'ALUMNO', 'CURSO', 'MESA'])
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(t, style: titulo()),
                              ),
                          ],
                        ),
                        for (final (i, (a, pago)) in filas.indexed)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text('${i + 1}'),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(a.nombreAlumno),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(a.cursoDivision ?? ''),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: CeldaMesaAlumno(
                                  alumno: a,
                                  extras: ExtrasSegunPago.de(a, pago),
                                  sorteoHecho: true,
                                  darMesa: sinMesa.contains(a),
                                  onDarMesa: jefe ? () {} : null,
                                ),
                              ),
                            ],
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
