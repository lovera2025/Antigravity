// La puerta ve el plano (6.5.0): la recepcionista toca una familia y ve, en su
// pantalla, el salón con su mesa encendida y el camino; VER LA LLEGADA la
// reproduce como en la tele, sin que la tele se entere; y MÁS → "Ver el plano
// entero" muestra cada familia en su mesa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/plano/modelo/armado_salon.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/widgets/vista_plano.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/plano_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/widgets/hoja_plano_puerta.dart';
import 'package:arguello_events/features/totem/estilos/escena_totem.dart';
import 'package:arguello_events/features/totem/estilos/totem_estilo.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/totem_config.dart';

import 'helpers/puerta_en_memoria.dart';

final _salon = ArmadosPredefinidos.normal2aPagina3();
final _cfg = TotemConfig.defaults(eventoMasivo);

List<ContratoAlumno> _institucion({bool sorteada = true}) {
  List<int> m(List<int> mesas) => sorteada ? mesas : const [];
  return [
    alumnoDePrueba('perez', 'PÉREZ, JUAN MARTÍN',
        mesas: m([12]), acomp: ['GÓMEZ, ANA']),
    alumnoDePrueba('acosta', 'ACOSTA, LUCÍA',
        mesas: m([14, 15]), extras: 1, division: '5° A'),
    alumnoDePrueba('benitez', 'BENÍTEZ, TOMÁS', mesas: m([13])),
  ];
}

Invitado _adentro(String id, String nombre, DateTime hora) => Invitado(
      id: id,
      eventoId: eventoMasivo,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: hora,
    );

GrupoPuerta _grupo(PuertaDelEvento p, String nombre) =>
    p.grupos.firstWhere((g) => g.titular.nombre == nombre);

late SupabaseClient _supabase;

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<PuertaEnMemoria> _abrir(
  WidgetTester tester, {
  bool sorteada = true,
  ArmadoSalon? plano,
  List<Invitado>? filas,
}) async {
  final mundo = PuertaEnMemoria(
    _supabase,
    alumnos: _institucion(sorteada: sorteada),
    filas: filas,
    plano: plano,
  );
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(mundo.motor.bajo.close);
  await tester.pumpWidget(mundo.panel(eventoMasivo, animarElPlano: false));
  await _asentar(tester);
  return mundo;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
  });

  test('el salón de prueba tiene las mesas de la institución', () {
    for (final n in [12, 13, 14, 15]) {
      expect(_salon.existe(n), isTrue, reason: 'mesa $n');
    }
  });

  group('SalonParaLaPuerta', () {
    final puerta = PuertaDelEvento.masivo(
      alumnos: _institucion(),
      invitados: [
        _adentro(idInvitadoPuerta('benitez', 0), 'BENÍTEZ, TOMÁS',
            DateTime(2026, 12, 12, 22)),
      ],
    );
    final salon = SalonParaLaPuerta.de(_salon, _cfg)!;

    test('sin plano o sin mesas no hay salón', () {
      expect(SalonParaLaPuerta.de(null, _cfg), isNull);
      expect(
        SalonParaLaPuerta.de(ArmadoSalon.fromJson(const {}), _cfg),
        isNull,
      );
    });

    test('la familia, con su mesa encendida y el camino', () {
      final g = _grupo(puerta, 'ACOSTA, LUCÍA');
      expect(salon.tieneMesaDe(g), isTrue);
      final guia = salon.deLaFamilia(g)!;
      expect(guia.mesas, {14, 15});
      expect(guia.principal, 14);
      expect(guia.ruta, isNotNull, reason: 'el salón tiene Ingreso');
    });

    test('sin mesa del plano, no', () {
      final p = PuertaDelEvento.masivo(
        alumnos: [alumnoDePrueba('x', 'X, Y', mesas: [200])],
        invitados: const [],
      );
      final g = p.grupos.single;
      expect(salon.tieneMesaDe(g), isFalse);
      expect(salon.deLaFamilia(g), isNull);
    });

    test('el salón entero: de quién es cada mesa y qué familias faltan', () {
      final e = salon.entero(puerta);
      expect(e.familiaDeMesa[14]!.titular.nombre, 'ACOSTA, LUCÍA');
      expect(e.familiaDeMesa[15]!.titular.nombre, 'ACOSTA, LUCÍA');
      expect(e.familiaDeMesa[13]!.titular.nombre, 'BENÍTEZ, TOMÁS');
      expect(e.faltan, {12, 14, 15}, reason: 'BENÍTEZ ya entró');
      expect(e.familiasQueFaltan, 2);
      expect(e.estado.info(14).ocupante!.nombre, 'ACOSTA, LUCÍA');
      expect(_salon.hoja(e.hoja), isNotNull);
    });

    test('la llegada que se vuelve a ver es la del titular, con su mesa', () {
      final g = _grupo(puerta, 'PÉREZ, JUAN MARTÍN');
      final b = SalonParaLaPuerta.llegadaDe(
        eventoMasivo,
        g,
        DateTime(2026, 12, 12, 23),
      );
      expect(b.familia, g.titular.id);
      expect(b.personas.single.id, g.titular.id);
      expect(b.personas.single.numeroMesa, '12');
    });

    test('al celular la config va sin la foto ni el fondo', () {
      const cfg = TotemConfig(
        eventoId: eventoMasivo,
        imagenUrl: 'https://nube/foto.jpg',
        fondoUrl: 'https://nube/fondo.jpg',
        estilo: 'tuFondo',
      );
      final enElCelular =
          TotemConfig.fromJson(SalonParaLaPuerta.cfgParaElCelular(cfg));
      expect(enElCelular.imagenUrl, isNull);
      expect(enElCelular.fondoUrl, isNull);
      expect(
        EstiloTotem.elegida(enElCelular.estilo, fondoUrl: enElCelular.fondoUrl),
        isNull,
        reason: '"Tu fondo" sin imagen va con la del evento masivo',
      );
    });
  });

  test('ADENTRO va por hora: el último que entró, arriba', () {
    final p = PuertaDelEvento.masivo(
      alumnos: _institucion(),
      invitados: [
        _adentro(idInvitadoPuerta('perez', 0), 'PÉREZ, JUAN MARTÍN',
            DateTime(2026, 12, 12, 22, 10)),
        _adentro(idInvitadoPuerta('acosta', 0), 'ACOSTA, LUCÍA',
            DateTime(2026, 12, 12, 22, 40)),
        _adentro(idInvitadoPuerta('benitez', 0), 'BENÍTEZ, TOMÁS',
            DateTime(2026, 12, 12, 22, 25)),
      ],
    );
    expect(
      p.buscar('', filtro: FiltroPuerta.adentro).map((g) => g.titular.nombre),
      ['ACOSTA, LUCÍA', 'BENÍTEZ, TOMÁS', 'PÉREZ, JUAN MARTÍN'],
    );
    // TODOS sigue como estaba.
    expect(
      p.buscar('').map((g) => g.titular.nombre),
      ['ACOSTA, LUCÍA', 'BENÍTEZ, TOMÁS', 'PÉREZ, JUAN MARTÍN'],
    );
  });

  group('en Recepción', () {
    testWidgets('con plano, cada familia con mesa tiene VER EN EL PLANO',
        (tester) async {
      await _abrir(tester, plano: _salon);
      expect(find.text('VER EN EL PLANO'), findsNWidgets(3));
    });

    testWidgets('sin plano, no', (tester) async {
      await _abrir(tester);
      expect(find.text('VER EN EL PLANO'), findsNothing);
    });

    testWidgets('sin sortear, no', (tester) async {
      await _abrir(tester, sorteada: false, plano: _salon);
      expect(find.text('VER EN EL PLANO'), findsNothing);
    });

    testWidgets('abre el salón con la mesa de la familia y el camino, y VER LA '
        'LLEGADA la reproduce solo ahí', (tester) async {
      await _abrir(tester, plano: _salon);
      await tester.tap(find.byKey(
        ValueKey('ver_en_el_plano_${idInvitadoPuerta('acosta', 0)}'),
      ));
      await _asentar(tester);

      expect(find.byType(HojaPlanoFamilia), findsOneWidget);
      expect(find.text(HojaPlanoFamilia.soloAca), findsOneWidget);
      final panel = tester.widget<PanelPlano>(
        find.byKey(const ValueKey('plano_de_la_familia')),
      );
      expect(panel.resaltadas, {14, 15});
      expect(panel.ruta, isNotNull);

      await tester.tap(find.byKey(const ValueKey('ver_la_llegada')));
      await _asentar(tester);
      final escena = tester.widget<EscenaTotem>(find.byType(EscenaTotem));
      expect(escena.llegada, isNotNull);
      expect(escena.llegada!.mesa, '14-15');
      expect(escena.plano!.mesas.length, _salon.mesas.length);

      // Termina sola y vuelve al plano.
      await tester.pump(const Duration(seconds: 30));
      await _asentar(tester);
      expect(find.byType(EscenaTotem), findsNothing);
      expect(find.byKey(const ValueKey('plano_de_la_familia')), findsOneWidget);

      await tester.tap(find.text('CERRAR'));
      await _asentar(tester);
      expect(find.byType(HojaPlanoFamilia), findsNothing);
    });

    testWidgets('MÁS → "Ver el plano entero", con las que faltan entrar',
        (tester) async {
      await _abrir(
        tester,
        plano: _salon,
        filas: [
          _adentro(idInvitadoPuerta('benitez', 0), 'BENÍTEZ, TOMÁS',
              DateTime(2026, 12, 12, 22)),
        ],
      );
      await tester.tap(find.byTooltip('Más'));
      await _asentar(tester);
      await tester.tap(find.text('Ver el plano entero'));
      await _asentar(tester);

      expect(find.byType(HojaPlanoEntero), findsOneWidget);
      VistaPlano vista() =>
          tester.widget<VistaPlano>(find.byKey(const ValueKey('plano_entero')));
      expect(vista().resaltadas, isEmpty);
      expect(vista().estado.info(12).ocupante!.nombre, 'PÉREZ, JUAN MARTÍN');

      await tester.tap(find.byKey(const ValueKey('faltan_entrar')));
      await _asentar(tester);
      expect(find.text('Faltan entrar 2 familias'), findsOneWidget);
      expect(vista().resaltadas, {12, 14, 15});

      // Tocar una mesa abre esa familia.
      vista().onTapMesa!(13);
      await _asentar(tester);
      expect(find.byType(HojaPlanoFamilia), findsOneWidget);
      expect(find.text('BENÍTEZ, TOMÁS'), findsWidgets);
    });

    testWidgets('sin sortear, MÁS no ofrece el plano', (tester) async {
      await _abrir(tester, sorteada: false, plano: _salon);
      await tester.tap(find.byTooltip('Más'));
      await _asentar(tester);
      expect(find.text('Ver el plano entero'), findsNothing);
    });
  });
}
