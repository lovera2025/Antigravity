import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminAuthState {
  final bool isAdmin;
  final DateTime? expiresAt;

  AdminAuthState({required this.isAdmin, this.expiresAt});

  factory AdminAuthState.loggedOut() => AdminAuthState(isAdmin: false);
}

class AdminAuthNotifier extends Notifier<AdminAuthState> {
  static const String _prefKey = 'admin_session_expiry';
  static const String _pinKey = 'admin_pin';
  static const String _defaultPin = '2026';
  static const String _miEmpresaExitKey = 'mi_empresa_last_exit';

  /// Tras validar PIN MAESTRO, cuánto dura el flag `isAdmin` persistido (alineado con sesión privilegiada).
  static const Duration sessionTtl = Duration(minutes: 3);

  /// Si salís de Mi Empresa y volvés pasado este tiempo, se pide PIN de nuevo (grace para reentradas rápidas).
  static const Duration miEmpresaReauthGrace = Duration(minutes: 3);

  @override
  AdminAuthState build() {
    _loadSession();
    return AdminAuthState.loggedOut();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
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
      final expiry = DateTime.now().add(sessionTtl);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, expiry.toIso8601String());
      await prefs.remove(_miEmpresaExitKey);
      state = AdminAuthState(isAdmin: true, expiresAt: expiry);
      return true;
    }
    return false;
  }

  /// Llamar al salir de [FinanzasView] (Mi Empresa) para marcar que hubo una salida.
  Future<void> recordMiEmpresaExit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_miEmpresaExitKey, DateTime.now().toIso8601String());
  }

  /// Sesión admin activa pero hace falta volver a verificar identidad para Mi Empresa (salida > grace).
  Future<bool> mustReauthMiEmpresa() async {
    if (!state.isAdmin) return false;
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
    return null; // éxito
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_miEmpresaExitKey);
    state = AdminAuthState.loggedOut();
  }
}

final adminAuthProvider = NotifierProvider<AdminAuthNotifier, AdminAuthState>(() {
  return AdminAuthNotifier();
});
