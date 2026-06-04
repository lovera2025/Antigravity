import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/egreso.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../common/utils/currency_extensions.dart';
import '../../../core/utils/ar_time.dart';
import '../bolsa_personal_helpers.dart';
import 'editar_egreso_bolsillo_dialog.dart';
import 'gasto_personal_dialog.dart';

enum BolsilloFiltro { todos, efectivo, transferencia, retiros, gastos, empresa }

/// Historial interactivo de retiros al bolsillo y gastos personales del dueño.
class BolsilloTimeline extends StatefulWidget {
  final List<Egreso> egresos;
  final bool isDark;
  final Color gold;
  final void Function(Egreso egreso)? onEditEgreso;

  const BolsilloTimeline({
    super.key,
    required this.egresos,
    required this.isDark,
    required this.gold,
    this.onEditEgreso,
  });

  @override
  State<BolsilloTimeline> createState() => _BolsilloTimelineState();
}

class _BolsilloTimelineState extends State<BolsilloTimeline> {
  BolsilloFiltro _filtro = BolsilloFiltro.todos;

  List<Egreso> get _movimientos {
    return widget.egresos.where((e) {
      final cat = (e.categoria ?? '').trim();
      if (cat != kCategoriaRetiroDueno && cat != kCategoriaGastoPersonal && cat != kCategoriaGastoEmpresa) return false;
      switch (_filtro) {
        case BolsilloFiltro.todos:
          return true;
        case BolsilloFiltro.efectivo:
          return e.medioPago?.toLowerCase().trim() != 'transferencia';
        case BolsilloFiltro.transferencia:
          return e.medioPago?.toLowerCase().trim() == 'transferencia';
        case BolsilloFiltro.retiros:
          return cat == kCategoriaRetiroDueno;
        case BolsilloFiltro.gastos:
          return cat == kCategoriaGastoPersonal;
        case BolsilloFiltro.empresa:
          return cat == kCategoriaGastoEmpresa;
      }
    }).toList()
      ..sort((a, b) {
        final fa = a.fecha;
        final fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });
  }

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFB74D);
    const teal = Color(0xFF26A69A);
    final items = _movimientos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip('Todo', BolsilloFiltro.todos, amber),
              const SizedBox(width: 6),
              _chip('Efectivo', BolsilloFiltro.efectivo, teal),
              const SizedBox(width: 6),
              _chip('Transfer.', BolsilloFiltro.transferencia, const Color(0xFF6C63FF)),
              const SizedBox(width: 6),
              _chip('Retiros', BolsilloFiltro.retiros, amber),
              const SizedBox(width: 6),
              _chip('Gastos', BolsilloFiltro.gastos, teal),
              const SizedBox(width: 6),
              _chip('Empresa', BolsilloFiltro.empresa, const Color(0xFF5C6BC0)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Todavía no hay movimientos en tu bolsillo con este filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final e = items[i];
              final cat = (e.categoria ?? '').trim();
              final esRetiro = cat == kCategoriaRetiroDueno;
              final esEmpresa = cat == kCategoriaGastoEmpresa;
              final esDesdeEmpresa = !esRetiro && !esEmpresa && gastoPersonalEsDesdeEmpresa(e);

              final Color accent;
              final IconData icon;
              final String badge;

              if (esRetiro) {
                accent = amber;
                icon = Icons.north_east_rounded;
                badge = 'PERSONAL';
              } else if (esEmpresa) {
                accent = const Color(0xFF5C6BC0);
                icon = Icons.store_rounded;
                badge = 'EMPRESA';
              } else if (esDesdeEmpresa) {
                accent = teal;
                icon = Icons.south_west_rounded;
                badge = 'GASTO MÍO';
              } else {
                accent = teal;
                icon = Icons.south_west_rounded;
                badge = 'GASTO MÍO';
              }

              final esTr = e.medioPago?.toLowerCase().trim() == 'transferencia';
              final fecha = e.fecha != null ? ArTime.formatFechaCorta(e.fecha!) : 'Sin fecha';
              final hora = e.fecha != null ? ArTime.formatHora(e.fecha!) : '';
              final titulo = proveedorGastoPersonalVisible(e.proveedor);

              return Material(
                color: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: widget.onEditEgreso != null ? () => widget.onEditEgreso!(e) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accent, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titulo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      badge,
                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: accent),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$fecha${hora.isNotEmpty ? ' · $hora' : ''}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: widget.isDark ? Colors.white54 : Colors.black54,
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
                              '−${e.monto.toCurrency()}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (esTr ? const Color(0xFF6C63FF) : teal).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                esTr ? 'TR' : 'EF',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: esTr ? const Color(0xFF6C63FF) : teal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _chip(String label, BolsilloFiltro f, Color color) {
    final sel = _filtro == f;
    return ChoiceChip(
      label: Text(label),
      selected: sel,
      selectedColor: color.withValues(alpha: 0.2),
      backgroundColor: widget.isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: sel ? color : (widget.isDark ? Colors.white54 : Colors.black54),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: sel ? color.withValues(alpha: 0.5) : Colors.transparent),
      ),
      onSelected: (_) => setState(() => _filtro = f),
    );
  }
}

/// Bottom sheet con historial del bolsillo personal.
Future<void> showBolsilloHistorialSheet(
  BuildContext context, {
  required List<Egreso> egresos,
  required bool isDark,
  required Color gold,
  required double gastadoTotal,
  required double retiroPendiente,
  required double retiradoTotal,
  required double gastadoEfectivo,
  required double gastadoTransferencia,
  VoidCallback? onRefresh,
}) {
  const amber = Color(0xFFFFB74D);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121218) : const Color(0xFFFCF9F2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: amber.withValues(alpha: 0.3)),
            ),
            child: ListView(
              controller: scrollCtrl,
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
                  'MI BOLSILLO',
                  style: GoogleFonts.oswald(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: amber,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lo que retiraste menos lo que gastaste = tu disponible.',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                ),
                const SizedBox(height: 16),
                Text(
                  retiroPendiente.toCurrency(),
                  style: GoogleFonts.oswald(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'disponible',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _saldoChip('Retiré', retiradoTotal, Colors.orange, isDark),
                    const SizedBox(width: 8),
                    _saldoChip('Gasté', gastadoTotal, const Color(0xFF00B894), isDark),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _saldoChip('Gasté EF', gastadoEfectivo, const Color(0xFF26A69A), isDark),
                    const SizedBox(width: 8),
                    _saldoChip('Gasté TR', gastadoTransferencia, const Color(0xFF6C63FF), isDark),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => const GastoPersonalDialog(),
                      );
                      if (result == true) {
                        onRefresh?.call();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF26A69A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                    label: const Text('REGISTRAR GASTO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'HISTORIAL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 10),
                BolsilloTimeline(
                  egresos: egresos,
                  isDark: isDark,
                  gold: gold,
                  onEditEgreso: (egreso) async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (_) => EditarEgresoBolsilloDialog(egreso: egreso),
                    );
                    if (result == true) {
                      onRefresh?.call();
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Widget _saldoChip(String label, double monto, Color color, bool isDark) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
          Text(
            monto.toCurrency(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    ),
  );
}
