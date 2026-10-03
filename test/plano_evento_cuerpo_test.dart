// La pantalla del plano, sin base: el encabezado, el plano con zoom y regla,
// el buscador, la familia elegida, las divisiones, los avisos y los botones.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/plano/dibujo/pintor_plano.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/estilos/fuentes_plano.dart';
import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/colores_y_textos.dart';
import 'package:arguello_events/features/plano/services/editar_armado.dart';
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

/// Otra familia de dos mesas: con GÓMEZ sí puede cambiar de lugar.
final _ruiz = _alumno('ruiz', 'RUIZ, TOMÁS',
    extras: 1, mesas: [25, 26], division: '5° B');

PlanoDeLaFiesta _plano({
  ArmadoSalon? armado,
  ConfigPlano config = ConfigPlano.vacia,
  List<ContratoAlumno>? alumnos,
}) =>
    PlanoDeLaFiesta.desde(
      armado: armado ?? _armado(),
      config: config,
      alumnos: alumnos ?? _alumnos,
    );

Future<void> _mostrar(
  WidgetTester tester, {
  PlanoDeLaFiesta? plano,
  List<ContratoAlumno>? alumnos,
  String? resaltar,
  bool ocupado = false,
  VoidCallback? onEstiloYArmado,
  AccionesPlano? acciones,
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
          plano: plano ?? _plano(alumnos: alumnos),
          estilo: EstiloPlano.arquitecto,
          alumnos: alumnos ?? _alumnos,
          resaltarAlumnoId: resaltar,
          ocupado: ocupado,
          onEstiloYArmado: onEstiloYArmado,
          acciones: acciones,
          onImprimir: onImprimir,
          onHistorial: onHistorial,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// Las acciones de Personalizar, anotando en [tocados] lo que se pidió.
AccionesPlano _acciones(
  List<String> tocados, {
  List<MedidasPlano>? medidas,
  List<ColoresYTextos>? colores,
  List<(ArmadoSalon, ArmadoSalon)>? salon,
}) =>
    AccionesPlano(
      onGuardarMedidas: medidas?.add,
      onGuardarColoresYTextos: colores?.add,
      onGuardarArmado: salon == null ? null : (b, n) => salon.add((b, n)),
      onFijarEnMesa: (m) => tocados.add('fijar en $m'),
      onFijar: (a, m) => tocados.add('fijar $a desde $m'),
      onQuitarFijadas: (a) => tocados.add('quitar fijadas de $a'),
      onQuitarFijadaDeMesa: (m) => tocados.add('quitar fijada de la $m'),
      onDejarLibre: (m) => tocados.add('libre $m'),
      onVolverAUsar: (m) => tocados.add('usar $m'),
      onCambiar: (a, b) => tocados.add('cambiar $a con $b'),
      onMover: (a, m) => tocados.add('mover $a a $m'),
    );

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

/// Dónde está una mesa en la pantalla, según el armado que se está dibujando.
Offset _enPantalla(WidgetTester tester, int numero) {
  final vista = _vista(tester);
  final caja = tester.getRect(find.byType(VistaPlano));
  final m = vista.armado.mesa(numero)!;
  return caja.topLeft +
      EncuadrePlano.de(vista.armado.hoja(m.hoja)!.caja, caja.size)
          .aPantalla(Offset(m.x, m.y));
}

/// Arrastra una mesa [metros] para un lado (x, y), como con el mouse.
Future<void> _arrastrarMesa(
  WidgetTester tester,
  int numero,
  Offset metros,
) async {
  final vista = _vista(tester);
  final caja = tester.getRect(find.byType(VistaPlano));
  final m = vista.armado.mesa(numero)!;
  final escala =
      EncuadrePlano.de(vista.armado.hoja(m.hoja)!.caja, caja.size).escala;
  final gesto = await tester.startGesture(_enPantalla(tester, numero));
  await tester.pump();
  final total = metros * vista.armado.aUnidades(1) * escala;
  for (var i = 0; i < 4; i++) {
    await gesto.moveBy(total / 4);
    await tester.pump();
  }
  await gesto.up();
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

  group('personalizar las mesas', () {
    Future<void> prender(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
    }

    String franja(WidgetTester tester) => tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('franja_personalizar')),
          matching: find.byType(Text),
        ))
        .first
        .data!;

    testWidgets('apagado, la pantalla solo muestra: no hay nada que tocar',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester, plano: _plano(armado: armado), acciones: _acciones([]));
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
      await _tocarMesa(tester, armado, 30);
      expect(find.byKey(const Key('accion_dejar_libre')), findsNothing);
      await _tocarMesa(tester, armado, 8);
      expect(find.byKey(const Key('accion_mover')), findsNothing);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('sin acciones no hay botón PERSONALIZAR', (tester) async {
      await _mostrar(tester, onEstiloYArmado: () {});
      expect(find.byKey(const Key('personalizar')), findsNothing);
    });

    testWidgets('una mesa vacía se puede fijar o dejar libre', (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      expect(franja(tester),
          'Personalizar las mesas: tocá una mesa o buscá una familia.');
      await _tocarMesa(tester, armado, 30);
      await tester.tap(find.byKey(const Key('accion_fijar_en_mesa')));
      await tester.tap(find.byKey(const Key('accion_dejar_libre')));
      expect(tocados, ['fijar en 30', 'libre 30']);
      // De una mesa vacía no se mueve ni se cambia nada.
      expect(find.byKey(const Key('accion_mover')), findsNothing);
    });

    testWidgets('mover: se elige la familia y después la mesa a donde va',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      expect(
        franja(tester),
        'Tocá la primera mesa para GÓMEZ: va a esa y a las que le siguen '
        '(2 seguidas y libres).',
      );
      await _tocarMesa(tester, armado, 30);
      expect(tocados, ['mover gomez a 30']);
      // Ya no espera nada.
      expect(franja(tester), startsWith('Personalizar las mesas'));
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('cambiar: hay que tocar una mesa de otra familia',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      final todos = [..._alumnos, _ruiz];
      await _mostrar(tester,
          plano: _plano(armado: armado, alumnos: todos),
          alumnos: todos,
          acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_cambiar')));
      await tester.pump();
      expect(franja(tester),
          'Tocá una mesa de la familia con la que cambia GÓMEZ, o buscala.');

      // Una vacía y la suya no sirven: lo dice y sigue esperando.
      await _tocarMesa(tester, armado, 30);
      expect(tester.widget<Text>(find.byKey(const Key('pista'))).data,
          'En esa mesa no hay ninguna familia. Para pasar a una mesa vacía '
          'usá Mover.');
      await _tocarMesa(tester, armado, 9);
      expect(tester.widget<Text>(find.byKey(const Key('pista'))).data,
          contains('su propia mesa'));
      // SOSA tiene una sola mesa: con ella no puede cambiar. Lo dice y sigue
      // esperando.
      await _tocarMesa(tester, armado, 20);
      expect(tester.widget<Text>(find.byKey(const Key('pista'))).data,
          contains('tienen que tener la misma cantidad'));
      expect(tocados, isEmpty);

      await _tocarMesa(tester, armado, 25);
      expect(tocados, ['cambiar gomez con ruiz']);
      expect(find.byKey(const Key('pista')), findsNothing);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('cambiar: la otra familia también se puede buscar',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      final todos = [..._alumnos, _ruiz];
      await _mostrar(tester,
          plano: _plano(armado: armado, alumnos: todos),
          alumnos: todos,
          acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_cambiar')));
      await tester.pump();
      // Ella misma no sirve: lo dice.
      await tester.enterText(find.byKey(const Key('buscar')), 'gomez');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_gomez')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('pista'))).data,
          'Es la misma familia: elegí otra.');
      await tester.enterText(find.byKey(const Key('buscar')), 'ruiz');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_ruiz')));
      await tester.pump();
      expect(tocados, ['cambiar gomez con ruiz']);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('mover a un lugar que no sirve: dice por qué y sigue esperando',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      // La 19 y la 20: la 20 es de SOSA.
      await _tocarMesa(tester, armado, 19);
      expect(tocados, isEmpty);
      expect(tester.widget<Text>(find.byKey(const Key('pista'))).data,
          startsWith('La mesa 20 es de SOSA'));
      expect(franja(tester), startsWith('Tocá la primera mesa para GÓMEZ'));
      // "Elegí otra" es tocar otra, sin empezar de nuevo.
      await _tocarMesa(tester, armado, 30);
      expect(tocados, ['mover gomez a 30']);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('mientras se espera, un aviso lleva a su mesa y no mueve a nadie',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 20);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      // El aviso de la mesa 8 (lleva diez sillas): se toca para ir a verla.
      await tester.tap(find.byKey(const Key('aviso_0')));
      await tester.pump();
      expect(tocados, isEmpty);
      expect(franja(tester), 'Tocá la mesa libre a donde va SOSA.');
      expect(_elegido(tester).first, 'SOSA, LUZ');
      expect(_zoom(tester), greaterThan(1.5));
      // Lo mismo buscando una mesa por número.
      await tester.enterText(find.byKey(const Key('buscar')), '30');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_mesa_30')));
      await tester.pump();
      expect(tocados, isEmpty);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('mientras se muda a una, buscar a otra no cambia a quién se muda',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('buscar')), 'sosa');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_sosa')));
      await tester.pump();
      // La tarjeta y la franja siguen hablando de GÓMEZ.
      expect(_elegido(tester).first, 'GÓMEZ, SOFÍA');
      expect(franja(tester), startsWith('Tocá la primera mesa para GÓMEZ'));
      await _tocarMesa(tester, armado, 30);
      expect(tocados, ['mover gomez a 30']);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('salir de Personalizar con algo a medias lo cancela',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      // El botón de abajo, que ahora dice SALIR DE PERSONALIZAR.
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
      await _tocarMesa(tester, armado, 30);
      expect(tocados, isEmpty);
      expect(_elegido(tester).first, 'Mesa 30');
    });

    testWidgets('si la familia que se estaba mudando ya no está, deja de esperar',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      final acciones = _acciones(tocados);
      await _mostrar(tester, plano: _plano(armado: armado), acciones: acciones);
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      expect(find.byKey(const Key('cancelar_espera')), findsOneWidget);

      // Baja un cambio de la otra PC: GÓMEZ ya no está en la fiesta.
      final sinGomez = [_alumnos[1], _alumnos[2]];
      await _mostrar(
        tester,
        plano: _plano(armado: armado, alumnos: sinGomez),
        alumnos: sinGomez,
        acciones: acciones,
      );
      expect(find.byKey(const Key('cancelar_espera')), findsNothing);
      expect(find.byKey(const Key('salir_personalizar')), findsOneWidget);
      await _tocarMesa(tester, armado, 30);
      expect(tocados, isEmpty);
    });

    testWidgets('mientras se guarda se ve, y no se puede empezar otro cambio',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      final acciones = _acciones(tocados);
      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: acciones,
          onEstiloYArmado: () => tocados.add('estilo'));
      await prender(tester);
      await _tocarMesa(tester, armado, 30);
      expect(find.byKey(const Key('guardando')), findsNothing);

      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: acciones,
          ocupado: true,
          onEstiloYArmado: () => tocados.add('estilo'));
      expect(find.byKey(const Key('guardando')), findsOneWidget);
      // Los botones siguen en su lugar, apagados.
      await tester.tap(find.byKey(const Key('accion_dejar_libre')),
          warnIfMissed: false);
      await tester.tap(find.byKey(const Key('estilo_y_armado')),
          warnIfMissed: false);
      expect(tocados, isEmpty);
    });

    testWidgets('una familia sin mesa dice cuáles tiene fijadas', (tester) async {
      final armado = _armado();
      await _mostrar(
        tester,
        plano: _plano(
          armado: armado,
          config: const ConfigPlano(fijadas: {
            31: MesaFijada(alumnoId: 'vega'),
            32: MesaFijada(alumnoId: 'vega'),
          }),
        ),
        acciones: _acciones([]),
      );
      await prender(tester);
      await tester.enterText(find.byKey(const Key('buscar')), 'vega');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_vega')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('fijadas_de_la_familia'))).data,
        'Tiene fijadas la 31 y la 32.',
      );
      expect(find.text('Fijarle otras mesas'), findsOneWidget);
      expect(find.text('Quitar sus mesas fijadas'), findsOneWidget);
    });

    testWidgets('una baja que conserva su mesa se ve, y no se la toca',
        (tester) async {
      final armado = _armado();
      final conBaja = [
        ..._alumnos,
        _alumno('paz', '[BAJA] PAZ, IVÁN', mesas: [33]),
      ];
      await _mostrar(tester,
          plano: _plano(armado: armado, alumnos: conBaja),
          alumnos: conBaja,
          acciones: _acciones([]));
      await prender(tester);
      await _tocarMesa(tester, armado, 33);
      expect(_elegido(tester).first, '[BAJA] PAZ, IVÁN');
      expect(find.textContaining('Está de baja y conserva su mesa'), findsOneWidget);
      expect(find.byKey(const Key('accion_mover')), findsNothing);
      expect(find.byKey(const Key('accion_cambiar')), findsNothing);
      await tester.tap(find.byKey(const Key('soltar')));
      await tester.pump();
    });

    testWidgets('se puede cancelar lo que se estaba por hacer', (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await _tocarMesa(tester, armado, 8);
      await tester.tap(find.byKey(const Key('accion_mover')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancelar_espera')));
      await tester.pump();
      // Ahora tocar una mesa la elige, no mueve a nadie.
      await _tocarMesa(tester, armado, 30);
      expect(tocados, isEmpty);
      expect(_elegido(tester).first, 'Mesa 30');
    });

    testWidgets('a una familia sin mesa se le fijan desde donde se toca',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await tester.enterText(find.byKey(const Key('buscar')), 'vega');
      await tester.pump();
      await tester.tap(find.byKey(const Key('resultado_vega')));
      await tester.pump();
      // Sin mesa no hay qué mover ni qué cambiar.
      expect(find.byKey(const Key('accion_mover')), findsNothing);
      expect(find.byKey(const Key('accion_quitar_fijada')), findsNothing);
      await tester.tap(find.byKey(const Key('accion_fijar')));
      await tester.pump();
      expect(franja(tester),
          'Tocá la mesa donde empieza VEGA: se le fijan 2 mesas seguidas.');
      await _tocarMesa(tester, armado, 31);
      expect(tocados, ['fijar vega desde 31']);
    });

    testWidgets('una libre vuelve a usarse; una fijada se puede quitar',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(
        tester,
        plano: _plano(
          armado: armado,
          config: const ConfigPlano(
            fijadas: {
              31: MesaFijada(alumnoId: 'vega'),
              32: MesaFijada(alumnoId: 'vega'),
              // Para una familia que ya no está en la fiesta.
              35: MesaFijada(alumnoId: 'fantasma'),
            },
            libres: {34: MesaLibre()},
          ),
        ),
        acciones: _acciones(tocados),
      );
      await prender(tester);
      await _tocarMesa(tester, armado, 34);
      await tester.tap(find.byKey(const Key('accion_volver_a_usar')));
      await _tocarMesa(tester, armado, 31);
      await tester.tap(find.byKey(const Key('accion_quitar_fijada')));
      await _tocarMesa(tester, armado, 35);
      // No se dibuja como fijada, pero lo está: no se puede fijar ni dejar
      // libre hasta quitarla.
      expect(find.byKey(const Key('accion_dejar_libre')), findsNothing);
      await tester.tap(find.byKey(const Key('accion_quitar_fijada')));
      expect(tocados, [
        'usar 34',
        'quitar fijadas de vega',
        'quitar fijada de la 35',
      ]);
    });

    testWidgets('LISTO apaga Personalizar y lo que se estaba por hacer',
        (tester) async {
      final tocados = <String>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones(tocados));
      await prender(tester);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
      await _tocarMesa(tester, armado, 30);
      expect(find.byKey(const Key('accion_dejar_libre')), findsNothing);
      expect(tocados, isEmpty);
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
        acciones: _acciones(tocados),
        onImprimir: () => tocados.add('imprimir'),
        onHistorial: () => tocados.add('historial'),
      );
      for (final k in ['estilo_y_armado', 'imprimir', 'historial']) {
        await tester.tap(find.byKey(Key(k)));
      }
      expect(tocados, ['estilo', 'imprimir', 'historial']);
      expect(find.byKey(const Key('personalizar')), findsOneWidget);
    });
  });

  group('personalizar: las pestañas y Medidas', () {
    Future<void> abrirMedidas(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pestana_medidas')));
      await tester.pump();
    }

    String texto(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('texto_personalizar')))
        .data!;

    testWidgets('sin con qué guardar medidas no hay pestañas: queda como antes',
        (tester) async {
      await _mostrar(tester, acciones: _acciones([]));
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsOneWidget);
      expect(find.byKey(const Key('pestanas_personalizar')), findsNothing);
    });

    testWidgets('Personalizar abre en Mesas, y Medidas cambia el panel',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], medidas: []));
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('pestanas_personalizar')), findsOneWidget);
      expect(texto(tester), startsWith('Personalizar las mesas'));
      expect(find.byKey(const Key('buscar')), findsOneWidget);
      expect(find.byKey(const Key('panel_medidas')), findsNothing);
      expect(_vista(tester).lugares, isNull);

      await tester.tap(find.byKey(const Key('pestana_medidas')));
      await tester.pump();
      expect(texto(tester), startsWith('Los lados del playón'));
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(find.byKey(const Key('buscar')), findsNothing);
      // El plano muestra el lugar de cada mesa, y no se elige nada.
      expect(_vista(tester).lugares, const MedidasPlano());
      expect(_vista(tester).onTapMesa, isNull);

      // De vuelta en Mesas, todo como estaba.
      await tester.tap(find.byKey(const Key('pestana_mesas')));
      await tester.pump();
      expect(find.byKey(const Key('buscar')), findsOneWidget);
      expect(_vista(tester).lugares, isNull);
      await _tocarMesa(tester, armado, 30);
      expect(find.byKey(const Key('accion_dejar_libre')), findsOneWidget);
    });

    testWidgets('lo que se escribe se ve en el plano antes de guardar',
        (tester) async {
      await _mostrar(tester, acciones: _acciones([], medidas: []));
      await abrirMedidas(tester);
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      expect(_vista(tester).lugares!.lugarMesaM, 2.4);
      // Algo que no sirve no se dibuja: vuelve a lo guardado.
      await tester.enterText(find.byKey(const Key('medida_lugar')), '9');
      await tester.pump();
      expect(_vista(tester).lugares, const MedidasPlano());
    });

    testWidgets('con medidas sin guardar no se sale ni se cambia de pestaña',
        (tester) async {
      final guardadas = <MedidasPlano>[];
      await _mostrar(tester, acciones: _acciones([], medidas: guardadas));
      await abrirMedidas(tester);
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();

      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('pista'))).data,
        'Hay medidas sin guardar: tocá GUARDAR MEDIDAS o DESCARTAR.',
      );
      await tester.tap(find.byKey(const Key('pestana_mesas')));
      await tester.pump();
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      // El botón de abajo tampoco saca.
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(guardadas, isEmpty);

      // Descartando, se sale.
      await tester.tap(find.byKey(const Key('descartar_medidas')));
      await tester.pump();
      expect(find.byKey(const Key('pista')), findsNothing);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
    });

    testWidgets('GUARDAR avisa las medidas; al llegar guardadas, sigue en '
        'Medidas y ya no hay nada pendiente', (tester) async {
      final guardadas = <MedidasPlano>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: _acciones([], medidas: guardadas));
      await abrirMedidas(tester);
      await tester.enterText(find.byKey(const Key('medida_lugar')), '2,4');
      await tester.pump();
      await tester.tap(find.byKey(const Key('guardar_medidas')));
      await tester.pump();
      expect(guardadas.single.lugarMesaM, 2.4);

      // La pantalla vuelve con lo guardado.
      await _mostrar(
        tester,
        plano: _plano(
          armado: armado,
          config: ConfigPlano(medidas: guardadas.single),
        ),
        acciones: _acciones([], medidas: guardadas),
      );
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(find.text('MEDIDAS GUARDADAS'), findsOneWidget);
      expect(_vista(tester).lugares!.lugarMesaM, 2.4);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
    });

    testWidgets('si el salón quedó armado a otra distancia, lo dice y lleva a '
        'armarlo de nuevo', (tester) async {
      var abrio = 0;
      final sinMesa = [_alumno('vega', 'VEGA, ANA', extras: 1)];
      await _mostrar(
        tester,
        alumnos: sinMesa,
        plano: _plano(
          alumnos: sinMesa,
          config: const ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.5)),
        ),
        acciones: _acciones([], medidas: []),
        onEstiloYArmado: () => abrio++,
      );
      await abrirMedidas(tester);
      final aviso = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('aviso_medidas')),
            matching: find.byType(Text),
          ))
          .first
          .data!;
      expect(aviso, contains('El salón está armado a 2 m entre mesas'));
      expect(aviso, contains('la medida guardada es 2,5 m'));
      expect(aviso, contains('ESTILO Y ARMADO → A medida del playón'));
      await tester.ensureVisible(find.byKey(const Key('accion_aviso_medidas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accion_aviso_medidas')));
      expect(abrio, 1);
    });

    testWidgets('con familias ya sentadas no ofrece armar de nuevo',
        (tester) async {
      await _mostrar(
        tester,
        plano: _plano(
          config: const ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.5)),
        ),
        acciones: _acciones([], medidas: []),
        onEstiloYArmado: () {},
      );
      await abrirMedidas(tester);
      final aviso = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('aviso_medidas')),
            matching: find.byType(Text),
          ))
          .first
          .data!;
      expect(aviso, contains('Ya hay familias con mesa'));
      expect(find.byKey(const Key('accion_aviso_medidas')), findsNothing);
    });

    testWidgets('un armado del Canva no lleva ese aviso', (tester) async {
      await _mostrar(
        tester,
        plano: _plano(
          armado: ArmadosPredefinidos.normal2aPagina3(),
          config: const ConfigPlano(medidas: MedidasPlano(lugarMesaM: 2.5)),
        ),
        acciones: _acciones([], medidas: []),
      );
      await abrirMedidas(tester);
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      expect(find.byKey(const Key('aviso_medidas')), findsNothing);
    });

    testWidgets('si se redibuja el hormigón, sigue en Medidas con el zoom en '
        'su lugar', (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], medidas: []));
      await abrirMedidas(tester);
      await tester.tap(find.byKey(const Key('acercar')));
      await tester.pump();
      expect(_zoom(tester), greaterThan(1));

      const nuevo = PlayonReal(frenteM: 34, fondoM: 52, profundidadM: 45);
      await _mostrar(
        tester,
        plano: _plano(
          armado: ArmarAMedida.conPlayon(armado, nuevo),
          config: const ConfigPlano(medidas: MedidasPlano(playon: nuevo)),
        ),
        acciones: _acciones([], medidas: []),
      );
      expect(find.byKey(const Key('panel_medidas')), findsOneWidget);
      // La hoja cambió de tamaño: el zoom de antes ya no apunta a lo mismo.
      expect(_zoom(tester), 1);
    });
  });

  group('personalizar: Colores y textos', () {
    Future<void> abrirColores(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pestana_colores')));
      await tester.pump();
    }

    testWidgets('la pestaña aparece si hay con qué guardar, al lado de las '
        'otras', (tester) async {
      await _mostrar(tester, acciones: _acciones([], medidas: []));
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('pestana_medidas')), findsOneWidget);
      expect(find.byKey(const Key('pestana_colores')), findsNothing);

      await _mostrar(tester, acciones: _acciones([], medidas: [], colores: []));
      expect(find.byKey(const Key('pestana_colores')), findsOneWidget);
    });

    testWidgets('lista las divisiones de la fiesta: las de la leyenda y las '
        'que todavía no tienen mesa', (tester) async {
      final alumnos = [
        ..._alumnos,
        _alumno('paz', 'PAZ, LEO', division: '6° A'),
        _alumno('rey', 'REY, EMA', division: '4° C'),
      ];
      await _mostrar(tester,
          alumnos: alumnos, acciones: _acciones([], colores: []));
      await abrirColores(tester);
      expect(find.byKey(const Key('panel_colores')), findsOneWidget);
      expect(find.byKey(const Key('buscar')), findsNothing);
      // 5° A y 5° B ya tienen mesa: van primero, con su color marcado. Las
      // otras dos, después, en orden.
      final nombres = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('panel_colores')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .where((t) => t != null && t.contains('°'))
          .toList();
      expect(nombres, ['5° A', '5° B', '4° C', '6° A']);
      expect(_vista(tester).onTapMesa, isNull);
    });

    testWidgets('el color elegido se ve en el plano y en la leyenda antes de '
        'guardar', (tester) async {
      final guardados = <ColoresYTextos>[];
      await _mostrar(tester, acciones: _acciones([], colores: guardados));
      expect(_vista(tester).tema.colorDivision(0),
          TemaPlano.arquitecto.divisiones[0]);
      await abrirColores(tester);
      await tester.tap(find.byKey(const Key('color_5A_5')));
      await tester.pump();
      expect(_vista(tester).tema.colorDivision(0),
          TemaPlano.arquitecto.divisiones[5]);
      // La otra división no cambió.
      expect(_vista(tester).tema.colorDivision(1),
          TemaPlano.arquitecto.divisiones[1]);
      expect(guardados, isEmpty);

      // Sin guardar no se sale.
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('panel_colores')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('pista'))).data,
        'Hay colores o textos sin guardar: tocá GUARDAR o DESCARTAR.',
      );

      await tester.tap(find.byKey(const Key('guardar_colores')));
      await tester.pump();
      expect(guardados.single.colores, {'5A': 5});
    });

    testWidgets('con lo guardado, el plano y la leyenda llevan ese color, '
        'también fuera de Personalizar', (tester) async {
      await _mostrar(
        tester,
        plano: _plano(config: const ConfigPlano(colores: {'5B': 6})),
        acciones: _acciones([], colores: []),
      );
      expect(_vista(tester).tema.colorDivision(0),
          TemaPlano.arquitecto.divisiones[0]);
      expect(_vista(tester).tema.colorDivision(1),
          TemaPlano.arquitecto.divisiones[6]);
    });

    testWidgets('el título y el subtítulo se ven arriba, y mientras se '
        'escriben', (tester) async {
      await _mostrar(tester, acciones: _acciones([], colores: []));
      expect(find.byKey(const Key('titulo_del_plano')), findsNothing);
      await abrirColores(tester);
      await tester.enterText(
          find.byKey(const Key('texto_titulo')), 'Egresados 2026');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('titulo_del_plano')),
          matching: find.text('Egresados 2026'),
        ),
        findsOneWidget,
      );

      await _mostrar(
        tester,
        plano: _plano(
          config: const ConfigPlano(
            titulo: 'Egresados 2026',
            subtitulo: 'Costa Surubí',
          ),
        ),
        acciones: _acciones([], colores: []),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('titulo_del_plano')),
          matching: find.text('Costa Surubí'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('el texto de un sector se ve en el plano mientras se escribe, '
        'y las mesas no se mueven', (tester) async {
      final guardados = <ColoresYTextos>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: _acciones([], colores: guardados));
      await abrirColores(tester);
      final i = armado.sectores
          .indexWhere((s) => s.tipo == TipoSector.escenario);
      await tester.ensureVisible(find.byKey(Key('texto_sector_$i')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(Key('texto_sector_$i')), 'Escenario Mayor');
      await tester.pump();
      final visto = _vista(tester).armado;
      expect(visto.sectores[i].texto, 'Escenario Mayor');
      expect(visto.sectores[i].caja, armado.sectores[i].caja);
      expect(visto.numeros, armado.numeros);

      await tester.tap(find.byKey(const Key('guardar_colores')));
      await tester.pump();
      expect(guardados.single.sectores.single.texto, 'Escenario Mayor');
      expect(
        identical(guardados.single.sectores.single.sector, armado.sectores[i]),
        isTrue,
      );
    });

    testWidgets('al llegar guardado, sigue en la pestaña y ya no hay nada '
        'pendiente', (tester) async {
      final guardados = <ColoresYTextos>[];
      await _mostrar(tester, acciones: _acciones([], colores: guardados));
      await abrirColores(tester);
      await tester.tap(find.byKey(const Key('color_5A_5')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('guardar_colores')));
      await tester.pump();

      await _mostrar(
        tester,
        plano: _plano(config: const ConfigPlano(colores: {'5A': 5})),
        acciones: _acciones([], colores: guardados),
      );
      expect(find.byKey(const Key('panel_colores')), findsOneWidget);
      expect(find.text('GUARDADO'), findsOneWidget);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
      // Y el color queda.
      expect(_vista(tester).tema.colorDivision(0),
          TemaPlano.arquitecto.divisiones[5]);
    });
  });

  group('personalizar: Acomodar', () {
    // Una mesa vacía de la última fila: correrla hacia el fondo no la deja
    // encima de ninguna otra.
    final fondo = () {
      final a = _armado();
      final libres = a.mesas.where((m) => !{8, 9, 20}.contains(m.numero));
      final abajo = libres.map((m) => m.y).reduce((x, y) => x > y ? x : y);
      return libres.firstWhere((m) => m.y == abajo).numero;
    }();

    Future<void> abrir(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('pestana_acomodar')));
      await tester.pump();
    }

    String texto(WidgetTester tester, String clave) =>
        tester.widget<Text>(find.byKey(Key(clave))).data!;

    String elegido(WidgetTester tester) => tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('elegido_acomodar')),
          matching: find.byType(Text),
        ))
        .first
        .data!;

    bool prendido(WidgetTester tester, String clave) =>
        tester.widget<ButtonStyleButton>(find.byKey(Key(clave))).onPressed !=
        null;

    testWidgets('la pestaña va segunda, y abre con el salón como está',
        (tester) async {
      final armado = _armado();
      await _mostrar(
        tester,
        plano: _plano(armado: armado),
        acciones: _acciones([], medidas: [], colores: [], salon: []),
      );
      await tester.tap(find.byKey(const Key('personalizar')));
      await tester.pump();
      final pestanas = tester
          .widget<SegmentedButton<ModoPersonalizar>>(
              find.byKey(const Key('pestanas_personalizar')))
          .segments
          .map((s) => s.value)
          .toList();
      expect(pestanas, ModoPersonalizar.values);

      await tester.tap(find.byKey(const Key('pestana_acomodar')));
      await tester.pump();
      expect(find.byKey(const Key('panel_acomodar')), findsOneWidget);
      expect(find.byKey(const Key('buscar')), findsNothing);
      expect(elegido(tester), startsWith('Tocá una mesa'));
      // Se ve el lugar que pide cada mesa, y no hay nada para guardar.
      expect(_vista(tester).lugares, const MedidasPlano());
      expect(identical(_vista(tester).armado, armado), isTrue);
      expect(prendido(tester, 'guardar_acomodo'), isFalse);
      expect(find.text('SALÓN GUARDADO'), findsOneWidget);
      expect(find.byKey(const Key('descartar_acomodo')), findsNothing);
      expect(prendido(tester, 'acomodar_sacar'), isFalse);
      expect(prendido(tester, 'acomodar_deshacer'), isFalse);
    });

    testWidgets('apretar una mesa la elige y dice si se puede sacar',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      await tester.tapAt(_enPantalla(tester, 30));
      await tester.pump();
      expect(elegido(tester), 'Mesa 30 · vacía');
      // Y a cuánto está de las tres más cercanas.
      expect(texto(tester, 'detalle_acomodar'), startsWith('A 2 m de la '));
      await tester.tapAt(_enPantalla(tester, 8));
      await tester.pump();
      expect(elegido(tester), 'Mesa 8 · la tiene GÓMEZ');
      // Tocarla no la corrió: no hay nada para guardar ni deshacer.
      expect(prendido(tester, 'guardar_acomodo'), isFalse);
      expect(prendido(tester, 'acomodar_deshacer'), isFalse);
    });

    testWidgets('arrastrar corre la mesa de a cuartos de metro, sin guardar',
        (tester) async {
      final guardados = <(ArmadoSalon, ArmadoSalon)>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: _acciones([], salon: guardados));
      await abrir(tester);
      await _arrastrarMesa(tester, fondo, const Offset(0, 3));
      final antes = armado.mesa(fondo)!;
      final ahora = _vista(tester).armado.mesa(fondo)!;
      final corrida = armado.aMetros(ahora.y - antes.y);
      expect(corrida, closeTo(3, 0.26));
      expect((corrida / 0.25 - (corrida / 0.25).round()).abs(), lessThan(1e-6));
      expect(ahora.x, antes.x);
      // El plano no se desplazó mientras se arrastraba.
      expect(_zoom(tester), 1);
      expect(guardados, isEmpty);
      expect(elegido(tester), 'Mesa $fondo · vacía');
      expect(prendido(tester, 'guardar_acomodo'), isTrue);
      expect(find.text('GUARDAR EL SALÓN'), findsOneWidget);

      // Deshacer la devuelve.
      await tester.tap(find.byKey(const Key('acomodar_deshacer')));
      await tester.pump();
      expect(_vista(tester).armado.mesa(fondo)!.y, antes.y);
      expect(prendido(tester, 'guardar_acomodo'), isFalse);
    });

    testWidgets('GUARDAR avisa el salón del que se partió y el que quedó',
        (tester) async {
      final guardados = <(ArmadoSalon, ArmadoSalon)>[];
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado),
          acciones: _acciones([], salon: guardados));
      await abrir(tester);
      await _arrastrarMesa(tester, fondo, const Offset(0, 3));
      await tester.tap(find.byKey(const Key('guardar_acomodo')));
      await tester.pump();
      final (base, nuevo) = guardados.single;
      expect(identical(base, armado), isTrue);
      expect(nuevo.mesa(fondo)!.y, greaterThan(armado.mesa(fondo)!.y));

      // Vuelve guardado: sigue en Acomodar, con la mesa elegida, sin nada
      // pendiente.
      await _mostrar(tester,
          plano: _plano(armado: nuevo),
          acciones: _acciones([], salon: guardados));
      expect(find.byKey(const Key('panel_acomodar')), findsOneWidget);
      expect(find.text('SALÓN GUARDADO'), findsOneWidget);
      expect(elegido(tester), 'Mesa $fondo · vacía');
      expect(prendido(tester, 'acomodar_deshacer'), isFalse);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
    });

    testWidgets('con cambios sin guardar no se sale; DESCARTAR pide dos veces',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      await _arrastrarMesa(tester, 30, const Offset(0, 3));
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('panel_acomodar')), findsOneWidget);
      expect(texto(tester, 'pista'), contains('cambios del salón sin guardar'));

      await tester.tap(find.byKey(const Key('descartar_acomodo')));
      await tester.pump();
      expect(find.text('¿DESCARTAR TODO?'), findsOneWidget);
      expect(_vista(tester).armado.mesa(30)!.y, isNot(armado.mesa(30)!.y));
      await tester.tap(find.byKey(const Key('descartar_acomodo')));
      await tester.pump();
      expect(identical(_vista(tester).armado, armado), isTrue);
      await tester.tap(find.byKey(const Key('salir_personalizar')));
      await tester.pump();
      expect(find.byKey(const Key('franja_personalizar')), findsNothing);
    });

    testWidgets('agregar da el número que sigue; una con familia no se saca',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      await tester.tap(find.byKey(const Key('acomodar_agregar')));
      await tester.pump();
      expect(_vista(tester).armado.existe(41), isTrue);
      expect(elegido(tester), 'Mesa 41 · vacía');
      expect(texto(tester, 'mensaje_acomodar'),
          'Mesa 41 agregada: arrastrala a su lugar.');
      // La nueva se puede sacar.
      await tester.tap(find.byKey(const Key('acomodar_sacar')));
      await tester.pump();
      expect(_vista(tester).armado.existe(41), isFalse);
      // Una con familia, no: dice por qué y queda.
      await tester.tapAt(_enPantalla(tester, 8));
      await tester.pump();
      await tester.tap(find.byKey(const Key('acomodar_sacar')));
      await tester.pump();
      expect(_vista(tester).armado.existe(8), isTrue);
      expect(texto(tester, 'mensaje_acomodar'),
          'La mesa 8 no se saca: la tiene GÓMEZ. Se puede correr.');
    });

    testWidgets('marcar de pasto y volver', (tester) async {
      await _mostrar(tester, acciones: _acciones([], salon: []));
      await abrir(tester);
      await tester.tapAt(_enPantalla(tester, 30));
      await tester.pump();
      await tester.tap(find.byKey(const Key('acomodar_pasto')));
      await tester.pump();
      expect(_vista(tester).armado.pasto, {30});
      expect(elegido(tester), 'Mesa 30 · vacía · en el pasto');
      expect(find.text('Sacar del pasto'), findsOneWidget);
    });

    testWidgets('una mesa encima de otra no deja guardar, y lo dice',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      final a = armado.mesa(30)!;
      final vecina = armado.mesasDeHoja(a.hoja).firstWhere(
          (m) => m.numero != 30 && armado.distanciaM(30, m.numero)! < 2.1);
      final metros = Offset(
        armado.aMetros(vecina.x - a.x),
        armado.aMetros(vecina.y - a.y),
      );
      await _arrastrarMesa(tester, 30, metros);
      expect(find.byKey(const Key('bloqueo_0')), findsOneWidget);
      expect(find.textContaining('se pisan'), findsOneWidget);
      expect(prendido(tester, 'guardar_acomodo'), isFalse);
    });

    testWidgets('separar o juntar: se ve antes, y recién cambia con APLICAR',
        (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      expect(texto(tester, 'separar_metros'), '2 m');
      tester
          .widget<Slider>(find.byKey(const Key('separar_paso')))
          .onChanged!(2.5);
      await tester.pump();
      expect(texto(tester, 'separar_metros'), '2,5 m');
      expect(texto(tester, 'separar_previa'), 'Siguen entrando las 40.');
      expect(
        tester.widget<Text>(find.byKey(const Key('texto_personalizar'))).data,
        startsWith('Así quedaría'),
      );
      // El plano ya lo muestra, pero no se puede guardar ni arrastrar.
      expect(_vista(tester).armado.distanciaM(1, 2), closeTo(2.5, 1e-6));
      expect(prendido(tester, 'guardar_acomodo'), isFalse);
      await _arrastrarMesa(tester, 30, const Offset(0, 2));
      expect(_vista(tester).armado.distanciaM(1, 2), closeTo(2.5, 1e-6));

      await tester.tap(find.byKey(const Key('separar_cancelar')));
      await tester.pump();
      expect(identical(_vista(tester).armado, armado), isTrue);
      expect(texto(tester, 'separar_metros'), '2 m');

      tester
          .widget<Slider>(find.byKey(const Key('separar_paso')))
          .onChanged!(2.5);
      await tester.pump();
      await tester.tap(find.byKey(const Key('separar_aplicar')));
      await tester.pump();
      expect(_vista(tester).armado.distanciaM(1, 2), closeTo(2.5, 1e-6));
      expect(prendido(tester, 'guardar_acomodo'), isTrue);
      expect(texto(tester, 'separar_metros'), '2,5 m');
    });

    testWidgets('volver al armado original: con familias sentadas está '
        'apagado, con el motivo', (tester) async {
      await _mostrar(tester, acciones: _acciones([], salon: []));
      await abrir(tester);
      expect(prendido(tester, 'acomodar_original'), isFalse);
      expect(texto(tester, 'motivo_sin_original'), contains('deshacé el sorteo'));
    });

    testWidgets('volver al armado original: antes del sorteo vuelve, sin '
        'guardar', (tester) async {
      final sinMesa = [_alumno('vega', 'VEGA, ANA', extras: 1)];
      final armado = _armado();
      await _mostrar(tester,
          alumnos: sinMesa,
          plano: _plano(armado: armado, alumnos: sinMesa),
          acciones: _acciones([], salon: []));
      await abrir(tester);
      expect(find.byKey(const Key('motivo_sin_original')), findsNothing);
      await _arrastrarMesa(tester, 30, const Offset(0, 3));
      await tester.ensureVisible(find.byKey(const Key('acomodar_original')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('acomodar_original')));
      await tester.pump();
      expect(_vista(tester).armado.mesa(30)!.y,
          closeTo(armado.mesa(30)!.y, 1e-6));
      expect(texto(tester, 'mensaje_acomodar'),
          startsWith('Volvió el armado original'));
    });

    testWidgets('si la otra PC cambia el salón mientras se acomoda, lo dice y '
        'no pierde lo hecho', (tester) async {
      final armado = _armado();
      await _mostrar(tester,
          plano: _plano(armado: armado), acciones: _acciones([], salon: []));
      await abrir(tester);
      await _arrastrarMesa(tester, 30, const Offset(0, 3));
      final corrida = _vista(tester).armado.mesa(30)!.y;

      final deLaOtra = EditarArmado.marcarPasto(armado, 1, true);
      await _mostrar(tester,
          plano: _plano(armado: deLaOtra), acciones: _acciones([], salon: []));
      expect(texto(tester, 'pista'), contains('cambió en la otra PC'));
      expect(_vista(tester).armado.mesa(30)!.y, corrida);
      // Descartando se ve cómo quedó.
      await tester.tap(find.byKey(const Key('descartar_acomodo')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('descartar_acomodo')));
      await tester.pump();
      expect(_vista(tester).armado.pasto, {1});
      expect(find.byKey(const Key('pista')), findsNothing);
    });

    testWidgets('un sector se elige, se agranda y se saca', (tester) async {
      await _mostrar(tester, acciones: _acciones([], salon: []));
      await abrir(tester);
      final vista = _vista(tester);
      final i = vista.armado.sectores
          .indexWhere((s) => s.tipo == TipoSector.escenario);
      final c = vista.armado.sectores[i].caja;
      final caja = tester.getRect(find.byType(VistaPlano));
      final punto = caja.topLeft +
          EncuadrePlano.de(vista.armado.hoja('A')!.caja, caja.size)
              .aPantalla(Offset(c.centroX, c.centroY));
      await tester.tapAt(punto);
      await tester.pump();
      expect(elegido(tester), 'Sector: Escenario');
      expect(texto(tester, 'tamano_sector'), startsWith('Mide 30 × '));
      await tester.tap(find.byKey(const Key('sector_mas_ancho')));
      await tester.pump();
      expect(texto(tester, 'tamano_sector'), startsWith('Mide 30,5 × '));
      await tester.tap(find.byKey(const Key('acomodar_sacar_sector')));
      await tester.pump();
      expect(_vista(tester).armado.sectores.length,
          vista.armado.sectores.length - 1);
      expect(elegido(tester), startsWith('Tocá una mesa'));
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
              acciones: _acciones([]),
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
