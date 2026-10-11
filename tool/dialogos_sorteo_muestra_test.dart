// Arnés manual: dibuja los dos avisos de "sortear a los que faltan" y guarda
// PNG para mirarlos sin levantar la app ni tocar la base.
//
//   flutter test tool/dialogos_sorteo_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen:
//   Deshacer_sorteo_ultimos.png — SORTEO → Deshacer sorteo de mesas, con "Solo
//     los últimos sorteados" elegido: cómo queda cada uno, y el que no se toca;
//   Deshacer_sorteo_todo.png — el mismo aviso con "Todo" elegido y su tilde;
//   Deshacer_sorteo_de_siempre.png — sin últimos sorteados, el aviso de antes;
//   Planilla_sorteo_quienes.png — PLANILLAS → Planilla del sorteo, con la
//     pregunta nueva ("Quiénes") y "Solo los últimos sorteados" elegido.
//
// Los avisos son los de la app; los nombres son inventados.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/eventos/widgets/deshacer_sorteo_dialog.dart';
import 'package:arguello_events/features/eventos/widgets/opciones_planilla_sorteo_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');

ContratoAlumno _alumno(String id, String nombre, String? mesa) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa: mesa,
    );

SorteoMesasRegistro _sorteo(
  String id,
  Map<String, String> resultado,
  DateTime cuando, {
  Map<String, String> antes = const {},
}) =>
    SorteoMesasRegistro(
      id: id,
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: antes,
      hechoPor: 'Jefe',
      createdAt: cuando,
    );

/// Las mesas 42 y 118 quedaron libres en el primer sorteo.
const _libres = {42, 118};

/// 126 familias del primer sorteo y cinco del de los que faltaban: tres
/// nuevas, DUARTE que compró otra mesa, y FLORES, a quien mudaron después.
final _alumnos = [
  for (var i = 1; i <= 128; i++)
    if (i != 41 && !_libres.contains(i)) _alumno('p$i', 'FAMILIA $i', '$i'),
  _alumno('p41', 'DUARTE, MILAGROS', '41, 42'),
  _alumno('n1', 'ACOSTA, LARA', '129'),
  _alumno('n2', 'BENÍTEZ, TOMÁS', '130'),
  _alumno('n3', 'FLORES, IVÁN', '118'),
  _alumno('n4', 'GÓMEZ, ABRIL', '131, 132'),
];

UltimosSorteados _ultimos() {
  return UltimosSorteados.de(
    [
      // 12/11/2026 21:40 y 20/11/2026 18:05, hora de Argentina.
      _sorteo(
        's1',
        {
          for (var i = 1; i <= 128; i++)
            if (!_libres.contains(i)) 'p$i': '$i',
        },
        DateTime.utc(2026, 11, 13, 0, 40),
      ),
      _sorteo(
        's2',
        const {
          'p41': '41, 42',
          'n1': '129',
          'n2': '130',
          'n3': '133',
          'n4': '131, 132',
        },
        DateTime.utc(2026, 11, 20, 21, 5),
        antes: const {'p41': '41'},
      ),
    ],
    _alumnos,
  )!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('dialogos_sorteo').path;

  /// Abre un aviso sobre una pantalla vacía, hace [despues] y guarda el PNG.
  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    required Future<void> Function(BuildContext context) abrir,
    Future<void> Function()? despues,
    Size tam = const Size(760, 640),
  }) async {
    await cargarFuentesPlano();
    // Los íconos de Material, que en los tests no vienen cargados.
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    final clave = GlobalKey();
    tester.view.physicalSize = tam * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
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

    await tester.runAsync(() async {
      final boundary =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await boundary.toImage(pixelRatio: 2);
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$carpeta${Platform.pathSeparator}$archivo')
        ..writeAsBytesSync(datos!.buffer.asUint8List());
      print('── PNG en: ${f.path}');
    });
  }

  testWidgets('deshacer, con solo los últimos elegido', (tester) async {
    await sacar(
      tester,
      archivo: 'Deshacer_sorteo_ultimos.png',
      abrir: (context) => mostrarDeshacerSorteoDialog(
        context: context,
        conMesa: _alumnos.length,
        ultimos: _ultimos(),
      ),
    );
  });

  testWidgets('deshacer, con todo elegido', (tester) async {
    await sacar(
      tester,
      archivo: 'Deshacer_sorteo_todo.png',
      abrir: (context) => mostrarDeshacerSorteoDialog(
        context: context,
        conMesa: _alumnos.length,
        ultimos: _ultimos(),
      ),
      despues: () => tester.tap(find.byKey(const Key('deshacer_todo'))),
    );
  });

  testWidgets('deshacer, sin últimos sorteados', (tester) async {
    await sacar(
      tester,
      archivo: 'Deshacer_sorteo_de_siempre.png',
      abrir: (context) =>
          mostrarDeshacerSorteoDialog(context: context, conMesa: 128),
      tam: const Size(760, 420),
    );
  });

  testWidgets('la planilla, con la pregunta de quiénes', (tester) async {
    await sacar(
      tester,
      archivo: 'Planilla_sorteo_quienes.png',
      abrir: (context) => elegirOpcionesPlanillaSorteo(
        context: context,
        ultimos: _ultimos(),
        sugerirUltimos: true,
      ),
      tam: const Size(760, 520),
    );
  });
}
