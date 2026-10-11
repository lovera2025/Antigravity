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
    ));
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

    await tester.tap(find.text('Para repartir'));
    await tester.tap(find.text('Blanco y negro'));
    await tester.pumpAndSettle();
    await generar(tester);
    expect(elegido.single, (
      version: VersionPlanillaSorteo.paraRepartir,
      blancoYNegro: true,
      soloUltimos: true,
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
