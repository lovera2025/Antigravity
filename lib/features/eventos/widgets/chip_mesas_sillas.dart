import 'package:flutter/material.dart';

import '../services/filtro_mesas_sillas.dart';

/// Chip "Mesas y sillas" de la barra del evento masivo: cuántas familias
/// tienen algo sin pagar o para revisar, y el filtro para verlas.
///
/// Se lee igual que el chip de mora, que está al lado. Las opciones van en
/// tres grupos (mesas, sillas, revisar), cada una con cuántos hay, para llegar
/// al sorteo sabiendo quién tiene qué y quién lo pagó.
class ChipMesasSillas extends StatelessWidget {
  final FiltroExtras filtro;
  final ValueChanged<FiltroExtras> onFiltro;

  /// Familias con algo pendiente: lo que muestra el chip.
  final int pendientes;

  /// Cuántos alumnos entran en cada opción.
  final Map<FiltroExtras, int> cuantos;

  /// Lo cargado en el evento y lo que daría hoy el sorteo.
  final ({int mesas, int agregadas, int conLoPagado, int sillas}) totales;
  final bool compacto;

  const ChipMesasSillas({
    super.key,
    required this.filtro,
    required this.onFiltro,
    required this.pendientes,
    required this.cuantos,
    required this.totales,
    this.compacto = false,
  });

  static const _titulos = {
    GrupoFiltroExtras.mesas: 'MESAS',
    GrupoFiltroExtras.sillas: 'SILLAS',
    GrupoFiltroExtras.revisar: 'ANTES DEL SORTEO',
  };

  /// "Mesas: 132 (14 agregadas) · con lo pagado hoy: 121 · Sillas extra: 30".
  String get resumen =>
      'Mesas: ${totales.mesas} (${totales.agregadas} '
      '${totales.agregadas == 1 ? 'agregada' : 'agregadas'}) · con lo pagado '
      'hoy: ${totales.conLoPagado} · Sillas extra: ${totales.sillas}';

  @override
  Widget build(BuildContext context) {
    final activo = filtro.activo;
    final color = pendientes == 0 && !activo
        ? Colors.grey
        : Colors.deepPurple.shade600;

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 6 : 10,
        vertical: compacto ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: activo ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(compacto ? 10 : 12),
        border: Border.all(
          color: color.withValues(alpha: activo ? 1 : 0.45),
          width: activo ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.table_restaurant_outlined,
            size: compacto ? 13 : 14,
            color: color,
          ),
          SizedBox(width: compacto ? 4 : 6),
          Text(
            '$pendientes',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: compacto ? 12 : 13,
              color: color,
            ),
          ),
          if (activo) ...[
            SizedBox(width: compacto ? 3 : 5),
            Text(
              filtro.label.toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compacto ? 9 : 10,
                letterSpacing: 0.4,
                color: color,
              ),
            ),
          ],
          SizedBox(width: compacto ? 2 : 4),
          Icon(Icons.arrow_drop_down, size: compacto ? 14 : 16, color: color),
        ],
      ),
    );

    PopupMenuItem<FiltroExtras> opcion(FiltroExtras f) => PopupMenuItem(
          value: f,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              f == filtro
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: f == filtro ? Colors.deepPurple.shade600 : null,
            ),
            title: Text(f.label),
            subtitle: Text(f.ayuda),
            trailing: f.activo
                ? Text(
                    '${cuantos[f] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  )
                : null,
          ),
        );

    PopupMenuItem<FiltroExtras> titulo(String texto) => PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              color: Colors.grey.shade600,
            ),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<FiltroExtras>(
          tooltip: 'Mesas y sillas de cada uno, y quién las pagó.\n$resumen',
          position: PopupMenuPosition.under,
          initialValue: filtro,
          onSelected: onFiltro,
          itemBuilder: (context) => [
            opcion(FiltroExtras.todos),
            for (final grupo in GrupoFiltroExtras.values) ...[
              titulo(_titulos[grupo]!),
              for (final f in FiltroExtras.values)
                if (f.grupo == grupo) opcion(f),
            ],
          ],
          child: chip,
        ),
        if (activo) ...[
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            iconSize: compacto ? 15 : 17,
            tooltip: 'Quitar el filtro de mesas y sillas',
            icon: const Icon(Icons.close),
            onPressed: () => onFiltro(FiltroExtras.todos),
          ),
        ],
      ],
    );
  }
}
