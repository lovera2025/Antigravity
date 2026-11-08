import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/instalacion_id.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../recepcion/central/direcciones_red.dart';
import '../providers/barra_del_jefe_provider.dart';
import 'barra_con_la_red.dart';
import 'buscar_central.dart';
import 'central_barra.dart';
import 'cliente_de_la_central.dart';
import 'filas_de_la_red.dart';

/// Si este equipo usa la red del salón (la central de la barra). En la web no; las
/// pruebas de pantalla lo apagan (`BarraEnPrueba`), así no abren conexiones de verdad.
final redDeLaBarraHabilitadaProvider = Provider<bool>((ref) => !kIsWeb);

/// Lo que guarda la central y el cliente: la barra de este equipo. Los tests la reemplazan.
final barraDeLaRedProvider = Provider<BarraDeLaRed>((ref) => ref.watch(barraDeEsteEquipoProvider));

/// Por dónde escucha la central: todas las conexiones de la PC. Las pruebas la ponen solo
/// en esta PC, así Windows no pregunta por el cortafuegos.
final escuchaCentralBarraProvider = Provider<InternetAddress>((ref) => InternetAddress.anyIPv4);

/// En qué puerto prueba primero la central. Las pruebas ponen 0: el que esté libre.
final puertoCentralBarraProvider = Provider<int>((ref) => kPuertoCentralBarra);

/// Por qué puerto se pregunta dónde está la central. Las pruebas ponen otro.
final puertoBusquedaBarraProvider = Provider<int>((ref) => kPuertoBusquedaBarra);

/// A dónde pregunta la caja por la red. Las pruebas: solo a esta PC.
final destinosBusquedaBarraProvider =
    Provider<Future<List<InternetAddress>> Function()>((ref) => destinosDeLaRed);

/// Las direcciones de esta PC que sirven para las tablets.
final direccionesCentralBarraProvider =
    Provider<Future<List<String>> Function()>((ref) => direccionesDeEstaPc);

/// El id de este equipo, para que la central reconozca a la tablet cuando vuelve.
final equipoDeLaBarraProvider = Provider<Future<String> Function()>((ref) => InstalacionId.inicializar);

/// Lo que se guarda en el equipo: la fiesta de la central que estaba prendida, y la
/// dirección escrita a mano. Los tests lo reemplazan.
final guardadoDeLaCentralProvider = Provider<GuardadoDeLaCentral>((ref) => const GuardadoDeLaCentral());

class GuardadoDeLaCentral {
  const GuardadoDeLaCentral();

  static const _prendida = 'barra_central_prendida_v1';
  static const _aMano = 'barra_central_a_mano_v1';

  /// Cuánto dura "la central estaba prendida": una noche.
  static const dura = Duration(hours: 18);

  Future<String?> _leer(String clave) async {
    try {
      return (await SharedPreferences.getInstance()).getString(clave);
    } catch (_) {
      return null;
    }
  }

  Future<void> _guardar(String clave, String? valor) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (valor == null) {
        await p.remove(clave);
      } else {
        await p.setString(clave, valor);
      }
    } catch (_) {}
  }

  /// La fiesta de la central prendida esta noche en esta PC, o null.
  Future<String?> prendida({DateTime? ahora}) async {
    final crudo = await _leer(_prendida);
    final partes = crudo?.split('|');
    if (partes == null || partes.length != 2) return null;
    final cuando = DateTime.tryParse(partes[1]);
    if (cuando == null || (ahora ?? DateTime.now()).difference(cuando) > dura) return null;
    return partes[0];
  }

  Future<void> anotarPrendida(String? eventoId, {DateTime? ahora}) => _guardar(
        _prendida,
        eventoId == null ? null : '$eventoId|${(ahora ?? DateTime.now()).toUtc().toIso8601String()}',
      );

  Future<DondeEstaLaCentral?> aMano() async {
    final crudo = await _leer(_aMano);
    return crudo == null ? null : DondeEstaLaCentral.deTexto(crudo);
  }

  Future<void> anotarAMano(DondeEstaLaCentral? donde) => _guardar(_aMano, donde?.texto);
}

/// Cómo está la central de la barra en esta notebook.
@immutable
class EstadoCentralBarra {
  final String? eventoId;
  final int? puerto;

  /// De la más probable a la menos ([direccionesParaCelulares]).
  final List<String> direcciones;
  final List<CajaConectada> cajas;

  /// Si contesta a las tablets que la buscan solas. Sin eso, la dirección se escribe a mano.
  final bool contestaBusqueda;

  /// Lo que salió mal al prenderla, en palabras.
  final String? error;

  const EstadoCentralBarra({
    this.eventoId,
    this.puerto,
    this.direcciones = const [],
    this.cajas = const [],
    this.contestaBusqueda = false,
    this.error,
  });

  bool get prendida => puerto != null;

  /// "192.168.0.10:8797": lo que se escribe a mano en la tablet. Null si la notebook no
  /// está conectada a ningún router.
  String? get direccion => !prendida || direcciones.isEmpty ? null : '${direcciones.first}:$puerto';

  int get conectadas => cajas.where((c) => c.conectada).length;

  EstadoCentralBarra con({List<String>? direcciones, List<CajaConectada>? cajas}) => EstadoCentralBarra(
        eventoId: eventoId,
        puerto: puerto,
        direcciones: direcciones ?? this.direcciones,
        cajas: cajas ?? this.cajas,
        contestaBusqueda: contestaBusqueda,
        error: error,
      );
}

/// La central de la barra de esta notebook ([CentralBarra]). Se prende desde BARRA →
/// CAJAS (CENTRAL) y queda prendida mientras el programa esté abierto; al volver a abrir
/// BARRA esa noche se vuelve a prender sola ([reanudar]). Atiende una fiesta por vez.
class CentralDeLaBarra extends Notifier<EstadoCentralBarra> {
  CentralBarra? _central;
  RespondeBusqueda? _busqueda;
  StreamSubscription<List<CajaConectada>>? _cajas;

  /// Se lee al armar: al cerrarse, Riverpod no deja leer otros providers.
  late AvisoALaRed _aviso;

  @override
  EstadoCentralBarra build() {
    _aviso = ref.read(avisoALaRedProvider);
    ref.onDispose(() => unawaited(_soltar()));
    return const EstadoCentralBarra();
  }

  Future<void> prender(String eventoId) async {
    if (!ref.read(redDeLaBarraHabilitadaProvider)) return;
    if (_central != null && state.eventoId == eventoId) {
      final direcciones = await ref.read(direccionesCentralBarraProvider)();
      state = state.con(direcciones: direcciones);
      return;
    }
    await _soltar();
    final central = CentralBarra(
      eventoId: eventoId,
      barra: ref.read(barraDeLaRedProvider),
      alGuardar: () => ref.read(operationalSyncRevisionProvider.notifier).bump(),
    );
    final int puerto;
    try {
      puerto = await central.arrancar(
        desde: ref.read(puertoCentralBarraProvider),
        en: ref.read(escuchaCentralBarraProvider),
      );
    } catch (_) {
      state = EstadoCentralBarra(
        eventoId: eventoId,
        error: 'No se pudo abrir la central en esta PC. Cerrá el programa, volvé a abrirlo y probá de nuevo.',
      );
      return;
    }
    _central = central;
    final busqueda = RespondeBusqueda(eventoId: eventoId, puertoCentral: puerto);
    final contesta = await busqueda.escuchar(
      puerto: ref.read(puertoBusquedaBarraProvider),
      en: ref.read(escuchaCentralBarraProvider),
    );
    _busqueda = busqueda;
    // Lo que se hace en esta notebook (el jefe anula desde CAJAS) va a todas las cajas.
    _aviso.salida = central.difundirDeEstaPc;
    _cajas = central.cambiosDeCajas.listen((cajas) {
      if (identical(_central, central)) state = state.con(cajas: cajas);
    });
    unawaited(ref.read(guardadoDeLaCentralProvider).anotarPrendida(eventoId));
    final direcciones = await ref.read(direccionesCentralBarraProvider)();
    if (!identical(_central, central)) return;
    state = EstadoCentralBarra(
      eventoId: eventoId,
      puerto: puerto,
      direcciones: direcciones,
      cajas: central.cajas,
      contestaBusqueda: contesta,
    );
  }

  /// Si la central de [eventoId] estaba prendida esta noche (la notebook se reinició, se
  /// cerró el programa), la vuelve a prender: las tablets se reconectan solas.
  Future<void> reanudar(String eventoId) async {
    if (_central != null) return;
    final prendida = await ref.read(guardadoDeLaCentralProvider).prendida();
    if (prendida != eventoId || _central != null) return;
    await prender(eventoId);
  }

  Future<void> apagar() async {
    final guardado = ref.read(guardadoDeLaCentralProvider);
    await _soltar();
    unawaited(guardado.anotarPrendida(null));
    state = const EstadoCentralBarra();
  }

  Future<void> _soltar() async {
    final central = _central;
    _central = null;
    if (central != null && _aviso.salida == central.difundirDeEstaPc) _aviso.salida = null;
    _busqueda?.cerrar();
    _busqueda = null;
    await _cajas?.cancel();
    _cajas = null;
    await central?.cerrar();
  }
}

final centralDeLaBarraProvider =
    NotifierProvider<CentralDeLaBarra, EstadoCentralBarra>(CentralDeLaBarra.new);

/// La caja de esta tablet con la central ([ClienteDeLaCentral]). La arranca VENDER; queda
/// andando mientras la app esté abierta. Null: todavía no arrancó (o no hay red del salón).
class ClienteDeLaBarra extends Notifier<ClienteDeLaCentral?> {
  ClienteDeLaCentral? _cliente;

  @override
  ClienteDeLaCentral? build() {
    ref.onDispose(() {
      _cliente?.dispose();
      _cliente = null;
    });
    return null;
  }

  /// La caja [nombreCaja] ("Caja 2 · Sofía") de [eventoId] empieza a buscar la central. Si
  /// ya estaba con esa fiesta, nada. En la notebook que tiene la central prendida para esa
  /// fiesta, tampoco: lo que se vende ahí ya va a la central.
  Future<void> arrancar({required String eventoId, required String nombreCaja}) async {
    if (!ref.read(redDeLaBarraHabilitadaProvider)) return;
    final central = ref.read(centralDeLaBarraProvider);
    if (central.prendida && central.eventoId == eventoId) return;
    final ya = _cliente;
    if (ya != null && ya.eventoId == eventoId && ya.nombreCaja == nombreCaja) return;
    _soltar();
    final equipo = await ref.read(equipoDeLaBarraProvider)();
    final aMano = await ref.read(guardadoDeLaCentralProvider).aMano();
    if (_cliente != null) return;
    final cliente = ClienteDeLaCentral(
      eventoId: eventoId,
      equipo: equipo,
      nombreCaja: nombreCaja,
      barra: ref.read(barraDeLaRedProvider),
      alGuardar: () => ref.read(operationalSyncRevisionProvider.notifier).bump(),
      buscador: BuscaCentral(
        eventoId: eventoId,
        puerto: ref.read(puertoBusquedaBarraProvider),
        destinos: ref.read(destinosBusquedaBarraProvider),
      ),
      aMano: aMano,
    );
    ref.read(avisoALaRedProvider).salida = cliente.mandar;
    _cliente = cliente;
    state = cliente;
    cliente.arrancar();
  }

  /// La dirección que muestra la notebook, escrita a mano en la tablet. Null: se la busca sola.
  Future<void> ponerAMano(DondeEstaLaCentral? donde) async {
    await ref.read(guardadoDeLaCentralProvider).anotarAMano(donde);
    _cliente?.ponerAMano(donde);
  }

  void _soltar() {
    final c = _cliente;
    if (c == null) return;
    final aviso = ref.read(avisoALaRedProvider);
    if (aviso.salida == c.mandar) aviso.salida = null;
    c.dispose();
    _cliente = null;
    state = null;
  }
}

final clienteDeLaBarraProvider =
    NotifierProvider<ClienteDeLaBarra, ClienteDeLaCentral?>(ClienteDeLaBarra.new);
