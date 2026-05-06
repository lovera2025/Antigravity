import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import '../../core/services/sync_engine.dart';
import '../../models/invitado.dart';
import '../totem/totem_panel.dart';
import 'providers/recepcion_provider.dart';
import 'repositories/invitados_repository.dart';
import '../../core/services/kiosk_launcher.dart';

class RecepcionUnifiedScreen extends ConsumerStatefulWidget {
  const RecepcionUnifiedScreen({super.key});

  @override
  ConsumerState<RecepcionUnifiedScreen> createState() => _RecepcionUnifiedScreenState();
}

class _RecepcionUnifiedScreenState extends ConsumerState<RecepcionUnifiedScreen> {
  static const _perla = Color(0xFFE2E2E2);
  
  TotemPanelMode _totemMode = TotemPanelMode.panel;
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final selectedEventId = ref.watch(selectedEventProvider);

    return PopScope(
      canPop: _totemMode == TotemPanelMode.panel,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _totemMode != TotemPanelMode.panel) {
          setState(() => _totemMode = TotemPanelMode.panel);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.door_front_door_rounded, size: 20, color: _perla),
              const SizedBox(width: 10),
              Text(
                'RECEPCIÓN UNIFICADA',
                style: GoogleFonts.oswald(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: _perla,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: _buildLayout(screenWidth, isDark, selectedEventId),
        ),
      ),
    );
  }

  Widget _buildLayout(double screenWidth, bool isDark, String? selectedEventId) {
    if (screenWidth > 1400) {
      return _buildSplitViewLayout(isDark, selectedEventId);
    } else if (screenWidth > 800) {
      return _buildTabsLayout(isDark, selectedEventId);
    } else {
      return _buildStackLayout(isDark, selectedEventId);
    }
  }

  // ── SPLIT VIEW (screenWidth > 1400px) ──────────────────────────────────────

  Widget _buildSplitViewLayout(bool isDark, String? selectedEventId) {
    return Row(
      children: [
        Expanded(
          flex: 45,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
            ),
            child: const OperadorViewContent(),
          ),
        ),
        Expanded(
          flex: 55,
          child: selectedEventId != null
              ? _buildTotemWithModeButtons(selectedEventId, isDark)
              : _buildNoEventSelected(),
        ),
      ],
    );
  }

  // ── TABS (800px < screenWidth <= 1400px) ────────────────────────────────

  Widget _buildTabsLayout(bool isDark, String? selectedEventId) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: 'RECEPCIÓN',
                  icon: Icons.door_front_door_rounded,
                  isSelected: _selectedTab == 0,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _TabButton(
                  label: 'VISTA TÓTEM',
                  icon: Icons.monitor_rounded,
                  isSelected: _selectedTab == 1,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedTab == 0
              ? const OperadorViewContent()
              : (selectedEventId != null
                  ? _buildTotemWithModeButtons(selectedEventId, isDark)
                  : _buildNoEventSelected()),
        ),
      ],
    );
  }

  // ── STACK VERTICAL (screenWidth < 800px) ────────────────────────────────

  Widget _buildStackLayout(bool isDark, String? selectedEventId) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.door_front_door_rounded, color: _perla, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'OPERADOR',
                            style: GoogleFonts.oswald(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: _perla,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 500,
                        child: const OperadorViewContent(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tv_rounded, color: Colors.purpleAccent, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'TÓTEM',
                            style: GoogleFonts.oswald(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (selectedEventId != null)
                        _buildTotemWithModeButtons(selectedEventId, isDark)
                      else
                        _buildNoEventSelected(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Totem con botones de modo ──────────────────────────────────────────────

  Widget _buildTotemWithModeButtons(String eventoId, bool isDark) {
    return Stack(
      children: [
        TotemPanel(
          eventoId: eventoId,
          onModeChanged: () {
            setState(() {});
          },
          showModeButtons: true,
        ),
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Controles de Ventana (Solo si hay tótem activo) ──────────
              if (KioskLauncher.isTotemActive) ...[
                Tooltip(
                  message: 'Cerrar ventana del tótem',
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'close_totem',
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                    onPressed: () => KioskLauncher.close().then((_) => setState(() {})),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Maximizar / Restaurar tótem',
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'maximize_totem',
                    backgroundColor: Colors.blueAccent.withValues(alpha: 0.8),
                    onPressed: () => KioskLauncher.maximize(),
                    child: const Icon(Icons.fullscreen, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Minimizar tótem',
                  child: FloatingActionButton(
                    mini: true,
                    heroTag: 'minimize_totem',
                    backgroundColor: Colors.orangeAccent.withValues(alpha: 0.8),
                    onPressed: () => KioskLauncher.minimize(),
                    child: const Icon(Icons.minimize, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 12),
              ],
              // ── Modos del panel embebido ───────────────────────────────────
              FloatingActionButton(
                mini: true,
                heroTag: 'panel_mode',
                backgroundColor: _totemMode == TotemPanelMode.panel ? _perla : Colors.grey,
                tooltip: 'Vista panel',
                onPressed: () => setState(() => _totemMode = TotemPanelMode.panel),
                child: const Icon(Icons.dashboard, color: Colors.black, size: 18),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                mini: true,
                heroTag: 'fullscreen_mode',
                backgroundColor: _totemMode == TotemPanelMode.fullscreen ? _perla : Colors.grey,
                tooltip: 'Pantalla completa (en esta ventana)',
                onPressed: () => setState(() => _totemMode = TotemPanelMode.fullscreen),
                child: const Icon(Icons.fullscreen, color: Colors.black, size: 18),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                mini: true,
                heroTag: 'focus_mode',
                backgroundColor: _totemMode == TotemPanelMode.focus ? _perla : Colors.grey,
                tooltip: 'Modo foco',
                onPressed: () => setState(() => _totemMode = TotemPanelMode.focus),
                child: const Icon(Icons.visibility, color: Colors.black, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoEventSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_rounded,
            size: 80,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'Seleccioná un evento para comenzar',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Button ─────────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const perla = Color(0xFFE2E2E2);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? perla : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? perla : Colors.white38,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.oswald(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: isSelected ? perla : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── OperadorViewContent (sin AppBar) ───────────────────────────────────────

class OperadorViewContent extends ConsumerStatefulWidget {
  const OperadorViewContent({super.key});

  @override
  ConsumerState<OperadorViewContent> createState() => _OperadorViewContentState();
}

class _OperadorViewContentState extends ConsumerState<OperadorViewContent> {
  String? _searchQuery;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const perla = Color(0xFFE2E2E2);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Column(
      children: [
        _buildEventSelector(isDark, perla),
        if (selectedEventId != null) ...[
          _buildStats(selectedEventId, isDark, perla),
          _buildActionBar(selectedEventId, isDark, perla),
          _buildSearchBar(isDark, perla),
          Expanded(child: _buildInvitadosList(selectedEventId, isDark, perla)),
        ] else
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 80,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Seleccioná un evento para comenzar',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEventSelector(bool isDark, Color gold) {
    final eventosAsync = ref.watch(eventosActivosProvider);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.01) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: eventosAsync.when(
        data: (eventos) {
          if (eventos.isEmpty) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No hay eventos activos disponibles',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }

          return DropdownButtonFormField<String>(
            key: ValueKey(selectedEventId),
            initialValue: selectedEventId,
            hint: Text(
              'Seleccionar evento activo...',
              style: GoogleFonts.outfit(fontSize: 14, color: isDark ? Colors.white38 : Colors.black38),
            ),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: gold),
            dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.event_available_rounded, color: gold, size: 20),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.01),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: gold, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: eventos.map((evento) {
              final cliente = evento.cliente?.nombreCompleto ?? 'Sin cliente';
              final fecha = evento.fechaEvento;
              final label = '$cliente — ${evento.tipoParaMostrar} (${fecha.day}/${fecha.month})';

              return DropdownMenuItem<String>(
                value: evento.id,
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.oswald(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (value) {
              ref.read(selectedEventProvider.notifier).select(value);
              _searchController.clear();
              setState(() => _searchQuery = null);
            },
            isExpanded: true,
          );
        },
        loading: () => LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          color: gold,
        ),
        error: (error, stack) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Error al cargar eventos: ${error.toString()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(String eventoId, bool isDark, Color gold) {
    final statsAsync = ref.watch(statsEventoProvider(eventoId));

    return statsAsync.when(
      data: (stats) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              _buildStatItem('TOTAL', stats['total'] ?? 0, Icons.people_rounded, gold, isDark),
              const SizedBox(width: 12),
              _buildStatItem('INGRESADOS', stats['ingresados'] ?? 0, Icons.check_circle_outline_rounded, Colors.greenAccent, isDark),
              const SizedBox(width: 12),
              _buildStatItem('PENDIENTES', stats['pendientes'] ?? 0, Icons.hourglass_empty_rounded, Colors.orangeAccent, isDark),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 4),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatItem(String label, int value, IconData icon, Color color, bool isDark) {
    const perla = Color(0xFFE2E2E2);
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? perla.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: GoogleFonts.oswald(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: isDark ? perla : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre...',
          prefixIcon: Icon(Icons.search, color: gold, size: 20),
          suffixIcon: _searchQuery != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = null);
                  },
                )
              : null,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: gold, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      ),
    );
  }

  Widget _buildInvitadosList(String eventoId, bool isDark, Color gold) {
    final invitadosAsync = ref.watch(invitadosStreamProvider(eventoId));

    return invitadosAsync.when(
      data: (invitados) {
        final filtered = _searchQuery == null || _searchQuery!.isEmpty
            ? invitados
            : invitados.where((i) => i.nombreCompleto.toLowerCase().contains(_searchQuery!)).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _searchQuery != null ? Icons.search_off : Icons.people_outline,
                  size: 80,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery != null ? 'No se encontraron resultados' : 'No hay invitados registrados',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final invitado = filtered[index];
            return _buildInvitadoCard(invitado, isDark, gold);
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 60),
              const SizedBox(height: 16),
              const Text(
                'Error de conexión',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(invitadosStreamProvider(eventoId)),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('REINTENTAR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvitadoCard(Invitado invitado, bool isDark, Color perlaAccent) {
    final isIngresado = invitado.estadoIngreso == EstadoIngreso.ingresado;
    final perla = const Color(0xFFE2E2E2);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isIngresado
              ? Colors.greenAccent.withValues(alpha: 0.2)
              : (isDark ? perla.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            leading: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (isIngresado ? Colors.greenAccent : perla).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isIngresado ? Colors.greenAccent : perla).withValues(alpha: 0.15),
                ),
              ),
              child: Icon(
                isIngresado ? Icons.check_circle_rounded : Icons.person_rounded,
                color: isIngresado ? Colors.greenAccent : perla,
                size: 22,
              ),
            ),
            title: Text(
              invitado.nombreCompleto.toUpperCase(),
              style: GoogleFonts.oswald(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: isIngresado ? (isDark ? Colors.white24 : Colors.black26) : (isDark ? perla : Colors.black),
                decoration: isIngresado ? TextDecoration.lineThrough : null,
              ),
            ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_restaurant_rounded,
                        size: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'MESA: ${invitado.numeroMesa ?? "—"}',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isIngresado) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.greenAccent.withValues(alpha: 0.2),
                        Colors.greenAccent.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                  ),
                  child: Center(
                    child: Text(
                      'ADENTRO',
                      style: GoogleFonts.oswald(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Colors.greenAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.orangeAccent, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmarDeshacerIngreso(invitado, context),
                ),
              ] else
                ElevatedButton(
                  onPressed: () => _marcarIngresado(invitado.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: perlaAccent.withValues(alpha: 0.1),
                    foregroundColor: perlaAccent,
                    elevation: 0,
                    side: BorderSide(color: perlaAccent.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'REGISTRAR',
                    style: GoogleFonts.oswald(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, 
                  color: isDark ? Colors.white24 : Colors.black26, 
                  size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmarEliminarInvitado(invitado, context),
              ),
            ],
          ),
          onTap: isIngresado ? null : () => _marcarIngresado(invitado.id),
        ),
      ),
    ),
  );
}

  Future<void> _marcarIngresado(String invitadoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.marcarIngreso(invitadoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                SizedBox(width: 12),
                Text(
                  'Ingreso registrado correctamente',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error: ${e.toString()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _confirmarDeshacerIngreso(Invitado invitado, BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer Ingreso'),
        content: Text('¿Estás seguro de deshacer el ingreso de ${invitado.nombreCompleto}? Volverá a la lista de pendientes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DESHACER'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(invitadosRepositoryProvider);
        await repo.deshacerIngreso(invitado.id);
        
        // Refrescar UI Stats
        ref.invalidate(statsEventoProvider(invitado.eventoId));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se deshizo el ingreso correctamente'), backgroundColor: Colors.orangeAccent),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _confirmarEliminarInvitado(Invitado invitado, BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Participante', style: TextStyle(color: Colors.redAccent)),
        content: Text('¿Realmente deseas eliminar a ${invitado.nombreCompleto}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(invitadosRepositoryProvider);
        await repo.eliminar(invitado.id);
        
        // Forzar sync inmediato y refresco de stats para reacción instántanea
        ref.read(syncEngineProvider).syncNow();
        ref.invalidate(statsEventoProvider(invitado.eventoId));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Participante eliminado correctamente'), backgroundColor: Colors.redAccent),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _confirmarVaciarLista(String eventoId, BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vaciar Toda la Lista', style: TextStyle(color: Colors.redAccent)),
        content: const Text('¡ATENCIÓN! ¿Estás seguro de que querés ELIMINAR COMPLETAMENTE a todos los invitados de este evento?\n\nEsta acción borrará el historial entero de este evento para que ingreses una nueva lista de otra fiesta. Es irreversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('VACIAR LISTA'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final repo = ref.read(invitadosRepositoryProvider);
        await repo.vaciarEvento(eventoId);
        
        // Forzar sync inmediato para que repercuta en la nube en el momento
        ref.read(syncEngineProvider).syncNow();
        
        // Notificar al tótem para reflejo inmediato sin esperar sync
        if (KioskLauncher.isTotemActive) {
          KioskLauncher.notifyListReset();
        }

        // Invalidar para que refresque stats y lista inmediatamente en el operador
        ref.invalidate(invitadosStreamProvider(eventoId));
        ref.invalidate(statsEventoProvider(eventoId));
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Se eliminaron todos los invitados. Lista vacía.'), backgroundColor: Colors.redAccent),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  Future<void> _refreshList(String eventoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.forceRefresh(eventoId);
      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lista actualizada'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Barra de acciones ─────────────────────────────────────────────────────

  Widget _buildActionBar(String eventoId, bool isDark, Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _refreshList(eventoId),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ACTUALIZAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                foregroundColor: isDark ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _agregarInvitado(eventoId),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('AGREGAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _importarArchivo(eventoId),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('IMPORTAR LISTA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _exportarExcel(eventoId),
              icon: const Icon(Icons.table_view_rounded, size: 18),
              label: const Text('EXPORTAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmarVaciarLista(eventoId, context),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: const Text('VACIAR LISTA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Agregar invitado manual ────────────────────────────────────────────────

  Future<void> _agregarInvitado(String eventoId) async {
    final nombreCtrl = TextEditingController();
    final dniCtrl = TextEditingController();
    final mesaCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Invitado'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dniCtrl,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'DNI *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                  helperText: 'Obligatorio para la seguridad del check-in',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mesaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Mesa (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.table_restaurant),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final nombre = nombreCtrl.text.trim();
              final dni = dniCtrl.text.trim();
              if (nombre.isEmpty || dni.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Nombre y DNI son obligatorios'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.agregar(
        eventoId: eventoId,
        nombreCompleto: nombreCtrl.text.trim(),
        dni: dniCtrl.text.trim(),
        numeroMesa: mesaCtrl.text.trim().isNotEmpty ? mesaCtrl.text.trim() : null,
      );
      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitado agregado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ── Importar archivo (Excel o CSV) ─────────────────────────────────────────

  Future<void> _importarArchivo(String eventoId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt'],
        dialogTitle: 'Seleccionar archivo (Excel o CSV) de invitados',
      );

      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path!;
      final isExcel = path.toLowerCase().endsWith('.xlsx');
      final file = File(path);
      
      List<List<dynamic>> rows = [];

      if (isExcel) {
        // Lectura de Excel Nativo
        final bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        // Usar la primera hoja que contenga datos
        var sheetName = excel.tables.keys.first;
        var sheet = excel.tables[sheetName]!;
        
        for (var row in sheet.rows) {
          // Convertir celdas a strings planos
          rows.add(row.map((cell) => cell?.value?.toString().trim() ?? "").toList());
        }
      } else {
        // Lectura de CSV Tradicional
        final content = await file.readAsString(encoding: utf8);
        String delimiter = ',';
        if (content.contains(';')) delimiter = ';';
        rows = CsvDecoder(fieldDelimiter: delimiter).convert(content);
      }

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El archivo está vacío'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Detectar headers (con soporte para nombres amigables de Excel)
      final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
      final nombreIdx = headers.indexWhere((h) => h.contains('nombre'));
      final dniIdx = headers.indexWhere((h) => h.contains('dni') || h.contains('documento'));
      final mesaIdx = headers.indexWhere((h) => h.contains('mesa'));

      if (nombreIdx == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: No se encontró la columna "Nombre". El archivo debe tener encabezados.'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Parsear filas (saltar header)
      final invitados = <Map<String, String>>[];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        final nombre = nombreIdx < row.length ? row[nombreIdx].toString().trim() : '';
        if (nombre.isEmpty) continue;

        String rawDni = dniIdx != -1 && dniIdx < row.length ? row[dniIdx].toString().trim() : '';
        if (rawDni.endsWith('.0')) rawDni = rawDni.substring(0, rawDni.length - 2);

        String rawMesa = mesaIdx != -1 && mesaIdx < row.length ? row[mesaIdx].toString().trim() : '';
        if (rawMesa.endsWith('.0')) rawMesa = rawMesa.substring(0, rawMesa.length - 2);

        invitados.add({
          'nombre_completo': nombre,
          'dni': rawDni,
          'numero_mesa': rawMesa,
        });
      }

      if (invitados.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se encontraron invitados válidos en el CSV'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Confirmar importación
      if (!mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Importación'),
          content: Text('Se importarán ${invitados.length} invitados al evento.\n\n¿Confirmar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('IMPORTAR'),
            ),
          ],
        ),
      );

      if (confirmar != true) return;

      final repo = ref.read(invitadosRepositoryProvider);
      final count = await repo.agregarBatch(eventoId: eventoId, invitados: invitados);

      // DISPARAR SYNC: Muy importante para que aparezcan en el celu/tótem al instante
      ref.read(syncEngineProvider).syncNow();

      ref.invalidate(invitadosStreamProvider(eventoId));
      ref.invalidate(statsEventoProvider(eventoId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Se importaron $count invitados correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al importar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  // ── Exportar Excel ─────────────────────────────────────────────────────────

  Future<void> _exportarExcel(String eventoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      final invitados = await repo.getByEvento(eventoId);

      // Obtener nombre del evento para el nombre del archivo
      final eventosAsync = ref.read(eventosActivosProvider);
      String nombreEvento = 'plantilla';
      
      eventosAsync.whenData((list) {
        final ev = list.firstWhere((e) => e.id == eventoId);
        final cliente = ev.cliente?.nombreCompleto ?? 'Invitados';
        nombreEvento = cliente.replaceAll(' ', '_').toLowerCase();
      });

      // Crear archivo Excel usando la librería 'excel'
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Sheet1'];
      
      // Estilo para el encabezado (negrita)
      CellStyle headerStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('#D4AF37'), // Color oro elegante
        fontColorHex: ExcelColor.fromHexString('#000000'),
      );

      // Encabezados
      var headers = ['Nombre y Apellido', 'DNI (Documento)', 'Nro de Mesa / Ubicación'];
      for (var i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // Datos
      for (int i = 0; i < invitados.length; i++) {
        final inv = invitados[i];
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = TextCellValue(inv.nombreCompleto);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = TextCellValue(inv.dni);
        sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1)).value = TextCellValue(inv.numeroMesa ?? '');
      }

      // Auto-ajustar ancho de columnas
      sheetObject.setColumnWidth(0, 30);
      sheetObject.setColumnWidth(1, 15);
      sheetObject.setColumnWidth(2, 20);

      var fileBytes = excel.save();
      
      if (!mounted) return;

      // Diálogo nativo de Windows "Guardar como"
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '¿Dónde querés guardar la lista de invitados?',
        fileName: 'Invitados_$nombreEvento.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) return; // Usuario canceló

      // Si el archivo no tiene la extensión, se la agregamos
      if (!outputFile.toLowerCase().endsWith('.xlsx')) {
        outputFile += '.xlsx';
      }

      final file = File(outputFile);
      await file.writeAsBytes(fileBytes!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                SizedBox(width: 12),
                Text('✅ Excel guardado correctamente en tu PC'),
              ],
            ),
            backgroundColor: Color(0xFF1A1A1A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
