import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
