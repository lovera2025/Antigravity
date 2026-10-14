// La ventana de PLANILLAS → "Acompañantes y música": exportar el Excel del
// delegado e importarlo de vuelta. Importar empieza siempre como simulacro: no
// se guarda nada hasta apretar IMPORTAR.
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/planilla_delegado.dart';
import 'package:arguello_events/features/eventos/widgets/acompanantes_musica_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

const _normal = 'e0000000-0000-4000-8000-000000000001';
const _nacional = 'e0000000-0000-4000-8000-000000000002';

ContratoAlumno _alumno(
  String principio,
  String nombre, {
  List<String> acomp = const [],
  String? musica,
}) =>
    ContratoAlumno(
      id: '${principio.padRight(8, '0')}-0000-4000-8000-000000000000',
      eventoId: _normal,
      nombreAlumno: nombre,
      cantidadAcompanantes: acomp.length,
      nombresAcompanantes: acomp,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: '6° A',
      musicaElegida: musica,
    );

List<ContratoAlumno> _escuela() => [
      _alumno('a1', 'ACOSTA, BRISA'),
      _alumno('b2', 'BENITEZ, JOAQUIN'),
      _alumno('d4', 'DUARTE, TOBIAS'),
      _alumno('e5', '[BAJA] ESPINOLA, LUZ'),
    ];

/// El Excel de [alumnos], con lo que escribió el delegado: nombre del alumno →
/// (acompañantes, música).
Uint8List _excel(
  List<ContratoAlumno> alumnos,
  Map<String, (String, String)> escrito, {
  String evento = _normal,
  String institucion = 'NORMAL MARIANO ILOZA',
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

/// Lo que le pasa a la ventana en un test.
class _Mundo {
  /// Lo que devuelve "elegir archivo". Null: se canceló.
  Uint8List? archivo;
  bool guardaElArchivo = true;
  bool fallaAlImportar = false;
  String? algoMas;

  final exportados = <({Uint8List bytes, String nombre})>[];
  final importados = <List<CambioDelegado>>[];
  final cerroCon = <bool?>[];
}

Future<_Mundo> _abrir(
  WidgetTester tester, {
  List<ContratoAlumno>? alumnos,
}) async {
  final mundo = _Mundo();
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => mundo.cerroCon.add(
              await showDialog<bool>(
                context: context,
                builder: (_) => AcompanantesMusicaDialog(
                  eventoId: _normal,
                  institucion: 'NORMAL MARIANO ILOZA',
                  alumnos: alumnos ?? _escuela(),
                  onGuardarArchivo: (bytes, nombre) async {
                    if (!mundo.guardaElArchivo) return false;
                    mundo.exportados.add((bytes: bytes, nombre: nombre));
                    return true;
                  },
                  onElegirArchivo: () async => mundo.archivo,
                  onImportar: (cambios) async {
                    if (mundo.fallaAlImportar) throw StateError('sin base');
                    mundo.importados.add(cambios);
                    return mundo.algoMas;
                  },
                ),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return mundo;
}

Future<void> _tocar(WidgetTester tester, String clave) async {
  await tester.tap(find.byKey(Key(clave)));
  await tester.pumpAndSettle();
}

bool _prendido(WidgetTester tester, String clave) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed != null;

String _dicho(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('delegado_dicho')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  test('el nombre del archivo lleva la institución, sin letras prohibidas', () {
    expect(
      nombreArchivoPlanillaDelegado('NORMAL MARIANO ILOZA'),
      'Acompañantes y música - NORMAL MARIANO ILOZA.xlsx',
    );
    expect(
      nombreArchivoPlanillaDelegado('E.P.E.T. N° 1 "Juan B." / Turno: tarde'),
      'Acompañantes y música - E.P.E.T. N° 1 Juan B. Turno tarde.xlsx',
    );
    expect(
      nombreArchivoPlanillaDelegado('  '),
      'Acompañantes y música - institución.xlsx',
    );
  });

  group('al abrir', () {
    testWidgets('dice de qué institución es y cuántos ya tienen algo cargado',
        (tester) async {
      await _abrir(
        tester,
        alumnos: [
          _alumno('a1', 'ACOSTA, BRISA', acomp: ['Marta Acosta'], musica: 'X'),
          _alumno('b2', 'BENITEZ, JOAQUIN', musica: 'Y'),
          _alumno('d4', 'DUARTE, TOBIAS'),
          // La baja no cuenta: no va en la planilla.
          _alumno('e5', '[BAJA] ESPINOLA, LUZ', acomp: ['Uno'], musica: 'Z'),
        ],
      );
      expect(find.text('Acompañantes y música'), findsOneWidget);
      expect(find.text('NORMAL MARIANO ILOZA · 3 alumno(s)'), findsOneWidget);
      // Con acompañantes: 1. Con música: 2.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('EXPORTAR EXCEL'), findsOneWidget);
      expect(find.text('IMPORTAR EXCEL'), findsOneWidget);
    });

    testWidgets('CERRAR sin haber importado avisa que no cambió nada',
        (tester) async {
      final mundo = await _abrir(tester);
      await _tocar(tester, 'delegado_cerrar');
      expect(mundo.cerroCon, [false]);
    });
  });

  group('exportar', () {
    testWidgets('guarda el Excel de la institución, con los activos',
        (tester) async {
      final mundo = await _abrir(tester);
      await _tocar(tester, 'delegado_exportar');

      final exportado = mundo.exportados.single;
      expect(
        exportado.nombre,
        'Acompañantes y música - NORMAL MARIANO ILOZA.xlsx',
      );
      final leido = PlanillaDelegado.leer(exportado.bytes);
      expect(leido.eventoId, _normal);
      expect(leido.renglones.map((r) => r.alumno), [
        'ACOSTA, BRISA',
        'BENITEZ, JOAQUIN',
        'DUARTE, TOBIAS',
      ]);
      expect(_dicho(tester), startsWith('Excel guardado, con 3 alumno(s).'));
      // Salió cerrado: no hace falta la advertencia.
      expect(_dicho(tester), isNot(contains('sin cerrar')));
    });

    testWidgets('si se cancela el "guardar como", no dice que guardó',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.guardaElArchivo = false;
      await _tocar(tester, 'delegado_exportar');
      expect(mundo.exportados, isEmpty);
      expect(find.byKey(const Key('delegado_dicho')), findsNothing);
    });
  });

  group('importar', () {
    testWidgets('elegir el archivo no guarda nada: muestra "Antes de guardar"',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = _excel(_escuela(), {
        'ACOSTA, BRISA': ('Marta Acosta / Hugo Ríos', 'Viva la vida'),
        'DUARTE, TOBIAS': ('Silvia / Omar / Tía Nora', 'Titanium'),
      });
      await _tocar(tester, 'delegado_importar');

      expect(mundo.importados, isEmpty);
      expect(find.text('Antes de guardar'), findsOneWidget);
      expect(
        find.text('ACOSTA, BRISA · Marta Acosta · Hugo Ríos · Música: Viva la vida'),
        findsOneWidget,
      );
      expect(
        find.text(
          'DUARTE, TOBIAS: trae 3 acompañantes y el máximo es 2. No se carga.',
        ),
        findsOneWidget,
      );
      expect(find.text('IMPORTAR 1 ALUMNO(S)'), findsOneWidget);
      expect(_prendido(tester, 'delegado_confirmar'), isTrue);
    });

    testWidgets('VOLVER no guarda nada', (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = _excel(_escuela(), {
        'ACOSTA, BRISA': ('Marta Acosta', ''),
      });
      await _tocar(tester, 'delegado_importar');
      await _tocar(tester, 'delegado_volver');

      expect(mundo.importados, isEmpty);
      expect(find.text('Acompañantes y música'), findsOneWidget);
      await _tocar(tester, 'delegado_cerrar');
      expect(mundo.cerroCon, [false]);
    });

    testWidgets('IMPORTAR guarda solo acompañantes y música, y lo dice',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = _excel(_escuela(), {
        'ACOSTA, BRISA': ('Marta Acosta / Hugo Ríos', 'Viva la vida'),
        'BENITEZ, JOAQUIN': ('', 'Thunderstruck'),
      });
      await _tocar(tester, 'delegado_importar');
      await _tocar(tester, 'delegado_confirmar');

      final cambios = mundo.importados.single;
      expect(
        {for (final c in cambios) c.alumno.nombreAlumno: c.datos},
        {
          'ACOSTA, BRISA': {
            'nombres_acompanantes': ['Marta Acosta', 'Hugo Ríos'],
            'cantidad_acompanantes': 2,
            'musica_elegida': 'Viva la vida',
          },
          'BENITEZ, JOAQUIN': {'musica_elegida': 'Thunderstruck'},
        },
      );
      // Vuelve a la primera pantalla, con los números al día.
      expect(find.text('Acompañantes y música'), findsOneWidget);
      expect(
        _dicho(tester),
        'Se cargaron 2 alumno(s). Suben a la nube y llegan a las otras PCs.',
      );
      expect(find.text('1'), findsOneWidget); // con acompañantes
      expect(find.text('2'), findsOneWidget); // con música

      await _tocar(tester, 'delegado_cerrar');
      expect(mundo.cerroCon, [true]);
    });

    testWidgets('si hay algo más para decir (la puerta), lo suma',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.algoMas = 'Recepción y el tótem ya tienen la lista: 5 persona(s).';
      mundo.archivo = _excel(_escuela(), {
        'ACOSTA, BRISA': ('Marta Acosta', ''),
      });
      await _tocar(tester, 'delegado_importar');
      await _tocar(tester, 'delegado_confirmar');
      expect(
        _dicho(tester),
        'Se cargaron 1 alumno(s). Suben a la nube y llegan a las otras PCs. '
        'Recepción y el tótem ya tienen la lista: 5 persona(s).',
      );
    });

    testWidgets('si no se pudo guardar lo dice, y no cuenta como importado',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.fallaAlImportar = true;
      mundo.archivo = _excel(_escuela(), {
        'ACOSTA, BRISA': ('Marta Acosta', ''),
      });
      await _tocar(tester, 'delegado_importar');
      await _tocar(tester, 'delegado_confirmar');

      expect(_dicho(tester), startsWith('No se guardó nada.'));
      // Sin el error crudo.
      expect(_dicho(tester), isNot(contains('StateError')));
      // Sigue en "Antes de guardar", para poder probar de nuevo.
      expect(find.text('Antes de guardar'), findsOneWidget);
      await _tocar(tester, 'delegado_volver');
      await _tocar(tester, 'delegado_cerrar');
      expect(mundo.cerroCon, [false]);
    });

    testWidgets('el Excel de otra institución no entra: no hay qué importar',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = _excel(
        [_alumno('f6', 'FERNANDEZ, IVAN')],
        {'FERNANDEZ, IVAN': ('Rita Fernández', '')},
        evento: _nacional,
        institucion: 'COLEGIO NACIONAL',
      );
      await _tocar(tester, 'delegado_importar');

      expect(
        find.text(
          'Este Excel es de COLEGIO NACIONAL y estás en NORMAL MARIANO ILOZA. '
          'No se importó nada.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('delegado_confirmar')), findsNothing);
      expect(mundo.importados, isEmpty);
    });

    testWidgets('un Excel sin nada nuevo no deja importar', (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = _excel(_escuela(), const {});
      await _tocar(tester, 'delegado_importar');
      expect(find.text('NADA PARA IMPORTAR'), findsOneWidget);
      expect(_prendido(tester, 'delegado_confirmar'), isFalse);
      expect(
        find.text('El Excel no trae nada nuevo para cargar.'),
        findsOneWidget,
      );
    });

    testWidgets('si se cancela el "elegir archivo", queda como estaba',
        (tester) async {
      final mundo = await _abrir(tester);
      mundo.archivo = null;
      await _tocar(tester, 'delegado_importar');
      expect(find.text('Acompañantes y música'), findsOneWidget);
      expect(find.text('Antes de guardar'), findsNothing);
    });
  });

  // "Vale el Excel, mostrando antes lo que cambia" (el usuario, 13-oct-2026).
  group('cuando el alumno ya tenía algo cargado', () {
    final yaCargada = [
      _alumno('a1', 'ACOSTA, BRISA', acomp: ['Marta Acosta'], musica: 'X'),
      _alumno('b2', 'BENITEZ, JOAQUIN'),
    ];

    testWidgets('muestra antes → después y pide la tilde para importar',
        (tester) async {
      final mundo = await _abrir(tester, alumnos: yaCargada);
      mundo.archivo = _excel(yaCargada, {
        'ACOSTA, BRISA': ('Hugo Ríos', 'X'),
        'BENITEZ, JOAQUIN': ('Raúl Benítez', ''),
      });
      await _tocar(tester, 'delegado_importar');

      expect(find.text('Cambia lo que ya tenían'), findsOneWidget);
      expect(
        find.text('ACOSTA, BRISA: Marta Acosta → Hugo Ríos'),
        findsOneWidget,
      );
      expect(_prendido(tester, 'delegado_confirmar'), isFalse);

      await _tocar(tester, 'delegado_entendido');
      expect(_prendido(tester, 'delegado_confirmar'), isTrue);
      await _tocar(tester, 'delegado_confirmar');
      expect(mundo.importados.single, hasLength(2));
    });

    testWidgets('si solo se completa lo vacío, no pide la tilde',
        (tester) async {
      final mundo = await _abrir(tester, alumnos: yaCargada);
      mundo.archivo = _excel(yaCargada, {
        'BENITEZ, JOAQUIN': ('Raúl Benítez', 'Thunderstruck'),
      });
      await _tocar(tester, 'delegado_importar');
      expect(find.byKey(const Key('delegado_entendido')), findsNothing);
      expect(_prendido(tester, 'delegado_confirmar'), isTrue);
    });
  });

  testWidgets('un casillero con coma se avisa antes de importar',
      (tester) async {
    final mundo = await _abrir(tester);
    mundo.archivo = _excel(_escuela(), {
      'ACOSTA, BRISA': ('ACOSTA, MARTA', ''),
    });
    await _tocar(tester, 'delegado_importar');
    expect(
      find.text('ACOSTA, BRISA · ACOSTA, MARTA  (con coma: una sola persona)'),
      findsOneWidget,
    );
    expect(find.textContaining('1 casillero(s) traen una coma'), findsOneWidget);
  });

  testWidgets('con una escuela entera no desborda en una notebook',
      (tester) async {
    final muchos = [
      for (var i = 0; i < 130; i++)
        _alumno(
          i.toRadixString(16).padLeft(4, '0'),
          'ALUMNO NÚMERO ${i.toString().padLeft(3, '0')}, CON NOMBRE LARGO',
        ),
    ];
    final mundo = await _abrir(tester, alumnos: muchos);
    mundo.archivo = _excel(muchos, {
      for (final a in muchos)
        a.nombreAlumno: ('Acompañante Uno Largo / Acompañante Dos Largo', 'Tema'),
    });
    await _tocar(tester, 'delegado_importar');
    expect(tester.takeException(), isNull);
    expect(find.text('IMPORTAR 130 ALUMNO(S)'), findsOneWidget);
  });
}
