// Arnés manual: dibuja la columna MESA de la grilla y el chip "Mesas y sillas"
// con familias inventadas, y guarda un PNG para mirarlo sin levantar la app ni
// tocar la base.
//
//   flutter test tool/grilla_mesas_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sale `Grilla_mesas_y_sillas.png`: cada caso sin el filtro y con el filtro
// puesto, antes y después del sorteo. Los nombres son inventados.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/filtro_mesas_sillas.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/celda_mesa_alumno.dart';
import 'package:arguello_events/features/eventos/widgets/chip_mesas_sillas.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

class _Caso {
  final String que;
  final ContratoAlumno alumno;
  final PagoAlumno pago;
  final SillasReparto? reparto;
  const _Caso(this.que, this.alumno, this.pago, {this.reparto});
}

ContratoAlumno _a(
  String nombre, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
}) =>
    ContratoAlumno(
      id: nombre,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

final _casos = <_Caso>[
  _Caso('Solo la del contrato, con la base pagada', _a('ACOSTA, VALENTINA'),
      const PagoAlumno(base: 90000)),
  _Caso('Sin nada pagado', _a('BENÍTEZ, JOAQUÍN'), PagoAlumno.nada),
  _Caso('Una mesa agregada, pagada entera', _a('CASTRO, MÍA', extras: 1),
      const PagoAlumno(base: 90000, mesas: 70000)),
  _Caso('Una mesa agregada, en cuotas', _a('DOMÍNGUEZ, BRUNO', extras: 1),
      const PagoAlumno(base: 90000, mesas: 20000)),
  _Caso('Una mesa agregada, sin pagar', _a('ESPÍNDOLA, CAMILA', extras: 1),
      const PagoAlumno(base: 90000)),
  _Caso('Dos agregadas y 3 sillas pagadas',
      _a('FERREYRA, LUCAS', extras: 2, sillas: 3),
      const PagoAlumno(base: 90000, mesas: 40000, sillas: 24000)),
  _Caso('Sillas sin pagar', _a('GÓMEZ, SOFÍA', sillas: 2),
      const PagoAlumno(base: 90000)),
  _Caso('Ya sorteado: falta elegir las sillas',
      _a('HERRERA, TOMÁS', extras: 1, sillas: 3, mesas: [12, 13]),
      const PagoAlumno(base: 90000, mesas: 70000, sillas: 24000)),
  _Caso(
    'Ya sorteado: sillas elegidas',
    _a('IBARRA, VALENTINA', extras: 1, sillas: 3, mesas: [20, 21]),
    const PagoAlumno(base: 90000, mesas: 70000, sillas: 24000),
    reparto: SillasReparto(
      id: 'r',
      contratoAlumnoId: 'IBARRA, VALENTINA',
      sillasPrincipal: 2,
      sillasExtra: 3,
      mesas: 2,
      createdAt: DateTime(2026, 11, 10),
      updatedAt: DateTime(2026, 11, 10),
    ),
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la columna Mesa y el chip, con familias inventadas',
      (tester) async {
    await cargarFuentesPlano();
    // Los íconos de Material, que en los tests no vienen cargados.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    final alumnos = [for (final c in _casos) c.alumno];
    final extras = extrasPorAlumno(
      alumnos,
      {for (final c in _casos) c.alumno.id: c.pago},
    );
    Widget chip(FiltroExtras filtro) => ChipMesasSillas(
          filtro: filtro,
          onFiltro: (_) {},
          pendientes: alumnos
              .where((a) => tieneAlgoPendienteDeExtras(a, extras[a.id]))
              .length,
          cuantos: contarPorFiltro(alumnos, extras, const {}),
          totales: totalesDeExtras(alumnos, extras),
        );
    Widget celda(_Caso c, {required bool marcar}) => SizedBox(
          width: 150,
          child: CeldaMesaAlumno(
            alumno: c.alumno,
            reparto: c.reparto,
            onElegirSillas: () {},
            extras: extras[c.alumno.id],
            marcarPago: marcar,
          ),
        );
    const cabecera = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      color: Color(0xFF6B7280),
    );

    final clave = GlobalKey();
    const tam = Size(1040, 760);
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
        home: RepaintBoundary(
          key: clave,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Columna MESA de la grilla · datos inventados',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('El chip, sin filtro:  '),
                      chip(FiltroExtras.todos),
                      const SizedBox(width: 28),
                      const Text('con un filtro puesto:  '),
                      chip(FiltroExtras.mesaSinPagar),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      SizedBox(width: 230, child: Text('ALUMNO', style: cabecera)),
                      SizedBox(
                        width: 200,
                        child: Text('MESA · SIN FILTRO', style: cabecera),
                      ),
                      SizedBox(
                        width: 200,
                        child: Text('MESA · CON EL FILTRO', style: cabecera),
                      ),
                      Expanded(child: Text('QUÉ ES', style: cabecera)),
                    ],
                  ),
                  const Divider(),
                  for (final c in _casos) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 230,
                          child: Text(
                            c.alumno.nombreAlumno,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 200, child: Align(
                          alignment: Alignment.centerLeft,
                          child: celda(c, marcar: false),
                        )),
                        SizedBox(width: 200, child: Align(
                          alignment: Alignment.centerLeft,
                          child: celda(c, marcar: true),
                        )),
                        Expanded(
                          child: Text(
                            c.que,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 22),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('grilla_muestra').path;
    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}Grilla_mesas_y_sillas.png')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  });
}
