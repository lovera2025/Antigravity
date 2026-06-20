import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cierre_caja_sync_config.dart';
import '../models/turno_caja.dart';
import '../providers/cierre_caja_provider.dart';
import 'guia_cambio_section.dart';

class AnotacionPdfSection extends ConsumerStatefulWidget {
  const AnotacionPdfSection({super.key});

  @override
  ConsumerState<AnotacionPdfSection> createState() => _AnotacionPdfSectionState();
}

class _AnotacionPdfSectionState extends ConsumerState<AnotacionPdfSection> {
  static const _gold = Color(0xFFD4AF37);

  final _ctrl = TextEditingController();
  Timer? _debounce;
  String? _ultimoTurnoCargado;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        await ref.read(cierreCajaProvider.notifier).setAnotacionTurno(value);
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierreCajaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45);
    final turnoKey = '${state.dia.millisecondsSinceEpoch}_${state.turno.slug}';
    if (_ultimoTurnoCargado != turnoKey) {
      _ultimoTurnoCargado = turnoKey;
      _ctrl.text = state.anotacionTurno;
    }

    final fechaIso = CierreCajaRepositoryFecha.fecha(state.dia);
    final syncOk = cierreCajaFechaElegibleSync(fechaIso);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ANOTACIÓN PARA EL PDF · ${state.turno.labelCorto.toUpperCase()}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: _gold.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Opcional. Aparece en el PDF de este turno. Se sincroniza entre equipos.',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            enabled: syncOk && !state.cargando,
            onChanged: _onChanged,
            maxLines: 3,
            minLines: 2,
            decoration: InputDecoration(
              hintText: 'Ej.: retiro parcial, faltó moneda chica…',
              hintStyle: TextStyle(fontSize: 12, color: muted.withValues(alpha: 0.7)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (!syncOk)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Sync de anotaciones desde $kCierreCajaSyncFechaCorte.',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
