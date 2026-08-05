import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/services/sync_engine.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../mi_empresa/providers/finanzas_provider.dart';

class OperationalSyncRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final operationalSyncRevisionProvider =
    NotifierProvider<OperationalSyncRevision, int>(OperationalSyncRevision.new);

/// Sincronización corta caja ↔ jefe. Solo actúa con un rol operativo elegido.
class OperationalSyncCoordinator extends ConsumerStatefulWidget {
  final Widget child;

  const OperationalSyncCoordinator({super.key, required this.child});

  @override
  ConsumerState<OperationalSyncCoordinator> createState() =>
      _OperationalSyncCoordinatorState();
}

class _OperationalSyncCoordinatorState
    extends ConsumerState<OperationalSyncCoordinator>
    with WidgetsBindingObserver, WindowListener {
  Timer? _timer;
  bool _appResumed = true;
  bool _windowFocused = true;
  bool _running = false;
  DateTime? _ultimoAutocierre;

  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _foreground => _appResumed && (!_desktop || _windowFocused);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_desktop) windowManager.addListener(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) unawaited(_tick());
  }

  @override
  void onWindowFocus() {
    _windowFocused = true;
    unawaited(_tick());
  }

  @override
  void onWindowBlur() => _windowFocused = false;

  @override
  void onWindowMinimize() => _windowFocused = false;

  @override
  void onWindowRestore() {
    _windowFocused = true;
    unawaited(_tick());
  }

  /// Cierre de cajas que quedaron abiertas de días anteriores.
  ///
  /// Va por fuera de [_tick] a propósito: no depende del rol elegido ni de que
  /// la ventana esté en foco. Con la app cerrada no corre nada, así que ésta es
  /// la primera oportunidad de detectar el cambio de día — y cubre la PC que se
  /// suspendió y despierta al otro día antes de que corra un latido.
  ///
  /// Throttle de un minuto: se dispara en cada foco de ventana y no tiene
  /// sentido repetir la consulta a cada alt-tab.
  Future<void> _autocierreCajas() async {
    if (!mounted) return;
    final ahora = DateTime.now();
    final ultimo = _ultimoAutocierre;
    if (ultimo != null && ahora.difference(ultimo) < const Duration(minutes: 1)) {
      return;
    }
    _ultimoAutocierre = ahora;
    await ref.read(appRoleProvider.notifier).autocerrarSesionesVencidas();
  }

  Future<void> _tick() async {
    unawaited(_autocierreCajas());
    if (!mounted || !_foreground || _running) return;
    final role = ref.read(appRoleProvider);
    if (!role.esJefe && !role.esCaja) return;

    _running = true;
    try {
      final engine = ref.read(syncEngineProvider);
      // El jefe también sube solo mientras haya una caja abierta: es la misma
      // regla que ya usa CajaAutoSyncService.afterMassiveMutation para subir
      // el cobro recién registrado. Sin esto, si esa subida fallaba nadie la
      // reintentaba y el cobro quedaba parado hasta que alguien apretara
      // "Subir pendientes" o cerrara la caja. Con la caja cerrada el jefe
      // sigue subiendo a mano, como siempre.
      final puedeSubirSolo =
          role.esCaja ||
          (role.esJefe &&
              role.sesionActiva != null &&
              role.sesionActiva!.estaAbierta);

      // Se pregunta por trabajo real, no por el contador de pendientes: ese
      // cuenta también los trabados, y con un registro imposible de subir esto
      // despertaría la sincronización cada 10 segundos y el indicador viviría
      // parpadeando. Los trabados entran igual, cada 5 minutos.
      if (puedeSubirSolo && await engine.hayTrabajoDeSubida) {
        await engine.flushPending();
      }
      final changed = await engine.pullOperationalUpdates();
      if (!changed || !mounted) return;
      ref.invalidate(dashboardStatsProvider);
      ref.read(contratosMutationTickProvider.notifier).bump();
      ref.read(operationalSyncRevisionProvider.notifier).bump();
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
