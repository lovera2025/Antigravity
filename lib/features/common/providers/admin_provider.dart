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
      final expiry = DateTime.now().add(const Duration(hours: 24));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, expiry.toIso8601String());
      state = AdminAuthState(isAdmin: true, expiresAt: expiry);
      return true;
    }
    return false;
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
    state = AdminAuthState.loggedOut();
  }
}

final adminAuthProvider = NotifierProvider<AdminAuthNotifier, AdminAuthState>(() {
  return AdminAuthNotifier();
});
