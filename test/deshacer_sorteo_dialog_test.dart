import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/ultimos_sorteados.dart';
import 'package:arguello_events/features/eventos/widgets/deshacer_sorteo_dialog.dart';
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

SorteoMesasRegistro _sorteo(
  Map<String, String> resultado, {
  required int dia,
  Map<String, String> antes = const {},
}) =>
    SorteoMesasRegistro(
      id: 'r$dia',
      eventoId: 'e',
      tipo: TipoRegistroSorteo.sorteo,
      resultado: resultado,
      antes: antes,
      hechoPor: 'Jefe',
      createdAt: _base.add(Duration(days: dia)),
    );

/// El primer sorteo sentó a `a` y `b`; después se sorteó a los que faltaban:
/// `c` (nuevo) y `a`, que compró otra mesa.
UltimosSorteados _ultimos({String? mesaDeC = '20'}) => UltimosSorteados.de(
      [
        _sorteo({'a': '12', 'b': '14'}, dia: 0),
        _sorteo({'a': '12, 13', 'c': '20'}, dia: 3, antes: {'a': '12'}),
      ],
      [_alumno('a', '12, 13'), _alumno('b', '14'), _alumno('c', mesaDeC)],
    )!;

void main() {
  /// Abre el diálogo y devuelve dónde queda lo que se eligió.
  Future<List<AlcanceDeshacer?>> abrir(
    WidgetTester tester, {
    required int conMesa,
    UltimosSorteados? ultimos,
    int adentro = 0,
  }) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final elegido = <AlcanceDeshacer?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => elegido.add(
                await mostrarDeshacerSorteoDialog(
                  context: context,
                  conMesa: conMesa,
                  ultimos: ultimos,
                  adentroEnLaPuerta: adentro,
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

  bool confirmarPrendido(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(find.byKey(const Key('deshacer_confirmar')))
          .onPressed !=
      null;

  group('con un último sorteo aparte del resto', () {
    testWidgets('viene elegido "Solo los últimos", sin tilde, y dice cómo '
        'queda cada uno', (tester) async {
      final elegido = await abrir(tester, conMesa: 3, ultimos: _ultimos());

      expect(find.text('Solo los últimos sorteados'), findsOneWidget);
      expect(
        find.text('2 familias · sorteo del 15/11/2026 21:40 hs · Jefe'),
        findsOneWidget,
      );
      expect(find.text('Todo'), findsOneWidget);
      // El que compró otra mesa conserva la suya; el nuevo queda sin mesa.
      expect(find.text('12, 13 → 12'), findsOneWidget);
      expect(find.text('20 → sin mesa'), findsOneWidget);
      // El del primer sorteo ni aparece.
      expect(find.text('ALUMNO b'), findsNothing);
      expect(find.byKey(const Key('deshacer_entendido')), findsNothing);
      expect(find.text('DESHACER A 2 FAMILIAS'), findsOneWidget);
      expect(confirmarPrendido(tester), isTrue);

      await tester.tap(find.byKey(const Key('deshacer_confirmar')));
      await tester.pumpAndSettle();
      expect(elegido, [AlcanceDeshacer.ultimos]);
    });

    testWidgets('"Todo" pide la tilde, como siempre', (tester) async {
      final elegido = await abrir(tester, conMesa: 3, ultimos: _ultimos());

      await tester.tap(find.byKey(const Key('deshacer_todo')));
      await tester.pumpAndSettle();
      expect(find.text('DESHACER MESAS'), findsOneWidget);
      expect(find.text('12, 13 → 12'), findsNothing);
      expect(confirmarPrendido(tester), isFalse);

      await tester.tap(find.byKey(const Key('deshacer_entendido')));
      await tester.pumpAndSettle();
      expect(confirmarPrendido(tester), isTrue);

      await tester.tap(find.byKey(const Key('deshacer_confirmar')));
      await tester.pumpAndSettle();
      expect(elegido, [AlcanceDeshacer.todo]);
    });

    testWidgets('al que mudaron después lo nombra y dice que no se toca',
        (tester) async {
      await abrir(tester, conMesa: 3, ultimos: _ultimos(mesaDeC: '31'));

      expect(find.text('ALUMNO c'), findsOneWidget);
      expect(
        find.text('No se toca: le cambiaron la mesa después de ese sorteo.'),
        findsOneWidget,
      );
      expect(find.text('DESHACER A 1 FAMILIA'), findsOneWidget);
    });

    testWidgets('cancelar no elige nada', (tester) async {
      final elegido = await abrir(tester, conMesa: 3, ultimos: _ultimos());
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(elegido, [null]);
    });
  });

  group('cuando no hay diferencia', () {
    testWidgets('sin registro de sorteos, es el aviso de siempre',
        (tester) async {
      await abrir(tester, conMesa: 133);

      expect(find.text('Solo los últimos sorteados'), findsNothing);
      expect(find.text('Todo'), findsNothing);
      expect(
        find.textContaining('Se van a borrar los números de mesa de 133'),
        findsOneWidget,
      );
      expect(confirmarPrendido(tester), isFalse);
    });

    testWidgets('si el único sorteo es de todos los que tienen mesa, también',
        (tester) async {
      final ultimos = UltimosSorteados.de(
        [_sorteo({'a': '1', 'b': '2'}, dia: 0)],
        [_alumno('a', '1'), _alumno('b', '2')],
      );
      await abrir(tester, conMesa: 2, ultimos: ultimos);

      expect(find.text('Solo los últimos sorteados'), findsNothing);
      expect(find.byKey(const Key('deshacer_entendido')), findsOneWidget);
    });
  });

  testWidgets('si todos los del último sorteo cambiaron después, la opción se '
      've apagada con el motivo y queda elegido "Todo"', (tester) async {
    final ultimos = UltimosSorteados.de(
      [
        _sorteo({'b': '14'}, dia: 0),
        _sorteo({'c': '20'}, dia: 3),
      ],
      [_alumno('b', '14'), _alumno('c', '31')],
    );
    await abrir(tester, conMesa: 2, ultimos: ultimos);

    expect(find.text('Solo los últimos sorteados'), findsOneWidget);
    expect(
      find.textContaining('cambiaron de mesa después: no hay nada para '
          'deshacer solo de ellas'),
      findsOneWidget,
    );
    expect(find.text('DESHACER MESAS'), findsOneWidget);
    expect(find.byKey(const Key('deshacer_entendido')), findsOneWidget);

    // Tocarla no la elige.
    await tester.tap(find.byKey(const Key('deshacer_ultimos')));
    await tester.pumpAndSettle();
    expect(find.text('DESHACER MESAS'), findsOneWidget);
  });

  testWidgets('con muchas familias no desborda en una notebook',
      (tester) async {
    final resultado = {for (var i = 1; i <= 40; i++) 'f$i': '${100 + i}'};
    final ultimos = UltimosSorteados.de(
      [
        _sorteo({'b': '14'}, dia: 0),
        _sorteo(resultado, dia: 3),
      ],
      [
        _alumno('b', '14'),
        for (final e in resultado.entries) _alumno(e.key, e.value),
      ],
    );
    await abrir(tester, conMesa: 41, ultimos: ultimos);
    expect(find.text('DESHACER A 40 FAMILIAS'), findsOneWidget);
  });

  // Al deshacer todo, la lista de la puerta de esa fiesta se vacía sola.
  group('la lista de la puerta', () {
    testWidgets('"Todo" dice que Recepción y el tótem dejan de mostrarla',
        (tester) async {
      await abrir(tester, conMesa: 133);
      expect(
        find.textContaining(
          'Recepción y el tótem dejan de mostrar a esta institución',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('deshacer_adentro')), findsNothing);
    });

    testWidgets('si hay gente marcada como adentro, lo dice con el número',
        (tester) async {
      await abrir(tester, conMesa: 133, adentro: 14);
      expect(
        find.text(
          'Hay 14 personas marcadas como adentro en Recepción: esos ingresos '
          'se pierden con la lista.',
        ),
        findsOneWidget,
      );
      // Sigue pidiendo la tilde: no se deshace de un toque.
      expect(confirmarPrendido(tester), isFalse);
    });

    testWidgets('con una sola persona adentro, lo dice en singular',
        (tester) async {
      await abrir(tester, conMesa: 133, adentro: 1);
      expect(
        find.text(
          'Hay 1 persona marcada como adentro en Recepción: ese ingreso se '
          'pierde con la lista.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('al deshacer solo a los últimos no asusta: la lista se queda',
        (tester) async {
      await abrir(tester, conMesa: 3, ultimos: _ultimos(), adentro: 14);
      expect(find.byKey(const Key('deshacer_adentro')), findsNothing);
    });
  });
}
