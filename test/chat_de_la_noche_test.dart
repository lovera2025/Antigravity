// El chat de la puerta (6.5.0, pedido del usuario el 9-nov): la PC y los
// celulares se hablan por la notebook del salón. Primero se elige a quién: una
// recepcionista o Todos. Vive solo en la memoria de la central: dura la noche.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/chat/chat_del_puesto.dart';
import 'package:arguello_events/features/recepcion/chat/hoja_chat.dart';
import 'package:arguello_events/features/recepcion/chat/mensaje_de_puesto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/central_en_memoria.dart';

const _codigo = '4821';

class _NavegadorEnMemoria implements GuardadoDelCelular {
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

Future<void> _hasta(bool Function() condicion, [String que = '']) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!condicion()) {
    if (DateTime.now().isAfter(limite)) {
      throw TimeoutException('no pasó: $que');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

MensajeDePuesto _msj(String id, String de, String? para, String texto) =>
    MensajeDePuesto(
      id: id,
      de: de,
      deNombre: de == kPuestoDeLaPc ? 'PC' : de,
      para: para,
      texto: texto,
      hora: DateTime(2026, 12, 12, 23),
    );

void main() {
  group('el chat de un puesto', () {
    late List<MensajeDePuesto> mandados;
    late ChatDelPuesto chat;

    setUp(() {
      mandados = [];
      chat = ChatDelPuesto(yo: 'juli', nombre: 'Juli', enviar: mandados.add)
        ..ponerPuestos(const [
          PuestoDelChat(id: kPuestoDeLaPc, nombre: 'Pato', conectado: true),
          PuestoDelChat(id: 'juli', nombre: 'Juli', conectado: true),
          PuestoDelChat(id: 'vero', nombre: 'Vero', conectado: false),
        ]);
    });
    tearDown(() => chat.dispose());

    test('la lista: Todos y cada otro puesto, los conectados primero', () {
      expect(
        [for (final c in chat.conversaciones) c.nombre],
        ['Todos', 'Pato', 'Vero'],
      );
      expect(chat.conversaciones[2].conectado, isFalse);
    });

    test('lo que manda va a la central y queda en su conversación', () {
      final m = chat.mandar('  ¿la 12 llegó?  ', kPuestoDeLaPc)!;
      expect(mandados.single.texto, '¿la 12 llegó?');
      expect(m.para, kPuestoDeLaPc);
      expect(chat.de(kPuestoDeLaPc).single.id, m.id);
      expect(chat.sinLeer, 0, reason: 'lo propio no queda sin leer');
      expect(chat.mandar('   ', kTodos), isNull);
      // Cuando vuelve de la central, no se repite.
      chat.recibir(m);
      expect(chat.de(kPuestoDeLaPc), hasLength(1));
    });

    test(
      'lo que llega con la conversación cerrada avisa y queda sin leer',
      () async {
        final nuevos = <MensajeNuevo>[];
        final sub = chat.nuevos.listen(nuevos.add);
        chat.recibir(_msj('1', kPuestoDeLaPc, 'juli', '¿alguien vio a GÓMEZ?'));
        chat.recibir(_msj('2', 'vero', null, 'Llegó el micro'));
        await Future<void>.delayed(Duration.zero);
        expect(nuevos.map((n) => n.quien), ['PC, a vos', 'vero, a todos']);
        expect(nuevos.first.conversacion, kPuestoDeLaPc);
        expect(chat.sinLeer, 2);

        chat.abrir(kPuestoDeLaPc);
        expect(chat.sinLeer, 1, reason: 'solo se leyó esa conversación');
        // Con la conversación abierta, lo que llega no avisa.
        chat.recibir(_msj('3', kPuestoDeLaPc, 'juli', 'ya está'));
        await Future<void>.delayed(Duration.zero);
        expect(nuevos, hasLength(2));
        expect(chat.sinLeer, 1);
        await sub.cancel();
      },
    );

    test('un puesto que se fue sigue con su nombre', () {
      chat.mandar('¿seguís?', 'vero');
      chat.ponerPuestos(const [
        PuestoDelChat(id: kPuestoDeLaPc, nombre: 'Pato', conectado: true),
      ]);
      expect(chat.conversaciones.last.nombre, 'Vero');
      expect(chat.conversaciones.last.conectado, isFalse);
    });

    test('lo de otros dos no lo ve', () {
      chat.recibir(_msj('1', kPuestoDeLaPc, 'vero', 'para Vero'));
      expect(chat.conversaciones.every((c) => c.ultimo == null), isTrue);
    });

    test('la historia de la primera vez queda leída', () {
      chat.ponerHistoria([
        _msj('1', 'vero', null, 'hola'),
        _msj('2', kPuestoDeLaPc, 'juli', 'hola Juli'),
      ]);
      expect(chat.sinLeer, 0);
      expect(chat.de(kTodos).single.texto, 'hola');
    });

    test('sin conexión no se manda', () {
      chat.puedeMandar = false;
      expect(chat.mandar('hola', kTodos), isNull);
      expect(mandados, isEmpty);
    });
  });

  group('por la central', () {
    late CentralPuerta central;
    late int puerto;
    late ChatDelPuesto pc;
    final llegaronALaPc = <MensajeDePuesto>[];
    final clientes = <ClienteCentral>[];

    Future<ClienteCentral> celular(String nombre) async {
      final c = ClienteCentral(
        servidor: Uri.parse('http://127.0.0.1:$puerto/'),
        guardado: _NavegadorEnMemoria(),
        latido: const Duration(milliseconds: 40),
        silencioMaximo: const Duration(seconds: 2),
        pausa: const Duration(milliseconds: 40),
      );
      clientes.add(c);
      await c.iniciar(codigoDelEnlace: _codigo);
      await c.ponerDatos(nombre: nombre);
      await _hasta(() => c.puerta != null, 'la lista de $nombre');
      return c;
    }

    String idDe(ClienteCentral c) => c.chat.yo;

    setUp(() async {
      llegaronALaPc.clear();
      final base = PcEnMemoria()
        ..filas['p1'] = filaDePrueba('p1', 'PÉREZ, JUAN');
      central = CentralPuerta(
        eventoId: eventoDeLaCentral,
        codigo: _codigo,
        pc: base,
      );
      puerto = await central.arrancar(
        desde: 0,
        en: InternetAddress.loopbackIPv4,
      );
      central.ponerPuerta(base.lista());
      // Como la PC (`CentralDeLaPuerta`): su chat va directo a la central.
      pc = ChatDelPuesto(
        yo: kPuestoDeLaPc,
        nombre: 'Pato',
        enviar: central.mandarDesdeLaPc,
      );
      central
        ..nombreDeLaPc = 'Pato'
        ..alLlegarALaPc = (m) {
          llegaronALaPc.add(m);
          pc.recibir(m);
        };
    });

    tearDown(() async {
      for (final c in clientes) {
        c.dispose();
      }
      clientes.clear();
      pc.dispose();
      await central.cerrar();
    });

    test(
      'cada celular sabe con quién puede hablar: la PC y los otros',
      () async {
        final juli = await celular('Juli');
        final vero = await celular('Vero');
        await _hasta(
          () => juli.chat.conversaciones.length == 3,
          'los puestos en Juli',
        );
        expect(
          [for (final c in juli.chat.conversaciones) c.nombre],
          ['Todos', 'Pato', 'Vero'],
        );
        // A Vero la lista le llega un instante después: se la espera. Sin
        // esperar, con la PC ocupada (la corrida entera) fallaba cada tanto.
        await _hasta(
          () => vero.chat.conversaciones.any((c) => c.nombre == 'Juli'),
          'Juli en Vero',
        );
        expect(vero.chat.conversaciones.map((c) => c.nombre), contains('Juli'));
      },
    );

    test('a Todos le llega a todos; a una, solo a esa', () async {
      final juli = await celular('Juli');
      final vero = await celular('Vero');

      juli.chat.mandar('Llegó el micro', kTodos);
      await _hasta(() => vero.chat.de(kTodos).isNotEmpty, 'Vero, a todos');
      await _hasta(() => llegaronALaPc.isNotEmpty, 'la PC, a todos');
      expect(vero.chat.de(kTodos).single.deNombre, 'Juli');
      expect(juli.chat.de(kTodos), hasLength(1), reason: 'sin repetirse');

      juli.chat.mandar('¿la 12?', idDe(vero));
      await _hasta(() => vero.chat.de(idDe(juli)).isNotEmpty, 'Vero, a ella');
      expect(vero.chat.sinLeer, 2);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        llegaronALaPc,
        hasLength(1),
        reason: 'la PC no ve lo de Juli a Vero',
      );

      pc.mandar('Juli, vení a la puerta', idDe(juli));
      await _hasta(
        () => juli.chat.de(kPuestoDeLaPc).isNotEmpty,
        'Juli, de la PC',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(vero.chat.de(kPuestoDeLaPc), isEmpty);
    });

    test('nadie escribe con el nombre de otro: lo dice la conexión', () async {
      final vero = await celular('Vero');
      // Otro programa conectado como "Juli" manda un mensaje que dice venir
      // de la PC.
      final crudo = await CelularDePrueba.conectar(
        puerto,
        codigo: _codigo,
        id: 'cel-juli',
        nombre: 'Juli',
      );
      addTearDown(crudo.irse);
      await crudo.espera('puerta');
      crudo.ws.add(
        jsonEncode({
          't': 'chat',
          'm': _msj('falso', kPuestoDeLaPc, null, 'soy la PC').toJson(),
        }),
      );
      await _hasta(() => vero.chat.de(kTodos).isNotEmpty, 'llega');
      expect(vero.chat.de(kTodos).single.de, 'cel-juli');
      expect(vero.chat.de(kTodos).single.deNombre, 'Juli');
      expect(llegaronALaPc.single.deNombre, 'Juli');
    });

    test(
      'la lista de puestos se manda al llegar y cuando cambia, no en cada latido',
      () async {
        final crudo = await CelularDePrueba.conectar(
          puerto,
          codigo: _codigo,
          id: 'cel-juli',
          nombre: 'Juli',
        );
        addTearDown(crudo.irse);
        await crudo.espera('puestos');
        final alLlegar = crudo.cuantos('puestos');
        for (var i = 0; i < 5; i++) {
          crudo.ws.add(jsonEncode({'t': 'hola'}));
          await crudo.espera('hola');
        }
        expect(
          crudo.cuantos('puestos'),
          alLlegar,
          reason: 'el latido no la vuelve a mandar',
        );

        await celular('Vero');
        await _hasta(() => crudo.cuantos('puestos') > alLlegar, 'llegó Vero');
      },
    );

    test('el que se conecta tarde recibe lo suyo, ya leído', () async {
      final juli = await celular('Juli');
      pc.mandar('Arrancamos', kTodos);
      pc.mandar('solo para Juli', idDe(juli));
      await _hasta(() => juli.chat.de(kPuestoDeLaPc).isNotEmpty, 'Juli');

      final vero = await celular('Vero');
      await _hasta(() => vero.chat.de(kTodos).isNotEmpty, 'la historia');
      expect(vero.chat.de(kTodos).single.texto, 'Arrancamos');
      expect(vero.chat.de(kPuestoDeLaPc), isEmpty);
      expect(vero.chat.sinLeer, 0);
    });
  });

  group('en pantalla', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<ChatDelPuesto> montar(WidgetTester tester, Size tam) async {
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chat = ChatDelPuesto(yo: 'juli', nombre: 'Juli', enviar: (_) {})
        ..ponerPuestos(const [
          PuestoDelChat(id: kPuestoDeLaPc, nombre: 'Pato', conectado: true),
          PuestoDelChat(id: 'vero', nombre: 'Vero', conectado: true),
        ]);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            appBar: AppBar(actions: [BotonChat(chat: chat)]),
            body: Column(children: [AvisoDelChat(chat: chat)]),
          ),
        ),
      );
      return chat;
    }

    testWidgets(
      'en el celular: el aviso, el número y la conversación de a uno',
      (tester) async {
        final chat = await montar(tester, const Size(390, 844));
        chat.recibir(_msj('1', kPuestoDeLaPc, 'juli', '¿alguien vio a GÓMEZ?'));
        await tester.pump();
        expect(find.text('PC, a vos: '), findsNothing);
        expect(find.textContaining('a vos'), findsOneWidget);
        expect(find.byKey(const ValueKey('chat_sin_leer')), findsOneWidget);

        // Tocar el aviso abre esa conversación.
        await tester.tap(find.byKey(const ValueKey('aviso_del_chat')));
        await tester.pumpAndSettle();
        expect(find.text('¿alguien vio a GÓMEZ?'), findsOneWidget);
        expect(chat.sinLeer, 0);

        // Atrás, la lista de a quién hablarle.
        await tester.tap(find.byKey(const ValueKey('volver_a_la_lista')));
        await tester.pumpAndSettle();
        expect(find.text(HojaChat.titulo), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('conversacion_vero')));
        await tester.pumpAndSettle();
        FilledButton enviar() => tester.widget<FilledButton>(
          find.byKey(const ValueKey('enviar_chat')),
        );
        expect(enviar().onPressed, isNull, reason: 'vacío no se manda');
        await tester.enterText(
          find.byKey(const ValueKey('texto_del_chat')),
          'voy',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('enviar_chat')));
        await tester.pump();
        expect(chat.de('vero').single.texto, 'voy');
        expect(find.text('voy'), findsOneWidget);
      },
    );

    testWidgets('en la PC: la lista y la conversación lado a lado', (
      tester,
    ) async {
      final chat = await montar(tester, const Size(1366, 900));
      await tester.tap(find.byKey(const ValueKey('boton_chat')));
      await tester.pumpAndSettle();
      expect(find.text(HojaChat.titulo), findsOneWidget);
      expect(find.text('Lo ven todos los puestos'), findsOneWidget);
      expect(chat.abierta, kTodos);
      await tester.tap(
        find.byKey(const ValueKey('conversacion_$kPuestoDeLaPc')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Escribile a Pato.'), findsOneWidget);
    });
  });
}
