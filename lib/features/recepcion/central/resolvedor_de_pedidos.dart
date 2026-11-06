import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/invitado.dart';
import '../../../models/silla_puerta.dart';
import '../../totem/services/tiempos_a_mano.dart';
import '../services/puerta_del_evento.dart';
import 'pedidos_de_la_puerta.dart';

/// Lo que la central necesita de esta PC: leer una fila y marcar, igual que
/// Recepción, y anotar o quitar una silla de la noche. En la app es la base
/// (`PuertaDeEstaPcConBase`); en las pruebas, una en memoria.
abstract class PuertaDeEstaPc {
  /// La fila de la lista de la puerta, como está ahora en la base.
  Future<Invitado?> fila(String id);

  /// Ingresa a [persona]; si su fila no existe (un masivo antes del sorteo), la
  /// crea, como "Ingresar" en Recepción.
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  });

  Future<void> deshacer(String id);

  /// Las sillas de la noche del evento, vigentes y quitadas, como están ahora
  /// en la base.
  Future<List<SillaPuerta>> sillasDelEvento(String eventoId);

  Future<void> sumarSilla({
    required String eventoId,
    required String contratoId,
    required int mesa,
    required String vale,
    required String anotadoPor,
    String? nota,
  });

  Future<void> quitarSilla(
    String sillaId, {
    required String por,
    required String motivo,
  });

  /// Los segundos de la llegada de esa noche: la tele cambia al instante.
  Future<void> ponerTiempos(String eventoId, TiemposAMano tiempos);
}

/// **Un solo candado para la PC y los celulares** (6.4.0): todo lo que se pide
/// en la puerta de un evento pasa por acá, de a uno, y se decide con la base de
/// ese momento. Así, si dos celulares —o un celular y la PC— suman una silla a
/// la misma familia con un solo lugar, entra una y la otra recibe "ya no puede
/// agregar".
///
/// Lo usa la central (`CentralPuerta`) con lo que llega por el wifi y la PC
/// (`CentralDeLaPuerta.resolverDeEstaPc`) aunque la central esté apagada.
class ResolvedorDePedidos {
  ResolvedorDePedidos({required this.eventoId, required PuertaDeEstaPc pc})
      : _pc = pc;

  final String eventoId;
  final PuertaDeEstaPc _pc;

  /// Quién marcó a cada uno esta noche, desde qué puesto.
  final marcas = MarcasDeLaNoche();

  /// La lista que ve Recepción, la última que se le pasó.
  PuertaDelEvento? puerta;

  final _respuestas = <String, Map<String, Object?>>{};
  var _fila = Future<void>.value();

  /// Atiende [pedido] cuando terminan los anteriores. [puesto] es quién lo pide
  /// (el nombre del celular, o quien opera la PC). [conLista] es la lista con
  /// que se pide, si no se le pasó una ([puerta]).
  ///
  /// Devuelve la respuesta que va al celular: `ok` false si la base falló (se
  /// puede volver a mandar); si no, `hizo` y el `aviso`, si hay algo que decir.
  Future<Map<String, Object?>> resolver(
    PedidoPuerta pedido,
    String puesto, {
    PuertaDelEvento? conLista,
  }) {
    final listo = Completer<Map<String, Object?>>();
    _fila = _fila.then((_) async {
      try {
        listo.complete(await _resolver(pedido, puesto, conLista ?? puerta));
      } catch (e) {
        debugPrint('Puerta, pedido ${pedido.id}: $e');
        listo.complete(_noSePudo(pedido));
      }
    });
    return listo.future;
  }

  static Map<String, Object?> _noSePudo(PedidoPuerta pedido) =>
      {'t': 'respuesta', 'id': pedido.id, 'ok': false};

  Future<Map<String, Object?>> _resolver(
    PedidoPuerta pedido,
    String puesto,
    PuertaDelEvento? lista,
  ) async {
    final previa = _respuestas[pedido.id];
    if (previa != null) return previa;

    final Map<String, Object?> respuesta;
    if (pedido.que.esIngreso) {
      if (lista == null) return _noSePudo(pedido);
      final r = await _ingreso(pedido, puesto, lista);
      if (r == null) return _noSePudo(pedido);
      respuesta = r;
    } else if (pedido.que == QuePide.tiemposTotem) {
      final t = pedido.tiempos;
      if (t == null) return _noSePudo(pedido);
      try {
        await _pc.ponerTiempos(eventoId, t);
      } catch (e) {
        debugPrint('Puerta, segundos del tótem: $e');
        return _noSePudo(pedido);
      }
      respuesta = _respuesta(pedido, QueHaceLaCentral.tiempos);
    } else {
      if (lista == null) return _noSePudo(pedido);
      final r = await _silla(pedido, puesto, lista);
      if (r == null) return _noSePudo(pedido);
      respuesta = r;
    }
    _respuestas[pedido.id] = respuesta;
    return respuesta;
  }

  Map<String, Object?> _respuesta(
    PedidoPuerta pedido,
    QueHaceLaCentral hizo, {
    String? aviso,
    int? mesa,
  }) =>
      {
        't': 'respuesta',
        'id': pedido.id,
        'ok': true,
        'hizo': hizo.name,
        'aviso': ?aviso,
        'mesa': ?mesa,
      };

  /// Null si la base falló.
  Future<Map<String, Object?>?> _ingreso(
    PedidoPuerta pedido,
    String puesto,
    PuertaDelEvento lista,
  ) async {
    final persona =
        lista.personas.where((p) => p.id == pedido.personaId).firstOrNull;
    final DecisionPedido decision;
    // Quién lo había marcado antes, para dejarlo como estaba si la base falla.
    final antes = marcas.quien(pedido.personaId);
    try {
      final fila = persona == null ? null : await _pc.fila(persona.id);
      decision = decidirPedido(
        pedido: pedido,
        persona: persona,
        fila: fila,
        quien: antes,
      );
      // Quién lo marcó se anota antes de marcar: la base avisa el cambio y la
      // lista nueva sale enseguida, y tiene que salir con el nombre.
      switch (decision.hace) {
        case QueHaceLaCentral.ingresar:
          marcas.ingreso(persona!.id, puesto);
          await _pc.ingresar(eventoId, persona, saludar: decision.saludar);
        case QueHaceLaCentral.deshacer:
          marcas.deshizo(persona!.id);
          await _pc.deshacer(persona.id);
        case QueHaceLaCentral.sumarSilla:
        case QueHaceLaCentral.quitarSilla:
        case QueHaceLaCentral.tiempos:
        case QueHaceLaCentral.nada:
          break;
      }
    } catch (e) {
      if (antes == null) {
        marcas.deshizo(pedido.personaId);
      } else {
        marcas.ingreso(pedido.personaId, antes);
      }
      // No se guarda: el celular lo vuelve a mandar.
      debugPrint('Puerta, pedido ${pedido.id}: $e');
      return null;
    }
    return _respuesta(pedido, decision.hace, aviso: decision.aviso);
  }

  /// Null si la base falló.
  Future<Map<String, Object?>?> _silla(
    PedidoPuerta pedido,
    String puesto,
    PuertaDelEvento lista,
  ) async {
    final grupo = lista.grupos
        .where((g) => g.titular.id == pedido.personaId)
        .firstOrNull;
    try {
      final deLaNoche = await _pc.sillasDelEvento(eventoId);
      final decision = decidirSilla(
        pedido: pedido,
        grupo: grupo,
        deLaNoche: deLaNoche,
        nombreDe: (contrato) => lista.grupos
            .where((g) => g.contratoId == contrato)
            .firstOrNull
            ?.titular
            .nombre,
      );
      final datos = pedido.silla;
      switch (decision.hace) {
        case QueHaceLaCentral.sumarSilla:
          await _pc.sumarSilla(
            eventoId: eventoId,
            contratoId: grupo!.contratoId!,
            mesa: decision.mesa!,
            vale: decision.vale!,
            anotadoPor: puesto,
            nota: datos?.nota,
          );
        case QueHaceLaCentral.quitarSilla:
          await _pc.quitarSilla(
            datos!.sillaId!,
            por: puesto,
            motivo: datos.motivo!.trim(),
          );
        case QueHaceLaCentral.ingresar:
        case QueHaceLaCentral.deshacer:
        case QueHaceLaCentral.tiempos:
        case QueHaceLaCentral.nada:
          break;
      }
      return _respuesta(
        pedido,
        decision.hace,
        aviso: decision.aviso,
        mesa: decision.mesa,
      );
    } catch (e) {
      debugPrint('Puerta, silla ${pedido.id}: $e');
      return null;
    }
  }
}
