import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cierre_caja_provider.dart';

/// Solo modo jefe: la nota que el operario escribió al cerrar caja.
class NotaCierreSesionSection extends ConsumerWidget {
  const NotaCierreSesionSection({super.key});

  static const _amber = Color(0xFFFFB020);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cierreCajaProvider);
    final nota = state.sesionSeleccionada?.notaCierreHumana;
    if (nota == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amber.withValues(alpha: 0.85), width: 1.8),
        color: _amber.withValues(alpha: isDark ? 0.18 : 0.12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NOTAS DE CIERRE:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: _amber,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nota,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
