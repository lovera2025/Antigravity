// Arnés manual: dibuja la pantalla del plano y los tres pasos de "Estilo y
// armado" con familias inventadas, y guarda PNG para mirarlos sin levantar la
// app ni tocar la base.
//
//   flutter test tool/plano_pantalla_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
//   • Pantalla_plano_<estilo>.png: la pantalla con una familia elegida;
//   • Pantalla_plano_faltan.png: un armado donde la fiesta no entra;
//   • Pasos_plano.png: la primera vez, con todo ya elegido;
//   • Pasos_plano_trabado.png: con familias ya sentadas.
//
// Los nombres son inventados: la muestra nunca usa datos reales.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/elegir_plano_dialog.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

const _apellidos = [
  'ACOSTA', 'BENÍTEZ', 'CASTRO', 'DOMÍNGUEZ', 'ESPÍNDOLA', 'FERREYRA', 'GÓMEZ',
  'HERRERA', 'IBARRA', 'JUÁREZ', 'LEDESMA', 'MOLINA', 'NÚÑEZ', 'ORTIZ',
  'PAREDES', 'QUIROGA', 'RAMÍREZ', 'SOSA', 'TORRES', 'VEGA',
];
const _nombres = [
  'VALENTINA', 'JOAQUÍN', 'MÍA', 'BRUNO', 'CAMILA', 'LUCAS', 'SOFÍA', 'TOMÁS',
];

/// Una escuela inventada que llena [mesas] mesas en tres divisiones, con
/// familias de una y de dos mesas y algunas sillas extra. Con [sorteada] en
/// false nadie tiene mesa todavía.
List<ContratoAlumno> _escuela(int mesas, {bool sorteada = true}) {
  final r = Random(11);
  final alumnos = <ContratoAlumno>[];
  var n = 1;
  var k = 0;
  while (n <= mesas) {
    final dos = n < mesas && r.nextInt(6) == 0;
    final sillas = r.nextInt(14) == 0 ? 1 + r.nextInt(2) : 0;
    final numeros = dos ? [n, n + 1] : [n];
    alumnos.add(ContratoAlumno(
      id: 'f$k',
      eventoId: 'e',
      nombreAlumno: '${_apellidos[k % _apellidos.length]}, '
          '${_nombres[(k * 3) % _nombres.length]}',
      cantidadAcompanantes: 2 + r.nextInt(6),
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: dos ? 70000 : 0,
      mesaExtraCantidad: dos ? 1 : 0,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          sorteada ? MesasExtraUtils.formatearAsignacionMesas(numeros) : null,
      cursoDivision: n <= mesas / 3
          ? '5° A'
          : n <= 2 * mesas / 3
              ? '5° B'
              : '5° C',
    ));
    n += numeros.length;
    k++;
  }
  return alumnos;
}

late String _carpeta;

Future<void> _guardar(
  WidgetTester tester,
  Widget pantalla,
  Size tam,
  String archivo,
) async {
  final clave = GlobalKey();
  tester.view.physicalSize = tam * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: FuentesPlano.linea,
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: RepaintBoundary(key: clave, child: pantalla),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await boundary.toImage(pixelRatio: 2);
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_carpeta${Platform.pathSeparator}$archivo')
      ..writeAsBytesSync(datos!.buffer.asUint8List());
    print('── PNG en: ${f.path}');
  });
}

Widget _pantalla(
  ArmadoSalon armado,
  List<ContratoAlumno> alumnos,
  EstiloPlano estilo, {
  String? resaltar,
}) =>
    Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plano del salón'),
            Text(
              'Escuela Normal (datos inventados)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: PlanoEventoCuerpo(
        plano: PlanoDeLaFiesta.desde(
          armado: armado,
          config: ConfigPlano.vacia,
          alumnos: alumnos,
        ),
        estilo: estilo,
        alumnos: alumnos,
        resaltarAlumnoId: resaltar,
        onEstiloYArmado: () {},
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await cargarFuentesPlano();
    // Los íconos de Material, que `flutter test` tampoco carga solo.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    _carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('plano_pantalla').path;
  });

  final aMedida = ArmarAMedida.armar(
    const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 132),
  ).armado;
  final escuela = _escuela(132);
  // Una familia con dos mesas y sillas extra, para ver su tarjeta.
  final elegida = escuela.firstWhere(
    (a) => a.mesaExtraCantidad > 0 && a.sillasExtraCantidad > 0,
    orElse: () => escuela.firstWhere((a) => a.mesaExtraCantidad > 0),
  );

  for (final e in EstiloPlano.values) {
    testWidgets('la pantalla del plano, en ${e.nombre}', (tester) async {
      await _guardar(
        tester,
        _pantalla(aMedida, escuela, e, resaltar: elegida.id),
        const Size(1440, 900),
        'Pantalla_plano_${e.name}.png',
      );
      // Queda corriendo el pulso de la familia resaltada.
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('la pantalla cuando la fiesta no entra en el armado',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        ArmadosPredefinidos.normal2aPaginas45(),
        _escuela(132, sorteada: false),
        EstiloPlano.arquitecto,
      ),
      const Size(1440, 900),
      'Pantalla_plano_faltan.png',
    );
  });

  testWidgets('los tres pasos, la primera vez', (tester) async {
    await _guardar(
      tester,
      const Scaffold(
        backgroundColor: Color(0xFF5F6368),
        body: ElegirPlanoDialog(
          mesasNecesarias: 132,
          medidas: MedidasPlano(),
        ),
      ),
      const Size(1200, 1000),
      'Pasos_plano.png',
    );
  });

  testWidgets('los tres pasos, con familias ya sentadas', (tester) async {
    final plano = PlanoEvento.nuevo(
      eventoId: 'e0000000-0000-4000-8000-000000000001',
      armado: aMedida,
      estilo: EstiloPlano.gala,
      modo: ModoSorteo.bloques,
      ahora: DateTime.utc(2026, 10, 1),
    );
    await _guardar(
      tester,
      Scaffold(
        backgroundColor: const Color(0xFF5F6368),
        body: ElegirPlanoDialog(
          mesasNecesarias: 132,
          medidas: const MedidasPlano(),
          actual: plano,
          ocupantes: PlanoDeLaFiesta.ocupantes(escuela, const {}),
          armadoTrabado: 'Ya hay familias con mesa: para cambiar el armado hay '
              'que deshacer el sorteo. El estilo se cambia siempre.',
        ),
      ),
      const Size(1200, 1000),
      'Pasos_plano_trabado.png',
    );
  });
}
