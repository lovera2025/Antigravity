import 'package:flutter/material.dart';

import '../../recepcion/services/lista_puerta.dart';

/// Las herramientas de la fiesta, a la vista en la barra del evento masivo:
/// PLANO, SORTEO, PLANILLAS y ENTRADAS, al lado de MÁS.
///
/// Antes estaban todas adentro de MÁS. Acá cada una tiene su botón, con los
/// mismos textos, y en MÁS ([BotonMasFiesta]) queda lo que no es de la fiesta
/// (ordenar, selección múltiple) y la lista de la puerta.
///
/// Los nombres se muestran solo si entran en el ancho que le toca: la barra
/// reparte primero los contadores y REGISTRAR, y este grupo usa lo que sobra.
/// Si no alcanza, quedan los íconos con el nombre al pasar el mouse.
///
/// No sabe nada de la base: recibe qué hacer con cada toque. Lo que no se
/// puede hacer llega en null y queda apagado con el motivo escrito.
class GrupoFiestaToolbar extends StatelessWidget {
  /// Los tamaños chicos de la barra (ventanas de menos de 1520 px).
  final bool compacto;

  final VoidCallback onPlano;

  final VoidCallback onSortear;
  final VoidCallback onDeshacer;

  /// Null: no hay copia guardada al deshacer, y el ítem no aparece.
  final VoidCallback? onRestaurar;
  final VoidCallback onHistorial;

  /// Null: la fiesta no tiene alumnos.
  final VoidCallback? onPlanillaSorteo;

  /// Null: la fiesta todavía no tiene plano.
  final VoidCallback? onPlanoImpreso;
  final VoidCallback onPlanillaEntrega;

  /// Null: nadie debe mora.
  final VoidCallback? onPlanillaMora;
  final int alumnosConMora;

  final VoidCallback onEntradas;

  const GrupoFiestaToolbar({
    super.key,
    required this.compacto,
    required this.onPlano,
    required this.onSortear,
    required this.onDeshacer,
    required this.onRestaurar,
    required this.onHistorial,
    required this.onPlanillaSorteo,
    required this.onPlanoImpreso,
    required this.onPlanillaEntrega,
    required this.onPlanillaMora,
    required this.alumnosConMora,
    required this.onEntradas,
  });

  /// El ancho que piden los cuatro botones con su nombre. Con menos, van solo
  /// los íconos. `test/grupo_fiesta_toolbar_test.dart` cuida que el grupo con
  /// nombres entre de verdad en esta medida.
  static double anchoConNombres({required bool compacto}) =>
      compacto ? 440 : 540;

  /// El ancho de los cuatro botones sin nombre: lo que la barra le reserva al
  /// grupo como mínimo.
  static double anchoSoloIconos({required bool compacto}) =>
      compacto ? 200 : 260;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final conNombres =
            constraints.maxWidth >= anchoConNombres(compacto: compacto);
        return Align(
          alignment: Alignment.centerRight,
          // Si ni los íconos entran (una ventana muy angosta), se desliza en
          // vez de desbordar.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              key: const Key('fiesta_grupo'),
              mainAxisSize: MainAxisSize.min,
              children: [
                _plano(context, conNombres),
                SizedBox(width: compacto ? 6 : 8),
                _sorteo(context, conNombres),
                SizedBox(width: compacto ? 6 : 8),
                _planillas(context, conNombres),
                SizedBox(width: compacto ? 6 : 8),
                _entradas(context, conNombres),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Los cuatro botones ──────────────────────────────────────────────────

  Widget _plano(BuildContext context, bool conNombres) => _botonSimple(
        context,
        clave: 'fiesta_plano',
        icono: Icons.table_restaurant_outlined,
        nombre: 'PLANO',
        ayuda: 'Plano del salón: el armado, las medidas y dónde está cada '
            'familia',
        conNombre: conNombres,
        onTap: onPlano,
      );

  Widget _entradas(BuildContext context, bool conNombres) => _botonSimple(
        context,
        clave: 'fiesta_entradas',
        icono: Icons.confirmation_number_outlined,
        nombre: 'ENTRADAS',
        ayuda: 'Retiro de entradas: quién retiró, quién falta y la planilla '
            'en papel',
        conNombre: conNombres,
        onTap: onEntradas,
      );

  Widget _sorteo(BuildContext context, bool conNombres) =>
      PopupMenuButton<VoidCallback>(
        key: const Key('fiesta_sorteo'),
        tooltip: 'Sorteo de mesas',
        position: PopupMenuPosition.under,
        shape: _formaMenu,
        onSelected: (accion) => accion(),
        itemBuilder: (context) => [
          _item(
            accion: onSortear,
            icono: Icons.casino,
            color: Colors.indigo,
            titulo: 'Sortear mesas',
          ),
          _item(
            accion: onDeshacer,
            icono: Icons.undo,
            color: Colors.deepOrange,
            titulo: 'Deshacer sorteo de mesas',
          ),
          if (onRestaurar != null)
            _item(
              accion: onRestaurar,
              icono: Icons.restore_rounded,
              color: Colors.teal,
              titulo: 'Restaurar sorteo anterior',
              detalle: 'La copia guardada al deshacer',
            ),
          _item(
            accion: onHistorial,
            icono: Icons.history,
            titulo: 'Historial de las mesas',
            detalle: 'Quién sorteó o cambió una mesa, cuándo y por qué',
          ),
        ],
        child: _cara(
          context,
          icono: Icons.casino_outlined,
          nombre: 'SORTEO',
          conNombre: conNombres,
          conFlecha: true,
        ),
      );

  Widget _planillas(BuildContext context, bool conNombres) =>
      PopupMenuButton<VoidCallback>(
        key: const Key('fiesta_planillas'),
        tooltip: 'Planillas para imprimir',
        position: PopupMenuPosition.under,
        shape: _formaMenu,
        onSelected: (accion) => accion(),
        itemBuilder: (context) => [
          _item(
            accion: onPlanillaSorteo,
            icono: Icons.print_rounded,
            titulo: 'Planilla del sorteo',
            detalle: onPlanillaSorteo == null
                ? 'Todavía no hay alumnos'
                : 'Una hoja por división, para imprimir o repartir',
          ),
          _item(
            accion: onPlanoImpreso,
            icono: Icons.map_outlined,
            color: Colors.indigo,
            titulo: 'Plano impreso',
            detalle: onPlanoImpreso == null
                ? 'Todavía no hay plano: armalo en PLANO'
                : 'El salón en papel, en color o en blanco y negro',
          ),
          _item(
            accion: onPlanillaEntrega,
            icono: Icons.confirmation_number_outlined,
            color: Colors.green,
            titulo: 'Planilla de entrega',
            detalle: 'Entradas y pulseras, una hoja por división',
          ),
          _item(
            accion: onPlanillaMora,
            icono: Icons.picture_as_pdf_outlined,
            titulo: 'Planilla de mora',
            detalle: onPlanillaMora == null
                ? 'Nadie debe mora'
                : '$alumnosConMora alumno(s) para llamar',
          ),
        ],
        child: _cara(
          context,
          icono: Icons.print_outlined,
          nombre: 'PLANILLAS',
          conNombre: conNombres,
          conFlecha: true,
        ),
      );

  // ── Piezas ──────────────────────────────────────────────────────────────

  double get _radio => compacto ? 12 : 16;

  ShapeBorder get _formaMenu =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radio));

  /// Un renglón de menú. Con [accion] en null queda apagado: el [detalle]
  /// dice por qué.
  PopupMenuItem<VoidCallback> _item({
    required VoidCallback? accion,
    required IconData icono,
    required String titulo,
    Color? color,
    String? detalle,
  }) =>
      PopupMenuItem<VoidCallback>(
        value: accion,
        enabled: accion != null,
        child: ListTile(
          dense: true,
          enabled: accion != null,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icono, color: accion == null ? null : color),
          title: Text(titulo),
          subtitle: detalle == null ? null : Text(detalle),
        ),
      );

  /// Un botón que abre su pantalla de un toque (PLANO y ENTRADAS).
  Widget _botonSimple(
    BuildContext context, {
    required String clave,
    required IconData icono,
    required String nombre,
    required String ayuda,
    required bool conNombre,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: ayuda,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key(clave),
            borderRadius: BorderRadius.circular(_radio),
            onTap: onTap,
            child: _cara(
              context,
              icono: icono,
              nombre: nombre,
              conNombre: conNombre,
            ),
          ),
        ),
      );

  /// Lo que se ve de cada botón: igual al de MÁS, que está al lado.
  Widget _cara(
    BuildContext context, {
    required IconData icono,
    required String nombre,
    required bool conNombre,
    bool conFlecha = false,
  }) =>
      _caraBoton(
        context,
        compacto: compacto,
        icono: icono,
        nombre: conNombre ? nombre : null,
        conFlecha: conFlecha,
      );
}

/// El botón MÁS de la barra del evento masivo: lo que no es de la fiesta
/// (ordenar, selección múltiple) y la lista de la puerta.
///
/// "Pasar a la lista de la puerta" queda a la vista pero apagado mientras
/// [kListaPuertaHabilitada] sea false, con el motivo escrito: así no parece
/// que se perdió.
class BotonMasFiesta extends StatelessWidget {
  final bool compacto;
  final bool ordenAlfabetico;
  final bool modoSeleccion;
  final VoidCallback onOrden;
  final VoidCallback onSeleccion;
  final VoidCallback onListaPuerta;
  final bool listaPuertaHabilitada;

  const BotonMasFiesta({
    super.key,
    required this.compacto,
    required this.ordenAlfabetico,
    required this.modoSeleccion,
    required this.onOrden,
    required this.onSeleccion,
    required this.onListaPuerta,
    this.listaPuertaHabilitada = kListaPuertaHabilitada,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      key: const Key('fiesta_mas'),
      tooltip: 'Más acciones',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compacto ? 12 : 16),
      ),
      onSelected: (accion) => accion(),
      itemBuilder: (context) => [
        PopupMenuItem<VoidCallback>(
          value: onOrden,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              ordenAlfabetico ? Icons.sort_by_alpha : Icons.schedule,
            ),
            title: Text(ordenAlfabetico ? 'Ordenar por fecha' : 'Ordenar A-Z'),
            subtitle: Text(
              ordenAlfabetico ? 'Ahora: alfabético' : 'Ahora: por alta',
            ),
          ),
        ),
        PopupMenuItem<VoidCallback>(
          value: onSeleccion,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              modoSeleccion ? Icons.close : Icons.checklist_rounded,
            ),
            title: Text(
              modoSeleccion ? 'Salir de selección' : 'Selección múltiple',
            ),
            subtitle: const Text('Marcar contratos de varios a la vez'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<VoidCallback>(
          value: onListaPuerta,
          enabled: listaPuertaHabilitada,
          child: ListTile(
            dense: true,
            enabled: listaPuertaHabilitada,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.door_front_door_outlined,
              color: listaPuertaHabilitada ? Colors.teal : null,
            ),
            title: const Text('Pasar a la lista de la puerta'),
            subtitle: Text(
              listaPuertaHabilitada
                  ? 'Alumnos y familias con su mesa, para el tótem'
                  : kListaPuertaTrabadaLeyenda,
            ),
          ),
        ),
      ],
      child: _caraBoton(
        context,
        compacto: compacto,
        icono: Icons.more_vert,
        nombre: 'MÁS',
        separacion: compacto ? 2 : 4,
      ),
    );
  }
}

/// La cara de un botón de la barra: un ícono y, si hay lugar, su nombre.
Widget _caraBoton(
  BuildContext context, {
  required bool compacto,
  required IconData icono,
  String? nombre,
  bool conFlecha = false,
  double? separacion,
}) {
  final oscuro = Theme.of(context).brightness == Brightness.dark;
  final double tamIcono = compacto ? 15 : 18;
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compacto ? 10 : 14,
      vertical: compacto ? 7 : 10,
    ),
    decoration: BoxDecoration(
      color: oscuro ? Colors.white12 : Colors.black12,
      borderRadius: BorderRadius.circular(compacto ? 12 : 16),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: tamIcono),
        if (nombre != null) ...[
          SizedBox(width: separacion ?? (compacto ? 4 : 6)),
          Text(
            nombre,
            style: TextStyle(
              fontSize: compacto ? 11 : 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
        if (conFlecha) Icon(Icons.arrow_drop_down, size: tamIcono),
      ],
    ),
  );
}
