import 'package:flutter/material.dart';

import '../../modelo/armado_salon.dart';
import '../../services/editar_armado.dart';
import '../../services/medir_salon.dart';
import '../../services/sesion_acomodo.dart';
import 'panel_colores_textos.dart';

/// Personalizar → Acomodar: lo que se le puede hacer al salón, al lado del
/// plano. La mesa o el sector se eligen y se arrastran en el plano; acá están
/// los botones, separar o juntar, lo que hay que saber antes de guardar, y
/// GUARDAR.
///
/// No sabe nada del salón: muestra lo que le pasan y avisa lo que se toca.
class PanelAcomodar extends StatefulWidget {
  /// Lo elegido en el plano ("Mesa 12 · la tiene GÓMEZ"). Null: nada.
  final String? seleccion;

  /// Algo más de lo elegido: a cuántos metros está de las mesas vecinas.
  final String? detalle;

  /// Lo que pasó con lo último que se tocó ("Mesa 133 agregada…").
  final String? mensaje;

  final VoidCallback onAgregar;

  /// Null: no hay una mesa elegida.
  final VoidCallback? onSacar;
  final VoidCallback? onPasto;

  /// La mesa elegida ya es de pasto: el botón la devuelve al salón.
  final bool mesaEnPasto;
  final VoidCallback? onDeshacer;

  // ── Sectores ──
  final ValueChanged<TipoSector> onAgregarSector;

  /// Null: no hay un sector elegido.
  final VoidCallback? onSacarSector;

  /// Agrandar o achicar el sector elegido, de a medio metro (ancho, alto).
  final void Function(double anchoM, double altoM)? onTamanoSector;

  /// "4 × 2 m", lo que mide el sector elegido.
  final String? tamanoSector;

  // ── Separar o juntar ──
  final List<AlcanceSeparar> alcances;
  final String alcance;
  final ValueChanged<String> onAlcance;

  /// La distancia que marca la barra, en metros.
  final double paso;
  final ValueChanged<double> onPaso;

  /// Cómo quedaría (si se movió la barra) y si entra.
  final String? textoPrevia;
  final bool previaEntra;

  /// A esa distancia se puede aplicar. Si no, [textoPrevia] dice por qué y
  /// APLICAR queda gris.
  final bool previaSePuede;
  final VoidCallback? onAplicar;
  final VoidCallback? onCancelar;

  // ── Antes de guardar ──
  /// Lo que no deja guardar. Va pegado a GUARDAR, siempre a la vista: es por
  /// qué el botón está gris.
  final List<AvisoAcomodo> bloqueos;

  /// Lo que conviene saber.
  final List<AvisoAcomodo> avisos;

  /// Se tocó un aviso o un bloqueo que habla de alguna mesa: hay que
  /// llevar la vista a ella.
  final ValueChanged<AvisoAcomodo>? onAviso;

  /// Por qué no se puede volver al armado original. Null: se puede.
  final String? motivoSinOriginal;
  final VoidCallback onOriginal;

  final bool hayCambios;
  final bool puedeGuardar;
  final bool ocupado;

  /// DESCARTAR ya se tocó una vez: falta confirmarlo.
  final bool confirmarDescartar;
  final VoidCallback onGuardar;
  final VoidCallback onDescartar;

  const PanelAcomodar({
    super.key,
    required this.seleccion,
    this.detalle,
    required this.mensaje,
    required this.onAgregar,
    required this.onSacar,
    required this.onPasto,
    required this.mesaEnPasto,
    required this.onDeshacer,
    required this.onAgregarSector,
    required this.onSacarSector,
    required this.onTamanoSector,
    required this.tamanoSector,
    required this.alcances,
    required this.alcance,
    required this.onAlcance,
    required this.paso,
    required this.onPaso,
    required this.textoPrevia,
    required this.previaEntra,
    this.previaSePuede = true,
    required this.onAplicar,
    required this.onCancelar,
    required this.bloqueos,
    required this.avisos,
    this.onAviso,
    required this.motivoSinOriginal,
    required this.onOriginal,
    required this.hayCambios,
    required this.puedeGuardar,
    required this.onGuardar,
    required this.onDescartar,
    this.confirmarDescartar = false,
    this.ocupado = false,
  });

  @override
  State<PanelAcomodar> createState() => _PanelAcomodarState();
}

class _PanelAcomodarState extends State<PanelAcomodar> {
  /// El panel es más largo que una notebook: la barra queda a la vista para
  /// que se note que hay más abajo.
  final _barra = ScrollController();

  @override
  void dispose() {
    _barra.dispose();
    super.dispose();
  }

  // Lo que el panel muestra, a mano.
  String? get seleccion => widget.seleccion;
  String? get detalle => widget.detalle;
  String? get mensaje => widget.mensaje;
  VoidCallback get onAgregar => widget.onAgregar;
  VoidCallback? get onSacar => widget.onSacar;
  VoidCallback? get onPasto => widget.onPasto;
  bool get mesaEnPasto => widget.mesaEnPasto;
  VoidCallback? get onDeshacer => widget.onDeshacer;
  ValueChanged<TipoSector> get onAgregarSector => widget.onAgregarSector;
  VoidCallback? get onSacarSector => widget.onSacarSector;
  void Function(double anchoM, double altoM)? get onTamanoSector =>
      widget.onTamanoSector;
  String? get tamanoSector => widget.tamanoSector;
  List<AlcanceSeparar> get alcances => widget.alcances;
  String get alcance => widget.alcance;
  ValueChanged<String> get onAlcance => widget.onAlcance;
  double get paso => widget.paso;
  ValueChanged<double> get onPaso => widget.onPaso;
  String? get textoPrevia => widget.textoPrevia;
  bool get previaEntra => widget.previaEntra;
  bool get previaSePuede => widget.previaSePuede;
  VoidCallback? get onAplicar => widget.onAplicar;
  VoidCallback? get onCancelar => widget.onCancelar;
  List<AvisoAcomodo> get bloqueos => widget.bloqueos;
  List<AvisoAcomodo> get avisos => widget.avisos;
  String? get motivoSinOriginal => widget.motivoSinOriginal;
  VoidCallback get onOriginal => widget.onOriginal;
  bool get hayCambios => widget.hayCambios;
  bool get puedeGuardar => widget.puedeGuardar;
  bool get ocupado => widget.ocupado;
  bool get confirmarDescartar => widget.confirmarDescartar;
  VoidCallback get onGuardar => widget.onGuardar;
  VoidCallback get onDescartar => widget.onDescartar;

  /// Un aviso o un bloqueo. Si habla de alguna mesa se toca y lleva a ella.
  Widget _renglon(
    String clave,
    AvisoAcomodo a, {
    required IconData icono,
    required Color color,
  }) {
    final lleva = a.mesas.isNotEmpty && widget.onAviso != null;
    return _Renglon(
      key: Key(clave),
      texto: a.texto,
      icono: icono,
      color: color,
      onTap: lleva && !ocupado ? () => widget.onAviso!(a) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final gris = TextStyle(color: Colors.grey.shade700, fontSize: 12.5);
    const compacto = ButtonStyle(visualDensity: VisualDensity.compact);

    Widget titulo(String texto) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.6,
            ),
          ),
        );

    Widget boton(
      String clave,
      String texto,
      IconData icono,
      VoidCallback? f,
    ) =>
        OutlinedButton.icon(
          key: Key(clave),
          style: compacto,
          onPressed: ocupado ? null : f,
          icon: Icon(icono, size: 16),
          label: Text(texto),
        );

    final probando = textoPrevia != null;

    return Column(
      key: const Key('panel_acomodar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Scrollbar(
            key: const Key('barra_acomodar'),
            controller: _barra,
            thumbVisibility: true,
            child: ListView(
            controller: _barra,
            // Lugar para la barra: que no pise los botones.
            padding: const EdgeInsets.only(right: 12),
            children: [
              Container(
                key: const Key('elegido_acomodar'),
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: seleccion == null
                        ? Colors.black12
                        : tema.colorScheme.primary,
                    width: seleccion == null ? 1 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seleccion ?? 'Tocá una mesa o un sector, o arrastralo.',
                      style: seleccion == null
                          ? gris
                          : const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (detalle != null)
                      Text(
                        detalle!,
                        key: const Key('detalle_acomodar'),
                        style: gris,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  boton('acomodar_agregar', 'Agregar mesa', Icons.add,
                      probando ? null : onAgregar),
                  boton('acomodar_sacar', 'Sacar', Icons.delete_outline,
                      probando ? null : onSacar),
                  boton(
                    'acomodar_pasto',
                    mesaEnPasto ? 'Sacar del pasto' : 'Es de pasto',
                    Icons.grass,
                    probando ? null : onPasto,
                  ),
                  boton('acomodar_deshacer', 'Deshacer', Icons.undo,
                      probando ? null : onDeshacer),
                ],
              ),
              if (mensaje != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    mensaje!,
                    key: const Key('mensaje_acomodar'),
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              titulo('SEPARAR O JUNTAR'),
              if (alcances.isEmpty)
                Text('En esta hoja no hay mesas para separar.', style: gris)
              else ...[
                DropdownButtonFormField<String>(
                  key: const Key('separar_alcance'),
                  initialValue: alcance,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    for (final a in alcances)
                      DropdownMenuItem(
                        value: a.clave,
                        child: Text(
                          '${a.rotulo} (${a.numeros.length})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: ocupado
                      ? null
                      : (v) {
                          if (v != null) onAlcance(v);
                        },
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        key: const Key('separar_paso'),
                        min: EditarArmado.separarMinimoM,
                        max: EditarArmado.separarMaximoM,
                        divisions: ((EditarArmado.separarMaximoM -
                                    EditarArmado.separarMinimoM) /
                                0.05)
                            .round(),
                        value: paso.clamp(
                          EditarArmado.separarMinimoM,
                          EditarArmado.separarMaximoM,
                        ),
                        onChanged: ocupado ? null : onPaso,
                      ),
                    ),
                    SizedBox(
                      width: 58,
                      child: Text(
                        MedirSalon.metros(paso, decimales: 2),
                        key: const Key('separar_metros'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Text(
                  textoPrevia ??
                      'Mové la barra para ver cómo queda. La fila de adelante '
                          'y la pasarela no se mueven.',
                  key: const Key('separar_previa'),
                  style: probando
                      ? TextStyle(
                          fontWeight: FontWeight.w700,
                          color: previaEntra
                              ? Colors.green.shade800
                              : Colors.red.shade700,
                        )
                      : gris,
                ),
                if (probando)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        FilledButton(
                          key: const Key('separar_aplicar'),
                          style: compacto,
                          onPressed:
                              ocupado || !previaSePuede ? null : onAplicar,
                          child: const Text('APLICAR'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          key: const Key('separar_cancelar'),
                          style: compacto,
                          onPressed: ocupado ? null : onCancelar,
                          child: const Text('CANCELAR'),
                        ),
                      ],
                    ),
                  ),
              ],
              titulo('SECTORES'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<TipoSector>(
                    key: const Key('acomodar_agregar_sector'),
                    enabled: !ocupado && !probando,
                    tooltip: 'Agregar un sector',
                    onSelected: onAgregarSector,
                    itemBuilder: (context) => [
                      for (final t in TipoSector.values)
                        PopupMenuItem(
                          value: t,
                          child: Text(PanelColoresTextos.rotuloDe(t)),
                        ),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(
                        style: compacto,
                        onPressed: ocupado || probando ? null : () {},
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar sector'),
                      ),
                    ),
                  ),
                  if (onSacarSector != null)
                    boton('acomodar_sacar_sector', 'Sacar sector',
                        Icons.delete_outline, probando ? null : onSacarSector),
                ],
              ),
              if (onTamanoSector != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mide ${tamanoSector ?? ''}',
                        key: const Key('tamano_sector'),
                      ),
                    ),
                    for (final (clave, pista, icono, dx, dy) in const [
                      ('sector_menos_ancho', 'Más angosto', Icons.west, -0.5, 0.0),
                      ('sector_mas_ancho', 'Más ancho', Icons.east, 0.5, 0.0),
                      ('sector_menos_alto', 'Más corto', Icons.north, 0.0, -0.5),
                      ('sector_mas_alto', 'Más largo', Icons.south, 0.0, 0.5),
                    ])
                      IconButton(
                        key: Key(clave),
                        tooltip: pista,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        // Con la vista previa de separar abierta no se toca
                        // nada más: se aplica o se cancela primero.
                        onPressed: ocupado || probando
                            ? null
                            : () => onTamanoSector!(dx, dy),
                        icon: Icon(icono),
                      ),
                  ],
                ),
              ],
              if (avisos.isNotEmpty) ...[
                titulo('ANTES DE GUARDAR'),
                for (final (i, a) in avisos.indexed)
                  _renglon(
                    'aviso_acomodar_$i',
                    a,
                    icono: Icons.info_outline,
                    color: Colors.orange.shade800,
                  ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('acomodar_original'),
                  style: compacto,
                  onPressed: ocupado || probando || motivoSinOriginal != null
                      ? null
                      : onOriginal,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('VOLVER AL ARMADO ORIGINAL'),
                ),
              ),
              if (motivoSinOriginal != null)
                Text(
                  motivoSinOriginal!,
                  key: const Key('motivo_sin_original'),
                  style: gris,
                ),
            ],
          ),
          ),
        ),
        // Por qué GUARDAR está gris, pegado al botón y fuera de lo que se
        // desliza: en una notebook quedaba abajo de todo, sin verse.
        if (bloqueos.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final (i, b) in bloqueos.take(_maximoBloqueos).indexed)
            _renglon(
              'bloqueo_$i',
              b,
              icono: Icons.error_outline,
              color: Colors.red.shade700,
            ),
          if (bloqueos.length > _maximoBloqueos)
            Padding(
              padding: const EdgeInsets.only(left: 23),
              child: Text(
                'Y ${bloqueos.length - _maximoBloqueos} más.',
                key: const Key('bloqueos_mas'),
                style: gris,
              ),
            ),
        ] else if (hayCambios && probando)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Para guardar, primero tocá APLICAR o CANCELAR en Separar o '
              'juntar.',
              key: const Key('motivo_sin_guardar'),
              style: gris,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('guardar_acomodo'),
                onPressed: puedeGuardar && !ocupado ? onGuardar : null,
                icon: const Icon(Icons.check, size: 18),
                label: Text(hayCambios ? 'GUARDAR EL SALÓN' : 'SALÓN GUARDADO'),
              ),
            ),
            if (hayCambios) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('descartar_acomodo'),
                onPressed: ocupado ? null : onDescartar,
                child: Text(confirmarDescartar ? '¿DESCARTAR TODO?' : 'DESCARTAR'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Cuántos bloqueos se muestran arriba de GUARDAR: con muchas mesas pisadas
/// se comerían el panel.
const _maximoBloqueos = 3;

class _Renglon extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color color;

  /// Null: el renglón solo informa. Si no, se toca y lleva a su mesa.
  final VoidCallback? onTap;

  const _Renglon({
    super.key,
    required this.texto,
    required this.icono,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, size: 17, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(texto)),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
            ],
          ),
        ),
      );
}
