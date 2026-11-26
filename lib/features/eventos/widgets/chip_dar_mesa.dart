import 'package:flutter/material.dart';

import '../../common/utils/solo_jefe.dart';

/// En la barra de la grilla de la fiesta: "N · SIN MESA · DAR MESA A TODOS"
/// (6.9.4). Tocarlo abre el cartel de DAR MESA A TODOS. Con [onTap] null (sin
/// modo jefe) se ve apagado y dice por qué.
class ChipDarMesa extends StatelessWidget {
  /// Cuántas familias esperan alguna mesa.
  final int cantidad;
  final bool compacto;
  final VoidCallback? onTap;

  const ChipDarMesa({
    super.key,
    required this.cantidad,
    this.compacto = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    final color = habilitado ? Colors.indigo : Colors.grey.shade500;
    return Tooltip(
      message: habilitado
          ? 'Familias sin todas sus mesas. Tocá para darles la mesa a todas '
              'juntas.'
          : '$kSoloEnModoJefe: la mesa la da el jefe.',
      child: InkWell(
        key: const Key('dar_mesa_a_todos'),
        borderRadius: BorderRadius.circular(compacto ? 10 : 12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? 6 : 10,
            vertical: compacto ? 2 : 4,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(compacto ? 10 : 12),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_open_rounded,
                size: compacto ? 13 : 14,
                color: color,
              ),
              SizedBox(width: compacto ? 4 : 6),
              Text(
                '$cantidad',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compacto ? 12 : 13,
                  color: color,
                ),
              ),
              SizedBox(width: compacto ? 3 : 5),
              Text(
                'SIN MESA · DAR MESA A TODOS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: compacto ? 9 : 10,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
