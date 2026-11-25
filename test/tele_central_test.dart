import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/central_en_memoria.dart';

/// La tele es el tótem (24-nov-2026): la central de la puerta corre en la Tele
/// 1. Los celulares eligen "Tu tele" y la Tele 2 se le conecta y copia la
/// lista. Todo por la red de esta PC, como en el salón; la base, en memoria.
const _evento = eventoDeLaCentral;
const _codigo = '4821';

void main() {
  late PcEnMemoria pc;
  late CentralPuerta central;
  late int puerto;
  late DateTime ahora;
  final abiertos = <CelularDePrueba>[];

  Future<CelularDePrueba> celular(String nombre, {int? tele}) async {
    final c = await CelularDePrueba.conectar(
      puerto,
      codigo: _codigo,
      id: 'cel-$nombre',
      nombre: nombre,
      tele: tele,
    );
    abiertos.add(c);
    return c;
  }

  Future<CelularDePrueba> tele2({String evento = _evento}) async {
    final t = await CelularDePrueba.conectarTele(puerto, evento: evento);
    abiertos.add(t);
    return t;
  }

  /// La base avisa el cambio y Recepción le pasa la lista a la central, como
  /// en la app (`CentralDeLaPuerta`).
  void conLaBase() {
    void avisar() {
      central
        ..ponerPuerta(pc.lista())
        ..ponerFilas(pc.filas.values.toList());
    }

    pc.alCambiar = avisar;
    avisar();
  }

  setUp(() async {
    pc = PcEnMemoria()
      ..filas['p1'] = filaDePrueba('p1', 'PÉREZ, JUAN')
      ..filas['p2'] = filaDePrueba('p2', 'ACOSTA, LUCÍA')
      ..filas['p3'] = filaDePrueba('p3', 'GÓMEZ, ANA', adentro: true);
    ahora = DateTime(2026, 12, 12, 22);
    central = CentralPuerta(
      eventoId: _evento,
      codigo: _codigo,
      pc: pc,
      ahora: () => ahora,
      esTele: true,
    );
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    conLaBase();
  });

  tearDown(() async {
    for (final c in abiertos) {
      try {
        await c.ws.close();
      } catch (_) {}
    }
    abiertos.clear();
    await central.cerrar();
  });

  group('cada recepcionista controla su tele', () {
    test('lo que marca Juli (Tele 1) se saluda en la 1; lo de Caro (Tele 2), en la 2',
        () async {
      final juli = await celular('Juli', tele: 1);
      final caro = await celular('Caro', tele: 2);
      await juli.espera('puerta');
      await caro.espera('puerta');

      expect((await juli.pedirYEsperar('a', QuePide.ingresar, 'p1'))['hizo'], 'ingresar');
      expect((await caro.pedirYEsperar('b', QuePide.ingresar, 'p2'))['hizo'], 'ingresar');

      final b1 = central.marcas.bienvenida('p1');
      final b2 = central.marcas.bienvenida('p2');
      expect(seSaludaEnLaTele(b1, miTele: 1, ahora: ahora), isTrue);
      expect(seSaludaEnLaTele(b1, miTele: 2, ahora: ahora), isFalse);
      expect(seSaludaEnLaTele(b2, miTele: 2, ahora: ahora), isTrue);
      expect(seSaludaEnLaTele(b2, miTele: 1, ahora: ahora), isFalse);
    });

    test('la segunda que ingresa a la misma persona recibe "ya ingresó", y no se '
        'saluda dos veces', () async {
      final juli = await celular('Juli', tele: 1);
      final caro = await celular('Caro', tele: 2);
      await juli.espera('puerta');
      await caro.espera('puerta');
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1');
      final r = await caro.pedirYEsperar('b', QuePide.ingresar, 'p1');
      expect(r['hizo'], 'nada');
      expect(r['aviso'], contains('ya ingresó'));
      expect(r['aviso'], contains('Juli'));
      expect(pc.ingresos.length, 1);
      // Sigue siendo de la Tele 1: Caro no le cambió la tele.
      expect(central.marcas.bienvenida('p1')!.tele, 1);
    });

    test('"Las dos": se saluda en las dos teles', () async {
      final juli = await celular('Juli', tele: kLasDosTeles);
      await juli.espera('puerta');
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1');
      final b = central.marcas.bienvenida('p1');
      expect(seSaludaEnLaTele(b, miTele: 1, ahora: ahora), isTrue);
      expect(seSaludaEnLaTele(b, miTele: 2, ahora: ahora), isTrue);
    });

    test('cambiar de tele desde el celular vale para lo que marca después', () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      juli.elegirTele(2);
      await juli.espera('teles', cumple: (m) {
        final lista = m['lista'] as List;
        return lista.any((t) => t['n'] == 2 && (t['maneja'] as List).contains('Juli'));
      });
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1');
      expect(central.marcas.bienvenida('p1')!.tele, 2);
    });

    test('un pedido que trae su tele (tocado sin wifi) se saluda en esa, aunque el '
        'celular haya cambiado después', () async {
      final juli = await celular('Juli', tele: 2);
      await juli.espera('puerta');
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1', tele: 1);
      expect(central.marcas.bienvenida('p1')!.tele, 1);
    });

    test('lo que llega tarde (sin wifi más de un minuto) se marca y no se saluda en '
        'ninguna', () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1',
          hace: const Duration(minutes: 3));
      expect(pc.filas['p1']!.estadoIngreso, EstadoIngreso.ingresado);
      final b = central.marcas.bienvenida('p1');
      expect(seSaludaEnLaTele(b, miTele: 1, ahora: ahora), isFalse);
      expect(seSaludaEnLaTele(b, miTele: 2, ahora: ahora), isFalse);
    });

    test('deshacer saca la bienvenida: si lo vuelven a marcar, se saluda de nuevo',
        () async {
      final juli = await celular('Juli', tele: 1);
      await juli.espera('puerta');
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1');
      await juli.pedirYEsperar('b', QuePide.deshacer, 'p1');
      expect(central.marcas.bienvenida('p1'), isNull);
    });

    test('cada celular ve qué teles hay y quién maneja cada una', () async {
      final juli = await celular('Juli', tele: 1);
      final t = await juli.espera('teles');
      final lista = (t['lista'] as List).cast<Map<String, dynamic>>();
      expect(lista.map((x) => x['n']), [1, 2]);
      expect(lista.first['maneja'], ['Juli']);
      expect(lista.last['conectada'], isFalse);
      final p = await juli.espera('puerta');
      expect(p['central'], 'Tele 1');
    });
  });

  group('la Tele 2', () {
    test('al conectarse recibe el código y la lista entera, con quién ya entró', () async {
      final t = await tele2();
      final hola = await t.espera('central');
      expect(hola['codigo'], _codigo);
      final filas = await t.espera('filas');
      final ids = [for (final f in filas['filas'] as List) f['id']];
      expect(ids, containsAll(['p1', 'p2', 'p3']));
      // Lo de antes de conectarse no trae bienvenida: no se saluda.
      expect(filas['bienvenidas'], isEmpty);
      // Sin el DNI: no hace falta en la tele.
      expect((filas['filas'] as List).first.containsKey('dni'), isFalse);
      expect(central.teles.single.conectada, isTrue);
    });

    test('un ingreso de Caro le llega con su bienvenida; solo la fila que cambió',
        () async {
      final t = await tele2();
      await t.espera('filas');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      await caro.pedirYEsperar('b', QuePide.ingresar, 'p2');
      final cambio = await t.espera('filas');
      expect([for (final f in cambio['filas'] as List) f['id']], ['p2']);
      final b = BienvenidaDeLaNoche.fromJson(
        (cambio['bienvenidas'] as Map)['p2'],
        ahora,
      );
      expect(seSaludaEnLaTele(b, miTele: 2, ahora: ahora), isTrue);
      expect(seSaludaEnLaTele(b, miTele: 1, ahora: ahora), isFalse);
    });

    test('una tele de otra fiesta no se conecta', () async {
      final t = await tele2(evento: 'e0000000-0000-4000-8000-0000000000ff');
      await t.espera('evento');
      expect(await t.cerro(), 4001);
      expect(central.teles.single.conectada, isFalse);
    });

    test('los segundos de la Tele 2 van a la Tele 2; los de la 1, a la 1', () async {
      final t = await tele2();
      await t.espera('filas');
      final caro = await celular('Caro', tele: 2);
      await caro.espera('puerta');
      await caro.pedirYEsperar('s', QuePide.tiemposTotem, '',
          tiempos: TiemposAMano(nombre: 5, camino: 9), tele: 2);
      // La central es la que reparte: acá la base de la Tele 1 recibe la tele.
      expect(pc.telesDeLosTiempos.last, 2);
      central.ponerTiemposDeTele(2, TiemposAMano(nombre: 5, camino: 9));
      final llegaron = await t.espera('tiempos');
      expect(TiemposAMano.fromJson(llegaron['tiempos']),
          TiemposAMano(nombre: 5, camino: 9));
      final p = await caro.espera('puerta',
          cumple: (m) => m['tiemposTeles'] != null);
      expect(TiemposAMano.fromJson((p['tiemposTeles'] as Map)['2']),
          TiemposAMano(nombre: 5, camino: 9));
    });

    test('quién maneja la Tele 2 le llega a la Tele 2', () async {
      final t = await tele2();
      await t.espera('filas');
      await celular('Caro', tele: 2);
      final m = await t.espera('maneja',
          cumple: (m) => (m['nombres'] as List).contains('Caro'));
      expect(m['nombres'], ['Caro']);
    });
  });

  group('con la central en la notebook, como siempre', () {
    test('sin teles: no manda "teles" ni acepta una Tele 2, y el pedido no lleva tele',
        () async {
      await central.cerrar();
      central = CentralPuerta(
        eventoId: _evento,
        codigo: _codigo,
        pc: pc,
        ahora: () => ahora,
      );
      puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      conLaBase();
      final juli = await celular('Juli', tele: 2);
      final p = await juli.espera('puerta');
      expect(p.containsKey('central'), isFalse);
      await juli.pedirYEsperar('a', QuePide.ingresar, 'p1');
      expect(juli.cuantos('teles'), 0);
      expect(central.marcas.bienvenida('p1')!.tele, isNull);
      final t = await tele2();
      expect(await t.cerro(), 4001);
    });
  });
}
