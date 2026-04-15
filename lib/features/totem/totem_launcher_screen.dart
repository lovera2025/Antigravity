import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/evento.dart';
import '../recepcion/providers/recepcion_provider.dart';
import 'totem_panel.dart';

/// Pantalla de lanzamiento del Tótem desde el Dashboard.
///
/// Muestra directamente el [TotemPanel] con el QR y la animación de bienvenida,
/// y un selector de evento flotante en la parte inferior para elegir el evento activo.
/// De esta forma, el operador puede activar el tótem desde el Dashboard
/// y la animación se dispara apenas se produce un check-in.
class TotemLauncherScreen extends ConsumerStatefulWidget {
  const TotemLauncherScreen({super.key});

  @override
  ConsumerState<TotemLauncherScreen> createState() =>
      _TotemLauncherScreenState();
}

class _TotemLauncherScreenState extends ConsumerState<TotemLauncherScreen> {
  static const _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final selectedEventId = ref.watch(selectedEventProvider);
    final eventosAsync = ref.watch(eventosActivosProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Panel Tótem Full ───────────────────────────────────────────────
          if (selectedEventId != null)
            TotemPanel(
              eventoId: selectedEventId,
              showModeButtons: false,
            )
          else
            _buildWaitingState(),

          // ── Barra superior con botón salir ─────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white70, size: 20),
                    ),
                  ),
                  const Spacer(),
                  // Indicador de evento activo
                  if (selectedEventId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _gold.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'TÓTEM ACTIVO',
                            style: GoogleFonts.oswald(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: _gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Selector de evento — Panel inferior ────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildEventSelector(eventosAsync, selectedEventId),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingState() {
    return Container(
      color: const Color(0xFF080410),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tv_rounded,
              size: 80,
              color: _gold.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 24),
            Text(
              'SELECCIONÁ UN EVENTO',
              style: GoogleFonts.oswald(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'para activar el tótem',
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventSelector(
    AsyncValue<List<Evento>> eventosAsync,
    String? selectedId,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0618).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.1),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: eventosAsync.when(
        data: (eventos) {
          if (eventos.isEmpty) {
            return Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orangeAccent, size: 20),
                const SizedBox(width: 12),
                Text(
                  'No hay eventos activos disponibles',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Icon(Icons.event_rounded, color: _gold, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId,
                    hint: Text(
                      'Elegí un evento...',
                      style: GoogleFonts.outfit(
                        color: Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                    dropdownColor: const Color(0xFF1C0F35),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: Icon(Icons.expand_less, color: _gold, size: 22),
                    isExpanded: true,
                    items: eventos.map((evento) {
                      final cliente =
                          evento.cliente?.nombreCompleto ?? 'Sin cliente';
                      final fecha = evento.fechaEvento;
                      final label =
                          '$cliente — ${evento.tipoParaMostrar} (${fecha.day}/${fecha.month}/${fecha.year})';
                      return DropdownMenuItem<String>(
                        value: evento.id,
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      ref
                          .read(selectedEventProvider.notifier)
                          .select(value);
                    },
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Color(0xFFD4AF37), strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Cargando eventos...',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
        error: (e, _) => Text(
          'Error al cargar eventos',
          style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 13),
        ),
      ),
    );
  }
}
