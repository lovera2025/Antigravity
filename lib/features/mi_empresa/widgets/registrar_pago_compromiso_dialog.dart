import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/utils/currency_extensions.dart';
import '../models/compromiso_personal.dart';
import '../providers/compromisos_personal_provider.dart';
import '../providers/finanzas_provider.dart';

/// Registra un pago contra una cuenta pendiente, eligiendo de qué bolsa sale.
///
/// El pago es un egreso común con `categoria = 'Personal'`: entra al flujo de
/// caja y a la liquidación de esa persona salga del negocio o del bolsillo. Lo
/// que cambia según el origen es qué saldo baja.
class RegistrarPagoCompromisoDialog extends ConsumerStatefulWidget {
  final CompromisoConSaldo cuenta;

  const RegistrarPagoCompromisoDialog({super.key, required this.cuenta});

  @override
  ConsumerState<RegistrarPagoCompromisoDialog> createState() =>
      _RegistrarPagoCompromisoDialogState();
}

class _RegistrarPagoCompromisoDialogState
    extends ConsumerState<RegistrarPagoCompromisoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();

  static const _rojo = Color(0xFFE74C3C);
  static const _verde = Color(0xFF00B894);
  static const _ambar = Color(0xFFFFB74D);

  String _medioPago = 'Efectivo';
  String _origen = kOrigenNegocio;
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Prellenado con lo que falta: el caso normal es saldar la cuenta.
    final saldo = widget.cuenta.saldo;
    if (saldo > 0) _montoController.text = saldo.toFormattedNumber();
  }

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  double get _monto {
    final t = _montoController.text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  bool get _esTransferencia => _medioPago == 'Transferencia';

  /// Saldo del bolsillo **del medio de pago elegido**, no el total.
  ///
  /// El bolsillo se lleva por separado en efectivo y transferencia, y cada lado
  /// clampea en cero. Si se validara contra el total, pagar $40.000 en efectivo
  /// de un bolsillo que tiene $50.000 pero todo por transferencia dejaría el
  /// lado efectivo en cero y el bolsillo bajaría menos de lo que se pagó: la
  /// diferencia se evapora del cálculo.
  double _saldoBolsilloDelMedio(FinanzasState f) => _esTransferencia
      ? f.hudSaldoBolsaPersonalTransferencia
      : f.hudSaldoBolsaPersonalEfectivo;

  String? _motivoFreno(FinanzasState f) {
    if (_origen != kOrigenBolsillo) return null;
    final disponible = _saldoBolsilloDelMedio(f);
    if (_monto <= disponible + 0.01) return null;
    return 'En tu bolsillo hay '
        '${f.hudSaldoBolsaPersonalEfectivo.toCurrency()} en efectivo y '
        '${f.hudSaldoBolsaPersonalTransferencia.toCurrency()} en transferencia. '
        'No alcanza para este pago.';
  }

  Future<void> _guardar(FinanzasState f) async {
    if (!_formKey.currentState!.validate()) return;
    if (_motivoFreno(f) != null) return;

    // El sobrepago sí se deja pasar: a veces se paga de más y se arregla
    // después. Solo se avisa antes.
    if (widget.cuenta.compromiso.huboSobrepago(widget.cuenta.pagado + _monto)) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Es más de lo que falta'),
          content: Text(
            'Faltan ${widget.cuenta.saldo.toCurrency()} y estás registrando '
            '${_monto.toCurrency()}. ¿Lo registro igual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('VOLVER'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('REGISTRAR IGUAL'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }

    setState(() => _guardando = true);
    try {
      await ref.read(compromisosPersonalProvider.notifier).registrarPago(
            compromisoId: widget.cuenta.compromiso.id,
            persona: widget.cuenta.compromiso.persona,
            monto: _monto,
            origenFondos: _origen,
            medioPago: _medioPago,
            fecha: _fecha,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar el pago: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final finanzas = ref.watch(finanzasProvider).value;
    final c = widget.cuenta;

    if (finanzas == null) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final freno = _motivoFreno(finanzas);
    final disponibleNegocio = finanzas.hudPlataDelNegocio;
    final disponibleBolsillo = _saldoBolsilloDelMedio(finanzas);

    return AlertDialog(
      title: Text('Pagarle a ${c.compromiso.persona}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _rojo.withValues(alpha: isDark ? 0.12 : 0.07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.compromiso.concepto?.isNotEmpty == true
                            ? '${c.compromiso.tipo} · ${c.compromiso.concepto}'
                            : c.compromiso.tipo,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Falta ${c.saldo.toCurrency()}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _rojo,
                        ),
                      ),
                      Text(
                        'Pagué ${c.pagado.toCurrency()} de '
                        '${c.compromiso.montoTotal.toCurrency()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _montoController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      if (newValue.text.isEmpty) return newValue;
                      final v = double.parse(newValue.text) / 100;
                      final t = v.toFormattedNumber();
                      return newValue.copyWith(
                        text: t,
                        selection: TextSelection.collapsed(offset: t.length),
                      );
                    }),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monto a pagar (\$)',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty || v == '0,00') ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _medioPago,
                  decoration: const InputDecoration(
                    labelText: 'Medio de pago',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(
                      value: 'Transferencia',
                      child: Text('Transferencia'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _medioPago = v);
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  '¿DE DÓNDE SALE?',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: kOrigenNegocio,
                      label: Text('Del negocio'),
                      icon: Icon(Icons.storefront_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: kOrigenBolsillo,
                      label: Text('De mi bolsillo'),
                      icon: Icon(Icons.wallet_rounded, size: 16),
                    ),
                  ],
                  selected: {_origen},
                  onSelectionChanged: (s) => setState(() => _origen = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _origen == kOrigenNegocio
                      ? 'Disponible en el negocio: ${disponibleNegocio.toCurrency()}'
                      : 'Disponible en tu bolsillo ($_medioPago): '
                          '${disponibleBolsillo.toCurrency()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: freno != null
                        ? _rojo
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
                if (freno != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _rojo.withValues(alpha: isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _rojo.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.block_rounded, size: 16, color: _rojo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            freno,
                            style: const TextStyle(fontSize: 11, color: _rojo),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_origen == kOrigenBolsillo) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: _ambar),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Baja tu bolsillo. El saldo del negocio no se mueve: '
                          'esa plata ya salió cuando la retiraste.',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Fecha', style: TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${_fecha.day.toString().padLeft(2, '0')}/'
                    '${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final elegida = await showDatePicker(
                        context: context,
                        initialDate: _fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (elegida != null) setState(() => _fecha = elegida);
                    },
                    child: const Text('CAMBIAR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed:
              _guardando || freno != null ? null : () => _guardar(finanzas),
          style: ElevatedButton.styleFrom(
            backgroundColor: _verde,
            foregroundColor: Colors.white,
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('REGISTRAR PAGO'),
        ),
      ],
    );
  }
}
