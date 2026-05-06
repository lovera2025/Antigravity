import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/obligacion_pago.dart';
import '../providers/obligaciones_provider.dart';
import '../../common/utils/currency_extensions.dart';
import 'package:uuid/uuid.dart';

class NuevoAvisoDialog extends ConsumerStatefulWidget {
  const NuevoAvisoDialog({super.key});

  @override
  ConsumerState<NuevoAvisoDialog> createState() => _NuevoAvisoDialogState();
}

class _NuevoAvisoDialogState extends ConsumerState<NuevoAvisoDialog> {
  final _tituloCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _montoFocus = FocusNode();
  String _tipo = 'empresa'; // 'empresa' o 'adrian'
  DateTime? _fechaVencimiento;
  bool _isLoading = false;

  @override
  void dispose() {
    _montoFocus.dispose();
    _tituloCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  /// Convierte un texto formateado AR ("1.234,56" o "1234,56") a `double`.
  /// Devuelve `0` si está vacío o no es parseable.
  double _parseMontoAr(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    final clean = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo Aviso / Recordatorio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _tituloCtrl,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _montoFocus.requestFocus(),
              decoration: const InputDecoration(labelText: 'Título corto (ej. Luz, Impuesto)'),
            ),
            const SizedBox(height: 16),
            const Text('Tipo de Obligación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            RadioGroup<String>(
              groupValue: _tipo,
              onChanged: (v) => setState(() => _tipo = v ?? _tipo),
              child: const Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('Empresa', style: TextStyle(fontSize: 13)),
                      value: 'empresa',
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('Adrián (Casa)', style: TextStyle(fontSize: 13)),
                      value: 'adrian',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _montoCtrl,
              focusNode: _montoFocus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              // Formateador AR: el usuario tipea dígitos puros y se muestra "1.234,56".
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
              onSubmitted: (_) {
                if (!_isLoading) _guardar();
              },
              decoration: const InputDecoration(
                labelText: 'Monto Estimado (Opcional)',
                prefixText: '\$ ',
                hintText: '0,00',
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de Vencimiento'),
              subtitle: Text(_fechaVencimiento != null 
                  ? '${_fechaVencimiento!.day}/${_fechaVencimiento!.month}/${_fechaVencimiento!.year}'
                  : 'Seleccionar fecha'),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (!mounted) return;
                if (date != null) {
                  setState(() => _fechaVencimiento = date);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _guardar,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar Aviso'),
        ),
      ],
    );
  }

  Future<void> _guardar() async {
    final t = _tituloCtrl.text.trim();
    if (t.isEmpty || _fechaVencimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Completar título y fecha')));
      return;
    }
    setState(() => _isLoading = true);

    final oblig = ObligacionPago(
      id: const Uuid().v4(),
      titulo: t,
      tipoObligacion: _tipo,
      fechaVencimiento: _fechaVencimiento!,
      montoEstimado: _parseMontoAr(_montoCtrl.text),
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(obligacionesProvider.notifier).guardar(oblig);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando aviso: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }
}
