import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/planilla_sorteo.dart';
import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/eventos/widgets/opciones_planilla_sorteo_dialog.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

ContratoAlumno _alumno(String id, String? mesa) => ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa: mesa,
    );

// 12/11/2026 21:40 en Argentina.
final _base = DateTime.utc(2026, 11, 13, 0, 40);

SorteoMesasRegistro _sorteo(Map<String, String> resultado, {required int dia}) =>
    SorteoMesasRegistro(
      id: 'r$dia',
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: const {},
      hechoPor: 'Jefe',
      createdAt: _base.add(Duration(days: dia)),
    );

/// Un primer sorteo y, después, el de los que faltaban (`c` y `d`).
UltimosSorteados _conLosQueFaltaban() => UltimosSorteados.de(
      [
        _sorteo({'a': '12', 'b': '14'}, dia: 0),
        _sorteo({'c': '20', 'd': '21'}, dia: 3),
      ],
      [
        _alumno('a', '12'),
        _alumno('b', '14'),
        _alumno('c', '20'),
        _alumno('d', '21'),
      ],
    )!;

void main() {
  Future<List<OpcionesPlanillaSorteo?>> abrir(
    WidgetTester tester, {
    UltimosSorteados? ultimos,
    bool sugerirUltimos = false,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final elegido = <OpcionesPlanillaSorteo?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => elegido.add(
                await elegirOpcionesPlanillaSorteo(
                  context: context,
                  ultimos: ultimos,
                  sugerirUltimos: sugerirUltimos,
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
    return elegido;
  }

  Future<void> generar(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('planilla_generar')));
    await tester.pumpAndSettle();
  }

  testWidgets('sin últimos sorteados no pregunta quiénes: es el de siempre',
      (tester) async {
    final elegido = await abrir(tester);
    expect(find.text('Quiénes'), findsNothing);
    expect(find.text('Versión'), findsOneWidget);
    expect(find.text('Impresión'), findsOneWidget);

    await generar(tester);
    expect(elegido.single, (
      version: VersionPlanillaSorteo.interna,
      blancoYNegro: false,
      soloUltimos: false,
      vertical: true,
      orden: OrdenPlanillaSorteo.alfabetico,
    ));
  });

  testWidgets('el orden viene alfabético, y se puede pedir por número de mesa',
      (tester) async {
    // 25-nov-2026: para ir anotando qué mesa le tocó a cada chico, la lista de
    // la mesa 1 a la última. Vale para la interna y para la de repartir.
    final elegido = await abrir(tester);
    expect(find.text('Orden'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<OrdenPlanillaSorteo>>(
            find.byKey(const Key('planilla_orden')),
          )
          .selected,
      {OrdenPlanillaSorteo.alfabetico},
    );
    expect(find.text('Una hoja por división, por apellido.'), findsOneWidget);

    await tester.ensureVisible(find.text('Por número de mesa'));
    await tester.tap(find.text('Por número de mesa'));
    await tester.ensureVisible(find.text('Para repartir'));
    await tester.tap(find.text('Para repartir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('de la mesa 1 a la última'), findsOneWidget);
    await generar(tester);
    expect(elegido.single!.orden, OrdenPlanillaSorteo.porMesa);
    expect(elegido.single!.version, VersionPlanillaSorteo.paraRepartir);
  });

  testWidgets('la hoja viene parada, y se puede pedir acostada', (tester) async {
    // 10-nov-2026: acostada, en una impresora puesta en vertical, salía a
    // media hoja o cortada a la derecha.
    final elegido = await abrir(tester);
    expect(find.text('La hoja'), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byKey(const Key('planilla_hoja')))
          .selected,
      {true},
    );

    await tester.ensureVisible(find.text('Acostada'));
    await tester.tap(find.text('Acostada'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('hay que elegir orientación Horizontal'),
      findsOneWidget,
    );
    await generar(tester);
    expect(elegido.single!.vertical, isFalse);
  });

  testWidgets('si el único sorteo es de todos, tampoco', (tester) async {
    final ultimos = UltimosSorteados.de(
      [_sorteo({'a': '12', 'b': '14'}, dia: 0)],
      [_alumno('a', '12'), _alumno('b', '14'), _alumno('c', null)],
    );
    await abrir(tester, ultimos: ultimos, sugerirUltimos: true);
    expect(find.text('Quiénes'), findsNothing);
  });

  testWidgets('con los que faltaban ya sorteados pregunta quiénes, y viene '
      'toda la escuela', (tester) async {
    final elegido = await abrir(tester, ultimos: _conLosQueFaltaban());
    expect(find.text('Quiénes'), findsOneWidget);
    expect(find.text('Toda la escuela'), findsOneWidget);
    expect(find.text('Solo los últimos sorteados (2)'), findsOneWidget);
    expect(
      find.text('El resumen del salón y una hoja por división.'),
      findsOneWidget,
    );

    await generar(tester);
    expect(elegido.single!.soloUltimos, isFalse);
  });

  testWidgets('se puede elegir solo los últimos, y dice de qué sorteo son',
      (tester) async {
    final elegido = await abrir(tester, ultimos: _conLosQueFaltaban());
    await tester.tap(find.text('Solo los últimos sorteados (2)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Las del sorteo del 15/11/2026 21:40 hs, en una sola hoja.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Para repartir'));
    await tester.tap(find.text('Para repartir'));
    await tester.ensureVisible(find.text('Blanco y negro'));
    await tester.tap(find.text('Blanco y negro'));
    await tester.pumpAndSettle();
    await generar(tester);
    expect(elegido.single, (
      version: VersionPlanillaSorteo.paraRepartir,
      blancoYNegro: true,
      soloUltimos: true,
      vertical: true,
      orden: OrdenPlanillaSorteo.alfabetico,
    ));
  });

  testWidgets('desde el aviso de "Sorteo listo" vienen elegidos los últimos',
      (tester) async {
    final elegido = await abrir(
      tester,
      ultimos: _conLosQueFaltaban(),
      sugerirUltimos: true,
    );
    await generar(tester);
    expect(elegido.single!.soloUltimos, isTrue);
  });

  testWidgets('un primer sorteo con mesas cargadas a mano aparte: se ofrece, '
      'pero no viene elegido', (tester) async {
    final ultimos = UltimosSorteados.de(
      [_sorteo({'a': '12'}, dia: 0)],
      [_alumno('a', '12'), _alumno('b', '50')],
    );
    final elegido = await abrir(tester, ultimos: ultimos, sugerirUltimos: true);
    expect(find.text('Solo los últimos sorteados (1)'), findsOneWidget);
    await generar(tester);
    expect(elegido.single!.soloUltimos, isFalse);
  });

  testWidgets('cancelar no elige nada', (tester) async {
    final elegido = await abrir(tester, ultimos: _conLosQueFaltaban());
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();
    expect(elegido, [null]);
  });
}
