import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/obligacion_pago.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/providers/egresos_provider.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../providers/finanzas_provider.dart';
import '../providers/obligaciones_provider.dart';

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
  /// `true` = egreso empresa (Impuestos/Servicios); `false` = [kCategoriaGastoPersonal].
  bool _origenEmpresa = true;
  bool _isLoading = false;

  static const _tolSaldo = 0.009;

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(text: widget.obligacion.montoEstimado.toStringAsFixed(0));
    _montoCtrl.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    if (!mounted) return;
    if (!_registrarEgreso || _origenEmpresa) {
      setState(() {});
      return;
    }
    final m = _parseMonto();
    final s = _saldoBolsilloMedio(ref.read(finanzasProvider).whenOrNull(data: (x) => x));
    if (m > s + _tolSaldo) {
      setState(() => _origenEmpresa = true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _montoCtrl.removeListener(_onDraftChanged);
    _montoCtrl.dispose();
    super.dispose();
  }

  double _parseMonto() {
    final raw = _montoCtrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(raw) ?? double.tryParse(_montoCtrl.text.trim()) ?? 0.0;
  }

  double _saldoBolsilloMedio(FinanzasState? s) {
    if (s == null) return 0;
    final mp = _medioPago.toLowerCase().trim();
    if (mp == 'transferencia') return s.hudSaldoBolsaPersonalTransferencia;
    return s.hudSaldoBolsaPersonalEfectivo;
  }

  Future<void> _pagar() async {
    final m = _parseMonto();
    if (m <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese un monto válido.')));
      return;
    }

    final finState = ref.read(finanzasProvider).whenOrNull(data: (x) => x);
    if (_registrarEgreso && !_origenEmpresa) {
      final saldo = _saldoBolsilloMedio(finState);
      if (m > saldo + _tolSaldo) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No alcanza el saldo en bolsillo (${_medioPago.toLowerCase()}): ${saldo.toCurrency()}. '
              'Retirá primero a bolsillo o pagá desde empresa.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_registrarEgreso) {
        final repoEgreso = ref.read(egresosRepositoryProvider);
        if (_origenEmpresa) {
          await repoEgreso.registrarEgresoSinEvento(
            monto: m,
            proveedor: widget.obligacion.titulo,
            categoria: 'Impuestos/Servicios',
            fecha: DateTime.now(),
            medioPago: _medioPago,
          );
        } else {
          await repoEgreso.registrarEgresoSinEvento(
            monto: m,
            proveedor: widget.obligacion.titulo,
            categoria: kCategoriaGastoPersonal,
            fecha: DateTime.now(),
            medioPago: _medioPago,
          );
        }
        ref.read(egresosProvider.notifier).refresh();
        await ref.read(finanzasProvider.notifier).recargar();
      }

      final act = widget.obligacion.copyWith(
        estado: 'pagado',
        fechaPago: DateTime.now(),
        montoEstimado: m,
      );
      await ref.read(obligacionesProvider.notifier).guardar(act);

      if (!mounted) return;
      Navigator.pop(context);

      final dup = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Recrear para el próximo mes?'),
          content: Text('¿Deseas programar automáticamente el próximo vencimiento de ${widget.obligacion.titulo}?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, programar')),
          ],
        ),
      );

      if (dup == true) {
        final nextDate = DateTime(
          widget.obligacion.fechaVencimiento.year,
          widget.obligacion.fechaVencimiento.month + 1,
          widget.obligacion.fechaVencimiento.day,
        );
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final finanzasAsync = ref.watch(finanzasProvider);
    final finState = finanzasAsync.whenOrNull(data: (x) => x);
    final montoDraft = _parseMonto();
    final saldoBolsa = _saldoBolsilloMedio(finState);
    final puedeBolsillo =
        montoDraft > 0 && montoDraft <= saldoBolsa + _tolSaldo && saldoBolsa > _tolSaldo;

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
              onChanged: _isLoading
                  ? null
                  : (v) {
                      setState(() {
                        _medioPago = v!;
                        if (_registrarEgreso && !_origenEmpresa) {
                          final m = _parseMonto();
                          final s = _saldoBolsilloMedio(ref.read(finanzasProvider).whenOrNull(data: (x) => x));
                          if (m > s + _tolSaldo) _origenEmpresa = true;
                        }
                      });
                    },
              decoration: const InputDecoration(isDense: true),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registrar en Finanzas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text('Genera un egreso contable.', style: TextStyle(fontSize: 10)),
              value: _registrarEgreso,
              activeThumbColor: const Color(0xFF00B894),
              onChanged: _isLoading
                  ? null
                  : (v) => setState(() {
                        _registrarEgreso = v;
                        if (!v) _origenEmpresa = true;
                      }),
            ),
            if (_registrarEgreso) ...[
              const SizedBox(height: 8),
              const Text('Origen del pago', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              RadioListTile<bool>(
                title: const Text('Empresa'),
                subtitle: const Text('Egreso Impuestos/Servicios (sale del saldo empresa).'),
                value: true,
                groupValue: _origenEmpresa,
                onChanged: _isLoading ? null : (v) => setState(() => _origenEmpresa = v ?? true),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<bool>(
                title: const Text('Bolsillo personal'),
                subtitle: Text(
                  finState != null
                      ? 'Saldo ${_medioPago.toLowerCase()}: ${saldoBolsa.toCurrency()}'
                      : 'Cargando saldos…',
                  style: TextStyle(fontSize: 11, color: puedeBolsillo ? Colors.black54 : Colors.orange.shade800),
                ),
                value: false,
                groupValue: _origenEmpresa,
                onChanged: _isLoading || !puedeBolsillo
                    ? null
                    : (v) => setState(() => _origenEmpresa = v ?? true),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              if (!_origenEmpresa && !puedeBolsillo && montoDraft > _tolSaldo)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'No alcanza el saldo en bolsillo para este medio; elegí Empresa o retirá primero a bolsillo.',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error, height: 1.25),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isLoading || (_registrarEgreso && !_origenEmpresa && !puedeBolsillo && montoDraft > _tolSaldo)
              ? null
              : _pagar,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00B894)),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Confirmar Pago'),
        ),
      ],
    );
  }
}
