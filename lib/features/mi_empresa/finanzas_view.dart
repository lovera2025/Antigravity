import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../core/utils/ar_time.dart';
import '../../models/egreso.dart';
import '../../models/evento.dart';
import '../common/providers/admin_provider.dart';
import '../common/widgets/admin_gate.dart';
import '../common/utils/currency_extensions.dart';
import '../common/utils/texto_busqueda.dart';
import '../common/services/pdf_service.dart';
import 'widgets/editar_pago_operador_dialog.dart';
import 'widgets/cartera_escuelas_dialog.dart';
import 'models/ingreso_detallado.dart';
import 'providers/finanzas_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import 'widgets/corregir_medio_pago_dialog.dart';
import 'widgets/anular_cobro_cuota_dialog.dart';
import 'widgets/smart_purge_dialog.dart';
import 'widgets/restaurar_mora_dialog.dart';
import '../eventos/detalle_evento_particular_screen.dart';
import '../eventos/detalle_evento_masivo_screen.dart';
import '../eventos/repositories/eventos_repository.dart';
import '../alquiler/prestamo_alquiler_detalle_screen.dart';
import '../egresos/repositories/egresos_repository.dart';
import '../egresos/widgets/registrar_egreso_global_dialog.dart';
import '../egresos/services/egreso_concepto_sugerencias.dart';
import '../eventos/eventos_screen.dart';
import '../eventos/presupuestos_screen.dart';
import 'repositories/finanzas_repository.dart';
import '../rentabilidad/repositories/rentabilidad_repository.dart';
import '../../models/calculo_rentabilidad.dart';
import '../../models/obligacion_pago.dart';
import 'providers/obligaciones_provider.dart';
import 'widgets/avisos_view.dart';
import 'widgets/pagar_aviso_dialog.dart';
import 'widgets/cobro_masivos_tab.dart';
import 'widgets/panel_movimientos_sheet.dart';
import 'widgets/calendario_filtro_movimientos.dart';
import 'widgets/retiro_bolsillo_personal_dialog.dart';
import 'widgets/gasto_personal_dialog.dart';
import '../cierre_caja/models/turno_caja.dart';
import '../cierre_caja/widgets/registrar_retiro_dialog.dart';
import 'widgets/finanzas_charts.dart';


enum SearchContext { todos, ingresos, egresos }
enum FinanzasSubView { salud, flujo, categorias, avisos }

/// Mitiga spam del motor Windows (`accessibility_bridge` / AXTree) en [Tooltip] dentro de scroll/listas.
bool _tooltipExcludeSemanticsWin() => defaultTargetPlatform == TargetPlatform.windows;

/// Destino al tocar cada pilar del score en SALUD (scroll + sección relacionada).
enum _SaludPillarTap { liquidez, margen, momentum, alertas }

/// Torta del mes (cobros por fuente / pagos por categoría): en SALUD; el toggle vive junto a ese bloque.
enum _FiltroMesCaja { cobros, pagos }

enum _PulsoRangoVista { mesCalendario, ultimos30 }

/// En el listado por mes, el chip «Efectivo» incluye explícitos + solo **hoy** todo lo que no sea transferencia (p. ej. sin medio).
bool _ingresoCuentaComoEfectivoEnListado(IngresoDetallado ing, DateTime hoyAr) {
  final mp = ing.medioPago?.toLowerCase().trim();
  if (mp == 'transferencia') return false;
  if (mp == 'efectivo') return true;
  return ArTime.mismoDia(ing.fecha, hoyAr);
}

class _DiaPulsoDatum {
  final DateTime dia;
  final double ing;
  final double eg;
  final int nPagos;
  final int nEgresos;
  double get neto => ing - eg;
  const _DiaPulsoDatum({
    required this.dia,
    required this.ing,
    required this.eg,
    required this.nPagos,
    required this.nEgresos,
  });
}

/// Totales de ingresos/egresos para un mes calendario (inicio = día 1).
class _MesData {
  final DateTime mes;
  final double ingresos;
  final double egresos;
  double get neto => ingresos - egresos;
  const _MesData({required this.mes, required this.ingresos, required this.egresos});
}

/// Delega en [calcularMesData] del provider en vez de repetir el cálculo.
///
/// Eran dos copias con el mismo error —leían las listas ya recortadas al mes
/// del filtro— y por eso este gráfico mostraba todas las barras en cero salvo
/// la del mes seleccionado.
_MesData _calcularMesData(FinanzasState state, DateTime mesInicio) {
  final d = calcularMesData(state, mesInicio);
  return _MesData(mes: d.mes, ingresos: d.ingresos, egresos: d.egresos);
}

List<_MesData> _ultimosMesesDatos(FinanzasState state, {int cantidad = 6}) {
  // Calendario argentino: en las primeras horas del día 1, `DateTime.now()`
  // local todavía puede estar en el mes anterior.
  final now = ArTime.nowAr();
  final out = <_MesData>[];
  for (int i = cantidad - 1; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    out.add(_calcularMesData(state, m));
  }
  return out;
}



List<IngresoDetallado> _ingresosVista(FinanzasState state) {
  final f = state.fechaExactaFiltro;
  if (f == null) return state.ingresos;
  return state.ingresos.where((i) => ArTime.mismoDia(i.fecha, f)).toList();
}

List<Egreso> _egresosVista(FinanzasState state) {
  final f = state.fechaExactaFiltro;
  if (f == null) return state.egresos;
  return state.egresos.where((e) => e.fecha != null && ArTime.mismoDia(e.fecha!, f)).toList();
}

/// Primer instante del lunes AR de la semana que contiene [diaAr].
DateTime _lunesSemanaArDesde(DateTime diaAr) {
  final a = ArTime.toAr(diaAr);
  final d = DateTime(a.year, a.month, a.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Línea horizontal punteada (referencia de promedio sobre la barra).

/// Tamaño mínimo de área táctil y dibujo de iconos en Finanzas (legible en 19–24" 1080p).
const double _kFinanzasAppBarIconSize = 22;
const double _kFinanzasIconButtonMinSide = 46;

ButtonStyle _finanzasIconButtonStyle() => IconButton.styleFrom(
      minimumSize: const Size(_kFinanzasIconButtonMinSide, _kFinanzasIconButtonMinSide),
      padding: const EdgeInsets.all(10),
      tapTargetSize: MaterialTapTargetSize.padded,
    );

class FinanzasView extends ConsumerStatefulWidget {
  const FinanzasView({super.key});

  @override
  ConsumerState<FinanzasView> createState() => _FinanzasViewState();
}

class _FinanzasViewState extends ConsumerState<FinanzasView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  /// Capturado en [initState]: en [dispose] no se puede usar [ref] (Riverpod).
  late final AdminAuthNotifier _adminAuthNotifier;

  // Tab OPERADORES: recepción check-in por evento
  List<Map<String, dynamic>> _eventosParaOperadores = [];
  String? _operadoresEventoId;
  final _operadoresPinCtrl = TextEditingController();
  bool _operadoresSavingPin = false;

  // Gestión de Asesores
  List<Map<String, dynamic>> _asesores = [];
  Set<String> _onlineUserIds = {};
  RealtimeChannel? _presenceChannel;

  // Buscador Maestro
  final _masterSearchCtrl = TextEditingController();
  // Búsqueda dentro del panel desplegable de ingresos / egresos (refina sin depender solo del scroll)
  final _ingresosListaSearchCtrl = TextEditingController();
  final _egresosListaSearchCtrl = TextEditingController();
  SearchContext _searchContext = SearchContext.todos;
  FinanzasSubView _currentSubView = FinanzasSubView.salud;
  final _ingresosHScrollCtrl = ScrollController();
  // null = Todos; valores posibles: 'efectivo' | 'transferencia' (efectivo = explícitos + solo hoy lo no transferencia)
  String? _medioPagoFiltro;

  /// Tras resolver reingreso a Mi Empresa (PIN si hace falta).
  bool _miEmpresaGateReady = false;
  bool _needsMiEmpresaReauth = false;

  _FiltroMesCaja _filtroMesCaja = _FiltroMesCaja.pagos;

  /// Operación del día en Resumen de caja (colapsada por defecto; el saldo principal queda arriba).
  bool _hudHoyExpanded = false;

  /// Caja fuerte colapsable en tab PERSONAL.

  /// Scroll a secciones de la vista SALUD al tocar pilares del hero.
  final GlobalKey _keySaludRunway = GlobalKey();
  final GlobalKey _keySaludResumen = GlobalKey();
  final GlobalKey _keySaludTabla = GlobalKey();
  final GlobalKey _keySaludAlertas = GlobalKey();
  final ExpansibleController _alertasGestionExpansionController = ExpansibleController();

  _PulsoRangoVista _pulsoRango = _PulsoRangoVista.mesCalendario;
  List<IngresoDetallado>? _pulso30Ingresos;
  List<Egreso>? _pulso30Egresos;
  bool _pulso30Loading = false;

  // Buscador de deudas por institución
  final _deudasSearchCtrl = TextEditingController();
  bool _deudasExpanded = false;

  /// Pulso diario (vista mes): scroll horizontal hasta acercar el día actual.
  final ScrollController _pulsoBarrasScrollController = ScrollController();
  String? _pulsoScrollAppliedStamp;

  Future<void> _cargarDatosPulso30(FinanzasState finState) async {
    setState(() => _pulso30Loading = true);
    try {
      final finRepo = ref.read(finanzasRepositoryProvider);
      final egrRepo = ref.read(egresosRepositoryProvider);
      final ing = await finRepo.obtenerIngresosDetallados(mes: null, eventoId: finState.eventoIdFiltro);
      final egMaps = await egrRepo.getEgresosConEvento();
      final eg = egMaps.map((e) => Egreso.fromJson(e)).toList();
      if (!mounted) return;
      final nowAr = ArTime.nowAr();
      final fin = DateTime(nowAr.year, nowAr.month, nowAr.day);
      final ini = fin.subtract(const Duration(days: 29));
      bool enRango(DateTime? dt) {
        if (dt == null) return false;
        final a = ArTime.toAr(dt);
        final solo = DateTime(a.year, a.month, a.day);
        return !solo.isBefore(ini) && !solo.isAfter(fin);
      }
      setState(() {
        _pulso30Ingresos = ing.where((i) => enRango(i.fecha)).toList();
        _pulso30Egresos = eg.where((e) => enRango(e.fecha)).toList();
        _pulso30Loading = false;
      });
    } catch (e) {
      debugPrint('Pulso 30d: $e');
      if (mounted) setState(() => _pulso30Loading = false);
    }
  }

  void _onTabControllerTick() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _adminAuthNotifier = ref.read(adminAuthProvider.notifier);
    // 4 pestañas: se retiró PERSONAL. Su contenido único —la liquidación por
    // operador— vive ahora en el panel SALDO DEL NEGOCIO, leyendo el
    // histórico en vez del mes filtrado, que era lo que la dejaba en blanco.
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabControllerTick);
    final isAdmin = ref.read(adminAuthProvider).isAdmin;
    if (isAdmin) {
      _fetchOperadores();
      _fetchAsesores();
      _setupPresenceListener();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveMiEmpresaAccess());
  }

  Future<void> _resolveMiEmpresaAccess() async {
    final reauth = await ref.read(adminAuthProvider.notifier).mustReauthMiEmpresa();
    if (!mounted) return;
    setState(() {
      _needsMiEmpresaReauth = reauth;
      _miEmpresaGateReady = true;
    });
  }

  @override
  void dispose() {
    unawaited(_adminAuthNotifier.recordMiEmpresaExit());
    _tabController.removeListener(_onTabControllerTick);
    _tabController.dispose();
    _operadoresPinCtrl.dispose();
    _masterSearchCtrl.dispose();
    _ingresosListaSearchCtrl.dispose();
    _egresosListaSearchCtrl.dispose();
    _ingresosHScrollCtrl.dispose();
    _pulsoBarrasScrollController.dispose();
    _deudasSearchCtrl.dispose();
    if (_presenceChannel != null) {
      Supabase.instance.client.removeChannel(_presenceChannel!);
    }
    _alertasGestionExpansionController.dispose();
    super.dispose();
  }

  void _onSaludPillarTap(_SaludPillarTap pillar) {
    void scrollTo(GlobalKey key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.15,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }

    switch (pillar) {
      case _SaludPillarTap.liquidez:
        scrollTo(_keySaludRunway);
        break;
      case _SaludPillarTap.margen:
        scrollTo(_keySaludResumen);
        break;
      case _SaludPillarTap.momentum:
        scrollTo(_keySaludTabla);
        break;
      case _SaludPillarTap.alertas:
        scrollTo(_keySaludAlertas);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _alertasGestionExpansionController.expand();
        });
        break;
    }
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

  Widget _buildFinanzasTabArea(
    bool isDark,
    Color gold,
    AsyncValue<FinanzasState> asyncFinanzas,
  ) {
    if (asyncFinanzas.isLoading && !asyncFinanzas.hasValue) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (asyncFinanzas.hasError) {
      return Center(
        child: Text(
          'Error: ${asyncFinanzas.error}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    final state = asyncFinanzas.requireValue;

    return TabBarView(
      controller: _tabController,
      children: [
        _buildContent(isDark, gold, state),
        const PresupuestosScreen(embedded: true),
        CobroMasivosTab(isDark: isDark, gold: gold),
        _buildOperadoresTab(isDark, gold),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(adminAuthProvider).isAdmin;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final showMiEmpresaContent =
        _miEmpresaGateReady && isAdmin && !_needsMiEmpresaReauth;

    final asyncFinanzas = ref.watch(finanzasProvider);

    ref.listen<AsyncValue<FinanzasState>>(finanzasProvider, (prev, next) {
      if (!showMiEmpresaContent) return;
      if (!next.hasValue) return;
      final no = next.requireValue;
      final po = prev != null && prev.hasValue ? prev.requireValue : null;
      if (po == null ||
          po.ingresos.length != no.ingresos.length ||
          po.egresos.length != no.egresos.length ||
          po.mesFiltro != no.mesFiltro ||
          po.eventoIdFiltro != no.eventoIdFiltro) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _pulso30Ingresos = null;
              _pulso30Egresos = null;
            });
          }
        });
      }
    });

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
              if (showMiEmpresaContent)
                IconButton(
                  style: _finanzasIconButtonStyle(),
                  icon: Icon(Icons.refresh_rounded, size: _kFinanzasAppBarIconSize, color: gold),
                  onPressed: () async {
                    ref.read(finanzasProvider.notifier).recargar();
                    _fetchOperadores();
                  },
                  tooltip: 'Actualizar',
                ),
              if (showMiEmpresaContent)
                PopupMenuButton<String>(
                  tooltip: 'Correcciones de cobro',
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.edit_outlined, size: _kFinanzasAppBarIconSize, color: gold.withValues(alpha: 0.92)),
                  onSelected: (value) async {
                    final ok = await AdminGate.check(context, ref, forceVerification: true);
                    if (!ok || !context.mounted) return;
                    if (value == 'medio') {
                      await showDialog<void>(
                        context: context,
                        builder: (_) => const CorregirMedioPagoDialog(),
                      );
                    } else if (value == 'anular') {
                      await showDialog<void>(
                        context: context,
                        builder: (_) => const AnularCobroCuotaDialog(),
                      );
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'medio', child: Text('Corregir medio de pago')),
                    PopupMenuItem(value: 'anular', child: Text('Anular cobro por error')),
                  ],
                ),
              if (showMiEmpresaContent)
                IconButton(
                  style: _finanzasIconButtonStyle(),
                  icon: Icon(
                    Icons.south_west_rounded,
                    size: _kFinanzasAppBarIconSize,
                    color: const Color(0xFFE74C3C),
                  ),
                  tooltip: 'Registrar retiro de caja',
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      builder: (_) => const RegistrarRetiroDialog(),
                    );
                    if (!context.mounted) return;
                    ref.read(finanzasProvider.notifier).recargar();
                  },
                ),
              if (showMiEmpresaContent)
                IconButton(
                  style: _finanzasIconButtonStyle(),
                  icon: Icon(Icons.cleaning_services_rounded, size: _kFinanzasAppBarIconSize, color: gold.withValues(alpha: 0.85)),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const SmartPurgeDialog(),
                  ),
                  tooltip: 'Saneamiento',
                ),
              if (showMiEmpresaContent)
                IconButton(
                  style: _finanzasIconButtonStyle(),
                  icon: Icon(Icons.restore_rounded, size: _kFinanzasAppBarIconSize, color: gold),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => const RestaurarMoraDialog(),
                  ),
                  tooltip: 'Restaurar mora persistida',
                ),
              const SizedBox(width: 4),
            ],
            bottom: showMiEmpresaContent
                ? TabBar(
                    isScrollable: true,
                    controller: _tabController,
                    labelColor: gold,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: gold,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                    tabs: const [
                      Tab(icon: Icon(Icons.bar_chart_rounded, size: 18), text: 'FINANZAS'),
                      Tab(icon: Icon(Icons.request_quote_outlined, size: 18), text: 'PRESUPUESTOS'),
                      Tab(icon: Icon(Icons.payments_outlined, size: 18), text: 'COBRO'),
                      Tab(icon: Icon(Icons.login_rounded, size: 18), text: 'OPERADORES'),
                    ],
                  )
                : null,
          ),
          // Sin FAB: colgaba de la pestaña PERSONAL. Registrar pago (gasto u
          // operador) se hace desde el panel SALDO DEL NEGOCIO.
          body: !_miEmpresaGateReady
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                )
              : (!isAdmin || _needsMiEmpresaReauth)
                  ? _buildLockScreen(
                      gold,
                      needsReauth: _needsMiEmpresaReauth,
                    )
                  : _buildFinanzasTabArea(isDark, gold, asyncFinanzas),
    );
  }

  // ── Pantalla de bloqueo ────────────────────────────────────────────────────
  Widget _buildLockScreen(Color gold, {bool needsReauth = false}) {
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
          if (needsReauth) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Volvé a ingresar el PIN: pasaron más de ${AdminAuthNotifier.miEmpresaReauthGrace.inMinutes} min desde la última vez que saliste de Mi Empresa, o revalidá para continuar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.black54,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () async {
              final hasAccess = await AdminGate.check(
                context,
                ref,
                forceVerification: needsReauth,
              );
              if (hasAccess && mounted) {
                _fetchOperadores();
                setState(() {
                  if (needsReauth) _needsMiEmpresaReauth = false;
                });
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

  static String _hudEstadoLiquidezLocal(FinanzasState state) {
    final cap = state.hudTotalIngresosHistoricoGlobal - state.hudTotalEgresosHistoricoGlobal;
    final proy = state.hudProyeccion30DiasLocal;
    if (proy < 0) return 'CRÍTICO: RIESGO DE INSOLVENCIA';
    if (cap > 0 && proy < cap * 0.2) return 'ADVERTENCIA: LIQUIDEZ BAJA';
    return 'SALUDABLE: FLUJO DE CAJA POSITIVO';
  }

  static Color _hudColorEstadoLiquidez(String status) {
    if (status.contains('CRÍTICO')) return const Color(0xFFE74C3C);
    if (status.contains('ADVERTENCIA')) return const Color(0xFFE67E22);
    return const Color(0xFF00B894);
  }

  String _hudLiquidezBadgeLabel(FinanzasState state) {
    final st = _hudEstadoLiquidezLocal(state);
    if (st.contains('CRÍTICO')) return 'Liquidez crítica · 30 días';
    if (st.contains('ADVERTENCIA')) return 'Liquidez ajustada · 30 días';
    return 'Flujo positivo';
  }

  bool _hudEsDiaCalendarioHoy(FinanzasState state) {
    if (state.fechaInteligenciaHud == null) return true;
    return ArTime.mismoDia(state.fechaInteligenciaHud!, ArTime.nowAr());
  }

  String _suffixDetalleDiaHud(FinanzasState state) {
    if (state.fechaInteligenciaHud == null || _hudEsDiaCalendarioHoy(state)) return 'hoy';
    return ArTime.formatFechaCorta(state.fechaInteligenciaHud!);
  }

  Future<void> _pickFechaInteligenciaHud(BuildContext context, FinanzasState state) async {
    final maxAr = ArTime.nowAr();
    final maxDay = DateTime(maxAr.year, maxAr.month, maxAr.day);
    var initial = state.fechaInteligenciaHud ?? maxDay;
    if (initial.isAfter(maxDay)) initial = maxDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: maxDay,
      helpText: 'Ver ingresos y egresos de ese día',
      cancelText: 'Cancelar',
      confirmText: 'Ver',
    );
    if (picked == null || !mounted) return;
    await ref.read(finanzasProvider.notifier).setFechaInteligenciaHud(picked);
  }

  Future<void> _exportarCierreCajaPdf(BuildContext context, FinanzasState state) async {
    if (state.hudModoInteligencia != FinanzasHudModo.hoy) return;
    final nAr = ArTime.nowAr();
    final hoyDia = DateTime(nAr.year, nAr.month, nAr.day);
    final diaNorm = state.fechaInteligenciaHud ?? hoyDia;
    try {
      await PdfService.generarCierreCajaPdf(
        diaCalendarioAr: diaNorm,
        ingresosDelDia: List<IngresoDetallado>.from(state.ingresosHoyLista),
        egresosDelDia: List<Egreso>.from(state.egresosHoyLista),
        totalIngresos: state.hudIngresosHoy,
        totalEgresos: state.hudEgresosHoy,
        ingresosEfectivo: state.hudIngresosHoyEfectivo,
        ingresosTransferencia: state.hudIngresosHoyTransferencia,
        emitidoPor: Supabase.instance.client.auth.currentUser?.email,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo generar el PDF de cierre: $e')),
        );
      }
    }
  }

  Widget _buildInteligenciaBarraDia(BuildContext context, FinanzasState state, bool isDark, Color gold, bool compact) {
    final fijo = state.fechaInteligenciaHud;
    final labelAr = fijo != null ? ArTime.formatFechaCorta(fijo) : ArTime.formatFechaCorta(ArTime.nowAr());
    final subt = fijo == null
        ? 'Tiempo real: totales del día según hora Argentina · tocá para elegir otro día'
        : (_hudEsDiaCalendarioHoy(state)
            ? 'Día fijado igual al calendario de hoy · tocá para cambiar'
            : 'Totales del día elegido (histórico) · tocá para cambiar');

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _pickFechaInteligenciaHud(context, state),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 8 : 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: gold.withValues(alpha: 0.38)),
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : gold.withValues(alpha: 0.07),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, size: compact ? 18 : 20, color: gold),
                      SizedBox(width: compact ? 8 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DÍA EN ANÁLISIS · $labelAr',
                              style: TextStyle(
                                fontSize: compact ? 9 : 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.85,
                                color: gold,
                              ),
                            ),
                            SizedBox(height: compact ? 2 : 4),
                            Text(
                              subt,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 8 : 10,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (fijo != null) ...[
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => ref.read(finanzasProvider.notifier).setFechaInteligenciaHud(null),
                          child: Text(
                            'AHORA',
                            style: TextStyle(
                              fontSize: compact ? 8 : 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: gold,
                            ),
                          ),
                        ),
                      ],
                      Icon(Icons.tune_rounded, size: compact ? 16 : 18, color: isDark ? Colors.white38 : Colors.black38),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            style: IconButton.styleFrom(
              padding: EdgeInsets.only(left: compact ? 2 : 4, top: compact ? 2 : 4),
              minimumSize: Size(compact ? 40 : 44, compact ? 40 : 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: 'Exportar cierre de caja (PDF) del día en análisis',
            onPressed: state.hudModoInteligencia == FinanzasHudModo.hoy ? () => _exportarCierreCajaPdf(context, state) : null,
            icon: Icon(
              Icons.picture_as_pdf_rounded,
              size: compact ? 22 : 24,
              color: gold.withValues(alpha: state.hudModoInteligencia == FinanzasHudModo.hoy ? 1 : 0.35),
            ),
          ),
        ],
      ),
    );
  }

  void _schedulePulsoScrollCentrarHoy(FinanzasState state, List<_DiaPulsoDatum> serie) {
    if (_pulsoRango != _PulsoRangoVista.mesCalendario || serie.isEmpty) return;
    final refMes = state.mesFiltro ?? ArTime.nowAr();
    final stamp = '${_pulsoRango.index}_${refMes.year}_${refMes.month}_${serie.length}';
    if (_pulsoScrollAppliedStamp == stamp) return;

    void attempt([int depth = 0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (depth > 28) {
          _pulsoScrollAppliedStamp = stamp;
          return;
        }
        if (!_pulsoBarrasScrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) => attempt(depth + 1));
          return;
        }
        final now = ArTime.nowAr();
        final idx = serie.indexWhere((d) => ArTime.mismoDia(d.dia, now));
        if (idx < 0) {
          _pulsoScrollAppliedStamp = stamp;
          return;
        }
        const colW = 26.0;
        const gap = 5.0;
        const step = colW + gap;
        final vp = _pulsoBarrasScrollController.position.viewportDimension;
        final max = _pulsoBarrasScrollController.position.maxScrollExtent;
        final ideal = idx * step - vp / 2 + step / 2;
        final offset = ideal.clamp(0.0, max);
        _pulsoBarrasScrollController.jumpTo(offset);
        _pulsoScrollAppliedStamp = stamp;
      });
    }

    attempt();
  }

  Widget _buildSaldoPrincipalBlock(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }) {
    const green = Color(0xFF00B894);
    const amber = Color(0xFFFFB74D);
    const violet = Color(0xFF6C63FF);
    final cap = state.hudPlataDelNegocio;
    final liquidezColor = _hudColorEstadoLiquidez(_hudEstadoLiquidezLocal(state));
    final liquidezLabel = _hudLiquidezBadgeLabel(state);

    Widget tarjetaSaldo({
      required String titulo,
      required String subtitulo,
      required double monto,
      required Color accent,
      required VoidCallback onTap,
      List<Widget>? chips,
      Widget? trailing,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: isDark ? 0.2 : 0.15),
                  accent.withValues(alpha: isDark ? 0.05 : 0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          fontSize: compact ? 9 : 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: accent,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                SizedBox(height: compact ? 4 : 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    monto.toCurrency(),
                    style: GoogleFonts.oswald(
                      fontSize: compact ? 22 : 30,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                if (chips != null) ...[
                  SizedBox(height: compact ? 6 : 8),
                  Wrap(spacing: 6, runSpacing: 4, children: chips),
                ],
                SizedBox(height: compact ? 4 : 6),
                Text(
                  subtitulo,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    height: 1.3,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tarjetaSaldo(
          titulo: 'SALDO DEL NEGOCIO',
          // La fórmula la desarrolla el panel en "EN QUÉ SE FUE", con los
          // montos reales. Acá alcanza con la advertencia que no es obvia:
          // es contable, no es lo que hay en el cajón.
          subtitulo: 'Contable, no es un arqueo físico. Tocá para ver en qué se fue',
          monto: cap,
          accent: green,
          onTap: () => _abrirDetalleEmpresa(context, state, isDark, gold),
          chips: [
            _medioChipMini('EF ${state.hudEfectivoNetoHistorico.toCurrency()}', green, isDark),
            _medioChipMini('TR ${state.hudTransferenciaNetaHistorica.toCurrency()}', violet, isDark),
          ],
          trailing: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 3 : 4),
            decoration: BoxDecoration(
              color: liquidezColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: liquidezColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              liquidezLabel,
              style: TextStyle(
                color: liquidezColor,
                fontSize: compact ? 8 : 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        tarjetaSaldo(
          titulo: 'MI BOLSILLO',
          // El subtítulo decía exactamente lo mismo que los chips, uno debajo
          // del otro. Los chips se quedan (se leen de un vistazo) y el
          // subtítulo pasa a explicar qué ES el número grande.
          subtitulo: 'Lo que apartaste para vos y todavía no gastaste',
          monto: state.hudRetiroPendienteTotal,
          accent: amber,
          onTap: () => _abrirHistorialBolsillo(context, state, isDark, gold),
          chips: [
            _medioChipMini('Aparté ${state.hudRetirosBolsaPersonalTotal.toCurrency()}', Colors.orange, isDark),
            _medioChipMini('Gasté ${state.hudGastadoPersonalTotal.toCurrency()}', green, isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildHudSectionDivider(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
          Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
        ],
      ),
    );
  }

  Widget _buildSaldoPorMedioSection(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Desglose por medio de pago',
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        Row(
          children: [
            Expanded(
              child: _hudTileIngresoHoyMedio(
                context: context,
                isDark: isDark,
                gold: gold,
                state: state,
                compact: compact,
                label: 'EFECTIVO',
                contexto: 'Saldo neto histórico',
                monto: state.hudEfectivoNetoHistorico,
                accent: const Color(0xFF00B894),
                icon: Icons.payments_outlined,
                bucket: '',
              ),
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: _hudTileIngresoHoyMedio(
                context: context,
                isDark: isDark,
                gold: gold,
                state: state,
                compact: compact,
                label: 'TRANSFERENCIA',
                contexto: 'Saldo neto histórico',
                monto: state.hudTransferenciaNetaHistorica,
                accent: const Color(0xFF6C63FF),
                icon: Icons.swap_horiz_rounded,
                bucket: '',
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(top: compact ? 6 : 8),
          child: Text(
            'Cobros menos gastos del negocio, separados por cómo se pagó. El total = saldo contable.',
            style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w600,
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.42),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _abrirDetalleCobrosHistoricos(context, state, isDark, gold),
            icon: Icon(Icons.receipt_long_rounded, size: compact ? 16 : 18, color: gold),
            label: Text(
              'Total cobrado histórico: ${state.hudTotalIngresosHistoricoGlobal.toCurrency()}',
              style: TextStyle(fontWeight: FontWeight.w800, color: gold, fontSize: compact ? 10 : 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperacionHoySection(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold, {
    required bool compact,
  }) {
    final fijo = state.fechaInteligenciaHud;
    final labelDia = fijo != null ? ArTime.formatFechaCorta(fijo) : ArTime.formatFechaCorta(ArTime.nowAr());
    final esHoy = _hudEsDiaCalendarioHoy(state);
    final neto = state.hudNetoDelDia;
    final resumenColapsado = state.hudIngresosHoy <= 0 && state.hudEgresosHoy <= 0
        ? (esHoy ? 'Sin movimientos hoy' : 'Sin movimientos ese día')
        : 'Cobré ${state.hudIngresosHoy.toCurrency()} · Salió ${state.hudEgresosHoy.toCurrency()} · Neto ${neto.toCurrency()}';

    Widget chipResumen(String lbl, double val, Color color) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.1 : 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lbl,
                style: TextStyle(fontSize: compact ? 8 : 9, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: color),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  val.toCurrency(),
                  style: GoogleFonts.oswald(
                    fontSize: compact ? 14 : 18,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: 0.25)),
        color: isDark ? Colors.white.withValues(alpha: 0.03) : gold.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _hudHoyExpanded = !_hudHoyExpanded),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14, vertical: compact ? 10 : 12),
                child: Row(
                  children: [
                    Icon(
                      _hudHoyExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: gold,
                      size: compact ? 20 : 22,
                    ),
                    SizedBox(width: compact ? 6 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            esHoy ? 'OPERACIÓN DE HOY · $labelDia' : 'OPERACIÓN DEL DÍA · $labelDia',
                            style: TextStyle(
                              fontSize: compact ? 9 : 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: gold,
                            ),
                          ),
                          if (!_hudHoyExpanded) ...[
                            const SizedBox(height: 3),
                            Text(
                              resumenColapsado,
                              style: TextStyle(
                                fontSize: compact ? 9 : 10,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_hudHoyExpanded) ...[
            Divider(height: 1, color: gold.withValues(alpha: 0.18)),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 14, compact ? 10 : 12, compact ? 12 : 14, compact ? 12 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildInteligenciaBarraDia(context, state, isDark, gold, compact),
                  SizedBox(height: compact ? 8 : 10),
                  Row(
                    children: [
                      chipResumen('COBRÉ', state.hudIngresosHoy, const Color(0xFF00B894)),
                      SizedBox(width: compact ? 6 : 8),
                      chipResumen('SALIÓ', state.hudEgresosHoy, const Color(0xFFE74C3C)),
                      SizedBox(width: compact ? 6 : 8),
                      chipResumen('NETO', neto, gold),
                    ],
                  ),
                  SizedBox(height: compact ? 10 : 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _hudTurnoSelector(state, isDark, gold, compact: compact),
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Row(
                    children: [
                      Expanded(
                        child: _hudTileIngresoHoyMedio(
                          context: context,
                          isDark: isDark,
                          gold: gold,
                          state: state,
                          compact: compact,
                          label: 'EFECTIVO',
                          contexto: 'Neto del día',
                          monto: state.hudEfectivoNetoHoy,
                          accent: const Color(0xFF00B894),
                          icon: Icons.payments_outlined,
                          bucket: 'efectivo',
                          retirosTurno: state.hudRetirosEfectivoHoy,
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: _hudTileIngresoHoyMedio(
                          context: context,
                          isDark: isDark,
                          gold: gold,
                          state: state,
                          compact: compact,
                          label: 'TRANSFERENCIA',
                          contexto: 'Neto del día',
                          monto: state.hudTransferenciaNetaHoy,
                          accent: const Color(0xFF6C63FF),
                          icon: Icons.swap_horiz_rounded,
                          bucket: 'transferencia',
                          retirosTurno: state.hudRetirosTransferenciaHoy,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 6 : 8),
                    child: Text(
                      'Los netos por medio restan salidas del turno elegido (mañana / tarde / día).',
                      style: TextStyle(
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w600,
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.42),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empresaDetalleLinea(String lbl, double monto, Color color, bool isDark, {bool negativo = false, String? nota}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lbl, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white54 : Colors.black54)),
              Text(
                '${negativo ? '−' : ''}${monto.toCurrency()}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
          if (nota != null) ...[
            const SizedBox(height: 2),
            Text(
              nota,
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
            ),
          ],
        ],
      ),
    );
  }

  Widget _medioChipMini(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  List<IngresoDetallado> _ingresosHoyPorMedioBucket(FinanzasState state, String bucket) {
    final items = state.ingresosHoyLista;
    switch (bucket) {
      case 'efectivo':
        return items.where((i) => i.medioPago?.toLowerCase().trim() != 'transferencia').toList();
      case 'transferencia':
        return items.where((i) => i.medioPago?.toLowerCase().trim() == 'transferencia').toList();
      default:
        return const [];
    }
  }

  void _abrirDetalleIngresosHoyPorMedio(BuildContext context, bool isDark, FinanzasState state, String bucket) {
    final list = _ingresosHoyPorMedioBucket(state, bucket);
    final total = list.fold<double>(0, (s, i) => s + i.monto);
    late final String titulo;
    late final String subtitulo;
    switch (bucket) {
      case 'efectivo':
        titulo = 'Ingresos en efectivo (${_suffixDetalleDiaHud(state)})';
        subtitulo =
            'Incluye efectivo explícito y lo demás que no sea transferencia (p. ej. sin medio en DB), movimientos del día seleccionado en Inteligencia financiera.';
        break;
      case 'transferencia':
        titulo = 'Ingresos por transferencia (${_suffixDetalleDiaHud(state)})';
        subtitulo = 'Cada ítem fue registrado con medio de pago transferencia.';
        break;
      default:
        titulo = '—';
        subtitulo = '';
    }
    const gold = Color(0xFFD4AF37);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.52,
          maxChildSize: 0.92,
          minChildSize: 0.32,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121218) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: GoogleFonts.oswald(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
                        const SizedBox(height: 6),
                        Text(subtitulo, style: TextStyle(fontSize: 12, height: 1.35, color: isDark ? Colors.white54 : Colors.black54)),
                        const SizedBox(height: 12),
                        Text(total.toCurrency(), style: GoogleFonts.oswald(fontSize: 28, fontWeight: FontWeight.w900, color: gold, letterSpacing: -0.5)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No hay movimientos en esta categoría para el día del análisis.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontWeight: FontWeight.w600),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final ing = list[index];
                              final quien = ing.alumnoOCliente.trim().isNotEmpty ? ing.alumnoOCliente : ing.nombreEvento;
                              final evLine = ing.nombreEvento.trim().isNotEmpty ? ' · ${ing.nombreEvento}' : '';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                  title: Text(ing.concepto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  subtitle: Text(
                                    '${ArTime.formatHora(ing.fecha)} · ${ing.fuente}$evLine\n$quien',
                                    style: TextStyle(fontSize: 12, height: 1.3, color: isDark ? Colors.white60 : Colors.black54),
                                  ),
                                  isThreeLine: true,
                                  trailing: Text(
                                    ing.monto.toCurrency(),
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _hudTileIngresoHoyMedio({
    required BuildContext context,
    required bool isDark,
    required Color gold,
    required FinanzasState state,
    required bool compact,
    required String label,
    required double monto,
    required Color accent,
    required IconData icon,
    required String bucket,
    String? contexto,
    double? retirosTurno,
  }) {
    final retiros = retirosTurno ?? 0.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: bucket.isEmpty ? null : () => _abrirDetalleIngresosHoyPorMedio(context, isDark, state, bucket),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 8 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
            color: accent.withValues(alpha: 0.07),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: compact ? 14 : 18, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: compact ? 9 : 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                            color: accent,
                          ),
                        ),
                        if (contexto != null)
                          Text(
                            contexto,
                            style: TextStyle(
                              fontSize: compact ? 8 : 9,
                              fontWeight: FontWeight.w700,
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.playlist_add_check_rounded, size: compact ? 14 : 16, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.22)),
                ],
              ),
              SizedBox(height: compact ? 4 : 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  monto.toCurrency(),
                  style: GoogleFonts.oswald(
                    fontSize: compact ? 15 : 34,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (retiros > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Retiros: −${retiros.toCurrency()}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE74C3C),
                    ),
                  ),
                ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tocá para ver cada movimiento',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.38)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Selector de turno (mañana/tarde/día) para los buckets netos del HUD.
  Widget _hudTurnoSelector(FinanzasState state, bool isDark, Color gold, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.copyWith(
                  labelLarge: TextStyle(fontSize: compact ? 10 : 11, fontWeight: FontWeight.w900),
                ),
          ),
          child: SegmentedButton<TurnoCaja>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity(
                horizontal: compact ? -3 : -2,
                vertical: compact ? -3 : -2,
              ),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 4 : 6),
              ),
            ),
            segments: const [
              ButtonSegment(
                value: TurnoCaja.manana,
                label: Text('MAÑ.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
              ButtonSegment(
                value: TurnoCaja.tarde,
                label: Text('TARDE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
              ButtonSegment(
                value: TurnoCaja.dia,
                label: Text('DÍA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ],
            selected: <TurnoCaja>{state.hudTurno},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              ref.read(finanzasProvider.notifier).setHudTurno(s.first);
            },
          ),
        ),
        Tooltip(
          message: 'Tocá para leer una guía breve',
          child: TextButton.icon(
            onPressed: () => _showAyudaTurnoInteligencia(context, gold),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 2, vertical: compact ? 2 : 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: gold.withValues(alpha: 0.92),
            ),
            icon: Icon(Icons.info_outline_rounded, size: compact ? 15 : 16),
            label: Text(
              '¿Qué es el turno aquí?',
              style: GoogleFonts.outfit(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAyudaTurnoInteligencia(BuildContext context, Color gold) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final muted = Theme.of(ctx).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.75)
            : Colors.black87;
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.schedule_rounded, color: gold, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¿Qué es el turno aquí?',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'En Inteligencia financiera, MAÑANA, TARDE y DÍA no filtran todo el panel por franja: solo indican en qué tramo horario se consideran los retiros de caja al calcular los netos de efectivo y transferencia (los bloques verde y violeta de abajo).\n\n'
              'Los totales del día (ingresos, egresos y neto que ves arriba) son siempre del día calendario completo.\n\n'
              'Si necesitás un cierre operativo de “solo mañana” o “solo tarde” con ingresos y movimientos de ese rango, usá la pantalla Cierre de caja: ahí el turno sí acota todo lo que ves.',
              style: TextStyle(height: 1.45, color: muted, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Entendido',
                style: TextStyle(fontWeight: FontWeight.w800, color: gold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHUD(BuildContext context, bool isDark, Color gold, FinanzasState state, {bool compact = false}) {
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;

    Widget header({required bool small}) {
      return Row(
        children: [
          Container(
            padding: EdgeInsets.all(small ? 8 : 10),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_wallet_outlined, color: gold, size: small ? 18 : 22),
          ),
          SizedBox(width: small ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESUMEN DE CAJA',
                  style: GoogleFonts.oswald(
                    fontSize: small ? 11 : 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w900,
                    color: gold,
                  ),
                ),
                Text(
                  small ? 'Negocio y bolsillo personal' : '¿Cuánta plata hay? Separá negocio y lo tuyo.',
                  style: TextStyle(
                    fontSize: small ? 9 : 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(small: compact),
        SizedBox(height: compact ? 10 : 16),
        _buildSaldoPrincipalBlock(context, state, isDark, gold, compact: compact),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('VER DESGLOSE Y HOY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: gold, letterSpacing: 1.5)),
            children: [
              _buildHudSectionDivider('DETALLE', isDark),
              SizedBox(height: compact ? 8 : 10),
              _buildSaldoPorMedioSection(context, state, isDark, gold, compact: compact),
              SizedBox(height: compact ? 10 : 14),
              _buildOperacionHoySection(context, state, isDark, gold, compact: compact),
            ],
          ),
        ),
      ],
    );

    if (compact) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gold.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(color: gold.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: body,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gold.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(color: gold.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: body,
    );
  }

  /// Panel MI BOLSILLO. Los movimientos salen del estado —que ya los trae— en
  /// vez de repetir el `getEgresosConEvento()` con JOIN en cada apertura.
  Future<void> _abrirHistorialBolsillo(BuildContext context, FinanzasState state, bool isDark, Color gold) async {
    const amber = Color(0xFFFFB74D);
    const teal = Color(0xFF26A69A);
    const violet = Color(0xFF6C63FF);
    void refrescar() => ref.read(finanzasProvider.notifier).recargar();

    await showPanelMovimientosSheet(
      context,
      ambito: AmbitoPanel.bolsillo,
      titulo: 'MI BOLSILLO',
      // "Lo que apartaste" ya lo dicen la tarjeta y la raya de abajo, con
      // números. Acá va para qué sirve: es el límite contra el que gastás.
      subtitulo: 'Tu límite: los gastos tuyos se descuentan de acá.',
      labelMonto: 'te queda disponible',
      isDark: isDark,
      accent: amber,
      // Todo lo que se muestra se relee del estado en cada rebuild: editando una
      // fila cambian la lista y estos números a la vez.
      datos: (s) {
        final apartado = s.hudRetirosBolsaPersonalTotal;
        final gastadoPropio = s.hudGastadoPersonalTotal - s.hudGastosPersonalEmpresaTotal;
        final delNegocio = s.hudGastosPersonalEmpresaTotal;
        return PanelDatosMovimientos(
          monto: s.hudRetiroPendienteTotal,
          egresos: s.egresosHistoricosLista,
          // La raya: de dónde sale el monto grande. No repite "te quedan" — ese
          // es justamente el número que está arriba en grande. Si algo salió
          // directo del negocio va aparte, nunca sumado a lo que salió de tu
          // bolsillo.
          notaRaya:
              'Apartaste ${apartado.toCurrency()} y gastaste ${gastadoPropio.toCurrency()}.'
              '${delNegocio > 0.01 ? '\nAparte, ${delNegocio.toCurrency()} de gastos tuyos salieron directo del negocio.' : ''}',
          // Solo el desglose por medio: "Aparté" y "Gasté" ya están en la raya,
          // dos centímetros más arriba.
          chips: [
            ChipResumen('Gasté en efectivo', s.hudGastosBolsaPersonalEfectivo, teal),
            ChipResumen('Gasté por transferencia', s.hudGastosBolsaPersonalTransferencia, violet),
          ],
        );
      },
      acciones: [
        AccionPanel(
          // Mismo movimiento que "APARTAR PARA MÍ" en el panel del negocio,
          // pero nombrado desde este lado: acá la plata no sale, entra. Decir
          // "apartar" mirando el bolsillo suena a separar algo de lo que ya
          // tenés, que es lo contrario de lo que hace.
          label: 'TRAER DEL NEGOCIO',
          icon: Icons.south_west_rounded,
          color: amber,
          colorTexto: Colors.black87,
          abrir: (ctx) => showDialog<bool>(
            context: ctx,
            builder: (_) => const RetiroBolsilloPersonalDialog(),
          ),
        ),
        AccionPanel(
          label: 'REGISTRAR GASTO',
          icon: Icons.remove_circle_outline_rounded,
          color: teal,
          abrir: (ctx) => showDialog<bool>(
            context: ctx,
            builder: (_) => const GastoPersonalDialog(),
          ),
        ),
      ],
      onRefresh: refrescar,
    );
  }

  void _abrirDetalleCobrosHistoricos(BuildContext context, FinanzasState state, bool isDark, Color gold) {
    const green = Color(0xFF00B894);
    final list = state.ingresosHistoricosLista;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.58,
          maxChildSize: 0.92,
          minChildSize: 0.35,
          builder: (_, scrollCtrl) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121218) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(color: gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL COBRADO (HISTÓRICO)',
                          style: GoogleFonts.oswald(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: gold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Suma de todos los cobros registrados, sin restar gastos ni retiros.',
                          style: TextStyle(fontSize: 12, height: 1.35, color: isDark ? Colors.white54 : Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.hudTotalIngresosHistoricoGlobal.toCurrency(),
                          style: GoogleFonts.oswald(fontSize: 28, fontWeight: FontWeight.w900, color: gold),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _medioChipMini('EF ${state.hudTotalIngresosHistoricoEfectivo.toCurrency()}', green, isDark),
                            _medioChipMini(
                              'TR ${state.hudTotalIngresosHistoricoTransferencia.toCurrency()}',
                              const Color(0xFF6C63FF),
                              isDark,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Text(
                              'No hay cobros registrados.',
                              style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontWeight: FontWeight.w600),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final ing = list[index];
                              final quien = ing.alumnoOCliente.trim().isNotEmpty ? ing.alumnoOCliente : ing.nombreEvento;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                                ),
                                child: ListTile(
                                  title: Text(ing.concepto, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                  subtitle: Text(
                                    '${ArTime.formatFechaCorta(ing.fecha)} · $quien',
                                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                                  ),
                                  trailing: Text(
                                    ing.monto.toCurrency(),
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Panel SALDO DEL NEGOCIO: mismo widget que MI BOLSILLO, con sus acciones y
  /// su historial. Antes era un modal de solo lectura — la tarjeta de $0 tenía
  /// botones y la de los millones no.
  void _abrirDetalleEmpresa(BuildContext context, FinanzasState state, bool isDark, Color gold) {
    const green = Color(0xFF00B894);
    const red = Color(0xFFE74C3C);
    const amber = Color(0xFFFFB74D);
    const violet = Color(0xFF6C63FF);
    void refrescar() => ref.read(finanzasProvider.notifier).recargar();

    showPanelMovimientosSheet(
      context,
      ambito: AmbitoPanel.negocio,
      titulo: 'SALDO DEL NEGOCIO',
      // Que es contable ya lo dicen la tarjeta y el rótulo del monto. Acá va lo
      // único que falta y no es obvio: contra qué hay que compararlo.
      subtitulo: 'Compará este número con lo que hay en caja, banco y cofre.',
      labelMonto: 'saldo contable',
      isDark: isDark,
      accent: green,
      datos: (s) => PanelDatosMovimientos(
        monto: s.hudPlataDelNegocio,
        egresos: s.egresosHistoricosLista,
        // Sin chip "Salió del negocio": ese número ya aparecía dos veces más
        // abajo en la misma pantalla —abierto por rubro en "EN QUÉ SE FUE", y
        // otra vez como neto al pie del historial—. Tres veces la misma cifra.
        chips: [
          ChipResumen('Efectivo', s.hudEfectivoNetoHistorico, green),
          ChipResumen('Transferencia', s.hudTransferenciaNetaHistorica, violet),
          ChipResumen('Total cobrado', s.hudTotalIngresosHistoricoGlobal, gold),
        ],
      ),
      acciones: [
        AccionPanel(
          label: 'REGISTRAR PAGO',
          icon: Icons.remove_circle_outline_rounded,
          color: red,
          abrir: (ctx) => showDialog<bool>(
            context: ctx,
            builder: (_) => const RegistrarEgresoGlobalDialog(),
          ),
        ),
        // Apartar plata vive solo en MI BOLSILLO ("TRAER DEL NEGOCIO").
        // Gasto y operador son el mismo egreso: un solo formulario con buscador.
      ],
      extras: (s) => [
        const SizedBox(height: 18),
        _desgloseSalidas(s, isDark, gold, red, amber),
        const SizedBox(height: 10),
        _liquidacionPorOperador(context, s, isDark, gold),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => _abrirDetalleCobrosHistoricos(context, s, isDark, gold),
          icon: Icon(Icons.receipt_long_rounded, size: 18, color: gold),
          // Sin el monto: ya está en el chip "Total cobrado", ahí arriba.
          label: Text(
            'Ver el detalle de los cobros',
            style: TextStyle(fontWeight: FontWeight.w800, color: gold, fontSize: 12),
          ),
        ),
      ],
      onRefresh: refrescar,
    );
  }

  /// En qué se fue la plata, abierto por categoría.
  ///
  /// El total suelto de "gastos operativos" mezcla un pago a proveedor con un
  /// `Retiro de caja`, que no compra nada: solo mueve plata del cajón del turno
  /// a la oficina. Verlo separado es lo que permite decidir si eso tiene que
  /// seguir restando del saldo.
  Widget _desgloseSalidas(
    FinanzasState state,
    bool isDark,
    Color gold,
    Color red,
    Color amber,
  ) {
    final porCategoria = state.hudGastosOperativosPorCategoria;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EN QUÉ SE FUE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          const SizedBox(height: 10),
          for (final e in porCategoria.entries)
            _empresaDetalleLinea(
              e.key,
              e.value,
              e.key.trim() == kCategoriaRetiroCaja ? amber : red,
              isDark,
              negativo: true,
              nota: e.key.trim() == kCategoriaRetiroCaja
                  ? 'Salió del cajón del turno, no se gastó. Hoy resta igual.'
                  : null,
            ),
          if (state.hudGastosPersonalEmpresaTotal > 0.01)
            _empresaDetalleLinea(
              'Gastos personales tuyos',
              state.hudGastosPersonalEmpresaTotal,
              red,
              isDark,
              negativo: true,
              nota: 'Salieron directo del negocio, sin pasar por tu bolsillo.',
            ),
          if (state.hudRetirosBolsaPersonalTotal > 0.01)
            // Es TODO lo apartado, no lo que quedó sin gastar: sale del negocio
            // igual lo hayas gastado o no. Decía "Retiros sin gastar" mientras
            // la tarjeta MI BOLSILLO mostraba otro número por lo mismo.
            //
            // Sin la nota de cuánto queda sin gastar: eso es estado del
            // bolsillo y ya lo dice su propio panel.
            _empresaDetalleLinea(
              'Aparté para mí',
              state.hudRetirosBolsaPersonalTotal,
              amber,
              isDark,
              negativo: true,
            ),
        ],
      ),
    );
  }

  /// Un solo control de período: dice qué estás viendo y abre el calendario.
  ///
  /// Reemplaza la fila de 6 chips de meses, que tenía tres problemas: solo
  /// llegaba 6 meses atrás (marzo se caía de la lista el mes siguiente), no
  /// mostraba en qué meses hay movimientos, y la salida a "ver todo" era un
  /// embudo tachado que aparecía a veces. Ese filtro invisible es el que dejaba
  /// pantallas en blanco con datos detrás.
  Widget _buildFiltroMeses(bool isDark, Color gold, FinanzasState state) {
    final rango = _rangoDesdeEstado(state);
    final hayFiltro = !rango.esTodo || state.eventoIdFiltro != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _abrirSelectorPeriodo(context, state, isDark, gold),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: hayFiltro
                      ? gold.withValues(alpha: 0.14)
                      : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hayFiltro
                        ? gold.withValues(alpha: 0.5)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 15, color: gold),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        rango.etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: hayFiltro ? gold : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more_rounded, size: 16, color: gold.withValues(alpha: 0.7)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hayFiltro)
          IconButton(
            style: _finanzasIconButtonStyle(),
            icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white54 : Colors.black54),
            tooltip: 'Ver todo el historial',
            onPressed: () => ref.read(finanzasProvider.notifier).aplicarFiltro(
                  clearMes: true,
                  clearEvento: true,
                  clearFechaExacta: true,
                ),
          ),
      ],
    );
  }

  /// Traduce el filtro del provider al recorte que entiende el calendario.
  RangoFiltroMovimientos _rangoDesdeEstado(FinanzasState state) {
    final mes = state.mesFiltro;
    if (mes == null) return const RangoFiltroMovimientos.todo();
    return RangoFiltroMovimientos(
      mes: DateTime(mes.year, mes.month),
      dia: state.fechaExactaFiltro,
    );
  }

  void _abrirSelectorPeriodo(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold,
  ) {
    // Los días que se marcan salen de ingresos Y egresos: el filtro manda
    // sobre las dos listas, así que un día con un cobro tiene que verse
    // aunque no haya habido gastos.
    final fechas = <DateTime>[
      for (final i in state.ingresosHistoricosLista) i.fecha,
      for (final e in state.egresosHistoricosLista)
        if (e.fecha != null) e.fecha!,
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121218) : const Color(0xFFFCF9F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gold.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'QUÉ PERÍODO MIRAR',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tocá un día para ver ese día, el nombre del mes para el mes entero, '
              'o TODO para el historial completo.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            CalendarioFiltroMovimientos(
              fechas: fechas,
              valor: _rangoDesdeEstado(state),
              isDark: isDark,
              accent: gold,
              onChanged: (r) {
                Navigator.of(ctx).pop();
                final notifier = ref.read(finanzasProvider.notifier);
                if (r.esTodo) {
                  notifier.aplicarFiltro(clearMes: true, clearFechaExacta: true);
                } else if (r.dia != null) {
                  notifier.aplicarFiltro(mes: r.mes, fechaExactaFiltro: r.dia);
                } else {
                  notifier.aplicarFiltro(mes: r.mes, clearFechaExacta: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── VISTA RENTABILIDAD BASE ────────────────────────────────────────────────
  Widget _buildVistaAvisos(bool isDark, Color gold) {
    return AvisosView(isDark: isDark, gold: gold);
  }

  static const List<String> _diaCortoEs = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  /// Próximos avisos pendientes: horizontal; tap → [PagarAvisoDialog] (registrar pago).
  Widget _buildProximosAvisosCarrusel(BuildContext context, bool isDark, Color gold) {
    final asyncObl = ref.watch(obligacionesProvider);

    return asyncObl.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: const LinearProgressIndicator(minHeight: 3),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (List<ObligacionPago> list) {
        final pendientes = list.where((o) => o.estado == 'pendiente').toList()
          ..sort((a, b) => a.fechaVencimiento.compareTo(b.fechaVencimiento));
        if (pendientes.isEmpty) return const SizedBox.shrink();

        final now = DateTime.now();
        final hoy = DateTime(now.year, now.month, now.day);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 18, color: gold.withValues(alpha: 0.9)),
                const SizedBox(width: 8),
                Text(
                  'PRÓXIMOS AVISOS · Toca para registrar pago',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.05,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: pendientes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final ObligacionPago o = pendientes[i];
                  final fv = DateTime(o.fechaVencimiento.year, o.fechaVencimiento.month, o.fechaVencimiento.day);
                  final dias = fv.difference(hoy).inDays;
                  final Color accent;
                  final String urgencia;
                  if (dias < 0) {
                    accent = Colors.redAccent;
                    urgencia = 'Vencido · hace ${dias.abs()} día(s)';
                  } else if (dias == 0) {
                    accent = Colors.deepOrangeAccent;
                    urgencia = 'Vence hoy';
                  } else if (dias <= 3) {
                    accent = Colors.orangeAccent;
                    urgencia = 'En $dias día(s)';
                  } else {
                    accent = gold;
                    urgencia = 'En $dias día(s)';
                  }
                  final isEmpresa = o.tipoObligacion == 'empresa';
                  final diasSem = _diaCortoEs[fv.weekday - 1];
                  final fechaTxt =
                      '${fv.day.toString().padLeft(2, '0')}/${fv.month.toString().padLeft(2, '0')}/${fv.year}';
                  final montoLbl = o.montoEstimado > 0.01 ? o.montoEstimado.toCurrency() : 'Monto libre';

                  return SizedBox(
                    width: min(274.0, MediaQuery.sizeOf(context).width * 0.82),
                    child: Material(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) => PagarAvisoDialog(obligacion: o),
                          );
                          if (!context.mounted) return;
                          await ref.read(finanzasProvider.notifier).recargar();
                          await ref.read(obligacionesProvider.notifier).refresh();
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isEmpresa ? Icons.domain_rounded : Icons.home_outlined,
                                    size: 16,
                                    color: isEmpresa ? Colors.blueAccent : Colors.purpleAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      o.titulo.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.oswald(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$urgencia · $diasSem $fechaTxt',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                isEmpresa ? 'Empresa · $montoLbl' : 'Adrián (Casa) · $montoLbl',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Contenido principal ────────────────────────────────────────────────────
  Widget _buildContent(bool isDark, Color gold, FinanzasState state) {
    final query = _masterSearchCtrl.text.trim();
    final isSearching = query.isNotEmpty;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(finanzasProvider.notifier).recargar();
        await ref.read(obligacionesProvider.notifier).refresh();
      },
      color: gold,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // Dos columnas solo con ventana cómoda; en 1080p apilado si está muy angosto.
          final isWide = w >= 1000;
          // Tablas apretadas solo cuando hay split ingresos|egresos y el ancho total es limitado.
          final compactSplitTables = _searchContext == SearchContext.todos && w < 1320;
          // Sin tope artificial 880: usa casi todo el ancho útil para no dejar “media pantalla vacía”.
          const horizontalInset = 40.0;
          final usableW = (w - horizontalInset).clamp(320.0, double.infinity);
          final contentMaxW = isWide ? min(1480.0, usableW) : usableW;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxW),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── CABECERA PERMANENTE (Filtros + Buscador) ──
                    _buildFiltroMeses(isDark, gold, state),
                    if (state.fechaExactaFiltro != null) ...[
                      const SizedBox(height: 12),
                      _buildChipViendoDia(isDark, gold, state),
                    ],
                    const SizedBox(height: 16),
                    _buildBuscadorMaestro(isDark, gold),
                    const SizedBox(height: 20),
                    
                    // ── CONTROLES DE VISTA INTERNA ──
                    if (!isSearching) ...[
                      Center(
                        child: SegmentedButton<FinanzasSubView>(
                          segments: const [
                            ButtonSegment(value: FinanzasSubView.salud, label: Text('SALUD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                            ButtonSegment(value: FinanzasSubView.flujo, label: Text('FLUJO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                            ButtonSegment(value: FinanzasSubView.categorias, label: Text('HOY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                            ButtonSegment(value: FinanzasSubView.avisos, label: Text('AVISOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                          ],
                          selected: {_currentSubView},
                          onSelectionChanged: (Set<FinanzasSubView> newSelection) {
                            setState(() {
                              _currentSubView = newSelection.first;
                            });
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) return gold.withValues(alpha: 0.2);
                              return Colors.transparent;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.selected)) return gold;
                              return isDark ? Colors.white54 : Colors.black54;
                            }),
                            side: WidgetStateProperty.all(BorderSide(color: gold.withValues(alpha: 0.3))),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildProximosAvisosCarrusel(context, isDark, gold),
                      const SizedBox(height: 12),
                    ],

                    // ── HUD Adaptativo (Siempre visible si hay búsqueda, o arriba de todo) ──
                    _buildHUD(context, isDark, gold, state, compact: isSearching),
                    const SizedBox(height: 16),

                    if (isSearching || _currentSubView == FinanzasSubView.flujo) ...[
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
                                    _buildIngresosLista(isDark, gold, const Color(0xFF00B894), _ingresosVista(state), isHalf: compactSplitTables),
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
                                    _buildEgresosLista(isDark, gold, const Color(0xFFE74C3C), _egresosVista(state), isHalf: compactSplitTables),
                                  ],
                                ),
                              ),
                          ],
                        )
                      else ...[
                        if (_searchContext != SearchContext.egresos) ...[
                          _sectionLabel('INGRESOS RECIENTES', Icons.add_card_rounded),
                          const SizedBox(height: 12),
                          _buildIngresosLista(isDark, gold, const Color(0xFF00B894), _ingresosVista(state), isHalf: false),
                          const SizedBox(height: 28),
                        ],
                        if (_searchContext != SearchContext.ingresos) ...[
                          _sectionLabel('EGRESOS REGISTRADOS', Icons.receipt_long_outlined),
                          const SizedBox(height: 12),
                          _buildEgresosLista(isDark, gold, const Color(0xFFE74C3C), _egresosVista(state), isHalf: false),
                        ],
                      ],
                    ] else if (_currentSubView == FinanzasSubView.salud) ...[
                      // ── VISTA SALUD ──
                      _buildVistaSalud(isDark, gold, state),
                    ] else if (_currentSubView == FinanzasSubView.categorias) ...[
                      _buildVistaCategorias(isDark, gold, state),
                    ] else if (_currentSubView == FinanzasSubView.avisos) ...[
                      _buildVistaAvisos(isDark, gold),
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

  Widget _buildChipViendoDia(bool isDark, Color gold, FinanzasState state) {
    final d = state.fechaExactaFiltro!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(finanzasProvider.notifier).aplicarFiltro(
              mes: state.mesFiltro,
              clearFechaExacta: true,
            ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: gold.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 16, color: gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Viendo: ${ArTime.formatDiaMes(d)} · Tocá para volver al mes completo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.close_rounded, size: 18, color: gold),
            ],
          ),
        ),
      ),
    );
  }

  // ── HERO: Score de Salud Financiera 0-100 ─────────────────────────────────
  /// Tarjeta principal de la vista SALUD: gauge circular con score compuesto
  /// (liquidez + margen + momentum + alertas), 4 pilares desglosados y un
  /// bloque con runway en meses.
  Widget _buildHealthScoreHero(
    bool isDark,
    Color gold,
    FinanzasState state, {
    Key? runwayKey,
    void Function(_SaludPillarTap)? onPillarTap,
  }) {
    final healthScoreAsync = ref.watch(healthScoreProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);

    return healthScoreAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
        ),
      ),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Error al calcular salud financiera: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
      data: (hs) {
        final stats = statsAsync.maybeWhen(
          data: (s) => s,
          orElse: () => null,
        );

        final Color scoreColor;
        final String scoreLabel;
        final String scoreAdvice;
        final IconData scoreIcon;

        if (hs.score < 40) {
          scoreColor = const Color(0xFFE74C3C);
          scoreLabel = 'CRÍTICO';
          scoreIcon = Icons.warning_amber_rounded;
          scoreAdvice = hs.runwayMeses >= 999 
              ? 'Atención: Nivel de alertas críticas elevado. Conviene revisar pagos pendientes urgente.'
              : 'Peligro: Tus reservas duran ${hs.runwayMeses.toStringAsFixed(1).replaceAll('.', ',')} meses. Conviene acelerar cobros o recortar gastos fijos urgente.';
        } else if (hs.score < 70) {
          scoreColor = const Color(0xFFF39C12);
          scoreLabel = 'AJUSTADO';
          scoreIcon = Icons.visibility_outlined;
          scoreAdvice = hs.runwayMeses >= 999
              ? 'Ajustado: Tenés alertas pendientes o ingresos en descenso. Conviene revisar vencimientos.'
              : 'Ajustado: Tenés reservas para ${hs.runwayMeses.toStringAsFixed(1).replaceAll('.', ',')} meses. Es buen momento para activar cobros pendientes o impulsar ventas.';
        } else {
          scoreColor = const Color(0xFF00B894);
          scoreLabel = 'SALUDABLE';
          scoreIcon = Icons.favorite_rounded;
          scoreAdvice = hs.runwayMeses >= 999
              ? 'Excelente: Operaciones al día y sin alertas pendientes.'
              : 'Excelente: Tenés reservas para ${hs.runwayMeses.toStringAsFixed(1).replaceAll('.', ',')} meses. Podés planificar inversiones o crecer con total tranquilidad.';
        }

        final cardBg = isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scoreColor.withValues(alpha: 0.45), 
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: scoreColor.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.monitor_heart_outlined, color: gold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SALUD FINANCIERA',
                      style: GoogleFonts.oswald(
                        fontSize: 14,
                        letterSpacing: 2.2,
                        color: gold,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Estado general conversacional
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: scoreColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(scoreIcon, size: 14, color: Colors.black),
                              const SizedBox(width: 6),
                              Text(
                                scoreLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Puntaje General: ${hs.score.toStringAsFixed(0)} / 100',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      scoreAdvice,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Fila de Tarjetas Métricas
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth >= 720;
                  final cards = [
                    _buildMetricCard(
                      icon: Icons.shield_outlined,
                      title: 'Fondo de respaldo (Caja)',
                      value: hs.runwayMeses >= 999 
                          ? 'Sin límite' 
                          : hs.runwayMeses >= 99 
                              ? '99+ meses' 
                              : '${hs.runwayMeses.toStringAsFixed(1).replaceAll('.', ',')} meses',
                      subtitle: 'de tranquilidad',
                      description: 'Dinero en caja para cubrir costos fijos si no ingresan nuevos cobros.',
                      color: hs.liquidez >= 20 ? const Color(0xFF00B894) : (hs.liquidez >= 10 ? const Color(0xFFF39C12) : const Color(0xFFE74C3C)),
                      isDark: isDark,
                      onTap: onPillarTap != null ? () => onPillarTap(_SaludPillarTap.liquidez) : null,
                    ),
                    _buildMetricCard(
                      icon: Icons.monetization_on_outlined,
                      title: 'Dinero libre (Ganancia)',
                      value: '${(hs.margenPct * 100).toStringAsFixed(1).replaceAll('.', ',')}%',
                      subtitle: 'de lo cobrado',
                      description: 'Porcentaje de los cobros totales que te queda libre después de restar gastos.',
                      color: hs.margen >= 20 ? const Color(0xFF00B894) : (hs.margen >= 10 ? const Color(0xFFF39C12) : const Color(0xFFE74C3C)),
                      isDark: isDark,
                      onTap: onPillarTap != null ? () => onPillarTap(_SaludPillarTap.margen) : null,
                    ),
                    _buildMetricCard(
                      icon: Icons.trending_up_rounded,
                      title: 'Comparativa de ingresos',
                      value: '${hs.deltaIngPct >= 0 ? '+' : ''}${(hs.deltaIngPct * 100).abs().toStringAsFixed(1).replaceAll('.', ',')}%',
                      subtitle: hs.deltaIngPct >= 0 ? 'de crecimiento' : 'de descenso',
                      description: 'Variación de la facturación comparando los cobros de este mes con el anterior.',
                      color: hs.momentum >= 15 ? const Color(0xFF00B894) : (hs.momentum >= 8 ? const Color(0xFFF39C12) : const Color(0xFFE74C3C)),
                      isDark: isDark,
                      onTap: onPillarTap != null ? () => onPillarTap(_SaludPillarTap.momentum) : null,
                    ),
                    _buildMetricCard(
                      icon: Icons.notifications_active_outlined,
                      title: 'Pendientes y deudas',
                      value: '${hs.alertasCount}',
                      subtitle: hs.alertasCount == 1 ? 'tema por revisar' : 'temas por revisar',
                      description: 'Alertas críticas de deudas vencidas o cobros atrasados que requieren atención.',
                      color: hs.alertasCount == 0 ? const Color(0xFF00B894) : (hs.alertasCount <= 3 ? const Color(0xFFF39C12) : const Color(0xFFE74C3C)),
                      isDark: isDark,
                      onTap: onPillarTap != null ? () => onPillarTap(_SaludPillarTap.alertas) : null,
                    ),
                  ];

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: cards.map((c) => Expanded(child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: c,
                      ))).toList(),
                    );
                  }

                  return Column(
                    children: cards.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: c,
                    )).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),

              // DETALLE DE ORIGEN (De dónde vienen los números)
              _buildOriginDetailSection(isDark, gold, state, stats),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required String description,
    required Color color,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.015);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04);

    return MouseRegion(
      cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: GoogleFonts.oswald(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.white30 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOriginDetailSection(
    bool isDark,
    Color gold,
    FinanzasState state,
    DashboardStats? stats,
  ) {
    // 1. Agrupar cobros del mes por evento
    final mapIngresos = <String, double>{};
    for (final ing in state.ingresos) {
      final name = ing.nombreEvento.trim().isNotEmpty ? ing.nombreEvento : 'Otros / Varios';
      mapIngresos[name] = (mapIngresos[name] ?? 0.0) + ing.monto;
    }
    final sortedIngresos = mapIngresos.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 2. Deudas por institución
    final deudas = stats?.deudasPorInstitucion ?? [];

    final containerBg = isDark ? Colors.white.withValues(alpha: 0.015) : Colors.black.withValues(alpha: 0.01);
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats_rounded, color: gold, size: 16),
              const SizedBox(width: 8),
              Text(
                'DETALLE DE ORIGEN (De dónde vienen los números)',
                style: GoogleFonts.oswald(
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w900,
                  color: gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isWide = constraints.maxWidth >= 600;

              final cobrosPanel = _buildOriginCobrosPanel(sortedIngresos, isDark, gold);
              final deudasPanel = _buildOriginDeudasPanel(deudas, isDark, gold);

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: cobrosPanel),
                    Container(
                      width: 1.5,
                      height: 240,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      color: dividerColor,
                    ),
                    Expanded(child: deudasPanel),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cobrosPanel,
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Divider(color: dividerColor, height: 1),
                  ),
                  deudasPanel,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOriginCobrosPanel(List<MapEntry<String, double>> ingresos, bool isDark, Color gold) {
    if (ingresos.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('¿Qué cobramos este mes?', Icons.payments_outlined, gold),
          const SizedBox(height: 16),
          Text(
            'No hay cobros registrados en el mes seleccionado.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white30 : Colors.black45,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('¿Qué cobramos este mes?', Icons.payments_outlined, gold),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ingresos.length > 5 ? 5 : ingresos.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final entry = ingresos[i];
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.arrow_circle_down_rounded, size: 12, color: const Color(0xFF00B894)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  entry.value.toCurrency(),
                  style: GoogleFonts.oswald(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            );
          },
        ),
        if (ingresos.length > 5) ...[
          const SizedBox(height: 8),
          Text(
            '+ ${ingresos.length - 5} eventos más en el listado inferior.',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white30 : Colors.black45,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOriginDeudasPanel(List<InstitucionDeuda> deudas, bool isDark, Color gold) {
    if (deudas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('¿Quiénes nos deben?', Icons.account_balance_outlined, gold),
          const SizedBox(height: 16),
          Text(
            '¡Excelente! No hay deudas pendientes registradas en la calle hoy.',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark ? const Color(0xFF00B894) : Colors.green.shade700,
            ),
          ),
        ],
      );
    }

    final double totalEnLaCalle = deudas.fold(0.0, (s, d) => s + d.saldoGlobal);
    final int conVencido = deudas.where((d) => d.vencido > 0.01).length;
    final int conPorVencer = deudas.where((d) => d.vencido <= 0.01 && d.aVencer > 0.01).length;
    final int nMasivos = deudas.where((d) => d.esMasivo).length;
    final int nParticulares = deudas.length - nMasivos;

    // Filtrar por búsqueda
    final query = _deudasSearchCtrl.text.trim().toLowerCase();
    final List<InstitucionDeuda> filtradas = query.isEmpty
        ? deudas
        : deudas.where((d) => d.nombre.toLowerCase().contains(query)).toList();

    // Si no está expandido y no hay búsqueda, solo mostrar las que tienen vencido (urgentes)
    final bool mostrarLista = _deudasExpanded || query.isNotEmpty;
    final List<InstitucionDeuda> visibles = mostrarLista ? filtradas : filtradas.where((d) => d.vencido > 0.01 || d.aVencer > 0.01).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panelHeader('¿Quiénes nos deben?', Icons.account_balance_outlined, gold),
        const SizedBox(height: 12),

        // ── Resumen compacto ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: gold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gold.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL EN LA CALLE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: gold,
                    ),
                  ),
                  Text(
                    totalEnLaCalle.toCurrency(),
                    style: GoogleFonts.oswald(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: gold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    // "instituciones" solo era cierto para las escuelas: la
                    // otra mitad son familias de recepciones particulares.
                    [
                      if (nMasivos > 0)
                        '$nMasivos ${nMasivos == 1 ? "escuela" : "escuelas"}',
                      if (nParticulares > 0)
                        '$nParticulares ${nParticulares == 1 ? "particular" : "particulares"}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                  if (conVencido > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE74C3C).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$conVencido con vencido',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE74C3C),
                        ),
                      ),
                    ),
                  ],
                  if (conPorVencer > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        // Es UNA cuota, la inmediata: el cálculo corta en la
                        // primera que vence dentro de 30 días. "Por vencer" a
                        // secas se leía como todo lo que viene.
                        '$conPorVencer con próxima cuota',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Buscador ──
        SizedBox(
          height: 36,
          child: TextField(
            controller: _deudasSearchCtrl,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar institución...',
              hintStyle: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: gold.withValues(alpha: 0.6)),
              suffixIcon: _deudasSearchCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () => setState(() => _deudasSearchCtrl.clear()),
                      child: Icon(Icons.close_rounded, size: 14, color: isDark ? Colors.white30 : Colors.black26),
                    )
                  : null,
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: gold.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ── Lista, partida por tipo de negocio ──
        // Una escuela con cuotas a meses y una recepción que se paga de una no
        // se leen igual: mezclarlas obligaba a adivinar cuál era cuál.
        if (query.isNotEmpty && filtradas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No se encontró ningún cliente con "$query".',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
            ),
          )
        else ...[
          _bloqueDeuda(
            'ESCUELAS · eventos masivos',
            visibles.where((d) => d.esMasivo).toList(),
            isDark,
            gold,
          ),
          _bloqueDeuda(
            'PARTICULARES · recepciones',
            visibles.where((d) => !d.esMasivo).toList(),
            isDark,
            gold,
          ),
        ],

        // ── Botón expandir/colapsar ──
        if (query.isEmpty && deudas.length > 3) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _deudasExpanded = !_deudasExpanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _deudasExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: gold.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _deudasExpanded ? 'Ver menos' : 'Ver los ${deudas.length} clientes',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: gold.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Cuánto se le pagó a cada operador, de mayor a menor.
  ///
  /// Responde "¿cuánto le pagué a Juan?", que el historial cronológico no
  /// contesta: ahí los pagos quedan mezclados con el alquiler y los proveedores.
  /// Entran `Personal` (lo que guarda el formulario) y `Operadores` (el combo
  /// viejo), para no partir el historial de Juan.
  /// Vivía en la pestaña PERSONAL, que leía `state.egresos` —recortado al mes
  /// del filtro— y por eso decía "SIN PAGOS REGISTRADOS" aunque hubiera
  /// millones pagados en meses anteriores. Acá lee la lista histórica.
  Widget _liquidacionPorOperador(
    BuildContext context,
    FinanzasState state,
    bool isDark,
    Color gold,
  ) {
    const azul = Color(0xFF3498DB);

    final porOperador = <String, List<Egreso>>{};
    for (final e in state.egresosHistoricosLista) {
      if (!esCategoriaOperador(e.categoria)) continue;
      porOperador
          .putIfAbsent(e.proveedorVisible ?? 'Sin nombre', () => [])
          .add(e);
    }
    if (porOperador.isEmpty) return const SizedBox.shrink();

    final ordenados = porOperador.entries.toList()
      ..sort((a, b) {
        final ta = a.value.fold<double>(0, (s, e) => s + e.monto);
        final tb = b.value.fold<double>(0, (s, e) => s + e.monto);
        return tb.compareTo(ta);
      });
    final total = ordenados.fold<double>(
      0,
      (s, e) => s + e.value.fold<double>(0, (x, g) => x + g.monto),
    );

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(
            'LIQUIDACIÓN POR OPERADOR',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          subtitle: Text(
            '${ordenados.length} ${ordenados.length == 1 ? "operador" : "operadores"} · ${total.toCurrency()}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: azul),
          ),
          children: [
            for (final op in ordenados)
              _filaOperador(context, op.key, op.value, isDark, azul),
          ],
        ),
      ),
    );
  }

  /// Un operador con su total. Se despliega para ver cada pago y editarlo.
  Widget _filaOperador(
    BuildContext context,
    String nombre,
    List<Egreso> pagos,
    bool isDark,
    Color azul,
  ) {
    final total = pagos.fold<double>(0, (s, e) => s + e.monto);
    final ordenados = List<Egreso>.from(pagos)
      ..sort((a, b) {
        final fa = a.fecha;
        final fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        dense: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              total.toCurrency(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: azul),
            ),
          ],
        ),
        subtitle: Text(
          '${pagos.length} ${pagos.length == 1 ? "pago" : "pagos"}',
          style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
        ),
        children: [
          for (final p in ordenados)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.only(left: 12, right: 0),
              title: Text(
                p.fecha != null ? ArTime.formatFechaCorta(p.fecha!) : 'Sin fecha',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                p.medioPago ?? '—',
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
              ),
              trailing: Text(
                '−${p.monto.toCurrency()}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFE74C3C)),
              ),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => EditarPagoOperadorDialog(egreso: p),
                );
                if (ok == true) {
                  await ref.read(finanzasProvider.notifier).recargar();
                }
              },
            ),
        ],
      ),
    );
  }

  /// Un bloque de la deuda (escuelas o particulares) con su propio subtotal.
  /// Se omite entero si no hay nadie de ese tipo.
  Widget _bloqueDeuda(
    String titulo,
    List<InstitucionDeuda> items,
    bool isDark,
    Color gold,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    final subtotal = items.fold<double>(0, (s, d) => s + d.saldoGlobal);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              Text(
                subtotal.toCurrency(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: gold.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (d) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildDeudaCard(d, isDark, gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeudaCard(InstitucionDeuda esc, bool isDark, Color gold) {
    final bool tieneVencido = esc.vencido > 0.01;
    final bool tienePorVencer = esc.aVencer > 0.01;
    final bool tieneMes = tieneVencido || tienePorVencer;

    final Color indicatorColor = tieneVencido
        ? const Color(0xFFE74C3C)
        : tienePorVencer
            ? Colors.orangeAccent
            : gold.withValues(alpha: 0.6);

    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.025)
        : Colors.black.withValues(alpha: 0.015);
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    // Tocar abre la cartera ya posicionada en esta escuela: el panel agrupa por
    // cliente, así que sin esto se ve el total pero nunca quién adentro debe.
    //
    // Solo para masivos: la cartera lista alumno por alumno y una recepción
    // particular no tiene alumnos, así que abriría vacía.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: esc.esMasivo
            ? () => showDialog<void>(
                  context: context,
                  builder: (_) => CarteraEscuelasDialog(
                    institucionId: esc.id,
                    institucionNombre: esc.nombre,
                  ),
                )
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  esc.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
                  ),
                ),
              ),
              if (esc.esMasivo) ...[
                Icon(Icons.chevron_right_rounded, size: 14, color: gold.withValues(alpha: 0.5)),
                const SizedBox(width: 2),
              ],
              // Total real a la derecha del nombre
              Text(
                esc.saldoGlobal.toCurrency(),
                style: GoogleFonts.oswald(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: gold,
                ),
              ),
            ],
          ),
          // Detalle de mes (solo si hay algo del mes)
          if (tieneMes) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 16),
                Text(
                  'Este mes: ${esc.total.toCurrency()}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: tieneVencido ? const Color(0xFFE74C3C) : Colors.orangeAccent,
                  ),
                ),
                if (tieneVencido) ...[
                  const SizedBox(width: 6),
                  Text(
                    '(${esc.vencido.toCurrency()} vencido)',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE74C3C),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

  Widget _panelHeader(String title, IconData icon, Color gold) {
    return Row(
      children: [
        Icon(icon, size: 14, color: gold),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: gold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ── VISTA SALUD ──
  Widget _buildVistaSalud(bool isDark, Color gold, FinanzasState state) {
    const gridGap = 22.0;

    final pulsoDiarioBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Pulso diario de caja', Icons.show_chart_rounded),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _buildPulsoDiarioCaja(isDark, gold, state),
        ),
      ],
    );

    final mSalud = state.mesFiltro ?? DateTime.now();
    final labelMesSalud = '${mSalud.month.toString().padLeft(2, '0')}/${mSalud.year}';
    final esCobrosSalud = _filtroMesCaja == _FiltroMesCaja.cobros;

    final tortaMesBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: gold, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                esCobrosSalud ? 'COBROS DEL MES' : 'PAGOS DEL MES',
                style: GoogleFonts.oswald(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: gold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Mes: $labelMesSalud · Ajustá el mes con el filtro superior.',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: SegmentedButton<_FiltroMesCaja>(
            segments: const [
              ButtonSegment<_FiltroMesCaja>(
                value: _FiltroMesCaja.cobros,
                label: Text('ME PAGARON', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                icon: Icon(Icons.arrow_downward_rounded, size: 16),
              ),
              ButtonSegment<_FiltroMesCaja>(
                value: _FiltroMesCaja.pagos,
                label: Text('YO PAGUÉ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                icon: Icon(Icons.arrow_upward_rounded, size: 16),
              ),
            ],
            selected: {_filtroMesCaja},
            onSelectionChanged: (s) => setState(() => _filtroMesCaja = s.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) return gold.withValues(alpha: 0.22);
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) return gold;
                return isDark ? Colors.white54 : Colors.black54;
              }),
              side: WidgetStateProperty.all(BorderSide(color: gold.withValues(alpha: 0.35))),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildDesgloseCategorias(
          isDark,
          gold,
          state,
          limitTop: 0,
          showPieChart: true,
          cobrosPorFuente: esCobrosSalud,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useGrid = constraints.maxWidth >= 1100;

        final cuatroBloquesSalud = useGrid
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        pulsoDiarioBlock,
                        SizedBox(height: gridGap),
                        _buildRentabilidadPromedioHUD(isDark),
                      ],
                    ),
                  ),
                  SizedBox(width: gridGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tortaMesBlock,
                        SizedBox(height: gridGap),
                        _buildPorCobrarHUD(isDark, gold),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pulsoDiarioBlock,
                  const SizedBox(height: 24),
                  tortaMesBlock,
                  const SizedBox(height: 24),
                  _buildRentabilidadPromedioHUD(isDark),
                  const SizedBox(height: 24),
                  _buildPorCobrarHUD(isDark, gold),
                ],
              );

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHealthScoreHero(
                isDark,
                gold,
                state,
                runwayKey: _keySaludRunway,
                onPillarTap: _onSaludPillarTap,
              ),
              const SizedBox(height: 24),
              ExpansionTile(
                title: Text('RESUMEN Y COMPARATIVA DEL MES', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  KeyedSubtree(
                    key: _keySaludResumen,
                    child: _buildResumenMes(isDark, gold, state),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text('ANÁLISIS PROFUNDO Y RENTABILIDAD', style: TextStyle(color: gold, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13)),
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  cuatroBloquesSalud,
                  const SizedBox(height: 24),
                  KeyedSubtree(
                    key: _keySaludTabla,
                    child: _buildTablaAnualDinamica(isDark, gold, const Color(0xFF00B894), const Color(0xFFE74C3C), state),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              KeyedSubtree(
                key: _keySaludAlertas,
                child: _buildAlertasGestion(isDark, gold),
              ),
            ],
          ),
        );
      },
    );
  }

  (double, double) _sumarIngEgRango(
    List<IngresoDetallado> ingSrc,
    List<Egreso> egSrc,
    DateTime desdeDia,
    DateTime hastaDiaInclusive,
  ) {
    bool enRango(DateTime? dt) {
      if (dt == null) return false;
      final a = ArTime.toAr(dt);
      final solo = DateTime(a.year, a.month, a.day);
      return !solo.isBefore(desdeDia) && !solo.isAfter(hastaDiaInclusive);
    }
    final ing = ingSrc.where((i) => enRango(i.fecha)).fold(0.0, (s, i) => s + i.monto);
    final eg = egSrc.where((e) => enRango(e.fecha)).fold(0.0, (s, e) => s + e.monto);
    return (ing, eg);
  }

  List<_DiaPulsoDatum> _serieDiasPulso(FinanzasState state) {
    if (_pulsoRango == _PulsoRangoVista.mesCalendario) {
      final refMes = state.mesFiltro ?? ArTime.nowAr();
      final y = refMes.year;
      final m = refMes.month;
      final last = DateTime(y, m + 1, 0).day;
      final out = <_DiaPulsoDatum>[];
      for (var d = 1; d <= last; d++) {
        final dia = DateTime(y, m, d);
        var ing = 0.0;
        var eg = 0.0;
        var ni = 0;
        var ne = 0;
        for (final i in state.ingresos) {
          if (ArTime.mismoDia(i.fecha, dia)) {
            ing += i.monto;
            ni++;
          }
        }
        for (final e in state.egresos) {
          if (e.fecha != null && ArTime.mismoDia(e.fecha!, dia)) {
            eg += e.monto;
            ne++;
          }
        }
        out.add(_DiaPulsoDatum(dia: dia, ing: ing, eg: eg, nPagos: ni, nEgresos: ne));
      }
      return out;
    }
    final ingL = _pulso30Ingresos ?? [];
    final egL = _pulso30Egresos ?? [];
    final nowAr = ArTime.nowAr();
    final fin = DateTime(nowAr.year, nowAr.month, nowAr.day);
    final ini = fin.subtract(const Duration(days: 29));
    final out = <_DiaPulsoDatum>[];
    for (var i = 0; i < 30; i++) {
      final dia = ini.add(Duration(days: i));
      var ing = 0.0;
      var eg = 0.0;
      var ni = 0;
      var ne = 0;
      for (final x in ingL) {
        if (ArTime.mismoDia(x.fecha, dia)) {
          ing += x.monto;
          ni++;
        }
      }
      for (final x in egL) {
        if (x.fecha != null && ArTime.mismoDia(x.fecha!, dia)) {
          eg += x.monto;
          ne++;
        }
      }
      out.add(_DiaPulsoDatum(dia: dia, ing: ing, eg: eg, nPagos: ni, nEgresos: ne));
    }
    return out;
  }

  Widget _buildPulsoChipsRapidos(bool isDark, Color gold, FinanzasState state, Color green, Color red) {
    final nowAr = ArTime.nowAr();
    final hoy = DateTime(nowAr.year, nowAr.month, nowAr.day);
    final ayer = hoy.subtract(const Duration(days: 1));
    final lun = _lunesSemanaArDesde(nowAr);
    final dom = lun.add(const Duration(days: 6));

    List<IngresoDetallado> ingPulse;
    List<Egreso> egPulse;
    if (_pulsoRango == _PulsoRangoVista.mesCalendario) {
      ingPulse = state.ingresos;
      egPulse = state.egresos;
    } else {
      ingPulse = _pulso30Ingresos ?? [];
      egPulse = _pulso30Egresos ?? [];
    }

    final h = _sumarIngEgRango(ingPulse, egPulse, hoy, hoy);
    final a = _sumarIngEgRango(ingPulse, egPulse, ayer, ayer);
    final sem = _sumarIngEgRango(ingPulse, egPulse, lun, dom);
    final mesIng = state.ingresos.fold(0.0, (s, i) => s + i.monto);
    final mesEg = state.egresos.fold(0.0, (s, e) => s + e.monto);

    Widget chip(String label, double ing, double eg) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gold.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '+${ing.toCurrency()}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: green),
            ),
            Text(
              '-${eg.toCurrency()}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: red),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('HOY', h.$1, h.$2),
        chip('AYER', a.$1, a.$2),
        chip('ESTA SEMANA (lun–dom)', sem.$1, sem.$2),
        chip('ESTE MES (filtro)', mesIng, mesEg),
      ],
    );
  }

  Widget _buildPulsoFooter(bool isDark, Color gold, FinanzasState state, Color green, Color red, List<_DiaPulsoDatum> serie) {
    if (serie.isEmpty) return const SizedBox.shrink();
    _DiaPulsoDatum best = serie.first;
    _DiaPulsoDatum worst = serie.first;
    for (final d in serie) {
      if (d.neto > best.neto) best = d;
      if (d.neto < worst.neto) worst = d;
    }
    var sinMov = 0;
    var sumI = 0.0;
    var sumE = 0.0;
    for (final d in serie) {
      sumI += d.ing;
      sumE += d.eg;
      if (d.ing == 0 && d.eg == 0) sinMov++;
    }
    final n = serie.length;
    final promI = n > 0 ? sumI / n : 0.0;
    final promE = n > 0 ? sumE / n : 0.0;
    const mesesN = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    String labelDia(DateTime d) {
      final ar = ArTime.toAr(d);
      return '${mesesN[ar.month - 1]} ${ar.day}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mejor día (neto): ${labelDia(best.dia)} · ${best.neto.toCurrency()}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: green.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 4),
        Text(
          'Peor día (neto): ${labelDia(worst.dia)} · ${worst.neto.toCurrency()}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: red.withValues(alpha: 0.9)),
        ),
        const SizedBox(height: 4),
        Text(
          'Días sin movimiento: $sinMov · Promedio diario: +${promI.toCurrency()} ing. · -${promE.toCurrency()} egr.',
          style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
        ),
      ],
    );
  }

  Widget _buildPulsoBarrasDias(bool isDark, Color gold, FinanzasState state, Color green, Color red) {
    final serie = _serieDiasPulso(state);
    if (serie.isEmpty) return const SizedBox.shrink();
    _schedulePulsoScrollCentrarHoy(state, serie);

    var scaleMax = 1.0;
    for (final d in serie) {
      scaleMax = max(scaleMax, max(d.ing, d.eg));
    }

    const maxH = 112.0;
    const colW = 26.0;
    const gap = 5.0;

    return LayoutBuilder(
      builder: (context, c) {
        return Scrollbar(
          controller: _pulsoBarrasScrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 7,
          radius: const Radius.circular(6),
          child: SingleChildScrollView(
            controller: _pulsoBarrasScrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: serie.map((d) {
              final hIn = scaleMax > 0 ? (d.ing / scaleMax) * maxH : 0.0;
              final hEg = scaleMax > 0 ? (d.eg / scaleMax) * maxH : 0.0;
              final ar = ArTime.toAr(d.dia);
              final sel = state.fechaExactaFiltro != null && ArTime.mismoDia(d.dia, state.fechaExactaFiltro!);
              final tip =
                  '${ArTime.formatDiaMes(d.dia)}: ingresó ${d.ing.toCurrency()} en ${d.nPagos} pagos · gastó ${d.eg.toCurrency()} en ${d.nEgresos} egresos. Tocá para filtrar el día.';

              return Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      excludeFromSemantics: _tooltipExcludeSemanticsWin(),
                      message: tip,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            await ref.read(finanzasProvider.notifier).aplicarFiltro(
                                  mes: DateTime(ar.year, ar.month, 1),
                                  fechaExactaFiltro: DateTime(ar.year, ar.month, ar.day),
                                );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: colW,
                            padding: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: sel ? gold : Colors.transparent,
                                width: sel ? 2 : 0,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: max(2.0, hIn),
                                  decoration: BoxDecoration(
                                    color: green.withValues(alpha: 0.85),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 10,
                                  height: max(2.0, hEg),
                                  decoration: BoxDecoration(
                                    color: red.withValues(alpha: 0.85),
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${ar.day}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPulsoDiarioCaja(bool isDark, Color gold, FinanzasState state) {
    final green = const Color(0xFF00B894);
    final red = const Color(0xFFE74C3C);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                _pulsoRango == _PulsoRangoVista.mesCalendario
                    ? 'Cada barra: verde = ingresos, rojo = egresos (escala compartida).'
                    : 'Últimos 30 días corridos (hora Argentina).',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
            ),
            SegmentedButton<_PulsoRangoVista>(
              segments: const [
                ButtonSegment(
                  value: _PulsoRangoVista.mesCalendario,
                  label: Text('Mes', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                ButtonSegment(
                  value: _PulsoRangoVista.ultimos30,
                  label: Text('30 días', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
              selected: {_pulsoRango},
              onSelectionChanged: (s) {
                final v = s.first;
                setState(() {
                  _pulsoRango = v;
                  if (v == _PulsoRangoVista.mesCalendario) {
                    _pulsoScrollAppliedStamp = null;
                  }
                });
                if (v == _PulsoRangoVista.ultimos30 && _pulso30Ingresos == null) {
                  _cargarDatosPulso30(state);
                }
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                side: WidgetStateProperty.all(BorderSide(color: gold.withValues(alpha: 0.35))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPulsoChipsRapidos(isDark, gold, state, green, red),
        const SizedBox(height: 16),
        if (_pulsoRango == _PulsoRangoVista.ultimos30 && _pulso30Loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
          )
        else ...[
          _buildPulsoBarrasDias(isDark, gold, state, green, red),
          const SizedBox(height: 14),
          _buildPulsoFooter(isDark, gold, state, green, red, _serieDiasPulso(state)),
        ],
      ],
    );
  }

  /// Detalle de egresos del día (totales del día van en el HUD «Inteligencia financiera», modo HOY).
  Widget _buildPanelOperativoDia(BuildContext context, bool isDark, Color gold, FinanzasState state) {
    final nAr = ArTime.nowAr();
    final hoyNorm = DateTime(nAr.year, nAr.month, nAr.day);
    final diaAnalisis = state.fechaInteligenciaHud ?? hoyNorm;
    final esCalendarioActual = ArTime.mismoDia(diaAnalisis, nAr);
    final red = const Color(0xFFE74C3C);

    final egresosHoy = <Egreso>[];
    for (final e in state.egresos) {
      if (e.fecha != null && ArTime.mismoDia(e.fecha!, diaAnalisis)) egresosHoy.add(e);
    }
    egresosHoy.sort((a, b) => b.monto.compareTo(a.monto));

    final labelRef = DateTime.utc(diaAnalisis.year, diaAnalisis.month, diaAnalisis.day, 12);
    final labelDia = ArTime.formatFechaLarga(labelRef);
    final topRows = egresosHoy.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.today_rounded, color: gold, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'OPERACIÓN DEL DÍA',
                style: GoogleFonts.oswald(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: gold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          labelDia[0].toUpperCase() + labelDia.substring(1),
          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
        ),
        const SizedBox(height: 6),
        Text(
          'Ingresos, egresos y neto del día están en «Inteligencia financiera» arriba (HOY).',
          style: TextStyle(
            fontSize: 10,
            height: 1.35,
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.receipt_long_outlined, color: gold.withValues(alpha: 0.85), size: 18),
            const SizedBox(width: 8),
            Text(
              esCalendarioActual ? 'EGRESOS DE HOY (${egresosHoy.length})' : 'EGRESOS DEL DÍA (${egresosHoy.length})',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (topRows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Text(
              esCalendarioActual ? 'Sin egresos registrados hoy.' : 'Sin egresos en este día.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          )
        else
          ...topRows.map((e) {
          final cat = (e.categoria?.trim().isNotEmpty == true) ? e.categoria! : 'Sin categoría';
          final titulo = e.proveedorVisible ?? cat;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_down_rounded, size: 18, color: red.withValues(alpha: 0.85)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (titulo != cat)
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Sin tachito acá: borrar un movimiento se hace tocándolo en el
                  // historial del panel. Este pedía PIN y el del panel no, así
                  // que la misma acción tenía dos reglas según por dónde entraras
                  // — y la que pedía PIN era justo la de los retiros de caja.
                  Text(
                    e.monto.toCurrency(),
                    style: GoogleFonts.oswald(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: red,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Barra 00:00–24:00 con puntos por movimiento del día (CustomPaint).
  Widget _buildTimelineDia(bool isDark, Color gold, FinanzasState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Movimientos del día', Icons.schedule_rounded),
          const SizedBox(height: 12),
          _TimelineDiaStrip(
            isDark: isDark,
            gold: gold,
            state: state,
            onIngresoDotTap: () async {
              final ok = await AdminGate.check(context, ref);
              if (!ok || !mounted) return;
              setState(() {
                _currentSubView = FinanzasSubView.flujo;
                _searchContext = SearchContext.ingresos;
              });
            },
            onEgresoDotTap: () async {
              final ok = await AdminGate.check(context, ref);
              if (!ok || !mounted) return;
              if (!context.mounted) return;
              await showDialog<bool>(
                context: context,
                builder: (_) => const RegistrarEgresoGlobalDialog(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Pestaña HOY: operación del día + timeline + accesos rápidos.
  Widget _buildVistaCategorias(bool isDark, Color gold, FinanzasState state) {
    final ctaStyle = ElevatedButton.styleFrom(
      backgroundColor: gold,
      foregroundColor: Colors.black87,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPanelOperativoDia(context, isDark, gold, state),
        const SizedBox(height: 24),
        _buildTimelineDia(isDark, gold, state),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton(
              onPressed: () async {
                final ok = await AdminGate.check(context, ref);
                if (!ok || !mounted) return;
                setState(() {
                  _currentSubView = FinanzasSubView.flujo;
                  _searchContext = SearchContext.ingresos;
                });
              },
              style: ctaStyle,
              child: const Text('+ INGRESO'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await AdminGate.check(context, ref);
                if (!ok || !mounted) return;
                if (!context.mounted) return;
                await showDialog<bool>(
                  context: context,
                  builder: (_) => const RegistrarEgresoGlobalDialog(),
                );
              },
              style: ctaStyle,
              child: const Text('+ EGRESO'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _currentSubView = FinanzasSubView.avisos);
              },
              style: ctaStyle,
              child: const Text('PAGAR AVISO'),
            ),
            ElevatedButton(
              onPressed: () async {
                final ok = await AdminGate.check(context, ref);
                if (!ok || !mounted) return;
                if (!context.mounted) return;
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const EventosScreen()),
                );
              },
              style: ctaStyle,
              child: const Text('VER AGENDA'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Bloque D: Desglose de Gastos por Categoría ───────────────────────────
  /// [limitTop]: cantidad máxima de filas en barras; `0` = todas las categorías.
  /// [showPieChart]: torta (máx. 6 segmentos; el resto se agrupa en "Otros").
  /// [cobrosPorFuente]: si es true, agrupa ingresos del mes por fuente (Particular / Masivo / Alquiler).
  Widget _buildDesgloseCategorias(
    bool isDark,
    Color gold,
    FinanzasState state, {
    int limitTop = 5,
    bool showPieChart = false,
    bool cobrosPorFuente = false,
  }) {
    final ingresosMes = _ingresosVista(state);
    final egresosMes = _egresosVista(state);

    if (cobrosPorFuente) {
      if (ingresosMes.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payments_outlined, size: 20, color: isDark ? Colors.white24 : Colors.black26),
              const SizedBox(width: 10),
              Text(
                'Sin cobros registrados para este período',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        );
      }
    } else if (egresosMes.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 20, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(width: 10),
            Text(
              'Sin egresos registrados para este período',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    String etiquetaFuenteCobro(String fuente) {
      switch (fuente.trim()) {
        case 'Masivo':
          return 'Eventos masivos';
        case 'Particular':
          return 'Eventos particulares';
        case 'Alquiler':
          return 'Alquiler / ítems';
        default:
          return fuente.trim().isEmpty ? 'Otro' : fuente.trim();
      }
    }

    // Agrupar
    final Map<String, double> porCategoria = {};
    if (cobrosPorFuente) {
      for (final i in ingresosMes) {
        final k = etiquetaFuenteCobro(i.fuente);
        porCategoria[k] = (porCategoria[k] ?? 0) + i.monto;
      }
    } else {
      for (final e in egresosMes) {
        final cat = (e.categoria?.trim().isNotEmpty == true) ? e.categoria! : 'Otro';
        porCategoria[cat] = (porCategoria[cat] ?? 0) + e.monto;
      }
    }

    final sorted = porCategoria.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalEg = cobrosPorFuente
        ? ingresosMes.fold(0.0, (s, i) => s + i.monto)
        : egresosMes.fold(0.0, (s, e) => s + e.monto);

    final barRows = limitTop <= 0 ? sorted : sorted.take(limitTop).toList();
    final accentTotal = cobrosPorFuente ? const Color(0xFF00B894) : const Color(0xFFE74C3C);

    // Paleta de colores para las barras / torta
    const barColors = [
      Color(0xFFE74C3C),
      Color(0xFFE67E22),
      Color(0xFF9B59B6),
      Color(0xFF3498DB),
      Color(0xFF1ABC9C),
      Color(0xFF00B894),
      Color(0xFF6C63FF),
      Color(0xFFE91E63),
    ];

    IconData iconForClave(String clave) {
      if (cobrosPorFuente) {
        final l = clave.toLowerCase();
        if (l.contains('masivo')) return Icons.groups_2_rounded;
        if (l.contains('particular')) return Icons.person_rounded;
        if (l.contains('alquiler')) return Icons.inventory_2_rounded;
        return Icons.payments_rounded;
      }
      switch (clave.toLowerCase()) {
        case 'sueldos':      return Icons.people_alt_rounded;
        case 'operadores':   return Icons.engineering_rounded;
        case 'personal':     return Icons.engineering_rounded;
        case 'alquiler local': return Icons.store_rounded;
        case 'alquiler':     return Icons.store_rounded;
        case 'proveedores':  return Icons.inventory_2_rounded;
        case 'proveedor':    return Icons.inventory_2_rounded;
        case 'logística':    return Icons.local_shipping_rounded;
        case 'logistica':    return Icons.local_shipping_rounded;
        case 'marketing':    return Icons.campaign_rounded;
        case 'impuestos':    return Icons.account_balance_rounded;
        case 'catering':     return Icons.restaurant_rounded;
        case 'bebida':       return Icons.local_bar_rounded;
        default:             return Icons.label_outline_rounded;
      }
    }

    // Datos para torta: hasta 5 categorías + "Otros"
    final List<MapEntry<String, double>> pieSlices = [];
    if (showPieChart && sorted.isNotEmpty) {
      const maxSlices = 5;
      if (sorted.length <= maxSlices) {
        pieSlices.addAll(sorted);
      } else {
        pieSlices.addAll(sorted.take(maxSlices));
        final resto = sorted.skip(maxSlices).fold(0.0, (s, e) => s + e.value);
        pieSlices.add(MapEntry('Otros', resto));
      }
    }

    final holeColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Widget pieAndLegend() {
      if (!showPieChart || pieSlices.isEmpty || totalEg <= 0) {
        return const SizedBox.shrink();
      }
      final amounts = pieSlices.map((e) => e.value).toList();
      final colors = List<Color>.generate(
        pieSlices.length,
        (i) => barColors[i % barColors.length],
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 480;
          final pieSize = wide ? 168.0 : 140.0;
          final pie = SizedBox(
            width: pieSize,
            height: pieSize,
            child: CustomPaint(
              painter: EgresosPiePainter(
                amounts: amounts,
                colors: colors,
                holeColor: holeColor,
              ),
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: pieSlices.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              final pct = totalEg > 0 ? (entry.value / totalEg) * 100 : 0.0;
              final c = colors[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                pie,
                const SizedBox(height: 16),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              pie,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cobrosPorFuente
                      ? (showPieChart ? 'DESGLOSE POR ORIGEN (ME PAGARON)' : 'TOP ORIGEN DE COBRO')
                      : (showPieChart ? 'DESGLOSE POR CATEGORÍA' : 'TOP CATEGORÍAS DE GASTO'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
              Text(
                'Total: ${totalEg.toCurrency()}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accentTotal.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          if (showPieChart) ...[
            const SizedBox(height: 16),
            pieAndLegend(),
          ],
          const SizedBox(height: 16),
          ...barRows.asMap().entries.map((entry) {
            final i = entry.key;
            final cat = entry.value.key;
            final monto = entry.value.value;
            final pct = totalEg > 0 ? (monto / totalEg) : 0.0;
            final color = barColors[i % barColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(iconForClave(cat), color: color, size: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(pct * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        monto.toCurrency(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: color.withValues(alpha: isDark ? 0.1 : 0.07),
                      valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.75)),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (limitTop > 0 && sorted.length > limitTop) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.more_horiz_rounded, size: 14, color: isDark ? Colors.white24 : Colors.black26),
                const SizedBox(width: 6),
                Text(
                  '+ ${sorted.length - limitTop} ítems más (pestaña HOY con filtro ${cobrosPorFuente ? 'cobros' : 'pagos'})',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResumenMes(bool isDark, Color gold, FinanzasState state) {
    final green = const Color(0xFF00B894);
    final red = const Color(0xFFE74C3C);

    String deltaLabel(double prevVal, double currVal) {
      if (prevVal == 0 && currVal == 0) return '0%';
      if (prevVal == 0) return currVal > 0 ? '+100%' : '0%';
      final p = ((currVal - prevVal) / prevVal) * 100;
      return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(1)}%';
    }

    final fe = state.fechaExactaFiltro;
    if (fe != null) {
      final ingList = _ingresosVista(state);
      final egList = _egresosVista(state);
      final ing = ingList.fold(0.0, (s, i) => s + i.monto);
      final eg = egList.fold(0.0, (s, e) => s + e.monto);
      final neto = ing - eg;

      final fAr = ArTime.toAr(fe);
      final diaRef = DateTime(fAr.year, fAr.month, fAr.day);
      final prevDia = diaRef.subtract(const Duration(days: 1));
      final ingPrev = state.ingresos.where((i) => ArTime.mismoDia(i.fecha, prevDia)).fold(0.0, (s, i) => s + i.monto);
      final egPrev = state.egresos.where((e) => e.fecha != null && ArTime.mismoDia(e.fecha!, prevDia)).fold(0.0, (s, e) => s + e.monto);
      final netoPrev = ingPrev - egPrev;

      final dIng = deltaLabel(ingPrev, ing);
      final dEg = deltaLabel(egPrev, eg);
      final dNeto = deltaLabel(netoPrev, neto);
      final ingBarVal = ingPrev > 0 ? (ing / ingPrev).clamp(0.0, 1.0) : (ing > 0 ? 1.0 : 0.0);
      final superaIng = ingPrev > 0 && ing > ingPrev;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildKPICard('INGRESOS', ing, isDark, gold, green)),
              const SizedBox(width: 16),
              Expanded(child: _buildKPICard('EGRESOS', eg, isDark, gold, red)),
              const SizedBox(width: 16),
              Expanded(
                child: _buildKPICard('SALDO NETO', neto, isDark, gold, neto >= 0 ? green : red, highlight: true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : gold.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : gold.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.compare_arrows_rounded, size: 18, color: gold),
                    const SizedBox(width: 8),
                    Text(
                      'VS DÍA ANTERIOR (${ArTime.formatFechaCorta(prevDia)})',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Ingresos respecto al día anterior (mismo mes cargado)',
                  style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black45),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ingBarVal,
                    minHeight: 8,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(superaIng ? green : gold.withValues(alpha: 0.85)),
                  ),
                ),
                if (superaIng)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Superás el día anterior en ingresos',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: green.withValues(alpha: 0.9)),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildDeltaChip('Ing.', dIng, isDark, green),
                    _buildDeltaChip('Egr.', dEg, isDark, red),
                    _buildDeltaChip('Neto', dNeto, isDark, neto >= netoPrev ? green : red),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Vista normal (sin drill-down desde el gráfico): mismos totales que el HUD — día en análisis (tiempo real o fecha fija).
    final arHud =
        state.fechaInteligenciaHud != null ? ArTime.toAr(state.fechaInteligenciaHud!) : ArTime.nowAr();
    final diaRef = DateTime(arHud.year, arHud.month, arHud.day);

    final ing = state.hudIngresosHoy;
    final eg = state.hudEgresosHoy;
    final neto = ing - eg;

    final prevDia = diaRef.subtract(const Duration(days: 1));
    final ingPrev =
        state.ingresos.where((i) => ArTime.mismoDia(i.fecha, prevDia)).fold(0.0, (s, i) => s + i.monto);
    final egPrev =
        state.egresos.where((e) => e.fecha != null && ArTime.mismoDia(e.fecha!, prevDia)).fold(0.0, (s, e) => s + e.monto);
    final netoPrev = ingPrev - egPrev;

    final dIng = deltaLabel(ingPrev, ing);
    final dEg = deltaLabel(egPrev, eg);
    final dNeto = deltaLabel(netoPrev, neto);
    final ingBarVal = ingPrev > 0 ? (ing / ingPrev).clamp(0.0, 1.0) : (ing > 0 ? 1.0 : 0.0);
    final superaIng = ingPrev > 0 && ing > ingPrev;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildKPICard('INGRESOS', ing, isDark, gold, green)),
            const SizedBox(width: 16),
            Expanded(child: _buildKPICard('EGRESOS', eg, isDark, gold, red)),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKPICard('SALDO NETO', neto, isDark, gold, neto >= 0 ? green : red, highlight: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : gold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : gold.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.compare_arrows_rounded, size: 18, color: gold),
                  const SizedBox(width: 8),
                  Text(
                    'VS DÍA ANTERIOR (${ArTime.formatFechaCorta(prevDia)})',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Ingresos respecto al día anterior',
                style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black45),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ingBarVal,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(superaIng ? green : gold.withValues(alpha: 0.85)),
                ),
              ),
              if (superaIng)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Superás el día anterior en ingresos',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: green.withValues(alpha: 0.9)),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildDeltaChip('Ing.', dIng, isDark, green),
                  _buildDeltaChip('Egr.', dEg, isDark, red),
                  _buildDeltaChip('Neto', dNeto, isDark, neto >= netoPrev ? green : red),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeltaChip(String label, String deltaStr, bool isDark, Color accent) {
    final isNeg = deltaStr.startsWith('-');
    final isFlat = deltaStr == '0%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: isDark ? Colors.white38 : Colors.black45)),
        Icon(
          isFlat ? Icons.horizontal_rule_rounded : (isNeg ? Icons.south_east_rounded : Icons.north_east_rounded),
          size: 14,
          color: accent,
        ),
        const SizedBox(width: 4),
        Text(
          deltaStr,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: accent),
        ),
      ],
    );
  }
  
  Widget _buildKPICard(String label, double amount, bool isDark, Color gold, Color accent, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight 
            ? accent.withValues(alpha: 0.1) 
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight 
              ? accent.withValues(alpha: 0.3) 
              : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
          width: highlight ? 2.0 : 1.0,
        ),
        boxShadow: highlight ? [
          BoxShadow(color: accent.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
        ] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label, 
            style: TextStyle(
              fontSize: 10, 
              fontWeight: FontWeight.w900, 
              letterSpacing: 1.5, 
              color: highlight ? accent : (isDark ? Colors.white54 : Colors.black54)
            )
          ),
          const SizedBox(height: 8),
          Text(
            amount.toCurrency(), 
            style: GoogleFonts.oswald(
              fontSize: 22, 
              fontWeight: FontWeight.w700, 
              color: highlight ? accent : (isDark ? Colors.white : Colors.black),
              letterSpacing: -0.5
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
                      controller: _alertasGestionExpansionController,
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

  // ── Tabla mensual (últimos 6 meses + promedio + tooltips) ─────────────────
  Widget _buildTablaAnualDinamica(bool isDark, Color gold, Color green, Color red, FinanzasState state) {
    const mesesNombre = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    final mesesCalculados = _ultimosMesesDatos(state, cantidad: 6);
    final maxVal = mesesCalculados.fold<double>(
      0,
      (m, d) => [m, d.ingresos, d.egresos].reduce((a, b) => a > b ? a : b),
    );

    final promIng = mesesCalculados.fold<double>(0, (s, d) => s + d.ingresos) / mesesCalculados.length;
    final promEg = mesesCalculados.fold<double>(0, (s, d) => s + d.egresos) / mesesCalculados.length;

    _MesData best = mesesCalculados.first;
    _MesData worst = mesesCalculados.first;
    for (final d in mesesCalculados) {
      if (d.neto > best.neto) best = d;
      if (d.neto < worst.neto) worst = d;
    }
    final tipMejorPeor =
        'Mejor mes (neto): ${mesesNombre[best.mes.month - 1]} ${best.mes.year} (${best.neto.toCurrency()}). '
        'Peor mes (neto): ${mesesNombre[worst.mes.month - 1]} ${worst.mes.year} (${worst.neto.toCurrency()}). '
        'Tocá una fila para filtrar Finanzas a ese mes.';

    final promIngRatio = maxVal > 0 ? (promIng / maxVal).clamp(0.0, 1.0) : 0.0;
    final promEgRatio = maxVal > 0 ? (promEg / maxVal).clamp(0.0, 1.0) : 0.0;

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 16, color: gold.withValues(alpha: 0.85)),
              const SizedBox(width: 8),
              Text(
                'COMPARATIVA MENSUAL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const Spacer(),
              Tooltip(
                excludeFromSemantics: _tooltipExcludeSemanticsWin(),
                message: tipMejorPeor,
                child: Icon(Icons.info_outline_rounded, size: 18, color: gold.withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Línea punteada = promedio de los 6 meses mostrados (ingresos / egresos).',
            style: TextStyle(fontSize: 9, color: isDark ? Colors.white30 : Colors.black38, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(width: 36, child: Text('MES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
              const SizedBox(width: 8),
              Expanded(child: Text('INGRESOS / EGRESOS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
              SizedBox(width: 80, child: Text('NETO', textAlign: TextAlign.right, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38))),
            ],
          ),
          const SizedBox(height: 10),
          // Fila promedio 6 meses (referencia)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    'Ø',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: gold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: promIngRatio,
                              minHeight: 6,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(green.withValues(alpha: 0.35)),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: DashedOverlayPainter(
                                color: green.withValues(alpha: 0.95),
                                strokeWidth: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: promEgRatio,
                              minHeight: 6,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(red.withValues(alpha: 0.35)),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: DashedOverlayPainter(
                                color: red.withValues(alpha: 0.95),
                                strokeWidth: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Prom. ${promIng.toCurrency()} / ${promEg.toCurrency()}',
                        style: TextStyle(fontSize: 8, color: isDark ? Colors.white30 : Colors.black38),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  child: Text(
                    (promIng - promEg).toCurrency(),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: (promIng - promEg) >= 0 ? green : red),
                  ),
                ),
              ],
            ),
          ),
          ...(mesesCalculados.map((m) {
            final nombre = mesesNombre[m.mes.month - 1];
            final neto = m.neto;
            final ingRatio = maxVal > 0 ? (m.ingresos / maxVal).clamp(0.0, 1.0) : 0.0;
            final egRatio = maxVal > 0 ? (m.egresos / maxVal).clamp(0.0, 1.0) : 0.0;
            final isCurrent = m.mes.month == DateTime.now().month && m.mes.year == DateTime.now().year;
            final isSelected =
                state.mesFiltro?.year == m.mes.year && state.mesFiltro?.month == m.mes.month;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => ref.read(finanzasProvider.notifier).aplicarFiltro(mes: m.mes, clearFechaExacta: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            nombre,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                              color: isSelected
                                  ? gold
                                  : (isCurrent ? gold : (isDark ? Colors.white54 : Colors.black54)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Tooltip(
                            excludeFromSemantics: _tooltipExcludeSemanticsWin(),
                            message:
                                '${mesesNombre[m.mes.month - 1]} ${m.mes.year}: neto ${neto.toCurrency()}. Tocá para filtrar.',
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ingRatio,
                                    minHeight: 6,
                                    backgroundColor: Colors.transparent,
                                    valueColor: AlwaysStoppedAnimation<Color>(green.withValues(alpha: 0.7)),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: egRatio,
                                    minHeight: 6,
                                    backgroundColor: Colors.transparent,
                                    valueColor: AlwaysStoppedAnimation<Color>(red.withValues(alpha: 0.7)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          child: Text(
                            neto.toCurrency(),
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: neto >= 0 ? green : red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                      Icon(Icons.account_balance_wallet_outlined, color: gold, size: 18),
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

  // Los dos usan la regla compartida: minúsculas, sin tildes y todas las
  // palabras en cualquier orden. Antes cada uno hacía su `contains` pelado sobre
  // el texto crudo, así que "operador maxi" no encontraba `MAXI OPERADOR` y
  // "anotacion" no encontraba "Anotación". Qué campos mira cada lista sí sigue
  // siendo distinto, según lo que esa pantalla ya filtre por otro lado.
  bool _ingresoCoincideTexto(IngresoDetallado ing, String q) =>
      coincideTextoBusqueda([
        ing.alumnoOCliente,
        ing.concepto,
        ing.nombreEvento,
        ing.fuente,
      ], q);

  bool _egresoCoincideTexto(Egreso eg, String q) => coincideTextoBusqueda([
        // Sobre el texto visible: se busca por el concepto, no por el prefijo.
        eg.proveedorVisible,
        eg.categoria,
        eg.medioPago,
      ], q);

  // ── Lista de Ingresos (ÉLITE DataTables) ───────────────────────────────────
  Widget _buildIngresosLista(bool isDark, Color gold, Color green, List<IngresoDetallado> ingresos, {required bool isHalf}) {
    // Filtrado dinámico unificado
    if (_searchContext == SearchContext.egresos) return const SizedBox.shrink();

    final query = _masterSearchCtrl.text.toLowerCase().trim();
    final localQ = _ingresosListaSearchCtrl.text.toLowerCase().trim();
    final hoyAr = ArTime.nowAr();
    final filteredIngresos = ingresos.where((ing) {
      if (_medioPagoFiltro != null) {
        if (_medioPagoFiltro == 'transferencia') {
          if (ing.medioPago?.toLowerCase().trim() != 'transferencia') return false;
        } else if (_medioPagoFiltro == 'efectivo') {
          if (!_ingresoCuentaComoEfectivoEnListado(ing, hoyAr)) return false;
        }
      }
      if (!_ingresoCoincideTexto(ing, query)) return false;
      if (!_ingresoCoincideTexto(ing, localQ)) return false;
      return true;
    }).toList();

    // Conteos para los chips (sin considerar _medioPagoFiltro; sí buscadores maestro + lista)
    final ingresosFiltradosPorQuery = ingresos.where((ing) {
      return _ingresoCoincideTexto(ing, query) && _ingresoCoincideTexto(ing, localQ);
    }).toList();
    final cntEfectivo = ingresosFiltradosPorQuery.where((i) => _ingresoCuentaComoEfectivoEnListado(i, hoyAr)).length;
    final cntTransferencia = ingresosFiltradosPorQuery.where((i) => i.medioPago?.toLowerCase().trim() == 'transferencia').length;

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
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              title: Text(
                'REGISTROS DE INGRESOS (${filteredIngresos.length})',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isDark ? Colors.white60 : Colors.black54, letterSpacing: 1.5),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _ingresosListaSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar en esta lista: cliente, concepto, evento, fuente…',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white24 : Colors.black38,
                      ),
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 22, color: gold.withValues(alpha: 0.75)),
                      suffixIcon: _ingresosListaSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _ingresosListaSearchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.55)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                // ── Filtro por medio de pago ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('Todos (${ingresosFiltradosPorQuery.length})', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        selected: _medioPagoFiltro == null,
                        onSelected: (_) => setState(() => _medioPagoFiltro = null),
                        selectedColor: gold.withValues(alpha: 0.2),
                        side: BorderSide(color: _medioPagoFiltro == null ? gold : Colors.grey.shade300, width: 1.2),
                      ),
                      ChoiceChip(
                        avatar: Icon(Icons.payments_outlined, size: 14, color: _medioPagoFiltro == 'efectivo' ? const Color(0xFF00B894) : Colors.grey),
                        label: Text('Efectivo ($cntEfectivo)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        selected: _medioPagoFiltro == 'efectivo',
                        onSelected: (_) => setState(() => _medioPagoFiltro = _medioPagoFiltro == 'efectivo' ? null : 'efectivo'),
                        selectedColor: const Color(0xFF00B894).withValues(alpha: 0.15),
                        side: BorderSide(color: _medioPagoFiltro == 'efectivo' ? const Color(0xFF00B894) : Colors.grey.shade300, width: 1.2),
                      ),
                      ChoiceChip(
                        avatar: Icon(Icons.swap_horiz_rounded, size: 14, color: _medioPagoFiltro == 'transferencia' ? const Color(0xFF6C63FF) : Colors.grey),
                        label: Text('Transferencia ($cntTransferencia)', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        selected: _medioPagoFiltro == 'transferencia',
                        onSelected: (_) => setState(() => _medioPagoFiltro = _medioPagoFiltro == 'transferencia' ? null : 'transferencia'),
                        selectedColor: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                        side: BorderSide(color: _medioPagoFiltro == 'transferencia' ? const Color(0xFF6C63FF) : Colors.grey.shade300, width: 1.2),
                      ),
                    ],
                  ),
                ),
                if (filteredIngresos.isEmpty && (_medioPagoFiltro != null || query.isNotEmpty || localQ.isNotEmpty))
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
                    child: Scrollbar(
                          controller: _ingresosHScrollCtrl,
                          thumbVisibility: true,
                          trackVisibility: false,
                          thickness: 4,
                          radius: const Radius.circular(10),
                          child: SingleChildScrollView(
                            controller: _ingresosHScrollCtrl,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 12),
                            child: DataTable(
                              headingRowHeight: 38,
                              dataRowMinHeight: 40,
                              dataRowMaxHeight: 52,
                              headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.015)),
                              headingTextStyle: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: gold.withValues(alpha: 0.7), letterSpacing: 0.8),
                              dataTextStyle: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                              dividerThickness: 0.5,
                              horizontalMargin: 12,
                              columnSpacing: 10,
                              columns: const [
                                DataColumn(label: Text('CLIENTE')),
                                DataColumn(label: Text('CONCEPTO')),
                                DataColumn(label: Text('EVENTO')),
                                DataColumn(label: Text('FECHA')),
                                DataColumn(label: Text('MONTO')),
                                DataColumn(label: Text('MEDIO')),
                                DataColumn(label: Text('ACCIÓN')),
                              ],
                              rows: filteredIngresos.map((ing) {
                                // Una sola conversión UTC → reloj AR (el repo ya no aplica toAr).
                                final fechaAr = ArTime.toAr(ing.fecha);
                                final fechaStr =
                                    '${fechaAr.day.toString().padLeft(2, '0')}/${fechaAr.month.toString().padLeft(2, '0')} '
                                    '${fechaAr.hour.toString().padLeft(2, '0')}:${fechaAr.minute.toString().padLeft(2, '0')}';
                                const double actionIconSize = 18.0;
                                final actionButtonStyle = IconButton.styleFrom(
                                  minimumSize: const Size(30, 30),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
    
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      SizedBox(
                                        width: isHalf ? 90 : 130,
                                        child: Text(
                                          ing.alumnoOCliente,
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: BoxConstraints(maxWidth: isHalf ? 70 : 90),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(color: gold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                          child: Text(ing.concepto.toUpperCase(), style: TextStyle(color: gold, fontSize: 7, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      SizedBox(
                                        width: isHalf ? 60 : 75,
                                        child: Text(
                                          Evento.formatearTipo(ing.nombreEvento), 
                                          style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 9),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    ),
                                    DataCell(Text(fechaStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 9))),
                                    DataCell(Text('+${ing.monto.toCurrency()}', style: TextStyle(color: green, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 11))),
                                    DataCell(
                                      Builder(builder: (_) {
                                        final mp = ing.medioPago;
                                        final mpLower = mp?.toLowerCase().trim();
                                        if (mpLower == 'transferencia') {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.swap_horiz_rounded, size: 11, color: const Color(0xFF6C63FF)),
                                              const SizedBox(width: 3),
                                              Text('Transferencia', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF6C63FF))),
                                            ],
                                          );
                                        }
                                        if (_ingresoCuentaComoEfectivoEnListado(ing, hoyAr)) {
                                          final label = (mp == null || mp.isEmpty || mpLower == 'efectivo') ? 'Efectivo' : mp;
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.payments_outlined, size: 11, color: const Color(0xFF00B894)),
                                              const SizedBox(width: 3),
                                              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF00B894))),
                                            ],
                                          );
                                        }
                                        if (mp == null || mp.isEmpty) {
                                          return Text('—', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 10));
                                        }
                                        return Text(mp, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : Colors.black54));
                                      }),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (ing.eventoId != null)
                                            IconButton(
                                              style: actionButtonStyle,
                                              icon: Icon(Icons.celebration_rounded, size: actionIconSize, color: gold),
                                              tooltip: 'Ir al Evento',
                                              onPressed: () => _navegarAEvento(ing),
                                            ),
                                          if (ing.prestamoId != null)
                                            IconButton(
                                              style: actionButtonStyle,
                                              icon: Icon(Icons.inventory_2_outlined, size: actionIconSize, color: gold),
                                              tooltip: 'Ver préstamo / PDF acta',
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => PrestamoAlquilerDetalleScreen(prestamoId: ing.prestamoId!),
                                                  ),
                                                );
                                              },
                                            ),
                                          IconButton(
                                            style: actionButtonStyle,
                                            icon: Icon(
                                              Icons.print_rounded,
                                              size: actionIconSize,
                                              color: ing.fuente == 'Alquiler' ? gold.withValues(alpha: 0.45) : gold,
                                            ),
                                            tooltip: ing.fuente == 'Alquiler' ? 'Recibo evento no aplica — usá PDF en préstamo' : 'Imprimir Recibo',
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
    final localEg = _egresosListaSearchCtrl.text.toLowerCase().trim();
    final filteredEgresos = egresos.where((eg) {
      return _egresoCoincideTexto(eg, query) && _egresoCoincideTexto(eg, localEg);
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
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              title: Text(
                'REGISTROS DE EGRESOS (${filteredEgresos.length})',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isDark ? Colors.white60 : Colors.black54, letterSpacing: 1.5),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _egresosListaSearchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar en esta lista: proveedor, categoría, medio de pago…',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white24 : Colors.black38,
                      ),
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 22, color: gold.withValues(alpha: 0.75)),
                      suffixIcon: _egresosListaSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _egresosListaSearchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: gold.withValues(alpha: 0.55)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                if (filteredEgresos.isEmpty && (query.isNotEmpty || localEg.isNotEmpty))
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
                        headingRowHeight: 46,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 68,
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
                        rows: filteredEgresos.map((eg) {
                          // Una sola conversión UTC → reloj AR, igual que la
                          // tabla de ingresos. Leyendo `eg.fecha.day` crudo, un
                          // movimiento de las 21:30 salía fechado al día
                          // siguiente: `fecha` es UTC.
                          final fechaAr = eg.fecha != null ? ArTime.toAr(eg.fecha!) : null;
                          final fechaStr = fechaAr != null ? '${fechaAr.day.toString().padLeft(2, '0')}/${fechaAr.month.toString().padLeft(2, '0')}' : '--';
                          final cat = (eg.categoria ?? 'Otro').toUpperCase();
                          return DataRow(
                            cells: [
                              DataCell(Text(eg.proveedorVisible ?? 'S/R', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11))),
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
                                      subject: 'Acceso Recepción - Junior Eventos',
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

  /// Referencia semanal cobrada vs cupo «caja fuerte» solo uso declarativo dueño (SQLite local).

  // Se retiró `_buildCajaFuertePersonalSection`: la UI del cofre físico era
  // un segundo libro llevado a mano, en su propia tabla y sin relación con
  // los egresos, sobre la misma plata que ya informa SALDO DEL NEGOCIO.


  // ── Tab PERSONAL ───────────────────────────────────────────────────────────

  // ── RENTABILIDAD PROMEDIO HUD ──────────────────────────────────────────────
  Widget _buildRentabilidadPromedioHUD(bool isDark) {
    return Consumer(
      builder: (context, ref, _) {
        final repo = ref.watch(rentabilidadRepositoryProvider);
        return FutureBuilder<List<CalculoRentabilidad>>(
          future: repo.getHistorial(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();

            final ahora = DateTime.now();
            final limite = ahora.subtract(const Duration(days: 30));
            final recientes = snapshot.data!.where((c) => c.createdAt.isAfter(limite)).toList();
            
            if (recientes.isEmpty) return const SizedBox.shrink();
            
            double sumRentabilidad = 0;
            int countValid = 0;
            for(final c in recientes) {
               if (c.resultado != null) {
                  sumRentabilidad += c.resultado!;
                  countValid++;
               }
            }
            if (countValid == 0) return const SizedBox.shrink();
            
            final prom = sumRentabilidad / countValid;
            
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00B894).withValues(alpha: 0.3), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      const Icon(Icons.insights_rounded, color: Color(0xFF00B894), size: 18),
                      const SizedBox(width: 8),
                      Text('RENTABILIDAD PROMEDIO (30 DÍAS)', style: GoogleFonts.oswald(fontSize: 12, letterSpacing: 2, color: const Color(0xFF00B894))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    prom.toCurrency(),
                    style: GoogleFonts.oswald(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: prom >= 0 ? const Color(0xFF00B894) : const Color(0xFFE74C3C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Promedio de ganancia neta empresa en $countValid simulaciones guardadas.',
                    style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black45),
                  ),
                ],
              ),
            );
          },
        );
      },
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

class _TimelineDiaStrip extends StatefulWidget {
  const _TimelineDiaStrip({
    required this.isDark,
    required this.gold,
    required this.state,
    this.onIngresoDotTap,
    this.onEgresoDotTap,
  });

  final bool isDark;
  final Color gold;
  final FinanzasState state;
  final VoidCallback? onIngresoDotTap;
  final VoidCallback? onEgresoDotTap;

  @override
  State<_TimelineDiaStrip> createState() => _TimelineDiaStripState();
}

class _TimelineDiaStripState extends State<_TimelineDiaStrip> {
  String? _activeTip;

  void _pickTip(Offset local, TimelineDiaLayout layout) {
    // Solo se evalúa la franja del gráfico (80px); así el cursor puede bajar al texto sin perder el tip.
    if (local.dy < 0 || local.dy > 80) return;
    for (final d in layout.dots) {
      if ((local - d.center).distance <= d.hitR) {
        if (_activeTip != d.tooltip) {
          setState(() => _activeTip = d.tooltip);
        }
        return;
      }
    }
    if (_activeTip != null) {
      setState(() => _activeTip = null);
    }
  }

  void _onTapDownChart(TapDownDetails details, TimelineDiaLayout layout) {
    final p = details.localPosition;
    if (p.dy >= 0 && p.dy <= 80) {
      for (final d in layout.dots) {
        if ((p - d.center).distance <= d.hitR) {
          if (d.esIngreso) {
            widget.onIngresoDotTap?.call();
          } else {
            widget.onEgresoDotTap?.call();
          }
          return;
        }
      }
    }
    _pickTip(p, layout);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = layoutTimelineDia(widget.state, Size(constraints.maxWidth, 80));
        return MouseRegion(
          onExit: (_) {
            if (_activeTip != null) setState(() => _activeTip = null);
          },
          onHover: (event) => _pickTip(event.localPosition, layout),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                excludeFromSemantics: _tooltipExcludeSemanticsWin(),
                message: 'Tocá un punto: verde = cobros, rojo = gastos',
                child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (d) => _onTapDownChart(d, layout),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerHover: (e) => _pickTip(e.localPosition, layout),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: 80,
                    child: CustomPaint(
                      painter: TimelineDiaPainter(
                        layout: layout,
                        isDark: widget.isDark,
                        gold: widget.gold,
                      ),
                    ),
                  ),
                ),
                ),
              ),
              if (_activeTip != null) ...[
                const SizedBox(height: 8),
                Text(
                  _activeTip!,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
