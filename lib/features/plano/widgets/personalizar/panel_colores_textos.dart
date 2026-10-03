import 'package:flutter/material.dart';

import '../../../../models/plano_evento.dart';
import '../../estilos/estilo_plano.dart';
import '../../modelo/armado_salon.dart';
import '../../services/colores_y_textos.dart';

/// Una división de la fiesta, para elegirle el color.
typedef DivisionParaColor = ({
  /// La clave con la que se agrupa (`Divisiones.clave`).
  String clave,

  /// Como se muestra ("5° A").
  String nombre,

  /// Su lugar en la leyenda del plano, que es el color que lleva si no se le
  /// elige otro. Null: todavía no tiene familias con mesa.
  int? lugar,
});

/// Personalizar → Colores y textos: el color de cada división (dentro de la
/// paleta del estilo), el título y el subtítulo del plano, y los textos de los
/// sectores.
///
/// No guarda nada por su cuenta: mientras se elige avisa lo que se va probando
/// ([onProbar]), para que el plano lo muestre, y recién con GUARDAR llama a
/// [onGuardar].
class PanelColoresTextos extends StatefulWidget {
  final EstiloPlano estilo;
  final List<DivisionParaColor> divisiones;

  /// Lo guardado: los colores, el título y el subtítulo.
  final ConfigPlano config;

  /// Los sectores del salón, como están guardados.
  final List<SectorPlano> sectores;

  /// El salón tiene más de una hoja: cada sector dice en cuál está.
  final bool variasHojas;
  final bool ocupado;
  final ValueChanged<ColoresYTextos> onGuardar;

  /// Lo que se está eligiendo, si es distinto de lo guardado. Null cuando
  /// vuelve a ser lo guardado.
  final ValueChanged<ColoresYTextos?>? onProbar;

  const PanelColoresTextos({
    super.key,
    required this.estilo,
    required this.divisiones,
    required this.config,
    required this.sectores,
    required this.onGuardar,
    this.variasHojas = false,
    this.ocupado = false,
    this.onProbar,
  });

  static String rotuloDe(TipoSector tipo) => switch (tipo) {
        TipoSector.escenario => 'Escenario',
        TipoSector.pasarela => 'Pasarela',
        TipoSector.ingreso => 'Ingreso',
        TipoSector.brindis => 'Brindis',
        TipoSector.barra => 'Barra',
        TipoSector.cajas => 'Cajas',
        TipoSector.banos => 'Baños',
        TipoSector.pista => 'Pista',
        TipoSector.otro => 'Sector',
      };

  @override
  State<PanelColoresTextos> createState() => _PanelColoresTextosState();
}

class _PanelColoresTextosState extends State<PanelColoresTextos> {
  final _titulo = TextEditingController();
  final _subtitulo = TextEditingController();
  List<TextEditingController> _textos = [];
  Map<String, int> _colores = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(PanelColoresTextos old) {
    super.didUpdateWidget(old);
    // Se guardó, o bajó otra cosa de la otra PC: se muestra lo que quedó.
    if (ColoresYTextos.firmaDe(old.config, old.sectores) !=
        ColoresYTextos.firmaDe(widget.config, widget.sectores)) {
      _cargar();
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    _subtitulo.dispose();
    for (final c in _textos) {
      c.dispose();
    }
    super.dispose();
  }

  void _cargar() {
    final guardado = ColoresYTextos.de(widget.config);
    _titulo.text = guardado.titulo;
    _subtitulo.text = guardado.subtitulo;
    _colores = {...guardado.colores};
    for (final c in _textos) {
      c.dispose();
    }
    _textos = [
      for (final s in widget.sectores) TextEditingController(text: s.texto),
    ];
  }

  ColoresYTextos _leer() => ColoresYTextos(
        colores: _colores,
        titulo: _titulo.text.trim(),
        subtitulo: _subtitulo.text.trim(),
        sectores: [
          for (final (i, s) in widget.sectores.indexed)
            if (_textos[i].text.trim() != s.texto.trim())
              (sector: s, texto: _textos[i].text.trim()),
        ],
      );

  void _cambio() {
    final leido = _leer();
    widget.onProbar?.call(leido.igualA(widget.config) ? null : leido);
    setState(() {});
  }

  /// El color que lleva hoy una división: el elegido o el de su lugar.
  int? _colorDe(DivisionParaColor d) => _colores[d.clave] ?? d.lugar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final paleta = TemaPlano.de(widget.estilo).divisiones;
    final leido = _leer();
    final cambio = !leido.igualA(widget.config);
    final gris = TextStyle(color: Colors.grey.shade700, fontSize: 12.5);

    Widget titulo(String texto) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
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

    InputDecoration casillero(String? pista) => InputDecoration(
          isDense: true,
          hintText: pista,
          counterText: '',
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        );

    Widget division(DivisionParaColor d) {
      final elegido = _colorDe(d);
      // Otra división con el mismo color: se puede, pero conviene saberlo.
      final repetido = elegido == null
          ? null
          : widget.divisiones
              .where((o) =>
                  o.clave != d.clave &&
                  _colorDe(o) != null &&
                  _colorDe(o)! % paleta.length == elegido % paleta.length)
              .map((o) => o.nombre)
              .firstOrNull;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (j, color) in paleta.indexed)
                  Tooltip(
                    message: 'Color ${j + 1}',
                    child: InkWell(
                      key: Key('color_${d.clave}_$j'),
                      customBorder: const CircleBorder(),
                      onTap: widget.ocupado
                          ? null
                          : () {
                              // Volver al color de su lugar, si no había uno
                              // guardado, es dejarla como estaba: no queda
                              // como un cambio para guardar.
                              final lugar = d.lugar;
                              final vuelve =
                                  !widget.config.colores.containsKey(d.clave) &&
                                      lugar != null &&
                                      lugar % paleta.length == j;
                              _colores = {..._colores};
                              if (vuelve) {
                                _colores.remove(d.clave);
                              } else {
                                _colores[d.clave] = j;
                              }
                              _cambio();
                            },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: elegido != null &&
                                    elegido % paleta.length == j
                                ? tema.colorScheme.primary
                                : Colors.black26,
                            width: elegido != null &&
                                    elegido % paleta.length == j
                                ? 3
                                : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (repetido != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Mismo color que $repetido.',
                  key: Key('repetido_${d.clave}'),
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      key: const Key('panel_colores'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              titulo('COLOR DE CADA DIVISIÓN'),
              if (widget.divisiones.isEmpty)
                Text(
                  'Todavía no hay divisiones cargadas en los alumnos.',
                  style: gris,
                )
              else
                for (final d in widget.divisiones) division(d),
              titulo('TÍTULO DEL PLANO'),
              TextField(
                key: const Key('texto_titulo'),
                controller: _titulo,
                enabled: !widget.ocupado,
                maxLength: ColoresYTextos.largoTitulo,
                decoration: casillero('Título (por ejemplo, Egresados 2026)'),
                onChanged: (_) => _cambio(),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('texto_subtitulo'),
                controller: _subtitulo,
                enabled: !widget.ocupado,
                maxLength: ColoresYTextos.largoSubtitulo,
                decoration: casillero('Subtítulo (por ejemplo, el predio)'),
                onChanged: (_) => _cambio(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Salen en la pantalla, en el plano impreso y, en diciembre, '
                  'en el tótem.',
                  style: gris,
                ),
              ),
              if (widget.sectores.isNotEmpty) ...[
                titulo('TEXTOS DE LOS SECTORES'),
                for (final (i, s) in widget.sectores.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Text(
                            widget.variasHojas
                                ? '${PanelColoresTextos.rotuloDe(s.tipo)} '
                                    '· hoja ${s.hoja}'
                                : PanelColoresTextos.rotuloDe(s.tipo),
                            style: gris,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            key: Key('texto_sector_$i'),
                            controller: _textos[i],
                            enabled: !widget.ocupado,
                            maxLength: ColoresYTextos.largoSector,
                            decoration: casillero('Sin texto'),
                            onChanged: (_) => _cambio(),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('guardar_colores'),
                onPressed: cambio && !widget.ocupado
                    ? () => widget.onGuardar(leido)
                    : null,
                icon: const Icon(Icons.check, size: 18),
                label: Text(cambio ? 'GUARDAR' : 'GUARDADO'),
              ),
            ),
            if (cambio) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const Key('descartar_colores'),
                onPressed: widget.ocupado
                    ? null
                    : () => setState(() {
                          _cargar();
                          widget.onProbar?.call(null);
                        }),
                child: const Text('DESCARTAR'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
