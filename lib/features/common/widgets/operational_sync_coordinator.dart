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

/// Lo que la sincronización hace cuando alguien mira la pantalla.
///
/// Desde la 6.3.3 (el sync en reposo) **no tiene reloj**. Hasta la 6.3.2 cada
/// 10 s subía la cola y bajaba 16 tablas haya o no novedades: unas 120
/// consultas por minuto por PC, el 95 % de lo que la app le pedía a la nube.
/// Ahora lo que corre solo vive en el motor (`SyncEngine`): la subida a los
/// 2 s de guardar y sus reintentos, el aviso entre PCs y la red de seguridad
/// de 5 y 30 minutos. Acá queda:
///
/// - **al abrir**, bajar todo (con la revisión de borrados y la de la mora);
/// - **al volver a la ventana**, bajar lo del cobro si hace más de un minuto
///   que no se baja: es el momento en que alguien va a mirar;
/// - **refrescar las pantallas cuando de verdad bajó algo nuevo**
///   (`cambiosBajadosStream`), venga del aviso, de la red o de antes de cobrar,
///   y no cada 10 s por las dudas;
/// - cerrar las cajas que quedaron abiertas de días anteriores.
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
  bool _appResumed = true;
  DateTime? _ultimoAutocierre;
  StreamSubscription<Set<String>>? _cambiosBajados;

  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_desktop) windowManager.addListener(this);
    _cambiosBajados = ref
        .read(syncEngineProvider)
        .cambiosBajadosStream
        .listen((_) => _refrescarPantallas());
    WidgetsBinding.instance.addPostFrameCallback((_) => _alArrancar());
  }

  @override
  void dispose() {
    unawaited(_cambiosBajados?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    if (_desktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) unawaited(_alMirar());
  }

  @override
  void onWindowFocus() => unawaited(_alMirar());

  @override
  void onWindowRestore() => unawaited(_alMirar());

  Future<void> _alArrancar() async {
    unawaited(_autocierreCajas());
    if (!mounted) return;
    await ref.read(syncEngineProvider).bajarAlArrancar();
  }

  Future<void> _alMirar() async {
    unawaited(_autocierreCajas());
    if (!mounted || !_appResumed) return;
    await ref.read(syncEngineProvider).bajarAlMirar();
  }

  /// Bajó algo distinto de lo que había: las pantallas abiertas se rehacen.
  void _refrescarPantallas() {
    if (!mounted) return;
    ref.invalidate(dashboardStatsProvider);
    ref.read(contratosMutationTickProvider.notifier).bump();
    ref.read(operationalSyncRevisionProvider.notifier).bump();
  }

  /// Cierre de cajas que quedaron abiertas de días anteriores.
  ///
  /// No depende del rol elegido. Con la app cerrada no corre nada, así que al
  /// abrir es la primera oportunidad de detectar el cambio de día — y cubre la
  /// PC que se suspendió y despierta al otro día antes de que corra un latido.
  /// Con una caja abierta, además, corre en cada latido.
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

  @override
  Widget build(BuildContext context) => widget.child;
}
