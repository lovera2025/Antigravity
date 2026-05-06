import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../common/utils/currency_extensions.dart';
import '../providers/cierre_caja_provider.dart';

class RegistrarRetiroDialog extends ConsumerStatefulWidget {
  const RegistrarRetiroDialog({super.key});

  @override
  ConsumerState<RegistrarRetiroDialog> createState() => _RegistrarRetiroDialogState();
}

class _RegistrarRetiroDialogState extends ConsumerState<RegistrarRetiroDialog> {
  final _montoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  String _medio = 'efectivo';
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  double get _monto {
    final raw = _montoCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  Future<void> _confirmar() async {
    final state = ref.read(cierreCajaProvider);
    final disponible = _medio == 'efectivo'
        ? state.efectivoNeto
        : state.transferenciaNeta;
    if (_monto <= 0) {
      setState(() => _error = 'Ingresá un monto válido.');
      return;
    }
    if (_monto > disponible + 0.001) {
      setState(() => _error =
          'El monto excede el disponible en $_medio (${disponible.toCurrency()}).');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref.read(cierreCajaProvider.notifier).registrarRetiro(
            monto: _monto,
            medioPago: _medio,
            notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retiro registrado'),
          backgroundColor: Color(0xFF00B894),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierreCajaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFD4AF37);
    final efectivoColor = const Color(0xFF00B894);
    final transferColor = const Color(0xFF6C63FF);

    final disponible = _medio == 'efectivo'
        ? state.efectivoNeto
        : state.transferenciaNeta;
    final puedeConfirmar = !_enviando && _monto > 0 && _monto <= disponible + 0.001;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.south_west_rounded, color: gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'REGISTRAR RETIRO DE CAJA',
                      style: GoogleFonts.oswald(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: gold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _bucketsLine(state, efectivoColor, transferColor, isDark),
              const SizedBox(height: 16),
              Text('MONTO', style: _labelStyle(gold)),
              const SizedBox(height: 6),
              TextField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() => _error = null),
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  hintText: '0,00',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 14),
              Text('MEDIO DE PAGO', style: _labelStyle(gold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Efectivo'),
                    avatar: Icon(Icons.payments_outlined, size: 16, color: efectivoColor),
                    selected: _medio == 'efectivo',
                    selectedColor: efectivoColor.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() {
                      _medio = 'efectivo';
                      _error = null;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Transferencia'),
                    avatar: Icon(Icons.swap_horiz_rounded, size: 16, color: transferColor),
                    selected: _medio == 'transferencia',
                    selectedColor: transferColor.withValues(alpha: 0.2),
                    onSelected: (_) => setState(() {
                      _medio = 'transferencia';
                      _error = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('NOTAS (opcional)', style: _labelStyle(gold)),
              const SizedBox(height: 6),
              TextField(
                controller: _notasCtrl,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Para qué fue el retiro…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: puedeConfirmar ? _confirmar : null,
                    icon: _enviando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirmar retiro'),
                    style: FilledButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _labelStyle(Color gold) => TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: gold.withValues(alpha: 0.9),
      );

  Widget _bucketsLine(
    CierreCajaState state,
    Color efectivoColor,
    Color transferColor,
    bool isDark,
  ) {
    Widget tile(String label, double monto, Color accent, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  monto.toCurrency(),
                  style: GoogleFonts.oswald(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('DISP. EFECTIVO', state.efectivoNeto, efectivoColor, Icons.payments_outlined),
        const SizedBox(width: 8),
        tile('DISP. TRANSF.', state.transferenciaNeta, transferColor, Icons.swap_horiz_rounded),
      ],
    );
  }
}
