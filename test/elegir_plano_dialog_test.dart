// "Estilo y armado": los tres pasos del plano de una fiesta, con todo ya
// elegido.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/widgets/elegir_plano_dialog.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// Lo que devolvió el diálogo: [cerrado] distingue "todavía abierto" de
/// "se canceló".
class _Resultado {
  EleccionPlano? eleccion;
  bool cerrado = false;
}

Future<_Resultado> _abrir(
  WidgetTester tester, {
  int necesarias = 132,
  PlanoEvento? actual,
  String? trabado,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final r = _Resultado();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                r.eleccion = await mostrarElegirPlano(
                  context: context,
                  mesasNecesarias: necesarias,
                  medidas: const MedidasPlano(),
                  actual: actual,
                  armadoTrabado: trabado,
                );
                r.cerrado = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return r;
}

Future<void> _tocar(WidgetTester tester, String clave) async {
  final donde = find.byKey(Key(clave));
  await tester.ensureVisible(donde);
  await tester.pumpAndSettle();
  await tester.tap(donde);
  await tester.pumpAndSettle();
}

String _textoDe(WidgetTester tester, String clave) =>
    tester.widget<Text>(find.byKey(Key(clave))).data!;

/// Los textos de la tarjeta de un armado.
List<String> _tarjeta(WidgetTester tester, String claveArmado) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(Key('armado_$claveArmado')),
          matching: find.byType(Text),
        ),
      ))
        t.data ?? '',
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(cargarFuentesPlano);

  final ahora = DateTime.utc(2026, 10, 1);
  PlanoEvento planoCon({
    EstiloPlano estilo = EstiloPlano.neon,
    ModoSorteo modo = ModoSorteo.entera,
  }) =>
      PlanoEvento.nuevo(
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        armado: ArmadosPredefinidos.normal2a2b(),
        estilo: estilo,
        modo: modo,
        ahora: ahora,
      );

  group('la primera vez', () {
    testWidgets('sin tocar nada, LISTO deja lo recomendado', (tester) async {
      final r = await _abrir(tester);
      expect(find.textContaining('La fiesta necesita 132 mesas'), findsOneWidget);
      await _tocar(tester, 'listo');
      expect(r.cerrado, isTrue);
      final e = r.eleccion!;
      // A medida del playón, con las mesas justas de la fiesta.
      expect(e.armado.clave, ArmarAMedida.claveArmado);
      expect(e.armado.mesas.length, 132);
      expect(e.armado.distanciaM(1, 2), closeTo(2.0, 1e-9));
      expect(e.estilo, EstiloPlano.arquitecto);
      expect(e.modo, ModoSorteo.bloques);
    });

    testWidgets('cada armado dice si entra la fiesta', (tester) async {
      await _abrir(tester);
      expect(_tarjeta(tester, ArmarAMedida.claveArmado),
          containsAll(['A medida del playón', '132 mesas a 2 m', 'Entra']));
      expect(_tarjeta(tester, ArmadosPredefinidos.normal2aPagina3Clave).last,
          'Faltan 54 mesas');
      expect(_tarjeta(tester, ArmadosPredefinidos.normal2aPaginas45Clave).last,
          'Faltan 32 mesas');
      expect(_tarjeta(tester, ArmadosPredefinidos.normal2a2bClave).last, 'Entra');
      // Técnica tiene 130 comunes: las dos que faltan van al pasto.
      final tecnica = _tarjeta(tester, ArmadosPredefinidos.tecnica1a1bClave);
      expect(tecnica.last, 'Entra con el pasto');
      expect(tecnica[1], startsWith('130 mesas y 20 de pasto · '));
      // La primera vez no hay "como está ahora".
      expect(find.byKey(const Key('armado___actual__')), findsNothing);
    });

    testWidgets('se puede elegir otro armado, otro estilo y otro sorteo',
        (tester) async {
      final r = await _abrir(tester);
      await _tocar(tester, 'armado_${ArmadosPredefinidos.normal2a2bClave}');
      // Con un armado del jefe, el panel de las medidas se va.
      expect(find.byKey(const Key('distancia')), findsNothing);
      await _tocar(tester, 'estilo_neon');
      await _tocar(tester, 'modo_entera');
      await _tocar(tester, 'listo');
      final e = r.eleccion!;
      expect(e.armado.clave, ArmadosPredefinidos.normal2a2bClave);
      expect(e.estilo, EstiloPlano.neon);
      expect(e.modo, ModoSorteo.entera);
    });

    testWidgets('cancelar no elige nada', (tester) async {
      final r = await _abrir(tester);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(r.cerrado, isTrue);
      expect(r.eleccion, isNull);
    });
  });

  group('a medida del playón', () {
    testWidgets('dice cuántas entran, y cuántas faltan si no entran',
        (tester) async {
      await _abrir(tester);
      expect(_textoDe(tester, 'resultado_medida'), 'Entran las 132 (hasta 284)');

      await tester.enterText(find.byKey(const Key('cantidad')), '300');
      await tester.pumpAndSettle();
      expect(_textoDe(tester, 'resultado_medida'), 'Entran 284: faltan 16');
      expect(_tarjeta(tester, ArmarAMedida.claveArmado).last, 'Faltan 16 mesas');
      // Si no entran, no hay playón que usar entero.
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('todo_el_playon')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('usar todo el playón separa las mesas lo más que se puede',
        (tester) async {
      final r = await _abrir(tester);
      await _tocar(tester, 'todo_el_playon');
      expect(find.textContaining('2,9 m'), findsWidgets);
      expect(_textoDe(tester, 'resultado_medida'), startsWith('Entran las 132'));
      await _tocar(tester, 'listo');
      expect(r.eleccion!.armado.mesas.length, 132);
      expect(r.eleccion!.armado.distanciaM(1, 2), closeTo(2.9, 1e-9));
    });

    testWidgets('sin pasarela entran más', (tester) async {
      final r = await _abrir(tester);
      await _tocar(tester, 'pasarela');
      final texto = _textoDe(tester, 'resultado_medida');
      final hasta = int.parse(RegExp(r'hasta (\d+)').firstMatch(texto)!.group(1)!);
      expect(hasta, greaterThan(284));
      await _tocar(tester, 'listo');
      expect(r.eleccion!.armado.sectores.length, 1);
    });

    testWidgets('una cantidad vacía o en cero no rompe: queda la anterior',
        (tester) async {
      final r = await _abrir(tester);
      await tester.enterText(find.byKey(const Key('cantidad')), '');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cantidad')), '0');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _tocar(tester, 'listo');
      expect(r.eleccion!.armado.mesas.length, 132);
    });
  });

  group('con el plano ya armado', () {
    testWidgets('viene elegido como está: el mismo armado, estilo y sorteo',
        (tester) async {
      final actual = planoCon();
      final r = await _abrir(tester, actual: actual);
      expect(_tarjeta(tester, '__actual__').first, 'Como está ahora');
      await _tocar(tester, 'listo');
      final e = r.eleccion!;
      expect(jsonEncode(e.armado.toJson()), actual.armadoJson);
      expect(e.estilo, EstiloPlano.neon);
      expect(e.modo, ModoSorteo.entera);
    });

    testWidgets('con familias ya sentadas el armado no se cambia; el estilo sí',
        (tester) async {
      final actual = planoCon();
      final r = await _abrir(
        tester,
        actual: actual,
        trabado: 'Ya hay familias con mesa: para cambiar el armado hay que '
            'deshacer el sorteo. El estilo se cambia siempre.',
      );
      expect(find.textContaining('deshacer el sorteo'), findsOneWidget);
      await _tocar(tester, 'armado_${ArmadosPredefinidos.normal2aPagina3Clave}');
      await _tocar(tester, 'armado_${ArmarAMedida.claveArmado}');
      await _tocar(tester, 'estilo_gala');
      await _tocar(tester, 'listo');
      final e = r.eleccion!;
      expect(jsonEncode(e.armado.toJson()), actual.armadoJson);
      expect(e.estilo, EstiloPlano.gala);
    });

    testWidgets('un estilo guardado que ya no existe cae en Arquitecto',
        (tester) async {
      final raro = PlanoEvento.fromMap(planoCon().toMap()..['estilo'] = 'cristal');
      final r = await _abrir(tester, actual: raro);
      await _tocar(tester, 'listo');
      expect(r.eleccion!.estilo, EstiloPlano.arquitecto);
    });

    testWidgets('un armado guardado que no se puede leer: se elige de nuevo',
        (tester) async {
      final roto = PlanoEvento.fromMap(planoCon().toMap()..['armado_json'] = '{');
      final r = await _abrir(tester, actual: roto);
      expect(find.byKey(const Key('armado___actual__')), findsNothing);
      await _tocar(tester, 'listo');
      expect(r.eleccion!.armado.clave, ArmarAMedida.claveArmado);
    });
  });

  testWidgets('con una sola mesa habla en singular', (tester) async {
    await _abrir(tester, necesarias: 1);
    expect(find.textContaining('La fiesta necesita 1 mesa.'), findsOneWidget);
    expect(_tarjeta(tester, ArmarAMedida.claveArmado)[1], '1 mesa a 2 m');
  });
}
