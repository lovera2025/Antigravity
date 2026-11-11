// El cartel del SORTEO, con el sorteo ya hecho (6.5.1): pregunta dónde van las
// mesas que faltan, y viene elegido "en una mesa nueva, al fondo", con el número
// que le toca a cada familia a la vista antes de sortear.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/pago_para_sorteo.dart';
import 'package:arguello_events/features/eventos/widgets/sorteo_mesas_dialog.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

const _playon = PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39.8);

ArmadoSalon _salon() => ArmarAMedida.armar(
      const OpcionesAMedida(playon: _playon, cantidad: 101),
    ).armado;

ContratoAlumno _familia(
  String id, {
  int extras = 0,
  List<int> mesas = const [],
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: '${id.toUpperCase()}, ALUMNO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: '5° A',
    );

/// Una familia en cada mesa de la 1 a la 100, menos la 9 y la 52.
List<ContratoAlumno> _sorteados() => [
      for (var n = 1; n <= 100; n++)
        if (n != 9 && n != 52) _familia('f$n', mesas: [n]),
    ];

PlanoEvento _plano(ArmadoSalon armado, {ModoSorteo modo = ModoSorteo.entera}) =>
    PlanoEvento.nuevo(
      eventoId: 'e',
      armado: armado,
      estilo: EstiloPlano.gala,
      modo: modo,
      ahora: DateTime.utc(2026, 11, 10),
    );

Future<void> _abrir(
  WidgetTester tester, {
  required List<ContratoAlumno> alumnos,
  required PlanoEvento plano,
  Map<String, PagoAlumno>? pagos,
  required void Function(SorteoMesasDialogResult?) alCerrar,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
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
                pagos: pagos ??
                    {
                      for (final a in alumnos)
                        a.id: const PagoAlumno(base: 1000, mesas: 1000),
                    },
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

bool _sePuedeSortear(WidgetTester tester) =>
    tester
        .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'SORTEAR'))
        .onPressed !=
    null;

bool _elegido(WidgetTester tester, String clave) =>
    tester.widget<ChoiceChip>(find.byKey(Key(clave))).selected;

void main() {
  final tarde = _familia('tarde', extras: 1, mesas: [9]);

  testWidgets('con el sorteo hecho, viene elegida la mesa nueva al fondo y dice '
      'qué número le toca', (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: [..._sorteados(), tarde],
      plano: _plano(_salon()),
      alCerrar: (r) => resultado = r,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('¿Dónde va la mesa que falta?'), findsOneWidget);
    expect(_elegido(tester, 'faltan_al_fondo'), isTrue);
    expect(_elegido(tester, 'faltan_en_libres'), isFalse);
    expect(
      tester.widget<Text>(find.byKey(const Key('faltan_numeros'))).data,
      '102 → TARDE',
    );
    expect(find.text('Nadie más cambia de mesa.'), findsOneWidget);
    expect(_sePuedeSortear(tester), isTrue);

    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado, isNotNull);
    expect(resultado!.mesasNuevasAlFondo, isTrue);
    expect(resultado!.modo, ModoSorteo.entera);
  });

  testWidgets('se puede elegir una mesa libre del salón, como siempre',
      (tester) async {
    SorteoMesasDialogResult? resultado;
    await _abrir(
      tester,
      alumnos: [..._sorteados(), tarde],
      plano: _plano(_salon()),
      alCerrar: (r) => resultado = r,
    );
    await tester.tap(find.byKey(const Key('faltan_en_libres')));
    await tester.pumpAndSettle();
    expect(_elegido(tester, 'faltan_en_libres'), isTrue);
    expect(find.byKey(const Key('faltan_numeros')), findsNothing);
    expect(find.byKey(const Key('faltan_en_libres_explica')), findsOneWidget);
    expect(_sePuedeSortear(tester), isTrue);

    await tester.tap(find.text('SORTEAR'));
    await tester.pumpAndSettle();
    expect(resultado!.mesasNuevasAlFondo, isFalse);

    // Y de vuelta.
    resultado = null;
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('faltan_en_libres')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('faltan_al_fondo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('faltan_numeros')), findsOneWidget);
    expect(_sePuedeSortear(tester), isTrue);
  });

  testWidgets('varias familias: los números, por orden de llegada',
      (tester) async {
    final nueva = _familia('nueva');
    final alumnos = [..._sorteados(), tarde, nueva];
    await _abrir(
      tester,
      alumnos: alumnos,
      plano: _plano(_salon()),
      pagos: {
        for (final a in alumnos)
          a.id: const PagoAlumno(base: 1000, mesas: 1000),
        'nueva': PagoAlumno(base: 1000, ultimo: DateTime.utc(2026, 11, 10, 20)),
        'tarde': PagoAlumno(
          base: 1000,
          mesas: 70000,
          ultimo: DateTime.utc(2026, 11, 10, 23),
        ),
      },
      alCerrar: (_) {},
    );
    expect(find.text('¿Dónde van las 2 mesas que faltan?'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('faltan_numeros'))).data,
      '102 → NUEVA  ·  103 → TARDE',
    );
    expect(_sePuedeSortear(tester), isTrue);
  });

  testWidgets('por división también deja sortear', (tester) async {
    await _abrir(
      tester,
      alumnos: [..._sorteados(), tarde],
      plano: _plano(_salon(), modo: ModoSorteo.bloques),
      alCerrar: (_) {},
    );
    expect(tester.takeException(), isNull);
    expect(_elegido(tester, 'faltan_al_fondo'), isTrue);
    // Con familias sentadas y sin bloques guardados se completa entero, y eso
    // se avisa (como siempre): hay que tildar que se leyó.
    expect(find.textContaining('se completa entero'), findsWidgets);
    expect(_sePuedeSortear(tester), isFalse);
    await tester.tap(find.text('Ya revisé estos casos'));
    await tester.pumpAndSettle();
    expect(_sePuedeSortear(tester), isTrue);
  });

  testWidgets('en el primer sorteo no se pregunta: todavía nadie tiene mesa',
      (tester) async {
    await _abrir(
      tester,
      alumnos: [for (var i = 0; i < 20; i++) _familia('f$i')],
      plano: _plano(_salon()),
      alCerrar: (_) {},
    );
    expect(find.byKey(const Key('faltan_donde')), findsNothing);
    expect(_sePuedeSortear(tester), isTrue);
  });

  testWidgets('en un armado del Canva no se pregunta', (tester) async {
    final canva = ArmadosPredefinidos.normal2aPagina3();
    await _abrir(
      tester,
      alumnos: [
        for (var n = 1; n <= 10; n++) _familia('f$n', mesas: [n]),
        _familia('tarde', extras: 1, mesas: [11]),
      ],
      plano: _plano(canva),
      alCerrar: (_) {},
    );
    expect(find.byKey(const Key('faltan_donde')), findsNothing);
  });

  testWidgets('a quien no pagó nada (el candado) no se le ofrece una mesa nueva',
      (tester) async {
    final sinPagar = _familia('sinpagar');
    final alumnos = [..._sorteados(), sinPagar];
    await _abrir(
      tester,
      alumnos: alumnos,
      plano: _plano(_salon()),
      pagos: {
        for (final a in alumnos)
          a.id: a.id == 'sinpagar'
              ? PagoAlumno.nada
              : const PagoAlumno(base: 1000, mesas: 1000),
      },
      alCerrar: (_) {},
    );
    expect(find.byKey(const Key('faltan_donde')), findsNothing);
    // Tildándolo para sortear igual, sí: le toca la 102.
    await tester.tap(find.textContaining('Sin nada pagado de la cuota base'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SINPAGAR, ALUMNO').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('faltan_numeros'))).data,
      '102 → SINPAGAR',
    );
  });
}
