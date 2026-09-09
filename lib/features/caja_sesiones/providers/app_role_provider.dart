import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/instalacion_id.dart';
import '../../common/providers/admin_provider.dart';
import '../models/modo_jefe_caja.dart';
import '../models/operador_caja.dart';
import '../models/sesion_caja.dart';
import '../repositories/operadores_caja_repository.dart';
import '../repositories/sesiones_caja_repository.dart';
import '../services/caja_auto_sync_service.dart';

enum AppRoleKind { none, jefe, caja }

/// Qué se sabe de una caja del mismo operador abierta en **otro** dispositivo.
///
/// Los estados salen de la antigüedad del latido, que se publica cada
/// [kLatidoSesionPeriodo]. El programa solo afirma lo que ese dato permite
/// afirmar: fuera de la ventana de [kLatidoSesionVivo] no dice "está abierta en
/// otra PC" — dice cuándo fue el último movimiento y deja decidir.
enum EstadoCajaAjena {
  /// Nada abierto en otro dispositivo. Flujo normal, sin preguntas.
  libre,

  /// Latido más fresco que el período: **alguien la está usando ahora**.
  enUso,

  /// Entre el período y [kLatidoSesionMuerto], o sin red para verificar:
  /// no se sabe. Se informa, no se acusa.
  sinCerteza,

  /// Hace rato que no da señales: quedó abierta sin cerrar.
  sinSenales,
}

class CajaAjena {
  final EstadoCajaAjena estado;
  final SesionCaja? sesion;

  /// `false` si no se pudo refrescar contra el servidor.
  final bool verificado;

  const CajaAjena(this.estado, {this.sesion, this.verificado = true});

  static const libre = CajaAjena(EstadoCajaAjena.libre);

  bool get requiereConfirmacion => estado != EstadoCajaAjena.libre;

  /// Hace cuánto fue el último movimiento de esa caja.
  Duration get antiguedad => sesion?.antiguedadLatido() ?? Duration.zero;
}

/// El cobro no puede atribuirse a ninguna caja.
///
/// Frenar es preferible a guardar el pago huérfano: un cobro sin
/// `sesion_caja_id` no aparece en el cierre de nadie y no se detecta hasta el
/// arqueo, cuando ya no se sabe de quién era.
class SinCajaAbiertaException implements Exception {
  final String mensaje;
  const SinCajaAbiertaException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Resultado de cerrar una caja.
///
/// Devuelve la sesión ya cerrada —con su `cerradaAt` y su arqueo— porque el papel
/// del cierre se emite después, cuando el operario ya está deslogueado y el
/// estado de rol está vacío.
class CierreCajaResultado {
  /// `null` solo si no había caja abierta que cerrar.
  final SesionCaja? cerrada;

  /// `false` si el cierre quedó únicamente en esta PC (sin conexión).
  final bool sincronizado;

  const CierreCajaResultado({this.cerrada, required this.sincronizado});
}

class AppRoleState {
  final AppRoleKind kind;
  final OperadorCaja? operador;
  final SesionCaja? sesionActiva;

  const AppRoleState({
    this.kind = AppRoleKind.none,
    this.operador,
    this.sesionActiva,
  });

  bool get esJefe => kind == AppRoleKind.jefe;
  bool get esCaja => kind == AppRoleKind.caja;
  bool get tieneSesionCaja =>
      esCaja && sesionActiva != null && sesionActiva!.estaAbierta;

  AppRoleState copyWith({
    AppRoleKind? kind,
    OperadorCaja? operador,
    SesionCaja? sesionActiva,
    bool clearOperador = false,
    bool clearSesion = false,
  }) {
    return AppRoleState(
      kind: kind ?? this.kind,
      operador: clearOperador ? null : (operador ?? this.operador),
      sesionActiva: clearSesion ? null : (sesionActiva ?? this.sesionActiva),
    );
  }
}

class AppRoleNotifier extends Notifier<AppRoleState> {
  Timer? _heartbeatTimer;

  @override
  AppRoleState build() {
    ref.onDispose(() => _heartbeatTimer?.cancel());
    return const AppRoleState();
  }

  /// El id de esta PC. Vive en [InstalacionId] desde que también lo necesita el
  /// pulso de sincronización: la caja y el pulso tienen que ver la misma
  /// máquina, o `sesiones_caja.device_id` y el filtro de origen dejarían de
  /// hablar de lo mismo.
  Future<String> _deviceId() => InstalacionId.inicializar();

  /// PIN maestro → modo jefe (reutiliza adminAuthProvider).
  Future<bool> loginJefe(String pin) async {
    final ok = await ref.read(adminAuthProvider.notifier).verifyAndLogin(pin);
    if (!ok) return false;
    await ref.read(adminAuthProvider.notifier).enableModoJefe();
    _stopHeartbeat();
    state = const AppRoleState(kind: AppRoleKind.jefe);
    unawaited(_reanudarSesionJefe());
    return true;
  }

  /// Cierra las cajas que quedaron abiertas de días anteriores y suelta la
  /// propia si era una de ellas.
  ///
  /// Corre en cualquier dispositivo y sin importar el rol logueado: la caja que
  /// el jefe dejó abierta anoche la puede cerrar la PC del operario que abre a
  /// la mañana, y el UPDATE sube para todos. Es idempotente y barato, así que
  /// se llama en cada arranque, al volver del segundo plano y en cada latido.
  Future<void> autocerrarSesionesVencidas() async {
    try {
      final sesRepo = ref.read(sesionesCajaRepositoryProvider);
      final cerradas = <SesionCaja>[...await sesRepo.cerrarSesionJefeVencida()];
      final op = state.operador;
      if (op != null && !esOperadorModoJefeId(op.id)) {
        cerradas.addAll(
          await sesRepo.cerrarSesionesVencidasDeOperador(
            op.id,
            notaCierre: kNotaCierreCambioDiaCaja,
          ),
        );
      }
      if (cerradas.isEmpty) return;
      final propia = state.sesionActiva?.id;
      if (propia != null && cerradas.any((s) => s.id == propia)) {
        _stopHeartbeat();
        state = state.copyWith(clearSesion: true);
      }
      await sesRepo.flushBestEffort();
    } catch (_) {}
  }

  /// Si quedó una sesión de modo jefe abierta hoy, la retoma y la deja latiendo.
  ///
  /// Entrar como jefe **no abre caja**: si la única sesión abierta era de otro
  /// día, se cierra sellada a las 23:59 de su día y el estado queda sin sesión.
  /// La caja del jefe se abre recién al cobrar.
  Future<void> _reanudarSesionJefe() async {
    try {
      final sesRepo = ref.read(sesionesCajaRepositoryProvider);
      await sesRepo.cerrarSesionJefeVencida();
      final abierta = await sesRepo.sesionAbiertaDeOperador(
        kOperadorModoJefeId,
      );
      if (abierta == null || !state.esJefe) return;
      state = state.copyWith(
        sesionActiva: abierta.copyWith(operadorNombre: kOperadorModoJefeNombre),
      );
      _startHeartbeat(abierta.id);
      unawaited(sesRepo.heartbeat(abierta.id));
    } catch (_) {}
  }

  /// Botón "Iniciar caja" del jefe: abre (o retoma) la sesión automática
  /// del día y arranca el heartbeat. Deja la caja lista para cobrar.
  Future<SesionCaja> iniciarCajaJefe() async {
    if (!state.esJefe) throw StateError('Solo disponible en modo jefe');
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    final sesion = await sesRepo.ensureSesionModoJefe();
    state = state.copyWith(sesionActiva: sesion);
    _startHeartbeat(sesion.id);
    await sesRepo.flushBestEffort();
    return sesion;
  }

  /// Cierra la sesión de modo jefe con arqueo opcional. A diferencia del
  /// cierre de operario, NO desloguea: el jefe sigue en su dashboard.
  Future<CierreCajaResultado> cerrarCajaJefe({
    double? arqueoCierre,
    String? notaCierre,
  }) async {
    final sesion = state.sesionActiva;
    if (!state.esJefe || sesion == null) {
      return const CierreCajaResultado(sincronizado: true);
    }
    _stopHeartbeat();
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    final cerrada = await sesRepo.cerrar(
      sesionId: sesion.id,
      arqueoCierre: arqueoCierre,
      notaCierre: notaCierre,
    );
    final sincronizado = await sesRepo.flushConfirmandoSesion(sesion.id);
    state = state.copyWith(clearSesion: true);
    return CierreCajaResultado(cerrada: cerrada, sincronizado: sincronizado);
  }

  /// PIN de operador → rol caja; reanuda sesión abierta si existe.
  Future<String?> loginCaja(String pin) async {
    final repo = ref.read(operadoresCajaRepositoryProvider);
    final op = await repo.findByPin(pin);
    if (op == null) return 'PIN de caja incorrecto o operador inactivo';
    if (esOperadorModoJefeId(op.id)) {
      return 'PIN de caja incorrecto o operador inactivo';
    }

    _stopHeartbeat();
    await ref.read(adminAuthProvider.notifier).logout();

    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    // La caja de ayer se cierra sellada a las 23:59 de ayer. Al quedar sin
    // sesión activa, RoleGateScreen dispara solo el diálogo "Abrir caja" y el
    // operario declara el cambio inicial del día — sin pasos nuevos que
    // aprender.
    await sesRepo.cerrarSesionesVencidasDeOperador(
      op.id,
      notaCierre: kNotaCierreCambioDiaCaja,
    );
    await sesRepo.consolidarSesionesDuplicadas(op.id);
    final abierta = await sesRepo.sesionAbiertaDeOperador(op.id);
    state = AppRoleState(
      kind: AppRoleKind.caja,
      operador: op,
      sesionActiva: abierta,
    );
    if (abierta != null) {
      _startHeartbeat(abierta.id);
      unawaited(sesRepo.heartbeat(abierta.id));
    }
    return null;
  }

  /// Qué se sabe de una caja de este operador abierta en otro dispositivo.
  ///
  /// Se consulta **antes** de abrir. Nunca bloquea por sí sola: el resultado
  /// alimenta un diálogo que siempre tiene salida, porque un dato remoto viejo
  /// (cierre sin red, reloj desfasado, `device_id` regenerado) no puede costarle
  /// el turno a alguien que hizo todo bien.
  Future<CajaAjena> estadoCajaEnOtroDispositivo() async {
    final op = state.operador;
    if (op == null || !state.esCaja) return CajaAjena.libre;
    try {
      final verificado = await ref
          .read(cajaAutoSyncServiceProvider)
          .refreshBeforeOpen();
      final sesRepo = ref.read(sesionesCajaRepositoryProvider);
      final device = await _deviceId();
      final abiertas = await sesRepo.sesionesAbiertasDeOperador(op.id);
      final ajenas = abiertas.where((s) => (s.deviceId ?? '') != device);
      if (ajenas.isEmpty) {
        // Nada que decir, con red o sin ella: el flujo normal no se interrumpe.
        return CajaAjena.libre;
      }
      final ajena = ajenas.first;
      if (!verificado) {
        return CajaAjena(
          EstadoCajaAjena.sinCerteza,
          sesion: ajena,
          verificado: false,
        );
      }
      if (ajena.enUsoAhora()) {
        return CajaAjena(EstadoCajaAjena.enUso, sesion: ajena);
      }
      if (ajena.sinSenales()) {
        return CajaAjena(EstadoCajaAjena.sinSenales, sesion: ajena);
      }
      return CajaAjena(EstadoCajaAjena.sinCerteza, sesion: ajena);
    } catch (_) {
      // Ante cualquier falla, no inventar un conflicto.
      return CajaAjena.libre;
    }
  }

  /// Abre la caja del operador logueado.
  ///
  /// [tomarDeOtroDispositivo] cierra primero las sesiones abiertas de este mismo
  /// operador en otras PCs. Hace falta porque `abrir()` es idempotente: sin
  /// cerrarlas, reanudaría la sesión ajena con el cambio inicial equivocado en
  /// vez de abrir una nueva.
  Future<void> abrirSesionCaja({
    required double cambioInicial,
    required String etiqueta,
    String? notaApertura,
    bool tomarDeOtroDispositivo = false,
  }) async {
    final op = state.operador;
    if (op == null || !state.esCaja) {
      throw StateError('No hay operador de caja logueado');
    }
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    final deviceId = await _deviceId();
    var nota = notaApertura?.trim() ?? '';
    if (tomarDeOtroDispositivo) {
      final tomadas = <String>[];
      for (final s in await sesRepo.sesionesAbiertasDeOperador(op.id)) {
        if ((s.deviceId ?? '') == deviceId) continue;
        await sesRepo.cerrar(
          sesionId: s.id,
          notaCierre: kNotaCierreTomadaOtraPc,
        );
        tomadas.add(s.deviceId ?? 'otra PC');
      }
      if (tomadas.isNotEmpty) {
        // La traza va en la nota de APERTURA de esta sesión, no en la de cierre
        // de la otra: si aquella PC recupera internet y sube su propio cierre
        // (con arqueo real, que es el que debe ganar), su nota se pisa. Esta
        // fila, en cambio, no la escribe nadie más.
        final traza = 'Caja tomada de ${tomadas.join(', ')} (sin cerrar allá)';
        nota = nota.isEmpty ? traza : '$traza · $nota';
      }
    }
    final sesion = await sesRepo.abrir(
      operadorId: op.id,
      cambioInicial: cambioInicial,
      etiqueta: etiqueta,
      notaApertura: nota,
      deviceId: deviceId,
    );
    state = state.copyWith(sesionActiva: sesion);
    _startHeartbeat(sesion.id);
    await sesRepo.flushBestEffort();
  }

  /// Cierra la caja del operario y lo desloguea.
  ///
  /// [CierreCajaResultado.sincronizado] es `false` si el cierre quedó **solo en
  /// esta PC** (sin conexión). El diálogo lo avisa en el momento: si nadie avisa,
  /// ese cierre reaparece horas después en otra PC como "caja abierta",
  /// desconectado de su causa, y eso se vive como un bug del programa.
  ///
  /// Devuelve también la sesión ya cerrada, con su `cerradaAt` y su arqueo, para
  /// que el papel del cierre pueda emitirse **después** del logout sin depender
  /// de un estado que a esa altura ya está vacío. La generación del PDF queda
  /// afuera a propósito: entregar un PDF puede abrir un diálogo del sistema que
  /// no termina hasta que alguien lo cierre, y esperarlo acá dejaría la caja
  /// cerrada con el operario todavía logueado.
  Future<CierreCajaResultado> cerrarSesionCaja({
    double? arqueoCierre,
    String? notaCierre,
  }) async {
    final sesion = state.sesionActiva;
    if (sesion == null) return const CierreCajaResultado(sincronizado: true);
    _stopHeartbeat();
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    final cerrada = await sesRepo.cerrar(
      sesionId: sesion.id,
      arqueoCierre: arqueoCierre,
      notaCierre: notaCierre,
    );
    final sincronizado = await sesRepo.flushConfirmandoSesion(sesion.id);
    await ref.read(adminAuthProvider.notifier).logout();
    state = const AppRoleState();
    return CierreCajaResultado(cerrada: cerrada, sincronizado: sincronizado);
  }

  /// ID de sesión a persistir en un cobro: sesión de caja activa, o sesión
  /// automática `Modo jefe` (día completo, sin corte de turno) si se cobra como jefe.
  ///
  /// Nunca devuelve `null`: si el cobro no se puede atribuir a ninguna caja
  /// lanza [SinCajaAbiertaException] para que el modal lo frene. Antes devolvía
  /// `null` en silencio y `registrarPago` omitía la columna, así que el pago
  /// quedaba huérfano y no aparecía en el cierre de nadie.
  Future<String> sesionCajaIdParaCobro() async {
    if (state.esCaja) {
      final sesion = state.sesionActiva;
      if (sesion == null || !sesion.estaAbierta) {
        throw const SinCajaAbiertaException(
          'No hay caja abierta. Abrí tu caja antes de cobrar.',
        );
      }
      return sesion.id;
    }
    if (state.esJefe) {
      final sesion = await ref
          .read(sesionesCajaRepositoryProvider)
          .ensureSesionModoJefe();
      // Cobró sin apretar "Iniciar caja": la sesión automática también
      // queda activa y latiendo, para que el chip refleje la realidad.
      if (state.sesionActiva?.id != sesion.id) {
        state = state.copyWith(sesionActiva: sesion);
        _startHeartbeat(sesion.id);
      }
      return sesion.id;
    }
    throw const SinCajaAbiertaException(
      'No hay una sesión de caja activa para atribuir este cobro. '
      'Entrá como jefe o abrí tu caja de operador.',
    );
  }

  /// Vuelve al gate sin sync. Si hay caja abierta, la deja abierta en local
  /// (reanudable al volver a entrar con el mismo operador).
  Future<void> logoutApp() async {
    _stopHeartbeat();
    await ref.read(adminAuthProvider.notifier).logout();
    state = const AppRoleState();
  }

  void _startHeartbeat(String sesionId) {
    _stopHeartbeat();
    // Publicación limitada: mantiene verde el estado remoto sin generar tráfico
    // continuo. La cola deduplica el UPDATE de esta sesión.
    //
    // El período es la fuente de la que salen los umbrales de kLatidoSesionVivo
    // y kLatidoSesionMuerto: si se cambia acá, hay que revisarlos.
    _heartbeatTimer = Timer.periodic(kLatidoSesionPeriodo, (_) async {
      try {
        // Cubre la app que queda prendida de noche: a los ≤60 s de la
        // medianoche la caja se cierra sola y el chip refleja la realidad.
        await autocerrarSesionesVencidas();
        if (state.sesionActiva?.id != sesionId) return;

        final repo = ref.read(sesionesCajaRepositoryProvider);
        await repo.heartbeat(sesionId);
        await repo.flushBestEffort();
        final fresh = await repo.getById(sesionId);
        if (fresh == null) return;
        if (!fresh.estaAbierta) {
          // La cerraron desde otra PC (o el jefe la cerró). Soltarla en vez de
          // seguir latiendo sobre una caja que ya no existe.
          _stopHeartbeat();
          state = state.esJefe
              ? state.copyWith(clearSesion: true)
              : const AppRoleState();
          return;
        }
        if (state.esCaja || state.esJefe) {
          state = state.copyWith(sesionActiva: fresh);
        }
      } catch (_) {}
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

final appRoleProvider = NotifierProvider<AppRoleNotifier, AppRoleState>(
  AppRoleNotifier.new,
);

/// Compat: UI que mira esModoJefe también considera appRole jefe.
final esRolJefeProvider = Provider<bool>((ref) {
  final app = ref.watch(appRoleProvider);
  if (app.esJefe) return true;
  return ref.watch(adminAuthProvider).esModoJefe;
});
