import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../barra/central/buscar_central.dart';
import '../recepcion/central/pedidos_de_la_puerta.dart';
import '../recepcion/providers/recepcion_provider.dart' show eventosActivosProvider;
import '../recepcion/repositories/invitados_repository.dart';
import '../recepcion/services/puerta_del_evento.dart' show etiquetaEventoRecepcion;
import '../totem/providers/tiempos_a_mano_provider.dart';
import '../totem/services/tiempos_a_mano.dart';
import 'cliente_de_la_tele.dart';
import 'giro_de_la_tele.dart';
import 'modo_tele.dart';
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
  /// por el wifi. **Si ya está enganchada, cambiar de escuela no la
  /// desconecta** (25-nov-2026): se le cuenta a la Tele 1, que la atiende.
  void conectar(String eventoId, {String? direccionAMano, int numero = 2}) {
    final actual = _cliente;
    if (actual != null && actual.direccionAMano == direccionAMano) {
      if (_eventoId != eventoId) {
        _eventoId = eventoId;
        actual.cambiarEscuela(eventoId);
      }
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
      // La Tele 1 manda las filas de las escuelas que atiende: cada una a la
      // suya.
      alRecibirFilas: (filas) async {
        final porEscuela = <String, List<Map<String, dynamic>>>{};
        for (final f in filas) {
          final e = f['evento_id'];
          (porEscuela[e is String && e.length == 36 ? e : _eventoId ?? eventoId] ??= []).add(f);
        }
        for (final e in porEscuela.entries) {
          await ref.read(invitadosRepositoryProvider).guardarDeOtraTele(e.key, e.value);
        }
      },
      alRecibirTiempos: (t) => unawaited(
        ref.read(tiemposAManoProvider(_eventoId ?? eventoId).notifier).ponerDeOtraTele(t),
      ),
      tiemposAlConectar: () {
        final id = _eventoId ?? eventoId;
        final t = ref.read(tiemposAManoProvider(id));
        if (t != null) return t;
        try {
          return TiemposAMano.de(
            ref.read(totemConfigDeLaNocheProvider(id)),
          );
        } catch (_) {
          return null;
        }
      },
      // La Tele 1 le pide otra escuela (un celular, o CAMBIAR): la tele la
      // muestra.
      alPedirEscuela: (id, por) {
        _eventoId = id;
        unawaited(ref.read(fiestaDeLaTeleProvider.notifier).elegir(id));
        // El cartel: "Caro pasó la Tele 2 a ESCUELA B".
        final e = ref.read(eventosActivosProvider).value?.where((x) => x.id == id).firstOrNull;
        final titulo = e == null ? 'otra escuela' : etiquetaEventoRecepcion(e);
        ref.read(avisoEnLaTeleProvider.notifier).decir(
              por == null ? 'La Tele 2 pasó a $titulo' : '$por pasó la Tele 2 a $titulo',
            );
      },
      alGirar: (como) {
        final nuevo = Giro.segun(como, ref.read(giroDeLaTeleProvider));
        if (nuevo != null) unawaited(ref.read(giroDeLaTeleProvider.notifier).poner(nuevo));
      },
    );
    _cliente = cliente;
    state = cliente;
    cliente.arrancar();
  }

  /// Pasa a principal (la Tele 1 se apagó): lo copiado esta noche se encola
  /// para subir, escuela por escuela, y la conexión se suelta. Devuelve los ids
  /// que se encolaron. [escuelaDeLaTele1] queda con la que mostraba la Tele 1:
  /// la nueva principal la atiende también.
  Future<Set<String>> soltarParaSerPrincipal() async {
    final eventoId = _eventoId;
    final cliente = _cliente;
    final copiadas = {...?cliente?.copiadas};
    final porEscuela = {
      for (final e in (cliente?.copiadasDe ?? const <String, Set<String>>{}).entries)
        e.key: {...e.value},
    };
    _escuelaDeLaTele1 = cliente?.escuelaDeLaTele1;
    soltar();
    if (porEscuela.isEmpty && eventoId != null && copiadas.isNotEmpty) {
      porEscuela[eventoId] = copiadas;
    }
    for (final e in porEscuela.entries) {
      await ref.read(invitadosRepositoryProvider).subirLoDeOtraTele(e.key, e.value);
    }
    return copiadas;
  }

  String? _escuelaDeLaTele1;

  /// La escuela que mostraba la Tele 1 cuando esta pasó a principal.
  String? get escuelaDeLaTele1 => _escuelaDeLaTele1;

  void soltar() {
    _cliente?.dispose();
    _cliente = null;
    state = null;
  }
}

final teleSegundaProvider =
    NotifierProvider<TeleSegunda, ClienteDeLaTele?>(TeleSegunda.new);
