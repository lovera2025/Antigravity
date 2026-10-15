import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/evento.dart';
import '../../../models/invitado.dart';
import '../providers/recepcion_provider.dart';
import '../repositories/invitados_repository.dart';
import '../services/puerta_del_evento.dart';
import 'central_puerta.dart';
import 'codigo_central.dart';
import 'direcciones_red.dart';

/// La central marca con la base de esta PC, por el mismo repositorio que
/// Recepción.
class PuertaDeEstaPcConBase implements PuertaDeEstaPc {
  PuertaDeEstaPcConBase(this._invitados);
  final InvitadosRepository _invitados;

  @override
  Future<Invitado?> fila(String id) => _invitados.getLocal(id);

  /// Por `ingresarDesdeLaPuerta`, que crea la fila si falta (un masivo antes del
  /// sorteo) y si no la marca como siempre.
  @override
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  }) =>
      _invitados.ingresarDesdeLaPuerta(
        eventoId: eventoId,
        id: persona.id,
        nombre: persona.nombre,
        mesa: persona.mesa,
        saludar: saludar,
      );

  @override
  Future<void> deshacer(String id) => _invitados.deshacerIngreso(id);
}

/// Por dónde escucha la central: todas las conexiones de la PC. Las pruebas
/// la ponen solo en esta PC, así Windows no pregunta por el cortafuegos.
final escuchaCentralProvider =
    Provider<InternetAddress>((ref) => InternetAddress.anyIPv4);

/// En qué puerto prueba primero. Las pruebas ponen 0: el que esté libre.
final puertoCentralProvider = Provider<int>((ref) => kPuertoCentral);

/// Las direcciones de esta PC que sirven para los celulares.
final direccionesDeEstaPcProvider =
    Provider<Future<List<String>> Function()>((ref) => direccionesDeEstaPc);

/// El código del evento, guardado en esta PC (`CodigoCentral`).
final codigoCentralProvider =
    Provider<Future<String> Function(String eventoId)>(
  (ref) => CodigoCentral.delEvento,
);

/// El código del evento si la central se usó esta noche, sin sacar uno nuevo.
final codigoVigenteCentralProvider =
    Provider<Future<String?> Function(String eventoId)>(
  (ref) => CodigoCentral.vigente,
);

final cambiarCodigoCentralProvider =
    Provider<Future<String> Function(String eventoId, String anterior)>(
  (ref) => (eventoId, anterior) =>
      CodigoCentral.cambiar(eventoId, anterior: anterior),
);

/// La carpeta con la página del celular: `puesto` al lado del programa. La
/// deja el instalador.
final paginaDelCelularProvider = Provider<Directory?>((ref) {
  try {
    final carpeta = Directory(
      '${File(Platform.resolvedExecutable).parent.path}'
      '${Platform.pathSeparator}puesto',
    );
    return carpeta.existsSync() ? carpeta : null;
  } catch (_) {
    return null;
  }
});

/// Cómo está la central de la puerta en esta PC.
class EstadoCentral {
  final String? eventoId;
  final String? codigo;
  final int? puerto;

  /// De la más probable a la menos ([direccionesParaCelulares]).
  final List<String> direcciones;
  final List<PuestoConectado> puestos;

  /// Lo que salió mal al prenderla, en palabras.
  final String? error;

  const EstadoCentral({
    this.eventoId,
    this.codigo,
    this.puerto,
    this.direcciones = const [],
    this.puestos = const [],
    this.error,
  });

  bool get prendida => puerto != null;

  /// "192.168.0.10:8787", lo que se escribe en el navegador del celular. Null
  /// si la PC no está conectada a ningún router.
  String? get direccion => !prendida || direcciones.isEmpty
      ? null
      : '${direcciones.first}:$puerto';

  /// Lo que va en el QR: la dirección con el código adentro.
  String? get enlace {
    final d = direccion;
    return d == null ? null : 'http://$d/?c=$codigo';
  }

  int get conectados => puestos.where((p) => p.conectado).length;

  EstadoCentral _con({
    String? codigo,
    List<String>? direcciones,
    List<PuestoConectado>? puestos,
  }) =>
      EstadoCentral(
        eventoId: eventoId,
        codigo: codigo ?? this.codigo,
        puerto: puerto,
        direcciones: direcciones ?? this.direcciones,
        puestos: puestos ?? this.puestos,
        error: error,
      );
}

/// La central de la puerta de esta PC (`CentralPuerta`).
///
/// Se prende con "Sumar un celular" en Recepción ([prender]) y queda prendida
/// mientras el programa esté abierto: salir de Recepción no deja a los
/// celulares sin lista. Atiende un evento por vez; prenderla para otro apaga la
/// del anterior.
class CentralDeLaPuerta extends Notifier<EstadoCentral> {
  CentralPuerta? _central;
  ProviderSubscription<AsyncValue<PuertaDelEvento>>? _lista;
  ProviderSubscription<AsyncValue<List<Evento>>>? _evento;
  StreamSubscription<List<PuestoConectado>>? _puestos;

  @override
  EstadoCentral build() {
    ref.onDispose(() => unawaited(_soltar()));
    return const EstadoCentral();
  }

  /// La central de [eventoId]. Si ya estaba prendida para ese evento, solo
  /// vuelve a mirar las direcciones (la PC pudo haberse conectado al router
  /// recién).
  Future<void> prender(String eventoId) async {
    if (_central != null && state.eventoId == eventoId) {
      final direcciones = await ref.read(direccionesDeEstaPcProvider)();
      state = state._con(direcciones: direcciones);
      return;
    }
    await _soltar();

    final codigo = await ref.read(codigoCentralProvider)(eventoId);
    final central = CentralPuerta(
      eventoId: eventoId,
      codigo: codigo,
      pc: PuertaDeEstaPcConBase(ref.read(invitadosRepositoryProvider)),
      paginaDelCelular: ref.read(paginaDelCelularProvider),
    );
    try {
      await central.arrancar(
        desde: ref.read(puertoCentralProvider),
        en: ref.read(escuchaCentralProvider),
      );
    } catch (_) {
      state = EstadoCentral(
        eventoId: eventoId,
        error: 'No se pudo abrir la central en esta PC. Cerrá el programa, '
            'volvé a abrirlo y probá de nuevo.',
      );
      return;
    }
    _central = central;
    // Desde el contenedor y no con `ref.listen`: Riverpod pausa lo que escucha
    // un provider cuando nadie lo mira, y la central tiene que seguir mandando
    // la lista aunque Recepción esté cerrada.
    _evento = ref.container.listen<AsyncValue<List<Evento>>>(
      eventosActivosProvider,
      (_, eventos) {
        final e = eventos.value?.where((e) => e.id == eventoId).firstOrNull;
        central.ponerTitulo(e == null ? null : etiquetaEventoRecepcion(e));
      },
      fireImmediately: true,
    );
    _lista = ref.container.listen<AsyncValue<PuertaDelEvento>>(
      puertaDelEventoProvider(eventoId),
      (_, lista) {
        final puerta = lista.value;
        if (puerta != null) central.ponerPuerta(puerta);
      },
      fireImmediately: true,
    );
    _puestos = central.cambiosDePuestos.listen((puestos) {
      if (identical(_central, central)) state = state._con(puestos: puestos);
    });
    final direcciones = await ref.read(direccionesDeEstaPcProvider)();
    if (!identical(_central, central)) return;
    state = EstadoCentral(
      eventoId: eventoId,
      codigo: codigo,
      puerto: central.puerto,
      direcciones: direcciones,
      puestos: central.puestos,
    );
  }

  /// Si la central de [eventoId] se usó esta noche y no está prendida (la
  /// notebook se reinició, o se cerró el programa), la vuelve a prender con el
  /// mismo código: los celulares se reconectan solos, sin volver a escanear.
  /// La llama Recepción al abrir el evento.
  Future<void> reanudar(String eventoId) async {
    if (_central != null) return;
    final codigo = await ref.read(codigoVigenteCentralProvider)(eventoId);
    if (codigo == null || _central != null) return;
    await prender(eventoId);
  }

  /// Otro código: los celulares conectados tienen que volver a escanear.
  Future<void> cambiarCodigo() async {
    final central = _central;
    final eventoId = state.eventoId;
    if (central == null || eventoId == null) return;
    final nuevo =
        await ref.read(cambiarCodigoCentralProvider)(eventoId, central.codigo);
    await central.cambiarCodigo(nuevo);
    if (identical(_central, central)) state = state._con(codigo: nuevo);
  }

  Future<void> apagar() async {
    await _soltar();
    state = const EstadoCentral();
  }

  /// Quién marcó a [personaId] esta noche desde un celular.
  String? quienMarco(String personaId) => _central?.marcas.quien(personaId);

  Future<void> _soltar() async {
    final central = _central;
    _central = null;
    _lista?.close();
    _lista = null;
    _evento?.close();
    _evento = null;
    await _puestos?.cancel();
    _puestos = null;
    await central?.cerrar();
  }
}

final centralDeLaPuertaProvider =
    NotifierProvider<CentralDeLaPuerta, EstadoCentral>(CentralDeLaPuerta.new);
