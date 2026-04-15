import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Estado de conectividad de la app.
enum AppConnectivity {
  /// Conexión a internet + Supabase confirmada
  online,
  /// Sin conexión a internet
  offline,
  /// Internet disponible pero Supabase no responde (cold start, caída)
  cloudUnavailable,
}

/// Servicio de monitoreo de conectividad con verificación real a Supabase.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  final _controller = StreamController<AppConnectivity>.broadcast();

  AppConnectivity _currentStatus = AppConnectivity.online;
  AppConnectivity get currentStatus => _currentStatus;

  Stream<AppConnectivity> get stream => _controller.stream;

  /// Inicia el monitoreo de red.
  void startMonitoring() {
    _sub = _connectivity.onConnectivityChanged.listen((results) async {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      if (!hasNetwork) {
        _updateStatus(AppConnectivity.offline);
        return;
      }

      // Tenemos red — verificar que Supabase responda
      final supabaseOk = await _pingSupabase();
      _updateStatus(supabaseOk ? AppConnectivity.online : AppConnectivity.cloudUnavailable);
    });

    // Check inicial
    _checkNow();
  }

  Future<void> _checkNow() async {
    final results = await _connectivity.checkConnectivity();
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);

    if (!hasNetwork) {
      _updateStatus(AppConnectivity.offline);
      return;
    }

    final supabaseOk = await _pingSupabase();
    _updateStatus(supabaseOk ? AppConnectivity.online : AppConnectivity.cloudUnavailable);
  }

  /// Ping ligero a Supabase para verificar disponibilidad real.
  /// Sirve también como wake-up para contenedores en cold start.
  Future<bool> _pingSupabase() async {
    try {
      await Supabase.instance.client
          .from('servicios')
          .select('id')
          .limit(1);
      return true;
    } catch (e) {
      debugPrint('⚡ Supabase ping fallido: $e');
      return false;
    }
  }

  /// Ping público para wake-up explícito antes de sincronizar.
  Future<bool> wakeUpCloud() async {
    debugPrint('🔔 Wake-up ping a Supabase...');
    return _pingSupabase();
  }

  /// Fuerza una re-verificación del estado de conectividad.
  Future<AppConnectivity> recheckNow() async {
    await _checkNow();
    return _currentStatus;
  }

  void _updateStatus(AppConnectivity newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      _controller.add(newStatus);
      debugPrint('🌐 Connectivity: ${newStatus.name}');
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

/// Servicio singleton de conectividad.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.startMonitoring();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream reactivo del estado de conectividad.
final connectivityStreamProvider = StreamProvider<AppConnectivity>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.stream;
});

/// Estado actual de conectividad (snapshot).
final connectivityStatusProvider = Provider<AppConnectivity>((ref) {
  final asyncConn = ref.watch(connectivityStreamProvider);
  return asyncConn.when(
    data: (status) => status,
    loading: () => AppConnectivity.online,
    error: (_, _) => AppConnectivity.offline,
  );
});
