import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../models/sesion_caja.dart';
import '../repositories/sesiones_caja_repository.dart';

/// Chip de estado de cajas abiertas para el dashboard del jefe.
class SesionCajaStatusChip extends ConsumerStatefulWidget {
  const SesionCajaStatusChip({super.key});

  @override
  ConsumerState<SesionCajaStatusChip> createState() =>
      _SesionCajaStatusChipState();
}

class _SesionCajaStatusChipState extends ConsumerState<SesionCajaStatusChip> {
  List<SesionCaja> _abiertas = [];
  Timer? _poll;

  Future<void> _refresh() async {
    try {
      final repo = ref.read(sesionesCajaRepositoryProvider);
      final list = await repo.sesionesAbiertas();
      if (mounted) setState(() => _abiertas = list);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Puntito más vivo; el nombre en tinta en tema claro (el flúor se lava).
  ({Color text, Color dot}) _colorsFor(SesionCaja s, bool isDark) {
    if (s.enUsoAhora()) {
      if (isDark) {
        return (text: Colors.greenAccent, dot: Colors.greenAccent);
      }
      return (text: Colors.green.shade800, dot: Colors.green.shade600);
    }
    if (isDark) {
      return (text: Colors.amber, dot: Colors.amber);
    }
    return (text: Colors.orange.shade800, dot: Colors.amber.shade700);
  }

  /// Sin latido por más de [kLatidoSesionMuerto] la app se cerró sin cerrar la
  /// caja: se muestra como cerrada. Desde v4.6 la sesión de modo jefe también
  /// late mientras la app está abierta, así que aplica la misma regla.
  bool _viva(SesionCaja s) => !s.sinSenales();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vivas = _abiertas.where(_viva).toList();
    if (vivas.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: Colors.grey),
            SizedBox(width: 6),
            Text(
              'Caja cerrada',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    final s = vivas.first;
    final colors = _colorsFor(s, isDark);
    final label = [
      s.operadorNombre ?? 'Operador',
      if (s.etiqueta != null && s.etiqueta!.isNotEmpty) s.etiqueta!,
      'desde ${ArTime.formatFechaHora(s.abiertaAt)}',
    ].join(' · ');

    return Tooltip(
      message: vivas.length > 1 ? '${vivas.length} cajas abiertas' : 'Sesión activa',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.text.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.text.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: colors.dot),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                'Caja activa · $label',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (vivas.length > 1) ...[
              const SizedBox(width: 6),
              Text(
                '+${vivas.length - 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
