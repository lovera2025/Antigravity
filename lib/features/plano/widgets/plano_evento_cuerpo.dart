import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/salon_mesas.dart';
import '../dibujo/pintor_plano.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/estado_plano.dart';
import '../services/divisiones.dart';
import '../services/medir_salon.dart';
import '../services/plano_de_la_fiesta.dart';
import 'vista_plano.dart';

/// La pantalla del plano, sin base ni Riverpod: recibe el plano ya calculado
/// ([PlanoDeLaFiesta]) y avisa lo que se toca. Así se prueba y se dibuja en
/// una muestra sin abrir la app.
///
/// - Arriba: cómo está el salón, en una frase con color.
/// - Al medio: el plano, con zoom y la regla en metros.
/// - A la derecha: el buscador, la familia o la mesa elegida, las divisiones y
///   los avisos. Cada aviso se toca y lleva a su mesa.
/// - Abajo: los botones. El que no tiene acción no se muestra.
class PlanoEventoCuerpo extends StatefulWidget {
  final PlanoDeLaFiesta plano;
  final EstiloPlano estilo;

  /// Las familias de la fiesta, para el buscador y la tarjeta.
  final List<ContratoAlumno> alumnos;

  /// Dónde eligió cada familia sus sillas extra: la tarjeta dice lo mismo que
  /// la planilla del sorteo.
  final Map<String, SillasReparto> repartos;

  /// La familia que se abre resaltada (se llegó desde su renglón en la
  /// grilla).
  final String? resaltarAlumnoId;

  /// Dibujar el círculo de lugar de cada mesa (para acomodar el salón).
  final bool mostrarLugares;

  final VoidCallback? onEstiloYArmado;
  final VoidCallback? onPersonalizar;
  final VoidCallback? onImprimir;
  final VoidCallback? onHistorial;

  const PlanoEventoCuerpo({
    super.key,
    required this.plano,
    required this.estilo,
    required this.alumnos,
    this.repartos = const {},
    this.resaltarAlumnoId,
    this.mostrarLugares = false,
    this.onEstiloYArmado,
    this.onPersonalizar,
    this.onImprimir,
    this.onHistorial,
  });

  @override
  State<PlanoEventoCuerpo> createState() => _PlanoEventoCuerpoState();
}

class _PlanoEventoCuerpoState extends State<PlanoEventoCuerpo> {
  static const double _zoomMaximo = 6;

  final _zoom = TransformationController();
  final _busqueda = TextEditingController();
  late String _hoja;
  String? _alumnoElegido;
  int? _mesaElegida;
  Size _tamPlano = Size.zero;

  PlanoDeLaFiesta get _plano => widget.plano;

  @override
  void initState() {
    super.initState();
    _hoja = _plano.armado.hojas.first.id;
    final id = widget.resaltarAlumnoId;
    if (id != null) {
      _alumnoElegido = id;
      final mesa = _ocupante(id)?.principal;
      final hoja = mesa == null ? null : _plano.armado.mesa(mesa)?.hoja;
      if (hoja != null) _hoja = hoja;
    }
  }

  @override
  void didUpdateWidget(PlanoEventoCuerpo old) {
    super.didUpdateWidget(old);
    // Si cambió el armado (se eligió otro), la hoja o la mesa elegidas pueden
    // no existir más.
    if (_plano.armado.hoja(_hoja) == null) {
      _hoja = _plano.armado.hojas.first.id;
      _zoom.value = Matrix4.identity();
    }
    final mesa = _mesaElegida;
    if (mesa != null && !_plano.armado.existe(mesa)) _mesaElegida = null;
  }

  @override
  void dispose() {
    _zoom.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  // ── Qué está elegido ────────────────────────────────────────────────────

  ContratoAlumno? _alumno(String? id) {
    if (id == null) return null;
    for (final a in widget.alumnos) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// La familia como ocupante del plano (con sus mesas), o null si todavía no
  /// tiene mesa.
  OcupantePlano? _ocupante(String id) {
    for (final i in _plano.estado.mesas) {
      for (final o in i.ocupantes) {
        if (o.id == id) return o;
      }
    }
    return null;
  }

  Set<int> get _resaltadas {
    final id = _alumnoElegido;
    if (id != null) return _ocupante(id)?.numeros.toSet() ?? const {};
    return const {};
  }

  void _elegirMesa(int numero) {
    final info = _plano.estado.info(numero);
    setState(() {
      if (info.ocupantes.isNotEmpty) {
        _alumnoElegido = info.ocupantes.first.id;
        _mesaElegida = null;
      } else {
        _alumnoElegido = null;
        _mesaElegida = numero;
      }
    });
  }

  void _elegirFamilia(String id) {
    setState(() {
      _alumnoElegido = id;
      _mesaElegida = null;
      _busqueda.clear();
    });
    final mesa = _ocupante(id)?.principal;
    if (mesa != null) _irA(mesa, elegir: false);
  }

  void _soltar() => setState(() {
        _alumnoElegido = null;
        _mesaElegida = null;
      });

  // ── Zoom ────────────────────────────────────────────────────────────────

  double get _escalaZoom => _zoom.value.getMaxScaleOnAxis();

  void _zoomear(double factor) {
    final actual = _escalaZoom;
    final nueva = (actual * factor).clamp(1.0, _zoomMaximo);
    if (nueva <= 1.001) {
      _zoom.value = Matrix4.identity();
      return;
    }
    final f = nueva / actual;
    final c = _tamPlano.center(Offset.zero);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(_zoom.value);
  }

  /// Lleva la vista a una mesa: cambia de hoja si hace falta y la deja al
  /// medio, con zoom como para leer el apellido.
  void _irA(int mesa, {bool elegir = true}) {
    final m = _plano.armado.mesa(mesa);
    if (m == null) return;
    final hoja = _plano.armado.hoja(m.hoja);
    if (hoja == null) return;
    setState(() => _hoja = m.hoja);
    if (elegir) _elegirMesa(mesa);
    if (_tamPlano.isEmpty) return;
    final punto = EncuadrePlano.de(hoja.caja, _tamPlano)
        .aPantalla(Offset(m.x, m.y));
    const escala = 2.4;
    final c = _tamPlano.center(Offset.zero);
    // Sin pasarse de los bordes: el plano no se despega de las orillas.
    final dx = (c.dx - punto.dx * escala)
        .clamp(_tamPlano.width * (1 - escala), 0.0);
    final dy = (c.dy - punto.dy * escala)
        .clamp(_tamPlano.height * (1 - escala), 0.0);
    _zoom.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(escala, escala, 1, 1);
  }

  // ── Dibujo ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _encabezado(context),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _areaPlano(context)),
              SizedBox(width: 340, child: _panel(context)),
            ],
          ),
        ),
        _botones(context),
      ],
    );
  }

  Widget _encabezado(BuildContext context) {
    final color = switch (_plano.semaforo) {
      SemaforoPlano.entran => Colors.green.shade700,
      SemaforoPlano.revisar => Colors.orange.shade800,
      SemaforoPlano.faltan => Colors.red.shade700,
    };
    final aproximado = _plano.medidas.playon.aproximado;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Container(
            key: const Key('titular'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _plano.titular,
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _plano.detalle,
              style: TextStyle(color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (aproximado)
            Tooltip(
              message: 'Las medidas del playón se tomaron de la foto '
                  'satelital. Corregilas con cinta en Personalizar.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.straighten, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Medidas aproximadas',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// El plano y, debajo, su barra: la regla, las hojas y el zoom. Van afuera
  /// del dibujo para no tapar ninguna mesa.
  Widget _areaPlano(BuildContext context) {
    final armado = _plano.armado;
    final tema = TemaPlano.de(widget.estilo);
    const altoBarra = 48.0;
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _tamPlano = Size(
            constraints.maxWidth,
            (constraints.maxHeight - altoBarra).clamp(0.0, double.infinity),
          );
          final hoja = armado.hoja(_hoja)!;
          final base = EncuadrePlano.de(hoja.caja, _tamPlano).escala;
          return Column(
            children: [
              SizedBox.fromSize(
                size: _tamPlano,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: tema.fondo,
                    child: InteractiveViewer(
                      transformationController: _zoom,
                      minScale: 1,
                      maxScale: _zoomMaximo,
                      child: VistaPlano(
                        armado: armado,
                        hoja: _hoja,
                        tema: tema,
                        estado: _plano.estado,
                        resaltadas: _resaltadas,
                        seleccionada: _mesaElegida,
                        onTapMesa: _elegirMesa,
                        mostrarMedidas: true,
                        lugares: widget.mostrarLugares ? _plano.medidas : null,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: altoBarra,
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _zoom,
                      builder: (context, _) => _Regla(
                        pxPorUnidad: base * _escalaZoom,
                        metrosPorUnidad: armado.metrosPorUnidad,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (armado.hojas.length > 1)
                      SegmentedButton<String>(
                        key: const Key('hojas'),
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: [
                          for (final h in armado.hojas)
                            ButtonSegment(
                              value: h.id,
                              label: Text(
                                h.titulo.isEmpty ? 'Hoja ${h.id}' : h.titulo,
                              ),
                            ),
                        ],
                        selected: {_hoja},
                        onSelectionChanged: (s) => setState(() {
                          _hoja = s.first;
                          _zoom.value = Matrix4.identity();
                        }),
                      ),
                    const Spacer(),
                    IconButton(
                      key: const Key('alejar'),
                      tooltip: 'Alejar',
                      onPressed: () => _zoomear(1 / 1.5),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      key: const Key('acercar'),
                      tooltip: 'Acercar',
                      onPressed: () => _zoomear(1.5),
                      icon: const Icon(Icons.add),
                    ),
                    TextButton(
                      key: const Key('ajustar'),
                      onPressed: () => _zoom.value = Matrix4.identity(),
                      child: const Text('AJUSTAR'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Panel ───────────────────────────────────────────────────────────────

  Widget _panel(BuildContext context) {
    final consulta = _busqueda.text.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('buscar'),
            controller: _busqueda,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar familia o mesa',
              border: const OutlineInputBorder(),
              suffixIcon: consulta.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_busqueda.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: consulta.isNotEmpty
                  ? _resultados(consulta)
                  : [
                      ..._elegido(context),
                      ..._leyenda(context),
                      ..._avisos(context),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _resultados(String consulta) {
    final numero = int.tryParse(consulta);
    final familias = [
      for (final a in widget.alumnos)
        if (!a.esBajaTemporal &&
            coincideTextoBusqueda(
              [a.nombreAlumno, a.cursoDivision, a.numeroMesa],
              consulta,
            ))
          a,
    ];
    return [
      if (numero != null && _plano.armado.existe(numero))
        ListTile(
          key: Key('resultado_mesa_$numero'),
          dense: true,
          leading: const Icon(Icons.table_restaurant_outlined),
          title: Text('Mesa $numero'),
          subtitle: Text(_estadoDeMesa(numero)),
          onTap: () {
            setState(_busqueda.clear);
            _irA(numero);
          },
        ),
      for (final a in familias.take(30))
        ListTile(
          key: Key('resultado_${a.id}'),
          dense: true,
          leading: const Icon(Icons.groups_outlined),
          title: Text(a.nombreAlumno),
          subtitle: Text([
            if ((a.cursoDivision ?? '').trim().isNotEmpty) a.cursoDivision!.trim(),
            SalonMesas.tieneNumeros(a)
                ? 'Mesa ${SalonMesas.textoMesas(a)}'
                : 'Todavía sin mesa',
          ].join(' · ')),
          onTap: () => _elegirFamilia(a.id),
        ),
      if (familias.isEmpty && (numero == null || !_plano.armado.existe(numero)))
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No hay ninguna familia ni mesa con "$consulta".',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
    ];
  }

  String _estadoDeMesa(int numero) {
    final info = _plano.estado.info(numero);
    final pasto = _plano.armado.pasto.contains(numero) ? ' · en el pasto' : '';
    final base = switch (info.estado) {
      EstadoMesa.vacia => 'Vacía',
      EstadoMesa.ocupada => info.ocupante?.nombre ?? 'Ocupada',
      EstadoMesa.libre => 'Se dejó libre: el sorteo no la da',
      EstadoMesa.fijada => 'Fijada para ${info.fijadaPara?.nombre ?? ''}',
      EstadoMesa.conflicto => 'Hay que revisarla',
    };
    return '$base$pasto';
  }

  List<Widget> _elegido(BuildContext context) {
    final mesa = _mesaElegida;
    final alumno = _alumno(_alumnoElegido);
    if (mesa == null && alumno == null) return const [];
    final tema = Theme.of(context);
    final List<Widget> renglones;
    final String titulo;
    if (alumno != null) {
      titulo = alumno.nombreAlumno;
      final ocupante = _ocupante(alumno.id);
      final division = (alumno.cursoDivision ?? '').trim();
      final personas = SalonMesas.ocupacion(alumno).personas;
      renglones = [
        Text([
          division.isEmpty ? Divisiones.sinDivision : division,
          personas == 1 ? '1 persona' : '$personas personas',
        ].join(' · ')),
        const SizedBox(height: 6),
        if (ocupante == null)
          Text(
            'Todavía sin mesa. Le '
            '${SalonMesas.mesas(alumno) == 1 ? 'corresponde 1' : 'corresponden ${SalonMesas.mesas(alumno)}'}.',
          )
        else
          for (final n in ocupante.numeros)
            Text(
              'Mesa $n: '
              '${SalonMesas.sillasPorMesa + (ocupante.sillasExtraPorMesa[n] ?? 0)} sillas'
              '${_plano.armado.existe(n) ? '' : ' (no está en este armado)'}',
              key: Key('sillas_mesa_$n'),
            ),
        // Lo mismo que dice la planilla del sorteo de su mesa principal.
        if (ocupante != null)
          if (PlanillaSorteo.fila(
                alumno,
                repartoElegido: widget.repartos[alumno.id],
              ).ocupacionPrincipal
              case final ocupacion?) ...[
            const SizedBox(height: 4),
            Text(
              'En la principal: $ocupacion',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
      ];
    } else {
      titulo = 'Mesa $mesa';
      final info = _plano.estado.info(mesa!);
      final motivo = info.libre
          ? _plano.config.libres[mesa]?.motivo
          : _plano.config.fijadas[mesa]?.motivo;
      renglones = [
        Text(_estadoDeMesa(mesa)),
        if (motivo != null && motivo.trim().isNotEmpty)
          Text('Motivo: ${motivo.trim()}'),
      ];
    }
    return [
      Container(
        key: const Key('elegido'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        decoration: BoxDecoration(
          border: Border.all(color: tema.colorScheme.primary, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  key: const Key('soltar'),
                  tooltip: 'Quitar la selección',
                  visualDensity: VisualDensity.compact,
                  onPressed: _soltar,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            ...renglones,
          ],
        ),
      ),
    ];
  }

  List<Widget> _leyenda(BuildContext context) {
    final estado = _plano.estado;
    if (estado.divisiones.isEmpty && !estado.haySinDivision) return const [];
    final tema = TemaPlano.de(widget.estilo);
    final mesasDe = <int?, int>{};
    for (final i in estado.mesas) {
      if (i.ocupantes.isEmpty) continue;
      mesasDe[i.division] = (mesasDe[i.division] ?? 0) + 1;
    }
    Widget renglon(Color color, String nombre, int mesas) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(nombre)),
              Text(
                mesas == 1 ? '1 mesa' : '$mesas mesas',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        );
    return [
      const _TituloSeccion('Divisiones'),
      for (final (i, clave) in estado.divisiones.indexed)
        renglon(
          tema.colorDivision(i),
          estado.nombresDivision[clave] ?? clave,
          mesasDe[i] ?? 0,
        ),
      if (estado.haySinDivision)
        renglon(tema.mesaBorde, Divisiones.sinDivision, mesasDe[null] ?? 0),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _avisos(BuildContext context) {
    final avisos = _plano.avisos;
    if (avisos.isEmpty) return const [];
    return [
      _TituloSeccion(avisos.length == 1 ? 'Aviso' : 'Avisos (${avisos.length})'),
      for (final (i, a) in avisos.indexed)
        InkWell(
          key: Key('aviso_$i'),
          borderRadius: BorderRadius.circular(8),
          onTap: a.mesa == null ? null : () => _irA(a.mesa!),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  a.grave ? Icons.error_outline : Icons.info_outline,
                  size: 18,
                  color: a.grave ? Colors.red.shade700 : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(a.texto)),
                if (a.mesa != null)
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
    ];
  }

  // ── Botones ─────────────────────────────────────────────────────────────

  Widget _botones(BuildContext context) {
    Widget boton(
      Key key,
      String texto,
      IconData icono,
      VoidCallback accion, {
      bool principal = false,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: principal
              ? FilledButton.icon(
                  key: key,
                  onPressed: accion,
                  icon: Icon(icono, size: 18),
                  label: Text(texto),
                )
              : OutlinedButton.icon(
                  key: key,
                  onPressed: accion,
                  icon: Icon(icono, size: 18),
                  label: Text(texto),
                ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          if (widget.onEstiloYArmado != null)
            boton(
              const Key('estilo_y_armado'),
              'ESTILO Y ARMADO',
              Icons.dashboard_customize_outlined,
              widget.onEstiloYArmado!,
              principal: true,
            ),
          if (widget.onPersonalizar != null)
            boton(
              const Key('personalizar'),
              'PERSONALIZAR',
              Icons.tune,
              widget.onPersonalizar!,
            ),
          if (widget.onImprimir != null)
            boton(
              const Key('imprimir'),
              'IMPRIMIR',
              Icons.print_rounded,
              widget.onImprimir!,
            ),
          if (widget.onHistorial != null)
            boton(
              const Key('historial'),
              'HISTORIAL',
              Icons.history,
              widget.onHistorial!,
            ),
        ],
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;

  const _TituloSeccion(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          texto.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.grey.shade600,
          ),
        ),
      );
}

/// La regla en metros, debajo del plano: sigue al zoom.
class _Regla extends StatelessWidget {
  final double pxPorUnidad;
  final double metrosPorUnidad;
  final Color color;

  const _Regla({
    required this.pxPorUnidad,
    required this.metrosPorUnidad,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final r = MedirSalon.reglaPara(pxPorUnidad, metrosPorUnidad);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: r.px,
            height: 7,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color, width: 2),
                right: BorderSide(color: color, width: 2),
                bottom: BorderSide(color: color, width: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MedirSalon.metros(r.metros),
            key: const Key('regla'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
