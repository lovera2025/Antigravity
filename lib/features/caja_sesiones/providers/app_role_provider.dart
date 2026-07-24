import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/ar_time.dart';
import '../../common/providers/admin_provider.dart';
import '../models/modo_jefe_caja.dart';
import '../models/operador_caja.dart';
import '../models/sesion_caja.dart';
import '../repositories/operadores_caja_repository.dart';
import '../repositories/sesiones_caja_repository.dart';

enum AppRoleKind { none, jefe, caja }

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
  static const _deviceKey = 'caja_device_id';
  Timer? _heartbeatTimer;

  @override
  AppRoleState build() {
    ref.onDispose(() => _heartbeatTimer?.cancel());
    return const AppRoleState();
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey);
    if (id == null || id.isEmpty) {
      id = 'pc-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

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

  /// Si quedó una sesión de modo jefe abierta hoy, la retoma y la deja
  /// latiendo. Una de otro día la cierra ensureSesionModoJefe al cobrar.
  Future<void> _reanudarSesionJefe() async {
    try {
      final sesRepo = ref.read(sesionesCajaRepositoryProvider);
      final abierta = await sesRepo.sesionAbiertaDeOperador(
        kOperadorModoJefeId,
      );
      if (abierta == null || !state.esJefe) return;
      final ar = ArTime.toAr(abierta.abiertaAt);
      final hoy = ArTime.nowAr();
      final mismoDia =
          ar.year == hoy.year && ar.month == hoy.month && ar.day == hoy.day;
      if (!mismoDia) return;
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
  Future<void> cerrarCajaJefe({double? arqueoCierre, String? notaCierre}) async {
    final sesion = state.sesionActiva;
    if (!state.esJefe || sesion == null) return;
    _stopHeartbeat();
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    await sesRepo.cerrar(
      sesionId: sesion.id,
      arqueoCierre: arqueoCierre,
      notaCierre: notaCierre,
    );
    await sesRepo.flushBestEffort();
    state = state.copyWith(clearSesion: true);
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

  Future<void> abrirSesionCaja({
    required double cambioInicial,
    required String etiqueta,
    String? notaApertura,
  }) async {
    final op = state.operador;
    if (op == null || !state.esCaja) {
      throw StateError('No hay operador de caja logueado');
    }
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    final deviceId = await _deviceId();
    final sesion = await sesRepo.abrir(
      operadorId: op.id,
      cambioInicial: cambioInicial,
      etiqueta: etiqueta,
      notaApertura: notaApertura,
      deviceId: deviceId,
    );
    state = state.copyWith(sesionActiva: sesion);
    _startHeartbeat(sesion.id);
    await sesRepo.flushBestEffort();
  }

  Future<void> cerrarSesionCaja({
    double? arqueoCierre,
    String? notaCierre,
  }) async {
    final sesion = state.sesionActiva;
    if (sesion == null) return;
    _stopHeartbeat();
    final sesRepo = ref.read(sesionesCajaRepositoryProvider);
    await sesRepo.cerrar(
      sesionId: sesion.id,
      arqueoCierre: arqueoCierre,
      notaCierre: notaCierre,
    );
    await sesRepo.flushBestEffort();
    await ref.read(adminAuthProvider.notifier).logout();
    state = const AppRoleState();
  }

  /// ID de sesión a persistir en un cobro: sesión de caja activa, o sesión
  /// automática `Modo jefe` (día completo, sin corte de turno) si se cobra como jefe.
  Future<String?> sesionCajaIdParaCobro() async {
    if (state.esCaja) return state.sesionActiva?.id;
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
    return null;
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      try {
        final repo = ref.read(sesionesCajaRepositoryProvider);
        await repo.heartbeat(sesionId);
        await repo.flushBestEffort();
        final fresh = await repo.getById(sesionId);
        if (fresh != null && (state.esCaja || state.esJefe)) {
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
