import 'dart:io';

import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/tele/busqueda_de_la_tele.dart';
import 'package:arguello_events/features/tele/cliente_de_la_tele.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/central_en_memoria.dart';

/// La Tele 2 de verdad ([ClienteDeLaTele]) contra la central de verdad de la
/// Tele 1, por la red de esta PC (la tele es el tótem, 24-nov-2026).
const _evento = eventoDeLaCentral;
const _codigo = '4821';

void main() {
  late PcEnMemoria pc;
  late CentralPuerta central;
  late int puerto;
  final abiertos = <CelularDePrueba>[];
  final clientes = <ClienteDeLaTele>[];

  void conLaBase() {
    void avisar() => central
      ..ponerPuerta(pc.lista())
      ..ponerFilas(pc.filas.values.toList());
    pc.alCambiar = avisar;
    avisar();
  }

  setUp(() async {
    pc = PcEnMemoria()
      ..filas['p1'] = filaDePrueba('p1', 'PÉREZ, JUAN')
      ..filas['p2'] = filaDePrueba('p2', 'ACOSTA, LUCÍA', adentro: true);
    central = CentralPuerta(
      eventoId: _evento,
      codigo: _codigo,
      pc: pc,
      esTele: true,
    );
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    conLaBase();
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

  /// La Tele 2, con lo que copia en su base y cómo saluda, en memoria.
  ({ClienteDeLaTele cliente, List<List<Map<String, dynamic>>> copiadas, Map<String, BienvenidaDeLaNoche> bienvenidas, List<String> orden, List<TiemposAMano> tiempos})
      laTele2({String evento = _evento, String? direccion}) {
    final copiadas = <List<Map<String, dynamic>>>[];
    final bienvenidas = <String, BienvenidaDeLaNoche>{};
    final orden = <String>[];
    final tiempos = <TiemposAMano>[];
    final cliente = ClienteDeLaTele(
      eventoId: evento,
      numero: 2,
      direccionAMano: direccion ?? '127.0.0.1:$puerto',
      alRecibirBienvenidas: (b) {
        orden.add('bienvenidas');
        bienvenidas.addAll(b);
      },
      alRecibirFilas: (f) async {
        orden.add('filas');
        copiadas.add(f);
      },
      alRecibirTiempos: tiempos.add,
      tiemposAlConectar: () => TiemposAMano(nombre: 6, camino: 10),
    );
    clientes.add(cliente);
    cliente.arrancar();
    return (
      cliente: cliente,
      copiadas: copiadas,
      bienvenidas: bienvenidas,
      orden: orden,
      tiempos: tiempos,
    );
  }

  Future<void> hasta(bool Function() listo) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (!listo()) {
      if (DateTime.now().isAfter(limite)) throw StateError('no pasó');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('se conecta, copia la lista entera y queda con el código para el QR', () async {
    final t = laTele2();
    await hasta(() => t.copiadas.isNotEmpty);
    expect(t.cliente.estado, EstadoDeLaSegunda.conectada);
    expect(t.copiadas.first.map((f) => f['id']), containsAll(['p1', 'p2']));
    expect(t.cliente.copiadas, containsAll(['p1', 'p2']));
    expect(t.cliente.enlaceParaCelulares, 'http://127.0.0.1:$puerto/?c=$_codigo&t=2');
    // Le contó a la Tele 1 con qué segundos arrancó.
    await hasta(() => central.teles.single.conectada);
  });

  test('cómo se saluda llega antes que la fila: el tótem ya lo sabe cuando la base '
      'avisa', () async {
    final t = laTele2();
    await hasta(() => t.copiadas.isNotEmpty);
    final caro = await CelularDePrueba.conectar(puerto, codigo: _codigo, id: 'c', nombre: 'Caro', tele: 2);
    abiertos.add(caro);
    await caro.espera('puerta');
    await caro.pedirYEsperar('x', QuePide.ingresar, 'p1');
    await hasta(() => t.copiadas.length >= 2);
    final i = t.orden.lastIndexOf('filas');
    expect(t.orden[i - 1], 'bienvenidas');
    expect(seSaludaEnLaTele(t.bienvenidas['p1'], miTele: 2, ahora: DateTime.now()), isTrue);
  });

  test('los segundos que su recepcionista cambia le llegan', () async {
    final t = laTele2();
    await hasta(() => t.copiadas.isNotEmpty);
    central.ponerTiemposDeTele(2, TiemposAMano(nombre: 4, camino: 8));
    await hasta(() => t.tiempos.isNotEmpty);
    expect(t.tiempos.single, TiemposAMano(nombre: 4, camino: 8));
  });

  test('con una central que no es tele (la notebook): lo dice y no copia nada', () async {
    await central.cerrar();
    central = CentralPuerta(eventoId: _evento, codigo: _codigo, pc: pc);
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    conLaBase();
    final t = laTele2();
    await hasta(() => t.cliente.estado == EstadoDeLaSegunda.otraFiesta);
    expect(t.copiadas, isEmpty);
  });

  group('cada tele con su escuela (25-nov-2026)', () {
    const otra = 'e0000000-0000-4000-8000-0000000000ff';

    // Las que vienen, como las pone la tele (LA FIESTA).
    setUp(() => central.ponerEscuelasParaElegir([EscuelaParaElegir(otra, 'OTRA ESCUELA')]));

    test('con una escuela que no es de esta tele no entra: no se atiende ni se lleva la '
        'lista (revisión del 26-nov)', () async {
      const inventada = 'e0000000-0000-4000-8000-0000000000aa';
      final t = laTele2(evento: inventada);
      await hasta(() => t.cliente.estado == EstadoDeLaSegunda.otraFiesta);
      expect(central.escuelaDeTele(2), isNull);
      expect(central.atiende, [_evento]);
      expect(t.copiadas, isEmpty);
      expect(t.cliente.codigo, isNull, reason: 'no se lleva el código de los celulares');
    });

    test('de otra escuela: se conecta y la Tele 1 la atiende', () async {
      final t = laTele2(evento: otra);
      await hasta(() => t.cliente.estado == EstadoDeLaSegunda.conectada);
      expect(central.escuelaDeTele(2), otra);
      expect(t.cliente.escuelaDeLaTele1, _evento);
      expect(t.cliente.atiende, [_evento, otra]);
    });

    test('cambia de escuela sin desconectarse', () async {
      final t = laTele2();
      await hasta(() => t.copiadas.isNotEmpty);
      final conexiones = central.teles.single;
      t.cliente.cambiarEscuela(otra);
      await hasta(() => central.escuelaDeTele(2) == otra);
      expect(t.cliente.estado, EstadoDeLaSegunda.conectada);
      expect(t.cliente.eventoId, otra);
      expect(central.teles.single.conectada, conexiones.conectada);
    });

    test('la Tele 1 le pide otra escuela (un celular): la tele la muestra', () async {
      final pedidas = <(String, String?)>[];
      final girada = <String>[];
      final cliente = ClienteDeLaTele(
        eventoId: _evento,
        numero: 2,
        direccionAMano: '127.0.0.1:$puerto',
        alRecibirBienvenidas: (_) {},
        alRecibirFilas: (_) async {},
        alPedirEscuela: (e, por) => pedidas.add((e, por)),
        alGirar: girada.add,
      );
      clientes.add(cliente);
      cliente.arrancar();
      await hasta(() => cliente.estado == EstadoDeLaSegunda.conectada);
      final caro = await CelularDePrueba.conectar(puerto, codigo: _codigo, id: 'c', nombre: 'Caro', tele: 2);
      abiertos.add(caro);
      await caro.espera('puerta');
      caro.mandar({'t': 'escuela', 'tele': 2, 'evento': otra});
      caro.mandar({'t': 'girar', 'tele': 2, 'como': 'vertical'});
      await hasta(() => pedidas.isNotEmpty && girada.isNotEmpty);
      expect(pedidas.single, (otra, 'Caro'));
      expect(cliente.eventoId, otra);
      expect(girada.single, 'vertical');
    });

    test('la encuentra sola aunque la Tele 1 tenga otra escuela', () async {
      const puertoDeBusqueda = 28779;
      final responde = RespondeLaTele1(puertoCentral: puerto, conoce: central.conoce);
      expect(
        await responde.escuchar(puerto: puertoDeBusqueda, en: InternetAddress.loopbackIPv4),
        isTrue,
      );
      final cliente = ClienteDeLaTele(
        eventoId: otra,
        numero: 2,
        busca: BuscaCentral(
          eventoId: otra,
          puerto: puertoDeBusqueda,
          cada: const Duration(milliseconds: 200),
          destinos: () async => [InternetAddress.loopbackIPv4],
        ),
        alRecibirBienvenidas: (_) {},
        alRecibirFilas: (_) async {},
      );
      clientes.add(cliente);
      cliente.arrancar();
      await hasta(() => cliente.estado == EstadoDeLaSegunda.conectada);
      expect(central.escuelaDeTele(2), otra);
      responde.cerrar();
    });
  });

  test('se corta la Tele 1: sigue con lo que tenía, y al volver se reengancha', () async {
    final t = laTele2();
    await hasta(() => t.copiadas.isNotEmpty);
    await central.cerrar();
    await hasta(() => t.cliente.estado == EstadoDeLaSegunda.cortada);
    expect(t.cliente.cortadaDesde, isNotNull);
    // La Tele 1 vuelve en el mismo puerto.
    central = CentralPuerta(eventoId: _evento, codigo: _codigo, pc: pc, esTele: true);
    await central.arrancar(desde: puerto, en: InternetAddress.loopbackIPv4);
    conLaBase();
    await hasta(() => t.cliente.estado == EstadoDeLaSegunda.conectada);
  });

  test('la Tele 1 apagada: cada reintento que no conecta queda atendido, sin errores '
      'sueltos (lo mostró el emulador el 26-nov)', () async {
    // Un puerto donde no escucha nadie.
    final libre = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final cerrado = libre.port;
    await libre.close();
    final t = laTele2(direccion: '127.0.0.1:$cerrado');
    // Dos intentos (el segundo, al segundo): un error sin atender haría
    // fallar la prueba.
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    expect(t.cliente.estado, isNot(EstadoDeLaSegunda.conectada));
    expect(t.copiadas, isEmpty);
  });

  test('sin la dirección escrita, la encuentra sola: pregunta y la Tele 1 contesta',
      () async {
    // Un puerto de prueba, en esta PC: la Tele 1 de verdad escucha en el 8778.
    const puertoDeBusqueda = 28778;
    final responde = RespondeBusqueda(eventoId: _evento, puertoCentral: puerto);
    expect(
      await responde.escuchar(puerto: puertoDeBusqueda, en: InternetAddress.loopbackIPv4),
      isTrue,
    );
    final copiadas = <Map<String, dynamic>>[];
    final cliente = ClienteDeLaTele(
      eventoId: _evento,
      numero: 2,
      busca: BuscaCentral(
        eventoId: _evento,
        puerto: puertoDeBusqueda,
        cada: const Duration(milliseconds: 200),
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
      alRecibirBienvenidas: (_) {},
      alRecibirFilas: (f) async => copiadas.addAll(f),
    );
    clientes.add(cliente);
    cliente.arrancar();
    await hasta(() => cliente.estado == EstadoDeLaSegunda.conectada);
    expect(cliente.donde?.puerto, puerto);
    await hasta(() => copiadas.isNotEmpty);
    responde.cerrar();
  });
}
