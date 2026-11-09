import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/sillas_de_la_puerta.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:arguello_events/models/silla_puerta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/puerta_en_memoria.dart' show alumnoDePrueba, eventoMasivo;

/// Qué hace la central de la puerta con lo que le piden los celulares
/// (`pedidos_de_la_puerta.dart`).
///
/// Lo que se cuida: que dos celulares no se pisen, que un pedido repetido o
/// atrasado no haga lío, y que nunca se vuelva a crear a alguien que se sacó
/// de la lista.
final _hora = DateTime.utc(2026, 12, 13, 1, 41);

Invitado _fila(String id, {bool adentro = false}) => Invitado(
      id: id,
      eventoId: 'evento',
      nombreCompleto: 'PÉREZ, JUAN',
      dni: '',
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: adentro ? _hora : null,
    );

/// Una lista de un particular con una persona: con su fila ([conFila]) o, si
/// no, como un alumno de un masivo antes de que exista su fila.
PersonaPuerta _persona({bool conFila = true}) {
  if (conFila) {
    return PuertaDelEvento.particular([_fila('p1')]).personas.single;
  }
  final json = {
    'masivo': true,
    'sorteado': false,
    'bajas': 0,
    'grupos': [
      {
        'titular': {
          'id': 'p1',
          'nombre': 'PÉREZ, JUAN',
          'dni': '',
          'mesa': null,
          'esAlumno': true,
          'acompanaA': null,
          'fila': null,
        },
        'acompanantes': [],
        'division': null,
        'sinMesa': false,
        'sillas': null,
        'sillasAConfirmar': false,
        'musica': null,
        'acompanantesSinNombre': 0,
        'cargadoAMano': false,
      },
    ],
  };
  return PuertaDelEvento.fromJson(json, eventoId: 'evento').personas.single;
}

PedidoPuerta _pedido(QuePide que, {Duration hace = Duration.zero}) =>
    PedidoPuerta(id: 'x1', que: que, personaId: 'p1', hace: hace);

void main() {
  group('ingresar', () {
    test('si está afuera, se ingresa y se saluda', () {
      final d = decidirPedido(
        pedido: _pedido(QuePide.ingresar),
        persona: _persona(),
        fila: _fila('p1'),
      );
      expect(d.hace, QueHaceLaCentral.ingresar);
      expect(d.saludar, isTrue);
      expect(d.aviso, isNull);
    });

    test('si ya entró por otro celular, no se hace nada y se dice quién y a '
        'qué hora', () {
      final d = decidirPedido(
        pedido: _pedido(QuePide.ingresar),
        persona: _persona(),
        fila: _fila('p1', adentro: true),
        quien: 'Juli',
      );
      expect(d.hace, QueHaceLaCentral.nada);
      expect(d.aviso, 'PÉREZ, JUAN ya ingresó a las ${horaCorta(_hora)} · Juli.');
    });

    test('lo decide la base de ese momento, no la lista que tenía el celular',
        () {
      // La lista que se mandó lo tenía afuera; otro celular lo acaba de entrar.
      final persona = _persona();
      expect(persona.ingresado, isFalse);
      final d = decidirPedido(
        pedido: _pedido(QuePide.ingresar),
        persona: persona,
        fila: _fila('p1', adentro: true),
      );
      expect(d.hace, QueHaceLaCentral.nada);
      expect(d.aviso, 'PÉREZ, JUAN ya ingresó a las ${horaCorta(_hora)}.');
    });

    test('un alumno sin fila todavía (antes del sorteo) se ingresa', () {
      final d = decidirPedido(
        pedido: _pedido(QuePide.ingresar),
        persona: _persona(conFila: false),
        fila: null,
      );
      expect(d.hace, QueHaceLaCentral.ingresar);
    });

    test('hasta un minuto después de tocado se saluda; después, no', () {
      DecisionPedido con(Duration hace) => decidirPedido(
            pedido: _pedido(QuePide.ingresar, hace: hace),
            persona: _persona(),
            fila: _fila('p1'),
          );
      expect(con(const Duration(seconds: 59)).saludar, isTrue);
      expect(con(kSaludarHasta).saludar, isTrue);
      final tarde = con(const Duration(minutes: 3));
      expect(tarde.hace, QueHaceLaCentral.ingresar);
      expect(tarde.saludar, isFalse);
    });
  });

  group('deshacer', () {
    test('si está adentro, vuelve a faltar', () {
      final d = decidirPedido(
        pedido: _pedido(QuePide.deshacer),
        persona: _persona(),
        fila: _fila('p1', adentro: true),
      );
      expect(d.hace, QueHaceLaCentral.deshacer);
    });

    test('si ya estaba afuera, no se hace nada', () {
      final d = decidirPedido(
        pedido: _pedido(QuePide.deshacer),
        persona: _persona(),
        fila: _fila('p1'),
      );
      expect(d.hace, QueHaceLaCentral.nada);
      expect(d.aviso, 'PÉREZ, JUAN no figuraba adentro.');
    });
  });

  group('quien ya no está en la lista', () {
    test('no se toca', () {
      for (final que in QuePide.values) {
        final d = decidirPedido(
          pedido: _pedido(que),
          persona: null,
          fila: null,
        );
        expect(d.hace, QueHaceLaCentral.nada);
        expect(d.aviso, 'Esa persona ya no está en la lista de la puerta.');
      }
    });

    test('si la lista tenía su fila y la base ya no, no se vuelve a crear', () {
      // Se eliminó de Recepción, o se deshizo el sorteo, justo antes del pedido.
      final d = decidirPedido(
        pedido: _pedido(QuePide.ingresar),
        persona: _persona(),
        fila: null,
      );
      expect(d.hace, QueHaceLaCentral.nada);
      expect(d.aviso, 'Esa persona ya no está en la lista de la puerta.');
    });
  });

  group('lo que llega de la red', () {
    test('un pedido va y vuelve igual', () {
      const p = PedidoPuerta(
        id: 'abc',
        que: QuePide.deshacer,
        personaId: 'p1',
        hace: Duration(seconds: 7),
      );
      final llego = PedidoPuerta.fromJson(p.toJson())!;
      expect(llego.id, 'abc');
      expect(llego.que, QuePide.deshacer);
      expect(llego.personaId, 'p1');
      expect(llego.hace, const Duration(seconds: 7));
    });

    test('lo que no se entiende no es un pedido', () {
      for (final roto in <Map<String, dynamic>>[
        {},
        {'id': 'a', 'que': 'borrar', 'persona': 'p1'},
        {'id': '', 'que': 'ingresar', 'persona': 'p1'},
        {'id': 'a', 'que': 'ingresar'},
        {'id': 3, 'que': 'ingresar', 'persona': 'p1'},
        {'id': 'a' * 65, 'que': 'ingresar', 'persona': 'p1'},
      ]) {
        expect(PedidoPuerta.fromJson(roto), isNull, reason: '$roto');
      }
    });

    test('un "hace" raro o negativo cuenta como recién', () {
      final p = PedidoPuerta.fromJson(
        {'id': 'a', 'que': 'ingresar', 'persona': 'p1', 'hace': -5},
      )!;
      expect(p.hace, Duration.zero);
      final q = PedidoPuerta.fromJson(
        {'id': 'a', 'que': 'ingresar', 'persona': 'p1', 'hace': 'mucho'},
      )!;
      expect(q.hace, Duration.zero);
    });
  });

  test('las marcas de la noche dicen quién ingresó a cada uno y cuántos lleva',
      () {
    final m = MarcasDeLaNoche()
      ..ingreso('a', 'Juli')
      ..ingreso('b', 'Juli')
      ..ingreso('c', 'Pato');
    expect(m.quien('a'), 'Juli');
    expect(m.cuantos('Juli'), 2);
    m.deshizo('b');
    expect(m.cuantos('Juli'), 1);
    expect(m.quien('b'), isNull);
    // Lo vuelve a ingresar otro: queda el último.
    m.ingreso('a', 'Pato');
    expect(m.quien('a'), 'Pato');
    expect(m.cuantos('Pato'), 2);
  });
  group('las sillas de la noche', () {
    const juli = 'c1000000-0000-4000-8000-000000000001';
    const gomez = 'c2000000-0000-4000-8000-000000000002';
    // PÉREZ, JULIANA: mesas 12 y 13, 2 sillas del contrato (las dos en la 12):
    // le entran 2 más, en la 13. GÓMEZ, ANA: mesa 14, sin extra.
    final puerta = PuertaDelEvento.masivo(
      alumnos: [
        alumnoDePrueba(juli, 'PÉREZ, JULIANA', mesas: [12, 13], extras: 1, sillas: 2),
        alumnoDePrueba(gomez, 'GÓMEZ, ANA', mesas: [14]),
      ],
      invitados: const [],
    );
    GrupoPuerta grupo(String contrato) =>
        puerta.grupos.firstWhere((g) => g.contratoId == contrato);

    var n = 0;
    SillaPuerta silla(String contrato, int mesa, String vale) {
      n++;
      return SillaPuerta(
        id: 's$n',
        eventoId: eventoMasivo,
        contratoAlumnoId: contrato,
        mesa: mesa,
        vale: vale,
        createdAt: _hora,
        updatedAt: _hora,
      );
    }

    PedidoPuerta sumar(String contrato, {int? mesa, String? vale = '2 0017'}) =>
        PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: grupo(contrato).titular.id,
          silla: DatosSilla(mesa: mesa, vale: vale),
        );

    DecisionSilla decidir(PedidoPuerta p, List<SillaPuerta> base) => decidirSilla(
          pedido: p,
          grupo: puerta.grupos
              .where((g) => g.titular.id == p.personaId)
              .firstOrNull,
          deLaNoche: base,
          nombreDe: (c) =>
              puerta.grupos.where((g) => g.contratoId == c).firstOrNull?.titular.nombre,
        );

    test('suma a la mesa con lugar, con el vale como se anota', () {
      final d = decidir(sumar(juli), const []);
      expect(d.hace, QueHaceLaCentral.sumarSilla);
      expect(d.mesa, 13);
      expect(d.vale, '2-17');
      expect(d.aviso, isNull);
    });

    test('si la mesa pedida está llena, va a otra de la familia y lo dice', () {
      final d = decidir(sumar(juli, mesa: 12), const []);
      expect(d.mesa, 13);
      expect(d.aviso, 'La mesa 12 ya estaba llena: la silla va a la mesa 13.');
    });

    test('una mesa que no es de la familia no se dice "llena"', () {
      // Lo encontró la prueba en el sandbox (6-nov): pedir la 101 decía "ya
      // estaba llena".
      final d = decidir(sumar(gomez, mesa: 101), const []);
      expect(d.mesa, 14);
      expect(d.aviso, 'La mesa 101 no es de la familia: la silla va a la mesa 14.');
    });

    test('lo hecho se dice igual en la PC y en el celular', () {
      expect(
        textoSillaHecha(sumar: true, mesa: 13, nombre: 'GÓMEZ, ANA'),
        'Silla sumada a la mesa 13 de GÓMEZ, ANA.',
      );
      expect(
        textoSillaHecha(
          sumar: true,
          mesa: 13,
          nombre: 'PÉREZ, JULIANA',
          aviso: 'La mesa 12 ya estaba llena: la silla va a la mesa 13.',
        ),
        'La mesa 12 ya estaba llena: la silla va a la mesa 13. '
        'Silla sumada a la mesa 13 de PÉREZ, JULIANA.',
      );
      expect(
        textoSillaHecha(sumar: false, mesa: 14, nombre: 'GÓMEZ, ANA'),
        'Silla quitada de la mesa 14 de GÓMEZ, ANA.',
      );
    });

    test('dos pedidos seguidos con la base del momento: el segundo no suma', () {
      // Le queda un lugar: una ya sumada en la 13.
      final base = [silla(juli, 13, '1-5')];
      final primero = decidir(sumar(juli, vale: '2-17'), base);
      expect(primero.haceAlgo, isTrue);
      // La central la anotó: el segundo pedido mira la base con ella.
      base.add(silla(juli, primero.mesa!, primero.vale!));
      final segundo = decidir(sumar(juli, vale: '2-18'), base);
      expect(segundo.haceAlgo, isFalse);
      expect(segundo.aviso, 'PÉREZ, JULIANA ya no puede agregar: 2 extra por mesa. Una silla suelta, sí.');
    });

    test('sin vale no suma', () {
      for (final vale in [null, '', '   ', 'sin número']) {
        final d = decidir(sumar(gomez, vale: vale), const []);
        expect(d.haceAlgo, isFalse, reason: '$vale');
        expect(d.aviso, 'Hace falta el número del vale de la barra.');
      }
    });

    test('el mismo vale dos veces no suma, aunque se escriba distinto', () {
      final d = decidir(sumar(gomez, vale: 'caja 2 n° 0017'), [silla(juli, 13, '2-17')]);
      expect(d.haceAlgo, isFalse);
      expect(d.aviso, 'El vale 2-17 ya se usó para PÉREZ, JULIANA.');
    });

    test('un vale de una silla quitada se puede volver a usar', () {
      final quitada = silla(juli, 13, '2-17')
          .quitada(por: 'Pato', motivo: 'se equivocó de familia', ahora: _hora);
      expect(decidir(sumar(gomez, vale: '2-17'), [quitada]).haceAlgo, isTrue);
    });

    test('sin mesa (antes del sorteo) no suma', () {
      final antes = PuertaDelEvento.masivo(
        alumnos: [alumnoDePrueba(juli, 'PÉREZ, JULIANA')],
        invitados: const [],
      );
      final g = antes.grupos.single;
      final d = decidirSilla(
        pedido: PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: g.titular.id,
          silla: const DatosSilla(vale: '1-1'),
        ),
        grupo: g,
        deLaNoche: const [],
      );
      expect(d.aviso, 'Esa familia no tiene mesa todavía.');
    });

    test('quitar pide el motivo', () {
      final s = silla(gomez, 14, '1-1');
      PedidoPuerta quitar(String? motivo) => PedidoPuerta(
            id: 'q',
            que: QuePide.quitarSilla,
            personaId: grupo(gomez).titular.id,
            silla: DatosSilla(sillaId: s.id, motivo: motivo),
          );
      expect(decidir(quitar(null), [s]).aviso, 'Decí por qué se quita.');
      expect(decidir(quitar('  '), [s]).haceAlgo, isFalse);
      final bien = decidir(quitar('devolvieron el vale'), [s]);
      expect(bien.hace, QueHaceLaCentral.quitarSilla);
      expect(bien.mesa, 14);
    });

    test('quitar lo que ya se quitó no hace nada', () {
      final s = silla(gomez, 14, '1-1').quitada(por: 'Pato', motivo: 'x', ahora: _hora);
      final d = decidir(
        PedidoPuerta(
          id: 'q',
          que: QuePide.quitarSilla,
          personaId: grupo(gomez).titular.id,
          silla: DatosSilla(sillaId: s.id, motivo: 'y'),
        ),
        [s],
      );
      expect(d.aviso, 'Esa silla ya se quitó.');
    });

    test('quitar la silla de otra familia no hace nada', () {
      final s = silla(juli, 13, '1-1');
      final d = decidir(
        PedidoPuerta(
          id: 'q',
          que: QuePide.quitarSilla,
          personaId: grupo(gomez).titular.id,
          silla: DatosSilla(sillaId: s.id, motivo: 'y'),
        ),
        [s],
      );
      expect(d.haceAlgo, isFalse);
    });

    test('a lo cargado a mano no se le suman sillas', () {
      final p = PuertaDelEvento.masivo(
        alumnos: const [],
        invitados: [_fila('a-mano')],
      );
      final g = p.grupos.single;
      final d = decidirSilla(
        pedido: PedidoPuerta(
          id: 'x',
          que: QuePide.sumarSilla,
          personaId: g.titular.id,
          silla: const DatosSilla(vale: '1-1'),
        ),
        grupo: g,
        deLaNoche: const [],
      );
      expect(d.haceAlgo, isFalse);
    });
  });

  group('el pedido viaja por la red', () {
    test('una silla, ida y vuelta', () {
      const p = PedidoPuerta(
        id: 'a',
        que: QuePide.sumarSilla,
        personaId: 'p1',
        silla: DatosSilla(mesa: 12, vale: '2 0017', nota: 'la abuela'),
      );
      final q = PedidoPuerta.fromJson(p.toJson())!;
      expect(q.que, QuePide.sumarSilla);
      expect(q.silla!.mesa, 12);
      expect(q.silla!.vale, '2 0017');
      expect(q.silla!.nota, 'la abuela');
    });

    test('los segundos del tótem, sin persona', () {
      final p = PedidoPuerta(
        id: 'a',
        que: QuePide.tiemposTotem,
        personaId: '',
        tiempos: TiemposAMano(nombre: 5, camino: 10),
      );
      final q = PedidoPuerta.fromJson(p.toJson())!;
      expect(q.tiempos, TiemposAMano(nombre: 5, camino: 10));
    });

    test('una silla sin sus datos, o los segundos sin segundos, no se entienden', () {
      expect(
        PedidoPuerta.fromJson({'id': 'a', 'que': 'sumarSilla', 'persona': 'p1'}),
        isNull,
      );
      expect(
        PedidoPuerta.fromJson({'id': 'a', 'que': 'tiemposTotem', 'persona': ''}),
        isNull,
      );
      expect(
        PedidoPuerta.fromJson({'id': 'a', 'que': 'ingresar', 'persona': ''}),
        isNull,
        reason: 'un ingreso sin persona sigue sin entenderse',
      );
    });

    test('un texto largo se corta', () {
      final d = DatosSilla.fromJson({'nota': 'x' * 500})!;
      expect(d.nota!.length, 120);
    });
  });

  test('el vale se anota con sus números, sin ceros adelante', () {
    expect(valeNormalizado('2 0017'), '2-17');
    expect(valeNormalizado('Caja 2 · N° 0017-3'), '2-17-3');
    expect(valeNormalizado('0012'), '12');
    expect(valeNormalizado('2.0017'), '2-17');
    expect(valeNormalizado('   '), isNull);
    expect(valeNormalizado(null), isNull);
  });
}
