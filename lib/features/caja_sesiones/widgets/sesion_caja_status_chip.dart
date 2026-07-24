import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ar_time.dart';
import '../models/modo_jefe_caja.dart';
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
    if (s.etiqueta == kEtiquetaModoJefe) return Colors.greenAccent;
    final hb = s.lastHeartbeat ?? s.abiertaAt;
    final age = DateTime.now().toUtc().difference(hb.toUtc());
    if (age > _stale) return Colors.amber;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    if (_abiertas.isEmpty) {
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

    final s = _abiertas.first;
    final color = _colorFor(s);
    final label = [
      s.operadorNombre ?? 'Operador',
      if (s.etiqueta != null && s.etiqueta!.isNotEmpty) s.etiqueta!,
      'desde ${ArTime.formatFechaHora(s.abiertaAt)}',
    ].join(' · ');

    return Tooltip(
      message: _abiertas.length > 1
          ? '${_abiertas.length} cajas abiertas'
          : 'Sesión activa',
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
            if (_abiertas.length > 1) ...[
              const SizedBox(width: 6),
              Text(
                '+${_abiertas.length - 1}',
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
