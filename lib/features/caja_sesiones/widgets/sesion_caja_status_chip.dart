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
  static const _stale = Duration(seconds: 90);
  static const _muerta = Duration(minutes: 5);

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

  Color _colorFor(SesionCaja s) {
    final hb = s.lastHeartbeat ?? s.abiertaAt;
    final age = DateTime.now().toUtc().difference(hb.toUtc());
    if (age > _stale) return Colors.amber;
    return Colors.greenAccent;
  }

  /// Sin heartbeat por más de [_muerta] la app se cerró sin cerrar la caja:
  /// se muestra como cerrada. Desde v4.6 la sesión de modo jefe también
  /// late mientras la app está abierta, así que aplica la misma regla.
  bool _viva(SesionCaja s) {
    final hb = s.lastHeartbeat ?? s.abiertaAt;
    return DateTime.now().toUtc().difference(hb.toUtc()) <= _muerta;
  }

  @override
  Widget build(BuildContext context) {
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
    final color = _colorFor(s);
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
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                'Caja activa · $label',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
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
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
