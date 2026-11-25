import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../barra/central/buscar_central.dart';
import '../recepcion/central/pedidos_de_la_puerta.dart';
import '../recepcion/repositories/invitados_repository.dart';
import '../totem/providers/tiempos_a_mano_provider.dart';
import '../totem/services/tiempos_a_mano.dart';
import 'cliente_de_la_tele.dart';
import 'red_de_la_tele.dart';

/// Cómo abre la Tele 2 la conexión con la Tele 1. Las pruebas la reemplazan.
final abrirCanalDeLaTeleProvider =
    Provider<WebSocketChannel Function(Uri)>((ref) => WebSocketChannel.connect);

/// A dónde pregunta la Tele 2 por la Tele 1: a toda la red. La ventana de
/// prueba pregunta solo en esta PC.
final destinosDeLaBusquedaProvider =
    Provider<Future<List<InternetAddress>> Function()>((ref) => destinosDeLaRed);

/// **La Tele 2 enganchada a la Tele 1** (la tele es el tótem, 24-nov-2026): su
/// [ClienteDeLaTele], y cómo se saluda a cada ingreso que llegó de la Tele 1.
///
/// Las filas que manda la Tele 1 se copian en la base de esta tele sin encolar
/// (`InvitadosRepository.guardarDeOtraTele`): así el tótem de la Tele 2 es el
/// mismo `TotemLocal`, y si la Tele 1 se apaga, esta tiene la lista.
class TeleSegunda extends Notifier<ClienteDeLaTele?> {
  final _bienvenidas = <String, BienvenidaDeLaNoche>{};
  ClienteDeLaTele? _cliente;
  String? _eventoId;

  @override
  ClienteDeLaTele? build() {
    ref.onDispose(() {
      _cliente?.dispose();
      _cliente = null;
    });
    return null;
  }

  /// Cómo se saluda a [personaId], si su ingreso llegó de la Tele 1.
  BienvenidaDeLaNoche? bienvenida(String personaId) => _bienvenidas[personaId];

  /// Se engancha a la Tele 1 para [eventoId]. Con [direccionAMano] no busca
  /// por el wifi.
  void conectar(String eventoId, {String? direccionAMano, int numero = 2}) {
    final actual = _cliente;
    if (actual != null &&
        _eventoId == eventoId &&
        actual.direccionAMano == direccionAMano) {
      return;
    }
    actual?.dispose();
    _bienvenidas.clear();
    _eventoId = eventoId;
    final destinos = ref.read(destinosDeLaBusquedaProvider);
    final cliente = ClienteDeLaTele(
      eventoId: eventoId,
      numero: numero,
      direccionAMano: direccionAMano,
      abrir: ref.read(abrirCanalDeLaTeleProvider),
      busca: BuscaCentral(
        eventoId: eventoId,
        puerto: kPuertoBusquedaTele,
        destinos: destinos,
      ),
      alRecibirBienvenidas: _bienvenidas.addAll,
      alRecibirFilas: (filas) async {
        await ref
            .read(invitadosRepositoryProvider)
            .guardarDeOtraTele(eventoId, filas);
      },
      alRecibirTiempos: (t) => unawaited(
        ref.read(tiemposAManoProvider(eventoId).notifier).ponerDeOtraTele(t),
      ),
      tiemposAlConectar: () {
        final t = ref.read(tiemposAManoProvider(eventoId));
        if (t != null) return t;
        try {
          return TiemposAMano.de(
            ref.read(totemConfigDeLaNocheProvider(eventoId)),
          );
        } catch (_) {
          return null;
        }
      },
    );
    _cliente = cliente;
    state = cliente;
    cliente.arrancar();
  }

  /// Pasa a principal (la Tele 1 se apagó): lo copiado esta noche se encola
  /// para subir y la conexión se suelta. Devuelve los ids que se encolaron.
  Future<Set<String>> soltarParaSerPrincipal() async {
    final eventoId = _eventoId;
    final copiadas = {...?_cliente?.copiadas};
    soltar();
    if (eventoId != null && copiadas.isNotEmpty) {
      await ref
          .read(invitadosRepositoryProvider)
          .subirLoDeOtraTele(eventoId, copiadas);
    }
    return copiadas;
  }

  void soltar() {
    _cliente?.dispose();
    _cliente = null;
    state = null;
  }
}

final teleSegundaProvider =
    NotifierProvider<TeleSegunda, ClienteDeLaTele?>(TeleSegunda.new);
