import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';

/// Diálogo para editar un pago a personal (egreso categoría Personal).
class EditarPagoOperadorDialog extends ConsumerStatefulWidget {
  final Egreso egreso;

  const EditarPagoOperadorDialog({super.key, required this.egreso});

  @override
  ConsumerState<EditarPagoOperadorDialog> createState() =>
      _EditarPagoOperadorDialogState();
}

class _EditarPagoOperadorDialogState
    extends ConsumerState<EditarPagoOperadorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _operadorController = TextEditingController();
  final _montoController = TextEditingController();

  bool _isSubmitting = false;
  List<Map<String, dynamic>> _eventos = [];
  String? _eventoIdSeleccionado;
  DateTime? _fecha;

  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _operadorController.text = widget.egreso.proveedor ?? '';
    _montoController.text = widget.egreso.monto.toFormattedNumber();
    _eventoIdSeleccionado = widget.egreso.eventoId;
    _fecha = widget.egreso.fecha ?? DateTime.now();
    _cargarEventos();
  }

  Future<void> _cargarEventos() async {
    final supabase = ref.read(supabaseProvider);
    try {
      final res = await supabase
          .from('eventos')
          .select('id, tipo, fecha_evento, clientes(nombre_completo)')
          .not('estado', 'eq', 'Cancelado')
          .order('fecha_evento', ascending: false)
          .limit(50);
      final lista = (res as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _eventos = lista);
    } catch (e) {
      debugPrint('EditarPagoOperadorDialog: error cargando eventos: $e');
    }
  }

  String _labelEvento(Map<String, dynamic> ev) {
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

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _fecha = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_eventoIdSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná un evento')),
      );
      return;
    }
    if (_fecha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná la fecha del pago')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = ref.read(supabaseProvider);
      final cleanText =
          _montoController.text.replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(cleanText);

      await supabase.from('egresos').update({
        'evento_id': _eventoIdSeleccionado,
        'monto': monto,
        'proveedor': _operadorController.text.trim(),
        'categoria': 'Personal',
        'fecha': _fecha!.toIso8601String(),
      }).eq('id', widget.egreso.id);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago actualizado'),
            backgroundColor: Color(0xFF00B894),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _operadorController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Widget _buildLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _gold),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: _gold.withValues(alpha: 0.2)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_rounded, color: _gold, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'EDITAR PAGO',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('EVENTO', Icons.event_note_outlined),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _eventoIdSeleccionado,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Seleccioná el evento...',
                  prefixIcon: const Icon(Icons.celebration_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: _eventos.map((ev) {
                  return DropdownMenuItem<String>(
                    value: ev['id'] as String,
                    child: Text(
                      _labelEvento(ev),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (val) =>
                    setState(() => _eventoIdSeleccionado = val),
                validator: (v) => v == null ? 'Seleccioná un evento' : null,
              ),
              const SizedBox(height: 16),
              _buildLabel('OPERADOR / PERSONAL', Icons.badge_outlined),
              const SizedBox(height: 6),
              TextFormField(
                controller: _operadorController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Nombre del operador...',
                  prefixIcon: const Icon(Icons.person_outline, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ingresá el nombre';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('MONTO', Icons.attach_money_rounded),
              const SizedBox(height: 6),
              TextFormField(
                controller: _montoController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final double value = double.parse(newValue.text) / 100;
                    final String newText = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: newText,
                      selection: TextSelection.collapsed(offset: newText.length),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  hintText: '0,00',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                validator: (v) {
                  if (v == null || v.trim().isEmpty || v == '0,00') return 'Ingresá el monto';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildLabel('FECHA DEL PAGO', Icons.calendar_today_rounded),
              const SizedBox(height: 6),
              InkWell(
                onTap: _elegirFecha,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.date_range_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  child: Text(
                    _fecha != null
                        ? '${_fecha!.day.toString().padLeft(2, '0')}/${_fecha!.month.toString().padLeft(2, '0')}/${_fecha!.year}'
                        : 'Elegir fecha',
                    style: TextStyle(
                      fontSize: 14,
                      color: _fecha != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text(
            'GUARDAR CAMBIOS',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}
