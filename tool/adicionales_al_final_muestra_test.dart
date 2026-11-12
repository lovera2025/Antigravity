// Muestras de la 6.6.1: la numeración fila por fila y las mesas adicionales al
// final. Salen de la pantalla y del cartel de verdad, con el salón entero (el
// playón de 30 m de frente y 46 de fondo, 80 mesas) y familias inventadas: una
// escuela de 67 familias con 13 adicionales, como la del sorteo del 12-nov.
//
//   flutter test tool/adicionales_al_final_muestra_test.dart
//     --dart-define=salida=<carpeta>
//
// Salen:
//   • 1_numeracion_por_mitades.png: como hasta hoy, la pasarela corta los números;
//   • 2_numeracion_fila_por_fila.png: cada fila cruza la pasarela;
//   • 3_acomodar_la_opcion.png: dónde se elige, en Personalizar → Acomodar;
//   • 4_cartel_como_abre.png: el cartel del sorteo, en "Con su familia";
//   • 5_cartel_al_final.png: con "Al final" elegido;
//   • 6_cartel_con_excepciones.png: con una adicional pegada y una familia junta;
//   • 7_plano_sorteado.png: cómo queda el salón, con una familia resaltada.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/services/sorteo_mesas_motor.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/services/sorteo_con_plano.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
late String _carpeta;

const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39);

ArmadoSalon _salon(FinNumeracion fin) => ArmarAMedida.armar(
      OpcionesAMedida(playon: _playon, cantidad: 80, fin: fin),
    ).armado;

const _apellidos = [
  'ACOSTA', 'BENÍTEZ', 'CABRERA', 'DOMÍNGUEZ', 'ESCOBAR', 'FERREYRA',
  'GIMÉNEZ', 'HERRERA', 'IBARRA', 'JUÁREZ', 'LEDESMA', 'MEDINA',
];

ContratoAlumno _familia(
  int i, {
  List<int> mesas = const [],
}) {
  // Nueve familias con una adicional y dos con dos: 13 adicionales.
  final extras = i <= 9 ? 1 : (i <= 11 ? 2 : 0);
  return ContratoAlumno(
    id: 'f$i',
    eventoId: 'e',
    nombreAlumno: i <= _apellidos.length
        ? '${_apellidos[i - 1]}, ALUMNO'
        : 'FAMILIA $i, ALUMNO',
    cantidadAcompanantes: 3,
    montoTotalPactado: 300000,
    saldoDeudor: 0,
    mesaExtraPrecio: 70000.0 * extras,
    mesaExtraCantidad: extras,
    numeroMesa:
        mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    cursoDivision: i.isEven ? '5° A' : '5° B',
  );
}

final _acciones = AccionesPlano(
  onFijarEnMesa: (_) {},
  onFijar: (_, _) {},
  onQuitarFijadas: (_) {},
  onQuitarFijadaDeMesa: (_) {},
  onDejarLibre: (_) {},
  onVolverAUsar: (_) {},
  onCambiar: (_, _) {},
  onMover: (_, _) {},
  onGuardarMedidas: (_, _) {},
  onGuardarColoresYTextos: (_, _) {},
  onGuardarArmado: (_, _, _, _, _, _, _) {},
  onGuardarComoPredio: (_, _) {},
);

Widget _pantalla(
  ArmadoSalon armado,
  List<ContratoAlumno> alumnos, {
  ConfigPlano config = ConfigPlano.vacia,
  String? resaltar,
  required String subtitulo,
}) =>
    Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plano del salón'),
            Text(
              subtitulo,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: PlanoEventoCuerpo(
        plano: PlanoDeLaFiesta.desde(
          armado: armado,
          config: config,
          alumnos: alumnos,
        ),
        estilo: EstiloPlano.arquitecto,
        alumnos: alumnos,
        resaltarAlumnoId: resaltar,
        acciones: _acciones,
        onImprimir: () {},
        onHistorial: () {},
      ),
    );

Future<void> _guardar(
  WidgetTester tester,
  Widget pantalla,
  Size tam,
  String archivo, {
  Future<void> Function()? antes,
}) async {
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
  if (antes != null) {
    await antes();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
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
  // Puede quedar corriendo el pulso de una familia resaltada.
  await tester.pumpWidget(const SizedBox());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    _carpeta = _salida.isNotEmpty
        ? _salida
        : Directory.systemTemp.createTempSync('adicionales_al_final').path;
    Directory(_carpeta).createSync(recursive: true);
  });

  const tam = Size(1440, 1000);
  final sinMesa = [for (var i = 1; i <= 67; i++) _familia(i)];
  final porFilas = _salon(FinNumeracion.filas);
  const configFilas = ConfigPlano(numeracion: FinNumeracion.filas);

  testWidgets('como hasta hoy: la pasarela corta los números', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        _salon(FinNumeracion.fondo),
        sinMesa,
        config: const ConfigPlano(numeracion: FinNumeracion.fondo),
        subtitulo: 'Como hasta hoy ("Al fondo"): toda la izquierda y después '
            'toda la derecha',
      ),
      tam,
      '1_numeracion_por_mitades.png',
    );
  });

  testWidgets('fila por fila: cada fila cruza la pasarela', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        porFilas,
        sinMesa,
        config: configFilas,
        subtitulo: 'Fila por fila (6.6.1): cada fila va de una punta a la otra',
      ),
      tam,
      '2_numeracion_fila_por_fila.png',
    );
  });

  testWidgets('dónde se elige: Personalizar → Acomodar', (tester) async {
    await _guardar(
      tester,
      _pantalla(
        _salon(FinNumeracion.fondo),
        sinMesa,
        config: const ConfigPlano(numeracion: FinNumeracion.fondo),
        subtitulo: 'Personalizar → Acomodar → La numeración',
      ),
      tam,
      '3_acomodar_la_opcion.png',
      antes: () async {
        await tester.tap(find.text('PERSONALIZAR'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Acomodar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.text('Fila por fila'));
        await tester.pump();
        await tester.tap(find.text('Fila por fila'));
        await tester.pump();
      },
    );
  });

  final pagos = {
    for (final a in sinMesa)
      a.id: PagoAlumno(base: 35000, mesas: a.mesaExtraPrecio),
  };
  final plano = PlanoEvento.nuevo(
    eventoId: 'e',
    armado: porFilas,
    estilo: EstiloPlano.arquitecto,
    modo: ModoSorteo.entera,
    ahora: DateTime.utc(2026, 11, 11),
  );
  Widget cartel() => Scaffold(
        body: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA (datos inventados)',
          alumnos: sinMesa,
          avisos: const [],
          pagos: pagos,
          plano: plano,
        ),
      );
  const tamCartel = Size(900, 1500);

  testWidgets('el cartel del sorteo, como abre', (tester) async {
    await _guardar(tester, cartel(), tamCartel, '4_cartel_como_abre.png');
  });

  testWidgets('el cartel con "Al final"', (tester) async {
    await _guardar(
      tester,
      cartel(),
      tamCartel,
      '5_cartel_al_final.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('adicionales_al_final')));
        await tester.pump();
      },
    );
  });

  testWidgets('el cartel con una pegada y una familia junta', (tester) async {
    await _guardar(
      tester,
      cartel(),
      tamCartel,
      '6_cartel_con_excepciones.png',
      antes: () async {
        await tester.tap(find.byKey(const Key('adicionales_al_final')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('dejar_juntas_f2')));
        await tester.pump();
      },
    );
  });

  // Lo mismo que hace el sorteo al confirmar, con "Al final" y ninguna pegada.
  final entrada = EntradaSorteoPlano(
    armado: porFilas,
    config: configFilas,
    alumnos: sinMesa,
    alFinal: SorteoConPlano.alFinalSegunElCartel(
      SorteoMesasMotor.pedidos(sinMesa),
    ),
  );
  final sorteo = SorteoConPlano.sortear(entrada, random: Random(7));
  final sorteados = [
    for (var i = 1; i <= 67; i++)
      _familia(i, mesas: sorteo.asignaciones['f$i']!),
  ];

  testWidgets('el salón sorteado: principales adelante, adicionales al fondo',
      (tester) async {
    expect(SorteoConPlano.validar(entrada, sorteo), isNull);
    print('BENÍTEZ (f2): ${sorteo.asignaciones['f2']} · '
        'JUÁREZ (f10): ${sorteo.asignaciones['f10']}');
    await _guardar(
      tester,
      _pantalla(
        porFilas,
        sorteados,
        config: configFilas,
        resaltar: 'f10',
        subtitulo: 'Sorteado con "Al final": las principales de la 1 a la 67, '
            'las adicionales de la 68 a la 80. Resaltada: una familia con 3 '
            'mesas',
      ),
      tam,
      '7_plano_sorteado.png',
    );
  });
}
