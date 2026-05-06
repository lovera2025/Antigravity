import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../models/obligacion_pago.dart';
import '../providers/obligaciones_provider.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../egresos/providers/egresos_provider.dart';

class PagarAvisoDialog extends ConsumerStatefulWidget {
  final ObligacionPago obligacion;
  const PagarAvisoDialog({super.key, required this.obligacion});

  @override
  ConsumerState<PagarAvisoDialog> createState() => _PagarAvisoDialogState();
}

class _PagarAvisoDialogState extends ConsumerState<PagarAvisoDialog> {
  late TextEditingController _montoCtrl;
  String _medioPago = 'Efectivo';
  bool _registrarEgreso = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(text: widget.obligacion.montoEstimado.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pagar: ${widget.obligacion.titulo}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_isLoading) _pagar();
              },
              decoration: const InputDecoration(labelText: 'Monto final pagado \$'),
            ),
            const SizedBox(height: 16),
            const Text('Medio de Pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
            DropdownButtonFormField<String>(
              initialValue: _medioPago,
              items: const [
                DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia / Tarjeta')),
              ],
              onChanged: (v) => setState(() => _medioPago = v!),
              decoration: const InputDecoration(isDense: true),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registrar en Finanzas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Genera un egreso contable sumando a los gastos del mes.', style: TextStyle(fontSize: 10)),
              value: _registrarEgreso,
              activeThumbColor: const Color(0xFF00B894),
              onChanged: (v) => setState(() => _registrarEgreso = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading ? null : _pagar,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00B894)),
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Confirmar Pago'),
        ),
      ],
    );
  }

  void _pagar() async {
    final m = double.tryParse(_montoCtrl.text) ?? 0.0;
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese un monto válido.')));
      return;
    }

    setState(() => _isLoading = true);

    if (_registrarEgreso) {
      final repoEgreso = ref.read(egresosRepositoryProvider);
      await repoEgreso.registrarEgresoSinEvento(
        monto: m,
        proveedor: widget.obligacion.titulo,
        categoria: 'Impuestos/Servicios',
        fecha: DateTime.now(),
        medioPago: _medioPago,
      );
      ref.read(egresosProvider.notifier).refresh();
    }

    final act = widget.obligacion.copyWith(
      estado: 'pagado', 
      fechaPago: DateTime.now(),
      montoEstimado: m, 
    );
    await ref.read(obligacionesProvider.notifier).guardar(act);
    
    if (!mounted) return;
    Navigator.pop(context);
    
    // Ofrecer duplicar para el próximo mes
    final dup = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Recrear para el próximo mes?'),
        content: Text('¿Deseas programar automáticamente el próximo vencimiento de ${widget.obligacion.titulo}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, programar')),
        ]
      )
    );

    if (dup == true) {
      final nextDate = DateTime(widget.obligacion.fechaVencimiento.year, widget.obligacion.fechaVencimiento.month + 1, widget.obligacion.fechaVencimiento.day);
      final nextOblig = ObligacionPago(
        id: const Uuid().v4(),
        titulo: widget.obligacion.titulo,
        tipoObligacion: widget.obligacion.tipoObligacion,
        fechaVencimiento: nextDate,
        montoEstimado: m,
        createdAt: DateTime.now(),
      );
      await ref.read(obligacionesProvider.notifier).guardar(nextOblig);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Programado para el ${nextDate.day}/${nextDate.month}')));
      }
    }
  }
}
