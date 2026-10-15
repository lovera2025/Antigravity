import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/central_en_memoria.dart';

/// El celular de la puerta (`ClienteCentral`) contra la central de verdad,
/// escuchando solo en esta PC. Lo único en memoria es la base de la notebook
/// ([PcEnMemoria]) y lo que el celular guarda en su navegador.
///
/// Lo que se cuida: que sin conexión se siga marcando y nada se pierda, que
/// llegue en orden y sin saludar tarde, y que la central sea la que decide.
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

/// Hasta que [condicion] se cumpla, o falla a los 5 s.
Future<void> _hasta(bool Function() condicion, [String que = '']) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!condicion()) {
    if (DateTime.now().isAfter(limite)) {
      throw TimeoutException('no pasó: $que');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late PcEnMemoria pc;
  late CentralPuerta central;
  late int puerto;
  late DateTime ahora;
  final clientes = <ClienteCentral>[];

  Future<CentralPuerta> abrirCentral({int? enPuerto, String codigo = _codigo}) async {
    final c = CentralPuerta(eventoId: eventoDeLaCentral, codigo: codigo, pc: pc)
      ..ponerTitulo('ESCUELA DE MUESTRA — Egresados (12/12) · particular');
    puerto = await c.arrancar(
      desde: enPuerto ?? 0,
      en: InternetAddress.loopbackIPv4,
    );
    c.ponerPuerta(pc.lista());
    // Como Recepción: cada cambio en la base vuelve a armar la lista.
    pc.alCambiar = () => c.ponerPuerta(pc.lista());
    return c;
  }

  ClienteCentral cliente(_NavegadorEnMemoria navegador) {
    final c = ClienteCentral(
      servidor: Uri.parse('http://127.0.0.1:$puerto/'),
      guardado: navegador,
      ahora: () => ahora,
      latido: const Duration(milliseconds: 40),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 40),
    );
    clientes.add(c);
    return c;
  }

  /// Un celular ya con nombre y conectado.
  Future<ClienteCentral> conectado(
    _NavegadorEnMemoria navegador, {
    String nombre = 'Juli',
  }) async {
    final c = cliente(navegador);
    await c.iniciar(codigoDelEnlace: _codigo);
    await c.ponerDatos(nombre: nombre);
    await _hasta(() => c.puerta != null, 'la lista');
    return c;
  }

  PersonaPuerta persona(ClienteCentral c, String id) =>
      c.puerta!.personas.firstWhere((p) => p.id == id);

  setUp(() async {
    ahora = DateTime(2026, 12, 12, 22, 40);
    pc = PcEnMemoria()
      ..filas['p1'] = filaDePrueba('p1', 'PÉREZ, JUAN')
      ..filas['p2'] = filaDePrueba('p2', 'ACOSTA, LUCÍA');
    central = await abrirCentral();
  });

  tearDown(() async {
    for (final c in clientes) {
      c.dispose();
    }
    clientes.clear();
    await central.cerrar();
  });

  group('la primera vez', () {
    test('con el código del QR, pide solo el nombre y se conecta', () async {
      final navegador = _NavegadorEnMemoria();
      final c = cliente(navegador);
      await c.iniciar(codigoDelEnlace: _codigo);
      expect(c.estado, EstadoDelPuesto.faltanDatos);

      await c.ponerDatos(nombre: '  Juli ');
      await _hasta(() => c.estado == EstadoDelPuesto.conectado);
      await _hasta(() => c.puerta != null);
      expect(c.puerta!.total, 2);
      expect(c.titulo, 'ESCUELA DE MUESTRA — Egresados (12/12) · particular');
      expect(c.eventoId, eventoDeLaCentral);
      expect(navegador.datos['puesto_nombre'], 'Juli');
      expect(central.puestos.single.nombre, 'Juli');
    });

    test('la segunda vez ya no pregunta nada', () async {
      final navegador = _NavegadorEnMemoria();
      final primero = await conectado(navegador);
      final celular = navegador.datos['puesto_celular'];
      primero.dispose();
      clientes.remove(primero);

      // Abre la dirección sola, sin el código en el enlace.
      final segundo = cliente(navegador);
      await segundo.iniciar();
      await _hasta(() => segundo.puerta != null);
      expect(navegador.datos['puesto_celular'], celular);
    });

    test('entrando con la dirección, pide también el código', () async {
      final c = cliente(_NavegadorEnMemoria());
      await c.iniciar();
      expect(c.estado, EstadoDelPuesto.faltanDatos);
      await c.ponerDatos(nombre: 'Juli');
      expect(c.estado, EstadoDelPuesto.faltanDatos);
      await c.ponerDatos(nombre: 'Juli', codigo: _codigo);
      await _hasta(() => c.puerta != null);
    });
  });

  group('marcar', () {
    test('lo ingresado se ve al instante, y la central lo marca', () async {
      final c = await conectado(_NavegadorEnMemoria());
      final ingreso = c.ingresar(persona(c, 'p1'));
      // Antes de la respuesta, ya se ve adentro.
      expect(persona(c, 'p1').ingresado, isTrue);
      await ingreso;

      await _hasta(() => pc.ingresos.isNotEmpty, 'el ingreso');
      expect(pc.ingresos, [('p1', true)]);
      await _hasta(() => c.pendientes.isEmpty, 'la respuesta');
      expect(persona(c, 'p1').ingresado, isTrue);
      expect(c.marca('p1'), 'Juli');
    });

    test('deshacer vuelve a dejarlo afuera', () async {
      final c = await conectado(_NavegadorEnMemoria());
      await c.ingresar(persona(c, 'p1'));
      await _hasta(() => pc.ingresos.isNotEmpty);
      await c.deshacer(persona(c, 'p1'));
      expect(persona(c, 'p1').ingresado, isFalse);
      await _hasta(() => pc.deshechos.isNotEmpty);
      await _hasta(() => c.pendientes.isEmpty);
      expect(persona(c, 'p1').ingresado, isFalse);
    });

    test('si otro celular ya lo ingresó, la central lo dice', () async {
      final juli = await conectado(_NavegadorEnMemoria());
      final pato = await conectado(_NavegadorEnMemoria(), nombre: 'Pato');
      final avisos = <String>[];
      final escucha = pato.avisos.listen(avisos.add);
      addTearDown(escucha.cancel);

      await juli.ingresar(persona(juli, 'p1'));
      await _hasta(() => pc.ingresos.isNotEmpty);
      // A Pato todavía le puede faltar la lista nueva: lo toca igual.
      await pato.ingresar(persona(pato, 'p1'));
      await _hasta(() => avisos.isNotEmpty, 'el aviso');

      expect(pc.ingresos, hasLength(1));
      expect(avisos.single, contains('PÉREZ, JUAN ya ingresó'));
      expect(avisos.single, contains('· Juli'));
      // En la fila queda lo de la central, no lo que tocó Pato.
      await _hasta(() => pato.marca('p1') == 'Juli', 'el nombre de la central');
      expect(persona(pato, 'p1').horaIngreso, horaDeLaCentral.toLocal());
    });

    test('si la central no pudo, lo vuelve a mandar solo', () async {
      final c = await conectado(_NavegadorEnMemoria());
      pc.falla = true;
      await c.ingresar(persona(c, 'p1'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.pendientes, hasLength(1));
      pc.falla = false;
      await _hasta(() => c.pendientes.isEmpty, 'el reintento');
      expect(pc.ingresos, [('p1', true)]);
    });
  });

  group('sin conexión con la central', () {
    test('se sigue marcando, se guarda, y al volver se manda en orden', () async {
      final navegador = _NavegadorEnMemoria();
      final c = await conectado(navegador);

      await central.cerrar();
      await _hasta(() => c.estado == EstadoDelPuesto.sinConexion, 'el corte');

      await c.ingresar(persona(c, 'p1'));
      await c.ingresar(persona(c, 'p2'));
      await c.deshacer(persona(c, 'p2'));
      expect(persona(c, 'p1').ingresado, isTrue);
      expect(persona(c, 'p2').ingresado, isFalse);
      expect(c.pendientes, hasLength(3));
      expect(c.marca('p1'), kPorMandar);
      expect(navegador.datos['puesto_pendientes'], isNotNull);

      // La central vuelve en el mismo lugar (la notebook se reinició).
      central = await abrirCentral(enPuerto: puerto);
      await _hasta(() => c.pendientes.isEmpty, 'que se mande todo');

      expect(pc.ingresos, [('p1', true), ('p2', true)]);
      expect(pc.deshechos, ['p2']);
      expect(c.estado, EstadoDelPuesto.conectado);
      expect(c.seMandaron, 3);
      expect(c.marca('p1'), 'Juli');
    });

    test('lo que se mandó más de un minuto después, no se saluda', () async {
      final c = await conectado(_NavegadorEnMemoria());
      await central.cerrar();
      await _hasta(() => c.estado == EstadoDelPuesto.sinConexion);

      await c.ingresar(persona(c, 'p1'));
      ahora = ahora.add(const Duration(minutes: 3));
      await c.ingresar(persona(c, 'p2'));

      central = await abrirCentral(enPuerto: puerto);
      await _hasta(() => pc.ingresos.length == 2);
      expect(pc.ingresos, [('p1', false), ('p2', true)]);
    });

    test('lo marcado sobrevive a cerrar el navegador', () async {
      final navegador = _NavegadorEnMemoria();
      final c = await conectado(navegador);
      await central.cerrar();
      await _hasta(() => c.estado == EstadoDelPuesto.sinConexion);
      await c.ingresar(persona(c, 'p1'));
      c.dispose();
      clientes.remove(c);

      central = await abrirCentral(enPuerto: puerto);
      final otra = cliente(navegador);
      await otra.iniciar();
      expect(otra.pendientes, hasLength(1));
      await _hasta(() => otra.pendientes.isEmpty);
      expect(pc.ingresos, [('p1', true)]);
    });

    test('una central que no contesta (el wifi se cortó sin avisar) se da por '
        'caída', () async {
      // Una "central" que manda la lista y después no dice nada más.
      final muda = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => muda.close(force: true));
      final sockets = <WebSocket>[];
      muda.listen((pedido) async {
        final ws = await WebSocketTransformer.upgrade(pedido);
        sockets.add(ws);
        ws.add(jsonEncode({
          't': 'puerta',
          'v': 1,
          'evento': eventoDeLaCentral,
          'puerta': pc.lista().toJson(),
          'por': {},
        }));
        ws.listen((_) {});
      });
      addTearDown(() async {
        for (final s in sockets) {
          await s.close();
        }
      });

      final c = ClienteCentral(
        servidor: Uri.parse('http://127.0.0.1:${muda.port}/'),
        guardado: _NavegadorEnMemoria(),
        latido: const Duration(milliseconds: 30),
        silencioMaximo: const Duration(milliseconds: 200),
        pausa: const Duration(seconds: 10),
      );
      clientes.add(c);
      await c.iniciar(codigoDelEnlace: _codigo);
      await c.ponerDatos(nombre: 'Juli');
      await _hasta(() => c.estado == EstadoDelPuesto.conectado);
      await _hasta(() => c.estado == EstadoDelPuesto.sinConexion, 'el silencio');
    });
  });

  group('lo que dice la central', () {
    test('si cambia el código, deja de buscarla y pide el nuevo', () async {
      final c = await conectado(_NavegadorEnMemoria());
      await central.cambiarCodigo('5555');
      await _hasta(() => c.estado == EstadoDelPuesto.codigoMal);

      await c.ponerDatos(nombre: 'Juli', codigo: '5555');
      await _hasta(() => c.estado == EstadoDelPuesto.conectado);
    });

    test('el mismo celular en dos pestañas: queda la última', () async {
      final navegador = _NavegadorEnMemoria();
      final primera = await conectado(navegador);
      final segunda = cliente(navegador);
      await segunda.iniciar();
      await _hasta(() => segunda.puerta != null);
      await _hasta(() => primera.estado == EstadoDelPuesto.otraPestana);
      expect(central.puestos, hasLength(1));
    });
  });

  group('la lista con lo que falta mandar encima', () {
    final lista = PuertaDelEvento.particular([
      filaDePrueba('p1', 'PÉREZ, JUAN'),
      filaDePrueba('p2', 'ACOSTA, LUCÍA', adentro: true),
    ]).toJson();
    PedidoPendiente pend(QuePide que, String id) => PedidoPendiente(
          PedidoPuerta(id: 'x$id$que', que: que, personaId: id),
          marcado: DateTime.utc(2026, 12, 13, 1, 43),
        );
    PuertaDelEvento armar(List<PedidoPendiente> cambios) =>
        PuertaDelEvento.fromJson(
          listaConCambios(
            jsonDecode(jsonEncode(lista)) as Map<String, dynamic>,
            cambios,
          ),
          eventoId: eventoDeLaCentral,
        );

    test('ingresar deja adentro desde que se tocó; deshacer, afuera', () {
      final p = armar([
        pend(QuePide.ingresar, 'p1'),
        pend(QuePide.deshacer, 'p2'),
      ]);
      final juan = p.personas.firstWhere((x) => x.id == 'p1');
      expect(juan.ingresado, isTrue);
      expect(juan.horaIngreso, DateTime.utc(2026, 12, 13, 1, 43).toLocal());
      expect(p.personas.firstWhere((x) => x.id == 'p2').ingresado, isFalse);
    });

    test('en el orden en que se tocó', () {
      final p = armar([
        pend(QuePide.ingresar, 'p1'),
        pend(QuePide.deshacer, 'p1'),
      ]);
      expect(p.personas.firstWhere((x) => x.id == 'p1').ingresado, isFalse);
    });

    test('no toca la lista que mandó la central', () {
      final copia = jsonEncode(lista);
      listaConCambios(lista, [pend(QuePide.ingresar, 'p1')]);
      expect(jsonEncode(lista), copia);
    });

    test('lo guardado roto no se lee como pendiente', () {
      expect(PedidoPendiente.listaDesdeTexto('basura'), isEmpty);
      expect(PedidoPendiente.listaDesdeTexto('[{"id": 3}]'), isEmpty);
      final ida = PedidoPendiente.listaATexto([pend(QuePide.ingresar, 'p1')]);
      final vuelta = PedidoPendiente.listaDesdeTexto(ida);
      expect(vuelta.single.pedido.personaId, 'p1');
      expect(
        vuelta.single.marcado
            .isAtSameMomentAs(DateTime.utc(2026, 12, 13, 1, 43)),
        isTrue,
      );
    });
  });

  test('un alumno de un masivo sin fila todavía se ve adentro al tocarlo', () {
    final masivo = PuertaDelEvento.fromJson(
      {
        'masivo': true,
        'sorteado': false,
        'bajas': 0,
        'grupos': [
          {
            'titular': {
              'id': 'a1',
              'nombre': 'BENÍTEZ, TOMÁS',
              'dni': '',
              'mesa': null,
              'esAlumno': true,
              'acompanaA': null,
              'fila': null,
            },
            'acompanantes': [],
            'division': '5° B',
            'sinMesa': false,
            'sillas': null,
            'sillasAConfirmar': false,
            'musica': null,
            'acompanantesSinNombre': 0,
            'cargadoAMano': false,
          },
        ],
      },
      eventoId: eventoDeLaCentral,
    ).toJson();
    final con = PuertaDelEvento.fromJson(
      listaConCambios(masivo, [
        PedidoPendiente(
          const PedidoPuerta(id: 'z', que: QuePide.ingresar, personaId: 'a1'),
          marcado: DateTime.utc(2026, 12, 13, 1, 43),
        ),
      ]),
      eventoId: eventoDeLaCentral,
    );
    expect(con.personas.single.ingresado, isTrue);
    expect(con.personas.single.fila!.estadoIngreso, EstadoIngreso.ingresado);
  });
}
