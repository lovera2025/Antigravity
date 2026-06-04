import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../providers/finanzas_provider.dart';

/// Registro explícito: plata que pasa del negocio al bolsillo personal del dueño ([kCategoriaRetiroDueno]).
class RetiroBolsilloPersonalDialog extends ConsumerStatefulWidget {
  const RetiroBolsilloPersonalDialog({super.key});

  @override
  ConsumerState<RetiroBolsilloPersonalDialog> createState() => _RetiroBolsilloPersonalDialogState();
}

enum _TipoRetiro { personal, empresa }

class _RetiroBolsilloPersonalDialogState extends ConsumerState<RetiroBolsilloPersonalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _conceptoController = TextEditingController(text: 'Retiro bolsillo personal');

  bool _isSubmitting = false;
  String _medioPago = 'Efectivo';
  _TipoRetiro _tipoRetiro = _TipoRetiro.personal;

  static const _gold = Color(0xFFD4AF37);
  static const _amber = Color(0xFFFFB74D);
  static const _teal = Color(0xFF26A69A);

  /// Umbral por redondeo de moneda / coma en el campo.
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
        final disp = finState.hudPlataDelNegocio;
        final dispClamped = disp > 0 ? disp : 0.0;
        if (monto > dispClamped + _excedeTol) {
          throw Exception('El monto supera lo disponible en empresa (${dispClamped.toCurrency()})');
        }
      }

      final repo = ref.read(egresosRepositoryProvider);
      final esPersonal = _tipoRetiro == _TipoRetiro.personal;
      final conceptoBase = _conceptoController.text.trim().isEmpty
          ? (esPersonal ? 'Retiro bolsillo personal' : 'Gasto del negocio')
          : _conceptoController.text.trim();

      await repo.registrarEgresoSinEvento(
        monto: monto,
        proveedor: conceptoBase,
        categoria: esPersonal ? kCategoriaRetiroDueno : kCategoriaGastoEmpresa,
        fecha: DateTime.now(),
        medioPago: _medioPago,
      );

      await ref.read(finanzasProvider.notifier).recargar();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(esPersonal ? 'Retiro personal registrado' : 'Gasto de empresa registrado'),
          backgroundColor: const Color(0xFF00B894),
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

    final double? disponibleEmpresa = finanzasAsync.whenOrNull(
      data: (s) {
        final neto = s.hudPlataDelNegocio;
        return neto > 0 ? neto : 0.0;
      },
    );

    final montoIngresado = _parseMontoField();
    final excedeDisponible = disponibleEmpresa != null &&
        montoIngresado != null &&
        montoIngresado > disponibleEmpresa + _excedeTol;
    final restaria =
        (disponibleEmpresa != null && montoIngresado != null) ? disponibleEmpresa - montoIngresado : null;

    final esPersonal = _tipoRetiro == _TipoRetiro.personal;
    final accentColor = esPersonal ? _amber : _teal;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            esPersonal ? Icons.account_balance_wallet_outlined : Icons.store_rounded,
            color: accentColor.withValues(alpha: 0.95),
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              esPersonal ? 'Retiro personal' : 'Gasto del negocio',
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
                Text('¿QUÉ TIPO DE RETIRO ES?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 8),
                SegmentedButton<_TipoRetiro>(
                  segments: const [
                    ButtonSegment(
                      value: _TipoRetiro.personal,
                      icon: Icon(Icons.person_rounded, size: 16),
                      label: Text('Personal (mío)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    ButtonSegment(
                      value: _TipoRetiro.empresa,
                      icon: Icon(Icons.store_rounded, size: 16),
                      label: Text('Del negocio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  selected: {_tipoRetiro},
                  onSelectionChanged: (v) => setState(() => _tipoRetiro = v.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    side: WidgetStatePropertyAll(BorderSide(color: accentColor.withValues(alpha: 0.5))),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    esPersonal
                        ? 'Sacás plata del negocio para vos. Se suma a tu bolsillo personal y podés registrar gastos desde ahí.'
                        : 'Es un gasto directo del negocio (insumos, servicios, etc.). Se descuenta del saldo de empresa.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                finanzasAsync.when(
                  data: (s) => _buildSaldoDisponiblePanel(
                    context,
                    isDark,
                    state: s,
                    disponibleEmpresa: disponibleEmpresa ?? 0,
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
                            color: _amber.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Actualizando saldo asignable…',
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
                      'No se pudo cargar el saldo: $e. Podés intentar de nuevo desde Finanzas.',
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
                    final disp = disponibleEmpresa;
                    if (disp != null) {
                      final cleanText = v.replaceAll('.', '').replaceAll(',', '.');
                      final monto = double.tryParse(cleanText);
                      if (monto != null && monto > disp + _excedeTol) {
                        return 'No podés retirar más que lo disponible (${disp.toCurrency()})';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
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
                Text('CONCEPTO (OPCIONAL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _gold, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _conceptoController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ej. Retiro fin de semana',
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
          onPressed: (_isSubmitting || disponibleEmpresa == null || excedeDisponible) ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(
            _isSubmitting ? 'GUARDANDO...' : (esPersonal ? 'REGISTRAR RETIRO' : 'REGISTRAR GASTO'),
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildSaldoDisponiblePanel(
    BuildContext context,
    bool isDark, {
    required FinanzasState state,
    required double disponibleEmpresa,
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
              : const Color(0xFF00B894).withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: excedeDisponible
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.45)
                : const Color(0xFF00B894).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  excedeDisponible ? Icons.warning_rounded : Icons.pie_chart_outline_rounded,
                  size: 18,
                  color: excedeDisponible ? Theme.of(context).colorScheme.error : const Color(0xFF00B894),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saldo contable del negocio',
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
            Text(disponibleEmpresa.toCurrency(), style: valStyle.copyWith(fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Cobros − operadores − gastos personales − retiros pendientes. '
              'No es plata física en un cajón: comparalo con caja + banco + cofre.',
              style: baseStyle.copyWith(fontSize: 10, height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'EF ${state.hudEfectivoNetoHistorico.toCurrency()} · TR ${state.hudTransferenciaNetaHistorica.toCurrency()}',
              style: baseStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFF00B894)),
            ),
            if (restaria != null && montoIngresado != null && montoIngresado > _excedeTol) ...[
              const SizedBox(height: 8),
              Text(
                excedeDisponible
                    ? 'Este monto supera lo que tenés en empresa.'
                    : 'Después del retiro quedaría en empresa:',
                style: baseStyle.copyWith(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              if (!excedeDisponible) ...[
                const SizedBox(height: 2),
                Text(
                  restaria.toCurrency(),
                  style: baseStyle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: restaria < 0.02 ? (isDark ? Colors.white38 : Colors.black38) : const Color(0xFF00B894),
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
