// Los diálogos de M6: confirmar un cambio con su motivo, elegir para quién se
// fija una mesa, y el Historial.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/services/historial_sorteo.dart';
import 'package:arguello_events/features/plano/widgets/cambio_de_mesa_dialogs.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/movimiento_mesas.dart';
import 'package:arguello_events/models/plano_evento.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

ContratoAlumno _alumno(String id, {int extras = 0, String? mesa}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa: mesa,
      cursoDivision: '5° A',
    );

/// Abre un diálogo desde un botón y guarda lo que devolvió.
Future<List<T?>> _abrir<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) abrir,
) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final devuelto = <T?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async => devuelto.add(await abrir(context)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return devuelto;
}

bool _confirmarPrendido(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('confirmar'))).onPressed !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(cargarFuentesPlano);

  group('confirmar un cambio', () {
    testWidgets('muestra cómo queda y no deja confirmar sin motivo',
        (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(
          context: c,
          titulo: 'GÓMEZ y SOSA cambian de lugar',
          renglones: const ['GÓMEZ: 12, 13 → 40, 41', 'SOSA: 40, 41 → 12, 13'],
          avisos: const ['Son de divisiones distintas: 5° A y 5° B.'],
          sugerencias: motivosParaCambiar,
          textoConfirmar: 'CAMBIAR',
        ),
      );
      expect(find.text('GÓMEZ: 12, 13 → 40, 41'), findsOneWidget);
      expect(find.text('Son de divisiones distintas: 5° A y 5° B.'), findsOneWidget);
      expect(_confirmarPrendido(tester), isFalse);

      await tester.enterText(find.byKey(const Key('motivo')), '  Primos  ');
      await tester.pump();
      expect(_confirmarPrendido(tester), isTrue);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(r, ['Primos']);
    });

    testWidgets('un motivo de los de siempre se pone con un toque',
        (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(
          context: c,
          titulo: 'x',
          sugerencias: motivosParaCambiar,
        ),
      );
      await tester.tap(find.text('Pedido de la familia'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(r, ['Pedido de la familia']);
    });

    testWidgets('si ya retiró las entradas, hay que tildar que se le avisa',
        (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(
          context: c,
          titulo: 'x',
          hayQueAvisarALaFamilia: true,
        ),
      );
      await tester.enterText(find.byKey(const Key('motivo')), 'Pedido');
      await tester.pump();
      expect(_confirmarPrendido(tester), isFalse);
      await tester.tap(find.byKey(const Key('le_aviso')));
      await tester.pump();
      expect(_confirmarPrendido(tester), isTrue);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(r, ['Pedido']);
    });

    testWidgets('con el motivo opcional se puede confirmar sin escribir',
        (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(
          context: c,
          titulo: 'Dejar libre la mesa 50',
          motivoObligatorio: false,
          sugerencias: motivosParaLibre,
        ),
      );
      expect(_confirmarPrendido(tester), isTrue);
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(r, ['']);
    });

    testWidgets('sin pedir motivo (deshacer) alcanza con confirmar',
        (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(
          context: c,
          titulo: 'Deshacer el cambio',
          pedirMotivo: false,
          textoConfirmar: 'DESHACER',
        ),
      );
      expect(find.byKey(const Key('motivo')), findsNothing);
      await tester.tap(find.text('DESHACER'));
      await tester.pumpAndSettle();
      expect(r, ['']);
    });

    testWidgets('cancelar no devuelve nada', (tester) async {
      final r = await _abrir<String>(
        tester,
        (c) => confirmarCambioDeMesa(context: c, titulo: 'x'),
      );
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(r, [null]);
    });
  });

  group('elegir para quién se fija una mesa', () {
    final candidatos = [
      _alumno('gomez', extras: 1),
      _alumno('sosa'),
      _alumno('vega'),
    ];
    ({List<int> mesas, String? problema}) resultado(String id) => switch (id) {
          'gomez' => (mesas: [40, 41], problema: null),
          'sosa' => (mesas: [40], problema: null),
          _ => (mesas: const <int>[], problema: 'La mesa 40 ya la tiene OTRO.'),
        };

    testWidgets('dice qué mesas se fijan y pide el motivo', (tester) async {
      final r = await _abrir<({String alumnoId, String motivo})>(
        tester,
        (c) => elegirFamiliaParaFijar(
          context: c,
          mesa: 40,
          candidatos: candidatos,
          resultadoDe: resultado,
        ),
      );
      expect(find.text('Fijar desde la mesa 40'), findsOneWidget);
      expect(_confirmarPrendido(tester), isFalse);

      await tester.tap(find.byKey(const Key('familia_gomez')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('resultado_fijar'))).data,
          'A GOMEZ se le fijan las mesas 40, 41.');
      // Falta el motivo.
      expect(_confirmarPrendido(tester), isFalse);
      await tester.tap(find.text('Movilidad reducida'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmar')));
      await tester.pumpAndSettle();
      expect(r.single, (alumnoId: 'gomez', motivo: 'Movilidad reducida'));
    });

    testWidgets('si a esa familia no se le puede, dice por qué y no deja',
        (tester) async {
      await _abrir<({String alumnoId, String motivo})>(
        tester,
        (c) => elegirFamiliaParaFijar(
          context: c,
          mesa: 40,
          candidatos: candidatos,
          resultadoDe: resultado,
        ),
      );
      await tester.tap(find.byKey(const Key('familia_vega')));
      await tester.enterText(find.byKey(const Key('motivo')), 'Pedido');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('resultado_fijar'))).data,
          'La mesa 40 ya la tiene OTRO.');
      expect(_confirmarPrendido(tester), isFalse);
      // Con una mesa sola habla en singular.
      await tester.tap(find.byKey(const Key('familia_sosa')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('resultado_fijar'))).data,
          'A SOSA se le fija la mesa 40.');
      expect(_confirmarPrendido(tester), isTrue);
    });

    testWidgets('la elegida que el buscador deja afuera deja de estar elegida',
        (tester) async {
      // Antes quedaba elegida sin verse: se tocaba GÓMEZ, se buscaba "sosa" y
      // FIJAR fijaba para GÓMEZ.
      await _abrir<({String alumnoId, String motivo})>(
        tester,
        (c) => elegirFamiliaParaFijar(
          context: c,
          mesa: 40,
          candidatos: candidatos,
          resultadoDe: resultado,
        ),
      );
      await tester.tap(find.byKey(const Key('familia_gomez')));
      await tester.enterText(find.byKey(const Key('motivo')), 'Pedido');
      await tester.pump();
      expect(_confirmarPrendido(tester), isTrue);
      await tester.enterText(find.byKey(const Key('buscar_familia')), 'sosa');
      await tester.pump();
      expect(find.byKey(const Key('resultado_fijar')), findsNothing);
      expect(_confirmarPrendido(tester), isFalse);
    });

    testWidgets('en una pantalla baja se puede llegar a los botones',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Scaffold(
            body: FijarMesaDialog(
              mesa: 40,
              candidatos: candidatos,
              resultadoDe: (_) => (
                mesas: const <int>[],
                problema: 'Desde la 40 no hay 2 mesas pegadas: la 40 y la 41 '
                    'no están juntas. Elegí otra.',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('familia_gomez')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('se busca por apellido', (tester) async {
      await _abrir<({String alumnoId, String motivo})>(
        tester,
        (c) => elegirFamiliaParaFijar(
          context: c,
          mesa: 40,
          candidatos: candidatos,
          resultadoDe: resultado,
        ),
      );
      await tester.enterText(find.byKey(const Key('buscar_familia')), 'sos');
      await tester.pump();
      expect(find.byKey(const Key('familia_sosa')), findsOneWidget);
      expect(find.byKey(const Key('familia_gomez')), findsNothing);
      await tester.enterText(find.byKey(const Key('buscar_familia')), 'zzz');
      await tester.pump();
      expect(find.text('No hay ninguna con ese nombre.'), findsOneWidget);
    });

    testWidgets('si todas ya tienen mesa, lo dice', (tester) async {
      await _abrir<({String alumnoId, String motivo})>(
        tester,
        (c) => elegirFamiliaParaFijar(
          context: c,
          mesa: 40,
          candidatos: const [],
          resultadoDe: resultado,
        ),
      );
      expect(find.text('Todas las familias ya tienen mesa.'), findsOneWidget);
      expect(_confirmarPrendido(tester), isFalse);
    });
  });

  group('el Historial', () {
    final cuando = DateTime.utc(2026, 11, 13, 0, 40);
    final cambio = MovimientoMesas(
      id: 'm1',
      eventoId: 'e',
      tipo: TipoMovimientoMesas.mover,
      antes: const {'vega': '60'},
      despues: const {'vega': '70'},
      motivo: 'Columna',
      hechoPor: 'Operador',
      createdAt: cuando.add(const Duration(hours: 1)),
    );
    HistorialSorteo historial({String mesaDeVega = '70'}) =>
        HistorialSorteo.armar(
          registros: [
            SorteoMesasRegistro(
              id: 's1',
              eventoId: 'e',
              tipo: TipoRegistroSorteo.sorteo,
              resultado: const {'vega': '60', 'sosa': '12'},
              hechoPor: 'Jefe',
              createdAt: cuando,
            ),
          ],
          movimientos: [cambio],
          config: const ConfigPlano(libres: {50: MesaLibre(motivo: 'Columna')}),
          alumnos: [
            _alumno('vega', mesa: mesaDeVega),
            _alumno('sosa', mesa: '15'),
          ],
        );

    testWidgets('muestra qué pasó, quién y por qué, y deja deshacer',
        (tester) async {
      final deshechos = <String>[];
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(
          context: c,
          historial: historial(),
          onDeshacer: (m) => deshechos.add(m.id),
        ),
      );
      expect(find.text('VEGA pasó a otras mesas'), findsOneWidget);
      expect(find.text('VEGA: 60 → 70'), findsOneWidget);
      expect(find.text('Motivo: Columna'), findsNWidgets(2));
      expect(find.text('Sorteo: 2 familias'), findsOneWidget);
      expect(find.text('Mesa 50 libre: el sorteo no la da'), findsOneWidget);
      expect(find.textContaining('12/11/2026 22:40 hs · Operador'), findsOneWidget);
      // A SOSA la cambiaron en Editar alumno, sin dejar renglón.
      expect(find.text('Cambios sin registro (1)'), findsOneWidget);
      expect(find.text('SOSA, ALUMNO: hoy 15; según el registro, 12.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('deshacer_m1')));
      await tester.pumpAndSettle();
      expect(deshechos, ['m1']);
      // Al deshacer se cierra: lo que sigue es confirmar.
      expect(find.text('Historial de las mesas'), findsNothing);
    });

    testWidgets('si ya no se puede deshacer, dice por qué y no hay botón',
        (tester) async {
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(
          context: c,
          historial: historial(mesaDeVega: '80'),
          onDeshacer: (_) {},
        ),
      );
      expect(find.byKey(const Key('deshacer_m1')), findsNothing);
      expect(find.textContaining('Las mesas de VEGA cambiaron después'),
          findsOneWidget);
    });

    testWidgets('solo para leer, sin botones de deshacer', (tester) async {
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(context: c, historial: historial()),
      );
      expect(find.byKey(const Key('deshacer_m1')), findsNothing);
      // Pero dice dónde se deshace.
      expect(find.byKey(const Key('donde_se_deshace')), findsOneWidget);
      await tester.tap(find.text('CERRAR'));
      await tester.pumpAndSettle();
      expect(find.text('Historial de las mesas'), findsNothing);
    });

    // Deshacer un cambio mueve familias: sin modo jefe no se ofrece, aunque
    // quien abre el Historial le pase con qué deshacer.
    testWidgets('sin modo jefe no deja deshacer y dice por qué', (tester) async {
      final deshechos = <String>[];
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(
          context: c,
          historial: historial(),
          onDeshacer: (m) => deshechos.add(m.id),
          soloJefe: true,
        ),
      );
      expect(find.byKey(const Key('deshacer_m1')), findsNothing);
      expect(find.text('Deshacer un cambio: solo en modo jefe.'), findsOneWidget);
      // Lo demás se lee igual.
      expect(find.text('VEGA pasó a otras mesas'), findsOneWidget);
      expect(deshechos, isEmpty);
    });

    testWidgets('en modo jefe, desde la fiesta, dice dónde se deshace',
        (tester) async {
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(context: c, historial: historial()),
      );
      expect(
        find.text(
          'Para deshacer un cambio, abrí el Historial desde el Plano del salón.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('una fiesta sin nada lo dice', (tester) async {
      await _abrir<void>(
        tester,
        (c) => mostrarHistorialSorteo(
          context: c,
          historial: const HistorialSorteo(renglones: [], sinRegistro: []),
        ),
      );
      expect(find.textContaining('Todavía no se sorteó'), findsOneWidget);
    });
  });
}
