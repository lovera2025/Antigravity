import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../bolsa_personal_helpers.dart';
import 'calendario_filtro_movimientos.dart';

/// Cuál de las dos bolsas está mirando el panel.
///
/// Son dos instancias del mismo widget, no dos pantallas parecidas: lo único
/// que cambia es qué movimientos entran y cómo se rotula cada fila.
enum AmbitoPanel { negocio, bolsillo }

/// Un botón de acción del panel. Devuelve `true` si registró algo, para que el
/// panel se refresque y se cierre.
class AccionPanel {
  final String label;
  final IconData icon;
  final Color color;
  final Color colorTexto;
  final Future<bool?> Function(BuildContext ctx) abrir;

  const AccionPanel({
    required this.label,
    required this.icon,
    required this.color,
    required this.abrir,
    this.colorTexto = Colors.white,
  });
}

/// Un dato de resumen arriba del historial.
class ChipResumen {
  final String label;
  final double monto;
  final Color color;

  const ChipResumen(this.label, this.monto, this.color);
}

/// Filtro por tipo de movimiento, además del calendario.
enum _FiltroTipo { todos, efectivo, transferencia, entradas, salidas }

/// Movimientos que le corresponden a cada ámbito.
///
/// El negocio ve **todo lo que le salió**, incluidos los retiros al bolsillo:
/// si faltan $500.000 y no hay línea que lo explique, el historial miente por
/// omisión. El bolsillo ve ese mismo retiro desde el otro lado, como entrada.
/// Es un movimiento único mostrado dos veces, como una transferencia entre
/// cuentas — no se duplica en ningún total.
List<Egreso> movimientosDelAmbito(List<Egreso> todos, AmbitoPanel ambito) {
  return todos.where((e) {
    final cat = (e.categoria ?? '').trim();
    if (ambito == AmbitoPanel.bolsillo) {
      return cat == kCategoriaRetiroDueno || cat == kCategoriaGastoPersonal;
    }
    return finanzasEgresoAfectaCajaEmpresa(e);
  }).toList();
}

/// `true` si el movimiento entra plata a la bolsa que se está mirando.
bool _esEntrada(Egreso e, AmbitoPanel ambito) {
  if (ambito != AmbitoPanel.bolsillo) return false;
  return (e.categoria ?? '').trim() == kCategoriaRetiroDueno;
}

/// Abre el panel de una bolsa: monto, acciones e historial con calendario.
Future<void> showPanelMovimientosSheet(
  BuildContext context, {
  required AmbitoPanel ambito,
  required String titulo,
  required String subtitulo,
  required double monto,
  required String labelMonto,
  required List<Egreso> egresos,
  required List<ChipResumen> chips,
  required List<AccionPanel> acciones,
  required bool isDark,
  required Color accent,
  String? notaRaya,
  List<Widget> extras = const [],
  VoidCallback? onRefresh,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121218) : const Color(0xFFFCF9F2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: _PanelMovimientos(
              scrollCtrl: scrollCtrl,
              ambito: ambito,
              titulo: titulo,
              subtitulo: subtitulo,
              monto: monto,
              labelMonto: labelMonto,
              egresos: egresos,
              chips: chips,
              acciones: acciones,
              isDark: isDark,
              accent: accent,
              notaRaya: notaRaya,
              extras: extras,
              onRefresh: onRefresh,
            ),
          );
        },
      );
    },
  );
}

class _PanelMovimientos extends StatefulWidget {
  final ScrollController scrollCtrl;
  final AmbitoPanel ambito;
  final String titulo;
  final String subtitulo;
  final double monto;
  final String labelMonto;
  final List<Egreso> egresos;
  final List<ChipResumen> chips;
  final List<AccionPanel> acciones;
  final bool isDark;
  final Color accent;
  final String? notaRaya;
  final List<Widget> extras;
  final VoidCallback? onRefresh;

  const _PanelMovimientos({
    required this.scrollCtrl,
    required this.ambito,
    required this.titulo,
    required this.subtitulo,
    required this.monto,
    required this.labelMonto,
    required this.egresos,
    required this.chips,
    required this.acciones,
    required this.isDark,
    required this.accent,
    required this.notaRaya,
    required this.extras,
    required this.onRefresh,
  });

  @override
  State<_PanelMovimientos> createState() => _PanelMovimientosState();
}

class _PanelMovimientosState extends State<_PanelMovimientos> {
  RangoFiltroMovimientos _rango = const RangoFiltroMovimientos.todo();
  _FiltroTipo _tipo = _FiltroTipo.todos;

  List<Egreso> get _delAmbito =>
      movimientosDelAmbito(widget.egresos, widget.ambito);

  List<Egreso> get _visibles {
    return _delAmbito.where((e) {
      if (!_rango.contiene(e.fecha)) return false;
      switch (_tipo) {
        case _FiltroTipo.todos:
          return true;
        case _FiltroTipo.efectivo:
          return e.medioPago?.toLowerCase().trim() != 'transferencia';
        case _FiltroTipo.transferencia:
          return e.medioPago?.toLowerCase().trim() == 'transferencia';
        case _FiltroTipo.entradas:
          return _esEntrada(e, widget.ambito);
        case _FiltroTipo.salidas:
          return !_esEntrada(e, widget.ambito);
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = widget.accent;
    final visibles = _visibles;
    final totalVisible =
        visibles.fold<double>(0, (s, e) => s + (_esEntrada(e, widget.ambito) ? -e.monto : e.monto));

    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.titulo,
          style: GoogleFonts.oswald(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            color: accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitulo,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.monto.toCurrency(),
          style: GoogleFonts.oswald(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.labelMonto,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        if (widget.notaRaya != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Text(
              widget.notaRaya!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _grillaChips(isDark),
        const SizedBox(height: 14),
        _filaAcciones(),
        ...widget.extras,
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'HISTORIAL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            Text(
              _rango.etiqueta,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CalendarioFiltroMovimientos(
          fechas: [
            for (final e in _delAmbito)
              if (e.fecha != null) e.fecha!,
          ],
          valor: _rango,
          onChanged: (r) => setState(() => _rango = r),
          isDark: isDark,
          accent: accent,
        ),
        const SizedBox(height: 10),
        _filtrosTipo(isDark),
        const SizedBox(height: 10),
        if (visibles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${visibles.length} ${visibles.length == 1 ? "movimiento" : "movimientos"}'
              ' · neto ${totalVisible.toCurrency()}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ),
        if (visibles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _rango.esTodo
                  ? 'Todavía no hay movimientos con este filtro.'
                  : 'No hubo movimientos en ${_rango.etiqueta.toLowerCase()}.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          )
        else
          ...visibles.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _fila(e, isDark),
              )),
      ],
    );
  }

  Widget _grillaChips(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in widget.chips)
          Container(
            constraints: const BoxConstraints(minWidth: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.color.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: c.color,
                  ),
                ),
                Text(
                  c.monto.toCurrency(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filaAcciones() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in widget.acciones)
          SizedBox(
            width: widget.acciones.length > 2 ? 150 : 168,
            child: FilledButton.icon(
              onPressed: () async {
                // El navegador se toma antes del await: después de abrir el
                // diálogo este context puede haber quedado atrás.
                final nav = Navigator.of(context);
                final ok = await a.abrir(context);
                if (ok == true) {
                  widget.onRefresh?.call();
                  nav.pop();
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: a.color,
                foregroundColor: a.colorTexto,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(a.icon, size: 16),
              label: Text(
                a.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _filtrosTipo(bool isDark) {
    const teal = Color(0xFF26A69A);
    const violet = Color(0xFF6C63FF);
    final entradasVale = widget.ambito == AmbitoPanel.bolsillo;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chipTipo('Todo', _FiltroTipo.todos, widget.accent, isDark),
          const SizedBox(width: 6),
          _chipTipo('Efectivo', _FiltroTipo.efectivo, teal, isDark),
          const SizedBox(width: 6),
          _chipTipo('Transfer.', _FiltroTipo.transferencia, violet, isDark),
          if (entradasVale) ...[
            const SizedBox(width: 6),
            _chipTipo('Aparté', _FiltroTipo.entradas, const Color(0xFFFFB74D), isDark),
            const SizedBox(width: 6),
            _chipTipo('Gasté', _FiltroTipo.salidas, teal, isDark),
          ],
        ],
      ),
    );
  }

  Widget _chipTipo(String label, _FiltroTipo f, Color color, bool isDark) {
    final sel = _tipo == f;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: color.withValues(alpha: 0.2),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.03),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: sel ? color : (isDark ? Colors.white54 : Colors.black54),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: sel ? color.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      onSelected: (_) => setState(() => _tipo = f),
    );
  }

  Widget _fila(Egreso e, bool isDark) {
    const amber = Color(0xFFFFB74D);
    const teal = Color(0xFF26A69A);
    const indigo = Color(0xFF5C6BC0);
    const violet = Color(0xFF6C63FF);

    final cat = (e.categoria ?? '').trim();
    final entrada = _esEntrada(e, widget.ambito);

    final Color color;
    final IconData icon;
    final String badge;

    if (cat == kCategoriaRetiroDueno) {
      color = amber;
      icon = entrada ? Icons.south_west_rounded : Icons.north_east_rounded;
      badge = entrada ? 'APARTÉ PARA MÍ' : 'FUE A MI BOLSILLO';
    } else if (cat == kCategoriaGastoPersonal) {
      color = teal;
      icon = Icons.shopping_bag_rounded;
      badge = gastoPersonalEsDesdeEmpresa(e) ? 'GASTO MÍO · DEL NEGOCIO' : 'GASTO MÍO';
    } else if (cat == kCategoriaGastoEmpresa) {
      color = indigo;
      icon = Icons.store_rounded;
      badge = 'EMPRESA';
    } else if (cat == kCategoriaRetiroCaja) {
      color = amber;
      icon = Icons.lock_outline_rounded;
      badge = 'RETIRO DE CAJA';
    } else {
      color = indigo;
      icon = Icons.receipt_long_rounded;
      badge = cat.isEmpty ? 'EGRESO' : cat.toUpperCase();
    }

    final esTr = e.medioPago?.toLowerCase().trim() == 'transferencia';
    final fecha =
        e.fecha != null ? ArTime.formatFechaCorta(e.fecha!) : 'Sin fecha';
    final hora = e.fecha != null ? ArTime.formatHora(e.fecha!) : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.proveedorVisible ?? 'Movimiento',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$fecha${hora.isNotEmpty ? ' · $hora' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${entrada ? '+' : '−'}${e.monto.toCurrency()}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: (esTr ? violet : teal).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  esTr ? 'TR' : 'EF',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: esTr ? violet : teal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
