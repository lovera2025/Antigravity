// La pantalla del plano, sin base: el encabezado, el plano con zoom y regla,
// el buscador, la familia elegida, las divisiones, los avisos y los botones.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/plano_de_la_fiesta.dart';
import 'package:arguello_events/features/plano/widgets/plano_evento_cuerpo.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/plano_evento.dart';

ContratoAlumno _alumno(
  String id,
  String nombre, {
  int extras = 0,
  int sillas = 0,
  List<int> mesas = const [],
  String division = '5° A',
}) =>
    ContratoAlumno(
      id: id,
      eventoId: 'e',
      nombreAlumno: nombre,
      cantidadAcompanantes: 3,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      sillasExtraCantidad: sillas,
      sillasExtraPrecioTotal: 8000.0 * sillas,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
      cursoDivision: division,
    );

final _alumnos = [
  _alumno('gomez', 'GÓMEZ, SOFÍA', extras: 1, sillas: 3, mesas: [8, 9]),
  _alumno('sosa', 'SOSA, LUZ', mesas: [20], division: '5° B'),
  _alumno('vega', 'VEGA, ANA', extras: 1, division: '5° B'),
];

ArmadoSalon _armado({int? partirEnFila}) => ArmarAMedida.armar(
      OpcionesAMedida(
        playon: PlayonReal.costaSurubi,
        cantidad: 40,
        partirEnFila: partirEnFila,
      ),
    ).armado;

PlanoDeLaFiesta _plano({ArmadoSalon? armado, ConfigPlano config = ConfigPlano.vacia}) =>
    PlanoDeLaFiesta.desde(
      armado: armado ?? _armado(),
      config: config,
      alumnos: _alumnos,
    );

Future<void> _mostrar(
  WidgetTester tester, {
  PlanoDeLaFiesta? plano,
  String? resaltar,
  VoidCallback? onEstiloYArmado,
  VoidCallback? onPersonalizar,
  VoidCallback? onImprimir,
  VoidCallback? onHistorial,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
      home: Scaffold(
        body: PlanoEventoCuerpo(
          plano: plano ?? _plano(),
          estilo: EstiloPlano.arquitecto,
          alumnos: _alumnos,
          resaltarAlumnoId: resaltar,
          onEstiloYArmado: onEstiloYArmado,
          onPersonalizar: onPersonalizar,
          onImprimir: onImprimir,
          onHistorial: onHistorial,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// Los textos de la tarjeta de lo elegido.
List<String> _elegido(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('elegido')),
          matching: find.byType(Text),
        ),
      ))
        t.data ?? '',
    ];

VistaPlano _vista(WidgetTester tester) =>
    tester.widget<VistaPlano>(find.byType(VistaPlano));

double _zoom(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

/// Toca una mesa del plano, en su lugar de la pantalla.
Future<void> _tocarMesa(WidgetTester tester, ArmadoSalon armado, int numero) async {
  final caja = tester.getRect(find.byType(VistaPlano));
  final m = armado.mesa(numero)!;
  final punto = EncuadrePlano.de(armado.hoja(m.hoja)!.caja, caja.size)
      .aPantalla(Offset(m.x, m.y));
  await tester.tapAt(caja.topLeft + punto);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(cargarFuentesPlano);

  group('el encabezado', () {
    testWidgets('dice cómo está el salón y lo que mide', (tester) async {
      await _mostrar(tester);
      // Tres familias: 2 + 1 + 2 mesas.
      final titular = find.descendant(
        of: find.byKey(const Key('titular')),
        matching: find.byType(Text),
      );
      expect(tester.widget<Text>(titular).data, 'Entran las 5');
      expect(find.textContaining('40 mesas · ocupa '), findsOneWidget);
      expect(find.textContaining('en el playón entran hasta 284'), findsOneWidget);
      // El playón todavía no se midió con cinta.
      expect(find.text('Medidas aproximadas'), findsOneWidget);
      // La regla, siempre a la vista.
      expect(tester.widget<Text>(find.byKey(const Key('regla'))).data, endsWith(' m'));
    });

    testWidgets('con el playón medido con cinta no dice "aproximadas"',
        (tester) async {
      await _mostrar(
        tester,
        plano: _plano(
          config: const ConfigPlano(
            medidas: MedidasPlano(
              playon: PlayonReal(frenteM: 30, fondoM: 46, profundidadM: 39),
            ),
          ),
        ),
      );
      expect(find.text('Medidas aproximadas'), findsNothing);
    });
  });

  group('elegir en el plano', () {
    testWidgets('tocar la mesa de una familia la elige entera', (tester) async {
      final armado = _armado();
      await _mostrar(tester, plano: _plano(armado: armado));
      expect(find.byKey(const Key('elegido')), findsNothing);

      await _tocarMesa(tester, armado, 9);
      final textos = _elegido(tester);
      expect(textos.first, 'GÓMEZ, SOFÍA');
      expect(textos, contains('5° A · 4 personas'));
      // Tres sillas extra: dos en la principal y una en la adicional.
      expect(textos, containsAll(['Mesa 8: 10 sillas', 'Mesa 9: 9 sillas']));
      // Y cómo se ocupa la principal, igual que en la planilla del sorteo.
      // La egresada y sus 3 acompañantes cenan; la mesa tiene 10 lugares.
      expect(textos, contains('En la principal: 4 con cena · 6 generales'));
      expect(_vista(tester).resaltadas, {8, 9});
      // Corre el pulso de lo resaltado: se suelta antes de terminar.
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
      expect(find.byKey(const Key('elegido')), findsNothing);
      expect(_vista(tester).resaltadas, isEmpty);
    });

    testWidgets('una mesa vacía se elige sola', (tester) async {
      final armado = _armado();
      await _mostrar(tester, plano: _plano(armado: armado));
      await _tocarMesa(tester, armado, 30);
      expect(_elegido(tester), ['Mesa 30', 'Vacía']);
      expect(_vista(tester).seleccionada, 30);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('una fijada o una libre dicen para quién y por qué',
        (tester) async {
      final armado = _armado();
      await _mostrar(
        tester,
        plano: _plano(
          armado: armado,
          config: const ConfigPlano(
            fijadas: {
              31: MesaFijada(alumnoId: 'vega', motivo: 'Cerca del ingreso'),
            },
            libres: {32: MesaLibre(motivo: 'Columna')},
          ),
        ),
      );
      await _tocarMesa(tester, armado, 31);
      expect(_elegido(tester),
          ['Mesa 31', 'Fijada para VEGA, ANA', 'Motivo: Cerca del ingreso']);
      await _tocarMesa(tester, armado, 32);
      expect(_elegido(tester),
          ['Mesa 32', 'Se dejó libre: el sorteo no la da', 'Motivo: Columna']);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('se abre con la familia resaltada si se llega desde la grilla',
        (tester) async {
      await _mostrar(tester, resaltar: 'sosa');
      expect(_elegido(tester).first, 'SOSA, LUZ');
      expect(_vista(tester).resaltadas, {20});
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });
  });

  group('el buscador', () {
    testWidgets('por apellido, sin importar tildes ni mayúsculas', (tester) async {
      await _mostrar(tester);
      await tester.enterText(find.byKey(const Key('buscar')), 'gomez');
      await tester.pump();
      expect(find.byKey(const Key('resultado_gomez')), findsOneWidget);
      expect(find.byKey(const Key('resultado_sosa')), findsNothing);
      expect(find.text('5° A · Mesa 8-9 (1 extra)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('resultado_gomez')));
      await tester.pump();
      expect(_elegido(tester).first, 'GÓMEZ, SOFÍA');
      // Va a la mesa: queda con zoom.
      expect(_zoom(tester), greaterThan(1.5));
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('por número de mesa', (tester) async {
      await _mostrar(tester);
      await tester.enterText(find.byKey(const Key('buscar')), '20');
      await tester.pump();
      expect(find.byKey(const Key('resultado_mesa_20')), findsOneWidget);
      await tester.tap(find.byKey(const Key('resultado_mesa_20')));
      await tester.pump();
      expect(_elegido(tester).first, 'SOSA, LUZ');
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('una familia que todavía no tiene mesa', (tester) async {
      await _mostrar(tester);
      await tester.enterText(find.byKey(const Key('buscar')), 'vega');
      await tester.pump();
      expect(find.text('5° B · Todavía sin mesa'), findsOneWidget);
      await tester.tap(find.byKey(const Key('resultado_vega')));
      await tester.pump();
      expect(_elegido(tester), contains('Todavía sin mesa. Le corresponden 2.'));
      expect(_vista(tester).resaltadas, isEmpty);
    });

    testWidgets('si no hay nada, lo dice', (tester) async {
      await _mostrar(tester);
      await tester.enterText(find.byKey(const Key('buscar')), 'zzz');
      await tester.pump();
      expect(find.text('No hay ninguna familia ni mesa con "zzz".'), findsOneWidget);
    });
  });

  group('las divisiones y los avisos', () {
    testWidgets('cada división con su color y sus mesas', (tester) async {
      await _mostrar(tester);
      expect(find.text('DIVISIONES'), findsOneWidget);
      expect(find.text('5° A'), findsOneWidget);
      expect(find.text('2 mesas'), findsOneWidget);
      expect(find.text('5° B'), findsOneWidget);
      expect(find.text('1 mesa'), findsOneWidget);
    });

    testWidgets('un aviso se toca y lleva a su mesa', (tester) async {
      await _mostrar(tester);
      // Las dos mesas de GÓMEZ llevan sillas extra y aprietan contra sus
      // vecinas: un aviso por mesa, no uno por vecina.
      expect(find.text('AVISOS (2)'), findsOneWidget);
      expect(find.textContaining('La mesa 8 lleva 10 sillas'), findsOneWidget);
      expect(find.textContaining('La mesa 9 lleva 9 sillas'), findsOneWidget);
      await tester.tap(find.byKey(const Key('aviso_0')));
      await tester.pump();
      expect(_elegido(tester).first, 'GÓMEZ, SOFÍA');
      expect(_zoom(tester), greaterThan(1.5));
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('sin avisos no aparece la sección', (tester) async {
      await _mostrar(
        tester,
        plano: PlanoDeLaFiesta.desde(
          armado: _armado(),
          config: ConfigPlano.vacia,
          alumnos: [_alumnos[1]],
        ),
      );
      expect(find.text('AVISO'), findsNothing);
      expect(find.textContaining('AVISOS'), findsNothing);
    });
  });

  group('el zoom y las hojas', () {
    testWidgets('acercar, alejar y ajustar', (tester) async {
      await _mostrar(tester);
      expect(_zoom(tester), closeTo(1, 1e-9));
      final regla = tester.getSize(find.byKey(const Key('regla')));
      expect(regla.width, greaterThan(0));

      await tester.tap(find.byKey(const Key('acercar')));
      await tester.pump();
      expect(_zoom(tester), closeTo(1.5, 1e-6));
      await tester.tap(find.byKey(const Key('acercar')));
      await tester.pump();
      expect(_zoom(tester), closeTo(2.25, 1e-6));
      await tester.tap(find.byKey(const Key('alejar')));
      await tester.pump();
      expect(_zoom(tester), closeTo(1.5, 1e-6));
      await tester.tap(find.byKey(const Key('ajustar')));
      await tester.pump();
      expect(_zoom(tester), closeTo(1, 1e-9));
      // Alejar desde el encuadre no achica el plano.
      await tester.tap(find.byKey(const Key('alejar')));
      await tester.pump();
      expect(_zoom(tester), closeTo(1, 1e-9));
    });

    testWidgets('con dos hojas se cambia de una a otra', (tester) async {
      final armado = _armado(partirEnFila: 2);
      await _mostrar(tester, plano: _plano(armado: armado));
      expect(_vista(tester).hoja, 'A');
      await tester.tap(find.text('Al fondo'));
      await tester.pump();
      expect(_vista(tester).hoja, 'B');
    });

    testWidgets('con una sola hoja no hay nada que elegir', (tester) async {
      await _mostrar(tester);
      expect(find.byKey(const Key('hojas')), findsNothing);
    });

    testWidgets('ir a una mesa de la otra hoja cambia de hoja', (tester) async {
      final armado = _armado(partirEnFila: 2);
      await _mostrar(tester, plano: _plano(armado: armado));
      expect(armado.mesa(20)!.hoja, 'B');
      await tester.enterText(find.byKey(const Key('buscar')), 'sosa');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_sosa')));
      await tester.pump();
      expect(_vista(tester).hoja, 'B');
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });
  });

  group('los botones', () {
    testWidgets('solo aparecen los que tienen acción', (tester) async {
      var estilo = 0;
      await _mostrar(tester, onEstiloYArmado: () => estilo++);
      expect(find.byKey(const Key('personalizar')), findsNothing);
      expect(find.byKey(const Key('imprimir')), findsNothing);
      expect(find.byKey(const Key('historial')), findsNothing);
      await tester.tap(find.byKey(const Key('estilo_y_armado')));
      expect(estilo, 1);
    });

    testWidgets('con todas las acciones, los cuatro', (tester) async {
      final tocados = <String>[];
      await _mostrar(
        tester,
        onEstiloYArmado: () => tocados.add('estilo'),
        onPersonalizar: () => tocados.add('personalizar'),
        onImprimir: () => tocados.add('imprimir'),
        onHistorial: () => tocados.add('historial'),
      );
      for (final k in ['estilo_y_armado', 'personalizar', 'imprimir', 'historial']) {
        await tester.tap(find.byKey(Key(k)));
      }
      expect(tocados, ['estilo', 'personalizar', 'imprimir', 'historial']);
    });
  });

  for (final e in EstiloPlano.values) {
    testWidgets('${e.name}: se dibuja sin desbordar en una pantalla chica',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: FuentesPlano.linea, useMaterial3: true),
          home: Scaffold(
            body: PlanoEventoCuerpo(
              plano: _plano(armado: _armado(partirEnFila: 2)),
              estilo: e,
              alumnos: _alumnos,
              mostrarLugares: true,
              onEstiloYArmado: () {},
              onPersonalizar: () {},
              onImprimir: () {},
              onHistorial: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
