import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../dashboard/providers/dashboard_provider.dart';

/// Indicador de sync local-first con menú: subir / verificar / bajar.
class SyncCloudIndicator extends ConsumerWidget {
  const SyncCloudIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityStatusProvider);
    final uploadCount = ref.watch(syncPendingCountProvider).when(
          data: (c) => c,
          loading: () => 0,
          error: (_, _) => 0,
        );
    final probe = ref.watch(remoteProbeProvider).when(
          data: (p) => p,
          loading: () => const RemoteProbeInfo(),
          error: (_, _) => const RemoteProbeInfo(),
        );
    final syncStatus = ref.watch(syncStatusProvider).when(
          data: (s) => s,
          loading: () => SyncStatus.idle,
          error: (_, _) => SyncStatus.idle,
        );

    final isBusy = syncStatus == SyncStatus.syncing ||
        syncStatus == SyncStatus.wakingUp ||
        syncStatus == SyncStatus.probing;

    final downloadCount =
        probe.probeSucceeded ? probe.remoteChangeCount : 0;

    Color cloudColor;
    IconData cloudIcon;
    switch (connectivity) {
      case AppConnectivity.online:
        cloudColor = Colors.greenAccent;
        cloudIcon = Icons.cloud_outlined;
        break;
      case AppConnectivity.cloudUnavailable:
        cloudColor = Colors.orangeAccent;
        cloudIcon = Icons.cloud_off_outlined;
        break;
      case AppConnectivity.offline:
        cloudColor = Colors.redAccent;
        cloudIcon = Icons.wifi_off_rounded;
        break;
    }
    if (isBusy) cloudColor = Colors.blueAccent;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: isBusy
            ? null
            : () => _openMenu(context, ref, uploadCount, probe, connectivity),
        child: Tooltip(
          message: _tooltip(
            connectivity,
            uploadCount,
            probe,
            isBusy,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _AnimatedSyncCloud(
                icon: cloudIcon,
                color: cloudColor,
                isSyncing: isBusy,
              ),
              if (uploadCount > 0 && !isBusy)
                _badge(
                  uploadCount > 99 ? '99+' : '$uploadCount',
                  Colors.orangeAccent,
                  alignment: Alignment.topRight,
                  icon: Icons.arrow_upward,
                ),
              if (downloadCount > 0 && !isBusy)
                _badge(
                  downloadCount > 99 ? '99+' : '$downloadCount',
                  Colors.lightBlueAccent,
                  alignment: Alignment.topLeft,
                  icon: Icons.arrow_downward,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _tooltip(
    AppConnectivity connectivity,
    int uploadCount,
    RemoteProbeInfo probe,
    bool isBusy,
  ) {
    if (isBusy) return 'Sincronizando…';
    final parts = <String>[];
    switch (connectivity) {
      case AppConnectivity.online:
        parts.add('Modo local — nube manual');
        break;
      case AppConnectivity.cloudUnavailable:
        parts.add('Nube no disponible');
        break;
      case AppConnectivity.offline:
        parts.add('Sin conexión');
        break;
    }
    if (uploadCount > 0) {
      parts.add('$uploadCount por subir');
    }
    if (probe.probeSucceeded && probe.remoteChangeCount > 0) {
      parts.add('${probe.remoteChangeCount} para bajar');
    } else if (probe.probeSucceeded) {
      parts.add('Nube al día');
    } else if (probe.probeError != null) {
      parts.add('Sin verificar remoto');
    }
    return parts.join(' · ');
  }

  Widget _badge(
    String text,
    Color color, {
    required Alignment alignment,
    required IconData icon,
  }) {
    return Positioned(
      top: -4,
      left: alignment == Alignment.topLeft ? -6 : null,
      right: alignment == Alignment.topRight ? -6 : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 7, color: Colors.black),
            const SizedBox(width: 1),
            Text(
              text,
              style: const TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    int uploadCount,
    RemoteProbeInfo probe,
    AppConnectivity connectivity,
  ) async {
    final engine = ref.read(syncEngineProvider);
    final isOffline = connectivity == AppConnectivity.offline;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.88;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Datos locales y nube',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Operás con lo que está en este dispositivo (Mis Documentos/JuniorEventos). '
                    'La nube es respaldo e intercambio entre equipos.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _statRow(
                    Icons.storage_rounded,
                    'Por subir a la nube',
                    uploadCount > 0 ? '$uploadCount cambios locales' : 'Nada pendiente',
                    Colors.orangeAccent,
                  ),
                  const SizedBox(height: 8),
                  _statRow(
                    Icons.cloud_download_outlined,
                    'Para bajar de la nube',
                    probe.probeSucceeded
                        ? (probe.remoteChangeCount > 0
                            ? '${probe.remoteChangeCount} cambios remotos'
                            : 'Al día (verificado)')
                        : (probe.probeError ?? 'Sin verificar — tocá Verificar'),
                    Colors.lightBlueAccent,
                  ),
                  if (probe.lastProbeAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Última verificación: ${_formatTime(probe.lastProbeAt!)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (isOffline)
                    Text(
                      'Sin conexión: podés seguir operando en local. Subir/bajar cuando vuelva internet.',
                      style: TextStyle(
                        color: Colors.redAccent.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  if (!isOffline) ...[
                    _actionTile(
                      ctx,
                      icon: Icons.arrow_upward_rounded,
                      label: 'Subir pendientes',
                      subtitle: uploadCount > 0
                          ? '$uploadCount cambios locales → nube'
                          : 'No hay nada para subir',
                      enabled: uploadCount > 0,
                      onTap: () => _run(ctx, ref, () => engine.flushPending()),
                    ),
                    _actionTile(
                      ctx,
                      icon: Icons.search_rounded,
                      label: 'Verificar nube',
                      subtitle: 'Consulta cuánto hay para bajar (no descarga)',
                      enabled: true,
                      onTap: () => _run(ctx, ref, () => engine.probeRemoteChanges()),
                    ),
                    _actionTile(
                      ctx,
                      icon: Icons.arrow_downward_rounded,
                      label: 'Bajar cambios',
                      subtitle: probe.remoteChangeCount > 0
                          ? 'Traer ${probe.remoteChangeCount} cambios a este dispositivo'
                          : 'Verificá primero o bajá igual por si acaso',
                      enabled: true,
                      onTap: () => _run(ctx, ref, () => engine.pullRemote()),
                    ),
                    _actionTile(
                      ctx,
                      icon: Icons.sync_rounded,
                      label: 'Subir y bajar',
                      subtitle: 'Sube pendientes y luego baja cambios remotos',
                      enabled: uploadCount > 0 || probe.remoteChangeCount > 0,
                      onTap: () => _run(ctx, ref, () => engine.syncBidirectional()),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(IconData icon, String title, String value, Color accent) {
    return Row(
      children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool enabled,
    required Future<void> Function() onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      enabled: enabled,
      leading: Icon(icon, color: enabled ? const Color(0xFFD4AF37) : Colors.white24),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
      ),
      onTap: enabled
          ? () {
              Navigator.pop(context);
              onTap();
            }
          : null,
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final engine = ref.read(syncEngineProvider);
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Procesando…'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    await action();
    if (!context.mounted) return;

    messenger.hideCurrentSnackBar();
    ref.invalidate(syncPendingCountProvider);
    ref.invalidate(remoteProbeProvider);
    ref.invalidate(dashboardStatsProvider);

    final upload = engine.pendingCount;
    final remote = engine.remoteProbe;
    final err = engine.lastError;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          err != null
              ? 'Error: $err'
              : 'Listo · $upload por subir · ${remote.probeSucceeded ? remote.remoteChangeCount : "?"} para bajar',
        ),
        backgroundColor: err != null ? Colors.redAccent : Colors.green.withValues(alpha: 0.85),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AnimatedSyncCloud extends StatefulWidget {
  final IconData icon;
  final Color color;
  final bool isSyncing;

  const _AnimatedSyncCloud({
    required this.icon,
    required this.color,
    required this.isSyncing,
  });

  @override
  State<_AnimatedSyncCloud> createState() => _AnimatedSyncCloudState();
}

class _AnimatedSyncCloudState extends State<_AnimatedSyncCloud>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isSyncing) _controller.repeat();
  }

  @override
  void didUpdateWidget(_AnimatedSyncCloud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isSyncing && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: widget.isSyncing ? _controller : const AlwaysStoppedAnimation(0),
      child: Icon(widget.icon, color: widget.color, size: 22),
    );
  }
}
