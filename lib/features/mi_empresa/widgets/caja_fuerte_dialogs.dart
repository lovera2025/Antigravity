import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../common/utils/currency_extensions.dart';
import '../providers/caja_fuerte_provider.dart';

/// Asignación de cupo en Caja fuerte (suma al saldo).
class CajaFuerteAsignarDialog extends ConsumerStatefulWidget {
  const CajaFuerteAsignarDialog({super.key});

  @override
  ConsumerState<CajaFuerteAsignarDialog> createState() => _CajaFuerteAsignarDialogState();
}

class _CajaFuerteAsignarDialogState extends ConsumerState<CajaFuerteAsignarDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  double _parseMontoAr(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final clean = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final m = _parseMontoAr(_montoCtrl.text);
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cajaFuerteProvider.notifier).registrarAsignacion(
            m,
            nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Text('Asignar a Caja fuerte'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sumá cupo para gastos personales del dueño. No descontamos automáticamente de la caja del negocio: es un control interno sobre lo que decidís disponer.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final value = double.parse(newValue.text) / 100;
                    final formatted = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: '\$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (_parseMontoAr(v) <= 0) return 'Monto mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Ej.: parte del finde',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _guardar,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF795548),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Retiro desde Caja fuerte (resta del saldo; bloqueado si supera disponible).
class CajaFuerteRetiroDialog extends ConsumerStatefulWidget {
  final double saldoActual;

  const CajaFuerteRetiroDialog({super.key, required this.saldoActual});

  @override
  ConsumerState<CajaFuerteRetiroDialog> createState() => _CajaFuerteRetiroDialogState();
}

class _CajaFuerteRetiroDialogState extends ConsumerState<CajaFuerteRetiroDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  double _parseMontoAr(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final clean = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final m = _parseMontoAr(_montoCtrl.text);
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un monto válido')),
      );
      return;
    }
    if (m > widget.saldoActual + 1e-6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saldo insuficiente (${widget.saldoActual.toCurrency()}). Asigná más en Caja fuerte o bajá el monto.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(cajaFuerteProvider.notifier).registrarRetiro(
            m,
            nota: _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Text('Retiro desde Caja fuerte'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disponible: ${widget.saldoActual.toCurrency()}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Registra un gasto personal que rebaja solo el cupo de Caja fuerte (no crea egreso operador).',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    if (newValue.text.isEmpty) return newValue;
                    final value = double.parse(newValue.text) / 100;
                    final formatted = value.toFormattedNumber();
                    return newValue.copyWith(
                      text: formatted,
                      selection: TextSelection.collapsed(offset: formatted.length),
                    );
                  }),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto del retiro',
                  prefixText: '\$ ',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (_parseMontoAr(v) <= 0) return 'Monto mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Concepto / nota (opcional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _guardar,
          style: FilledButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF795548),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Registrar'),
        ),
      ],
    );
  }
}
