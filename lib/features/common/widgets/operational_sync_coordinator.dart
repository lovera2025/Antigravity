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

  Future<void> _tick() async {
    if (!mounted || !_foreground || _running) return;
    final role = ref.read(appRoleProvider);
    if (!role.esJefe && !role.esCaja) return;

    _running = true;
    try {
      final engine = ref.read(syncEngineProvider);
      if (role.esCaja && engine.pendingCount > 0) {
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
