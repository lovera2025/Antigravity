import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart' show GuardadoDelCelular;
import 'package:arguello_events/features/recepcion/central/cliente_locutor.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_locutor.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/como_lo_nombran.dart';

import 'helpers/central_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart' show alumnoDePrueba;

/// **La pantalla del locutor** (28-nov-2026), contra la central de verdad en esta PC.
const _evento = eventoDeLaCentral;
const _ana = 'a0000000-0000-4000-8000-000000000001';

class _Navegador implements GuardadoDelCelular {
  final datos = <String, String>{};

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> guardar(String clave, String? valor) async {
    if (valor == null) {
      datos.remove(clave);
    } else {
      datos[clave] = valor;
    }
  }
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  late PcEnMemoria pc;
  late CentralPuerta central;

  setUp(() {
    pc = PcEnMemoria();
    pc.alumnos
      ..add(alumnoDePrueba(_ana, 'CEIBO, ANA', acomp: ['ULMO, CELIA'], institucion: 'ESCUELA NORMAL', evento: _evento))
      ..add(alumnoDePrueba('a0000000-0000-4000-8000-000000000002', 'SAUCE, PEDRO',
          institucion: 'INSTITUTO SUR', evento: _evento));
    central = CentralPuerta(eventoId: _evento, codigo: '4821', codigoLocutor: '7391', pc: pc);
  });

  tearDown(() async => central.cerrar());

  PuertaDelEvento lista({bool nombrada = false}) => PuertaDelEvento.masivo(
        alumnos: pc.alumnos,
        invitados: const [],
        nombres: {
          if (nombrada)
            _ana: ComoLoNombran.para(
              eventoId: _evento,
              contratoAlumnoId: _ana,
              alumno: 'Ani',
              alumnoCargado: 'CEIBO, ANA',
              ahora: DateTime.now(),
            ),
        },
      );

  Future<void> esperar(WidgetTester tester, bool Function() listo, {String que = ''}) async {
    for (var i = 0; i < 250 && !listo(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(listo(), isTrue, reason: que);
  }

  Future<ClienteLocutor> abrir(WidgetTester tester, {String? codigo = '7391'}) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late int puerto;
    await tester.runAsync(() async {
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    });
    final c = ClienteLocutor(servidor: Uri.parse('http://127.0.0.1:$puerto/'), guardado: _Navegador());
    await tester.runAsync(() => c.iniciar(codigoDelEnlace: codigo));
    await tester.pumpWidget(MaterialApp(home: PantallaLocutor(cliente: c)));
    await tester.pump();
    return c;
  }

  Future<void> cerrar(WidgetTester tester, ClienteLocutor c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(const Duration(minutes: 1));
  }

  testWidgets('la lista: institución, egresado y acompañantes; A+ agranda la letra', (tester) async {
    central.ponerPuerta(lista());
    final c = await abrir(tester);
    await esperar(tester, () => find.text('ANA CEIBO').evaluate().isNotEmpty, que: 'la lista');
    expect(find.text('ESCUELA NORMAL'), findsWidgets, reason: 'el título y su chip');
    expect(find.text('CELIA ULMO'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    final antes = tester.widget<Text>(find.text('ANA CEIBO')).style!.fontSize!;
    await tester.tap(find.byKey(const Key('locutor_mas')));
    await tester.pump();
    expect(tester.widget<Text>(find.text('ANA CEIBO')).style!.fontSize, greaterThan(antes));
    expect(tester.takeException(), isNull);
    await cerrar(tester, c);
  });

  testWidgets('lo cambiado: NUEVO hasta tocarlo, lo cargado chico al lado, CAMBIADOS y el buscador', (tester) async {
    central.ponerPuerta(lista());
    final c = await abrir(tester);
    await esperar(tester, () => find.text('ANA CEIBO').evaluate().isNotEmpty);
    central.ponerPuerta(lista(nombrada: true));
    await esperar(tester, () => find.text('Ani').evaluate().isNotEmpty, que: 'el nombre nuevo, sin recargar');
    expect(find.byKey(const Key('locutor_aviso')), findsOneWidget);
    expect(find.text('cargado: CEIBO, ANA'), findsOneWidget);
    expect(find.byKey(const Key('locutor_nuevo_$_ana')), findsOneWidget);
    await tester.tap(find.text('Ani'));
    await tester.pump();
    expect(find.byKey(const Key('locutor_nuevo_$_ana')), findsNothing, reason: 'tocarlo lo da por visto');

    await tester.tap(find.byKey(const Key('locutor_cambiadas')));
    await tester.pump();
    expect(find.text('PEDRO SAUCE'), findsNothing);
    expect(find.text('Ani'), findsOneWidget);
    await tester.tap(find.byKey(const Key('locutor_cambiadas')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('locutor_buscar')), 'sauce');
    await tester.pump();
    expect(find.text('PEDRO SAUCE'), findsOneWidget);
    expect(find.text('Ani'), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(find.byKey(const Key('locutor_aviso')), findsNothing, reason: 'el aviso se va solo');
    await cerrar(tester, c);
  });

  testWidgets('sin conexión: la franja lo dice y la lista sigue a la vista', (tester) async {
    central.ponerPuerta(lista());
    final c = await abrir(tester);
    await esperar(tester, () => find.text('ANA CEIBO').evaluate().isNotEmpty);
    await tester.runAsync(central.cerrar);
    await esperar(tester, () => c.estado == EstadoDelLocutor.sinConexion, que: 'sin conexión');
    await tester.pump();
    expect(find.byKey(const Key('locutor_franja')), findsOneWidget);
    expect(find.textContaining('Sin conexión con la PC'), findsOneWidget);
    expect(find.text('ANA CEIBO'), findsOneWidget);
    await cerrar(tester, c);
    central = CentralPuerta(eventoId: _evento, codigo: '4821', pc: pc);
  });

  testWidgets('sin código lo pide', (tester) async {
    final c = await abrir(tester, codigo: null);
    expect(find.byKey(const Key('locutor_pide_codigo')), findsOneWidget);
    expect(find.byKey(const Key('locutor_entrar')), findsOneWidget);
    await cerrar(tester, c);
  });

  testWidgets('una fiesta particular no tiene lista para el locutor', (tester) async {
    central.ponerPuerta(PuertaDelEvento.particular(const []));
    final c = await abrir(tester);
    await esperar(tester, () => find.byKey(const Key('locutor_sin_lista')).evaluate().isNotEmpty);
    await cerrar(tester, c);
  });
}
