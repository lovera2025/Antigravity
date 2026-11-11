// Muestras de la 6.5.1: la numeración que termina al fondo y la mesa nueva para
// quien llega después del sorteo. Salen de la pantalla y del cartel de verdad, con
// el salón entero (30 m de frente, 46 de fondo, 101 mesas) y familias inventadas.
//
//   flutter test tool/mesas_al_fondo_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
//   • 1_numeracion_de_siempre.png: la 101 queda junto al escenario;
//   • 2_numeracion_al_fondo.png: la 101 queda al fondo, a la derecha;
//   • 3_acomodar_la_opcion.png: dónde se elige, en Personalizar → Acomodar;
//   • 4_cartel_del_sorteo.png: "¿Dónde van las mesas que faltan?";
//   • 5_plano_con_las_nuevas.png: la 102 y la 103 al fondo, a la derecha;
//   • 6_plano_en_papel.pdf: el mismo salón, como sale impreso;
//   • 7_otra_fiesta_viene_elegido.png: en otra fiesta, Acomodar ya viene con lo
//     último que se eligió.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/pdf_service.dart';
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
import 'package:arguello_events/features/plano/services/mesas_nuevas_al_fondo.dart';
import 'package:arguello_events/features/plano/services/numeracion_recordada.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/models/cliente.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
late String _carpeta;

const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8);

ArmadoSalon _salon(FinNumeracion fin) => ArmarAMedida.armar(
      OpcionesAMedida(playon: _playon, cantidad: 101, fin: fin),
    ).armado;

ContratoAlumno _familia(
  String id,
  String nombre, {
  int extras = 0,
  List<int> mesas = const [],
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// La escuela ya sorteada: una familia por mesa, menos la 9 (de la que pagó su
/// adicional tarde) y la 52, que quedó libre.
List<ContratoAlumno> _sorteados() => [
      for (var n = 1; n <= 101; n++)
        if (n != 9 && n != 52) _familia('f$n', 'FAMILIA $n, ALUMNO', mesas: [n]),
    ];

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
  String subtitulo = 'Escuela de prueba (datos inventados)',
  NumeracionRecordada? recordada,
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
        numeracionRecordada: recordada,
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
        : Directory.systemTemp.createTempSync('mesas_al_fondo').path;
    Directory(_carpeta).createSync(recursive: true);
  });

  const tam = Size(1440, 1000);
  final sinMesa = [
    for (var n = 1; n <= 101; n++) _familia('f$n', 'FAMILIA $n, ALUMNO'),
  ];

  testWidgets('la numeración de siempre: la 101 junto al escenario',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        _salon(FinNumeracion.escenario),
        sinMesa,
        subtitulo: 'La numeración termina junto al escenario (como hasta hoy)',
      ),
      tam,
      '1_numeracion_de_siempre.png',
    );
  });

  testWidgets('la numeración al fondo: la 101 al fondo, a la derecha',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        _salon(FinNumeracion.fondo),
        sinMesa,
        config: const ConfigPlano(numeracion: FinNumeracion.fondo),
        subtitulo: 'La numeración termina al fondo (6.5.1)',
      ),
      tam,
      '2_numeracion_al_fondo.png',
    );
  });

  testWidgets('dónde se elige: Personalizar → Acomodar', (tester) async {
    await _guardar(
      tester,
      _pantalla(_salon(FinNumeracion.escenario), sinMesa),
      tam,
      '3_acomodar_la_opcion.png',
      antes: () async {
        await tester.tap(find.text('PERSONALIZAR'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Acomodar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Al fondo'));
        await tester.pump();
      },
    );
  });

  // Otra fiesta, sin sortear y que nunca eligió: como en una anterior se guardó
  // "Al fondo", Acomodar ya viene así y solo falta GUARDAR. Nadie tocó la opción.
  testWidgets('otra fiesta: Acomodar viene con lo último que se eligió',
      (tester) async {
    await _guardar(
      tester,
      _pantalla(
        _salon(FinNumeracion.escenario),
        sinMesa,
        subtitulo: 'Otra fiesta, sin sortear: viene con lo último que se eligió',
        recordada: NumeracionRecordada(
          FinNumeracion.fondo,
          DateTime.utc(2026, 11, 11, 15),
        ),
      ),
      tam,
      '7_otra_fiesta_viene_elegido.png',
      antes: () async {
        await tester.tap(find.text('PERSONALIZAR'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Acomodar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('numeracion_recordada')), findsOneWidget);
      },
    );
  });

  // Dos que llegaron después del sorteo: la de la mesa 9 pagó su adicional, y
  // una familia nueva pagó su primera cuota.
  final tarde = _familia('tarde', 'ROMERO, LUCAS', extras: 1, mesas: [9]);
  final nueva = _familia('nueva', 'DÍAZ, SOFÍA');
  final alumnos = [..._sorteados(), tarde, nueva];
  final pagos = {
    for (final a in alumnos) a.id: const PagoAlumno(base: 35000, mesas: 70000),
    'tarde': PagoAlumno(
      base: 35000,
      mesas: 70000,
      ultimo: DateTime.utc(2026, 11, 11, 13),
    ),
    'nueva': PagoAlumno(base: 35000, ultimo: DateTime.utc(2026, 11, 11, 14)),
  };
  final salon = _salon(FinNumeracion.escenario);

  testWidgets('el cartel del sorteo, con dos que llegaron tarde',
      (tester) async {
    await _guardar(
      tester,
      Scaffold(
        body: SorteoMesasDialog(
          tituloInstitucion: 'ESCUELA DE PRUEBA',
          alumnos: alumnos,
          avisos: const [],
          pagos: pagos,
          plano: PlanoEvento.nuevo(
            eventoId: 'e',
            armado: salon,
            estilo: EstiloPlano.arquitecto,
            modo: ModoSorteo.entera,
            ahora: DateTime.utc(2026, 11, 10),
          ),
        ),
      ),
      const Size(900, 1000),
      '4_cartel_del_sorteo.png',
    );
  });

  // Lo mismo que hace el sorteo al confirmar: las mesas nuevas, y cada familia
  // con la suya.
  final plan = MesasNuevasAlFondo.planear(
    armado: salon,
    config: ConfigPlano.vacia,
    alumnos: alumnos,
    pedidos: SorteoMesasMotor.pedidos(alumnos),
    llegada: llegadaPorPago(pagos),
    por: 'Jefe',
    ahora: DateTime.utc(2026, 11, 11, 15),
  );
  final dadas = plan.porAlumno;
  final despues = [
    for (final a in alumnos)
      dadas.containsKey(a.id)
          ? _familia(
              a.id,
              a.nombreAlumno,
              extras: a.mesaExtraCantidad,
              mesas: [
                ...MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa),
                ...dadas[a.id]!,
              ],
            )
          : a,
  ];

  test('el plano en papel, con las mesas nuevas', () async {
    final bytes = await PdfService.construirPlanoPdf(
      Evento(
        id: 'e',
        clienteId: 'c',
        tipo: 'Recepción',
        fechaEvento: DateTime(2026, 12, 5),
        estado: EstadoEvento.planificacion,
        modalidad: 'masivo',
        cliente: Cliente(id: 'c', nombreCompleto: 'ESCUELA DE PRUEBA'),
      ),
      PlanoDeLaFiesta.desde(
        armado: plan.armado,
        config: plan.config,
        alumnos: despues,
      ),
      estilo: EstiloPlano.arquitecto,
      generada: DateTime(2026, 11, 11, 9, 15),
    );
    final f = File('$_carpeta${Platform.pathSeparator}6_plano_en_papel.pdf')
      ..writeAsBytesSync(bytes);
    print('── PDF en: ${f.path}');
  });

  testWidgets('el plano con las mesas nuevas, al fondo a la derecha',
      (tester) async {
    print('Mesas nuevas: ${plan.mesas.map((m) => '${m.numero}→${m.alumnoId}')}');
    await _guardar(
      tester,
      _pantalla(
        plan.armado,
        despues,
        config: plan.config,
        resaltar: 'tarde',
        subtitulo: 'Después: la 102 y la 103 al fondo, a la derecha. Nadie más '
            'se movió',
      ),
      tam,
      '5_plano_con_las_nuevas.png',
    );
  });
}
