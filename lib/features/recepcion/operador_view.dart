import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../models/invitado.dart';
import 'providers/recepcion_provider.dart';
import 'repositories/invitados_repository.dart';

class OperadorView extends ConsumerStatefulWidget {
  const OperadorView({super.key});

  @override
  ConsumerState<OperadorView> createState() => _OperadorViewState();
}

class _OperadorViewState extends ConsumerState<OperadorView> {
  String? _searchQuery;
  final _searchController = TextEditingController();
  bool _ordenAlfabetico = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.door_front_door_rounded, size: 20, color: gold),
            const SizedBox(width: 10),
            Text(
              'CONTROL DE ACCESO',
              style: GoogleFonts.oswald(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          if (selectedEventId != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () {
                ref.invalidate(invitadosStreamProvider(selectedEventId));
                ref.invalidate(statsEventoProvider(selectedEventId));
              },
              tooltip: 'Actualizar',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildEventSelector(isDark, gold),
            if (selectedEventId != null) ...[
              _buildStats(selectedEventId, isDark, gold),
              _buildActionBar(selectedEventId, isDark, gold),
              _buildSearchBar(isDark, gold),
              Expanded(child: _buildInvitadosList(selectedEventId, isDark, gold)),
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
        ),
      ),
    );
  }

  Widget _buildEventSelector(bool isDark, Color gold) {
    final eventosAsync = ref.watch(eventosActivosProvider);
    final selectedEventId = ref.watch(selectedEventProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
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
            initialValue: selectedEventId,
            hint: const Text('Seleccionar evento'),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.event_rounded, color: gold, size: 20),
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            items: eventos.map((evento) {
              final cliente = evento.cliente?.nombreCompleto ?? 'Sin cliente';
              final fecha = evento.fechaEvento;
              final label = '$cliente - ${evento.tipoParaMostrar} (${fecha.day}/${fecha.month}/${fecha.year})';

              return DropdownMenuItem<String>(
                value: evento.id,
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () => ref.invalidate(eventosActivosProvider),
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
        final total = stats['total'] ?? 0;
        final ingresados = stats['ingresados'] ?? 0;
        final pendientes = stats['pendientes'] ?? 0;
        final progress = total > 0 ? ingresados / total : 0.0;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _buildStatCard('TOTAL', total.toString(), Icons.people_rounded, gold, isDark),
                  const SizedBox(width: 12),
                  _buildStatCard('INGRESADOS', ingresados.toString(), Icons.check_circle_rounded, Colors.greenAccent, isDark),
                  const SizedBox(width: 12),
                  _buildStatCard('PENDIENTES', pendientes.toString(), Icons.schedule_rounded, Colors.orangeAccent, isDark),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% completado',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 4),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
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

        final sortedList = List<Invitado>.from(filtered);
        if (_ordenAlfabetico) {
          sortedList.sort((a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()));
        } else {
          sortedList.sort((a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
        }

        if (sortedList.isEmpty) {
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
          itemCount: sortedList.length,
          itemBuilder: (context, index) {
            final invitado = sortedList[index];
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

  Widget _buildInvitadoCard(Invitado invitado, bool isDark, Color gold) {
    final isIngresado = invitado.estadoIngreso == EstadoIngreso.ingresado;
    final tieneFallos = invitado.intentosFallidos > 0;
    final bloqueado = invitado.intentosFallidos >= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: bloqueado
              ? Colors.redAccent.withValues(alpha: 0.5)
              : (isIngresado
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06))),
          width: bloqueado ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: bloqueado
                ? Colors.redAccent.withValues(alpha: 0.15)
                : (isIngresado ? Colors.greenAccent : gold).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            bloqueado
                ? Icons.block_rounded
                : (isIngresado ? Icons.check_circle_rounded : Icons.person_rounded),
            color: bloqueado ? Colors.redAccent : (isIngresado ? Colors.greenAccent : gold),
            size: 24,
          ),
        ),
        title: Text(
          invitado.nombreCompleto,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            decoration: isIngresado ? TextDecoration.lineThrough : null,
            decorationColor: Colors.white54,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.table_restaurant_rounded,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Mesa: ${invitado.numeroMesa ?? 'Sin asignar'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.badge_rounded,
                    size: 14,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _maskDni(invitado.dni),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              if (tieneFallos) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: bloqueado ? Colors.redAccent : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      bloqueado
                          ? 'BLOQUEADO - Contactar operador'
                          : '${invitado.intentosFallidos} intento(s) fallido(s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: bloqueado ? Colors.redAccent : Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        trailing: isIngresado
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check, color: Colors.greenAccent, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'INGRESADO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.greenAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              )
            : bloqueado
                ? ElevatedButton(
                    onPressed: () async {
                      await _resetearIntentos(invitado.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'RESETEAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () async {
                      await _marcarIngresado(invitado.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'INGRESAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
        onTap: isIngresado
            ? null
            : bloqueado
                ? () async => await _resetearIntentos(invitado.id)
                : () async => await _marcarIngresado(invitado.id),
      ),
    );
  }

  String _maskDni(String dni) {
    if (dni.isEmpty) return '***';
    if (dni.length <= 3) return '***';
    return '${dni.substring(0, 2)}.${'*' * (dni.length - 4)}.${dni.substring(dni.length - 2)}';
  }

  Future<void> _resetearIntentos(String invitadoId) async {
    try {
      final repo = ref.read(invitadosRepositoryProvider);
      await repo.registrarIntentoFallido(invitadoId); // O resetear si es lo que se busca
      // Nota: El original usaba resetearIntentosInvitado, pero el repo tiene registrarIntentoFallido
      // y marcarIngreso. Voy a añadir resetearIntentos al repo.
      await repo.resetearIntentos(invitadoId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                SizedBox(width: 12),
                Text(
                  'Intentos reseteados correctamente',
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

  // ── Barra de acciones ─────────────────────────────────────────────────────

  Widget _buildActionBar(String eventoId, bool isDark, Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
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
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _importarCSV(eventoId),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('CSV', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _ordenAlfabetico = !_ordenAlfabetico),
              icon: Icon(_ordenAlfabetico ? Icons.sort_by_alpha : Icons.schedule, size: 18),
              label: Text(_ordenAlfabetico ? 'A-Z' : 'FECHA', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                foregroundColor: isDark ? Colors.white : Colors.black,
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

  // ── Importar CSV ──────────────────────────────────────────────────────────

  Future<void> _importarCSV(String eventoId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        dialogTitle: 'Seleccionar archivo CSV de invitados',
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString(encoding: utf8);
      final rows = const CsvDecoder().convert(content);

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El archivo está vacío'), backgroundColor: Colors.orangeAccent),
          );
        }
        return;
      }

      // Detectar headers
      final headers = rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
      final nombreIdx = headers.indexWhere((h) => h.contains('nombre'));
      final dniIdx = headers.indexWhere((h) => h.contains('dni') || h.contains('documento'));
      final mesaIdx = headers.indexWhere((h) => h.contains('mesa'));

      if (nombreIdx == -1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('CSV inválido: no se encontró columna "nombre". Usá: nombre_completo, dni, numero_mesa'),
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

        invitados.add({
          'nombre_completo': nombre,
          'dni': dniIdx != -1 && dniIdx < row.length ? row[dniIdx].toString().trim() : '',
          'numero_mesa': mesaIdx != -1 && mesaIdx < row.length ? row[mesaIdx].toString().trim() : '',
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
}

