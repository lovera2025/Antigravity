import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/central/resolvedor_de_pedidos.dart';
import 'package:arguello_events/features/recepcion/providers/acciones_puerta_provider.dart';
import 'package:arguello_events/features/recepcion/services/como_lo_nombran.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/central_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart';

/// **"Cómo lo nombran" por el candado de la puerta** (el locutor, v85, 28-nov-2026): la
/// PC y los celulares cambian cómo nombrar a una familia por el mismo
/// [ResolvedorDePedidos], de a uno y con la base del momento. Si otro lo cambió mientras
/// se editaba, conflicto; un pedido repetido no guarda dos veces.
void main() {
  final ahora = DateTime.utc(2026, 12, 5, 1, 41);
  final perez = alumnoDePrueba('perez', 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA'], cantidad: 2);

  late PcEnMemoria pc;
  late ResolvedorDePedidos resolvedor;

  PuertaDelEvento lista() => PuertaDelEvento.masivo(alumnos: [perez], invitados: const [], nombres: pc.nombres);
  GrupoPuerta familia() => lista().grupos.single;

  PedidoPuerta pedido(String id, DatosNombres d) =>
      PedidoPuerta(id: id, que: QuePide.nombrar, personaId: familia().titular.id, nombres: d);

  setUp(() {
    pc = PcEnMemoria();
    resolvedor = ResolvedorDePedidos(eventoId: eventoMasivo, pc: pc, ahora: () => ahora);
  });

  test('guarda, y la respuesta dice cómo quedó', () async {
    final antes = familia().nombres!.firma;
    final r = await resolvedor.resolver(
      pedido('p1', DatosNombres(alumno: "Juani 'el Tano'", lugares: const {2: 'la abuela Tita'}, antes: antes)),
      'Juli',
      conLista: lista(),
    );
    expect(r['ok'], isTrue);
    expect(r['hizo'], 'nombrar');
    final guardada = pc.nombres['perez']!;
    expect(guardada.alumno, "Juani 'el Tano'");
    expect(guardada.cambiadoPor, 'Juli');
    expect(guardada.acompanantes.single.lugar, 2);
    final quedo = NombresDeLaFamilia.fromJson(r['nombres'])!;
    expect(quedo.alumno, "Juani 'el Tano'");
    expect(familia().titular.nombrado, "Juani 'el Tano'");
    expect(familia().titular.nombre, 'PÉREZ, JUAN', reason: 'la ficha no cambia');
  });

  test('si otro lo cambió mientras editaba: conflicto, con lo de ahora, y no se guarda', () async {
    final lo = familia().nombres!.firma;
    await resolvedor.resolver(pedido('juli', DatosNombres(alumno: 'Juani', antes: lo)), 'Juli', conLista: lista());
    final r = await resolvedor.resolver(pedido('pato', DatosNombres(alumno: 'Juancito', antes: lo)), 'Pato', conLista: lista());
    expect(r['ok'], isTrue);
    expect(r['hizo'], 'nada');
    expect(r['conflicto'], isTrue);
    expect(r['aviso'], contains('Juli lo cambió recién (${horaCorta(ahora)})'));
    expect(NombresDeLaFamilia.fromJson(r['nombres'])!.alumno, 'Juani');
    expect(pc.nombres['perez']!.alumno, 'Juani', reason: 'no pisó lo de Juli');
    // Con la firma nueva, GUARDAR de nuevo deja lo suyo, ya a sabiendas.
    final nueva = NombresDeLaFamilia.fromJson(r['nombres'])!.firma;
    final otra = await resolvedor.resolver(pedido('pato2', DatosNombres(alumno: 'Juancito', antes: nueva)), 'Pato',
        conLista: lista());
    expect(otra['hizo'], 'nombrar');
    expect(pc.nombres['perez']!.alumno, 'Juancito');
  });

  test('el mismo pedido dos veces no guarda dos veces; lo mismo con otro id, "Quedó así."', () async {
    final antes = familia().nombres!.firma;
    final d = DatosNombres(alumno: 'Juani', antes: antes);
    await resolvedor.resolver(pedido('p1', d), 'Juli', conLista: lista());
    await resolvedor.resolver(pedido('p1', d), 'Juli', conLista: lista());
    expect(pc.nombresGuardados, 1);
    final r = await resolvedor.resolver(pedido('p2', d), 'Juli', conLista: lista());
    expect(r['aviso'], 'Quedó así.');
    expect(r['conflicto'], isNull, reason: 'pedir lo que ya está no es un conflicto');
    expect(pc.nombresGuardados, 1);
  });

  test('si la base falla: ok false, no queda guardada la respuesta y se puede reintentar', () async {
    pc.falla = true;
    final d = DatosNombres(alumno: 'Juani', antes: familia().nombres!.firma);
    final r = await resolvedor.resolver(pedido('p1', d), 'Juli', conLista: lista());
    expect(r['ok'], isFalse);
    pc.falla = false;
    final otra = await resolvedor.resolver(pedido('p1', d), 'Juli', conLista: lista());
    expect(otra['hizo'], 'nombrar');
  });

  test('lo cargado a mano no se nombra', () async {
    final conAMano = PuertaDelEvento.masivo(
      alumnos: [perez],
      invitados: [filaDePrueba('a-mano', 'SOSA, TITO')],
    );
    final g = conAMano.grupos.firstWhere((g) => g.cargadoAMano);
    final r = await resolvedor.resolver(
      PedidoPuerta(id: 'x', que: QuePide.nombrar, personaId: g.titular.id, nombres: const DatosNombres(antes: 'x')),
      'Juli',
      conLista: conAMano,
    );
    expect(r['hizo'], 'nada');
    expect(r['aviso'], contains('egresados'));
    expect(pc.nombres, isEmpty);
  });

  test('el pedido viaja entero y el más grande entra en un mensaje', () {
    final p = PedidoPuerta(
      id: 'p1',
      que: QuePide.nombrar,
      personaId: 'perez',
      nombres: DatosNombres(
        alumno: '"' * kTopeNombre,
        lugares: {for (var l = 1; l < kMaxLugaresPorAlumno; l++) l: '"' * kTopeNombre},
        antes: '0123456789abcdef',
      ),
    );
    final texto = jsonEncode(p.toJson());
    expect(texto.length, lessThanOrEqualTo(4096));
    final vuelta = PedidoPuerta.fromJson(jsonDecode(texto) as Map<String, dynamic>)!;
    expect(vuelta.nombres, p.nombres);
    expect(PedidoPuerta.fromJson({'id': 'x', 'que': 'nombrar', 'persona': 'perez'}), isNull,
        reason: 'sin nombres no es un pedido');
  });

  group('lo que dice la PC al guardar', () {
    Future<ResultadoNombres> nombrarDesdeLaPc({required bool central}) {
      final acciones = AccionesDeEstaPc(
        InvitadosEnMemoria(SupabaseClient('http://localhost:1', 'x'), []),
        (_) => null,
        resolver: (eventoId, p, {required puesto, required puerta}) => resolvedor.resolver(p, puesto, conLista: puerta),
        quienOpera: () => 'PC',
        centralPrendida: (_) => central,
      );
      return acciones.nombrar(eventoMasivo, lista(), familia(),
          DatosNombres(alumno: 'Juani${central ? '' : 'to'}', antes: familia().nombres!.firma),
          id: 'pc-$central');
    }

    test('con la central de los celulares prendida acá, el locutor ya lo ve', () async {
      final r = await nombrarDesdeLaPc(central: true);
      expect(r.hecho, isTrue);
      expect(r.texto, 'Guardado: el locutor ya lo ve.');
    });

    test('sin la central acá, quedó en esta PC', () async {
      final r = await nombrarDesdeLaPc(central: false);
      expect(r.hecho, isTrue);
      expect(r.texto, startsWith('Guardado en esta PC'));
    });
  });

  group('en la pantalla de Recepción', () {
    // El cliente de la nube se crea fuera de los tests: creado adentro deja un reloj
    // suyo andando (como en panel_puerta_test).
    late SupabaseClient supabase;
    setUpAll(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    });

    Future<PuertaEnMemoria> abrir(WidgetTester tester, {List<ComoLoNombran> nombres = const []}) async {
      final mundo = PuertaEnMemoria(
        supabase,
        alumnos: [
          alumnoDePrueba('perez', 'PÉREZ, JUAN', mesas: const [12], acomp: ['GÓMEZ, LAURA'], cantidad: 2),
          alumnoDePrueba('acosta', 'ACOSTA, LUCÍA', mesas: const [13]),
        ],
        nombres: nombres,
      );
      tester.view.physicalSize = const Size(1366, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(mundo.motor.bajo.close);
      await tester.pumpWidget(mundo.panel(eventoMasivo));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      return mundo;
    }

    testWidgets('sin cambios no hay línea; CÓMO LO NOMBRAN guarda y la tarjeta lo dice', (tester) async {
      final mundo = await abrir(tester);
      expect(find.textContaining('Lo nombran:'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('como_lo_nombran_perez')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nombrar_aviso_tele')), findsOneWidget);
      expect(find.text('Acompañante 2 · sin nombre en la lista'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('nombrar_alumno')), "Juani 'el Tano'");
      await tester.enterText(find.byKey(const ValueKey('nombrar_2')), 'la abuela Tita');
      await tester.tap(find.byKey(const Key('nombrar_guardar')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(mundo.comoLoNombran.filas['perez']!.alumno, "Juani 'el Tano'");
      expect(mundo.comoLoNombran.filas['perez']!.cambiadoPor, 'PC');
      expect(find.text("Lo nombran: «Juani 'el Tano'»"), findsOneWidget);
      expect(find.text('Lo nombran: «la abuela Tita»'), findsOneWidget);
      expect(find.textContaining('Guardado'), findsOneWidget);
      // La ficha no cambió: el nombre sigue siendo el cargado.
      expect(find.text('PÉREZ, JUAN'), findsOneWidget);
    });

    testWidgets('el botón está también antes del sorteo, y no en lo que no es de un alumno', (tester) async {
      final mundo = PuertaEnMemoria(
        supabase,
        alumnos: [alumnoDePrueba('perez', 'PÉREZ, JUAN', acomp: ['GÓMEZ, LAURA'])],
        filas: [filaDePrueba('a-mano', 'SOSA, TITO')],
      );
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(mundo.motor.bajo.close);
      await tester.pumpWidget(mundo.panel(eventoMasivo));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const ValueKey('como_lo_nombran_perez')), findsOneWidget);
      expect(find.byKey(const ValueKey('como_lo_nombran_null')), findsNothing);
    });

    testWidgets('lo guardado se ve al abrir, y se busca por el apodo', (tester) async {
      await abrir(tester, nombres: [
        ComoLoNombran.para(
          eventoId: eventoMasivo,
          contratoAlumnoId: 'perez',
          alumno: 'Juani',
          alumnoCargado: 'PÉREZ, JUAN',
          acompanantes: const [NombreDeAcompanante(lugar: 1, cargado: 'GÓMEZ, LAURA', nombre: 'Lau')],
          cambiadoPor: 'Juli',
          ahora: ahora,
        ),
      ]);
      expect(find.text('Lo nombran: «Juani»'), findsOneWidget);
      expect(find.text('Lo nombran: «Lau»'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'juani');
      await tester.pump();
      expect(find.text('ACOSTA, LUCÍA'), findsNothing);
      expect(find.text('PÉREZ, JUAN'), findsOneWidget);
    });
  });
}
