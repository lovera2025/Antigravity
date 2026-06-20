import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/turno_caja.dart';

/// Selector segmentado de turno: Mañana · Tarde · Día completo (misma lógica, UI prolija).
class TurnoCierreSelector extends StatelessWidget {
  final TurnoCaja turnoActivo;
  final int corteHorarioAr;
  final bool isDark;
  final ValueChanged<TurnoCaja> onTurnoChanged;

  static const _gold = Color(0xFFD4AF37);
  static const _tardeColor = Color(0xFF6C63FF);

  const TurnoCierreSelector({
    super.key,
    required this.turnoActivo,
    required this.corteHorarioAr,
    required this.isDark,
    required this.onTurnoChanged,
  });

  Color _accent(TurnoCaja t) {
    switch (t) {
      case TurnoCaja.manana:
        return const Color(0xFFE8A317);
      case TurnoCaja.tarde:
        return _tardeColor;
      case TurnoCaja.dia:
        return _gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.45);
    final corte = corteHorarioAr.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TURNO DE CIERRE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const tabs = TurnoCaja.values;
            final w = constraints.maxWidth / tabs.length;
            final idx = tabs.indexOf(turnoActivo);
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.25)),
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  left: idx * w + 3,
                  top: 3,
                  bottom: 3,
                  width: w - 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent(turnoActivo).withValues(alpha: isDark ? 0.2 : 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accent(turnoActivo).withValues(alpha: 0.65),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent(turnoActivo).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: tabs.map((t) {
                    final sel = t == turnoActivo;
                    final accent = _accent(t);
                    final rango = switch (t) {
                      TurnoCaja.manana => '00:00 – $corte:00',
                      TurnoCaja.tarde => '$corte:00 – 23:59',
                      TurnoCaja.dia => '00:00 – 23:59',
                    };
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => onTurnoChanged(t),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (sel) ...[
                                      Icon(Icons.check_circle_rounded, size: 13, color: accent),
                                      const SizedBox(width: 4),
                                    ],
                                    Flexible(
                                      child: Text(
                                        t.labelCorto.toUpperCase(),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.oswald(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: sel
                                              ? accent
                                              : (isDark ? Colors.white70 : Colors.black87),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  rango,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? accent.withValues(alpha: 0.8)
                                        : muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            );
          },
        ),
      ],
    );
  }
}
