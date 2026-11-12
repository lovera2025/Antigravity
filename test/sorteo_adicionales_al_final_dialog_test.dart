// El cartel del sorteo con "Las mesas adicionales: Con su familia · Al final"
// (6.6.1). Viene en "Con su familia": sin tocar nada, devuelve lo de siempre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/modelo/numeracion.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _familia(String id, {int extras = 0, String division = '5° A'}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      cursoDivision: division,
    );

/// 20 familias: tres con una adicional (a1, a2, a3), una con dos (b1) y una
/// con cuatro (c1). 29 mesas.
List<ContratoAlumno> _escuela() => [
      _familia('a1', extras: 1),
      _familia('a2', extras: 1),
      _familia('a3', extras: 1, division: '5° B'),
      _familia('b1', extras: 2),
      _familia('c1', extras: 4, division: '5° B'),
      for (var i = 0; i < 15; i++)
        _familia('s$i', division: i.isEven ? '5° A' : '5° B'),
    ];

/// Todos con la base y sus adicionales pagas: nadie queda afuera por pagos.
Map<String, PagoAlumno> _pagos(List<ContratoAlumno> alumnos) => {
      for (final a in alumnos)
        a.id: PagoAlumno(base: 1000, mesas: a.mesaExtraPrecio),
    };

PlanoEvento _plano({ModoSorteo modo = ModoSorteo.entera, int mesas = 40}) =>
    PlanoEvento.nuevo(
      eventoId: 'e',
      armado: ArmarAMedida.armar(
        OpcionesAMedida(
          playon: const PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
          cantidad: mesas,
          fin: FinNumeracion.filas,
        ),
      ).armado,
      estilo: EstiloPlano.gala,
      modo: modo,
      ahora: DateTime.utc(2026, 11, 11),
    );

Future<void> _abrir(
  WidgetTester tester, {
  required List<ContratoAlumno> alumnos,
  required PlanoEvento plano,
  required void Function(SorteoMesasDialogResult?) alCerrar,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async => alCerrar(
              await mostrarSorteoMesasDialog(
                context: context,
                tituloInstitucion: 'ESCUELA DE PRUEBA',
                alumnos: alumnos,
                avisos: const [],
                pagos: _pagos(alumnos),
                plano: plano,
              ),
            ),
            child: const Text('ABRIR'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ABRIR'));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

String _texto(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

bool _elegido(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

const _alFinal = Key('adicionales_al_final');

void main() {
  testWidgets('viene en "Con su familia", y sin tocar nada devuelve lo de '
      'siempre', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Las mesas adicionales'), findsOneWidget);
    expect(_elegido(tester, 'adicionales_con_su_familia'), isTrue);
    expect(_elegido(tester, 'adicionales_al_final'), isFalse);
    expect(find.byKey(const Key('adicionales_juntas')), findsNothing);
    expect(find.byKey(const Key('adicionales_rangos')), findsNothing);
    expect(find.text('Usar de la mesa 1 a la'), findsOneWidget);
    expect(find.byKey(const Key('dejar_juntas_a1')), findsNothing);
    // La de más de 3 mesas viene tildada "lejos", como desde la 6.5.0.
    expect(find.byKey(const Key('aviso_mas_de_tres')), findsOneWidget);

    await _tocar(tester, find.text('SORTEAR'));
    expect(r, isNotNull);
    expect(r!.adicionalesAlFinal, isFalse);
    expect(r!.alFinal, isEmpty);
    expect(r!.separaciones, {'c1': 2});
    expect(r!.hastaMesa, 29);
  });

  testWidgets('"Al final": dice de qué mesa a qué mesa va cada cosa y cada '
      'familia tiene su "Dejar juntas"', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    await _tocar(tester, find.byKey(_alFinal));
    expect(tester.takeException(), isNull);
    expect(_elegido(tester, 'adicionales_al_final'), isTrue);
    expect(
      _texto(tester, 'adicionales_rangos'),
      'Adelante: de la 1 a la 20 · Al final: de la 21 a la 29 (9 mesas).',
    );
    expect(find.text('Las de adelante, de la mesa 1 a la'), findsOneWidget);
    expect(find.text('Mínimo la 20 para que entren las de adelante.'),
        findsOneWidget);
    expect(
      _texto(tester, 'con_mesas_extra_explica'),
      contains('van al final'),
    );
    // Sin los tildes de "lejos": cada familia dice dónde va cada mesa.
    expect(find.byKey(const Key('aviso_mas_de_tres')), findsNothing);
    expect(find.byKey(const Key('explicacion_lejos_c1')), findsNothing);
    expect(
      _texto(tester, 'explicacion_al_final_a1'),
      'La principal va adelante; la otra va al final.',
    );
    expect(
      _texto(tester, 'explicacion_al_final_c1'),
      'La principal va adelante; las otras 4 van al final, juntas entre sí.',
    );

    await _tocar(tester, find.text('SORTEAR'));
    expect(r, isNotNull);
    expect(r!.adicionalesAlFinal, isTrue);
    expect(r!.juntasConLaPrincipal, 0);
    expect(r!.alFinal, {'a1': 1, 'a2': 1, 'a3': 1, 'b1': 2, 'c1': 4});
    expect(r!.separaciones, isEmpty,
        reason: 'el "lejos" que venía tildado no viaja con "Al final"');
    expect(r!.distancias, isEmpty);
    expect(r!.hastaMesa, 20);
  });

  testWidgets('la regla por cantidad: con 1, solo va al final lo que pasa de '
      'una adicional', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    await _tocar(tester, find.byKey(_alFinal));
    await _tocar(
      tester,
      find.descendant(
        of: find.byKey(const Key('adicionales_juntas')),
        matching: find.text('1'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      _texto(tester, 'explicacion_al_final_a1'),
      'Sus 2 mesas van juntas, adelante.',
    );
    expect(
      _texto(tester, 'explicacion_al_final_b1'),
      'La principal y 1 adicional van juntas, adelante; la otra va al final.',
    );
    expect(_texto(tester, 'adicionales_rangos'), contains('(4 mesas)'));

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.juntasConLaPrincipal, 1);
    expect(r!.alFinal, {'b1': 1, 'c1': 3});
  });

  testWidgets('"Dejar juntas" saca a esa familia: queda entera, adelante',
      (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    await _tocar(tester, find.byKey(_alFinal));
    await _tocar(tester, find.byKey(const Key('dejar_juntas_b1')));
    expect(tester.takeException(), isNull);
    expect(
      _texto(tester, 'explicacion_al_final_b1'),
      'Sus 3 mesas van juntas, adelante.',
    );
    expect(_texto(tester, 'adicionales_rangos'), contains('(7 mesas)'));

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.dejarJuntas, {'b1'});
    expect(r!.alFinal, {'a1': 1, 'a2': 1, 'a3': 1, 'c1': 4});
  });

  testWidgets('volver a "Con su familia" deja todo como estaba', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    await _tocar(tester, find.byKey(_alFinal));
    await _tocar(tester, find.byKey(const Key('adicionales_con_su_familia')));
    expect(find.byKey(const Key('adicionales_rangos')), findsNothing);
    expect(find.text('Usar de la mesa 1 a la'), findsOneWidget);
    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.adicionalesAlFinal, isFalse);
    expect(r!.alFinal, isEmpty);
    expect(r!.separaciones, {'c1': 2});
    expect(r!.hastaMesa, 29);
  });

  testWidgets('por división se ve apagada, con el motivo', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(modo: ModoSorteo.bloques),
      alCerrar: (x) => r = x,
    );
    expect(find.text('Las mesas adicionales'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(find.byKey(_alFinal)).onSelected,
      isNull,
    );
    expect(
      _texto(tester, 'adicionales_motivo'),
      contains('Toda la escuela junta'),
    );
    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.adicionalesAlFinal, isFalse);
    expect(r!.alFinal, isEmpty);

  });

  testWidgets('elegida y después "Por división": deja de valer', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(),
      alCerrar: (x) => r = x,
    );
    await _tocar(tester, find.byKey(_alFinal));
    await _tocar(tester, find.text('Por división, cada una junta'));
    expect(tester.takeException(), isNull);
    expect(_elegido(tester, 'adicionales_al_final'), isFalse);
    expect(find.byKey(const Key('dejar_juntas_a1')), findsNothing);
    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.adicionalesAlFinal, isFalse);
    expect(r!.alFinal, isEmpty);
  });

  testWidgets('sin adicionales para sortear, ni se pregunta', (tester) async {
    await _abrir(
      tester,
      alumnos: [for (var i = 0; i < 10; i++) _familia('s$i')],
      plano: _plano(),
      alCerrar: (_) {},
    );
    expect(find.text('Las mesas adicionales'), findsNothing);
  });

  testWidgets('si las del final no entran, lo dice en rojo y no deja sortear',
      (tester) async {
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(mesas: 27),
      alCerrar: (_) {},
    );
    await _tocar(tester, find.byKey(_alFinal));
    expect(tester.takeException(), isNull);
    expect(
      _texto(tester, 'adicionales_rangos'),
      contains('no entran después de las de adelante'),
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'SORTEAR'),
          )
          .onPressed,
      isNull,
    );
  });
}
