import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../main.dart';
import '../../models/evento.dart';
import '../eventos/eventos_screen.dart';
import '../clientes/clientes_screen.dart';
import '../catalogo/catalogo_screen.dart';
import '../cotizacion/solicitudes_cotizacion_screen.dart';
import '../cotizacion/widgets/generar_qr_dialog.dart';
import '../eventos/presupuestos_screen.dart';
import '../mi_empresa/finanzas_view.dart';
import '../alquiler/prestamos_alquiler_list_screen.dart';
import '../cierre_caja/cierre_caja_screen.dart';
import '../common/providers/user_role_provider.dart';
import '../recepcion/recepcion_unified_screen.dart';
import '../common/widgets/animated_background.dart';
import '../common/widgets/operational_sync_coordinator.dart';
import 'providers/dashboard_provider.dart';
import '../mi_empresa/providers/finanzas_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/services/kiosk_launcher.dart';
import '../../core/services/user_role_cache.dart';
import '../../core/services/app_update_checker.dart';
import 'widgets/app_update_download_dialog.dart';
import 'widgets/app_update_whats_new_dialog.dart';
import '../recepcion/providers/recepcion_provider.dart';
import '../common/widgets/admin_gate.dart';
import '../common/providers/admin_provider.dart';
import '../caja_sesiones/providers/app_role_provider.dart';
import '../caja_sesiones/widgets/cerrar_caja_dialog.dart';
import '../caja_sesiones/widgets/operadores_caja_screen.dart';
import '../caja_sesiones/widgets/sesion_caja_status_chip.dart';
import 'dart:async';
import 'dart:ui';
import '../common/widgets/sync_menu_sheet.dart';
import '../common/widgets/animated_brand_logo.dart';

Future<void> mostrarDialogoActualizacion(
  BuildContext context,
  AppUpdateInfo info,
) async {
  final quiereDescargar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppUpdateWhatsNewDialog(
      version: info.latestVersion,
      notes: info.notes,
      showLater: true,
    ),
  );
  if (quiereDescargar != true || !context.mounted) return;
  await AppUpdateChecker.markWhatsNewSeen(info.latestVersion);
  if (!context.mounted) return;
  final result = await showDialog<AppUpdateDownloadResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AppUpdateDownloadDialog(info: info),
  );
  if (!context.mounted) return;
  if (result == AppUpdateDownloadResult.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Se abrió el instalador. Seguí los pasos; puede pedir cerrar Junior Eventos.',
        ),
      ),
    );
  }
}

/// Primera apertura de una versión que todavía no se acusó. Sin MÁS TARDE.
Future<void> mostrarNovedadesSiPrimeraApertura(
  BuildContext context,
  AppUpdateChecker checker,
) async {
  final current = await checker.currentVersion();
  final seen = await AppUpdateChecker.whatsNewSeenVersion();
  if (!context.mounted) return;
  if (seen == current) return;
  final info = await checker.consultar();
  if (!context.mounted) return;
  if (info != null && info.hayNueva) return;
  final notes = (info != null && info.latestVersion == current)
      ? info.notes
      : 'Junior Eventos $current está lista.';
  final accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AppUpdateWhatsNewDialog(
      version: current,
      notes: notes,
      alreadyInstalled: true,
    ),
  );
  if (accepted == true) {
    await AppUpdateChecker.markWhatsNewSeen(current);
  }
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late String _greeting;
  String _appVersionLabel = '3.5.1';
  String _appBuildNumber = '';
  late SupabaseClient _supabase;
  int _pendingRequestsCount = 0;
  bool _isLaunchingPortal = false; // Estado para el efecto Portal
  Timer? _statsRefreshDebounce;

  final List<String> _greetingOptions = [
    '¡Bienvenido, Titán!',
    '¡Al mando, Comandante!',
    'Arquitecto de Sueños, adelante.',
    'Dominando el mercado, Jefe.',
    'El éxito te espera, Junior.',
    'Gestión de Élite lista.',
    'Haciendo que las cosas pasen.',
  ];

  static const _diasSemana = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _supabase = ref.read(supabaseProvider);
    _greeting = (List.from(_greetingOptions)..shuffle()).first;
    _fetchPendingRequestsCount();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersionLabel = info.version;
          _appBuildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      /* mantiene fallback */
    }
    if (mounted) unawaited(_chequearUpdateSilencioso());
  }

  Future<void> _chequearUpdateSilencioso() async {
    if (!AppUpdateChecker.habilitado) return;
    final checker = AppUpdateChecker();
    final info = await checker.consultarSiCorrespondeHoy();
    if (!mounted) return;
    if (info != null) {
      await mostrarDialogoActualizacion(context, info);
      return;
    }
    await mostrarNovedadesSiPrimeraApertura(context, checker);
  }

  /// Muestra p. ej. 4.5.0 →4.5; 4.5.1 → 4.5.1 (marketing en pie del dashboard).
  static String _versionMarketingLabel(String raw) {
    final v = raw.split('+').first.trim();
    final parts = v.split('.');
    if (parts.length == 3 && parts[2] == '0') {
      return '${parts[0]}.${parts[1]}';
    }
    return v;
  }

  @override
  void dispose() {
    _statsRefreshDebounce?.cancel();
    super.dispose();
  }

  void _scheduleDashboardStatsRefresh() {
    _statsRefreshDebounce?.cancel();
    _statsRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.refresh(dashboardStatsProvider);
    });
  }

  Future<void> _fetchPendingRequestsCount() async {
    try {
      final response = await _supabase
          .from('solicitudes_cotizacion')
          .select('id')
          .eq('estado', 'pendiente');
      final List data = response as List;
      if (!mounted) return;
      setState(() => _pendingRequestsCount = data.length);
    } catch (e) {
      debugPrint('Error al contar solicitudes: $e');
    }
  }

  // El canal `solicitudes_changes` se retiró el 2026-09-02: mantenerlo abierto
  // hacía que Realtime consultara el WAL cada 100 ms. `solicitudes_cotizacion`
  // ahora baja en el pull incremental, y el contador se recuenta desde el
  // listen de `operationalSyncRevisionProvider` en build().

  Future<void> _signOut() async => UserRoleCache.signOut(_supabase);

  String get _fechaHoy {
    final now = DateTime.now();
    final dia = _diasSemana[now.weekday - 1];
    final mes = _meses[now.month - 1];
    return '$dia ${now.day} de $mes';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(contratosMutationTickProvider, (prev, next) {
      if (prev != null && prev != next && mounted) {
        _scheduleDashboardStatsRefresh();
      }
    });

    // Reemplaza al canal `solicitudes_changes`: el pull incremental baja
    // `solicitudes_cotizacion` y acá se recuenta lo pendiente.
    ref.listen<int>(operationalSyncRevisionProvider, (prev, next) {
      if (prev != next && mounted) _fetchPendingRequestsCount();
    });

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryGold = Color(0xFFD4AF37);
    final statsAsync = ref.watch(dashboardStatsProvider);
    final appRole = ref.watch(appRoleProvider);
    final modoJefe = appRole.esJefe || ref.watch(adminAuthProvider).esModoJefe;
    final modoCaja = appRole.esCaja;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnimatedBrandLogo(height: 28),
            const SizedBox(width: 10),
            const Text(
              'JUNIOR EVENTOS',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            if (modoJefe) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: primaryGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: primaryGold.withValues(alpha: 0.45),
                  ),
                ),
                child: const Text(
                  'MODO JEFE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ),
            ] else if (modoCaja) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  'CAJA · ${(appRole.operador?.nombre ?? '').toUpperCase()}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: isDark ? Colors.tealAccent : Colors.teal.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        actions: [
          if (modoJefe)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CierreCajaScreen()),
                  ),
                  child: const SesionCajaStatusChip(),
                ),
              ),
            ),
          // ── Indicador offline/sync ─────────────────────────────
          if (!kIsWeb) const SyncCloudIndicator(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.refresh(dashboardStatsProvider),
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: primaryGold,
              size: 20,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
            tooltip: 'Cambiar tema',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            onPressed: _signOut,
            tooltip: 'Cerrar Sesión',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _buildEliteDrawer(context, modoJefe: modoJefe),
      body: Stack(
        children: [
          AnimatedBackground(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final hPad = w > 900
                      ? 40.0
                      : w > 600
                      ? 24.0
                      : 16.0;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 32),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header slim ──────────────────────────────────────
                          _buildSlimHeader(isDark, primaryGold),
                          const SizedBox(height: 20),

                          // ── Notificación QR pendiente (solo modo jefe) ────────
                          if (modoJefe && _pendingRequestsCount > 0) ...[
                            _buildQrAlert(primaryGold),
                            const SizedBox(height: 16),
                          ],

                          // ── KPI Cards ─────────────────────────────────────────
                          statsAsync.when(
                            skipLoadingOnReload: true,
                            data: (stats) => _buildKpiRow(
                              stats,
                              isDark,
                              primaryGold,
                              modoJefe: modoJefe,
                            ),
                            loading: () => const SizedBox(
                              height: 90,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFD4AF37),
                                ),
                              ),
                            ),
                            error: (e, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 20),

                          // ── Próximos Eventos ──────────────────────────────────
                          statsAsync.when(
                            skipLoadingOnReload: true,
                            data: (stats) => _buildProximosEventos(
                              stats,
                              isDark,
                              primaryGold,
                              soloMasivos: !modoJefe || modoCaja,
                            ),
                            loading: () => const SizedBox.shrink(),
                            error: (e, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 20),

                          if (modoJefe)
                            statsAsync.when(
                              skipLoadingOnReload: true,
                              data: (stats) {
                                final operationalAlerts = stats.alertas
                                    .where((a) => !a.isFinanciera)
                                    .toList();
                                return operationalAlerts.isNotEmpty
                                    ? _buildAlertas(operationalAlerts, isDark)
                                    : _buildTodoOk(isDark, primaryGold);
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (e, _) => const SizedBox.shrink(),
                            )
                          else
                            _buildTodoOk(isDark, primaryGold),
                          const SizedBox(height: 20),

                          // ── Centro de Comando (solo modo jefe) ────────────────
                          if (modoJefe) ...[
                            _buildSectionLabel(
                              'CENTRO DE COMANDO',
                              Icons.bolt_outlined,
                            ),
                            const SizedBox(height: 12),
                            _buildCommandCenter(isDark, primaryGold),
                            const SizedBox(height: 40),
                          ] else
                            const SizedBox(height: 40),

                          // ── Footer ────────────────────────────────────────────
                          _buildFooter(isDark, primaryGold),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_isLaunchingPortal) _buildPortalOverlay(primaryGold),
        ],
      ),
    );
  }

  // ── Header slim ────────────────────────────────────────────────────────────
  Widget _buildSlimHeader(bool isDark, Color gold) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(
            color: gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting.toUpperCase(),
                style: GoogleFonts.oswald(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _fechaHoy,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white54 : Colors.black45,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── QR Alert banner ────────────────────────────────────────────────────────
  Widget _buildQrAlert(Color gold) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.qr_code_scanner_rounded, color: gold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tenés $_pendingRequestsCount solicitud(es) de servicios vía QR pendientes.',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () async {
              final remaining = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                  builder: (_) => const SolicitudesCotizacionScreen(),
                ),
              );
              if (mounted && remaining != null) {
                setState(() => _pendingRequestsCount = remaining);
              } else {
                _fetchPendingRequestsCount();
              }
              ref.invalidate(dashboardStatsProvider);
            },
            style: TextButton.styleFrom(
              foregroundColor: gold,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'REVISAR',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── KPI Row (solo operativos) ──────────────────────────────────────────────
  Widget _buildKpiRow(
    DashboardStats stats,
    bool isDark,
    Color gold, {
    required bool modoJefe,
  }) {
    return Row(
      children: [
        _buildKpiCard(
          title: 'EVENTOS MASIVOS',
          value: '${stats.eventosMasivosActivos}',
          icon: Icons.groups_2_outlined,
          color: gold,
          isDark: isDark,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EventosScreen(modalidad: 'masivo'),
            ),
          ),
        ),
        if (modoJefe) ...[
          const SizedBox(width: 10),
          _buildKpiCard(
            title: 'EVENTOS PARTICULARES',
            value: '${stats.eventosParticularesActivos}',
            icon: Icons.person_outline,
            color: gold,
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EventosScreen(modalidad: 'particular'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    Widget? detailBottom,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (detailBottom != null) ...[
                      const SizedBox(height: 4),
                      detailBottom,
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: Colors.grey.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Próximos eventos ───────────────────────────────────────────────────────
  Widget _buildProximosEventos(
    DashboardStats stats,
    bool isDark,
    Color gold, {
    bool soloMasivos = false,
  }) {
    final eventos = soloMasivos
        ? stats.proximosEventos
              .where((ev) => (ev['modalidad'] as String?) == 'masivo')
              .toList()
        : stats.proximosEventos;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('PRÓXIMOS EVENTOS', Icons.event_rounded),
          const SizedBox(height: 14),
          if (eventos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                soloMasivos
                    ? 'No hay eventos masivos próximos agendados.'
                    : 'No hay eventos próximos agendados.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            )
          else
            ...eventos.map((ev) {
              final fecha = DateTime.tryParse(ev['fecha_evento'] ?? '');
              final diff = fecha != null
                  ? fecha.difference(DateTime.now()).inDays
                  : 0;
              final cliente = ev['clientes']?['nombre_completo'] ?? 'Cliente';
              final tipo = Evento.formatearTipo(ev['tipo'] as String?);
              final urgente = diff <= 7;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (urgente ? Colors.orangeAccent : gold)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.celebration_outlined,
                        size: 16,
                        color: urgente ? Colors.orangeAccent : gold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cliente,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            tipo,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (urgente ? Colors.orangeAccent : gold)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        diff == 0 ? 'HOY' : 'en $diff d.',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: urgente ? Colors.orangeAccent : gold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Alertas como chips ─────────────────────────────────────────────────────
  Widget _buildAlertas(List<Alerta> alertas, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ALERTAS', Icons.auto_awesome_outlined),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: alertas.map((a) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: isDark ? 0.1 : 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: a.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.icono, color: a.color, size: 14),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      a.mensaje,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: a.color,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTodoOk(bool isDark, Color gold) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.greenAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            '¡TODO BAJO CONTROL! NO HAY ALERTAS CRÍTICAS HOY.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Centro de Comando ──────────────────────────────────────────────────────
  Widget _buildCommandCenter(bool isDark, Color gold) {
    final actions = [
      _CommandAction(
        label: 'NUEVO EVENTO',
        icon: Icons.add_circle_outline_rounded,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventosScreen()),
        ),
      ),
      _CommandAction(
        label: 'CLIENTES',
        icon: Icons.people_alt_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClientesScreen()),
        ),
      ),
      _CommandAction(
        label: 'RECEPCIÓN',
        icon: Icons.door_front_door_rounded,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecepcionUnifiedScreen()),
        ),
      ),
      _CommandAction(
        label: 'CATÁLOGO',
        icon: Icons.settings_suggest_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CatalogoServiciosScreen()),
        ),
      ),
      _CommandAction(
        label: 'QR',
        icon: Icons.qr_code_2_rounded,
        badge: _pendingRequestsCount > 0 ? '$_pendingRequestsCount' : null,
        onTap: () => showDialog(
          context: context,
          builder: (_) => const GenerarQRDialog(),
        ),
        onLongPress: () async {
          final remaining = await Navigator.push<int>(
            context,
            MaterialPageRoute(
              builder: (_) => const SolicitudesCotizacionScreen(),
            ),
          );
          if (mounted && remaining != null) {
            setState(() => _pendingRequestsCount = remaining);
          }
        },
      ),
      _CommandAction(
        label: 'TÓTEM',
        icon: Icons.monitor_rounded,
        onTap: () {
          final selectedId = ref.read(selectedEventProvider);
          if (selectedId != null) {
            _triggerPortal(selectedId);
          } else {
            ref.read(eventosActivosProvider).whenData((eventos) {
              if (eventos.isNotEmpty) {
                _triggerPortal(eventos.first.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No hay eventos activos para el tótem'),
                  ),
                );
              }
            });
          }
        },
      ),
    ];

    final double screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = screenWidth > 900
        ? 6
        : (screenWidth > 600 ? 4 : 3);
    final double spacing = screenWidth > 900 ? 16 : 10;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: 0.85,
      children: actions.map((a) {
        return GestureDetector(
          onLongPress: a.onLongPress,
          child: InkWell(
            onTap: a.onTap,
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Glassmorphic Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: gold.withValues(alpha: isDark ? 0.15 : 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Icon Container with Premium Gradient
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  gold.withValues(alpha: 0.25),
                                  gold.withValues(alpha: 0.08),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: gold.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            child: Icon(a.icon, color: gold, size: 26),
                          ),
                          const SizedBox(height: 12),
                          // Refined Text
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              a.label,
                              style: GoogleFonts.oswald(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Premium Badge
                if (a.badge != null)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        a.badge!,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _triggerPortal(String eventoId) {
    setState(() => _isLaunchingPortal = true);
    KioskLauncher.launch(eventoId);

    // Desactivar portal después de un tiempo para que el Dashboard vuelva a ser usable
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _isLaunchingPortal = false);
    });
  }

  Widget _buildPortalOverlay(Color gold) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 1500),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.scale(
                        scale: 0.8 + (0.4 * value),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: gold.withValues(alpha: 0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: gold.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: gold,
                      size: 60,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'INICIANDO PORTAL...',
                  style: GoogleFonts.oswald(
                    fontSize: 18,
                    color: gold,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sincronizando experiencia de élite',
                  style: TextStyle(
                    fontSize: 12,
                    color: gold.withValues(alpha: 0.5),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFD4AF37)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter(bool isDark, Color gold) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.verified_rounded, color: gold, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'JUNIOR EVENTOS  ·  v${_versionMarketingLabel(_appVersionLabel)}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ),
          Text(
            'DESARROLLADO POR LM · ${now.year}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
        ],
      ),
    );
  }

  void _abrirCierreCaja(BuildContext context) {
    final roleAsync = ref.read(userRoleProvider);
    final role = roleAsync.asData?.value;
    final puede =
        role?.isAdmin == true || role?.permisos.puedeCierreCaja == true;
    if (!puede) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tenés permiso para Cierre de Caja.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CierreCajaScreen()),
    );
  }

  /// Iniciar/cerrar la caja de modo jefe desde el header del menú.
  Future<void> _toggleCajaJefe(BuildContext context) async {
    if (ref.read(appRoleProvider).sesionActiva == null) {
      try {
        await ref.read(appRoleProvider.notifier).iniciarCajaJefe();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Caja de jefe iniciada: lista para cobrar.'),
            backgroundColor: Color(0xFF00B894),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar la caja: $e')),
        );
      }
    } else {
      await showCerrarCajaDialog(context);
    }
  }

  // ── Drawer ─────────────────────────────────────────────────────────────────
  Widget _buildEliteDrawer(BuildContext context, {required bool modoJefe}) {
    final primaryGold = const Color(0xFFD4AF37);

    final actions = <VoidCallback>[];
    final destinations = <Widget>[];

    void addDest({required Widget destination, required VoidCallback onTap}) {
      destinations.add(destination);
      actions.add(onTap);
    }

    if (modoJefe) {
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.event_available_outlined),
          selectedIcon: Icon(Icons.event_available, color: Color(0xFFD4AF37)),
          label: Text('EVENTOS PARTICULARES'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EventosScreen(modalidad: 'particular'),
          ),
        ),
      );
    }

    addDest(
      destination: const NavigationDrawerDestination(
        icon: Icon(Icons.groups_2_outlined),
        selectedIcon: Icon(Icons.groups_2, color: Color(0xFFD4AF37)),
        label: Text('EVENTOS MASIVOS'),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const EventosScreen(modalidad: 'masivo'),
        ),
      ),
    );

    if (modoJefe) {
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.sticky_note_2_outlined),
          selectedIcon: Icon(Icons.sticky_note_2, color: Color(0xFFD4AF37)),
          label: Text('PRESUPUESTOS'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PresupuestosScreen()),
        ),
      );
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people, color: Color(0xFFD4AF37)),
          label: Text('CLIENTES'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClientesScreen()),
        ),
      );
      destinations.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 28, 16),
          child: Divider(color: Colors.white10),
        ),
      );
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.settings_suggest_outlined),
          selectedIcon: Icon(Icons.settings_suggest, color: Color(0xFFD4AF37)),
          label: Text('CATÁLOGO'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CatalogoServiciosScreen()),
        ),
      );
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(
            Icons.inventory_2_rounded,
            color: Color(0xFFD4AF37),
          ),
          label: Text('ALQUILER DE ÍTEMS'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PrestamosAlquilerListScreen(),
          ),
        ),
      );
    }

    addDest(
      destination: const NavigationDrawerDestination(
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(
          Icons.point_of_sale_rounded,
          color: Color(0xFFD4AF37),
        ),
        label: Text('CIERRE DE CAJA'),
      ),
      onTap: () => _abrirCierreCaja(context),
    );

    if (modoJefe) {
      destinations.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 28, 8),
          child: Divider(color: Colors.white10),
        ),
      );
      addDest(
        destination: NavigationDrawerDestination(
          icon: Icon(
            Icons.business_center_outlined,
            color: primaryGold.withValues(alpha: 0.8),
          ),
          selectedIcon: const Icon(
            Icons.business_center_rounded,
            color: Color(0xFFD4AF37),
          ),
          label: Row(
            children: [
              const Text(
                'MI EMPRESA',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PRIVADO',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: primaryGold,
                  ),
                ),
              ),
            ],
          ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FinanzasView()),
        ),
      );
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings, color: Color(0xFFD4AF37)),
          label: Text('CONFIGURACIÓN'),
        ),
        onTap: () => _showConfiguracionDialog(context),
      );
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.badge_outlined),
          selectedIcon: Icon(Icons.badge, color: Color(0xFFD4AF37)),
          label: Text('OPERADORES DE CAJA'),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OperadoresCajaScreen()),
        ),
      );
    }

    if (!modoJefe) {
      addDest(
        destination: const NavigationDrawerDestination(
          icon: Icon(Icons.lock_outlined),
          selectedIcon: Icon(Icons.lock, color: Color(0xFFD4AF37)),
          label: Text('CERRAR CAJA / SALIR'),
        ),
        onTap: () async {
          final ok = await showCerrarCajaDialog(context);
          if (ok == true && context.mounted) {
            // logout ya ocurrió en el provider al cerrar
          }
        },
      );
    }

    return NavigationDrawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      indicatorColor: primaryGold.withValues(alpha: 0.1),
      selectedIndex: -1,
      onDestinationSelected: (idx) {
        Navigator.pop(context);
        if (idx >= 0 && idx < actions.length) {
          actions[idx]();
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AnimatedBrandLogo(height: 50),
              const SizedBox(height: 24),
              const Text(
                'JUNIOR',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'EVENTOS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: primaryGold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 20),
              if (modoJefe)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Modo jefe',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: primaryGold,
                    ),
                  ),
                  subtitle: Text(
                    ref.watch(appRoleProvider).sesionActiva == null
                        ? 'Solo consulta · caja sin iniciar'
                        : 'Caja iniciada · listo para cobrar',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black45,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _toggleCajaJefe(context);
                        },
                        child: Text(
                          ref.watch(appRoleProvider).sesionActiva == null
                              ? 'Iniciar caja'
                              : 'Cerrar caja',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await ref.read(appRoleProvider.notifier).logoutApp();
                        },
                        child: const Text('Salir'),
                      ),
                    ],
                  ),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Modo caja',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    ref.watch(appRoleProvider).operador?.nombre ?? 'Operativo',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await showCerrarCajaDialog(context);
                    },
                    child: const Text('Cerrar'),
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: Divider(color: Colors.white10),
        ),
        ...destinations,
      ],
    );
  }

  void _showConfiguracionDialog(BuildContext context) {
    final isAdmin = ref.read(adminAuthProvider).isAdmin;
    if (!isAdmin) {
      AdminGate.check(context, ref).then((granted) {
        if (granted && context.mounted) _showConfiguracionDialog(context);
      });
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ConfiguracionSheet(
        supabase: _supabase,
        appVersionDisplay:
            '${_versionMarketingLabel(_appVersionLabel)}${_appBuildNumber.isNotEmpty ? ' · compilación $_appBuildNumber' : ''}',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hoja de Configuración
// ─────────────────────────────────────────────────────────────────────────────
class _ConfiguracionSheet extends ConsumerStatefulWidget {
  final SupabaseClient supabase;

  /// Texto listo para mostrar (ej. "0.1 · compilación 1")
  final String appVersionDisplay;

  const _ConfiguracionSheet({
    required this.supabase,
    required this.appVersionDisplay,
  });

  @override
  ConsumerState<_ConfiguracionSheet> createState() =>
      _ConfiguracionSheetState();
}

class _ConfiguracionSheetState extends ConsumerState<_ConfiguracionSheet> {
  final _pinActualCtrl = TextEditingController();
  final _pinNuevoCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  String? _pinError;
  String? _pinSuccess;
  bool _pinLoading = false;
  bool _buscandoUpdate = false;

  @override
  void dispose() {
    _pinActualCtrl.dispose();
    _pinNuevoCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarActualizacion() async {
    setState(() => _buscandoUpdate = true);
    try {
      final info = await AppUpdateChecker().consultar();
      if (!mounted) return;
      if (info == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo consultar GitHub. Probá más tarde.',
            ),
          ),
        );
        return;
      }
      if (!info.hayNueva) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estás al día (${info.currentVersion}).'),
          ),
        );
        return;
      }
      await mostrarDialogoActualizacion(context, info);
    } finally {
      if (mounted) setState(() => _buscandoUpdate = false);
    }
  }

  Future<void> _cambiarPin() async {
    final actual = _pinActualCtrl.text.trim();
    final nuevo = _pinNuevoCtrl.text.trim();
    final confirmar = _pinConfirmCtrl.text.trim();
    if (actual.isEmpty || nuevo.isEmpty || confirmar.isEmpty) {
      setState(() {
        _pinError = 'Completá todos los campos.';
        _pinSuccess = null;
      });
      return;
    }
    if (nuevo != confirmar) {
      setState(() {
        _pinError = 'El PIN nuevo y la confirmación no coinciden.';
        _pinSuccess = null;
      });
      return;
    }
    setState(() {
      _pinLoading = true;
      _pinError = null;
      _pinSuccess = null;
    });
    final error = await ref
        .read(adminAuthProvider.notifier)
        .changePin(actual, nuevo);
    if (mounted) {
      setState(() {
        _pinLoading = false;
        if (error != null) {
          _pinError = error;
        } else {
          _pinSuccess = '✅ PIN actualizado correctamente.';
          _pinActualCtrl.clear();
          _pinNuevoCtrl.clear();
          _pinConfirmCtrl.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'CONFIGURACIÓN',
              style: GoogleFonts.oswald(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: gold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sistema Operativo Jr. Eventos',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 28),

            // ── PIN ────────────────────────────────────────────────────────
            _sectionHeader('🔐  SEGURIDAD — PIN MAESTRO', isDark),
            const SizedBox(height: 12),
            if (_pinError != null)
              _statusMsg(_pinError!, Colors.redAccent, Icons.error_outline),
            if (_pinSuccess != null)
              _statusMsg(
                _pinSuccess!,
                Colors.greenAccent,
                Icons.check_circle_outline,
              ),
            TextField(
              controller: _pinActualCtrl,
              decoration: const InputDecoration(
                labelText: 'PIN actual',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinNuevoCtrl,
              decoration: const InputDecoration(
                labelText: 'Nuevo PIN',
                prefixIcon: Icon(Icons.key_rounded),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinConfirmCtrl,
              decoration: const InputDecoration(
                labelText: 'Confirmar nuevo PIN',
                prefixIcon: Icon(Icons.key_off_outlined),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _cambiarPin(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _pinLoading ? null : _cambiarPin,
                icon: _pinLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text(
                  'ACTUALIZAR PIN',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
            _sectionHeader('ℹ️  ACERCA DE', isDark),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Junior Eventos',
                    style: GoogleFonts.oswald(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: gold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sistema de gestión operativa para eventos.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Versión ${widget.appVersionDisplay}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  if (AppUpdateChecker.habilitado) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: _buscandoUpdate ? null : _buscarActualizacion,
                        icon: _buscandoUpdate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt_rounded, size: 18),
                        label: const Text(
                          'BUSCAR ACTUALIZACIÓN',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'LM · ${DateTime.now().year}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
      color: isDark ? Colors.white54 : Colors.black45,
    ),
  );

  Widget _statusMsg(String msg, Color color, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg, style: TextStyle(color: color, fontSize: 12.5)),
        ),
      ],
    ),
  );
}

class _CommandAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? badge;
  const _CommandAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.badge,
  });
}
