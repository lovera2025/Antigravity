// Personalizar → Colores y textos: el panel. No guarda por su cuenta: avisa
// lo que se prueba y lo que se guarda.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/services/colores_y_textos.dart';
import 'package:arguello_events/features/plano/widgets/personalizar/panel_colores_textos.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _sectores = [
  SectorPlano(
    tipo: TipoSector.escenario,
    texto: 'Escenario',
    hoja: 'A',
    caja: RectPlano(100, 0, 400, 50),
  ),
  SectorPlano(
    tipo: TipoSector.barra,
    texto: 'Barra',
    hoja: 'A',
    caja: RectPlano(0, 300, 60, 200),
    vertical: true,
  ),
];

const List<DivisionParaColor> _divisiones = [
  (clave: '5A', nombre: '5° A', lugar: 0),
  (clave: '5B', nombre: '5° B', lugar: 1),
  (clave: '6A', nombre: '6° A', lugar: null),
];

Future<({List<ColoresYTextos> guardados, List<ColoresYTextos?> probados})>
    _mostrar(
  WidgetTester tester, {
  ConfigPlano config = ConfigPlano.vacia,
  List<SectorPlano> sectores = _sectores,
  List<DivisionParaColor> divisiones = _divisiones,
  bool ocupado = false,
  bool variasHojas = false,
}) async {
  final guardados = <ColoresYTextos>[];
  final probados = <ColoresYTextos?>[];
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 1000,
            child: PanelColoresTextos(
              estilo: EstiloPlano.arquitecto,
              divisiones: divisiones,
              config: config,
              sectores: sectores,
              variasHojas: variasHojas,
              ocupado: ocupado,
              onGuardar: guardados.add,
              onProbar: probados.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return (guardados: guardados, probados: probados);
}

bool _sePuedeGuardar(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('guardar_colores')))
        .onPressed !=
    null;

/// El ancho del borde del color [j] de la división: 3 si es el elegido.
double _borde(WidgetTester tester, String clave, int j) {
  final caja = tester.widget<Container>(find.descendant(
    of: find.byKey(Key('color_${clave}_$j')),
    matching: find.byType(Container),
  ));
  return ((caja.decoration! as BoxDecoration).border! as Border).top.width;
}

String _campo(WidgetTester tester, String clave) =>
    tester.widget<TextField>(find.byKey(Key(clave))).controller!.text;

void main() {
  testWidgets('abre con lo guardado: cada división en el color de su lugar',
      (tester) async {
    final r = await _mostrar(tester);
    expect(find.text('5° A'), findsOneWidget);
    expect(find.text('6° A'), findsOneWidget);
    expect(_borde(tester, '5A', 0), 3);
    expect(_borde(tester, '5A', 1), 1);
    expect(_borde(tester, '5B', 1), 3);
    // La que todavía no tiene familias con mesa no tiene color marcado.
    for (var j = 0; j < 8; j++) {
      expect(_borde(tester, '6A', j), 1);
    }
    expect(_campo(tester, 'texto_titulo'), '');
    expect(_campo(tester, 'texto_sector_0'), 'Escenario');
    expect(_campo(tester, 'texto_sector_1'), 'Barra');
    expect(_sePuedeGuardar(tester), isFalse);
    expect(find.text('GUARDADO'), findsOneWidget);
    expect(find.byKey(const Key('descartar_colores')), findsNothing);
    expect(r.probados, isEmpty);
  });

  testWidgets('elegir un color se prueba enseguida y se guarda con GUARDAR',
      (tester) async {
    final r = await _mostrar(tester);
    await tester.tap(find.byKey(const Key('color_5A_4')));
    await tester.pump();
    expect(_borde(tester, '5A', 4), 3);
    expect(_borde(tester, '5A', 0), 1);
    expect(r.probados.last!.colores, {'5A': 4});
    expect(_sePuedeGuardar(tester), isTrue);
    expect(r.guardados, isEmpty);

    await tester.tap(find.byKey(const Key('guardar_colores')));
    expect(r.guardados.single.colores, {'5A': 4});
    expect(r.guardados.single.sectores, isEmpty);
  });

  testWidgets('volver al color de su lugar es no haber cambiado nada',
      (tester) async {
    final r = await _mostrar(tester);
    await tester.tap(find.byKey(const Key('color_5A_4')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color_5A_0')));
    await tester.pump();
    expect(r.probados.last, isNull);
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('dos divisiones con el mismo color: se puede, y lo dice',
      (tester) async {
    await _mostrar(tester);
    expect(find.byKey(const Key('repetido_5A')), findsNothing);
    await tester.tap(find.byKey(const Key('color_5A_1')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('repetido_5A'))).data,
      'Mismo color que 5° B.',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('repetido_5B'))).data,
      'Mismo color que 5° A.',
    );
    expect(_sePuedeGuardar(tester), isTrue);
  });

  testWidgets('una división sin lugar en la leyenda también elige color',
      (tester) async {
    final r = await _mostrar(tester);
    await tester.tap(find.byKey(const Key('color_6A_5')));
    await tester.pump();
    expect(_borde(tester, '6A', 5), 3);
    expect(r.probados.last!.colores, {'6A': 5});
  });

  testWidgets('el título, el subtítulo y el texto de un sector', (tester) async {
    final r = await _mostrar(tester);
    await tester.enterText(
        find.byKey(const Key('texto_titulo')), ' Egresados 2026 ');
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('texto_subtitulo')), 'Costa Surubí');
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('texto_sector_1')), 'Barra de tragos');
    await tester.pump();
    final probado = r.probados.last!;
    expect(probado.titulo, 'Egresados 2026');
    expect(probado.subtitulo, 'Costa Surubí');
    // Solo el sector que cambió, como estaba, con su texto nuevo.
    expect(probado.sectores.length, 1);
    expect(identical(probado.sectores.single.sector, _sectores[1]), isTrue);
    expect(probado.sectores.single.texto, 'Barra de tragos');

    await tester.tap(find.byKey(const Key('guardar_colores')));
    expect(r.guardados.single.titulo, 'Egresados 2026');
  });

  testWidgets('DESCARTAR vuelve a lo guardado', (tester) async {
    const config = ConfigPlano(colores: {'5A': 3}, titulo: 'Egresados');
    final r = await _mostrar(tester, config: config);
    expect(_borde(tester, '5A', 3), 3);
    expect(_campo(tester, 'texto_titulo'), 'Egresados');

    await tester.tap(find.byKey(const Key('color_5A_6')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('texto_titulo')), 'Otra');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('texto_sector_0')), 'Tablado');
    await tester.pump();
    expect(_sePuedeGuardar(tester), isTrue);

    await tester.tap(find.byKey(const Key('descartar_colores')));
    await tester.pump();
    expect(_borde(tester, '5A', 3), 3);
    expect(_campo(tester, 'texto_titulo'), 'Egresados');
    expect(_campo(tester, 'texto_sector_0'), 'Escenario');
    expect(r.probados.last, isNull);
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('cuando lo guardado cambia, el panel lo muestra', (tester) async {
    await _mostrar(tester);
    await tester.tap(find.byKey(const Key('color_5A_4')));
    await tester.pump();
    await _mostrar(
      tester,
      config: const ConfigPlano(colores: {'5A': 4}, titulo: 'Egresados'),
    );
    expect(_borde(tester, '5A', 4), 3);
    expect(_campo(tester, 'texto_titulo'), 'Egresados');
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('con varias hojas, cada sector dice en cuál está',
      (tester) async {
    await _mostrar(tester, variasHojas: true);
    expect(find.text('Escenario · hoja A'), findsOneWidget);
    expect(find.text('Barra · hoja A'), findsOneWidget);
  });

  testWidgets('sin divisiones ni sectores no rompe', (tester) async {
    await _mostrar(tester, divisiones: const [], sectores: const []);
    expect(
      find.text('Todavía no hay divisiones cargadas en los alumnos.'),
      findsOneWidget,
    );
    expect(find.text('TEXTOS DE LOS SECTORES'), findsNothing);
  });

  testWidgets('mientras se guarda no se toca nada', (tester) async {
    final r = await _mostrar(tester, ocupado: true);
    await tester.tap(find.byKey(const Key('color_5A_4')));
    await tester.pump();
    expect(r.probados, isEmpty);
    expect(
      tester.widget<TextField>(find.byKey(const Key('texto_titulo'))).enabled,
      isFalse,
    );
  });
}
