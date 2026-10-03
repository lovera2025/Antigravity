import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/salon_mesas.dart';
import '../dibujo/pintor_plano.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import '../services/armar_a_medida.dart';
import '../services/cambios_de_mesa.dart';
import '../services/divisiones.dart';
import '../services/medir_salon.dart';
import '../services/plano_de_la_fiesta.dart';
import 'personalizar/panel_medidas.dart';
import 'vista_plano.dart';

/// Lo que se puede hacer con las mesas desde Personalizar. La pantalla avisa
/// qué se tocó; quien la usa calcula, pide el motivo y guarda.
class AccionesPlano {
  /// Fijar desde una mesa vacía: falta elegir para qué familia.
  final void Function(int mesa) onFijarEnMesa;

  /// Fijarle a una familia sus mesas, desde la que se tocó en el plano.
  final void Function(String alumnoId, int desdeMesa) onFijar;
  final void Function(String alumnoId) onQuitarFijadas;

  /// La fijada de una mesa cuya familia ya no está en la fiesta.
  final void Function(int mesa) onQuitarFijadaDeMesa;
  final void Function(int mesa) onDejarLibre;
  final void Function(int mesa) onVolverAUsar;
  final void Function(String alumnoId, String otroId) onCambiar;
  final void Function(String alumnoId, int desdeMesa) onMover;

  /// Guardar las medidas del playón y de las mesas. Null: no hay pestaña
  /// Medidas.
  final void Function(MedidasPlano medidas)? onGuardarMedidas;

  const AccionesPlano({
    required this.onFijarEnMesa,
    required this.onFijar,
    required this.onQuitarFijadas,
    required this.onQuitarFijadaDeMesa,
    required this.onDejarLibre,
    required this.onVolverAUsar,
    required this.onCambiar,
    required this.onMover,
    this.onGuardarMedidas,
  });
}

/// Las pestañas de Personalizar: una cosa por pestaña.
enum ModoPersonalizar {
  /// Fijar, dejar libres, cambiar y mover familias.
  mesas('Mesas'),

  /// Las medidas del playón y el lugar que pide cada mesa.
  medidas('Medidas');

  final String rotulo;
  const ModoPersonalizar(this.rotulo);
}

/// Lo que Personalizar está esperando que se toque en el plano.
enum _Espera { mover, fijar, cambiar }

/// La pantalla del plano, sin base ni Riverpod: recibe el plano ya calculado
/// ([PlanoDeLaFiesta]) y avisa lo que se toca. Así se prueba y se dibuja en
/// una muestra sin abrir la app.
///
/// - Arriba: cómo está el salón, en una frase con color.
/// - Al medio: el plano, con zoom y la regla en metros.
/// - A la derecha: el buscador, la familia o la mesa elegida, las divisiones y
///   los avisos. Cada aviso se toca y lleva a su mesa.
/// - Abajo: los botones. El que no tiene acción no se muestra.
///
/// Con [acciones], PERSONALIZAR prende el modo de tocar las mesas: mientras
/// está apagado la pantalla solo muestra, y nadie cambia una mesa sin querer.
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

  /// Se está guardando un cambio: se ve una barra y no se puede empezar otro.
  final bool ocupado;

  final VoidCallback? onEstiloYArmado;

  /// Fijar, dejar libres, cambiar y mover. Null: no hay PERSONALIZAR.
  final AccionesPlano? acciones;
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
    this.ocupado = false,
    this.onEstiloYArmado,
    this.acciones,
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

  /// La pestaña de Personalizar que está abierta. Null: Personalizar está
  /// apagado y la pantalla solo muestra.
  ModoPersonalizar? _modo;

  bool get _personalizando => _modo != null;

  /// Las medidas que se están escribiendo en la pestaña Medidas, todavía sin
  /// guardar: el plano dibuja el lugar de cada mesa con ellas.
  MedidasPlano? _medidasEnPrueba;

  /// Se eligió una acción que necesita un toque más en el plano (a dónde va la
  /// familia, o con cuál cambia).
  ({_Espera que, String alumnoId})? _esperando;

  /// Lo que se le dice si tocó algo que no sirve para lo que se espera.
  String? _pista;

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
    } else if (old.plano.armado.hoja(_hoja)?.caja !=
        _plano.armado.hoja(_hoja)?.caja) {
      // La hoja cambió de tamaño (se redibujó el hormigón): el zoom de antes
      // apuntaría a otro lugar.
      _zoom.value = Matrix4.identity();
    }
    // Lo que se estaba probando ya se guardó, o cambió lo guardado.
    if (old.plano.medidas != _plano.medidas) _medidasEnPrueba = null;
    // Una pestaña que dejó de estar (quien usa la pantalla le sacó la acción).
    final modo = _modo;
    if (modo != null && !_modos.contains(modo)) _modo = _modos.first;
    final mesa = _mesaElegida;
    if (mesa != null && !_plano.armado.existe(mesa)) _mesaElegida = null;
    // Lo que se estaba por hacer puede haber dejado de tener sentido con lo
    // que bajó de la otra PC: la familia ya no está, o ya no tiene (o ya
    // tiene) mesa.
    final espera = _esperando;
    if (espera != null) {
      final a = _alumno(espera.alumnoId);
      final conMesa = a != null && CambiosDeMesa.numerosDe(a).isNotEmpty;
      final sigue = a != null &&
          !a.esBajaTemporal &&
          (espera.que == _Espera.fijar ? !conMesa : conMesa);
      if (!sigue) {
        _esperando = null;
        _pista = null;
      }
    }
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
    final espera = _esperando;
    final acciones = widget.acciones;
    if (espera != null && acciones != null) {
      switch (espera.que) {
        // Si ahí no se puede, se dice por qué y se sigue esperando: así
        // "elegí otra" es tocar otra, sin empezar de nuevo.
        case _Espera.mover:
          final problema = CambiosDeMesa.mover(
            armado: _plano.armado,
            config: _plano.config,
            alumnos: widget.alumnos,
            alumnoId: espera.alumnoId,
            desdeMesa: numero,
          ).problema;
          if (problema != null) {
            setState(() => _pista = problema);
            return;
          }
          _dejarDeEsperar();
          acciones.onMover(espera.alumnoId, numero);
        case _Espera.fijar:
          final problema = CambiosDeMesa.fijar(
            armado: _plano.armado,
            config: _plano.config,
            alumnos: widget.alumnos,
            alumnoId: espera.alumnoId,
            desdeMesa: numero,
            // El motivo se pide después: acá solo se mira si el lugar sirve.
            motivo: '-',
            por: null,
            ahora: DateTime.now(),
          ).problema;
          if (problema != null) {
            setState(() => _pista = problema);
            return;
          }
          _dejarDeEsperar();
          acciones.onFijar(espera.alumnoId, numero);
        case _Espera.cambiar:
          final otro = info.ocupantes.isEmpty ? null : info.ocupantes.first.id;
          if (otro == null) {
            setState(() => _pista = 'En esa mesa no hay ninguna familia. '
                'Para pasar a una mesa vacía usá Mover.');
          } else if (otro == espera.alumnoId) {
            setState(() => _pista = 'Esa es su propia mesa: tocá una de otra '
                'familia.');
          } else {
            // Si con esa no se puede (tiene otra cantidad de mesas, está de
            // baja), se dice y se sigue esperando.
            final problema = CambiosDeMesa.intercambiar(
              armado: _plano.armado,
              config: _plano.config,
              alumnos: widget.alumnos,
              alumnoId: espera.alumnoId,
              otroId: otro,
            ).problema;
            if (problema != null) {
              setState(() => _pista = problema);
              return;
            }
            _dejarDeEsperar();
            acciones.onCambiar(espera.alumnoId, otro);
          }
      }
      return;
    }
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
    final espera = _esperando;
    final acciones = widget.acciones;
    if (espera != null && acciones != null) {
      if (espera.que != _Espera.cambiar) {
        // Buscando a dónde mudar (o fijar) una familia: el buscador solo lleva
        // la vista a la otra. Lo elegido sigue siendo la que se muda, y el
        // lugar se toca en el plano.
        setState(_busqueda.clear);
        final mesa = _ocupante(id)?.principal;
        if (mesa != null) _irA(mesa, elegir: false);
        return;
      }
      // Buscando con quién cambia: la familia elegida en el buscador es esa.
      if (id == espera.alumnoId) {
        setState(() => _pista = 'Es la misma familia: elegí otra.');
        return;
      }
      final problema = CambiosDeMesa.intercambiar(
        armado: _plano.armado,
        config: _plano.config,
        alumnos: widget.alumnos,
        alumnoId: espera.alumnoId,
        otroId: id,
      ).problema;
      if (problema != null) {
        setState(() {
          _pista = problema;
          _busqueda.clear();
        });
        return;
      }
      setState(() {
        _esperando = null;
        _pista = null;
        _busqueda.clear();
      });
      acciones.onCambiar(espera.alumnoId, id);
      return;
    }
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
        _esperando = null;
        _pista = null;
      });

  void _esperar(_Espera que, String alumnoId) => setState(() {
        _esperando = (que: que, alumnoId: alumnoId);
        _pista = null;
      });

  void _dejarDeEsperar() => setState(() {
        _esperando = null;
        _pista = null;
      });

  /// Las pestañas que hay: la de Mesas siempre, y cada una de las otras si
  /// quien usa la pantalla le dio con qué guardar.
  List<ModoPersonalizar> get _modos => [
        ModoPersonalizar.mesas,
        if (widget.acciones?.onGuardarMedidas != null) ModoPersonalizar.medidas,
      ];

  /// Lo que quedaría sin guardar si se sale de la pestaña, dicho en palabras.
  /// Null: no hay nada pendiente.
  String? get _sinGuardar => switch (_modo) {
        ModoPersonalizar.medidas when _medidasEnPrueba != null =>
          'Hay medidas sin guardar: tocá GUARDAR MEDIDAS o DESCARTAR.',
        _ => null,
      };

  void _cambiarModo(ModoPersonalizar modo) {
    if (modo == _modo || widget.ocupado) return;
    final pendiente = _sinGuardar;
    setState(() {
      if (pendiente != null) {
        _pista = pendiente;
        return;
      }
      _modo = modo;
      _esperando = null;
      _pista = null;
      _medidasEnPrueba = null;
    });
  }

  void _salirDePersonalizar() {
    final pendiente = _sinGuardar;
    setState(() {
      if (pendiente != null) {
        _pista = pendiente;
        return;
      }
      _modo = null;
      _esperando = null;
      _pista = null;
      _medidasEnPrueba = null;
    });
  }

  bool get _hayFamiliasConMesa => widget.alumnos
      .any((a) => !a.esBajaTemporal && SalonMesas.tieneNumeros(a));

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
        if (widget.ocupado)
          const Padding(
            key: Key('guardando'),
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Guardando…'),
              ],
            ),
          ),
        if (_personalizando) _franjaPersonalizar(context),
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

  /// Qué se está haciendo en Personalizar y qué hay que tocar ahora.
  Widget _franjaPersonalizar(BuildContext context) {
    final tema = Theme.of(context);
    final modos = _modos;
    final espera = _esperando;
    final alumno = espera == null ? null : _alumno(espera.alumnoId);
    final String texto;
    if (_modo == ModoPersonalizar.medidas) {
      texto = 'Los lados del playón como los da la cinta, y cuánto lugar '
          'pide cada mesa.';
    } else if (espera == null || alumno == null) {
      texto = 'Personalizar las mesas: tocá una mesa o buscá una familia.';
    } else {
      final quien = CambiosDeMesa.apellido(alumno);
      texto = switch (espera.que) {
        _Espera.mover => () {
            final n = CambiosDeMesa.numerosDe(alumno).length;
            return n == 1
                ? 'Tocá la mesa libre a donde va $quien.'
                : 'Tocá la primera mesa para $quien: va a esa y a las que le '
                    'siguen ($n seguidas y libres).';
          }(),
        _Espera.fijar => () {
            final n = SalonMesas.mesas(alumno);
            return 'Tocá la mesa donde empieza $quien: se le '
                '${n == 1 ? 'fija 1 mesa' : 'fijan $n mesas seguidas'}.';
          }(),
        _Espera.cambiar =>
          'Tocá una mesa de la familia con la que cambia $quien, o buscala.',
      };
    }
    return Container(
      key: const Key('franja_personalizar'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: tema.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tema.colorScheme.primary),
      ),
      child: Row(
        children: [
          if (modos.length > 1) ...[
            SegmentedButton<ModoPersonalizar>(
              key: const Key('pestanas_personalizar'),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final m in modos)
                  ButtonSegment(
                    value: m,
                    label: Text(m.rotulo, key: Key('pestana_${m.name}')),
                  ),
              ],
              selected: {_modo!},
              onSelectionChanged: (s) => _cambiarModo(s.first),
            ),
            const SizedBox(width: 12),
          ] else ...[
            Icon(Icons.tune, size: 18, color: tema.colorScheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto,
                  key: const Key('texto_personalizar'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_pista != null)
                  Text(
                    _pista!,
                    key: const Key('pista'),
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
              ],
            ),
          ),
          if (espera != null)
            TextButton(
              key: const Key('cancelar_espera'),
              onPressed: () => setState(() {
                _esperando = null;
                _pista = null;
              }),
              child: const Text('CANCELAR'),
            )
          else
            TextButton(
              key: const Key('salir_personalizar'),
              onPressed: _salirDePersonalizar,
              child: const Text('LISTO'),
            ),
        ],
      ),
    );
  }

  /// Lo que se puede hacer con lo elegido, mientras Personalizar está
  /// prendido.
  List<Widget> _accionesDeLoElegido() {
    final acciones = widget.acciones;
    if (_modo != ModoPersonalizar.mesas || acciones == null) return const [];
    Widget boton(String clave, String texto, IconData icono, VoidCallback f) =>
        OutlinedButton.icon(
          key: Key(clave),
          onPressed: widget.ocupado ? null : f,
          icon: Icon(icono, size: 16),
          label: Text(texto),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        );
    final botones = <Widget>[];
    final alumno = _alumno(_alumnoElegido);
    final mesa = _mesaElegida;
    if (alumno != null) {
      if (alumno.esBajaTemporal) return const [];
      final conMesa = CambiosDeMesa.numerosDe(alumno).isNotEmpty;
      final fijadas =
          _plano.config.fijadasPorAlumno[alumno.id] ?? const <int>[];
      if (conMesa) {
        botones.addAll([
          boton('accion_cambiar', 'Cambiar con otra familia', Icons.swap_horiz,
              () => _esperar(_Espera.cambiar, alumno.id)),
          boton('accion_mover', 'Mover a otras mesas', Icons.open_with,
              () => _esperar(_Espera.mover, alumno.id)),
        ]);
      } else {
        botones.add(boton(
          'accion_fijar',
          fijadas.isEmpty ? 'Fijarle mesas' : 'Fijarle otras mesas',
          Icons.lock_outline,
          () => _esperar(_Espera.fijar, alumno.id),
        ));
        if (fijadas.isNotEmpty) {
          botones.add(boton('accion_quitar_fijada', 'Quitar sus mesas fijadas',
              Icons.lock_open, () => acciones.onQuitarFijadas(alumno.id)));
        }
      }
    } else if (mesa != null) {
      final info = _plano.estado.info(mesa);
      final para = info.fijadaPara;
      if (info.libre) {
        botones.add(boton('accion_volver_a_usar', 'Volver a usarla',
            Icons.check_circle_outline, () => acciones.onVolverAUsar(mesa)));
      } else if (para != null) {
        botones.add(boton(
          'accion_quitar_fijada',
          'Quitarle las fijadas a ${para.apellido}',
          Icons.lock_open,
          () => acciones.onQuitarFijadas(para.id),
        ));
      } else if (_plano.config.fijadas.containsKey(mesa)) {
        // Fijada para una familia que ya no está: no se dibuja, pero existe.
        botones.add(boton('accion_quitar_fijada', 'Quitar la fijada',
            Icons.lock_open, () => acciones.onQuitarFijadaDeMesa(mesa)));
      } else if (info.estado == EstadoMesa.vacia) {
        botones.addAll([
          boton('accion_fijar_en_mesa', 'Fijar para una familia',
              Icons.lock_outline, () => acciones.onFijarEnMesa(mesa)),
          boton('accion_dejar_libre', 'Dejar libre', Icons.block,
              () => acciones.onDejarLibre(mesa)),
        ]);
      }
    }
    if (botones.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: botones),
    ];
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
                        // En Medidas no se elige nada: el plano solo muestra
                        // cómo queda el lugar de cada mesa.
                        onTapMesa: _modo == ModoPersonalizar.medidas
                            ? null
                            : _elegirMesa,
                        mostrarMedidas: true,
                        lugares: _modo == ModoPersonalizar.medidas
                            ? _medidasEnPrueba ?? _plano.medidas
                            : widget.mostrarLugares
                                ? _plano.medidas
                                : null,
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

  /// Lo que conviene hacer después de cambiar las medidas, si el salón está
  /// armado a medida y ya no coincide con ellas.
  String? get _avisoMedidas {
    final lugar = ArmarAMedida.lugarDe(_plano.armado);
    if (lugar == null) return null;
    final guardado = _plano.medidas.lugarMesaM;
    final afuera = _plano.sinLugar.fueraDelHormigon.length;
    final partes = [
      if ((lugar - guardado).abs() > 0.005)
        'El salón está armado a ${MedirSalon.metros(lugar, decimales: 2)} '
            'entre mesas y la medida guardada es '
            '${MedirSalon.metros(guardado, decimales: 2)}.',
      if (afuera > 0)
        afuera == 1
            ? 'Hay 1 mesa que no entra en el hormigón.'
            : 'Hay $afuera mesas que no entran en el hormigón.',
    ];
    if (partes.isEmpty) return null;
    partes.add(_hayFamiliasConMesa
        ? 'Ya hay familias con mesa: el salón no se arma de nuevo, se '
            'acomoda a mano.'
        : 'Para armarlo de nuevo con estas medidas: ESTILO Y ARMADO → '
            'A medida del playón.');
    return partes.join(' ');
  }

  Widget _panelMedidas() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
        child: PanelMedidas(
          medidas: _plano.medidas,
          mesasNecesarias: _plano.mesasNecesarias,
          ocupado: widget.ocupado,
          onProbar: (m) => setState(() {
            _medidasEnPrueba = m;
            if (m == null) _pista = null;
          }),
          onGuardar: (m) {
            setState(() => _pista = null);
            widget.acciones?.onGuardarMedidas?.call(m);
          },
          aviso: _avisoMedidas,
          textoAccionAviso: 'ARMAR DE NUEVO',
          onAccionAviso: _hayFamiliasConMesa ? null : widget.onEstiloYArmado,
        ),
      );

  Widget _panel(BuildContext context) {
    if (_modo == ModoPersonalizar.medidas) return _panelMedidas();
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
            // Mientras se espera un toque en el plano, el buscador solo lleva
            // la vista: el lugar se elige tocando la mesa.
            _irA(numero, elegir: _esperando == null);
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
        if (alumno.esBajaTemporal)
          Text(
            'Está de baja y conserva su mesa: el sorteo no se la da a nadie. '
            'Si no vuelve, sacásela en Editar alumno.',
            style: TextStyle(color: Colors.orange.shade800),
          ),
        if (ocupante == null) ...[
          Text(
            'Todavía sin mesa. Le '
            '${SalonMesas.mesas(alumno) == 1 ? 'corresponde 1' : 'corresponden ${SalonMesas.mesas(alumno)}'}.',
          ),
          if (_plano.config.fijadasPorAlumno[alumno.id] case final fijadas?)
            Text(
              'Tiene fijada${fijadas.length == 1 ? '' : 's'} '
              '${CambiosDeMesa.textoMesas(fijadas)}.',
              key: const Key('fijadas_de_la_familia'),
            ),
        ] else
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
            ..._accionesDeLoElegido(),
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
          onTap: a.mesa == null
              ? null
              : () => _irA(a.mesa!, elegir: _esperando == null),
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
          // Mientras se guarda quedan a la vista, apagados: si desaparecieran,
          // los demás se correrían de lugar en cada cambio.
          child: principal
              ? FilledButton.icon(
                  key: key,
                  onPressed: widget.ocupado ? null : accion,
                  icon: Icon(icono, size: 18),
                  label: Text(texto),
                )
              : OutlinedButton.icon(
                  key: key,
                  onPressed: widget.ocupado ? null : accion,
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
          if (widget.acciones != null)
            boton(
              const Key('personalizar'),
              _personalizando ? 'SALIR DE PERSONALIZAR' : 'PERSONALIZAR',
              Icons.tune,
              () => _personalizando
                  ? _salirDePersonalizar()
                  : setState(() => _modo = ModoPersonalizar.mesas),
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
