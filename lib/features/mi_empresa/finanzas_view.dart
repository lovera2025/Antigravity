import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../models/egreso.dart';
import '../../models/evento.dart';
import '../common/providers/admin_provider.dart';
import '../common/widgets/admin_gate.dart';
import '../common/utils/currency_extensions.dart';
import 'widgets/pagar_operador_dialog.dart';
import 'widgets/editar_pago_operador_dialog.dart';
import 'models/ingreso_detallado.dart';
import 'providers/finanzas_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import 'widgets/smart_purge_dialog.dart';
import '../eventos/detalle_evento_particular_screen.dart';
import '../eventos/detalle_evento_masivo_screen.dart';
import '../eventos/repositories/eventos_repository.dart';


enum SearchContext { todos, ingresos, egresos }

class FinanzasView extends ConsumerStatefulWidget {
  const FinanzasView({super.key});

  @override
  ConsumerState<FinanzasView> createState() => _FinanzasViewState();
}

class _FinanzasViewState extends ConsumerState<FinanzasView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tab OPERADORES: recepción check-in por evento
  List<Map<String, dynamic>> _eventosParaOperadores = [];
  String? _operadoresEventoId;
  final _operadoresPinCtrl = TextEditingController();
  bool _operadoresSavingPin = false;

  // Gestión de Asesores
  List<Map<String, dynamic>> _asesores = [];
  Set<String> _onlineUserIds = {};
  RealtimeChannel? _presenceChannel;

  // Filtro de búsqueda unificado (Buscador Maestro)
  final _masterSearchCtrl = TextEditingController();
  SearchContext _searchContext = SearchContext.todos;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    final isAdmin = ref.read(adminAuthProvider).isAdmin;
    if (isAdmin) {
      _fetchOperadores();
      _fetchAsesores();
      _setupPresenceListener();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _operadoresPinCtrl.dispose();
    _masterSearchCtrl.dispose();
    if (_presenceChannel != null) {
      Supabase.instance.client.removeChannel(_presenceChannel!);
    }
    super.dispose();
  }

  /// Cargar lista de Asesores desde perfiles + permisos.
  Future<void> _fetchAsesores() async {
    final supabase = ref.read(supabaseProvider);
    try {
      final res = await supabase
          .from('perfiles')
          .select('id, nombre, rol')
          .eq('rol', 'Asesor')
          .order('nombre');
      if (!mounted) return;
      setState(() {
        _asesores = (res as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      debugPrint('Error cargando asesores: $e');
    }
  }

  /// Escuchar presencia de usuarios en tiempo real.
  void _setupPresenceListener() {
    _presenceChannel = Supabase.instance.client.channel('online_users');

    // Sync completo (se dispara al inicio y en cada cambio)
    _presenceChannel!.onPresenceSync((payload) {
      _updateOnlineUsers();
    });

    // Detección rápida de join/leave individuales
    _presenceChannel!.onPresenceJoin((payload) {
      _updateOnlineUsers();
    });

    _presenceChannel!.onPresenceLeave((payload) {
      _updateOnlineUsers();
    });

    // Suscribir al canal
    _presenceChannel!.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('✅ Admin suscrito a presencia');
        // Admin también trackea para que el canal esté activo
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          _presenceChannel!.track({
            'user_id': user.id,
            'email': user.email ?? '',
            'role': 'Admin',
            'online_at': DateTime.now().toIso8601String(),
          });
        }
        // Chequear estado actual después de suscribirse
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _updateOnlineUsers();
        });
      }
    });
  }

  void _updateOnlineUsers() {
    if (_presenceChannel == null) return;
    final presences = _presenceChannel!.presenceState();
    final ids = <String>{};
    for (final state in presences) {
      for (final presence in state.presences) {
        final uid = presence.payload['user_id']?.toString();
        if (uid != null) ids.add(uid);
      }
    }
    if (mounted) {
      setState(() => _onlineUserIds = ids);
    }
    debugPrint('🟢 Usuarios online: ${ids.length} → $ids');
  }

  Future<void> _fetchOperadores() async {
    final supabase = ref.read(supabaseProvider);
    try {
      final evRes = await supabase
          .from('eventos')
          .select('id, tipo, fecha_evento, clientes(nombre_completo), pin_operador')
          .not('estado', 'eq', 'Cancelado')
          .order('fecha_evento', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _eventosParaOperadores = (evRes as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar operadores: $e')));
      }
    }
  }

  Future<void> _navegarAEvento(IngresoDetallado ing) async {
    if (ing.eventoId == null) return;
    
    final repo = ref.read(eventosRepositoryProvider);
    try {
      final evento = await repo.getById(ing.eventoId!);
      if (evento != null && mounted) {
        if (ing.fuente == 'Particular') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetalleEventoParticularScreen(evento: evento)),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DetalleEventoMasivoScreen(evento: evento)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al navegar al evento: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(adminAuthProvider).isAdmin;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'MI EMPRESA',
          style: GoogleFonts.oswald(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                ref.read(finanzasProvider.notifier).recargar();
                _fetchOperadores();
              },
              tooltip: 'Actualizar',
            ),
          if (isAdmin)
            IconButton(
              icon: Icon(Icons.cleaning_services_rounded, size: 16, color: gold.withValues(alpha: 0.3)),
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const SmartPurgeDialog(),
              ),
              tooltip: 'Saneamiento',
            ),
          const SizedBox(width: 8),
        ],
        bottom: isAdmin
            ? TabBar(
                controller: _tabController,
                labelColor: gold,
                unselectedLabelColor: Colors.grey,
                indicatorColor: gold,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                tabs: const [
                  Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'FINANZAS'),
                  Tab(icon: Icon(Icons.engineering_outlined, size: 18), text: 'PERSONAL'),
                  Tab(icon: Icon(Icons.login_rounded, size: 18), text: 'OPERADORES'),
                ],
              )
            : null,
      ),
      floatingActionButton: isAdmin && _tabController.index == 1
          ? _buildPersonalFAB(isDark, gold)
          : null,
      body: !isAdmin
          ? _buildLockScreen(gold)
          : !isAdmin
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                )
              : Consumer(
                  builder: (context, ref, _) {
                    final asyncFinanzas = ref.watch(finanzasProvider);
                    
                    if (asyncFinanzas.isLoading && !asyncFinanzas.hasValue) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                    }
                    if (asyncFinanzas.hasError) {
                      return Center(child: Text('Error: ${asyncFinanzas.error}', style: const TextStyle(color: Colors.red)));
                    }
                    
                    final state = asyncFinanzas.requireValue;

                    return TabBarView(
                      controller: _tabController,
                      children: [
                        _buildContent(isDark, gold, state),
                        _buildPersonalTab(isDark, gold, state),
                        _buildOperadoresTab(isDark, gold),
                      ],
                    );
                  }
                ),
    );
  }

  // ── Pantalla de bloqueo ────────────────────────────────────────────────────
  Widget _buildLockScreen(Color gold) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.business_center_rounded, color: Color(0xFFD4AF37), size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            'ZONA PRIVADA',
            style: GoogleFonts.oswald(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
              color: gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Esta sección contiene información confidencial\nexclusiva del propietario.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white38
                  : Colors.black38,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () async {
              final hasAccess = await AdminGate.check(context, ref);
              if (hasAccess && mounted) {
                _fetchOperadores();
                setState(() {});
              }
            },
            icon: const Icon(Icons.key_rounded),
            label: const Text('ACCEDER CON PIN MAESTRO'),
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHUD(bool isDark, Color gold, FinanzasState state, {bool compact = false}) {
    final proj = state.proyeccionFinanciera;
    if (proj == null) return const SizedBox.shrink();

    final cap = (proj['capital_liquido'] as num?)?.toDouble() ?? 0.0;
    final opex = (proj['opex_capex_a_30_dias'] as num?)?.toDouble() ?? 0.0;
    final proy30 = (proj['proyeccion_caja_30d'] as num?)?.toDouble() ?? 0.0;
    final status = proj['estado_sistema']?.toString() ?? 'DESCONOCIDO';
    final isCritical = status.contains('CRÍTICO');
    final pColor = isCritical ? const Color(0xFFE74C3C) : const Color(0xFF00B894);

    if (compact) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: pColor.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: pColor.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hub_outlined, color: gold, size: 18),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('CAPITAL LÍQUIDO ACTUAL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                Text(cap.toCurrency(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ESTADO DEL SISTEMA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: pColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: pColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: pColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: pColor.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('INTELIGENCIA FINANCIERA', style: GoogleFonts.oswald(fontSize: 12, letterSpacing: 2, color: gold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: pColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(status, style: TextStyle(color: pColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(cap.toCurrency(), style: GoogleFonts.oswald(fontSize: 44, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black, letterSpacing: -1)),
          Text('CAPITAL LÍQUIDO ACTUAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1.5)),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OPEX/CAPEX (30 DÍAS)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text('-${opex.toCurrency()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFFE74C3C))),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PROYECCIÓN (30 DÍAS)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(proy30.toCurrency(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: pColor)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFiltroMeses(bool isDark, Color gold, FinanzasState state) {
    final now = DateTime.now();
    final meses = List.generate(6, (i) => DateTime(now.year, now.month - i, 1));
    const mesesNombres = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...meses.map((m) {
            final isSelected = state.mesFiltro?.year == m.year && state.mesFiltro?.month == m.month;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${mesesNombres[m.month - 1]} ${m.year}'),
                selected: isSelected,
                selectedColor: gold.withValues(alpha: 0.2),
                backgroundColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: isSelected ? gold : (isDark ? Colors.white54 : Colors.black54),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? gold.withValues(alpha: 0.5) : Colors.transparent)),
                onSelected: (val) {
                  if (val) {
                    ref.read(finanzasProvider.notifier).aplicarFiltro(mes: m);
                  } else {
                    ref.read(finanzasProvider.notifier).aplicarFiltro(clearMes: true);
                  }
                },
              ),
            );
          }),
          if (state.mesFiltro != null || state.eventoIdFiltro != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: IconButton(
                icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                tooltip: 'Limpiar Filtros',
                color: isDark ? Colors.white54 : Colors.black54,
                onPressed: () {
                  ref.read(finanzasProvider.notifier).aplicarFiltro(clearMes: true, clearEvento: true);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Contenido principal ────────────────────────────────────────────────────
  Widget _buildContent(bool isDark, Color gold, FinanzasState state) {
    final query = _masterSearchCtrl.text.trim();
    final isSearching = query.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async { 
        await ref.read(finanzasProvider.notifier).recargar(); 
      },
      color: gold,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1400 : 800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── CABECERA PERMANENTE (Filtros + Buscador) ──
                    _buildFiltroMeses(isDark, gold, state),
                    const SizedBox(height: 16),
                    _buildBuscadorMaestro(isDark, gold),
                    const SizedBox(height: 20),
                    
                    // ── HUD Adaptativo ──
                    _buildHUD(isDark, gold, state, compact: isSearching),
                    if (!isSearching) ...[
                      const SizedBox(height: 16),
                      _buildPorCobrarHUD(isDark, gold),
                      _buildAlertasGestion(isDark, gold),
                      const SizedBox(height: 24),
                      _sectionLabel('Rendimiento Mensual', Icons.bar_chart_rounded),
                      _buildTablaAnualDinamica(isDark, gold, const Color(0xFF00B894), const Color(0xFFE74C3C), state),
                      const SizedBox(height: 32),
                    ],

                    // ── ZONA DE OPERACIONES (Doble Columna si es ancho) ──
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchContext != SearchContext.egresos)
                            Expanded(
                              flex: _searchContext == SearchContext.ingresos ? 2 : 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel('INGRESOS', Icons.add_card_rounded),
                                  const SizedBox(height: 12),
                                  _buildIngresosLista(isDark, gold, const Color(0xFF00B894), state.ingresos, isHalf: _searchContext == SearchContext.todos),
                                ],
                              ),
                            ),
                          if (_searchContext == SearchContext.todos) const SizedBox(width: 24),
                          if (_searchContext != SearchContext.ingresos)
                            Expanded(
                              flex: _searchContext == SearchContext.egresos ? 2 : 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sectionLabel('EGRESOS', Icons.receipt_long_outlined),
                                  const SizedBox(height: 12),
                                  _buildEgresosLista(isDark, gold, const Color(0xFFE74C3C), state.egresos, isHalf: _searchContext == SearchContext.todos),
                                ],
                              ),
                            ),
                        ],
                      )
                    else ...[
                      if (_searchContext != SearchContext.egresos) ...[
                        _sectionLabel('INGRESOS RECIENTES', Icons.add_card_rounded),
                        const SizedBox(height: 12),
                        _buildIngresosLista(isDark, gold, const Color(0xFF00B894), state.ingresos, isHalf: false),
                        const SizedBox(height: 28),
                      ],
                      if (_searchContext != SearchContext.ingresos) ...[
                        _sectionLabel('EGRESOS REGISTRADOS', Icons.receipt_long_outlined),
                        const SizedBox(height: 12),
                        _buildEgresosLista(isDark, gold, const Color(0xFFE74C3C), state.egresos, isHalf: false),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Buscador Maestro de Inteligencia Financiera ──────────────────────────
  Widget _buildBuscadorMaestro(bool isDark, Color gold) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: gold.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: gold.withValues(alpha: 0.08),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: _masterSearchCtrl,
            onChanged: (val) => setState(() {}),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'CUALQUIER MOVIMIENTO, PERSONA O CONCEPTO...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white24 : Colors.black26,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
              prefixIcon: Icon(Icons.hub_outlined, color: gold, size: 22),
              suffixIcon: _masterSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _masterSearchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Chips de Contexto
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFiltroChip('TODOS', SearchContext.todos, gold, isDark),
              const SizedBox(width: 8),
              _buildFiltroChip('INGRESOS', SearchContext.ingresos, const Color(0xFF00B894), isDark),
              const SizedBox(width: 8),
              _buildFiltroChip('EGRESOS', SearchContext.egresos, const Color(0xFFE74C3C), isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroChip(String label, SearchContext ctx, Color color, bool isDark) {
    final isSelected = _searchContext == ctx;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.15),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: isSelected ? color : (isDark ? Colors.white30 : Colors.black38),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? color.withValues(alpha: 0.5) : Colors.transparent),
      ),
      onSelected: (val) => setState(() => _searchContext = ctx),
    );
  }

  // ── Alertas de Gestión (Privadas) ──────────────────────────────────────────
  Widget _buildAlertasGestion(bool isDark, Color gold) {
    return Consumer(
      builder: (context, ref, _) {
        final statsAsync = ref.watch(dashboardStatsProvider);
        return statsAsync.when(
          data: (stats) {
            final financialAlerts = stats.alertas.where((a) => a.isFinanciera).toList();
            if (financialAlerts.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: Icon(Icons.admin_panel_settings_outlined, color: gold, size: 20),
                      title: Text(
                        'GESTIÓN DE VENCIMIENTOS Y DEUDAS',
                        style: GoogleFonts.oswald(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: gold,
                        ),
                      ),
                      subtitle: Text(
                        '${financialAlerts.length} alertas detectadas que requieren su atención.',
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: financialAlerts.map((alerta) => Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: alerta.color.withValues(alpha: isDark ? 0.08 : 0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: alerta.color.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: alerta.color.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(alerta.icono, color: alerta.color, size: 18),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          alerta.titulo,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                            color: alerta.color,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          alerta.mensaje,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
        );
      },
    );
  }

  // ── Tabla mensual ──────────────────────────────────────────────────────────
  Widget _buildTablaAnualDinamica(bool isDark, Color gold, Color green, Color red, FinanzasState state) {
    const mesesNombre = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    
    final now = DateTime.now();
    final List<_MesData> mesesCalculados = [];
    
    for (int i = 5; i >= 0; i--) {
      final mes = DateTime(now.year, now.month - i, 1);
      final siguiente = DateTime(mes.year, mes.month + 1, 1);
      
      final ing = state.ingresos.where((x) => !x.fecha.isBefore(mes) && x.fecha.isBefore(siguiente)).fold(0.0, (s, e) => s + e.monto);
      final eg = state.egresos.where((x) => x.fecha != null && !x.fecha!.isBefore(mes) && x.fecha!.isBefore(siguiente)).fold(0.0, (s, e) => s + e.monto);
      
      mesesCalculados.add(_MesData(mes: mes, ingresos: ing, egresos: eg));
    }

    final maxVal = mesesCalculados.fold<double>(
      0,
      (m, d) => [m, d.ingresos, d.egresos].reduce((a, b) => a > b ? a : b),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 36, child: Text('MES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
              const SizedBox(width: 8),
              Expanded(child: Text('INGRESOS / EGRESOS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
              SizedBox(width: 80, child: Text('NETO', textAlign: TextAlign.right, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
            ],
          ),
          const SizedBox(height: 10),
          ...(mesesCalculados.map((m) {
            final nombre = mesesNombre[m.mes.month - 1];
            final neto = m.ingresos - m.egresos;
            final ingRatio = maxVal > 0 ? (m.ingresos / maxVal).clamp(0.0, 1.0) : 0.0;
            final egRatio = maxVal > 0 ? (m.egresos / maxVal).clamp(0.0, 1.0) : 0.0;
            final isCurrent = m.mes.month == DateTime.now().month && m.mes.year == DateTime.now().year;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Text(nombre, style: TextStyle(fontSize: 10, fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600, color: isCurrent ? gold : (isDark ? Colors.white54 : Colors.black54)))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: ingRatio, minHeight: 6, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(green.withValues(alpha: 0.7)))),
                        const SizedBox(height: 3),
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: egRatio, minHeight: 6, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(red.withValues(alpha: 0.7)))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 80, child: Text(neto.toCurrency(), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: neto >= 0 ? green : red))),
                ],
              ),
            );
          })),
        ],
      ),
    );
  }

  // ── POR COBRAR HUD ─────────────────────────────────────────────────────────
  Widget _buildPorCobrarHUD(bool isDark, Color gold) {
    return Consumer(
      builder: (context, ref, _) {
        final statsAsync = ref.watch(dashboardStatsProvider);
        return statsAsync.when(
          data: (stats) {
            if (stats.saldoPorCobrar <= 0) return const SizedBox.shrink();

            final pColor = stats.morosidadReal > 0.01 ? const Color(0xFFE74C3C) : gold;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: pColor.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, color: gold, size: 16),
                      const SizedBox(width: 8),
                      Text('POR COBRAR', style: GoogleFonts.oswald(fontSize: 12, letterSpacing: 2, color: gold)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('A VENCER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text((stats.saldoPorCobrar - stats.morosidadReal).toCurrency(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: isDark ? Colors.white70 : Colors.black87)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('VENCIDO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(stats.morosidadReal.toCurrency(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: stats.morosidadReal > 0.01 ? const Color(0xFFE74C3C) : (isDark ? Colors.white70 : Colors.black87))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('TOTAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black38, letterSpacing: 1)),
                            const SizedBox(height: 4),
                            Text(stats.saldoPorCobrar.toCurrency(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: gold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (err, st) => const SizedBox.shrink(),
        );
      },
    );
  }

  // ── Lista de Ingresos (ÉLITE DataTables) ───────────────────────────────────
  Widget _buildIngresosLista(bool isDark, Color gold, Color green, List<IngresoDetallado> ingresos, {required bool isHalf}) {
    // Filtrado dinámico unificado
    if (_searchContext == SearchContext.egresos) return const SizedBox.shrink();

    final query = _masterSearchCtrl.text.toLowerCase().trim();
    final filteredIngresos = ingresos.where((ing) {
      if (query.isEmpty) return true;
      return ing.alumnoOCliente.toLowerCase().contains(query) ||
             ing.concepto.toLowerCase().contains(query);
    }).toList();

    return Column(
      children: [
        // ── Lista de Ingresos ────────────────────────────────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: query.isNotEmpty, // Se expande automáticamente al buscar
              tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              title: Text(
                'MOSTRAR REGISTROS DE INGRESOS (${filteredIngresos.length})',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isDark ? Colors.white60 : Colors.black54, letterSpacing: 1.5),
              ),
              children: [
                if (filteredIngresos.isEmpty && query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'SIN INGRESOS QUE COINCIDAN',
                        style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  )
                else if (filteredIngresos.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 45,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 60,
                        headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.015)),
                        headingTextStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: gold.withValues(alpha: 0.7), letterSpacing: 1),
                        dataTextStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        dividerThickness: 0.5,
                        horizontalMargin: isHalf ? 8 : 20,
                        columnSpacing: isHalf ? 10 : 25,
                        columns: const [
                          DataColumn(label: Text('CLIENTE')),
                          DataColumn(label: Text('CONCEPTO')),
                          DataColumn(label: Text('EVENTO')),
                          DataColumn(label: Text('FECHA')),
                          DataColumn(label: Text('MONTO')),
                          DataColumn(label: Text('ACCION')),
                        ],
                        rows: filteredIngresos.take(50).map((ing) {
                          final fechaStr = '${ing.fecha.day.toString().padLeft(2, '0')}/${ing.fecha.month.toString().padLeft(2, '0')}';
                          return DataRow(
                            cells: [
                                DataCell(
                                  SizedBox(
                                    width: isHalf ? 120 : 180,
                                    child: Text(
                                      ing.alumnoOCliente,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                child: Text(ing.concepto.toUpperCase(), style: TextStyle(color: gold, fontSize: 8, fontWeight: FontWeight.w900)),
                              )),
                              DataCell(Text(Evento.formatearTipo(ing.nombreEvento), style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 10))),
                              DataCell(Text(fechaStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                              DataCell(Text('+${ing.monto.toCurrency()}', style: TextStyle(color: green, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 13))),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (ing.eventoId != null)
                                        IconButton(
                                          icon: const Icon(Icons.celebration_rounded, size: 16),
                                          color: gold,
                                          tooltip: 'Ir al Evento',
                                          onPressed: () => _navegarAEvento(ing),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.print_rounded, size: 16),
                                        color: gold.withValues(alpha: 0.6),
                                        tooltip: 'Imprimir Recibo',
                                        onPressed: () {
                                          ref.read(finanzasProvider.notifier).imprimirRecibo(context, ing);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Lista de egresos (ÉLITE DataTables) ───────────────────────────────────
  Widget _buildEgresosLista(bool isDark, Color gold, Color red, List<Egreso> egresos, {required bool isHalf}) {
    // Filtrado dinámico unificado
    if (_searchContext == SearchContext.ingresos) return const SizedBox.shrink();

    final query = _masterSearchCtrl.text.toLowerCase().trim();
    final filteredEgresos = egresos.where((eg) {
      if (query.isEmpty) return true;
      final prov = (eg.proveedor ?? '').toLowerCase();
      final cat = (eg.categoria ?? '').toLowerCase();
      return prov.contains(query) || cat.contains(query);
    }).toList();

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: query.isNotEmpty, // Auto-expansión al buscar
              tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              title: Text(
                'MOSTRAR REGISTROS DE EGRESOS (${filteredEgresos.length})',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isDark ? Colors.white60 : Colors.black54, letterSpacing: 1.5),
              ),
              children: [
                if (filteredEgresos.isEmpty && query.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'SIN EGRESOS QUE COINCIDAN',
                        style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                      ),
                    ),
                  )
                else if (filteredEgresos.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 45,
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 60,
                        headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.015)),
                        headingTextStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: gold.withValues(alpha: 0.7), letterSpacing: 1),
                        dataTextStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                        dividerThickness: 0.5,
                        horizontalMargin: isHalf ? 16 : 24,
                        columnSpacing: isHalf ? 24 : 40,
                        columns: const [
                          DataColumn(label: Text('PROVEEDOR')),
                          DataColumn(label: Text('CATEGORÍA')),
                          DataColumn(label: Text('FECHA')),
                          DataColumn(label: Text('MONTO')),
                        ],
                        rows: filteredEgresos.take(50).map((eg) {
                          final fechaStr = eg.fecha != null ? '${eg.fecha!.day.toString().padLeft(2, '0')}/${eg.fecha!.month.toString().padLeft(2, '0')}' : '--';
                          final cat = (eg.categoria ?? 'Otro').toUpperCase();
                          return DataRow(
                            cells: [
                              DataCell(Text(eg.proveedor ?? 'S/R', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11))),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(cat, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900)),
                              )),
                              DataCell(Text(fechaStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                              DataCell(Text('-${eg.monto.toCurrency()}', style: TextStyle(color: red, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 13))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── FAB Personal ──────────────────────────────────────────────────────────
  Widget _buildPersonalFAB(bool isDark, Color gold) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog<bool>(
            context: context,
            builder: (_) => const PagarOperadorDialog(),
          );
          if (mounted && result == true) {
            _fetchOperadores();
            ref.read(finanzasProvider.notifier).recargar();
          }
        },
        backgroundColor: Colors.blueAccent,
        label: const Text(
          'PAGAR OPERADOR',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12),
        ),
        icon: const Icon(Icons.engineering_outlined, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ── Tab OPERADORES (recepción check-in por evento) ───────────────────────────
  String _labelEventoOp(Map<String, dynamic> ev) {
    final cliente = ev['clientes']?['nombre_completo'] ?? 'Sin cliente';
    final tipo = Evento.formatearTipo(ev['tipo'] as String?);
    final fecha = ev['fecha_evento'] != null
        ? DateTime.tryParse(ev['fecha_evento'])
        : null;
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}'
        : '';
    return '$cliente · $tipo · $fechaStr';
  }

  void _generarPinOperadores() {
    final pin = (1000 + Random().nextInt(9000)).toString();
    setState(() => _operadoresPinCtrl.text = pin);
    _guardarPinOperadores(pin);
  }

  Future<void> _guardarPinOperadores(String pin) async {
    final eventoId = _operadoresEventoId;
    if (eventoId == null) return;
    setState(() => _operadoresSavingPin = true);
    try {
      await Supabase.instance.client
          .from('eventos')
          .update({'pin_operador': pin.isEmpty ? null : pin})
          .eq('id', eventoId);
      if (mounted) {
        final idx = _eventosParaOperadores.indexWhere((e) => e['id'] == eventoId);
        if (idx >= 0) _eventosParaOperadores[idx]['pin_operador'] = pin.isEmpty ? null : pin;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN guardado correctamente'),
            backgroundColor: Color(0xFF00B894),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar PIN: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _operadoresSavingPin = false);
    }
  }

  /// Mostrar diálogo de permisos para un Asesor específico.
  Future<void> _showPermissionsDialog(String userId, String nombre) async {
    final supabase = ref.read(supabaseProvider);
    const gold = Color(0xFFD4AF37);

    // Cargar permisos actuales
    Map<String, bool> permisos = {
      'puede_recepcion': true,
      'puede_eventos': false,
      'puede_clientes': false,
      'puede_catalogo': false,
      'puede_totem': false,
      'puede_qr': false,
      'puede_finanzas': false,
    };

    try {
      final res = await supabase
          .from('permisos_usuario')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (res != null) {
        for (final key in permisos.keys) {
          permisos[key] = res[key] ?? permisos[key];
        }
      }
    } catch (e) {
      debugPrint('Error cargando permisos: $e');
    }

    final labels = {
      'puede_recepcion': ('Recepción / Check-in', Icons.door_front_door_rounded),
      'puede_eventos': ('Eventos', Icons.celebration_outlined),
      'puede_clientes': ('Clientes', Icons.people_alt_outlined),
      'puede_catalogo': ('Catálogo', Icons.settings_suggest_outlined),
      'puede_totem': ('Tótem', Icons.monitor_rounded),
      'puede_qr': ('QR', Icons.qr_code_2_rounded),
      'puede_finanzas': ('Finanzas', Icons.business_center_outlined),
    };

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: gold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const Text('PERMISOS DE ACCESO', style: TextStyle(fontSize: 9, color: Colors.grey, letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(),
                    ...permisos.entries.map((entry) {
                      final info = labels[entry.key]!;
                      return SwitchListTile(
                        value: entry.value,
                        onChanged: (val) {
                          setDialogState(() => permisos[entry.key] = val);
                        },
                        title: Text(info.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        secondary: Icon(info.$2, color: entry.value ? gold : Colors.grey, size: 20),
                        activeThumbColor: gold,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      );
                    }),
                    const Divider(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await supabase.from('permisos_usuario').upsert({
                        'user_id': userId,
                        ...permisos,
                        'asignado_por': supabase.auth.currentUser?.id,
                        'updated_at': DateTime.now().toIso8601String(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Permisos de $nombre actualizados'),
                            backgroundColor: const Color(0xFF00B894),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOperadoresTab(bool isDark, Color gold) {
    const purple = Colors.purpleAccent;
    final tienePinReal = _operadoresPinCtrl.text.trim().isNotEmpty;
    final opUrl = _operadoresEventoId != null
        ? '$kWebBaseUrl/op?evento=$_operadoresEventoId'
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── GESTIÓN DE ASESORES ─────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.group_rounded, color: Colors.cyanAccent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ASESORES REGISTRADOS',
                          style: GoogleFonts.oswald(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.cyanAccent,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          '${_asesores.length} usuario(s) · ${_onlineUserIds.length} online',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    color: Colors.cyanAccent,
                    onPressed: () {
                      _fetchAsesores();
                    },
                    tooltip: 'Actualizar lista',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_asesores.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: Center(
                    child: Text(
                      'No hay asesores registrados aún.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                )
              else
                ..._asesores.map((asesor) {
                  final uid = asesor['id'] as String;
                  final nombre = asesor['nombre'] ?? 'Sin nombre';
                  final isOnline = _onlineUserIds.contains(uid);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _showPermissionsDialog(uid, nombre),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isOnline
                                ? Colors.greenAccent.withValues(alpha: 0.4)
                                : (isDark ? Colors.white12 : Colors.black12),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Online indicator
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.greenAccent : Colors.grey,
                                boxShadow: isOnline
                                    ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.5), blurRadius: 6)]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Avatar
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: gold.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  nombre.toString().isNotEmpty
                                      ? nombre.toString()[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: gold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nombre,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    isOnline ? 'En línea' : 'Desconectado',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isOnline ? Colors.greenAccent : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.tune_rounded,
                              color: gold,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: isDark ? Colors.white24 : Colors.black26,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 24),
              Divider(color: isDark ? Colors.white12 : Colors.black12),
              const SizedBox(height: 24),

              // ── SECCIÓN ORIGINAL: CHECK-IN POR EVENTO ────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: purple.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.login_rounded, color: purple, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RECEPCIÓN DE INVITADOS (CHECK-IN)',
                          style: GoogleFonts.oswald(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: purple,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'Elegí un evento y configurá el PIN para que recepción marque ingresos con el link.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _operadoresEventoId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'EVENTO',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                items: _eventosParaOperadores.map((ev) {
                  return DropdownMenuItem<String>(
                    value: ev['id'] as String,
                    child: Text(
                      _labelEventoOp(ev),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == null) return;
                  Map<String, dynamic>? ev;
                  for (final e in _eventosParaOperadores) {
                    if (e['id'] == val) { ev = e; break; }
                  }
                  setState(() {
                    _operadoresEventoId = val;
                    _operadoresPinCtrl.text = (ev?['pin_operador']?.toString() ?? '').trim();
                  });
                },
              ),
              if (_operadoresEventoId != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: tienePinReal
                        ? Colors.green.withValues(alpha: isDark ? 0.08 : 0.06)
                        : Colors.orange.withValues(alpha: isDark ? 0.08 : 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tienePinReal
                          ? Colors.greenAccent.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        tienePinReal ? Icons.lock_open_rounded : Icons.lock_rounded,
                        color: tienePinReal ? Colors.greenAccent : Colors.orange,
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          tienePinReal
                              ? 'Recepción (check-in) habilitada con PIN'
                              : 'Configurá un PIN para dar acceso',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tienePinReal ? Colors.greenAccent : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'PIN DE ACCESO',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _operadoresPinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.oswald(fontSize: 24, letterSpacing: 6),
                        decoration: InputDecoration(
                          hintText: '0000',
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onSubmitted: (v) => _guardarPinOperadores(v.trim()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _generarPinOperadores,
                      style: IconButton.styleFrom(
                        backgroundColor: purple.withValues(alpha: 0.15),
                        foregroundColor: purple,
                      ),
                      icon: const Icon(Icons.casino_rounded, size: 22),
                      tooltip: 'Generar PIN',
                    ),
                    const SizedBox(width: 6),
                    _operadoresSavingPin
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                          )
                        : IconButton.filled(
                            onPressed: () => _guardarPinOperadores(_operadoresPinCtrl.text.trim()),
                            style: IconButton.styleFrom(
                              backgroundColor: gold.withValues(alpha: 0.15),
                              foregroundColor: gold,
                            ),
                            icon: const Icon(Icons.save_rounded, size: 22),
                            tooltip: 'Guardar PIN',
                          ),
                  ],
                ),
                if (tienePinReal && opUrl.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'LINK PARA RECEPCIÓN',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          opUrl,
                          style: GoogleFonts.outfit(fontSize: 12, color: gold, height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('COPIAR'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: gold,
                                  side: BorderSide(color: gold.withValues(alpha: 0.4)),
                                  textStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: opUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Link copiado'), duration: Duration(seconds: 2)),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.share_rounded, size: 16),
                                label: const Text('COMPARTIR'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: purple.withValues(alpha: 0.8),
                                  textStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                                onPressed: () async {
                                  await SharePlus.instance.share(
                                    ShareParams(
                                      text: 'Acceso recepción (check-in):\n$opUrl\nPIN: ${_operadoresPinCtrl.text.trim()}\n\nAbrí el link, ingresá el PIN y marcá ingresos.',
                                      subject: 'Acceso Recepción - Arguello Events',
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab PERSONAL ───────────────────────────────────────────────────────────
  Widget _buildPersonalTab(bool isDark, Color gold, FinanzasState state) {
    const blue = Colors.blueAccent;
    const red = Color(0xFFE74C3C);

    final personal = state.egresos.where((e) => e.categoria == 'Personal').toList();

    if (personal.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.engineering_outlined, color: blue, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'SIN PAGOS A PERSONAL REGISTRADOS',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Usá el botón para registrar el pago a un operador.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Agrupar por proveedor (operador)
    final grouped = <String, List<Egreso>>{};
    for (final eg in personal) {
      final key = eg.proveedor ?? 'Sin nombre';
      grouped.putIfAbsent(key, () => []).add(eg);
    }
    final operadores = grouped.entries.toList()
      ..sort((a, b) {
        final totalA = a.value.fold(0.0, (s, e) => s + e.monto);
        final totalB = b.value.fold(0.0, (s, e) => s + e.monto);
        return totalB.compareTo(totalA);
      });

    final totalPersonal = personal.fold(0.0, (s, e) => s + e.monto);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner total personal ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      blue.withValues(alpha: 0.85),
                      Colors.blueAccent,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: blue.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.engineering_outlined, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TOTAL PAGADO AL PERSONAL',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            totalPersonal.toCurrency(),
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${operadores.length} operadores',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${personal.length} pagos',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _sectionLabel('LIQUIDACIÓN POR OPERADOR', Icons.people_outline),
              const SizedBox(height: 12),

              // ── Tarjeta por operador ───────────────────────────────────────
              ...operadores.map((entry) {
                final nombre = entry.key;
                final pagos = entry.value;
                final totalOp = pagos.fold(0.0, (s, e) => s + e.monto);
                final ultimoPago = pagos.first;
                final ultimaFecha = ultimoPago.fecha != null
                    ? '${ultimoPago.fecha!.day.toString().padLeft(2, '0')}/${ultimoPago.fecha!.month.toString().padLeft(2, '0')}/${ultimoPago.fecha!.year}'
                    : 'Sin fecha';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.person_outline, color: blue, size: 20),
                        ),
                        title: Text(
                          nombre.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${pagos.length} pago(s) · Último: $ultimaFecha',
                          style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              totalOp.toCurrency(),
                              style: const TextStyle(color: blue, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, color: blue, size: 20),
                              tooltip: 'Nuevo pago a $nombre',
                              onPressed: () async {
                                final result = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => PagarOperadorDialog(
                                    eventoIdInicial: null,
                                    tipoEventoInicial: null,
                                  ),
                                );
                                if (mounted && result == true) {
                                  _fetchOperadores();
                                  ref.read(finanzasProvider.notifier).recargar();
                                }
                              },
                            ),
                          ],
                        ),
                        children: [
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                              child: DataTable(
                                headingRowHeight: 0,
                                dataRowMinHeight: 36,
                                dataRowMaxHeight: 44,
                                dividerThickness: 0.5,
                                horizontalMargin: 24,
                                columnSpacing: 16,
                                columns: const [
                                  DataColumn(label: SizedBox.shrink()),
                                  DataColumn(label: SizedBox.shrink(), numeric: true),
                                  DataColumn(label: SizedBox.shrink()),
                                ],
                                rows: pagos.map((pg) {
                                  final fecha = pg.fecha != null ? '${pg.fecha!.day.toString().padLeft(2, '0')}/${pg.fecha!.month.toString().padLeft(2, '0')}/${pg.fecha!.year}' : 'Sin fecha';
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(fecha, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: isDark ? Colors.white70 : Colors.black87))),
                                      DataCell(Text('-${pg.monto.toCurrency()}', style: const TextStyle(color: red, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 12))),
                                      DataCell(
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: IconButton(
                                            icon: Icon(Icons.edit_outlined, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                                            tooltip: 'Editar pago',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () async {
                                              final result = await showDialog<bool>(context: context, builder: (_) => EditarPagoOperadorDialog(egreso: pg));
                                              if (mounted && result == true) _fetchOperadores();
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label, IconData icon) {
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
}

class _MesData {
  final DateTime mes;
  final double ingresos;
  final double egresos;
  const _MesData({required this.mes, required this.ingresos, required this.egresos});
}
