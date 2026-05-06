import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/providers/user_role_provider.dart';
import '../recepcion/recepcion_unified_screen.dart';
import '../eventos/eventos_screen.dart';
import '../clientes/clientes_screen.dart';
import '../catalogo/catalogo_screen.dart';
import '../cotizacion/widgets/generar_qr_dialog.dart';
import '../totem/totem_launcher_screen.dart';
import '../mi_empresa/finanzas_view.dart';
import '../cierre_caja/cierre_caja_screen.dart';
import '../rentabilidad/calculador_rentabilidad_screen.dart';
import '../../core/services/sync_engine.dart';
import '../../core/services/user_role_cache.dart';

class AsesorHomeScreen extends ConsumerStatefulWidget {
  const AsesorHomeScreen({super.key});

  @override
  ConsumerState<AsesorHomeScreen> createState() => _AsesorHomeScreenState();
}

class _AsesorHomeScreenState extends ConsumerState<AsesorHomeScreen> {
  RealtimeChannel? _presenceChannel;

  @override
  void initState() {
    super.initState();
    _setupPresence();
  }

  @override
  void dispose() {
    _removePresence();
    super.dispose();
  }

  void _setupPresence() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    _presenceChannel = Supabase.instance.client.channel('online_users');

    // Necesario para que el canal active la feature de presencia
    _presenceChannel!.onPresenceSync((payload) {
      debugPrint('📡 Presence sync en Asesor');
    });

    _presenceChannel!.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _presenceChannel!.track({
          'user_id': user.id,
          'email': user.email ?? '',
          'online_at': DateTime.now().toIso8601String(),
        });
        debugPrint('✅ Presencia activada para ${user.email}');
      }
    });
  }

  void _removePresence() {
    if (_presenceChannel != null) {
      _presenceChannel!.untrack();
      Supabase.instance.client.removeChannel(_presenceChannel!);
      _presenceChannel = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
    
    // Iniciar motor de sincronización para asegurar que la DB local tenga los eventos/datos
    ref.watch(syncEngineProvider);

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0D0B14), const Color(0xFF0A0A0A)]
                : [const Color(0xFFF8F9FA), const Color(0xFFE9ECEF)],
          ),
        ),
        child: SafeArea(
          child: roleAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: gold),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
            ),
            data: (role) => _buildContent(context, role, isDark, gold),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    UserRoleState role,
    bool isDark,
    Color gold,
  ) {
    final permisos = role.permisos;
    final nombre = role.nombre ?? 'Operador';

    // Construir lista de módulos habilitados
    final modules = <_ModuleItem>[];

    if (permisos.puedeRecepcion) {
      modules.add(_ModuleItem(
        label: 'RECEPCIÓN',
        subtitle: 'Check-in de invitados',
        icon: Icons.door_front_door_rounded,
        color: Colors.purpleAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RecepcionUnifiedScreen()),
        ),
      ));
    }

    if (permisos.puedeEventos) {
      modules.add(_ModuleItem(
        label: 'EVENTOS',
        subtitle: 'Gestionar eventos',
        icon: Icons.celebration_outlined,
        color: gold,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EventosScreen()),
        ),
      ));
    }

    if (permisos.puedeClientes) {
      modules.add(_ModuleItem(
        label: 'CLIENTES',
        subtitle: 'Base de clientes',
        icon: Icons.people_alt_outlined,
        color: Colors.blueAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ClientesScreen()),
        ),
      ));
    }

    if (permisos.puedeCatalogo) {
      modules.add(_ModuleItem(
        label: 'CATÁLOGO',
        subtitle: 'Servicios disponibles',
        icon: Icons.settings_suggest_outlined,
        color: Colors.tealAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CatalogoServiciosScreen()),
        ),
      ));
    }

    if (permisos.puedeTotem) {
      modules.add(_ModuleItem(
        label: 'TÓTEM',
        subtitle: 'Pantalla de recepción',
        icon: Icons.monitor_rounded,
        color: Colors.orangeAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TotemLauncherScreen()),
        ),
      ));
    }

    if (permisos.puedeQr) {
      modules.add(_ModuleItem(
        label: 'QR',
        subtitle: 'Código QR de catálogo',
        icon: Icons.qr_code_2_rounded,
        color: Colors.greenAccent,
        onTap: () => showDialog(
          context: context,
          builder: (_) => const GenerarQRDialog(),
        ),
      ));
    }

    if (permisos.puedeCierreCaja) {
      modules.add(_ModuleItem(
        label: 'CIERRE DE CAJA',
        subtitle: 'Turnos, retiros y exportar',
        icon: Icons.point_of_sale_outlined,
        color: gold,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CierreCajaScreen()),
        ),
      ));
    }

    if (permisos.puedeFinanzas) {
      modules.add(_ModuleItem(
        label: 'MI EMPRESA',
        subtitle: 'Finanzas y personal',
        icon: Icons.business_center_outlined,
        color: gold,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FinanzasView()),
        ),
      ));

      modules.add(_ModuleItem(
        label: 'RENTABILIDAD',
        subtitle: 'Cálculo y simulador',
        icon: Icons.analytics_outlined,
        color: Colors.greenAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CalculadorRentabilidadScreen()),
        ),
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ── Logo ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    gold.withValues(alpha: 0.5),
                    gold.withValues(alpha: 0.1),
                  ]),
                ),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF141414) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: gold.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icons/isotipo-ej.png',
                      height: 60,
                      width: 60,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.celebration_rounded,
                        size: 44,
                        color: gold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Saludo ─────────────────────────────────────────────
              Text(
                'Hola, $nombre',
                style: GoogleFonts.oswald(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PANEL DE OPERADOR',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: gold.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 36),

              // ── Módulos disponibles ────────────────────────────────
              if (modules.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          color: isDark ? Colors.white24 : Colors.black26,
                          size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Sin módulos asignados aún',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Contactá al administrador para que te habilite funciones.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...modules.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildModuleCard(context, m, isDark, gold),
                    )),

              const SizedBox(height: 32),

              // ── Cerrar sesión ──────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    _removePresence();
                    await UserRoleCache.signOut(Supabase.instance.client);
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    'CERRAR SESIÓN',
                    style: GoogleFonts.oswald(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white38 : Colors.black38,
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Footer ─────────────────────────────────────────────
              Text(
                'JUNIOR EVENTOS  ·  OPERADOR',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context,
    _ModuleItem module,
    bool isDark,
    Color gold,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: module.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: module.color.withValues(alpha: isDark ? 0.2 : 0.3),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: module.color.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: module.color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.label,
                      style: GoogleFonts.oswald(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      module.subtitle,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModuleItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
