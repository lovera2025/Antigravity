import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../providers/finanzas_provider.dart';

/// Gasto pagado con plata que ya está en el bolsillo personal ([kCategoriaGastoPersonal]).
class GastoPersonalDialog extends ConsumerStatefulWidget {
  const GastoPersonalDialog({super.key});

  @override
  ConsumerState<GastoPersonalDialog> createState() => _GastoPersonalDialogState();
}

class _GastoPersonalDialogState extends ConsumerState<GastoPersonalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _conceptoController = TextEditingController(text: 'Gasto personal');

  bool _isSubmitting = false;
  String _medioPago = 'Efectivo';

  static const _gold = Color(0xFFD4AF37);
  static const _teal = Color(0xFF26A69A);
  static const _excedeTol = 0.009;

  @override
  void initState() {
    super.initState();
    _montoController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _montoController.dispose();
    _conceptoController.dispose();
    super.dispose();
  }

  double _saldoMedio(FinanzasState s) {
    final mp = _medioPago.toLowerCase().trim();
    if (mp == 'transferencia') {
      return s.hudSaldoBolsaPersonalTransferencia;
    }
    return s.hudSaldoBolsaPersonalEfectivo;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final cleanText = _montoController.text.replaceAll('.', '').replaceAll(',', '.');
      final monto = double.parse(cleanText);
      if (monto <= 0) {
        throw Exception('El monto debe ser mayor a cero');
      }
      final finState = ref.read(finanzasProvider).whenOrNull(data: (s) => s);
      if (finState != null) {
        final disp = _saldoMedio(finState);
        if (monto > disp + _excedeTol) {
          throw Exception(
            'Superás lo disponible en bolsillo (${_medioPago.toLowerCase()}): ${disp.toCurrency()}',
          );
        }
      }

      final repo = ref.read(egresosRepositoryProvider);
      await repo.registrarEgresoSinEvento(
        monto: monto,
        proveedor: _conceptoController.text.trim().isEmpty ? 'Gasto personal' : _conceptoController.text.trim(),
        categoria: kCategoriaGastoPersonal,
        fecha: DateTime.now(),
        medioPago: _medioPago,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gasto personal registrado'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  double? _parseMontoField() {
    final t = _montoController.text.trim();
    if (t.isEmpty || t == '0,00') return null;
    try {
      final cleanText = t.replaceAll('.', '').replaceAll(',', '.');
      return double.parse(cleanText);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final finanzasAsync = ref.watch(finanzasProvider);

    final double? saldoMedio = finanzasAsync.whenOrNull(data: _saldoMedio);

    final montoIngresado = _parseMontoField();
    final excedeDisponible =
        saldoMedio != null && montoIngresado != null && montoIngresado > saldoMedio + _excedeTol;
    final restaria = (saldoMedio != null && montoIngresado != null) ? saldoMedio - montoIngresado : null;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: _teal.withValues(alpha: 0.95), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gasto personal',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: isDark ? 0.14 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _teal.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    'Registrás un gasto pagado con plata que ya retiraste al bolsillo. '
                    'No baja de nuevo el saldo empresa; solo el disponible del bolsillo (según el medio).',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('MEDIO DE PAGO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _medioPago,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.swap_vert_rounded, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                    DropdownMenuItem(value: 'Transferencia', child: Text('Transferencia')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _medioPago = val);
                  },
                ),
                const SizedBox(height: 14),
                finanzasAsync.when(
                  data: (_) => _buildSaldoBolsilloPanel(
                    context,
                    isDark,
                    saldoMedio: saldoMedio ?? 0,
                    restaria: restaria,
                    excedeDisponible: excedeDisponible,
                    montoIngresado: montoIngresado,
                  ),
                  loading: () => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _teal.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Actualizando saldo bolsillo…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No se pudo cargar el saldo: $e.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.error,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
                Text('MONTO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
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
                    final disp = saldoMedio;
                    if (disp != null) {
                      final cleanText = v.replaceAll('.', '').replaceAll(',', '.');
                      final monto = double.tryParse(cleanText);
                      if (monto != null && monto > disp + _excedeTol) {
                        return 'No podés gastar más que lo disponible (${disp.toCurrency()})';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Text('CONCEPTO (OPCIONAL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _conceptoController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ej. Supermercado',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton.icon(
          onPressed: (_isSubmitting || saldoMedio == null || excedeDisponible) ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.white),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isSubmitting ? 'GUARDANDO...' : 'REGISTRAR GASTO', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
        ),
      ],
    );
  }

  Widget _buildSaldoBolsilloPanel(
    BuildContext context,
    bool isDark, {
    required double saldoMedio,
    required double? restaria,
    required bool excedeDisponible,
    required double? montoIngresado,
  }) {
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white70 : Colors.black87,
    );
    final valStyle = baseStyle.copyWith(
      fontWeight: FontWeight.w900,
      color: excedeDisponible
          ? Theme.of(context).colorScheme.error
          : (isDark ? Colors.white : Colors.black87),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: excedeDisponible
              ? Theme.of(context).colorScheme.error.withValues(alpha: isDark ? 0.14 : 0.08)
              : _teal.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: excedeDisponible
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.45)
                : _teal.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  excedeDisponible ? Icons.warning_rounded : Icons.savings_outlined,
                  size: 18,
                  color: excedeDisponible ? Theme.of(context).colorScheme.error : _teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Disponible en bolsillo ($_medioPago)',
                    style: baseStyle.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(saldoMedio.toCurrency(), style: valStyle.copyWith(fontSize: 18)),
            if (restaria != null && montoIngresado != null && montoIngresado > _excedeTol) ...[
              const SizedBox(height: 8),
              Text(
                excedeDisponible ? 'Este monto supera lo disponible en este medio.' : 'Después del gasto quedaría:',
                style: baseStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              if (!excedeDisponible) ...[
                const SizedBox(height: 2),
                Text(
                  restaria.toCurrency(),
                  style: baseStyle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: restaria < 0.02 ? (isDark ? Colors.white38 : Colors.black38) : _teal,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
