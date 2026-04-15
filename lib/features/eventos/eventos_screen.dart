import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/evento.dart';
import 'crear_evento_screen.dart';
import 'detalle_evento_masivo_screen.dart';
import 'detalle_evento_particular_screen.dart';
import '../common/widgets/animated_background.dart';
import 'repositories/eventos_repository.dart';

class EventosScreen extends ConsumerStatefulWidget {
  /// modalidad: 'particular', 'masivo' o null para todos
  final String? modalidad;

  const EventosScreen({super.key, this.modalidad});

  @override
  ConsumerState<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends ConsumerState<EventosScreen> {
  bool _isLoading = true;
  List<Evento> _eventos = [];
  String _searchQuery = '';
  final _searchController = TextEditingController();
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetchEventos();
    _setupRealtime();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchEventos({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final repo = ref.read(eventosRepositoryProvider);
      final data = await repo.getAll(modalidad: widget.modalidad);

      if (!mounted) return;
      setState(() {
        _eventos = data;
      });
    } catch (e, stack) {
      debugPrint('Error cargando eventos: $e');
      debugPrint('$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar eventos: $e')),
        );
      }
    } finally {
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  void _setupRealtime() {
    final repo = ref.read(eventosRepositoryProvider);
    _channel = repo.subscribeToChanges(() {
      debugPrint('REALTIME: Cambio detectado en tabla eventos');
      if (!_isLoading) {
        _fetchEventos(showLoading: false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool esMasivo = widget.modalidad == 'masivo';
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          esMasivo ? 'GESTIÓN DE RECEPCIONES / MASIVOS' : 'GESTIÓN DE EVENTOS',
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFD4AF37)),
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
            tooltip: 'Volver al Inicio',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchEventos,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: _buildPremiumFAB(),
      body: AnimatedBackground(
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                : SafeArea(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          children: [
                            // --- BARRA DE BÚSQUEDA PREMIUM (GLASS) ---
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    if (Theme.of(context).brightness == Brightness.light)
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    hintText: 'Buscar por cliente, tipo o fecha...',
                                    hintStyle: TextStyle(
                                      color: (Theme.of(context).brightness == Brightness.dark 
                                          ? Colors.white 
                                          : Colors.black).withValues(alpha: 0.3),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFD4AF37), size: 22),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  ),
                                ),
                              ),
                            ),
                            
                            Expanded(
                              child: () {
                                final filtered = _eventos.where((ev) {
                                  final q = _searchQuery.toLowerCase();
                                  if (q.isEmpty) return true;
                                  
                                  final cliente = (ev.cliente?.nombreCompleto ?? '').toLowerCase();
                                  final tipo = ev.tipoParaMostrar.toLowerCase();
                                  final fecha = "${ev.fechaEvento.day}/${ev.fechaEvento.month}/${ev.fechaEvento.year}";
                                  
                                  return cliente.contains(q) || tipo.contains(q) || fecha.contains(q);
                                }).toList();

                                if (filtered.isEmpty) {
                                  return Center(
                                    child: Text(
                                      _eventos.isEmpty ? 'No hay eventos registrados.' : 'No se encontraron resultados.',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  );
                                }

                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final evento = filtered[index];
                                    return TweenAnimationBuilder<double>(
                                      duration: Duration(milliseconds: 400 + (index * 50)),
                                      tween: Tween(begin: 0.0, end: 1.0),
                                      builder: (context, value, child) {
                                        return Opacity(
                                          opacity: value,
                                          child: Transform.translate(
                                            offset: Offset(0, 30 * (1 - value)),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: _buildEliteEventoCard(evento),
                                    );
                                  },
                                );
                              }(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CrearEventoScreen()),
          ).then((_) => _fetchEventos());
        },
        backgroundColor: const Color(0xFFD4AF37),
        label: const Text('NUEVO EVENTO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 12)),
        icon: const Icon(Icons.add, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildEliteEventoCard(Evento evento) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGold = const Color(0xFFD4AF37);
    final bool esMasivo = evento.modalidad == 'masivo';

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: esMasivo 
            ? (isDark ? Colors.blueAccent.withValues(alpha: 0.05) : Colors.blueGrey.withValues(alpha: 0.04))
            : (isDark ? Colors.white.withValues(alpha: 0.02) : Theme.of(context).cardColor),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: esMasivo
              ? Colors.blueAccent.withValues(alpha: 0.4)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
          width: esMasivo ? 1.6 : 1.0,
        ),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () {
            if (evento.modalidad == 'masivo') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetalleEventoMasivoScreen(evento: evento)),
              ).then((_) => _fetchEventos());
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetalleEventoParticularScreen(evento: evento)),
              ).then((_) => _fetchEventos());
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: esMasivo ? Colors.blueAccent.withValues(alpha: 0.12) : primaryGold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: esMasivo 
                        ? const Icon(Icons.school_rounded, color: Colors.blueAccent, size: 28)
                        : Image.asset(
                            evento.iconoPath,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(Icons.celebration_outlined, color: primaryGold),
                          ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            evento.cliente?.nombreCompleto ?? 'CLIENTE PREMIUM',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_month_outlined, size: 14, color: primaryGold.withValues(alpha: 0.6)),
                              const SizedBox(width: 8),
                              Text(
                                "${evento.fechaEvento.day}/${evento.fechaEvento.month}/${evento.fechaEvento.year}",
                                style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.grey)),
                              const SizedBox(width: 12),
                              Text(
                                evento.tipoParaMostrar.toUpperCase(),
                                style: TextStyle(color: primaryGold.withValues(alpha: 0.7), fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (esMasivo)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.school_rounded, size: 14, color: Colors.blueAccent),
                                SizedBox(width: 6),
                                Text(
                                  'EVENTO MASIVO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildStatusBadge(evento.estado),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // BLOQUE LOGÍSTICO (Privacidad de Datos Financieros)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.01) : Colors.grey[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('FECHA DEL EVENTO', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.event_available_rounded, size: 16, color: esMasivo ? Colors.blueAccent : primaryGold),
                                const SizedBox(width: 8),
                                Text(
                                  "${evento.fechaEvento.day} de ${_getMesNombre(evento.fechaEvento.month)} de ${evento.fechaEvento.year}",
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 30, color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(esMasivo ? 'GESTIÓN MASIVA' : 'MODALIDAD', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Text(
                              esMasivo ? 'ALUMNOS / ESCUELAS' : 'PARTICULAR',
                              style: TextStyle(
                                fontWeight: FontWeight.w900, 
                                fontSize: 13,
                                color: esMasivo ? Colors.blueAccent : primaryGold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: Colors.grey.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    const Text(
                      'Toca para ver balance y detalles de cobro.',
                      style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getMesNombre(int mes) {
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    return meses[mes - 1];
  }
Widget _buildStatusBadge(EstadoEvento estado) {
    Color color;
    switch (estado) {
      case EstadoEvento.planificacion: color = Colors.orangeAccent; break;
      case EstadoEvento.confirmado: color = Colors.blueAccent; break;
      case EstadoEvento.finalizado: color = Colors.greenAccent; break;
      case EstadoEvento.cancelado: color = Colors.redAccent; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        estado.name.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 1),
      ),
    );
  }
}
