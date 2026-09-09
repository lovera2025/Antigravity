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

/// Sincronización corta entre las PCs.
///
/// Baja siempre, en cualquier sesión abierta y también con la ventana atrás o
/// minimizada. Sube solo con un rol operativo elegido (jefe o caja).
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
  bool _running = false;
  DateTime? _ultimoAutocierre;

  /// Ciclos de pull efectivamente corridos, para la cadencia por niveles.
  ///
  /// Cuenta bajadas, no invocaciones: los ticks que salen temprano —sin foco en
  /// móvil, o con otro ciclo todavía corriendo— no suman. Y **nunca se
  /// reinicia**: si se pusiera en cero con cada vuelta a la ventana, un rato de
  /// alt-tab dejaría a las tablas de carga sin llegar nunca a su turno.
  int _ciclos = 0;

  bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// En escritorio ya no se mira el foco de la ventana.
  ///
  /// Antes, con la app atrás de otra ventana o minimizada, [_tick] salía sin
  /// hacer nada: la PC de la oficina, que pasa el día con el navegador adelante,
  /// no sincronizaba. Y no era simétrico — la máquina que más miraba la pantalla
  /// era la que más al día estaba, sin que nadie supiera por qué.
  ///
  /// En móvil el guard se queda: ahí "sin foco" significa que el sistema puede
  /// congelar el proceso en cualquier momento, que es otra cosa.
  bool get _foreground => _appResumed;

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

  // Volver a la ventana ya no habilita nada —el ciclo corre igual de fondo—,
  // pero sigue valiendo un tick inmediato: es el momento en que alguien va a
  // mirar la pantalla, y conviene que lo que vea esté al día sin esperar al
  // próximo turno del timer.

  @override
  void onWindowFocus() => unawaited(_tick());

  @override
  void onWindowRestore() => unawaited(_tick());

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

    _running = true;
    try {
      final engine = ref.read(syncEngineProvider);
      final role = ref.read(appRoleProvider);

      // Subir pide un rol operativo elegido; bajar no.
      //
      // Antes el tick entero salía si el rol era `none`, y un usuario Asesor
      // nunca elige rol —va derecho a su menú sin pasar por la pantalla de
      // roles, que es solo para Admin—. O sea que una PC de operario no
      // sincronizaba sola nunca, ni para un lado ni para el otro, y quedaba
      // mirando datos de la última vez que alguien apretó sincronizar.
      //
      // Bajar no compromete nada: escribe filas de la nube en la base local.
      final puedeSubirSolo = role.esJefe || role.esCaja;

      // Al jefe ya no se le pide caja abierta.
      //
      // Entrar como jefe no abre caja —se abre recién al cobrar—, así que un
      // cambio hecho antes del primer cobro del día se quedaba parado en la
      // cola sin que nadie lo reintentara. Y es justo cuando se cargan los
      // presupuestos. Subir la cola no cobra nada ni abre ninguna sesión: manda
      // lo que alguien ya guardó.
      //
      // Se pregunta por trabajo real, no por el contador de pendientes: ese
      // cuenta también los trabados, y con un registro imposible de subir esto
      // despertaría la sincronización cada 10 segundos y el indicador viviría
      // parpadeando. Los trabados entran igual, cada 5 minutos.
      if (puedeSubirSolo && await engine.hayTrabajoDeSubida) {
        await engine.flushPending();
      }
      // El primer ciclo baja todo (0 % 6 == 0): al abrir la app conviene la
      // foto completa, no solo lo del cobro.
      final incluirTablasDeCarga =
          _ciclos % SyncEngine.ciclosEntrePullsLentos == 0;
      _ciclos++;

      final changed = await engine.pullOperationalUpdates(
        incluirTablasDeCarga: incluirTablasDeCarga,
      );
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
