// Personalizar → Medidas: los lados del playón con cinta y el lugar de cada
// mesa. No guarda por su cuenta: avisa lo que se prueba y lo que se guarda.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/widgets/personalizar/panel_medidas.dart';

Future<({List<MedidasPlano> guardadas, List<MedidasPlano?> probadas})> _mostrar(
  WidgetTester tester, {
  MedidasPlano medidas = const MedidasPlano(),
  int mesasNecesarias = 132,
  bool ocupado = false,
  String? aviso,
  VoidCallback? onAccionAviso,
  List<bool>? malEscrito,
}) async {
  final guardadas = <MedidasPlano>[];
  final probadas = <MedidasPlano?>[];
  // Alto de sobra: la lista arma solo lo que se ve, y acá se mira todo.
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
            child: PanelMedidas(
              medidas: medidas,
              mesasNecesarias: mesasNecesarias,
              ocupado: ocupado,
              onGuardar: guardadas.add,
              onProbar: probadas.add,
              onMalEscrito: malEscrito?.add,
              aviso: aviso,
              textoAccionAviso: 'ARMAR DE NUEVO',
              onAccionAviso: onAccionAviso,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  return (guardadas: guardadas, probadas: probadas);
}

String _campo(WidgetTester tester, String clave) =>
    tester.widget<TextField>(find.byKey(Key(clave))).controller!.text;

Future<void> _escribir(WidgetTester tester, String clave, String texto) async {
  await tester.enterText(find.byKey(Key(clave)), texto);
  await tester.pump();
}

String _resultado(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byKey(const Key('medidas_resultado')),
      matching: find.byType(Text),
    ))
    .map((t) => t.data ?? '')
    .join(' | ');

bool _sePuedeGuardar(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('guardar_medidas')))
        .onPressed !=
    null;

void main() {
  test('los números se escriben con coma y se leen con coma o con punto', () {
    expect(PanelMedidas.numero(30), '30');
    expect(PanelMedidas.numero(2.5), '2,5');
    expect(PanelMedidas.numero(0.15), '0,15');
    expect(PanelMedidas.numero(39.812), '39,81');
    expect(PanelMedidas.leer('39,8'), 39.8);
    expect(PanelMedidas.leer(' 39.8 '), 39.8);
    expect(PanelMedidas.leer('treinta'), isNull);
    expect(PanelMedidas.leer(''), isNull);
  });

  testWidgets('abre con lo guardado, sin nada para guardar', (tester) async {
    final r = await _mostrar(tester);
    expect(_campo(tester, 'medida_frente'), '30');
    expect(_campo(tester, 'medida_fondo'), '46');
    // El costado inclinado de un playón de 30 / 46 / 39.
    expect(_campo(tester, 'medida_costado'), '39,81');
    expect(_campo(tester, 'medida_lugar'), '2');
    expect(_campo(tester, 'medida_extra'), '0,15');
    expect(_resultado(tester), contains('entran hasta 284 mesas'));
    expect(_resultado(tester), contains('1482 m²'));
    expect(find.byKey(const Key('medidas_aproximadas')), findsOneWidget);
    expect(_sePuedeGuardar(tester), isFalse);
    expect(find.text('MEDIDAS GUARDADAS'), findsOneWidget);
    // Son las de fábrica: no hay a qué volver ni qué descartar.
    expect(find.byKey(const Key('medidas_de_fabrica')), findsNothing);
    expect(find.byKey(const Key('descartar_medidas')), findsNothing);
    expect(r.probadas, isEmpty);
  });

  testWidgets('cambiar la distancia entre mesas cambia cuántas entran, y el '
      'playón queda como estaba', (tester) async {
    final r = await _mostrar(tester);
    await _escribir(tester, 'medida_lugar', '2,5');
    expect(_resultado(tester), contains('entran hasta 180 mesas'));
    expect(r.probadas.last!.lugarMesaM, 2.5);
    // El playón no se tocó: es el mismo, y sigue marcado como aproximado.
    expect(r.probadas.last!.playon, PlayonReal.costaSurubi);
    expect(find.byKey(const Key('medidas_aproximadas')), findsOneWidget);
    expect(_sePuedeGuardar(tester), isTrue);

    await tester.tap(find.byKey(const Key('guardar_medidas')));
    expect(r.guardadas.single.lugarMesaM, 2.5);
    expect(r.guardadas.single.playon, PlayonReal.costaSurubi);
  });

  testWidgets('pasar por un casillero del playón sin cambiar la medida no lo '
      'corrige: "30,0" es el mismo 30, y sigue siendo aproximado',
      (tester) async {
    final r = await _mostrar(tester);
    await _escribir(tester, 'medida_frente', '30,0');
    await _escribir(tester, 'medida_fondo', ' 46 ');
    await _escribir(tester, 'medida_costado', '39.81');
    await _escribir(tester, 'medida_lugar', '2,5');
    expect(r.probadas.last!.playon, PlayonReal.costaSurubi);
    expect(r.probadas.last!.playon.aproximado, isTrue);
    expect(find.byKey(const Key('medidas_aproximadas')), findsOneWidget);
    await tester.tap(find.byKey(const Key('guardar_medidas')));
    expect(r.guardadas.single.playon, PlayonReal.costaSurubi);
  });

  testWidgets('con la cinta: el playón sale del frente, el fondo y un costado, '
      'y deja de ser aproximado', (tester) async {
    final r = await _mostrar(tester);
    await _escribir(tester, 'medida_frente', '32');
    await _escribir(tester, 'medida_fondo', '44');
    await _escribir(tester, 'medida_costado', '40,5');
    final playon = r.probadas.last!.playon;
    expect(playon.frenteM, 32);
    expect(playon.fondoM, 44);
    expect(playon.costadoM, closeTo(40.5, 1e-9));
    expect(playon.aproximado, isFalse);
    expect(find.byKey(const Key('medidas_aproximadas')), findsNothing);

    await tester.tap(find.byKey(const Key('guardar_medidas')));
    expect(r.guardadas.single.playon, playon);
    // Lo guardado se puede leer de vuelta igual (nada queda fuera de rango).
    expect(MedidasPlano.fromMap(r.guardadas.single.toMap()), r.guardadas.single);
  });

  testWidgets('un costado que no cierra el playón se dice y no se guarda',
      (tester) async {
    final r = await _mostrar(tester);
    await _escribir(tester, 'medida_costado', '7');
    expect(_resultado(tester), contains('no cierra'));
    expect(_sePuedeGuardar(tester), isFalse);
    // Lo que no sirve no se le pasa al plano.
    expect(r.probadas.last, isNull);
  });

  testWidgets('lo que no es un número, o está fuera de rango, no se guarda',
      (tester) async {
    await _mostrar(tester);
    await _escribir(tester, 'medida_lugar', 'dos');
    expect(_resultado(tester),
        contains('"De centro a centro" va de 1,5 m a 5 m'));
    expect(_sePuedeGuardar(tester), isFalse);
    await _escribir(tester, 'medida_lugar', '1');
    expect(_sePuedeGuardar(tester), isFalse);
    await _escribir(tester, 'medida_lugar', '2');

    await _escribir(tester, 'medida_extra', '3');
    expect(_resultado(tester), contains('"Más, por cada silla extra" va de 0 a 1 m'));
    await _escribir(tester, 'medida_extra', '0,15');

    await _escribir(tester, 'medida_frente', '2');
    expect(_resultado(tester), contains('Cada lado del playón va de 5 m a'));
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('si la fiesta no entra con esas medidas, lo dice',
      (tester) async {
    await _mostrar(tester, mesasNecesarias: 200);
    expect(_resultado(tester), isNot(contains('no entran')));
    await _escribir(tester, 'medida_lugar', '2,5');
    expect(_resultado(tester), contains('La fiesta necesita 200: no entran.'));
    // Igual se puede guardar: es un aviso, no un freno.
    expect(_sePuedeGuardar(tester), isTrue);
  });

  testWidgets('DESCARTAR vuelve a lo guardado', (tester) async {
    final r = await _mostrar(tester);
    await _escribir(tester, 'medida_lugar', '2,5');
    await tester.tap(find.byKey(const Key('descartar_medidas')));
    await tester.pump();
    expect(_campo(tester, 'medida_lugar'), '2');
    expect(r.probadas.last, isNull);
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('con medidas propias se puede volver a las de fábrica',
      (tester) async {
    const propias = MedidasPlano(
      lugarMesaM: 2.2,
      playon: PlayonReal(frenteM: 32, fondoM: 44, profundidadM: 40),
    );
    final r = await _mostrar(tester, medidas: propias);
    expect(_campo(tester, 'medida_lugar'), '2,2');
    expect(find.byKey(const Key('medidas_aproximadas')), findsNothing);

    await tester.tap(find.byKey(const Key('medidas_de_fabrica')));
    await tester.pump();
    expect(_campo(tester, 'medida_frente'), '30');
    expect(_campo(tester, 'medida_lugar'), '2');
    expect(r.probadas.last, const MedidasPlano());
    // Todavía no se guardó: hay que tocar GUARDAR.
    expect(r.guardadas, isEmpty);
    await tester.tap(find.byKey(const Key('guardar_medidas')));
    expect(r.guardadas.single, const MedidasPlano());
  });

  testWidgets('cuando lo guardado cambia, los casilleros lo muestran',
      (tester) async {
    await _mostrar(tester);
    await _escribir(tester, 'medida_lugar', '2,5');
    await _mostrar(tester, medidas: const MedidasPlano(lugarMesaM: 2.5));
    expect(_campo(tester, 'medida_lugar'), '2,5');
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('mientras se guarda no se toca nada', (tester) async {
    await _mostrar(tester, ocupado: true);
    expect(
      tester.widget<TextField>(find.byKey(const Key('medida_frente'))).enabled,
      isFalse,
    );
    expect(_sePuedeGuardar(tester), isFalse);
  });

  testWidgets('el aviso lleva a su botón, y se esconde mientras hay cambios '
      'sin guardar', (tester) async {
    var tocado = 0;
    await _mostrar(
      tester,
      aviso: 'El salón está armado a 2 m entre mesas.',
      onAccionAviso: () => tocado++,
    );
    expect(find.byKey(const Key('aviso_medidas')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('accion_aviso_medidas')));
    await tester.tap(find.byKey(const Key('accion_aviso_medidas')));
    expect(tocado, 1);

    await _escribir(tester, 'medida_lugar', '2,5');
    expect(find.byKey(const Key('aviso_medidas')), findsNothing);
  });
}
