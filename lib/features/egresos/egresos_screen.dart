import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/ar_time.dart';
import '../../models/egreso.dart';
import '../../models/evento.dart';
import '../common/widgets/admin_gate.dart';
import '../common/utils/currency_extensions.dart';
import 'widgets/registrar_egreso_global_dialog.dart';
import 'providers/egresos_provider.dart';

class EgresosScreen extends ConsumerStatefulWidget {
  const EgresosScreen({super.key});

  @override
  ConsumerState<EgresosScreen> createState() => _EgresosScreenState();
}

class _EgresosScreenState extends ConsumerState<EgresosScreen> {
  // Filtro de categoría activo (se mantiene local al widget)
  String? _filtroCategoria;

  static const _expenseRed = Color(0xFFE74C3C);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Observamos los providers reactivos
    final egresosAsync = ref.watch(egresosProvider);
    final stats = ref.watch(egresosStatsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'GESTIÓN DE EGRESOS',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFD4AF37)),
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            tooltip: 'Inicio',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(egresosProvider.notifier).refresh(),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final hPad = w > 900 ? 40.0 : w > 600 ? 24.0 : 16.0;

              return egresosAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: _expenseRed)),
                error: (err, stack) => Center(child: Text('Error: $err')),
                data: (data) {
                  final egresosFiltrados = _filtroCategoria == null 
                      ? data 
                      : data.where((e) => e['categoria'] == _filtroCategoria).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header con KPIs ──────────────────────────────
                      Padding(
                        padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
                        child: _buildHeader(isDark, stats['totalMes'] as double, stats['totalGeneral'] as double),
                      ),
                      const SizedBox(height: 16),

                      // ── Gráfico por categoría ────────────────────────
                      if (data.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 0),
                          child: _buildCategoryChart(
                            isDark, 
                            stats['totalesPorCategoria'] as Map<String, double>,
                            stats['conteoPorCategoria'] as Map<String, int>,
                          ),
                        ),
                      const SizedBox(height: 14),

                      // ── Filtros de categoría ─────────────────────────
                      if ((stats['categorias'] as Set<String>).isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: hPad),
                          child: _buildFiltros(isDark, data, stats['categorias'] as Set<String>, stats['conteoPorCategoria'] as Map<String, int>),
                        ),
                      const SizedBox(height: 10),

                      // ── Lista de egresos ─────────────────────────────
                      Expanded(
                        child: egresosFiltrados.isEmpty
                            ? _buildEmptyState(isDark)
                            : ListView.builder(
                                padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 100),
                                itemCount: egresosFiltrados.length,
                                itemBuilder: (context, index) {
                                  final item = egresosFiltrados[index];
                                  final egreso = Egreso.fromJson(item);
                                  final evento = item['eventos'];
                                  return TweenAnimationBuilder<double>(
                                    duration: Duration(milliseconds: 300 + (index * 30).clamp(0, 300)),
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    builder: (context, value, child) => Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 16 * (1 - value)),
                                        child: child,
                                      ),
                                    ),
                                    child: _buildEgresoRow(egreso, evento, isDark),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ── Header con 2 KPIs ──────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark, double totalMes, double totalGeneral) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 44,
          decoration: BoxDecoration(color: _expenseRed, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EGRESOS',
                style: GoogleFonts.oswald(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 0.5, height: 1.1),
              ),
              Text(
                'Control de gastos y flujo de caja',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildKpiMini(
          label: 'ESTE MES',
          value: totalMes.toCurrency(),
          color: _expenseRed,
          isDark: isDark,
        ),
        const SizedBox(width: 10),
        _buildKpiMini(
          label: 'TOTAL',
          value: totalGeneral.toCurrency(),
          color: Colors.orangeAccent,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildKpiMini({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: isDark ? Colors.white38 : Colors.black38),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart(bool isDark, Map<String, double> totales, Map<String, int> conteo) {
    if (totales.isEmpty) return const SizedBox.shrink();
    final maxVal = totales.values.reduce((a, b) => a > b ? a : b);
    final sorted = totales.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 13, color: _expenseRed),
              const SizedBox(width: 7),
              const Text(
                'DISTRIBUCIÓN POR CATEGORÍA',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sorted.map((entry) {
            final color = _getCategoryColor(entry.key);
            final ratio = maxVal > 0 ? (entry.value / maxVal).clamp(0.0, 1.0) : 0.0;
            final count = conteo[entry.key] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 7,
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    entry.value.toCurrency(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color),
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

  Widget _buildFiltros(bool isDark, List<Map<String, dynamic>> data, Set<String> categorias, Map<String, int> conteo) {
    final cats = ['Todos', ...categorias.toList()..sort()];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, i) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final cat = cats[i];
          final isAll = cat == 'Todos';
          final isActive = isAll ? _filtroCategoria == null : _filtroCategoria == cat;
          final color = isAll ? _expenseRed : _getCategoryColor(cat);
          final count = isAll ? data.length : (conteo[cat] ?? 0);
          return GestureDetector(
            onTap: () => setState(() => _filtroCategoria = isAll ? null : cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? color : (isDark ? Colors.white.withValues(alpha: 0.04) : Theme.of(context).cardColor),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? color : color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cat.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: isActive ? Colors.white : color,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white.withValues(alpha: 0.25) : color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: isActive ? Colors.white : color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEgresoRow(Egreso egreso, dynamic eventoData, bool isDark) {
    final catColor = _getCategoryColor(egreso.categoria);
    final clienteNombre = eventoData?['clientes']?['nombre_completo'] ?? 'General';
    final tipoEvento = Evento.formatearTipo(eventoData?['tipo'] as String?);
    final fecha = egreso.fecha;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getCategoryIcon(egreso.categoria), color: catColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (egreso.proveedorVisible ?? 'GASTO OPERATIVO').toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (egreso.categoria ?? 'Otro').toUpperCase(),
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: catColor, letterSpacing: 0.5),
                      ),
                    ),
                    if (tipoEvento.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${clienteNombre.toUpperCase()} · $tipoEvento'.toUpperCase(),
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                egreso.monto.toCurrency(),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: _expenseRed, letterSpacing: -0.3),
              ),
              if (fecha != null)
                Text(
                  // `Egreso.fecha` es UTC: leído crudo, un egreso de las 21:30
                  // se mostraba fechado al día siguiente.
                  ArTime.formatFechaCorta(fecha),
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _expenseRed.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined, size: 40, color: _expenseRed),
          ),
          const SizedBox(height: 16),
          Text(
            _filtroCategoria != null ? 'SIN EGRESOS EN ESTA CATEGORÍA' : 'SIN EGRESOS REGISTRADOS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _filtroCategoria != null ? 'Probá con otro filtro.' : 'Registrá tu primer gasto con el botón.',
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white24 : Colors.black26),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _expenseRed.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: FloatingActionButton.extended(
        onPressed: () async {
          final hasAccess = await AdminGate.check(context, ref);
          if (!hasAccess || !mounted) return;
          await showDialog<bool>(
            context: context,
            builder: (_) => const RegistrarEgresoGlobalDialog(),
          );
          // Ya no necesitamos _fetchEgresos() manual, el stream lo manejará.
        },
        backgroundColor: _expenseRed,
        label: const Text('REGISTRAR PAGO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12)),
        icon: const Icon(Icons.add_circle_outline, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Color _getCategoryColor(String? cat) {
    switch (cat) {
      case 'Personal':
      case 'Operadores': return Colors.blueAccent;
      case 'Alquiler': return Colors.purpleAccent;
      case 'Catering': return Colors.greenAccent;
      case 'Bebida': return Colors.cyanAccent;
      case 'Proveedor': return Colors.orangeAccent;
      default: return Colors.orangeAccent;
    }
  }

  IconData _getCategoryIcon(String? cat) {
    switch (cat) {
      case 'Personal':
      case 'Operadores': return Icons.engineering_outlined;
      case 'Alquiler': return Icons.home_work_outlined;
      case 'Catering': return Icons.restaurant_menu_rounded;
      case 'Bebida': return Icons.local_bar_rounded;
      case 'Proveedor': return Icons.handshake_outlined;
      default: return Icons.account_balance_wallet_outlined;
    }
  }
}
