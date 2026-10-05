import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../../models/sillas_reparto.dart';
import '../../common/utils/solo_jefe.dart';
import '../../common/utils/texto_busqueda.dart';
import '../../eventos/services/planilla_sorteo.dart';
import '../../eventos/services/salon_mesas.dart';
import '../dibujo/pintor_acomodo.dart';
import '../dibujo/pintor_plano.dart';
import '../estilos/estilo_plano.dart';
import '../modelo/armado_salon.dart';
import '../modelo/estado_plano.dart';
import '../modelo/medidas_salon.dart';
import '../services/armar_a_medida.dart';
import '../services/cambios_de_mesa.dart';
import '../services/colores_y_textos.dart';
import '../services/divisiones.dart';
import '../services/editar_armado.dart';
import '../services/medir_salon.dart';
import '../services/plano_de_la_fiesta.dart';
import '../services/sesion_acomodo.dart';
import 'personalizar/panel_acomodar.dart';
import 'personalizar/panel_colores_textos.dart';
import 'personalizar/panel_medidas.dart';
import 'vista_plano.dart';

/// Por dónde quien muestra el plano le pregunta, antes de salir de la
/// pantalla, si en Personalizar quedó algo sin guardar.
class PendienteDelPlano {
  String? Function()? _leer;

  /// Lo que se perdería al salir, dicho en palabras. Null: nada.
  String? get sinGuardar => _leer?.call();
}

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

  /// Guardar las medidas del playón y de las mesas: [vistas] son las que
  /// estaban guardadas cuando se corrigieron. Null: no hay pestaña Medidas.
  final void Function(MedidasPlano medidas, MedidasPlano vistas)?
      onGuardarMedidas;

  /// Guardar los colores de las divisiones, el título y los textos de los
  /// sectores: [visto] es lo que estaba guardado cuando se eligieron. Null:
  /// no hay pestaña Colores y textos.
  final void Function(ColoresYTextos cambio, ConfigPlano visto)?
      onGuardarColoresYTextos;

  /// Guardar el salón acomodado a mano: [base] es el que estaba guardado al
  /// empezar, [nuevo] el que quedó y [enUso] las mesas que tenían familia o
  /// estaban fijadas al empezar. Null: no hay pestaña Acomodar.
  final void Function(
    ArmadoSalon base,
    ArmadoSalon nuevo,
    Map<int, String> enUso,
  )? onGuardarArmado;

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
    this.onGuardarColoresYTextos,
    this.onGuardarArmado,
  });
}

/// Las pestañas de Personalizar: una cosa por pestaña.
enum ModoPersonalizar {
  /// Fijar, dejar libres, cambiar y mover familias.
  mesas('Mesas'),

  /// Correr, agregar y sacar mesas y sectores, y separar o juntar.
  acomodar('Acomodar'),

  /// Las medidas del playón y el lugar que pide cada mesa.
  medidas('Medidas'),

  /// El color de cada división, el título y los textos de los sectores.
  colores('Colores y textos');

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

  /// La sesión no está en modo jefe: ESTILO Y ARMADO y PERSONALIZAR llegan en
  /// null, y en vez de desaparecer quedan a la vista, apagados, con el motivo
  /// escrito ([kSoloEnModoJefe]).
  final bool soloJefe;

  /// Para que la pantalla sepa, al querer salir, si hay algo sin guardar.
  final PendienteDelPlano? pendiente;

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
    this.soloJefe = false,
    this.pendiente,
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

  /// Lo que se está eligiendo en Colores y textos, todavía sin guardar: el
  /// plano se dibuja con eso.
  ColoresYTextos? _coloresEnPrueba;

  /// El salón que se está acomodando, mientras la pestaña Acomodar está
  /// abierta. Nada de esto se guarda hasta tocar GUARDAR EL SALÓN.
  SesionAcomodo? _acomodo;
  int? _mesaAcomodo;
  int? _sectorAcomodo;

  /// Dónde se agarró lo que se arrastra, respecto de su lugar: así no pega un
  /// salto al empezar a moverlo.
  Offset _desfase = Offset.zero;

  /// Dónde se apretó, y si el puntero ya se alejó lo suficiente como para
  /// que sea un arrastre y no un clic.
  Offset _apretadoEn = Offset.zero;
  bool _seMovio = false;
  static const double _recorridoMinimoPx = 6;
  String _alcance = 'hoja';
  double? _pasoSeparar;
  String? _mensajeAcomodo;
  bool _confirmarDescartar = false;

  /// En Medidas hay un casillero que no sirve (vacío, con letras, fuera de
  /// rango): cuenta como algo sin guardar.
  bool _medidasMalEscritas = false;

  /// Se eligió una acción que necesita un toque más en el plano (a dónde va la
  /// familia, o con cuál cambia).
  ({_Espera que, String alumnoId})? _esperando;

  /// Lo que se le dice si tocó algo que no sirve para lo que se espera.
  String? _pista;

  PlanoDeLaFiesta get _plano => widget.plano;

  String? _leerPendiente() => _sinGuardar;

  @override
  void initState() {
    super.initState();
    widget.pendiente?._leer = _leerPendiente;
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
    if (!identical(old.pendiente, widget.pendiente)) {
      if (old.pendiente?._leer == _leerPendiente) {
        old.pendiente!._leer = null;
      }
      widget.pendiente?._leer = _leerPendiente;
    }
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
    // Lo que se estaba probando ya se guardó, o cambió lo guardado. Si no fue
    // por guardar acá (bajó de la otra PC), lo escrito se pierde: se dice.
    final guardando = widget.ocupado || old.ocupado;
    if (old.plano.medidas != _plano.medidas) {
      if (_medidasEnPrueba != null && !guardando) {
        _pista = 'La otra PC cambió las medidas mientras las corregías: se '
            'muestran las que guardó.';
      }
      _medidasEnPrueba = null;
      _medidasMalEscritas = false;
    }
    if (ColoresYTextos.firmaDe(old.plano.config, old.plano.armado.sectores) !=
        ColoresYTextos.firmaDe(_plano.config, _plano.armado.sectores)) {
      if (_coloresEnPrueba != null && !guardando) {
        _pista = 'La otra PC cambió los colores o los textos mientras los '
            'elegías: se muestran los que guardó.';
      }
      _coloresEnPrueba = null;
    }
    // Una pestaña que dejó de estar (quien usa la pantalla le sacó la acción).
    final modo = _modo;
    if (modo != null && !_modos.contains(modo)) {
      _modo = _modos.first;
      _limpiarAcomodo();
    }
    // El salón guardado cambió mientras se acomodaba.
    final sesion = _acomodo;
    if (sesion != null && !identical(sesion.base, _plano.armado)) {
      final guardado = EditarArmado.firma(_plano.armado);
      if (guardado != EditarArmado.firma(sesion.base)) {
        if (!sesion.hayCambios ||
            guardado == EditarArmado.firma(sesion.actual)) {
          // Se guardó lo acomodado (o no había nada pendiente): se sigue desde
          // lo que quedó.
          final mesa = _mesaAcomodo;
          _limpiarAcomodo();
          _acomodo = _nuevaSesion();
          if (mesa != null && _plano.armado.existe(mesa)) _mesaAcomodo = mesa;
        } else {
          _pista = 'El salón guardado cambió mientras lo acomodabas: tocá '
              'DESCARTAR para ver cómo quedó.';
        }
      }
    }
    // Las familias cambiaron de mesa mientras se acomodaba (la otra PC sorteó,
    // cambió a una o fijó una mesa): la sesión deja de mirar lo viejo. Sin
    // nada pendiente arranca de nuevo; con algo acomodado lo conserva, pero
    // ya no deja volver al original ni guardar sobre familias que no vio.
    final abierta = _acomodo;
    if (abierta != null) {
      final uso = EditarArmado.enUso(widget.alumnos, _plano.config);
      if (!EditarArmado.mismoUso(uso, abierta.enUso)) {
        if (!abierta.hayCambios) {
          final mesa = _mesaAcomodo;
          _limpiarAcomodo();
          _acomodo = _nuevaSesion();
          if (mesa != null && _plano.armado.existe(mesa)) _mesaAcomodo = mesa;
        } else {
          abierta.ponerAlDia(
            enUso: uso,
            ocupantes:
                PlanoDeLaFiesta.ocupantes(widget.alumnos, widget.repartos),
            haySorteo: widget.alumnos.any(SalonMesas.tieneNumeros),
          );
          if (abierta.cambioElUso) {
            _pista = 'Cambiaron las mesas de las familias mientras '
                'acomodabas: tocá DESCARTAR para ver cómo quedó.';
          }
        }
      }
    }
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
        if (widget.acciones?.onGuardarArmado != null) ModoPersonalizar.acomodar,
        if (widget.acciones?.onGuardarMedidas != null) ModoPersonalizar.medidas,
        if (widget.acciones?.onGuardarColoresYTextos != null)
          ModoPersonalizar.colores,
      ];

  /// Pestañas donde el plano solo muestra: no se elige ninguna mesa.
  bool get _soloMuestra =>
      _modo == ModoPersonalizar.medidas || _modo == ModoPersonalizar.colores;

  /// El estilo con los colores de la fiesta (o los que se están probando).
  TemaPlano get _tema => TemaPlano.de(widget.estilo).conColores(
        PlanoDeLaFiesta.coloresDe(
          _plano.estado,
          _coloresEnPrueba?.colores ?? _plano.config.colores,
        ),
      );

  /// El salón como se dibuja: el guardado; el que se está acomodando; o,
  /// mientras se prueban textos de sectores, con esos textos.
  ArmadoSalon get _armadoVisto {
    final acomodando = _acomodo?.visto;
    if (acomodando != null) return acomodando;
    // Mientras se corrige un lado del playón, el borde del hormigón se dibuja
    // con esa medida: lo que queda afuera se ve antes de guardar.
    final medidas = _medidasEnPrueba;
    if (medidas != null) {
      return ArmarAMedida.conPlayon(_plano.armado, medidas.playon);
    }
    return _coloresEnPrueba?.armadoCon(_plano.armado) ?? _plano.armado;
  }

  SesionAcomodo _nuevaSesion() => SesionAcomodo(
        base: _plano.armado,
        medidas: _plano.medidas,
        enUso: EditarArmado.enUso(widget.alumnos, _plano.config),
        ocupantes: PlanoDeLaFiesta.ocupantes(widget.alumnos, widget.repartos),
        // También las bajas que conservan mesa: los números ya están dados.
        haySorteo: widget.alumnos.any(SalonMesas.tieneNumeros),
      );

  void _limpiarAcomodo() {
    _acomodo = null;
    _mesaAcomodo = null;
    _sectorAcomodo = null;
    _alcance = 'hoja';
    _pasoSeparar = null;
    _mensajeAcomodo = null;
    _confirmarDescartar = false;
  }

  /// Lo que quedaría sin guardar si se sale de la pestaña, dicho en palabras.
  /// Null: no hay nada pendiente.
  String? get _sinGuardar => switch (_modo) {
        ModoPersonalizar.medidas when _medidasMalEscritas =>
          'Hay una medida mal escrita: corregila o tocá DESCARTAR.',
        ModoPersonalizar.medidas when _medidasEnPrueba != null =>
          'Hay medidas sin guardar: tocá GUARDAR MEDIDAS o DESCARTAR.',
        ModoPersonalizar.colores when _coloresEnPrueba != null =>
          'Hay colores o textos sin guardar: tocá GUARDAR o DESCARTAR.',
        ModoPersonalizar.acomodar when _acomodo?.hayCambios ?? false =>
          'Hay cambios del salón sin guardar: tocá GUARDAR EL SALÓN o '
              'DESCARTAR.',
        _ => null,
      };

  /// Con algo sin guardar, lo que saca de la pestaña (otro armado, imprimir,
  /// el historial) no se hace: la franja dice qué falta guardar o descartar.
  /// Si no, se perdería sin aviso, o se imprimiría lo guardado y no lo que se
  /// está viendo.
  VoidCallback _siNoHayPendiente(VoidCallback accion) => () {
        final pendiente = _sinGuardar;
        if (pendiente != null) {
          setState(() => _pista = pendiente);
          return;
        }
        accion();
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
      _medidasMalEscritas = false;
      _coloresEnPrueba = null;
      _limpiarAcomodo();
      if (modo == ModoPersonalizar.acomodar) _acomodo = _nuevaSesion();
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
      _medidasMalEscritas = false;
      _coloresEnPrueba = null;
      _limpiarAcomodo();
    });
  }

  // ── Acomodar: lo que se toca en el plano ────────────────────────────────

  /// La mesa de la hoja a la vista bajo un punto del plano, o null.
  int? _mesaEn(ArmadoSalon armado, Offset p) {
    int? mejor;
    var cerca = double.infinity;
    for (final m in armado.mesasDeHoja(_hoja)) {
      final d = (Offset(m.x, m.y) - p).distance;
      if (d <= armado.radio * 1.1 && d < cerca) {
        mejor = m.numero;
        cerca = d;
      }
    }
    return mejor;
  }

  /// Se apretó en el plano: si ahí hay una mesa o un sector, queda elegido y
  /// agarrado para arrastrar. Con la vista previa de separar abierta no se
  /// agarra nada.
  bool _apretar(Offset p) {
    final s = _acomodo;
    if (s == null || widget.ocupado || s.previa != null) return false;
    final armado = s.actual;
    final mesa = _mesaEn(armado, p);
    final sector =
        mesa != null ? null : EditarArmado.sectorEn(armado, _hoja, p.dx, p.dy);
    _apretadoEn = p;
    _seMovio = false;
    setState(() {
      _mesaAcomodo = mesa;
      _sectorAcomodo = sector;
      _mensajeAcomodo = null;
      _confirmarDescartar = false;
      if (mesa != null) {
        final m = armado.mesa(mesa)!;
        _desfase = p - Offset(m.x, m.y);
        s.empezarArrastre();
      } else if (sector != null) {
        final c = armado.sectores[sector].caja;
        _desfase = p - Offset(c.x, c.y);
        s.empezarArrastre();
      }
    });
    return mesa != null || sector != null;
  }

  void _arrastrar(Offset p) {
    final s = _acomodo;
    if (s == null || !s.arrastrando) return;
    // Un clic para elegir no es un arrastre: mientras el puntero no se aleje
    // de donde se apretó, no se corre nada. (Un temblor de un par de píxeles
    // ya alcanzaba para correr la mesa un cuarto de metro sin querer.)
    if (!_seMovio) {
      final hoja = s.actual.hoja(_hoja);
      final pxPorUnidad = hoja == null
          ? 1.0
          : EncuadrePlano.de(hoja.caja, _tamPlano).escala;
      final lejos = (p - _apretadoEn).distance * pxPorUnidad * _escalaZoom;
      if (lejos < _recorridoMinimoPx) return;
      _seMovio = true;
    }
    final destino = p - _desfase;
    setState(() {
      final mesa = _mesaAcomodo;
      final sector = _sectorAcomodo;
      if (mesa != null) {
        s.arrastrarMesa(mesa, destino.dx, destino.dy);
      } else if (sector != null) {
        s.arrastrarSector(sector, destino.dx, destino.dy);
      }
    });
  }

  void _soltarArrastre() {
    final s = _acomodo;
    if (s != null) setState(s.terminarArrastre);
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
    } else if (_modo == ModoPersonalizar.colores) {
      texto = 'El color de cada división, el título del plano y los textos '
          'de los sectores.';
    } else if (_modo == ModoPersonalizar.acomodar) {
      texto = _acomodo?.previa != null
          ? 'Así quedaría: APLICAR para dejarlo así, o CANCELAR.'
          : 'Arrastrá una mesa para correrla: se ve la distancia a las tres '
              'más cercanas. Nada cambia hasta tocar GUARDAR EL SALÓN.';
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
    final titulo =
        (_coloresEnPrueba?.titulo ?? _plano.config.titulo ?? '').trim();
    final subtitulo =
        (_coloresEnPrueba?.subtitulo ?? _plano.config.subtitulo ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          if (titulo.isNotEmpty || subtitulo.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                key: const Key('titulo_del_plano'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (titulo.isNotEmpty)
                    Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  if (subtitulo.isNotEmpty)
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
          ],
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
    final armado = _armadoVisto;
    final tema = _tema;
    final acomodando = _acomodo != null;
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
                      // Mientras se arrastra una mesa, el plano se queda
                      // quieto.
                      panEnabled: !(_acomodo?.arrastrando ?? false),
                      child: VistaPlano(
                        armado: armado,
                        hoja: _hoja,
                        tema: tema,
                        estado: _plano.estado,
                        // Acomodando no se apaga ninguna mesa: hay que ver
                        // las vecinas.
                        resaltadas: acomodando ? const {} : _resaltadas,
                        seleccionada: acomodando ? null : _mesaElegida,
                        // En Medidas y en Colores y textos no se elige
                        // nada: el plano solo muestra cómo queda. En Acomodar
                        // se elige apretando, para poder arrastrar.
                        onTapMesa:
                            _soloMuestra || acomodando ? null : _elegirMesa,
                        mostrarMedidas: true,
                        lugares: _modo == ModoPersonalizar.medidas
                            ? _medidasEnPrueba ?? _plano.medidas
                            : widget.mostrarLugares || acomodando
                                ? _plano.medidas
                                : null,
                        encima: acomodando
                            ? PintorAcomodo(
                                armado: armado,
                                hoja: _hoja,
                                tema: tema,
                                mesa: _mesaAcomodo,
                                sector: _sectorAcomodo,
                                vecinas: _mesaAcomodo == null
                                    ? const []
                                    : EditarArmado.vecinas(
                                        armado,
                                        _mesaAcomodo!,
                                      ),
                                pideM: _plano.medidas.lugarMesaM,
                              )
                            : null,
                        onApretar: acomodando ? _apretar : null,
                        onArrastrar: acomodando ? _arrastrar : null,
                        onSoltar: acomodando ? _soltarArrastre : null,
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
                          // Lo elegido y la vista previa de separar eran de
                          // la otra hoja: no se actúa sobre lo que no se ve.
                          _acomodo?.cancelarSeparar();
                          _pasoSeparar = null;
                          _alcance = 'hoja';
                          _mesaAcomodo = null;
                          _sectorAcomodo = null;
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
          onMalEscrito: (mal) {
            if (mal != _medidasMalEscritas) {
              setState(() => _medidasMalEscritas = mal);
            }
          },
          onGuardar: (m) {
            setState(() => _pista = null);
            widget.acciones?.onGuardarMedidas?.call(m, _plano.medidas);
          },
          aviso: _avisoMedidas,
          // El botón se llama como la pantalla que abre.
          textoAccionAviso: 'ESTILO Y ARMADO',
          onAccionAviso: _hayFamiliasConMesa || widget.onEstiloYArmado == null
              ? null
              : _siNoHayPendiente(widget.onEstiloYArmado!),
        ),
      );

  /// Las divisiones de la fiesta, para elegirles el color: primero las de la
  /// leyenda (las que ya tienen mesa), en su orden, y después las demás.
  List<DivisionParaColor> get _divisionesParaColor {
    final estado = _plano.estado;
    final nombres = Divisiones.nombres(
      widget.alumnos.where((a) => !a.esBajaTemporal),
    );
    final resto = Divisiones.ordenNatural(
      nombres.keys.where((k) => k.isNotEmpty && !estado.divisiones.contains(k)),
    );
    return [
      for (final (i, k) in estado.divisiones.indexed)
        (clave: k, nombre: estado.nombresDivision[k] ?? k, lugar: i),
      for (final k in resto) (clave: k, nombre: nombres[k] ?? k, lugar: null),
    ];
  }

  Widget _panelColores() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
        child: PanelColoresTextos(
          estilo: widget.estilo,
          divisiones: _divisionesParaColor,
          config: _plano.config,
          sectores: _plano.armado.sectores,
          variasHojas: _plano.armado.hojas.length > 1,
          ocupado: widget.ocupado,
          onProbar: (c) => setState(() {
            _coloresEnPrueba = c;
            if (c == null) _pista = null;
          }),
          onGuardar: (c) {
            setState(() => _pista = null);
            widget.acciones?.onGuardarColoresYTextos?.call(c, _plano.config);
          },
        ),
      );

  Widget _panelAcomodar() {
    final s = _acomodo!;
    final armado = s.actual;
    final numeroElegido = _mesaAcomodo;
    final mesa = numeroElegido == null ? null : armado.mesa(numeroElegido);
    final indice = _sectorAcomodo;
    final sector = indice != null && indice < armado.sectores.length
        ? armado.sectores[indice]
        : null;
    final alcances = EditarArmado.alcances(
      armado,
      _hoja,
      bloques: _plano.config.bloques,
      nombres: _plano.estado.nombresDivision,
    );
    final alcance = alcances.any((a) => a.clave == _alcance)
        ? _alcance
        : alcances.isEmpty
            ? 'hoja'
            : alcances.first.clave;
    final numeros = alcances
            .where((a) => a.clave == alcance)
            .map((a) => a.numeros)
            .firstOrNull ??
        const <int>{};
    final paso = _pasoSeparar ??
        EditarArmado.pasoDe(armado, numeros) ??
        _plano.medidas.lugarMesaM;

    String? seleccion;
    String? detalle;
    if (mesa != null) {
      seleccion = [
        'Mesa ${mesa.numero}',
        s.enUso[mesa.numero] ?? 'vacía',
        if (mesa.pasto) 'en el pasto',
      ].join(' · ');
      final vecinas = EditarArmado.vecinas(armado, mesa.numero);
      if (vecinas.isNotEmpty) {
        detalle = 'A ${[
          for (final v in vecinas)
            '${MedirSalon.metros(v.metros, decimales: 2)} de la ${v.numero}',
        ].join(', ')}.';
      }
    } else if (sector != null) {
      seleccion = 'Sector: '
          '${sector.texto.trim().isEmpty ? PanelColoresTextos.rotuloDe(sector.tipo) : sector.texto.trim()}';
    }

    void hecho(String? mensaje) {
      _mensajeAcomodo = mensaje;
      _confirmarDescartar = false;
      _pista = null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
      child: PanelAcomodar(
        seleccion: seleccion,
        detalle: detalle,
        mensaje: _mensajeAcomodo,
        onAgregar: () => setState(() {
          final n = s.agregar(_hoja, cerca: _mesaAcomodo);
          _mesaAcomodo = n;
          _sectorAcomodo = null;
          hecho('Mesa $n agregada: arrastrala a su lugar.');
        }),
        onSacar: mesa == null
            ? null
            : () => setState(() {
                  final problema = s.sacar(mesa.numero);
                  if (problema == null) _mesaAcomodo = null;
                  hecho(problema ?? 'Mesa ${mesa.numero} sacada.');
                }),
        onPasto: mesa == null
            ? null
            : () => setState(() {
                  s.cambiarPasto(mesa.numero);
                  hecho(null);
                }),
        mesaEnPasto: mesa?.pasto ?? false,
        onDeshacer: s.puedeDeshacer
            ? () => setState(() {
                  s.deshacer();
                  _pasoSeparar = null;
                  final n = _mesaAcomodo;
                  if (n != null && !s.actual.existe(n)) _mesaAcomodo = null;
                  final i = _sectorAcomodo;
                  if (i != null && i >= s.actual.sectores.length) {
                    _sectorAcomodo = null;
                  }
                  hecho(null);
                })
            : null,
        onAgregarSector: (tipo) => setState(() {
          _sectorAcomodo = s.agregarSector(
            _hoja,
            tipo,
            texto: PanelColoresTextos.rotuloDe(tipo),
          );
          _mesaAcomodo = null;
          hecho('Sector agregado arriba a la izquierda: arrastralo a su '
              'lugar. El texto se cambia en Colores y textos.');
        }),
        onSacarSector: sector == null
            ? null
            : () => setState(() {
                  s.sacarSector(indice!);
                  _sectorAcomodo = null;
                  hecho(null);
                }),
        onTamanoSector: sector == null
            ? null
            : (dx, dy) => setState(() {
                  s.tamanoSector(
                    indice!,
                    anchoM: armado.aMetros(sector.caja.ancho) + dx,
                    altoM: armado.aMetros(sector.caja.alto) + dy,
                  );
                  hecho(null);
                }),
        tamanoSector: sector == null
            ? null
            : '${MedirSalon.metros(armado.aMetros(sector.caja.ancho)).replaceFirst(' m', '')}'
                ' × ${MedirSalon.metros(armado.aMetros(sector.caja.alto))}',
        alcances: alcances,
        alcance: alcance,
        onAlcance: (v) => setState(() {
          _alcance = v;
          _pasoSeparar = null;
          s.cancelarSeparar();
        }),
        paso: paso,
        onPaso: (v) => setState(() {
          _pasoSeparar = v;
          _confirmarDescartar = false;
          s.probarSeparar(
            numeros,
            v,
            sillasExtraDe: (n) => _plano.estado.info(n).sillasExtra,
          );
        }),
        textoPrevia: s.previa?.texto,
        previaEntra: s.previa?.entra ?? true,
        previaSePuede: s.previa?.sePuede ?? true,
        onAplicar: () => setState(() {
          s.aplicarSeparar();
          _pasoSeparar = null;
          hecho(null);
        }),
        onCancelar: () => setState(() {
          s.cancelarSeparar();
          _pasoSeparar = null;
        }),
        bloqueos: s.bloqueos,
        avisos: s.avisos((n) => _plano.estado.info(n).sillasExtra),
        motivoSinOriginal: s.motivoSinOriginal,
        onOriginal: () => setState(() {
          final problema = s.volverAlOriginal();
          _mesaAcomodo = null;
          _sectorAcomodo = null;
          _pasoSeparar = null;
          hecho(problema ??
              'Volvió el armado original. Todavía no se guardó: se puede '
                  'deshacer.');
        }),
        hayCambios: s.hayCambios,
        puedeGuardar: s.puedeGuardar,
        ocupado: widget.ocupado,
        confirmarDescartar: _confirmarDescartar,
        onGuardar: () {
          setState(() => _pista = null);
          widget.acciones?.onGuardarArmado
              ?.call(s.base, s.actual, s.enUsoAlEmpezar);
        },
        // Descartar se lleva todo lo acomodado: se pide dos veces, y aun así
        // se puede deshacer (un doble clic no pierde una hora de trabajo).
        onDescartar: () => setState(() {
          if (!_confirmarDescartar) {
            _confirmarDescartar = true;
            return;
          }
          // Si el salón guardado es otro (cambió mientras se acomodaba), se
          // arranca desde ese: ahí lo de antes ya no se puede traer de vuelta.
          final otroSalon = !identical(s.base, _plano.armado);
          s.descartar();
          _mesaAcomodo = null;
          _sectorAcomodo = null;
          _pasoSeparar = null;
          hecho(otroSalon
              ? null
              : 'Volvió el salón guardado. Con Deshacer vuelve lo que habías '
                  'acomodado.');
          if (otroSalon) _acomodo = _nuevaSesion();
        }),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    if (_modo == ModoPersonalizar.acomodar) return _panelAcomodar();
    if (_modo == ModoPersonalizar.medidas) return _panelMedidas();
    if (_modo == ModoPersonalizar.colores) return _panelColores();
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
    final tema = _tema;
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
    // Sin modo jefe, lo que cambia el salón queda a la vista y apagado: si
    // desapareciera, el operario no sabría que existe ni a quién pedírselo.
    Widget apagado(
      Key key,
      String texto,
      IconData icono, {
      bool principal = false,
    }) =>
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Tooltip(
            message: kSoloEnModoJefe,
            child: principal
                ? FilledButton.icon(
                    key: key,
                    onPressed: null,
                    icon: Icon(icono, size: 18),
                    label: Text(texto),
                  )
                : OutlinedButton.icon(
                    key: key,
                    onPressed: null,
                    icon: Icon(icono, size: 18),
                    label: Text(texto),
                  ),
          ),
        );
    final sinArmar = widget.soloJefe && widget.onEstiloYArmado == null;
    final sinPersonalizar = widget.soloJefe && widget.acciones == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: [
          if (widget.onEstiloYArmado != null)
            boton(
              const Key('estilo_y_armado'),
              'ESTILO Y ARMADO',
              Icons.dashboard_customize_outlined,
              _siNoHayPendiente(widget.onEstiloYArmado!),
              principal: true,
            )
          else if (sinArmar)
            apagado(
              const Key('estilo_y_armado'),
              'ESTILO Y ARMADO',
              Icons.dashboard_customize_outlined,
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
            )
          else if (sinPersonalizar)
            apagado(const Key('personalizar'), 'PERSONALIZAR', Icons.tune),
          if (widget.onImprimir != null)
            boton(
              const Key('imprimir'),
              'IMPRIMIR',
              Icons.print_rounded,
              _siNoHayPendiente(widget.onImprimir!),
            ),
          if (widget.onHistorial != null)
            boton(
              const Key('historial'),
              'HISTORIAL',
              Icons.history,
              _siNoHayPendiente(widget.onHistorial!),
            ),
          if (sinArmar || sinPersonalizar)
            Flexible(
              child: Text(
                'Armar y personalizar el plano: solo en modo jefe.',
                key: const Key('motivo_solo_jefe'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
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
