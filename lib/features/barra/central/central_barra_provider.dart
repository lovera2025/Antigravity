import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/instalacion_id.dart';
import '../../../core/services/pc_despierta.dart';
import '../../caja_sesiones/models/modo_jefe_caja.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../caja_sesiones/repositories/operadores_caja_repository.dart';
import '../../caja_sesiones/repositories/permisos_operador_repository.dart';
import '../../common/providers/admin_provider.dart';
import '../../common/widgets/operational_sync_coordinator.dart';
import '../../recepcion/central/direcciones_red.dart';
import '../cuentas/reglas_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import '../pagina/catalogo_de_la_pagina.dart';
import '../providers/barra_del_jefe_provider.dart';
import '../providers/barra_providers.dart' show eventosDeLaBarraProvider, subirDeLaBarraProvider;
import '../services/barras_del_salon.dart';
import 'barra_con_la_red.dart';
import 'buscar_central.dart';
import 'central_barra.dart';
import 'cliente_de_la_central.dart';
import 'filas_de_la_red.dart';
import 'llave_de_la_barra.dart';
import 'vigia_de_la_red.dart';

/// Si este equipo usa la red del salón (la central de la barra). En la web no; las
/// pruebas de pantalla lo apagan (`BarraEnPrueba`), así no abren conexiones de verdad.
final redDeLaBarraHabilitadaProvider = Provider<bool>((ref) => !kIsWeb);

/// Si en este equipo se muestra PRENDER LA CENTRAL (6.4.0): en la notebook sí, en la
/// web y en una tablet Android no. La central es la notebook del salón; la encargada
/// mira LAS CAJAS desde su tablet, y dos centrales en la misma red se pisarían.
/// En la tablet se pregunta por `Platform`, no por `defaultTargetPlatform`
/// (en `flutter test` ese dice siempre Android).
final centralSePrendeAcaProvider = Provider<bool>((ref) => !kIsWeb && !Platform.isAndroid);

/// **La página del iPhone de la encargada y del repositor** (28-nov-2026): la carpeta
/// `barra_pagina` al lado del programa, que deja el instalador. Null si no está (la
/// central sigue andando para las tablets, sin la página). Los tests la reemplazan.
final paginaDeLaBarraProvider = Provider<Directory?>((ref) {
  try {
    if (kIsWeb || Platform.isAndroid) return null;
    final carpeta = Directory('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}barra_pagina');
    return carpeta.existsSync() ? carpeta : null;
  } catch (_) {
    return null;
  }
});

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

/// Quién mira si este equipo cambió de red ([VigiaDeLaRed]); uno por central y por caja.
/// Las pruebas lo reemplazan para cambiar la red a mano.
final vigiaDeLaRedProvider = Provider<VigiaDeLaRed Function()>((ref) => VigiaDeLaRed.new);

/// **Quién es quién para la central de esta notebook** (26-nov-2026): sus operadores con
/// sus permisos y su PIN maestro. Con eso la central reconoce el PIN de cada aparato sin
/// que el PIN viaje. Los tests lo reemplazan.
final quienEsQuienEnLaBarraProvider = Provider<QuienEsQuienEnLaBarra>((ref) => QuienEsQuienDeLaApp(ref));

class QuienEsQuienDeLaApp implements QuienEsQuienEnLaBarra {
  QuienEsQuienDeLaApp(this._ref);
  final Ref _ref;

  @override
  Future<PersonaDeLaBarra?> operador(String id) async {
    final op = await _ref.read(operadoresCajaRepositoryProvider).getById(id);
    if (op == null || !op.activo || esOperadorModoJefeId(op.id) || op.pin.trim().isEmpty) return null;
    final permisos = await _ref.read(permisosOperadorRepositoryProvider).de(op.id);
    return PersonaDeLaBarra(id: op.id, nombre: op.nombre, pin: op.pin, rol: ReglasDeLaBarra.dePermisos(permisos));
  }

  @override
  Future<String?> pinMaestro() => _ref.read(adminAuthProvider.notifier).pinMaestroDeEstaPc();

  @override
  Future<bool> esEncargada(String nombre) async {
    final buscado = nombre.trim().toLowerCase();
    for (final op in await _ref.read(operadoresCajaRepositoryProvider).listar(soloActivos: true)) {
      if (op.nombre.trim().toLowerCase() != buscado) continue;
      if ((await _ref.read(permisosOperadorRepositoryProvider).de(op.id)).encargadaBarra) return true;
    }
    return false;
  }

  @override
  Future<List<PersonaDeLaBarra>> paraLaPagina() async {
    final lista = <PersonaDeLaBarra>[];
    for (final op in await _ref.read(operadoresCajaRepositoryProvider).listar(soloActivos: true)) {
      if (esOperadorModoJefeId(op.id) || op.pin.trim().isEmpty) continue;
      final rol = ReglasDeLaBarra.dePermisos(await _ref.read(permisosOperadorRepositoryProvider).de(op.id));
      if (rol == RolEnLaBarra.encargada || rol == RolEnLaBarra.repositor) {
        lista.add(PersonaDeLaBarra(id: op.id, nombre: op.nombre, pin: op.pin, rol: rol));
      }
    }
    return lista;
  }
}

/// **Con qué PIN se conecta a la central la caja de este aparato**: el de quien entró a la
/// barra (cajera o encargada) o, en modo jefe, el PIN maestro. Null: nadie puso su PIN, y
/// la central no la deja entrar. Los tests lo reemplazan.
final credencialDeLaBarraProvider = Provider<Future<CredencialDeLaBarra?> Function()>((ref) => () async {
      final estado = ref.read(appRoleProvider);
      final op = estado.operador;
      if (estado.esBarra && op != null && op.pin.trim().isNotEmpty) {
        return CredencialDeLaBarra.operador(op.id, op.pin);
      }
      if (ref.read(esRolJefeProvider)) {
        return CredencialDeLaBarra.maestro(await ref.read(adminAuthProvider.notifier).pinMaestroDeEstaPc());
      }
      return null;
    });

/// **Quién está usando la barra en este aparato** ("operador:<id>", "jefe" o null), para
/// saber si la conexión con la central sigue siendo de la misma persona. La central
/// reconoce a quien puso su PIN **al conectarse**: si en la tablet entra otra persona (la
/// cajera sale y la encargada abre LAS CAJAS) y la conexión no se rehace, la central la
/// sigue tomando por la anterior y rechaza lo que hace (revisión del 27-nov-2026).
final quienUsaLaBarraProvider = Provider<String? Function()>((ref) => () {
      final estado = ref.read(appRoleProvider);
      final op = estado.operador;
      if (estado.esBarra && op != null) return 'operador:${op.id}';
      if (ref.read(esRolJefeProvider)) return 'jefe';
      return null;
    });

/// Con qué se engancha esta central a la de la otra barra: el PIN maestro de esta
/// notebook (las dos notebooks tienen que tener el mismo). Los tests lo reemplazan.
final credencialDeLaCentralProvider = Provider<Future<CredencialDeLaBarra?> Function()>(
    (ref) => () async => CredencialDeLaBarra.maestro(await ref.read(adminAuthProvider.notifier).pinMaestroDeEstaPc()));

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

  /// Lo que llegó por el wifi y la central **no guardó**, con quién lo mandó y por qué (los
  /// últimos, del más viejo al más nuevo). Hasta el 28-nov-2026 no se veía en ninguna
  /// pantalla de la notebook: quien lo había hecho creía que había llegado.
  final List<RechazoDeLaCentral> rechazos;

  const EstadoCentralBarra({
    this.eventoId,
    this.puerto,
    this.barra,
    this.direcciones = const [],
    this.cajas = const [],
    this.otras = const [],
    this.contestaBusqueda = false,
    this.error,
    this.rechazos = const [],
    this.paginas = const [],
    this.hayPagina = false,
  });

  /// Los teléfonos con la página de la barra abierta (la encargada, el repositor).
  final List<PaginaConectada> paginas;

  /// Si esta notebook tiene la página del iPhone para servir.
  final bool hayPagina;

  /// Lo que va en el QR de la página del iPhone: `http://192.168.0.10:8797/`. Null sin
  /// página o sin router.
  String? get enlaceDeLaPagina => !hayPagina || direccion == null ? null : 'http://$direccion/';

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

  EstadoCentralBarra con({
    List<String>? direcciones,
    List<CajaConectada>? cajas,
    List<EngancheConOtra>? otras,
    List<RechazoDeLaCentral>? rechazos,
    List<PaginaConectada>? paginas,
  }) =>
      EstadoCentralBarra(
        eventoId: eventoId,
        puerto: puerto,
        barra: barra,
        direcciones: direcciones ?? this.direcciones,
        cajas: cajas ?? this.cajas,
        otras: otras ?? this.otras,
        contestaBusqueda: contestaBusqueda,
        error: error,
        rechazos: rechazos ?? this.rechazos,
        paginas: paginas ?? this.paginas,
        hayPagina: hayPagina,
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
  StreamSubscription<void>? _rechazos;
  StreamSubscription<List<PaginaConectada>>? _paginas;

  /// Si la notebook cambia de red, vuelve a abrir lo que contesta la búsqueda y relee
  /// sus direcciones, sin apagar la central (26-nov-2026).
  VigiaDeLaRed? _vigia;
  StreamSubscription<void>? _cambiosDeRed;

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

  /// Prender, volver a prender y apagar van **de a uno, en el orden en que se pidieron**
  /// (26-nov-2026, la revisión independiente): tocar PRENDER mientras [reanudar] todavía
  /// armaba la central dejaba una central a medio cerrar contestando con un puerto muerto,
  /// o dos centrales con el mismo id y las tablets repartidas entre las dos.
  Future<void> _enCurso = Future<void>.value();

  Future<void> _enOrden(Future<void> Function() hacer) {
    final hecho = _enCurso.then((_) => hacer());
    _enCurso = hecho.then<void>((_) {}, onError: (Object _) {});
    return hecho;
  }

  /// Prende la central de [eventoId] en esta notebook, de la [barra] elegida (null: la
  /// recordada de este equipo). Si ya estaba prendida para esa fiesta y esa barra, solo
  /// relee las direcciones. [desdeElBoton] false: la volvió a prender [reanudar], y lo
  /// guardado (desde cuándo) no cambia.
  Future<void> prender(String eventoId, {String? barra, bool desdeElBoton = true}) =>
      _enOrden(() => _prender(eventoId, barra: barra, desdeElBoton: desdeElBoton));

  Future<void> _prender(String eventoId, {String? barra, required bool desdeElBoton}) async {
    if (!ref.read(redDeLaBarraHabilitadaProvider)) return;
    final deLaBarra = barraDe(barra) ?? await ref.read(barraDelEquipoProvider).leer();
    if (_central != null && state.eventoId == eventoId && state.barra == deLaBarra) {
      final direcciones = await ref.read(direccionesCentralBarraProvider)();
      state = state.con(direcciones: direcciones);
      return;
    }
    await _soltar();
    if (deLaBarra != null) unawaited(ref.read(barraDelEquipoProvider).guardar(deLaBarra));
    final pagina = ref.read(paginaDeLaBarraProvider);
    final central = CentralBarra(
      eventoId: eventoId,
      barra: ref.read(barraDeLaRedProvider),
      quienEsQuien: ref.read(quienEsQuienEnLaBarraProvider),
      barraDelSalon: deLaBarra,
      alGuardar: () => ref.read(operationalSyncRevisionProvider.notifier).bump(),
      // La página del iPhone (28-nov-2026): la sirve esta central, con lo que necesita.
      paginaDeLaBarra: pagina,
      fiestaParaLaPagina: () async {
        final eventos = await ref.read(eventosDeLaBarraProvider.future);
        final evento = eventos.where((e) => e.id == eventoId).firstOrNull;
        return evento == null ? null : fiestaParaLaPagina(evento);
      },
      catalogoParaLaPagina: () => catalogoParaLaPagina(ref.read(barraDelJefeProvider), eventoId),
      // Lo que anotó la página lo sube esta notebook enseguida.
      alGuardarDeLaPagina: (tabla, id) => unawaited(ref.read(subirDeLaBarraProvider)(tabla, id)),
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
    // Esta notebook ya es la central de esa fiesta: si antes se había conectado como caja
    // (VENDER o LAS CAJAS de la encargada) a la central de otra notebook, se suelta. Con el
    // mismo id que su enganche, la otra central los echaba por turno sin fin (26-nov-2026,
    // la revisión independiente).
    ref.read(clienteDeLaBarraProvider.notifier).soltarSiEsDe(eventoId);
    final equipo = await ref.read(equipoDeLaBarraProvider)();
    final busqueda = RespondeBusqueda(eventoId: eventoId, puertoCentral: puerto, barra: deLaBarra, equipo: equipo);
    final contesta = await busqueda.escuchar(
      puerto: ref.read(puertoBusquedaBarraProvider),
      en: ref.read(escuchaCentralBarraProvider),
    );
    if (!identical(_central, central)) {
      busqueda.cerrar();
      return;
    }
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
    // Lo que la central no guardó: a la vista en el panel de la notebook.
    _rechazos = central.cambiosDeRechazos.listen((_) {
      if (identical(_central, central) && state.prendida) {
        state = state.con(rechazos: List.unmodifiable(central.rechazos));
      }
    });
    // Los teléfonos con la página abierta: a la vista en el panel de la notebook.
    _paginas = central.cambiosDePaginas.listen((paginas) {
      if (identical(_central, central) && state.prendida) state = state.con(paginas: paginas);
    });
    // Si la notebook cambia de red: lo que contesta la búsqueda se vuelve a abrir, las
    // direcciones que muestra CAJAS se releen y el enganche busca de nuevo (26-nov-2026:
    // hasta ahí había que apagar y prender la central).
    final vigia = ref.read(vigiaDeLaRedProvider)();
    _vigia = vigia;
    _cambiosDeRed = vigia.cambios.listen((_) async {
      if (!identical(_central, central)) return;
      await _busqueda?.reabrir();
      final direcciones = await ref.read(direccionesCentralBarraProvider)();
      if (identical(_central, central) && state.prendida) state = state.con(direcciones: direcciones);
    });
    vigia.arrancar();
    central.engancharConOtras(
      equipo: equipo,
      buscador: BuscaCentral(
        eventoId: eventoId,
        puertos: ref.read(puertosQuePreguntaBarraProvider),
        destinos: ref.read(destinosBusquedaBarraProvider),
      ),
      cambiosDeRed: vigia.cambios,
      credencial: ref.read(credencialDeLaCentralProvider),
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
      rechazos: List.unmodifiable(central.rechazos),
      paginas: central.paginas,
      hayPagina: pagina != null,
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
  Future<void> reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) =>
      _enOrden(() => _reanudar(eventoId, fechaDeLaFiesta: fechaDeLaFiesta));

  Future<void> _reanudar(String eventoId, {DateTime? fechaDeLaFiesta}) async {
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
    await _prender(eventoId, barra: guardada.barra, desdeElBoton: false);
  }

  /// Corta el enganche con la central de la otra barra y la vuelve a buscar (si se ven,
  /// se vuelven a enganchar solas). Lo usa la ventana de prueba de las dos barras para
  /// "separar" las redes.
  void volverABuscarLaOtra() => _central?.volverABuscarLaOtra();

  Future<void> apagar() => _enOrden(_apagar);

  Future<void> _apagar() async {
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
    await _cambiosDeRed?.cancel();
    _cambiosDeRed = null;
    await _vigia?.cerrar();
    _vigia = null;
    await _cajas?.cancel();
    _cajas = null;
    await _puente?.cancel();
    _puente = null;
    await _rechazos?.cancel();
    _rechazos = null;
    await _paginas?.cancel();
    _paginas = null;
    await central?.cerrar();
  }
}

/// Si la central guardada vuelve a prenderse sola ([CentralDeLaBarra.reanudar]):
/// - la misma noche en que se prendió (hasta el mediodía siguiente);
/// - la noche de la fiesta;
/// - **el día siguiente, pasado el mediodía, mientras queden abiertas cajas de anoche**
///   (de la noche en que se prendió o de una después): la fiesta que siguió de día.
///
/// Nunca más allá: una caja de prueba que quedó abierta la noche en que se prendió la
/// central la traía de vuelta para siempre, cada vez que se abría CAJAS de esa fiesta
/// (26-nov-2026, la revisión independiente).
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
  final anoche = hoy.anterior;
  if (anoche.isBefore(noche)) return false;
  return cajas.any((c) => c.abierta && DiaDeOperacion.deLaCaja(c) == anoche);
}

final centralDeLaBarraProvider =
    NotifierProvider<CentralDeLaBarra, EstadoCentralBarra>(CentralDeLaBarra.new);

/// La caja de esta tablet con la central ([ClienteDeLaCentral]). La arranca VENDER; queda
/// andando mientras la app esté abierta. Null: todavía no arrancó (o no hay red del salón).
class ClienteDeLaBarra extends Notifier<ClienteDeLaCentral?> {
  ClienteDeLaCentral? _cliente;

  /// De quién es la conexión que está abierta ([quienUsaLaBarraProvider] al arrancarla).
  String? _deQuien;

  /// Si la tablet cambia de red, la caja busca la central de nuevo (26-nov-2026).
  VigiaDeLaRed? _vigia;

  @override
  ClienteDeLaCentral? build() {
    ref.onDispose(() {
      _cliente?.dispose();
      _cliente = null;
      unawaited(_vigia?.cerrar());
      _vigia = null;
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
    final quien = ref.read(quienUsaLaBarraProvider)();
    // La misma fiesta, la misma caja **y la misma persona**: con otra, la conexión se
    // rehace para que la central la reconozca por su PIN.
    if (ya != null && ya.eventoId == eventoId && ya.nombreCaja == nombreCaja && _deQuien == quien) return;
    _soltar();
    _deQuien = quien;
    final equipo = await ref.read(equipoDeLaBarraProvider)();
    final aMano = await ref.read(guardadoDeLaCentralProvider).aMano();
    if (_cliente != null) return;
    final vigia = ref.read(vigiaDeLaRedProvider)();
    _vigia = vigia;
    final cliente = ClienteDeLaCentral(
      cambiosDeRed: vigia.cambios,
      credencial: ref.read(credencialDeLaBarraProvider),
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
    vigia.arrancar();
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
    // "Queda esa" vale mientras sea de la misma persona: si la dejó conectada otra (la
    // cajera que salió), se rehace con quien entró ahora.
    if (_cliente?.eventoId == eventoId && _deQuien == ref.read(quienUsaLaBarraProvider)()) return;
    await arrancar(eventoId: eventoId, nombreCaja: nombre);
  }

  /// La dirección que muestra la notebook, escrita a mano en la tablet. Null: se la busca sola.
  Future<void> ponerAMano(DondeEstaLaCentral? donde) async {
    await ref.read(guardadoDeLaCentralProvider).anotarAMano(donde);
    _cliente?.ponerAMano(donde);
  }

  /// La notebook que prende la central de [eventoId] ya no necesita su conexión de caja a
  /// otra central de esa fiesta: se corta (ver [CentralDeLaBarra.prender]).
  void soltarSiEsDe(String eventoId) {
    if (_cliente?.eventoId == eventoId) _soltar();
  }

  void _soltar() {
    unawaited(_vigia?.cerrar());
    _vigia = null;
    _deQuien = null;
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

/// Si este equipo **sabe lo que pasa en las demás cajas** de la fiesta en este momento:
/// está conectado a la central de la barra, o es la notebook que la tiene prendida para
/// esa fiesta. Con eso VENDER frena lo que no queda en su barra; sin eso avisa "sin
/// señal" y deja vender (28-nov-2026). Se pregunta en el momento, no se escucha.
final hayCentralALaVistaProvider = Provider<bool Function(String eventoId)>((ref) {
  return (eventoId) {
    final central = ref.read(centralDeLaBarraProvider);
    if (central.prendida && central.eventoId == eventoId) return true;
    return ref.read(clienteDeLaBarraProvider)?.estado == EstadoDeLaCentral.conectada;
  };
});
