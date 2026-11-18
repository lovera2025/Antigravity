// Las capturas de la mesa adicional "a confirmar" (6.9.2), con las pantallas de
// verdad montadas en memoria y familias inventadas: lo que ve la recepcionista
// y lo que hace el jefe en el PLANO (cobrarla o anularla).
//
//   flutter test tool/a_confirmar_muestra_test.dart --dart-define=salida=<carpeta>
//
// Sin `salida`, las deja en una carpeta temporal y dice dónde.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:arguello_events/models/plano_evento.dart';

import '../test/helpers/plano_en_memoria.dart';
import '../test/helpers/puerta_en_memoria.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _eventoId = 'e0000000-0000-4000-8000-000000000001';
final _ahora = DateTime.utc(2026, 11, 18, 15);

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  List<int> mesas = const [],
  String division = '5° A',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: _eventoId,
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000 + 70000.0 * extras,
      saldoDeudor: 70000.0 * extras,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

Map<String, dynamic> _pagoDeMesa(double monto) => {
      'concepto': 'Mesa extra (1/1)',
      'monto': monto,
      'monto_gross': monto,
      'anulado': 0,
    };

/// Un salón de 40 mesas con veinte familias sentadas. GARCÍA (la 8 y la 9) no
/// pagó nada de su adicional; MEDINA (la 14 y la 15) pagó una parte; RUIZ (la 25
/// y la 26) la pagó entera.
List<ContratoAlumno> _alumnos() => [
      _alumno('garcia', 'GARCÍA, LUCAS', extras: 1, mesas: [8, 9]),
      _alumno('medina', 'MEDINA, SOL', extras: 1, mesas: [14, 15]),
      _alumno('ruiz', 'RUIZ, TOMÁS', extras: 1, mesas: [25, 26], division: '5° B'),
      for (final (i, n) in const [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 16, 17, 18]
          .indexed)
        _alumno('f$i', 'FAMILIA ${i + 1}, ALUMNO',
            mesas: [n], division: i.isEven ? '5° A' : '5° B'),
    ];

Map<String, List<Map<String, dynamic>>> _pagos() => {
      'garcia': const [],
      'medina': [_pagoDeMesa(30000)],
      'ruiz': [_pagoDeMesa(70000)],
    };

final _evento = Evento(
  id: _eventoId,
  clienteId: 'c0000000-0000-4000-8000-000000000001',
  tipo: 'Recepción',
  fechaEvento: DateTime(2026, 12, 12),
  estado: EstadoEvento.confirmado,
  modalidad: 'masivo',
);

PlanoEvento _plano() => PlanoEvento.nuevo(
      eventoId: _eventoId,
      armado: ArmarAMedida.armar(
        const OpcionesAMedida(playon: PlayonReal.costaSurubi, cantidad: 40),
      ).armado,
      estilo: EstiloPlano.arquitecto,
      modo: ModoSorteo.entera,
      ahora: _ahora,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('a_confirmar_muestra').path;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    Directory(carpeta).createSync(recursive: true);
    await cargarFuentesPlano();
    // Los íconos de Material, que en los tests no vienen cargados.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();
    // Outfit, con los nombres con que la pide `google_fonts` (Recepción). En la
    // app la encuentra sola entre los archivos; acá hay que tenerla cargada.
    final regular = FontLoader('Outfit_regular')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Regular.ttf'));
    await regular.load();
    final negrita = FontLoader('Outfit_700')
      ..addFont(rootBundle.load('assets/google_fonts/Outfit-Bold.ttf'));
    await negrita.load();
  });

  /// La pantalla entera, como está: también un cartel abierto encima.
  Future<void> guardar(WidgetTester tester, String archivo) async {
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final vista = tester.binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final capa = vista.layer! as OffsetLayer;
      final imagen = await capa.toImage(
        Offset.zero & (vista.size * tester.view.devicePixelRatio),
      );
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      // ignore: avoid_print
      print('── PNG en: ${f.path}');
    });
  }

  /// La pantalla del plano, con el doble de puntos para que se lea al acercar.
  Future<MundoDelPlano> abrirPlano(
    WidgetTester tester, {
    bool esJefe = true,
  }) async {
    final mundo = await montarPlanoDeLaFiesta(
      tester,
      evento: _evento,
      plano: _plano(),
      alumnos: _alumnos(),
      pagos: _pagos(),
      esJefe: esJefe,
      tamanio: const Size(1400, 860),
    );
    // Más puntos, misma pantalla.
    tester.view.physicalSize = const Size(2800, 1720);
    tester.view.devicePixelRatio = 2;
    await asentar(tester);
    return mundo;
  }

  Future<void> elegir(WidgetTester tester, String id, String apellido) async {
    await tester.enterText(find.byKey(const Key('buscar')), apellido);
    await asentar(tester);
    await tester.tap(find.byKey(Key('resultado_$id')));
    await asentar(tester);
    // Más cerca: se leen los números y el relojito.
    await tester.tap(find.byKey(const Key('acercar')));
    await asentar(tester);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('el PLANO en modo jefe: la tarjeta con COBRAR y ANULAR',
      (tester) async {
    await abrirPlano(tester);
    await elegir(tester, 'garcia', 'GARCÍA');
    expect(find.text('Mesa adicional 9 · a confirmar'), findsOneWidget);
    await guardar(tester, 'AConfirmar_1_plano_modo_jefe.png');
  });

  testWidgets('el PLANO en modo jefe: con algo pagado no se anula',
      (tester) async {
    await abrirPlano(tester);
    await elegir(tester, 'medina', 'MEDINA');
    expect(find.textContaining('esta noche no se anula'), findsOneWidget);
    await guardar(tester, 'AConfirmar_2_con_algo_pagado.png');
  });

  testWidgets('ANULAR: el cartel, y cómo queda', (tester) async {
    await abrirPlano(tester);
    await elegir(tester, 'garcia', 'GARCÍA');
    await tester.tap(find.byKey(const Key('anular_a_confirmar_9')));
    await asentar(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Anular la mesa 9 de GARCÍA'), findsOneWidget);
    await guardar(tester, 'AConfirmar_3_cartel_de_anular.png');
    await tester.tap(find.byKey(const Key('confirmar')));
    await asentar(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('GARCÍA dejó la 9'), findsOneWidget);
    await guardar(tester, 'AConfirmar_4_anulada.png');
  });

  testWidgets('el PLANO sin modo jefe: se ve, y nada más', (tester) async {
    await abrirPlano(tester, esJefe: false);
    await elegir(tester, 'garcia', 'GARCÍA');
    expect(find.byKey(const Key('a_pagar_9')), findsNothing);
    await guardar(tester, 'AConfirmar_5_sin_modo_jefe.png');
  });

  testWidgets('Recepción: la línea apagada, y lo que dice al tocarla',
      (tester) async {
    final supabase = supabaseDePrueba();
    final mundo = PuertaEnMemoria(
      supabase,
      alumnos: [
        alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
            mesas: [12], acomp: ['GÓMEZ, ANA']),
        alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
            mesas: [14, 15], extras: 1, acomp: ['ACOSTA, RAÚL'], division: '5° A'),
      ],
      pagos: {
        'perez': [
          {'concepto': 'Cuota Base', 'monto': 300000.0, 'monto_gross': 300000.0, 'anulado': 0},
        ],
        'acosta': [
          {'concepto': 'Cuota Base', 'monto': 300000.0, 'monto_gross': 300000.0, 'anulado': 0},
        ],
      },
    );
    tester.view.physicalSize = const Size(2732, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(mundo.motor.bajo.close);
    await tester.pumpWidget(mundo.panel(eventoMasivo));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(find.byKey(const ValueKey('mesa_acosta_15')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Esta mesa la confirma el jefe.'), findsOneWidget);
    await guardar(tester, 'AConfirmar_6_recepcion.png');
  });
}
