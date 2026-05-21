import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../common/utils/currency_extensions.dart';
import '../providers/cierre_caja_provider.dart';

/// Control visual del fondo de cambio: no altera ingresos, egresos ni medios de pago.
class GuiaCambioSection extends ConsumerWidget {
  const GuiaCambioSection({super.key});

  static const _gold = Color(0xFFD4AF37);

  static double _parseMonto(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  Future<void> _dialogEditarSaldo(BuildContext context, WidgetRef ref) async {
    final state = ref.read(cierreCajaProvider);
    final ctrl = TextEditingController(
      text: state.fondoCambioGuia <= 0 ? '' : state.fondoCambioGuia.toString(),
    );
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
            title: Text(
              'Saldo de cambio (guía)',
              style: GoogleFonts.oswald(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: _gold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuánto tenés armado para vueltos en este día.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Monto',
                    errorText: error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  final v = _parseMonto(ctrl.text);
                  if (v < 0) {
                    setLocal(() => error = 'Monto inválido.');
                    return;
                  }
                  await ref.read(cierreCajaProvider.notifier).setFondoCambioGuia(v);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _dialogUsarCambio(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
            title: Text(
              'Usé cambio del fondo',
              style: GoogleFonts.oswald(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: _gold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se resta solo de esta guía. No registra egreso ni mueve la caja contable.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Monto usado',
                    errorText: error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: () async {
                  final v = _parseMonto(ctrl.text);
                  if (v <= 0) {
                    setLocal(() => error = 'Ingresá un monto mayor a cero.');
                    return;
                  }
                  try {
                    await ref.read(cierreCajaProvider.notifier).registrarUsoCambioGuia(v);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    setLocal(() => error = '$e');
                  }
                },
                child: const Text('Restar'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cierreCajaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = _gold.withValues(alpha: 0.35);
    final bg = _gold.withValues(alpha: isDark ? 0.08 : 0.06);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
          color: bg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.paid_outlined, size: 20, color: _gold.withValues(alpha: 0.95)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'GUÍA DE CAMBIO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: _gold.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'No suma ni resta del recaudado del día (efectivo / transferencia).',
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.fondoCambioGuia.toCurrency(),
              style: GoogleFonts.oswald(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.cargando ? null : () => _dialogEditarSaldo(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _gold,
                      side: BorderSide(color: _gold.withValues(alpha: 0.55)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'EDITAR SALDO',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: state.cargando ? null : () => _dialogUsarCambio(context, ref),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold.withValues(alpha: 0.85),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'USÉ CAMBIO',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
