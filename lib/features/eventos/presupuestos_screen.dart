import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/presupuesto.dart';
import '../common/utils/currency_extensions.dart';
import '../common/widgets/animated_background.dart';
import '../common/services/pdf_service.dart';
import 'repositories/presupuestos_repository.dart';
import 'selector_servicios_screen.dart';
import 'utils/evento_presentacion.dart';
import '../rentabilidad/calculador_rentabilidad_screen.dart';

class PresupuestosScreen extends ConsumerStatefulWidget {
  /// Si es true, se muestra solo el cuerpo (sin [Scaffold] propio) para incrustar en un [TabBarView].
  final bool embedded;

  const PresupuestosScreen({super.key, this.embedded = false});

  @override
  ConsumerState<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends ConsumerState<PresupuestosScreen> {
  late Timer _timer;
  bool _showSuccessAnimation = false;
  final Set<EstadoPresupuesto> _filtrosEstado = {EstadoPresupuesto.borrador, EstadoPresupuesto.enviado};
  String _filtroFecha = 'Todos';

  List<Presupuesto> _lista = const [];
  bool _cargandoInicial = true;
  Object? _errorCarga;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarInicial());
    // Actualizar el cronómetro visual cada minuto
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _cargarInicial() async {
    setState(() {
      _cargandoInicial = true;
      _errorCarga = null;
    });
    try {
      final repo = ref.read(presupuestosRepositoryProvider);
      final list = await repo.getAll(pullRemoteWhenOnline: true);
      if (mounted) {
        setState(() {
          _lista = list;
          _cargandoInicial = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorCarga = e;
          _cargandoInicial = false;
        });
      }
    }
  }

  /// Refresco tras acciones locales: SQLite rápido; pull opcional al tirar hacia abajo.
  Future<void> _refrescarLista({bool pullRemote = false}) async {
    try {
      final repo = ref.read(presupuestosRepositoryProvider);
      final list = await repo.getAll(pullRemoteWhenOnline: pullRemote);
      if (mounted) {
        setState(() {
          _lista = list;
          _errorCarga = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorCarga = e);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const primaryGold = Color(0xFFD4AF37);

    final body = Stack(
      children: [
        AnimatedBackground(
          child: SafeArea(
            child: Builder(
              builder: (context) {
                if (_cargandoInicial && _lista.isEmpty) {
                  return const Center(child: CircularProgressIndicator(color: primaryGold));
                }
                if (_errorCarga != null && _lista.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Error: $_errorCarga', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _cargarInicial,
                            child: const Text('REINTENTAR'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final todas = _lista;
                var presupuestos = todas.where((p) {
                  final st = p.estaVencido ? EstadoPresupuesto.vencido : p.estado;
                  if (_filtrosEstado.isNotEmpty && !_filtrosEstado.contains(st)) return false;

                  if (_filtroFecha != 'Todos') {
                    final now = DateTime.now();
                    final date = p.fechaEvento ?? p.fechaVencimiento;
                    if (_filtroFecha == 'Últimos 30 días' && date.isBefore(now.subtract(const Duration(days: 30)))) return false;
                    if (_filtroFecha == 'Este mes' && (date.month != now.month || date.year != now.year)) return false;
                    if (_filtroFecha == 'Mes pasado' && (date.month != now.subtract(const Duration(days: 30)).month)) return false;
                    if (_filtroFecha == 'Próximos 90 días' && date.isAfter(now.add(const Duration(days: 90)))) return false;
                  }
                  return true;
                }).toList();

                return Column(
                  children: [
                    _buildFiltros(isDark, primaryGold),
                    if (presupuestos.isEmpty)
                      Expanded(child: _buildEmptyState(isDark))
                    else
                      Expanded(
                        child: RefreshIndicator(
                          color: primaryGold,
                          onRefresh: () => _refrescarLista(pullRemote: true),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(24, widget.embedded ? 8 : 24, 24, 24),
                            itemCount: presupuestos.length,
                            itemBuilder: (context, index) {
                              final p = presupuestos[index];
                              return _buildPresupuestoCard(p, isDark, primaryGold);
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        if (_showSuccessAnimation) _buildSuccessOverlay(primaryGold),
      ],
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CENTRO DE PRESUPUESTOS',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
      ),
      body: body,
    );
  }

  Widget _buildSuccessOverlay(Color gold) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: gold,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: gold.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 10),
                      ],
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.black, size: 80),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Column(
                    children: [
                      Text(
                        '¡NEGOCIO CERRADO!',
                        style: GoogleFonts.oswald(
                          color: gold,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'EL EVENTO HA SIDO CREADO CON ÉXITO',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltros(bool isDark, Color gold) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02),
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: EstadoPresupuesto.values.map((est) {
                final isSelected = _filtrosEstado.contains(est);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(est.name.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _filtrosEstado.add(est);
                        } else {
                          _filtrosEstado.remove(est);
                        }
                      });
                    },
                    selectedColor: gold.withValues(alpha: 0.2),
                    checkmarkColor: gold,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.date_range, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _filtroFecha,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  isDense: true,
                  items: ['Todos', 'Últimos 30 días', 'Este mes', 'Mes pasado', 'Próximos 90 días']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _filtroFecha = v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getIconForCategory(String? category) {
    if (category == null) return Icons.category_rounded;
    final cat = category.toLowerCase();
    if (cat.contains('sonido')) return Icons.speaker_rounded;
    if (cat.contains('iluminación') || cat.contains('iluminacion')) return Icons.lightbulb_outline;
    if (cat.contains('dj') || cat.contains('animación') || cat.contains('animacion')) return Icons.music_note_rounded;
    return Icons.category_rounded;
  }

  Widget _buildPresupuestoCard(Presupuesto p, bool isDark, Color gold) {
    final now = DateTime.now();
    final remaining = p.fechaVencimiento.difference(now);
    final realState = p.estaVencido ? EstadoPresupuesto.vencido : p.estado;
    final bool isCorrupt = p.cliente?.nombreCompleto == 'CLIENTE DESCONOCIDO';
    
    Color customColor;
    String statusText;
    IconData statusIcon;

    switch (realState) {
      case EstadoPresupuesto.borrador:
        customColor = Colors.grey;
        statusText = 'BORRADOR';
        statusIcon = Icons.edit_document;
        break;
      case EstadoPresupuesto.enviado:
        customColor = gold;
        statusText = 'ENVIADO';
        statusIcon = Icons.send_rounded;
        break;
      case EstadoPresupuesto.aprobado:
        customColor = Colors.greenAccent;
        statusText = 'APROBADO';
        statusIcon = Icons.check_circle_outline;
        break;
      case EstadoPresupuesto.rechazado:
        customColor = Colors.redAccent;
        statusText = 'RECHAZADO';
        statusIcon = Icons.cancel_outlined;
        break;
      case EstadoPresupuesto.vencido:
        customColor = Colors.orangeAccent;
        statusText = 'VENCIDO';
        statusIcon = Icons.timer_off_outlined;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCorrupt ? Colors.red.withValues(alpha: 0.8) : customColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Header: Cronómetro / Estado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: customColor.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, size: 16, color: customColor),
                      const SizedBox(width: 8),
                      Text(
                        isCorrupt ? 'REGISTRO CORRUPTO / HUÉRFANO' : '$statusText • ${realState == EstadoPresupuesto.enviado || realState == EstadoPresupuesto.borrador ? _formatRemaining(remaining) : ""}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: isCorrupt ? Colors.red : customColor,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '#${p.id.substring(0, 5).toUpperCase()}',
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white24 : Colors.black26),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _eliminarPresupuesto(p),
                        icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Eliminar presupuesto',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.cliente?.nombreCompleto ?? 'CLIENTE SIN NOMBRE',
                              style: GoogleFonts.oswald(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 10, color: gold),
                                const SizedBox(width: 4),
                                Text(p.lugar ?? 'Sin lugar', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                const SizedBox(width: 8),
                                Icon(Icons.calendar_month, size: 10, color: gold),
                                const SizedBox(width: 4),
                                Text(p.fechaEvento != null ? '${p.fechaEvento!.day}/${p.fechaEvento!.month}/${p.fechaEvento!.year}' : 'Válido hasta ${_formatDate(p.fechaVencimiento)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('INVERSIÓN', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
                          Text(
                            p.total.toCurrency(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Detalle de servicios
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: p.servicios.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(_getIconForCategory(s.categoria), size: 14, color: isDark ? Colors.white54 : Colors.black54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.nombre ?? 'SERVICIO',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            (s.precioFinal * s.cantidad).toCurrency(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Colors.grey),
                  const SizedBox(height: 16),
                  
                  // Acciones
                  Row(
                    children: [
                      if (realState == EstadoPresupuesto.borrador) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await ref.read(presupuestosRepositoryProvider).cambiarEstado(p.id, EstadoPresupuesto.enviado);
                              if (!context.mounted) return;
                              await PdfService.generarPresupuestoElite(p, context: context);
                              if (!context.mounted) return;
                              await _refrescarLista(pullRemote: false);
                            },
                            icon: const Icon(Icons.send, size: 16),
                            label: const Text('ENVIAR / PDF', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        OutlinedButton(
                          onPressed: () => PdfService.generarPresupuestoElite(p, context: context),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        ),
                        const SizedBox(width: 8),
                      ],

                      if (realState != EstadoPresupuesto.aprobado && realState != EstadoPresupuesto.rechazado)
                        IconButton(
                          onPressed: () => _mostrarOpcionesEdicion(p),
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFD4AF37)),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5)),
                          ),
                        ),
                      const SizedBox(width: 8),

                      if (realState == EstadoPresupuesto.enviado || realState == EstadoPresupuesto.vencido) ...[
                        Expanded(child: ElevatedButton(
                          onPressed: () async {
                              await ref.read(presupuestosRepositoryProvider).cambiarEstado(p.id, EstadoPresupuesto.rechazado);
                              if (!context.mounted) return;
                              await _refrescarLista(pullRemote: false);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withValues(alpha: 0.1), foregroundColor: Colors.redAccent, elevation: 0),
                          child: const Text('RECHAZAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: ElevatedButton(
                          onPressed: () async {
                              await ref.read(presupuestosRepositoryProvider).cambiarEstado(p.id, EstadoPresupuesto.aprobado);
                              if (!context.mounted) return;
                              await _refrescarLista(pullRemote: false);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                          child: const Text('APROBAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                        )),
                      ],

                      if (realState == EstadoPresupuesto.aprobado)
                         Expanded(
                           child: ElevatedButton.icon(
                             onPressed: () => _confirmarPresupuesto(p),
                             icon: const Icon(Icons.celebration),
                             label: const Text('CREAR EVENTO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                           ),
                         ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    if (d.inDays > 0) return 'VENCE EN ${d.inDays} DÍAS';
    if (d.inHours > 0) return 'VENCE EN ${d.inHours} HORAS';
    return 'VENCE EN ${d.inMinutes} MINUTOS';
  }

  String _formatDate(DateTime d) {
     return '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _editarPresupuesto(Presupuesto p) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectorServiciosScreen(
          presupuestoId: p.id,
          clienteId: p.clienteId,
          nombreCliente: p.cliente?.nombreCompleto,
          tipoEvento: p.tipoEvento,
          isPresupuesto: true,
          servicioIdPorLineaInicial: { for (var s in p.servicios) s.id: s.servicioId },
          serviciosIniciales: { for (var s in p.servicios) s.id: s.precioFinal },
          cantidadesIniciales: { for (var s in p.servicios) s.id: s.cantidad },
          gruposIniciales: { for (var s in p.servicios) s.id: s.grupo },
          comboOrdenIniciales: { for (var s in p.servicios) s.id: s.comboOrden },
          extrasIniciales: { for (var s in p.servicios) s.id: s.esExtra },
          descripcionesIniciales: { for (var s in p.servicios) s.id: s.detalleServicio },
          detalleAnclajeIA: p.detalleAnclaje,
          lugar: p.lugar,
          nombreFestejado: p.nombreFestejado,
          encabezadoEvento: p.encabezadoEvento,
          tituloFestejado: p.encabezadoEvento ?? p.tituloFestejado ?? p.nombreFestejado,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(_refrescarLista(pullRemote: false));
    });
  }

  Future<void> _eliminarPresupuesto(Presupuesto p) async {
     final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Presupuesto'),
        content: Text('¿Está seguro de que desea eliminar permanentemente el presupuesto para ${p.cliente?.nombreCompleto}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('SÍ, ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(presupuestosRepositoryProvider).eliminar(p.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Presupuesto eliminado.'), backgroundColor: Colors.orange));
          await _refrescarLista(pullRemote: false);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _mostrarOpcionesEdicion(Presupuesto p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('EDITAR PRESUPUESTO', style: GoogleFonts.oswald(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.design_services_outlined, color: Color(0xFFD4AF37)),
              title: const Text('Editar Servicios y Precios', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Modificar los servicios incluidos y su costo.', style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () {
                Navigator.pop(ctx);
                _editarPresupuesto(p);
              },
            ),
            const Divider(color: Colors.white12),
            if (widget.embedded) ...[
              ListTile(
                leading: const Icon(Icons.analytics_outlined, color: Colors.greenAccent),
                title: const Text('Analizar Rentabilidad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Solo en MI EMPRESA: simulador con este presupuesto.', style: TextStyle(color: Colors.white54, fontSize: 10)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CalculadorRentabilidadScreen(presupuestoPreCargado: p)));
                },
              ),
              const Divider(color: Colors.white12),
            ],
            ListTile(
              leading: const Icon(Icons.settings_suggest_rounded, color: Color(0xFFD4AF37)),
              title: const Text('Configuración Maestro (Pro)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Parte completa: Asesor, Cliente, Lugar y Tiempos.', style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () {
                Navigator.pop(ctx);
                _mostrarPanelMaestro(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarPanelMaestro(Presupuesto p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => _PanelMaestroContenido(
        presupuesto: p,
        onSave: () {
          if (mounted) unawaited(_refrescarLista(pullRemote: false));
        },
      ),
    );
  }

  Future<void> _confirmarPresupuesto(Presupuesto p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Presupuesto'),
        content: Text('¿Desea convertir este presupuesto en un Evento Particular oficial para ${p.cliente?.nombreCompleto}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            child: const Text('SÍ, CONFIRMAR'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(presupuestosRepositoryProvider).confirmarPresupuesto(p.id);
        if (mounted) {
          await _refrescarLista(pullRemote: false);
          setState(() {
            _showSuccessAnimation = true;
          });
          
          // Ocultar animación tras unos segundos
          Future.delayed(const Duration(milliseconds: 3000), () {
            if (mounted) {
              setState(() {
                _showSuccessAnimation = false;
              });
            }
          });
        }
      } on PresupuestoSinItemsException {
        // Un snackbar que se va solo no alcanza: si esto pasa desapercibido, el
        // evento queda sin monto y nadie se entera hasta que alguien lo abre.
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_off_rounded, color: Color(0xFFE74C3C), size: 32),
            title: const Text('Faltan datos para confirmar'),
            content: const Text(PresupuestoSinItemsException.mensaje),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ENTENDIDO'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 60, color: isDark ? Colors.white12 : Colors.black12),
          const SizedBox(height: 16),
          const Text('NO HAY PRESUPUESTOS EMITIDOS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text('Iniciá uno nuevo desde la pantalla de creación.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
        ],
      ),
    );
  }
}

class _PanelMaestroContenido extends ConsumerStatefulWidget {
  final Presupuesto presupuesto;
  final VoidCallback onSave;

  const _PanelMaestroContenido({required this.presupuesto, required this.onSave});

  @override
  ConsumerState<_PanelMaestroContenido> createState() => _PanelMaestroContenidoState();
}

class _PanelMaestroContenidoState extends ConsumerState<_PanelMaestroContenido> {
  final _formKey = GlobalKey<FormState>();
  
  // Identidad
  late TextEditingController _vendedorController;
  late TextEditingController _telefonoPubController;
  late TextEditingController _instagramController;
  
  // Solicitante y Evento
  late TextEditingController _nombreFestejadoController;
  late TextEditingController _encabezadoController;
  late TextEditingController _clienteNombreController;
  late TextEditingController _clienteTelefonoController;
  late TextEditingController _clienteEmailController;
  
  // Logística y Tiempos
  late TextEditingController _lugarController;
  late TextEditingController _detalleAnclajeController;
  late DateTime _fechaVencimiento;
  late DateTime _fechaEvento;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.presupuesto;
    final legacy = EventoPresentacion.dividirTituloFestejadoLegacy(
      p.tituloFestejado,
      p.tipoEvento,
    );
    final nombreInicial = p.nombreFestejado?.trim().isNotEmpty == true
        ? p.nombreFestejado!
        : (legacy.nombreFestejado ?? '');
    _nombreFestejadoController = TextEditingController(text: nombreInicial);
    _encabezadoController = TextEditingController(
      text: p.encabezadoEvento?.trim().isNotEmpty == true
          ? p.encabezadoEvento!
          : (legacy.encabezadoEvento ??
              (nombreInicial.isNotEmpty
                  ? EventoPresentacion.resolverEncabezado(
                      nombreFestejado: nombreInicial,
                      tipoEvento: p.tipoEvento,
                    )
                  : '')),
    );
    _vendedorController = TextEditingController(text: p.vendedorNombre);
    _telefonoPubController = TextEditingController(text: p.telefono);
    _instagramController = TextEditingController(text: p.instagram);
    _lugarController = TextEditingController(text: p.lugar);
    _detalleAnclajeController = TextEditingController(text: p.detalleAnclaje);
    _fechaVencimiento = p.fechaVencimiento;
    _fechaEvento = p.fechaEvento ?? DateTime.now().add(const Duration(days: 30));
    
    _clienteNombreController = TextEditingController(text: p.cliente?.nombreCompleto);
    _clienteTelefonoController = TextEditingController(text: p.cliente?.telefono);
    _clienteEmailController = TextEditingController(text: p.cliente?.email);
  }

  @override
  void dispose() {
    _vendedorController.dispose();
    _telefonoPubController.dispose();
    _instagramController.dispose();
    _nombreFestejadoController.dispose();
    _encabezadoController.dispose();
    _lugarController.dispose();
    _detalleAnclajeController.dispose();
    _clienteNombreController.dispose();
    _clienteTelefonoController.dispose();
    _clienteEmailController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_encabezadoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indicá cómo debe verse el encabezado en el PDF.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_nombreFestejadoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indicá el nombre del homenajeado/a.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_clienteNombreController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El solicitante es obligatorio.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    
    setState(() => _isSaving = true);
    
    try {
      final repo = ref.read(presupuestosRepositoryProvider);
      await repo.actualizarConfiguracionIntegral(
        presupuestoId: widget.presupuesto.id,
        vendedorNombre: _vendedorController.text.trim(),
        nombreFestejado: _nombreFestejadoController.text.trim(),
        encabezadoEvento: _encabezadoController.text.trim(),
        telefonoPublicidad: _telefonoPubController.text.trim(),
        instagram: _instagramController.text.trim(),
        lugar: _lugarController.text.trim(),
        detalleAnclaje: _detalleAnclajeController.text.trim(),
        fechaVencimiento: _fechaVencimiento,
        fechaEvento: _fechaEvento,
        clienteId: widget.presupuesto.clienteId,
        clienteNombre: _clienteNombreController.text.trim(),
        clienteTelefono: _clienteTelefonoController.text.trim(),
        clienteEmail: _clienteEmailController.text.trim(),
      );
      
      if (mounted) {
        widget.onSave();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Configuración maestra actualizada con éxito.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    
    return Container(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PANEL MAESTRO (PRO)', style: GoogleFonts.oswald(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white54)),
                ],
              ),
              const Text('CONFIGURACIÓN INTEGRAL DEL PRESUPUESTO', style: TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 32),
              
              _buildSectionHeader(Icons.badge_outlined, 'NUESTRA IDENTIDAD (¿QUIÉN OFRECE?)'),
              _buildTextField(controller: _vendedorController, label: 'Nombre del Asesor', hint: 'Eje: Maxi o Adriana', icon: Icons.person_outline),
              _buildTextField(controller: _telefonoPubController, label: 'WhatsApp de Contacto', hint: 'Número para el cliente', icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone),
              _buildTextField(controller: _instagramController, label: 'Instagram', hint: 'junior_eventos_ok', icon: Icons.camera_alt_outlined, prefix: '@ '),
              
              const SizedBox(height: 32),
              _buildSectionHeader(Icons.title_rounded, 'ENCABEZADO Y PERSONAS'),
              _buildTextField(controller: _encabezadoController, label: 'Cómo se verá arriba en el PDF', hint: 'Ej: LOS 15 DE PAULI', icon: Icons.title_rounded),
              _buildTextField(controller: _nombreFestejadoController, label: 'Homenajeado/a', hint: 'Ej: Morena, Pauli', icon: Icons.person_outline_rounded),
              _buildTextField(controller: _clienteNombreController, label: 'Solicitante', icon: Icons.person),
              _buildTextField(controller: _clienteTelefonoController, label: 'Teléfono de contacto privado', icon: Icons.phone, keyboardType: TextInputType.phone),
              _buildTextField(controller: _clienteEmailController, label: 'Email para envío', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),

              const SizedBox(height: 32),
              _buildSectionHeader(Icons.location_on_outlined, 'LOGÍSTICA Y TIEMPOS'),
              _buildTextField(controller: _lugarController, label: 'Lugar del Evento', hint: 'A definir o Salón específico', icon: Icons.map_outlined),
              _buildTextField(controller: _detalleAnclajeController, label: 'Anotaciones especiales', hint: 'Ej: SERVICIO INTEGRAL...', icon: Icons.description_outlined, maxLines: 3),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.celebration_outlined, color: gold, size: 20),
                title: const Text('Fecha del Evento', style: TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(
                  '${_fechaEvento.day}/${_fechaEvento.month}/${_fechaEvento.year}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaEvento,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    );
                    if (picked != null) setState(() => _fechaEvento = picked);
                  },
                  child: const Text('CAMBIAR', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded, color: gold, size: 20),
                title: const Text('Vencimiento del Presupuesto', style: TextStyle(color: Colors.white70, fontSize: 12)),
                subtitle: Text(
                  '${_fechaVencimiento.day}/${_fechaVencimiento.month}/${_fechaVencimiento.year}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaVencimiento,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _fechaVencimiento = picked);
                  },
                  child: const Text('CAMBIAR', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                  ),
                  child: _isSaving 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('GUARDAR CONFIGURACIÓN MAESTRA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4AF37), size: 18),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    String? prefix,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
          prefixIcon: Icon(icon, color: const Color(0xFFD4AF37).withValues(alpha: 0.6), size: 18),
          prefixText: prefix,
          prefixStyle: const TextStyle(color: Colors.white),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1)),
        ),
      ),
    );
  }
}
