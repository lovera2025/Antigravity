import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _a(String id, String division) => ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: 'ALUMNO $id',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      cursoDivision: division,
    );

List<ContratoAlumno> _division(String division, int n) =>
    [for (var i = 0; i < n; i++) _a('$division-$i', division)];

/// Los tamaños de los bloques de colores del jefe (páginas 4-5).
final _comoElJefe = [
  ..._division('5° A', 24),
  ..._division('5° B', 25),
  ..._division('5° C', 3),
  ..._division('5° D', 26),
  ..._division('5° E', 20),
];

/// Todos con la cuota base pagada: nadie queda afuera por pagos.
Map<String, PagoAlumno> _pagos(List<ContratoAlumno> alumnos) => {
      for (final a in alumnos) a.id: const PagoAlumno(base: 1000),
    };

PlanoEvento _plano(
  ArmadoSalon armado, {
  ModoSorteo modo = ModoSorteo.bloques,
  ConfigPlano config = const ConfigPlano(),
}) =>
    PlanoEvento.nuevo(
      eventoId: 'e',
      armado: armado,
      estilo: EstiloPlano.gala,
      modo: modo,
      ahora: DateTime.utc(2026, 9, 26),
    ).copyWith(config: config, ahora: DateTime.utc(2026, 9, 26));

Future<void> _abrir(
  WidgetTester tester, {
  required List<ContratoAlumno> alumnos,
  PlanoEvento? plano,
  required void Function(SorteoMesasDialogResult?) alCerrar,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
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

/// Si SORTEAR está habilitado. Mirar el botón y no "tocar y ver si devolvió
/// algo": un toque que no llega se confundiría con un botón apagado.
bool _sePuedeSortear(WidgetTester tester) =>
    tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SORTEAR'))
        .onPressed !=
    null;

void main() {
  testWidgets('sin plano, el diálogo es el de siempre', (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: _division('5° A', 10),
      alCerrar: (r) => resultado = r,
    );
    expect(find.text('Capacidad del salón (mesas numeradas)'), findsOneWidget);
    expect(find.textContaining('Salón:'), findsNothing);
    expect(find.text('Usar de la mesa 1 a la'), findsNothing);

    // Y devuelve lo de siempre: la capacidad, y nada del plano.
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNotNull);
    expect(resultado!.capacidadSalon, 10);
    expect(resultado!.modo, isNull);
    expect(resultado!.hastaMesa, isNull);
    expect(resultado!.usarPasto, isFalse);
  });

  testWidgets('un plano que no se puede leer: lo dice y no deja sortear',
      (tester) async {
    final roto = PlanoEvento.fromMap(
      _plano(ArmadosPredefinidos.normal2aPagina3()).toMap()
        ..['armado_json'] = '{roto',
    );
    await _abrir(
      tester,
      alumnos: _division('5° A', 10),
      plano: roto,
      alCerrar: (_) {},
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('no se puede leer'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);
    // No cae al sorteo sin plano: ignoraría las mesas fijas y libres.
    expect(find.text('Capacidad del salón (mesas numeradas)'), findsNothing);
  });

  testWidgets('por bloques, si no entran: lo marca en rojo y no deja sortear',
      (tester) async {
    await _abrir(
      tester,
      // 90 familias en un salón de 78.
      alumnos: [..._division('5° A', 45), ..._division('5° B', 45)],
      plano: _plano(ArmadosPredefinidos.normal2aPagina3()),
      alCerrar: (_) {},
    );
    expect(find.text('no entra'), findsWidgets);
    expect(find.textContaining('No entran todas las familias'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);
  });

  testWidgets('entero: una mesa que el salón no tiene no se acepta',
      (tester) async {
    await _abrir(
      tester,
      alumnos: _division('5° A', 60),
      plano: _plano(
        ArmadosPredefinidos.normal2aPagina3(),
        modo: ModoSorteo.entera,
      ),
      alCerrar: (_) {},
    );
    expect(_sePuedeSortear(tester), isTrue);
    // El salón tiene 78 mesas. Antes el 200 pasaba y se usaba la mínima sin
    // avisar.
    await tester.enterText(find.byType(TextField), '200');
    await tester.pumpAndSettle();
    expect(find.text('La mesa 200 no está en este salón.'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);

    await tester.enterText(find.byType(TextField), '78');
    await tester.pumpAndSettle();
    expect(_sePuedeSortear(tester), isTrue);
  });

  testWidgets('entero: una mesa del pasto no vale si el pasto no se usa',
      (tester) async {
    await _abrir(
      tester,
      alumnos: _division('6° A', 60),
      plano: _plano(
        ArmadosPredefinidos.tecnica1a1b(),
        modo: ModoSorteo.entera,
      ),
      alCerrar: (_) {},
    );
    await tester.enterText(find.byType(TextField), '140');
    await tester.pumpAndSettle();
    expect(find.text('La mesa 140 es del pasto.'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);
  });

  testWidgets('un aviso del plano pide tildar "ya revisé", y uno nuevo lo '
      'vuelve a pedir', (tester) async {
    await _abrir(
      tester,
      alumnos: [
        ..._division('5° A', 10),
        // Ya tiene mesa: por división no se puede, se completa entero.
        _a('ya', '5° B').copyWith(numeroMesa: '3'),
        ..._division('5° B', 10),
      ],
      plano: _plano(
        ArmadosPredefinidos.normal2aPagina3(),
        modo: ModoSorteo.entera,
      ),
      alCerrar: (_) {},
    );
    // Entero, sin avisos: se puede sortear.
    expect(find.text('Ya revisé estos casos'), findsNothing);
    expect(_sePuedeSortear(tester), isTrue);

    // Al elegir "por división" aparece el aviso de que se completa entero.
    await tester.tap(find.text('Por división, cada una junta'));
    await tester.pumpAndSettle();
    expect(find.text('Ya revisé estos casos'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);
    await tester.tap(find.text('Ya revisé estos casos'));
    await tester.pumpAndSettle();
    expect(_sePuedeSortear(tester), isTrue);

    // Vuelve a entero y otra vez a por división: el aviso reaparece y el
    // tilde de antes no vale.
    await tester.tap(find.text('Toda la escuela junta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Por división, cada una junta'));
    await tester.pumpAndSettle();
    expect(find.text('Ya revisé estos casos'), findsOneWidget);
    expect(_sePuedeSortear(tester), isFalse);
  });

  testWidgets('las flechas mueven entre las divisiones que se ven',
      (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: [..._division('5° A', 5), ..._division('5° C', 5)],
      plano: _plano(
        ArmadosPredefinidos.normal2aPagina3(),
        // El orden guardado tiene en el medio una división sin familias.
        config: const ConfigPlano(ordenDivisiones: ['5A', '5B', '5C']),
      ),
      alCerrar: (r) => resultado = r,
    );
    expect(find.text('mesas 1 a 5'), findsOneWidget);
    expect(find.byTooltip('Bajar'), findsNWidgets(2));
    // 5° A baja: queda después de 5° C, que pasa a arrancar en la 1.
    await tester.tap(find.byTooltip('Bajar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado!.ordenDivisiones, ['5C', '5A']);
  });

  testWidgets('por bloques: muestra el rango de cada división y se reordena',
      (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: _comoElJefe,
      plano: _plano(
        ArmadosPredefinidos.normal2aPaginas45(),
        config: const ConfigPlano(libres: {50: MesaLibre(), 51: MesaLibre()}),
      ),
      alCerrar: (r) => resultado = r,
    );
    expect(find.text('Salón: Normal 2A · páginas 4 y 5'), findsOneWidget);
    expect(find.text('Capacidad del salón (mesas numeradas)'), findsNothing);
    expect(find.text('mesas 1 a 24'), findsOneWidget);
    expect(find.text('mesas 52 a 54'), findsOneWidget);
    expect(find.text('mesas 81 a 100'), findsOneWidget);

    // 5° A baja un lugar: ahora 5° B arranca en la 1.
    await tester.tap(find.byTooltip('Bajar').first);
    await tester.pumpAndSettle();
    expect(find.text('mesas 1 a 25'), findsOneWidget);

    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNotNull);
    expect(resultado!.modo, ModoSorteo.bloques);
    expect(resultado!.ordenDivisiones.take(2), ['5B', '5A']);
  });

  testWidgets('entero: propone hasta qué mesa y no deja menos', (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: _division('5° A', 60),
      plano: _plano(
        ArmadosPredefinidos.normal2aPagina3(),
        modo: ModoSorteo.entera,
      ),
      alCerrar: (r) => resultado = r,
    );
    expect(find.text('Usar de la mesa 1 a la'), findsOneWidget);
    expect(find.text('Mínimo la 60 para que entre todo.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '50');
    await tester.pumpAndSettle();
    expect(find.text('Con esas mesas no entran: mínimo la 60'), findsOneWidget);
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNull, reason: 'con menos de lo mínimo no sortea');

    await tester.enterText(find.byType(TextField), '70');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado?.modo, ModoSorteo.entera);
    expect(resultado?.hastaMesa, 70);
  });

  testWidgets('si no entra sin el pasto, pide tildarlo antes de sortear',
      (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: _division('6° A', 140),
      plano: _plano(
        ArmadosPredefinidos.tecnica1a1b(),
        modo: ModoSorteo.entera,
      ),
      alCerrar: (r) => resultado = r,
    );
    final casilla = find.text('Usar las mesas del pasto (131 a 150)');
    expect(casilla, findsOneWidget);
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNull);

    await tester.tap(casilla);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado?.usarPasto, isTrue);
  });
}
