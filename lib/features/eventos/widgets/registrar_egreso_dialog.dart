import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../egresos/providers/egresos_provider.dart';
import '../../egresos/services/egreso_concepto_sugerencias.dart';

class RegistrarEgresoDialog extends ConsumerStatefulWidget {
  final Evento evento;

  const RegistrarEgresoDialog({super.key, required this.evento});

  @override
  ConsumerState<RegistrarEgresoDialog> createState() => _RegistrarEgresoDialogState();
}

class _RegistrarEgresoDialogState extends ConsumerState<RegistrarEgresoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _proveedorController = TextEditingController();
  final _montoController = TextEditingController();
  bool _isSubmitting = false;

  /// Misma taxonomía que el pago unificado (Finanzas / desglose por categoría).
  String _categoriaSeleccionada = kCategoriaComboDefault;
  String _medioPagoSeleccionado = 'Efectivo';

  @override
  void dispose() {
    _proveedorController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text
          .replaceAll('.', '')
          .replaceAll(',', '.');
      final monto = double.parse(cleanText);
      
      // Usamos el repositorio centralizado
      final repo = ref.read(egresosRepositoryProvider);
      await repo.registrarEgreso(
        eventoId: widget.evento.id,
        monto: monto,
        proveedor: _proveedorController.text.trim(),
        categoria: categoriaEgresoParaGuardar(_categoriaSeleccionada),
        medioPago: _medioPagoSeleccionado,
      );

      // Notificamos al provider de egresos masivo para que se refresque
      ref.read(egresosProvider.notifier).refresh();

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gasto registrado exitosamente'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar gasto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar Nuevo Gasto'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _proveedorController,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Proveedor / Concepto',
                  hintText: 'Ej: DJ Junior, Catering X...',
                  prefixIcon: Icon(Icons.business_center),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese un proveedor o concepto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _categoriaSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  prefixIcon: Icon(Icons.category),
                ),
                items: kCategoriasEgresoNegocioCombo.map((String cat) {
                  return DropdownMenuItem<String>(
                    value: cat,
                    child: Text(cat),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _categoriaSeleccionada = newValue;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
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
                decoration: const InputDecoration(
                  labelText: 'Monto del Gasto (\$)',
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: '0,00',
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_isSubmitting) _submit();
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty || value == '0,00') {
                    return 'Ingrese un monto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _medioPagoSeleccionado,
                decoration: const InputDecoration(
                  labelText: 'Medio de Pago',
                  prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _medioPagoSeleccionado = val);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE74C3C), // Rojo para egresos
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Registrar Gasto'),
        ),
      ],
    );
  }
}
