import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/evento.dart';
import '../repositories/eventos_repository.dart';
import '../utils/evento_presentacion.dart';

/// Panel Maestro (Pro) para eventos particulares activos.
Future<void> showPanelMaestroEventoSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Evento evento,
  VoidCallback? onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (ctx) => _PanelMaestroEventoContenido(
      evento: evento,
      onSave: onSaved,
    ),
  );
}

class _PanelMaestroEventoContenido extends ConsumerStatefulWidget {
  final Evento evento;
  final VoidCallback? onSave;

  const _PanelMaestroEventoContenido({required this.evento, this.onSave});

  @override
  ConsumerState<_PanelMaestroEventoContenido> createState() =>
      _PanelMaestroEventoContenidoState();
}

class _PanelMaestroEventoContenidoState
    extends ConsumerState<_PanelMaestroEventoContenido> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreFestejadoController;
  late TextEditingController _encabezadoController;
  late TextEditingController _clienteNombreController;
  late TextEditingController _clienteTelefonoController;
  late TextEditingController _clienteEmailController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.evento;
    final legacy = EventoPresentacion.dividirTituloFestejadoLegacy(
      e.tituloFestejado,
      e.tipo,
    );
    final nombreInicial = e.nombreFestejado?.trim().isNotEmpty == true
        ? e.nombreFestejado!
        : (legacy.nombreFestejado ??
            EventoPresentacion.homenajeadoDesdeObservaciones(e.observaciones) ??
            '');
    final encabezadoInicial = e.encabezadoEvento?.trim().isNotEmpty == true
        ? e.encabezadoEvento!
        : (legacy.encabezadoEvento ??
            (nombreInicial.isNotEmpty
                ? EventoPresentacion.resolverEncabezado(
                    nombreFestejado: nombreInicial,
                    tipoEvento: e.tipo,
                  )
                : ''));

    _encabezadoController = TextEditingController(text: encabezadoInicial);
    _nombreFestejadoController = TextEditingController(text: nombreInicial);
    _clienteNombreController =
        TextEditingController(text: e.cliente?.nombreCompleto ?? '');
    _clienteTelefonoController =
        TextEditingController(text: e.cliente?.telefono ?? '');
    _clienteEmailController = TextEditingController(text: e.cliente?.email ?? '');
  }

  @override
  void dispose() {
    _nombreFestejadoController.dispose();
    _encabezadoController.dispose();
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
          content: Text('El nombre del solicitante es obligatorio.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(eventosRepositoryProvider).actualizarConfiguracionMaestra(
            eventoId: widget.evento.id,
            nombreFestejado: _nombreFestejadoController.text.trim(),
            encabezadoEvento: _encabezadoController.text.trim(),
            tipo: widget.evento.tipo,
            observaciones: widget.evento.observaciones,
            clienteId: widget.evento.clienteId,
            clienteNombre: _clienteNombreController.text.trim(),
            clienteTelefono: _clienteTelefonoController.text.trim().isEmpty
                ? null
                : _clienteTelefonoController.text.trim(),
            clienteEmail: _clienteEmailController.text.trim().isEmpty
                ? null
                : _clienteEmailController.text.trim(),
          );

      if (mounted) {
        widget.onSave?.call();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Configuración maestra actualizada.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
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
                  Text(
                    'PANEL MAESTRO (PRO)',
                    style: GoogleFonts.oswald(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  ),
                ],
              ),
              const Text(
                'DATOS PARA EL PDF',
                style: TextStyle(
                  color: gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              _buildSectionHeader(Icons.title_rounded, 'ENCABEZADO'),
              _buildTextField(
                controller: _encabezadoController,
                label: 'Cómo se verá arriba en el PDF',
                hint: 'Ej: LOS 15 DE PAULI',
                icon: Icons.title_rounded,
              ),
              const SizedBox(height: 8),
              _buildSectionHeader(Icons.celebration_outlined, 'HOMENAJEADO/A'),
              _buildTextField(
                controller: _nombreFestejadoController,
                label: 'Homenajeado/a',
                hint: 'Ej: Pauli, Morena, Tomás',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 8),
              _buildSectionHeader(Icons.person_pin_rounded, 'SOLICITANTE'),
              _buildTextField(
                controller: _clienteNombreController,
                label: 'Solicitante',
                hint: 'Ej: García (papá), familia...',
                icon: Icons.person,
              ),
              _buildTextField(
                controller: _clienteTelefonoController,
                label: 'Teléfono de contacto',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              _buildTextField(
                controller: _clienteEmailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _guardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text(
                          'GUARDAR CONFIGURACIÓN MAESTRA',
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
                        ),
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
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
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
          prefixIcon: Icon(
            icon,
            color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
            size: 18,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD4AF37)),
          ),
        ),
      ),
    );
  }
}
