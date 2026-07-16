import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminAuthState {
  /// Sesión PIN puntual (TTL) o activa porque [modoJefe] está ON.
  final bool isAdmin;

  /// Modo jefe solo en memoria (sesión de app); no sobrevive a reinicio.
  final bool modoJefe;

  final DateTime? expiresAt;

  AdminAuthState({
    required this.isAdmin,
    this.modoJefe = false,
    this.expiresAt,
  });

  factory AdminAuthState.loggedOut() => AdminAuthState(isAdmin: false);

  /// UI privilegiada del menú / métricas / cierre histórico.
  bool get esModoJefe => modoJefe;
}

class AdminAuthNotifier extends Notifier<AdminAuthState> {
  static const String _prefKey = 'admin_session_expiry';
  /// Key legacy: se borra al arrancar; modo jefe ya no se persiste.
  static const String _modoJefeKey = 'modo_jefe_activo';
  static const String _pinKey = 'admin_pin';
  static const String _defaultPin = '2026';
  static const String _miEmpresaExitKey = 'mi_empresa_last_exit';

  /// Tras validar PIN MAESTRO puntual (AdminGate), duración del flag sin modo jefe.
  static const Duration sessionTtl = Duration(minutes: 3);

  /// Si salís de Mi Empresa y volvés pasado este tiempo, se pide PIN de nuevo.
  static const Duration miEmpresaReauthGrace = Duration(minutes: 3);

  @override
  AdminAuthState build() {
    _loadSession();
    return AdminAuthState.loggedOut();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    // Migración: nunca restaurar modo jefe tras reinicio.
    await prefs.remove(_modoJefeKey);

    final expiryStr = prefs.getString(_prefKey);
    if (expiryStr != null) {
      final expiry = DateTime.parse(expiryStr);
      if (expiry.isAfter(DateTime.now())) {
        state = AdminAuthState(isAdmin: true, expiresAt: expiry);
      } else {
        await prefs.remove(_prefKey);
        state = AdminAuthState.loggedOut();
      }
    }
  }

  Future<String> _getPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinKey) ?? _defaultPin;
  }

  Future<bool> verifyAndLogin(String pin) async {
    final storedPin = await _getPin();
    if (pin == storedPin) {
      final prefs = await SharedPreferences.getInstance();
      // Si modo jefe ya está ON en esta sesión, mantenerlo (sin TTL).
      if (state.modoJefe) {
        await prefs.remove(_miEmpresaExitKey);
        state = AdminAuthState(isAdmin: true, modoJefe: true);
        return true;
      }
      final expiry = DateTime.now().add(sessionTtl);
      await prefs.setString(_prefKey, expiry.toIso8601String());
      await prefs.remove(_miEmpresaExitKey);
      state = AdminAuthState(isAdmin: true, expiresAt: expiry);
      return true;
    }
    return false;
  }

  /// Activa modo jefe solo en memoria (llamar tras PIN correcto desde el interruptor).
  Future<void> enableModoJefe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modoJefeKey);
    await prefs.remove(_prefKey);
    await prefs.remove(_miEmpresaExitKey);
    state = AdminAuthState(isAdmin: true, modoJefe: true);
  }

  /// Apaga modo jefe (interruptor OFF).
  Future<void> disableModoJefe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modoJefeKey);
    await prefs.remove(_prefKey);
    await prefs.remove(_miEmpresaExitKey);
    state = AdminAuthState.loggedOut();
  }

  /// Llamar al salir de [FinanzasView] (Mi Empresa) para marcar que hubo una salida.
  Future<void> recordMiEmpresaExit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_miEmpresaExitKey, DateTime.now().toIso8601String());
  }

  /// Sesión admin activa pero hace falta volver a verificar identidad para Mi Empresa.
  Future<bool> mustReauthMiEmpresa() async {
    if (!state.isAdmin) return false;
    if (state.modoJefe) return false;
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_miEmpresaExitKey);
    if (s == null) return false;
    final exit = DateTime.parse(s);
    return DateTime.now().difference(exit) > miEmpresaReauthGrace;
  }

  /// Verifica el PIN actual y luego cambia al nuevo.
  /// Retorna null si exitoso, o un mensaje de error.
  Future<String?> changePin(String currentPin, String newPin) async {
    final storedPin = await _getPin();
    if (currentPin != storedPin) {
      return 'El PIN actual es incorrecto.';
    }
    if (newPin.length < 4) {
      return 'El PIN debe tener al menos 4 dígitos.';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, newPin);
    return null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_modoJefeKey);
    await prefs.remove(_miEmpresaExitKey);
    state = AdminAuthState.loggedOut();
  }
}

final adminAuthProvider =
    NotifierProvider<AdminAuthNotifier, AdminAuthState>(() {
  return AdminAuthNotifier();
});
