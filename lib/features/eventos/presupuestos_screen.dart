import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/presupuesto.dart';
import '../../models/evento.dart';
import '../common/utils/currency_extensions.dart';
import '../common/widgets/animated_background.dart';
import '../common/services/pdf_service.dart';
import 'repositories/presupuestos_repository.dart';
import 'selector_servicios_screen.dart';

class PresupuestosScreen extends ConsumerStatefulWidget {
  const PresupuestosScreen({super.key});

  @override
  ConsumerState<PresupuestosScreen> createState() => _PresupuestosScreenState();
}

class _PresupuestosScreenState extends ConsumerState<PresupuestosScreen> {
  late Timer _timer;
  bool _showSuccessAnimation = false;

  @override
  void initState() {
    super.initState();
    // Actualizar el cronómetro visual cada minuto
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CENTRO DE PRESUPUESTOS', 
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2)
        ),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          AnimatedBackground(
            child: SafeArea(
              child: Consumer(
                builder: (context, ref, _) {
                  final repo = ref.watch(presupuestosRepositoryProvider);
                  return FutureBuilder<List<Presupuesto>>(
                    future: repo.getAll(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: primaryGold));
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final presupuestos = snapshot.data ?? [];

                      if (presupuestos.isEmpty) {
                        return _buildEmptyState(isDark);
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: presupuestos.length,
                        itemBuilder: (context, index) {
                          final p = presupuestos[index];
                          return _buildPresupuestoCard(p, isDark, primaryGold);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (_showSuccessAnimation) _buildSuccessOverlay(primaryGold),
        ],
      ),
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

  Widget _buildPresupuestoCard(Presupuesto p, bool isDark, Color gold) {
    final now = DateTime.now();
    final remaining = p.fechaVencimiento.difference(now);
    final bool isExpired = remaining.isNegative && p.estado == EstadoPresupuesto.activo;
    final bool isConfirmed = p.estado == EstadoPresupuesto.confirmado;
    final bool isCorrupt = p.cliente?.nombreCompleto == 'CLIENTE DESCONOCIDO';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCorrupt 
              ? Colors.red.withValues(alpha: 0.8) 
              : (isConfirmed 
                  ? Colors.greenAccent.withValues(alpha: 0.3) 
                  : (isExpired ? Colors.redAccent.withValues(alpha: 0.3) : gold.withValues(alpha: 0.2))),
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
              color: isConfirmed 
                  ? Colors.greenAccent.withValues(alpha: 0.1) 
                  : (isExpired ? Colors.redAccent.withValues(alpha: 0.1) : gold.withValues(alpha: 0.1)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isConfirmed 
                            ? Icons.verified_user_rounded 
                            : (isExpired ? Icons.timer_off_outlined : Icons.timer_outlined),
                        size: 16,
                        color: isConfirmed ? Colors.greenAccent : (isExpired ? Colors.redAccent : gold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isCorrupt 
                            ? 'REGISTRO CORRUPTO / HUÉRFANO' 
                            : (isConfirmed 
                                ? 'CONTRATO FIRMADO' 
                                : (isExpired ? 'PLAZO VENCIDO' : _formatRemaining(remaining))),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: isCorrupt ? Colors.red : (isConfirmed ? Colors.greenAccent : (isExpired ? Colors.redAccent : gold)),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        '#' + p.id.substring(0, 5).toUpperCase(),
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
                            Text(
                              Evento.formatearTipo(p.tipoEvento).toUpperCase(),
                              style: TextStyle(fontSize: 10, color: gold, fontWeight: FontWeight.w900, letterSpacing: 2),
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
                  
                  // Detalle de servicios (resumen)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: p.servicios.take(3).map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.nombre?.toUpperCase() ?? 'SERVICIO',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 24),
                  
                  // Acciones
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => PdfService.generarPresupuestoElite(p),
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: const Text('PDF ÉLITE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // BOTÓN EDITAR (A pedido del Señor)
                      if (!isConfirmed)
                        IconButton(
                          onPressed: () => _mostrarOpcionesEdicion(p),
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFFD4AF37)),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5)),
                          ),
                        ),
                      const SizedBox(width: 8),
                      if (!isConfirmed && !isExpired)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _confirmarPresupuesto(p),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('CONFIRMAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      if (isConfirmed)
                         const Expanded(
                          child: Center(
                            child: Text('CONVERTIDO A EVENTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                          ),
                        ),
                        if (isExpired)
                         Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              // TODO: Reactivar (opcional)
                            },
                            icon: const Icon(Icons.refresh, size: 18, color: Colors.orangeAccent),
                            label: const Text('RE-NEGOCIAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.orangeAccent)),
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
          serviciosIniciales: { for (var s in p.servicios) s.servicioId : s.precioFinal },
          cantidadesIniciales: { for (var s in p.servicios) s.servicioId : s.cantidad },
          gruposIniciales: { for (var s in p.servicios) s.servicioId : s.grupo ?? '' },
          descripcionesIniciales: { for (var s in p.servicios) s.servicioId : s.detalleServicio ?? '' },
          detalleAnclajeIA: p.detalleAnclaje,
          lugar: p.lugar,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
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
          setState(() {});
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
          if (mounted) setState(() {});
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
  late TextEditingController _tituloFestejadoController;
  late TextEditingController _clienteNombreController;
  late TextEditingController _clienteTelefonoController;
  late TextEditingController _clienteEmailController;
  
  // Logística y Tiempos
  late TextEditingController _lugarController;
  late TextEditingController _detalleAnclajeController;
  late DateTime _fechaVencimiento;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.presupuesto;
    _vendedorController = TextEditingController(text: p.vendedorNombre);
    _telefonoPubController = TextEditingController(text: p.telefono);
    _instagramController = TextEditingController(text: p.instagram);
    _tituloFestejadoController = TextEditingController(text: p.tituloFestejado);
    _lugarController = TextEditingController(text: p.lugar);
    _detalleAnclajeController = TextEditingController(text: p.detalleAnclaje);
    _fechaVencimiento = p.fechaVencimiento;
    
    _clienteNombreController = TextEditingController(text: p.cliente?.nombreCompleto);
    _clienteTelefonoController = TextEditingController(text: p.cliente?.telefono);
    _clienteEmailController = TextEditingController(text: p.cliente?.email);
  }

  @override
  void dispose() {
    _vendedorController.dispose();
    _telefonoPubController.dispose();
    _instagramController.dispose();
    _tituloFestejadoController.dispose();
    _lugarController.dispose();
    _detalleAnclajeController.dispose();
    _clienteNombreController.dispose();
    _clienteTelefonoController.dispose();
    _clienteEmailController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    
    try {
      final repo = ref.read(presupuestosRepositoryProvider);
      await repo.actualizarConfiguracionIntegral(
        presupuestoId: widget.presupuesto.id,
        vendedorNombre: _vendedorController.text.trim(),
        tituloFestejado: _tituloFestejadoController.text.trim(),
        telefonoPublicidad: _telefonoPubController.text.trim(),
        instagram: _instagramController.text.trim(),
        lugar: _lugarController.text.trim(),
        detalleAnclaje: _detalleAnclajeController.text.trim(),
        fechaVencimiento: _fechaVencimiento,
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
              _buildSectionHeader(Icons.person_pin_rounded, 'A NOMBRE DE QUIÉN (¿QUIÉN SOLICITA?)'),
              _buildTextField(controller: _tituloFestejadoController, label: 'Motivo del Festejo / Para quién', hint: 'Eje: Los 15 de Morena', icon: Icons.star_border_rounded),
              _buildTextField(controller: _clienteNombreController, label: 'Nombre del Cliente (Solicitante)', icon: Icons.person),
              _buildTextField(controller: _clienteTelefonoController, label: 'Teléfono de contacto privado', icon: Icons.phone, keyboardType: TextInputType.phone),
              _buildTextField(controller: _clienteEmailController, label: 'Email para envío', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),

              const SizedBox(height: 32),
              _buildSectionHeader(Icons.location_on_outlined, 'LOGÍSTICA Y TIEMPOS'),
              _buildTextField(controller: _lugarController, label: 'Lugar del Evento', hint: 'A definir o Salón específico', icon: Icons.map_outlined),
              _buildTextField(controller: _detalleAnclajeController, label: 'Anotaciones Especiales / Detalle para el PDF', hint: 'Eje: SERVICIO INTEGRAL...', icon: Icons.description_outlined, maxLines: 3),
              const SizedBox(height: 16),
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
