import 'package:flutter/material.dart';

import '../../common/utils/currency_extensions.dart';
import '../extracciones.dart';

/// La sección "Extracciones" del panel SALDO DEL NEGOCIO.
///
/// Arranca cerrada cada vez que se abre el panel: cerrada dice solo cuántas son
/// y cuánto suman; abierta, cada rubro con su parte en efectivo y en
/// transferencia. Pedido del dueño: los retiros estaban "muy expuestos" en "En
/// qué se fue", mezclados con los gastos.
class ExtraccionesNegocio extends StatefulWidget {
  const ExtraccionesNegocio({
    super.key,
    required this.resumen,
    required this.isDark,
  });

  final List<ResumenExtraccion> resumen;
  final bool isDark;

  @override
  State<ExtraccionesNegocio> createState() => _ExtraccionesNegocioState();
}

class _ExtraccionesNegocioState extends State<ExtraccionesNegocio> {
  bool _abierta = false;

  static const _amber = Color(0xFFFFB74D);

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final resumen = widget.resumen;
    if (resumen.isEmpty) return const SizedBox.shrink();

    final cantidad = resumen.fold<int>(0, (s, r) => s + r.cantidad);
    final total = resumen.fold<double>(0, (s, r) => s + r.total);
    final suave = isDark ? Colors.white54 : Colors.black54;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _abierta = !_abierta),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    _abierta ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 16,
                    color: _amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXTRACCIONES',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: isDark ? Colors.white38 : Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$cantidad ${cantidad == 1 ? 'movimiento' : 'movimientos'}'
                          ' · ${total.toCurrency()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: suave,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _abierta
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: suave,
                  ),
                ],
              ),
            ),
          ),
          if (_abierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                children: [
                  for (final r in resumen) _rubro(r, isDark, suave),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rubro(ResumenExtraccion r, bool isDark, Color suave) {
    final partes = [
      if (r.efectivo > 0.01) 'Efectivo ${r.efectivo.toCurrency()}',
      if (r.transferencia > 0.01)
        'Transferencia ${r.transferencia.toCurrency()}',
    ].join(' · ');
    final nota = r.rubro == RubroExtraccion.retiroCaja
        ? 'Del cajón del turno a la oficina, no se gastó.'
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.rubro.nombre} · ${r.cantidad}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              Text(
                '-${r.total.toCurrency()}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: _amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            nota == null ? partes : '$partes. $nota',
            style: TextStyle(fontSize: 10.5, color: suave),
          ),
        ],
      ),
    );
  }
}
