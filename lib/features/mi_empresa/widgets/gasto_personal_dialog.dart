import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../bolsa_personal_helpers.dart';
import '../providers/finanzas_provider.dart';

/// Gasto personal: sale del negocio (o consume retiro pendiente si hay).
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

  /// Pasarse del bolsillo tiene que ser una decisión tomada a propósito.
  ///
  /// Antes el diálogo ofrecía como "máximo" la suma de tu bolsillo **más** todo
  /// el saldo del negocio, y al pasarte partía el gasto solo, sin avisar:
  /// apartabas $500.000, cargabas $800.000 y $300.000 salían de la empresa en
  /// silencio. La raya que marcaste no servía de nada.
  bool _confirmaExcedente = false;

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

  double _pendienteMedio(FinanzasState s) {
    if (_medioPago.toLowerCase().trim() == 'transferencia') {
      return s.hudSaldoBolsaPersonalTransferencia;
    }
    return s.hudSaldoBolsaPersonalEfectivo;
  }

  double _maxPermitido(FinanzasState s) {
    final empresa = s.hudPlataDelNegocio > 0 ? s.hudPlataDelNegocio : 0.0;
    return _pendienteMedio(s) + empresa;
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
      if (finState == null) throw Exception('Finanzas no disponibles');

      final pendiente = _pendienteMedio(finState);
      final desdePendiente = monto <= pendiente + _excedeTol ? monto : pendiente;
      final desdeEmpresa = monto - desdePendiente;
      if (desdeEmpresa > _excedeTol) {
        final dispEmp = finState.hudPlataDelNegocio > 0 ? finState.hudPlataDelNegocio : 0.0;
        if (desdeEmpresa > dispEmp + _excedeTol) {
          throw Exception(
            'Superás lo disponible en empresa (${dispEmp.toCurrency()}) para este gasto',
          );
        }
      }

      final concepto = _conceptoController.text.trim().isEmpty
          ? 'Gasto personal'
          : _conceptoController.text.trim();
      final repo = ref.read(egresosRepositoryProvider);

      if (desdePendiente > _excedeTol) {
        await repo.registrarEgresoSinEvento(
          monto: desdePendiente,
          proveedor: empaquetarProveedorGastoPendiente(concepto),
          categoria: kCategoriaGastoPersonal,
          fecha: DateTime.now(),
          medioPago: _medioPago,
        );
      }
      if (desdeEmpresa > _excedeTol) {
        await repo.registrarEgresoSinEvento(
          monto: desdeEmpresa,
          proveedor: empaquetarProveedorGastoEmpresa(concepto),
          categoria: kCategoriaGastoPersonal,
          fecha: DateTime.now(),
          medioPago: _medioPago,
        );
      }

      await ref.read(finanzasProvider.notifier).recargar();
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

    final finState = finanzasAsync.whenOrNull(data: (s) => s);
    final pendiente = finState != null ? _pendienteMedio(finState) : null;
    final maxPermitido = finState != null ? _maxPermitido(finState) : null;
    final gastadoTotal = finState?.hudGastadoPersonalTotal;

    final montoIngresado = _parseMontoField();
    final excedeDisponible =
        maxPermitido != null && montoIngresado != null && montoIngresado > maxPermitido + _excedeTol;
    // Se pasa del bolsillo pero todavía entra en lo que hay en la empresa.
    final excedeBolsillo = pendiente != null &&
        montoIngresado != null &&
        montoIngresado > pendiente + _excedeTol;
    final excedente = excedeBolsillo ? montoIngresado - pendiente : 0.0;
    final faltaConfirmar = excedeBolsillo && !excedeDisponible && !_confirmaExcedente;

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
                    'Registrá un gasto personal. Se descuenta de tu bolsillo; '
                    'si no alcanza, el resto sale del saldo de empresa.',
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
                  data: (_) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildResumenPanel(
                        context,
                        isDark,
                        gastadoTotal: gastadoTotal ?? 0,
                        pendiente: pendiente ?? 0,
                        maxPermitido: maxPermitido ?? 0,
                        excedeDisponible: excedeDisponible,
                      ),
                      if (excedeBolsillo && !excedeDisponible)
                        _buildAvisoExcedente(
                          context,
                          isDark,
                          excedente: excedente,
                          pendiente: pendiente,
                        ),
                    ],
                  ),
                  loading: () => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('No se pudo cargar: $e', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 14),
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
                    if (maxPermitido != null) {
                      final cleanText = v.replaceAll('.', '').replaceAll(',', '.');
                      final monto = double.tryParse(cleanText);
                      if (monto != null && monto > maxPermitido + _excedeTol) {
                        return 'Superás lo que podés registrar (${maxPermitido.toCurrency()})';
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
          onPressed: (_isSubmitting ||
                  maxPermitido == null ||
                  excedeDisponible ||
                  faltaConfirmar)
              ? null
              : _submit,
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

  /// Te pasaste del bolsillo: decilo con todas las letras y ofrecé las dos
  /// salidas. Sin elegir una, el botón de guardar no habilita.
  Widget _buildAvisoExcedente(
    BuildContext context,
    bool isDark, {
    required double excedente,
    required double pendiente,
  }) {
    const naranja = Color(0xFFF39C12);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: naranja.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: naranja.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: naranja),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Te pasás por ${excedente.toCurrency()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tu bolsillo cubre ${pendiente.toCurrency()}. El resto sale de la '
            'plata de la empresa.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Checkbox(
                value: _confirmaExcedente,
                onChanged: (v) =>
                    setState(() => _confirmaExcedente = v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: naranja,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(
                    () => _confirmaExcedente = !_confirmaExcedente,
                  ),
                  child: Text(
                    'Sí, quiero que ${excedente.toCurrency()} salgan del negocio',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Si no, bajá el monto a ${pendiente.toCurrency()} y queda todo '
              'dentro de lo que apartaste.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenPanel(
    BuildContext context,
    bool isDark, {
    required double gastadoTotal,
    required double pendiente,
    required double maxPermitido,
    required bool excedeDisponible,
  }) {
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white70 : Colors.black87,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
          Text('Disponible en tu bolsillo ($_medioPago)', style: baseStyle.copyWith(fontSize: 10, fontWeight: FontWeight.w900)),
          Text(
            pendiente.toCurrency(),
            style: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          if (gastadoTotal > 0.01) ...[
            const SizedBox(height: 6),
            Text(
              'Ya gastaste en total: ${gastadoTotal.toCurrency()}',
              style: baseStyle.copyWith(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
            ),
          ],
          if (maxPermitido > pendiente + _excedeTol) ...[
            const SizedBox(height: 8),
            // El tope duro sigue siendo bolsillo + empresa, pero se muestra como
            // lo que es —un límite absoluto— y no como "lo que podés gastar":
            // ese rótulo invitaba a usar la plata del negocio sin pensarlo.
            Text(
              'Tope absoluto ${maxPermitido.toCurrency()}, contando la empresa',
              style: baseStyle.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: excedeDisponible
                    ? Theme.of(context).colorScheme.error
                    : (isDark ? Colors.white38 : Colors.black38),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
