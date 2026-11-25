// TU TELE en el celular de la puerta (25-nov-2026): CAMBIAR LA ESCUELA y GIRAR
// la tele, sin PIN, y "La Tele 1 cambió a ESCUELA B · MANTENER · CAMBIAR".
// La pantalla con el cliente de mentira; el cliente de verdad contra la
// central de verdad de una tele, por la red de esta PC.
import 'dart:async';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pantalla_puesto.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/central_en_memoria.dart';
import 'helpers/cliente_de_prueba.dart';

const _a = eventoDeLaCentral;
const _b = 'e0000000-0000-4000-8000-0000000000bb';

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

Future<void> _hasta(bool Function() listo, [String que = '']) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) throw StateError('no pasó: $que');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('la pantalla del celular', () {
    late ClienteDePrueba cliente;

    Future<void> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: PantallaPuesto(cliente: cliente),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    setUp(() {
      cliente = ClienteDePrueba()
        ..p = PuertaDelEvento.particular([
          Invitado(
            id: 'p1',
            eventoId: _a,
            nombreCompleto: 'PÉREZ, JUAN',
            dni: '',
            estadoIngreso: EstadoIngreso.pendiente,
          ),
        ])
        ..tel = const [
          TeleDelCelular(numero: 1, conectada: true, evento: _a, titulo: 'ESCUELA A'),
          TeleDelCelular(numero: 2, conectada: true, evento: _a, titulo: 'ESCUELA A'),
        ]
        ..esc = const [EscuelaDelCelular(_a, 'ESCUELA A'), EscuelaDelCelular(_b, 'ESCUELA B')]
        ..miTele = 1
        ..centralTele = 'Tele 1';
    });

    testWidgets('TU TELE: CAMBIAR LA ESCUELA con un cartel que confirma, sin PIN', (tester) async {
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('tu_tele_hoja')));
      await tester.pumpAndSettle();
      expect(find.text('TU TELE · TELE 1'), findsOneWidget);
      expect(find.text('Muestra: ESCUELA A'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cambiar_la_escuela')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('escuela_$_b')));
      await tester.pumpAndSettle();
      expect(find.text('¿Pasar la Tele 1 a ESCUELA B?'), findsOneWidget);
      // La otra tele tiene la misma: lo dice.
      expect(find.textContaining('a sus celulares se les pregunta'), findsOneWidget);
      expect(find.text('PIN del jefe'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('escuela_volver')));
      await tester.pumpAndSettle();
      expect(cliente.escuelasPedidas, isEmpty);
      await tester.tap(find.byKey(const ValueKey('escuela_$_b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('escuela_cambiar')));
      await tester.pumpAndSettle();
      expect(cliente.escuelasPedidas, [(1, _b)]);
    });

    testWidgets('TU TELE: GIRAR, Horizontal · Vertical · Dar vuelta', (tester) async {
      cliente.miTele = 2;
      await abrir(tester);
      await tester.tap(find.byKey(const ValueKey('tu_tele_hoja')));
      await tester.pumpAndSettle();
      expect(find.text('TU TELE · TELE 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('girar_vertical')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('girar_dar_vuelta')));
      await tester.pump();
      expect(cliente.girosPedidos, [(2, 'vertical'), (2, 'dar_vuelta')]);
      expect(find.textContaining('Mirá la tele'), findsOneWidget);
    });

    testWidgets('la pregunta: MANTENER · CAMBIAR', (tester) async {
      cliente.preg = const PreguntaDeLaTele(id: 'p1', texto: 'La Tele 1 cambió a ESCUELA B', evento: _b);
      await abrir(tester);
      expect(find.text('La Tele 1 cambió a ESCUELA B'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pregunta_cambiar')));
      await tester.pump();
      expect(cliente.respuestas, [true]);
      expect(find.byKey(const ValueKey('pregunta_de_la_tele')), findsNothing);
    });

    testWidgets('"Las dos", apagada con escuelas distintas', (tester) async {
      cliente.lasDos = false;
      await abrir(tester);
      expect(find.text('Las dos (otra escuela)'), findsOneWidget);
    });

    testWidgets('en la notebook no hay TU TELE', (tester) async {
      cliente.tel = const [];
      await abrir(tester);
      expect(find.byKey(const ValueKey('tu_tele_hoja')), findsNothing);
    });
  });

  group('el celular de verdad, con la central de una tele', () {
    late PcEnMemoria pc;
    late CentralPuerta central;
    late int puerto;
    final clientes = <ClienteCentral>[];
    final abiertos = <CelularDePrueba>[];
    final pedidasTele1 = <(String, String?)>[];

    setUp(() async {
      pc = PcEnMemoria()..filas['p1'] = filaDePrueba('p1', 'PÉREZ, JUAN');
      pedidasTele1.clear();
      central = CentralPuerta(eventoId: _a, codigo: '4821', pc: pc, esTele: true)
        ..ponerEscuelasParaElegir(const [
          EscuelaParaElegir(_a, 'ESCUELA A'),
          EscuelaParaElegir(_b, 'ESCUELA B'),
        ]);
      central.alCambiarTele1 = (e, por) {
        pedidasTele1.add((e, por));
      };
      central.alAtender = (e) {
        central.ponerPuerta(PuertaDelEvento.particular(const []), de: e);
      };
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      central.ponerPuerta(pc.lista());
    });

    tearDown(() async {
      for (final c in clientes) {
        c.dispose();
      }
      clientes.clear();
      for (final c in abiertos) {
        try {
          await c.ws.close();
        } catch (_) {}
      }
      abiertos.clear();
      await central.cerrar();
    });

    Future<ClienteCentral> celular(String nombre, {String tele = '1'}) async {
      final c = ClienteCentral(
        servidor: Uri.parse('http://127.0.0.1:$puerto/'),
        guardado: _Navegador(),
        latido: const Duration(milliseconds: 40),
        pausa: const Duration(milliseconds: 40),
      );
      clientes.add(c);
      await c.iniciar(codigoDelEnlace: '4821', teleDelEnlace: tele);
      await c.ponerDatos(nombre: nombre);
      await _hasta(() => c.puerta != null && c.escuelas.isNotEmpty, 'la lista');
      return c;
    }

    test('ve las escuelas y pide otra para su tele; se le avisa y pasa sola', () async {
      final juli = await celular('Juli');
      expect(juli.escuelas.map((e) => e.titulo), ['ESCUELA A', 'ESCUELA B']);
      final avisos = <String>[];
      final sub = juli.avisos.listen(avisos.add);
      expect(juli.cambiarEscuela(1, _b), isTrue);
      await _hasta(() => juli.eventoId == _b, 'pasar a la B');
      await _hasta(() => avisos.isNotEmpty, 'el aviso');
      expect(avisos.single, startsWith('Juli pasó la Tele 1 a'));
      expect(pedidasTele1.single, (_b, 'Juli'));
      await sub.cancel();
    });

    test('lo que marca va con la escuela que miraba', () async {
      final juli = await celular('Juli');
      await juli.ingresar(juli.puerta!.personas.first);
      await _hasta(() => pc.ingresos.isNotEmpty, 'el ingreso');
      expect(juli.eventoId, _a);
      // El pedido salió con su escuela (si quedaba sin mandar y la tele cambiaba,
      // iba igual a la suya).
      expect(pc.ingresos.single.$1, 'p1');
    });

    test('la otra tele tenía la misma: le salta la pregunta y CAMBIAR pasa la tele', () async {
      final t = await CelularDePrueba.conectarTele(puerto, evento: _a);
      abiertos.add(t);
      await t.espera('central');
      final caro = await celular('Caro', tele: '2');
      central.cambiarEscuelaDeTele(1, _b, yaCambio: true);
      await _hasta(() => caro.pregunta != null, 'la pregunta');
      expect(caro.pregunta!.texto, 'La Tele 1 cambió a ESCUELA B');
      caro.contestar(cambiar: true);
      expect((await t.espera('escuela'))['evento'], _b);
      await _hasta(() => caro.eventoId == _b, 'Caro pasa a la B');
      expect(caro.pregunta, isNull);
    });

    test('"Las dos" con escuelas distintas: la central la deja en su tele', () async {
      final t = await CelularDePrueba.conectarTele(puerto, evento: _b);
      abiertos.add(t);
      await t.espera('central');
      final juli = await celular('Juli');
      await _hasta(() => !juli.lasDosSePuede, 'que diga que no');
      await juli.elegirTele(kLasDosTeles);
      await _hasta(() => juli.tele == 1, 'que vuelva a la Tele 1');
    });
  });
}
