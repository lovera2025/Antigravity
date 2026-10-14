// Arnés manual: dibuja la ventana de PLANILLAS → "Acompañantes y música" y
// guarda PNG y un Excel de muestra, para mirarlos sin levantar la app ni tocar
// la base.
//
//   flutter test tool/planilla_delegado_muestra_test.dart --dart-define=salida=<carpeta>
//
// Salen, como se ven en una notebook (1366 × 768):
//   Delegado_1_ventana.png — la ventana al abrir;
//   Delegado_2_antes_de_guardar.png — después de elegir el Excel completado;
//   Delegado_3_cambia_lo_que_tenian.png — cuando un alumno ya tenía algo;
//   Delegado_4_otra_institucion.png — el Excel de otra institución;
//   Delegado_5_importado.png — después de importar;
//   Acompañantes y música - ESCUELA DE MUESTRA.xlsx — como lo recibe el delegado.
//
// La ventana y el Excel son los de la app; la escuela y los nombres son
// inventados.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/services/planilla_delegado_bloqueo.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _salida = String.fromEnvironment('salida', defaultValue: '');
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _otra = 'e0000000-0000-4000-8000-000000000002';
const _escuela = 'ESCUELA DE MUESTRA';

const _nombres = [
  'ACOSTA, BRISA',
  'BENITEZ, JOAQUIN',
  'CABRAL, MILAGROS',
  'DUARTE, TOBIAS',
  'ESCOBAR, CAMILA',
  'FERNANDEZ, IVAN',
  'GIMENEZ, LUCIA',
  'HERRERA, MATEO',
  'INSAURRALDE, SOL',
  'JARA, THIAGO',
  'LEDESMA, ABRIL',
  'MEZA, BAUTISTA',
];

ContratoAlumno _alumno(
  int i, {
  List<String> acomp = const [],
  String? musica,
  String? nombre,
}) =>
    ContratoAlumno(
      id: '${(i + 161).toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000',
      eventoId: _evento,
      nombreAlumno: nombre ?? _nombres[i],
      // (el de baja lleva su propio número, para no repetir el id de otro)
      cantidadAcompanantes: acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: i < 7 ? '6° A' : '6° B',
      musicaElegida: musica,
    );

List<ContratoAlumno> _alumnos({bool conAlgoCargado = false}) => [
      for (var i = 0; i < _nombres.length; i++)
        conAlgoCargado && i == 1
            ? _alumno(i, acomp: ['Raúl Benítez'], musica: 'Thunderstruck')
            : conAlgoCargado && i == 4
                ? _alumno(i, musica: 'Tusa')
                : _alumno(i),
      _alumno(_nombres.length, nombre: '[BAJA] ZALAZAR, NAHUEL'),
    ];

/// El Excel de [alumnos] con lo que escribió el delegado.
Uint8List _completado(
  List<ContratoAlumno> alumnos,
  Map<String, (String, String)> escrito, {
  String evento = _evento,
  String institucion = _escuela,
}) {
  final excel = Excel.decodeBytes(
    PlanillaDelegado.armar(
      eventoId: evento,
      institucion: institucion,
      alumnos: alumnos,
    ),
  );
  final hoja = excel.tables.values.first;
  CellIndex en(int c, int f) =>
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: f);
  for (var f = PlanillaDelegado.filaEncabezados + 1; f < hoja.maxRows; f++) {
    final e = escrito[hoja.cell(en(1, f)).value?.toString()];
    if (e == null) continue;
    hoja.cell(en(PlanillaDelegado.columnaAcompanantes, f)).value =
        TextCellValue(e.$1);
    hoja.cell(en(PlanillaDelegado.columnaMusica, f)).value = TextCellValue(e.$2);
  }
  return Uint8List.fromList(excel.encode()!);
}

const _loDelDelegado = {
  'ACOSTA, BRISA': ('Marta Acosta / Hugo Ríos', 'Viva la vida'),
  'BENITEZ, JOAQUIN': ('Raúl Benítez', 'Thunderstruck'),
  'DUARTE, TOBIAS': ('Silvia / Omar / Tía Nora', 'Titanium'),
  'ESCOBAR, CAMILA': ('Paola Escobar', 'Tusa'),
  'FERNANDEZ, IVAN': ('', 'Persiana americana'),
  'GIMENEZ, LUCIA': ('GIMENEZ, ROSA', ''),
  'HERRERA, MATEO': ('Carla Herrera y Diego Herrera', 'De música ligera'),
  'JARA, THIAGO': ('Nélida Jara', ''),
  'LEDESMA, ABRIL': ('Mónica Ledesma / José Ledesma', 'Flowers'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final carpeta = _salida.isNotEmpty
      ? _salida
      : Directory.systemTemp.createTempSync('planilla_delegado').path;

  Future<void> sacar(
    WidgetTester tester, {
    required String archivo,
    required List<ContratoAlumno> alumnos,
    Uint8List? excelElegido,
    bool importar = false,
  }) async {
    await cargarFuentesPlano();
    final iconos = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconos.load();

    const tam = Size(1366, 768);
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
              backgroundColor: const Color(0xFFF4F2EE),
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => AcompanantesMusicaDialog(
                    eventoId: _evento,
                    institucion: _escuela,
                    alumnos: alumnos,
                    onGuardarArchivo: (_, _) async => true,
                    onElegirArchivo: () async => excelElegido,
                    onImportar: (_) async => null,
                  ),
                ),
                child: const Text(' '),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    if (excelElegido != null) {
      await tester.tap(find.byKey(const Key('delegado_importar')));
      await tester.pumpAndSettle();
    }
    if (importar) {
      await tester.tap(find.byKey(const Key('delegado_confirmar')));
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

  test('el Excel de muestra, como lo recibe el delegado', () {
    final planilla = exportarPlanillaDelegado(
      eventoId: _evento,
      institucion: _escuela,
      alumnos: _alumnos(),
    );
    expect(planilla.cerrada, isTrue);
    final f = File(
      '$carpeta${Platform.pathSeparator}'
      '${nombreArchivoPlanillaDelegado(_escuela)}',
    )..writeAsBytesSync(planilla.bytes);
    print('── Excel en: ${f.path}');
  });

  testWidgets('la ventana al abrir', (tester) async {
    await sacar(tester, archivo: 'Delegado_1_ventana.png', alumnos: _alumnos());
  });

  testWidgets('antes de guardar', (tester) async {
    final alumnos = _alumnos();
    await sacar(
      tester,
      archivo: 'Delegado_2_antes_de_guardar.png',
      alumnos: alumnos,
      excelElegido: _completado(alumnos, _loDelDelegado),
    );
  });

  testWidgets('cuando un alumno ya tenía algo cargado', (tester) async {
    final alumnos = _alumnos(conAlgoCargado: true);
    await sacar(
      tester,
      archivo: 'Delegado_3_cambia_lo_que_tenian.png',
      alumnos: alumnos,
      excelElegido: _completado(alumnos, {
        'BENITEZ, JOAQUIN': ('Raúl Benítez / Estela Ojeda', 'Thunderstruck'),
        'ESCOBAR, CAMILA': ('Paola Escobar', 'Provenza'),
        'JARA, THIAGO': ('Nélida Jara', ''),
      }),
    );
  });

  testWidgets('el Excel de otra institución', (tester) async {
    await sacar(
      tester,
      archivo: 'Delegado_4_otra_institucion.png',
      alumnos: _alumnos(),
      excelElegido: _completado(
        _alumnos(),
        _loDelDelegado,
        evento: _otra,
        institucion: 'COLEGIO DE AL LADO',
      ),
    );
  });

  testWidgets('después de importar', (tester) async {
    final alumnos = _alumnos();
    await sacar(
      tester,
      archivo: 'Delegado_5_importado.png',
      alumnos: alumnos,
      excelElegido: _completado(alumnos, _loDelDelegado),
      importar: true,
    );
  });
}
