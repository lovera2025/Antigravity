import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/instalacion_id.dart';
import '../../../core/services/pc_despierta.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../recepcion/central/direcciones_red.dart';
import '../datos/barra_repositorio.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../services/barras_del_salon.dart';
import 'barra_con_la_red.dart';
import 'buscar_central.dart';
import 'central_barra.dart';
import 'cliente_de_la_central.dart';
import 'filas_de_la_red.dart';

/// Si este equipo usa la red del salón (la central de la barra). En la web no; las
/// pruebas de pantalla lo apagan (`BarraEnPrueba`), así no abren conexiones de verdad.
final redDeLaBarraHabilitadaProvider = Provider<bool>((ref) => !kIsWeb);

/// Si en este equipo se muestra PRENDER LA CENTRAL (6.4.0): en la notebook sí, en la
/// web y en una tablet Android no. La central es la notebook del salón; la encargada
/// mira LAS CAJAS desde su tablet, y dos centrales en la misma red se pisarían.
/// En la tablet se pregunta por `Platform`, no por `defaultTargetPlatform`
/// (en `flutter test` ese dice siempre Android).
final centralSePrendeAcaProvider = Provider<bool>((ref) => !kIsWeb && !Platform.isAndroid);

/// Lo que guarda la central y el cliente: la barra de este equipo. Los tests la reemplazan.
final barraDeLaRedProvider = Provider<BarraDeLaRed>((ref) => ref.watch(barraDeEsteEquipoProvider));

/// Por dónde escucha la central: todas las conexiones de la PC. Las pruebas la ponen solo
/// en esta PC, así Windows no pregunta por el cortafuegos.
final escuchaCentralBarraProvider = Provider<InternetAddress>((ref) => InternetAddress.anyIPv4);

/// En qué puerto prueba primero la central. Las pruebas ponen 0: el que esté libre.
final puertoCentralBarraProvider = Provider<int>((ref) => kPuertoCentralBarra);

/// Por qué puerto se pregunta dónde está la central (y en cuál contesta la de esta
/// notebook). Las pruebas ponen otro.
final puertoBusquedaBarraProvider = Provider<int>((ref) => kPuertoBusquedaBarra);

/// A qué puertos pregunta este equipo por las centrales: en la app, el mismo de
/// [puertoBusquedaBarraProvider]. Las ventanas de prueba, con las dos centrales de las dos
/// barras en la misma PC (cada una contesta en su puerto), preguntan a los dos.
final puertosQuePreguntaBarraProvider = Provider<List<int>>((ref) => [ref.watch(puertoBusquedaBarraProvider)]);

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

/// La central que estaba prendida en esta notebook: de qué fiesta, desde cuándo y de qué
/// barra.
@immutable
class CentralGuardada {
  final String eventoId;

  /// Cuándo se prendió con el botón (volver a prenderla sola no lo cambia).
  final DateTime desde;
  final String? barra;

  const CentralGuardada({required this.eventoId, required this.desde, this.barra});
}

class GuardadoDeLaCentral {
  const GuardadoDeLaCentral();

  static const _prendida = 'barra_central_prendida_v1';
  static const _aMano = 'barra_central_a_mano_v1';

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

  /// La última central prendida en esta PC, o null. **No vence sola** (25-nov-2026): si
  /// vuelve a prenderse lo decide [CentralDeLaBarra.reanudar], con la noche y las cajas
  /// abiertas. Hasta la 6.9.3 vencía a las 18 horas, y una fiesta que siguió pasado el
  /// mediodía se quedaba sin central después de un reinicio.
  Future<CentralGuardada?> prendida() async {
    final crudo = await _leer(_prendida);
    final partes = crudo?.split('|');
    if (partes == null || partes.length < 2 || partes[0].isEmpty) return null;
    final cuando = DateTime.tryParse(partes[1]);
    if (cuando == null) return null;
    final barra = partes.length > 2 && partes[2].isNotEmpty ? partes[2] : null;
    return CentralGuardada(eventoId: partes[0], desde: cuando, barra: barra);
  }

  /// [eventoId] null: se apagó a mano.
  Future<void> anotarPrendida(String? eventoId, {String? barra, DateTime? ahora}) => _guardar(
        _prendida,
        eventoId == null
            ? null
            : '$eventoId|${(ahora ?? DateTime.now()).toUtc().toIso8601String()}|${barra ?? ''}',
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

  /// "Barra 1": la barra de esta notebook (25-nov-2026). Null: de toda la fiesta.
  final String? barra;

  /// De la más probable a la menos ([direccionesParaCelulares]).
  final List<String> direcciones;

  /// Las cajas, y también las otras centrales enganchadas (`esCentral`).
  final List<CajaConectada> cajas;

  /// El enganche con la central de la otra barra, si se encontraron.
  final List<EngancheConOtra> otras;

  /// Si contesta a las tablets que la buscan solas. Sin eso, la dirección se escribe a mano.
  final bool contestaBusqueda;

  /// Lo que salió mal al prenderla, en palabras.
  final String? error;

  const EstadoCentralBarra({
    this.eventoId,
    this.puerto,
    this.barra,
    this.direcciones = const [],
    this.cajas = const [],
    this.otras = const [],
    this.contestaBusqueda = false,
    this.error,
  });

  bool get prendida => puerto != null;

  /// "192.168.0.10:8797": lo que se escribe a mano en la tablet. Null si la notebook no
  /// está conectada a ningún router.
  String? get direccion => !prendida || direcciones.isEmpty ? null : '${direcciones.first}:$puerto';

  /// Cuántas cajas conectadas (sin las otras centrales).
  int get conectadas => cajas.where((c) => c.conectada && !c.esCentral).length;

  /// Solo las cajas, sin las otras centrales.
  List<CajaConectada> get soloCajas => [for (final c in cajas) if (!c.esCentral) c];

  /// Si está enganchada ahora con alguna otra central de la fiesta.
  bool get enganchada => otras.any((o) => o.conectada);

  EstadoCentralBarra con({List<String>? direcciones, List<CajaConectada>? cajas, List<EngancheConOtra>? otras}) =>
      EstadoCentralBarra(
        eventoId: eventoId,
        puerto: puerto,
        barra: barra,
        direcciones: direcciones ?? this.direcciones,
        cajas: cajas ?? this.cajas,
        otras: otras ?? this.otras,
        contestaBusqueda: contestaBusqueda,
        error: error,
      );
}

/// La central de la barra de esta notebook ([CentralBarra]). Se prende desde BARRA →
/// CAJAS (CENTRAL) y queda prendida mientras el programa esté abierto; al volver a abrir
/// BARRA esa noche se vuelve a prender sola ([reanudar]). Atiende una fiesta por vez.
///
/// **Es la central de una barra** (25-nov-2026: una notebook por barra): contesta con su
/// barra, y busca a la central de la otra barra para engancharse y pasarse todo.
class CentralDeLaBarra extends Notifier<EstadoCentralBarra> {
  CentralBarra? _central;
  RespondeBusqueda? _busqueda;
  StreamSubscription<List<CajaConectada>>? _cajas;
  StreamSubscription<void>? _puente;

  /// Se lee al armar: al cerrarse, Riverpod no deja leer otros providers.
  late AvisoALaRed _aviso;

  /// Con la central prendida, la notebook de la barra no se duerme: las tablets
  /// dependen de ella aunque nadie la toque ([PcDespierta]).
  PcDespierta? _despierta;

  @override
  EstadoCentralBarra build() {
    _aviso = ref.read(avisoALaRedProvider);
    _despierta = PcDespierta(avisar: ref.read(avisarUsoAlSistemaProvider));
    ref.onDispose(() => unawaited(_soltar()));
    return const EstadoCentralBarra();
  }

  /// Prende la central de [eventoId] en esta notebook, de la [barra] elegida (null: la
  /// recordada de este equipo). Si ya estaba prendida para esa fiesta y esa barra, solo
  /// relee las direcciones. [desdeElBoton] false: la volvió a prender [reanudar], y lo
  /// guardado (desde cuándo) no cambia.
  Future<void> prender(String eventoId, {String? barra, bool desdeElBoton = true}) async {
    if (!ref.read(redDeLaBarraHabilitadaProvider)) return;
    final deLaBarra = barraDe(barra) ?? await ref.read(barraDelEquipoProvider).leer();
    if (_central != null && state.eventoId == eventoId && state.barra == deLaBarra) {
      final direcciones = await ref.read(direccionesCentralBarraProvider)();
      state = state.con(direcciones: direcciones);
      return;
    }
    await _soltar();
    if (deLaBarra != null) unawaited(ref.read(barraDelEquipoProvider).guardar(deLaBarra));
    final central = CentralBarra(
      eventoId: eventoId,
      barra: ref.read(barraDeLaRedProvider),
      barraDelSalon: deLaBarra,
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
    _despierta?.mantener(true);
    final equipo = await ref.read(equipoDeLaBarraProvider)();
    final busqueda = RespondeBusqueda(eventoId: eventoId, puertoCentral: puerto, barra: deLaBarra, equipo: equipo);
    final contesta = await busqueda.escuchar(
      puerto: ref.read(puertoBusquedaBarraProvider),
      en: ref.read(escuchaCentralBarraProvider),
    );
    _busqueda = busqueda;
    // Lo que se hace en esta notebook (el jefe anula desde CAJAS) va a todas las cajas.
    _aviso.salida = central.difundirDeEstaPc;
    _cajas = central.cambiosDeCajas.listen((cajas) {
      if (identical(_central, central)) state = state.con(cajas: cajas, otras: central.otras);
    });
    // La central de la otra barra: si está en la misma red, se enganchan solas.
    _puente = central.cambiosDelPuente.listen((_) {
      if (identical(_central, central) && state.prendida) state = state.con(otras: central.otras);
    });
    central.engancharConOtras(
      equipo: equipo,
      buscador: BuscaCentral(
        eventoId: eventoId,
        puertos: ref.read(puertosQuePreguntaBarraProvider),
        destinos: ref.read(destinosBusquedaBarraProvider),
      ),
    );
    if (desdeElBoton) {
      unawaited(ref.read(guardadoDeLaCentralProvider).anotarPrendida(
            eventoId,
            barra: deLaBarra,
            ahora: ref.read(relojDeLaBarraProvider)(),
          ));
    }
    final direcciones = await ref.read(direccionesCentralBarraProvider)();
    if (!identical(_central, central)) return;
    state = EstadoCentralBarra(
      eventoId: eventoId,
      puerto: puerto,
      barra: deLaBarra,
      direcciones: direcciones,
      cajas: central.cajas,
      otras: central.otras,
      contestaBusqueda: contesta,
    );
  }

  /// Si la central de [eventoId] estaba prendida (la notebook se reinició, se cerró el
  /// programa), **la vuelve a prender sola, con su barra**, y las tablets se reconectan
  /// solas. Vuelve ([sigueLaNoche]):
  /// - la misma noche en que se prendió (hasta el mediodía siguiente);
  /// - la noche de la fiesta ([fechaDeLaFiesta]);
  /// - **mientras haya cajas abiertas de esa noche**, aunque pase el mediodía: la caja se
  ///   abre a la tarde y sigue hasta las 7 u 8 de la mañana (25-nov-2026; hasta la 6.9.3
  ///   dejaba de volver a las 18 horas de prenderla).
  Future<void> reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) async {
    if (_central != null) return;
    final guardada = await ref.read(guardadoDeLaCentralProvider).prendida();
    if (guardada == null || guardada.eventoId != eventoId || _central != null) return;
    List<CajaBarra> cajas;
    try {
      cajas = await ref.read(barraDeEsteEquipoProvider).cajas(eventoId);
    } catch (_) {
      cajas = const [];
    }
    final vuelve = sigueLaNoche(
      guardada: guardada,
      ahora: ref.read(relojDeLaBarraProvider)(),
      fechaDeLaFiesta: fechaDeLaFiesta,
      cajas: cajas,
    );
    if (!vuelve || _central != null) return;
    await prender(eventoId, barra: guardada.barra, desdeElBoton: false);
  }

  /// Corta el enganche con la central de la otra barra y la vuelve a buscar (si se ven,
  /// se vuelven a enganchar solas). Lo usa la ventana de prueba de las dos barras para
  /// "separar" las redes.
  void volverABuscarLaOtra() => _central?.volverABuscarLaOtra();

  Future<void> apagar() async {
    final guardado = ref.read(guardadoDeLaCentralProvider);
    await _soltar();
    unawaited(guardado.anotarPrendida(null));
    state = const EstadoCentralBarra();
  }

  Future<void> _soltar() async {
    final central = _central;
    _central = null;
    _despierta?.mantener(false);
    if (central != null && _aviso.salida == central.difundirDeEstaPc) _aviso.salida = null;
    _busqueda?.cerrar();
    _busqueda = null;
    await _cajas?.cancel();
    _cajas = null;
    await _puente?.cancel();
    _puente = null;
    await central?.cerrar();
  }
}

/// Si la central guardada vuelve a prenderse sola ([CentralDeLaBarra.reanudar]): la
/// misma noche en que se prendió, la noche de la fiesta, o mientras haya cajas abiertas
/// de esa noche (o de una después) en este equipo. Una caja de prueba de una noche
/// anterior que quedó abierta no la trae de vuelta.
bool sigueLaNoche({
  required CentralGuardada guardada,
  required DateTime ahora,
  DateTime? fechaDeLaFiesta,
  Iterable<CajaBarra> cajas = const [],
}) {
  final hoy = DiaDeOperacion.de(ahora);
  final noche = DiaDeOperacion.de(guardada.desde);
  if (hoy == noche) return true;
  if (fechaDeLaFiesta != null && DiaDeOperacion.delCalendario(fechaDeLaFiesta) == hoy) return true;
  return cajas.any((c) => c.abierta && !DiaDeOperacion.deLaCaja(c).isBefore(noche));
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

  /// La caja [nombreCaja] ("Caja 2 · Sofía") de [eventoId] empieza a buscar la central **de
  /// su [barra]** ("Barra 1"; null: cualquiera de la fiesta, como la encargada). Si ya
  /// estaba con esa fiesta, nada. En la notebook que tiene la central prendida para esa
  /// fiesta, tampoco: lo que se vende ahí ya va a la central.
  Future<void> arrancar({required String eventoId, required String nombreCaja, String? barra}) async {
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
      barraDeLaCaja: barraDe(barra),
      alGuardar: () => ref.read(operationalSyncRevisionProvider.notifier).bump(),
      buscador: BuscaCentral(
        eventoId: eventoId,
        puertos: ref.read(puertosQuePreguntaBarraProvider),
        destinos: ref.read(destinosBusquedaBarraProvider),
      ),
      aMano: aMano,
    );
    ref.read(avisoALaRedProvider).salida = cliente.mandar;
    _cliente = cliente;
    state = cliente;
    cliente.arrancar();
  }

  /// La encargada que entra **directo a LAS CAJAS**, sin pasar por VENDER: busca la
  /// central igual. Hasta la 6.8.0 solo VENDER la arrancaba: si su tablet se reiniciaba
  /// y ella entraba derecho a LAS CAJAS, sin internet no veía las ventas de las otras
  /// cajas ni "la Caja N pide cerrar", y su OK no salía por la red del salón (revisión
  /// del 13-nov).
  ///
  /// **Solo si no hay una conexión para esa fiesta:** si ya la arrancó VENDER con su
  /// caja, queda esa, con su nombre; [arrancar] con otro nombre la cortaría y la
  /// volvería a armar.
  Future<void> arrancarSiNoHay({required String eventoId, required String nombre}) async {
    if (_cliente?.eventoId == eventoId) return;
    await arrancar(eventoId: eventoId, nombreCaja: nombre);
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
