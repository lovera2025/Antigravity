// El cartel del sorteo con el tilde "Cumplimiento debido" (6.7.1). Viene
// destildado: sin tocar nada, devuelve lo de siempre. Tildado, esconde lo que
// ya no decide y sirve también con el sorteo ya hecho (reacomoda).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// 9 cuotas de $30.000, alta el 30/3: la cuota 1 vence el 30/4.
ContratoAlumno _familia(String id, {int extras = 0, String? mesa}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 0,
      totalCuotas: 9,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      cursoDivision: '5° A',
      numeroMesa: mesa,
      createdAt: DateTime.utc(2026, 3, 30, 3),
    );

/// 12 familias, dos con una adicional. 14 mesas.
List<ContratoAlumno> _escuela({bool sentadas = false}) => [
      _familia('a1', extras: 1, mesa: sentadas ? '13, 14' : null),
      _familia('a2', extras: 1, mesa: sentadas ? '11, 12' : null),
      for (var i = 0; i < 10; i++)
        _familia('s$i', mesa: sentadas ? '${10 - i}' : null),
    ];

/// Todos con la base y sus adicionales pagas: nadie queda afuera por pagos.
Map<String, PagoAlumno> _pagos(List<ContratoAlumno> alumnos) => {
      for (final a in alumnos)
        a.id: PagoAlumno(base: 1000, mesas: a.mesaExtraPrecio),
    };

/// Los pagos uno por uno: cada familia canceló un día distinto de abril, así
/// el orden no depende del azar (la que antes canceló, primero).
Map<String, List<Map<String, dynamic>>> _crudos(List<ContratoAlumno> alumnos) =>
    {
      for (final (i, a) in alumnos.indexed)
        a.id: [
          {
            'id': 'p$i',
            'concepto': 'Cuota Base',
            'monto': 270000.0,
            'monto_gross': 270000.0,
            'fecha_pago': DateTime.utc(2026, 4, 1 + i, 15).toIso8601String(),
            'created_at': DateTime.utc(2026, 4, 1 + i, 15).toIso8601String(),
            'anulado': 0,
          },
        ],
    };

PlanoEvento _plano({ModoSorteo modo = ModoSorteo.entera}) => PlanoEvento.nuevo(
      eventoId: 'e',
      armado: ArmarAMedida.armar(
        const OpcionesAMedida(
          playon: PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
          cantidad: 24,
        ),
      ).armado,
      estilo: EstiloPlano.gala,
      modo: modo,
      ahora: DateTime.utc(2026, 11, 12),
    );

Future<void> _abrir(
  WidgetTester tester, {
  required List<ContratoAlumno> alumnos,
  required void Function(SorteoMesasDialogResult?) alCerrar,
  PlanoEvento? plano,
  bool conPagos = true,
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
              await showDialog<SorteoMesasDialogResult>(
                context: context,
                builder: (_) => SorteoMesasDialog(
                  tituloInstitucion: 'ESCUELA DE PRUEBA',
                  alumnos: alumnos,
                  avisos: const [],
                  pagos: _pagos(alumnos),
                  plano: plano ?? _plano(),
                  eventoId: conPagos ? 'e' : null,
                  pagosCrudos: conPagos ? _crudos(alumnos) : null,
                  hoyAr: DateTime(2026, 11, 12),
                ),
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

bool _sePuedeSortear(WidgetTester tester) =>
    tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'SORTEAR'),
        )
        .onPressed !=
    null;

const _tilde = Key('por_cumplimiento');

void main() {
  testWidgets('sin los pagos a mano, el tilde no aparece', (tester) async {
    await _abrir(
      tester,
      alumnos: _escuela(),
      alCerrar: (_) {},
      conPagos: false,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(_tilde), findsNothing);
  });

  testWidgets('viene destildado, y sin tocarlo devuelve lo de siempre',
      (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(tester, alumnos: _escuela(), alCerrar: (x) => r = x);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_tilde), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(_tilde)).value, isFalse);
    expect(_texto(tester, 'por_cumplimiento_dice'),
        'Las mejores mesas, para quien mejor cumplió.');
    expect(find.byKey(const Key('cumplimiento_recorrido')), findsNothing);
    expect(find.text('Usar de la mesa 1 a la'), findsOneWidget);

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.porCumplimiento, isFalse);
    expect(r!.hastaMesa, 14);
    expect(r!.modo, ModoSorteo.entera);
  });

  testWidgets('tildado, esconde lo que ya no decide y devuelve el tilde',
      (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(tester, alumnos: _escuela(), alCerrar: (x) => r = x);
    await _tocar(tester, find.byKey(_tilde));
    expect(tester.takeException(), isNull);

    expect(find.byKey(const Key('cumplimiento_recorrido')), findsOneWidget);
    expect(find.text('Usar de la mesa 1 a la'), findsNothing);
    expect(find.text('Por división, cada una junta'), findsNothing);
    expect(find.textContaining('Con mesas extra'), findsNothing);
    // "Las mesas adicionales" sigue: se puede mandarlas al final.
    expect(find.text('Las mesas adicionales'), findsOneWidget);
    expect(_texto(tester, 'sorteo_resumen'), 'Se van a sortear 14 mesas');
    expect(_sePuedeSortear(tester), isTrue);

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.porCumplimiento, isTrue);
    expect(r!.recorrido, RecorridoDelOrden.columnas);
    expect(r!.modo, ModoSorteo.entera);
    expect(r!.hastaMesa, isNull);
    expect(r!.separaciones, isEmpty);
    expect(r!.zonas, isEmpty);
    expect(r!.alFinal, isEmpty);
    expect(r!.mesasNuevasAlFondo, isFalse);
  });

  testWidgets('por filas y con las adicionales al final', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(tester, alumnos: _escuela(), alCerrar: (x) => r = x);
    await _tocar(tester, find.byKey(_tilde));
    await _tocar(tester, find.text('Por filas'));
    await _tocar(tester, find.byKey(const Key('adicionales_al_final')));
    expect(tester.takeException(), isNull);
    expect(_texto(tester, 'adicionales_por_cumplimiento'),
        'Primero todas las principales; después, las adicionales.');
    expect(find.byKey(const Key('adicionales_rangos')), findsNothing);
    expect(_sePuedeSortear(tester), isTrue);

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.porCumplimiento, isTrue);
    expect(r!.recorrido, RecorridoDelOrden.filas);
    expect(r!.adicionalesAlFinal, isTrue);
    // Al sorteo no se le pide nada "al final": ya lo repartió el orden.
    expect(r!.alFinal, isEmpty);
  });

  testWidgets('en una fiesta por división, tildarlo pasa a toda la escuela '
      'junta', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(),
      plano: _plano(modo: ModoSorteo.bloques),
      alCerrar: (x) => r = x,
    );
    expect(find.text('Por división, cada una junta'), findsOneWidget);
    await _tocar(tester, find.byKey(_tilde));
    expect(tester.takeException(), isNull);
    expect(_sePuedeSortear(tester), isTrue);
    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.porCumplimiento, isTrue);
    expect(r!.modo, ModoSorteo.entera);
  });

  testWidgets('con el sorteo ya hecho: sin el tilde no queda nada por '
      'sortear; con el tilde, reacomoda', (tester) async {
    SorteoMesasDialogResult? r;
    await _abrir(
      tester,
      alumnos: _escuela(sentadas: true),
      alCerrar: (x) => r = x,
    );
    expect(tester.takeException(), isNull);
    expect(_texto(tester, 'sorteo_resumen'), 'No queda nadie por sortear');
    expect(_sePuedeSortear(tester), isFalse);

    await _tocar(tester, find.byKey(_tilde));
    expect(tester.takeException(), isNull);
    expect(_texto(tester, 'sorteo_resumen'), 'Se reacomoda el salón');
    expect(_texto(tester, 'sorteo_reacomoda'),
        contains('cambian de mesa. Nadie pierde mesas.'));
    expect(_sePuedeSortear(tester), isTrue);

    await _tocar(tester, find.text('SORTEAR'));
    expect(r!.porCumplimiento, isTrue);
  });
}
