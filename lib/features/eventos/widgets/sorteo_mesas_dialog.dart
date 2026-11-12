import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../plano/modelo/armado_salon.dart';
import '../../plano/services/cambios_de_mesa.dart';
import '../../plano/services/divisiones.dart';
import '../../plano/services/mesas_nuevas_al_fondo.dart';
import '../../plano/services/orden_en_el_salon.dart';
import '../../plano/services/sorteo_con_plano.dart';
import '../../plano/widgets/elegir_zona_dialog.dart';
import '../services/mesas_extra_utils.dart';
import '../services/pago_para_sorteo.dart';
import '../services/salon_mesas.dart';
import '../services/sorteo_mesas_motor.dart';

/// Diálogo previo al sorteo: a quién se le sortea según lo pagado, qué se va a
/// sortear, quién tiene mesas y sillas extra, qué conviene revisar y con qué
/// capacidad.
///
/// La capacidad que propone es la mínima con la que todo entra
/// ([SorteoMesasMotor.capacidadMinima]), y SORTEAR solo se habilita si la que
/// quedó escrita pasa [SorteoMesasMotor.esFactible]: el mismo chequeo con el
/// que arranca el sorteo. Así "no entra" no puede pasar al tocar el botón.
///
/// Si la fiesta tiene [plano], en vez de la capacidad se elige cómo se sortea
/// sobre el salón: por bloques de división (en el orden que se elija) o entero
/// ("de la mesa 1 a la N"). Lo que muestra sale de [SorteoConPlano.preparar],
/// que es lo mismo que después hace el sorteo.
Future<SorteoMesasDialogResult?> mostrarSorteoMesasDialog({
  required BuildContext context,
  required String tituloInstitucion,
  required List<ContratoAlumno> alumnos,
  required List<AvisoSalon> avisos,
  required Map<String, PagoAlumno> pagos,
  SorteoMesasDialogResult? inicial,
  String? novedad,
  PlanoEvento? plano,
  String? eventoId,
  Map<String, List<Map<String, dynamic>>>? pagosCrudos,
}) {
  return showDialog<SorteoMesasDialogResult>(
    context: context,
    builder: (context) => SorteoMesasDialog(
      tituloInstitucion: tituloInstitucion,
      alumnos: alumnos,
      avisos: avisos,
      pagos: pagos,
      inicial: inicial,
      novedad: novedad,
      plano: plano,
      eventoId: eventoId,
      pagosCrudos: pagosCrudos,
    ),
  );
}

@visibleForTesting
/// Cuántas mesas de una familia van juntas sin preguntar: la principal y 2
/// adicionales (pedido del usuario, 9-nov). De ahí en más, las de más van lejos:
/// en el cartel del sorteo vienen tildadas.
const kMesasJuntasEnElSorteo = 3;

class SorteoMesasDialog extends StatefulWidget {
  final String tituloInstitucion;
  final List<ContratoAlumno> alumnos;
  final List<AvisoSalon> avisos;
  final Map<String, PagoAlumno> pagos;
  final SorteoMesasDialogResult? inicial;
  final String? novedad;
  final PlanoEvento? plano;

  /// Para "Cumplimiento debido" (6.7.1): la fiesta y los pagos uno por uno,
  /// de donde sale quién cumplió mejor. Sin ellos, el tilde no aparece.
  final String? eventoId;
  final Map<String, List<Map<String, dynamic>>>? pagosCrudos;

  /// El día de hoy en Argentina. Solo para las pruebas.
  final DateTime? hoyAr;

  const SorteoMesasDialog({
    super.key,
    required this.tituloInstitucion,
    required this.alumnos,
    required this.avisos,
    required this.pagos,
    this.inicial,
    this.novedad,
    this.plano,
    this.eventoId,
    this.pagosCrudos,
    this.hoyAr,
  });

  @override
  State<SorteoMesasDialog> createState() => _SorteoMesasDialogState();
}

class _SorteoMesasDialogState extends State<SorteoMesasDialog> {
  late final TextEditingController _capacidadCtrl;
  late final Map<String, int> _separaciones;

  /// Qué tan lejos van las separadas de cada alumno. Viene en "cerca".
  late final Map<String, DistanciaLejos> _distancias;

  /// Las mesas del plano donde van las lejos de cada alumno, con "Donde yo
  /// elija" (6.5.0).
  late final Map<String, Set<int>> _zonas;

  /// Las zonas que valen: de quien tildó lejos y eligió "Donde yo elija".
  Map<String, Set<int>> get _zonasElegidas => {
        for (final e in _zonas.entries)
          if (_separacionesQueValen.containsKey(e.key) &&
              _distancias[e.key] == DistanciaLejos.enLaZona &&
              e.value.isNotEmpty)
            e.key: e.value,
      };

  // ── Las mesas adicionales, al final (6.6.1) ──

  /// "Las mesas adicionales: Al final" (true) o "Con su familia" (false, lo de
  /// siempre). Viene en false: el jefe lo elige en cada sorteo.
  bool _adicionalesAlFinal = false;

  /// Con "Al final": cuántas adicionales quedan pegadas a la principal, para
  /// todas las familias (0, 1 o 2).
  int _juntasConLaPrincipal = 0;

  /// Con "Al final": las familias tildadas "dejar juntas".
  late final Set<String> _dejarJuntas;

  /// Los alumnos que no tienen ninguna mesa: a ellos les vale "Al final".
  late final Set<String> _sinNingunaMesa;

  /// Vale solo sobre el plano y con toda la escuela junta: por división cada
  /// bloque es de su división y "después de todas" no tiene un lugar.
  bool get _alFinalActivo =>
      _adicionalesAlFinal && _plano != null && _modo == ModoSorteo.entera;

  /// Lo que se le pide al sorteo: alumno → cuántas de sus mesas van al final.
  /// Con "Cumplimiento debido" no se le pide nada: ya lo repartió el orden.
  Map<String, int> get _alFinal => !_alFinalActivo || _cumplimiento
      ? const {}
      : SorteoConPlano.alFinalSegunElCartel(
          _pedidos,
          juntas: _juntasConLaPrincipal,
          dejarJuntas: _dejarJuntas,
        );

  // ── Cumplimiento debido (6.7.1) ──

  /// El tilde. Viene destildado: el jefe lo elige en cada sorteo.
  bool _porCumplimiento = false;
  RecorridoDelOrden _recorrido = RecorridoDelOrden.columnas;
  String? _claveOrden;
  OrdenParaElSorteo? _ordenMemo;

  /// Se ofrece sobre el plano y con los pagos a mano.
  bool get _ofreceCumplimiento =>
      _plano != null && widget.eventoId != null && widget.pagosCrudos != null;

  bool get _cumplimiento => _porCumplimiento && _ofreceCumplimiento;

  /// El plano sin lo que dejó el tilde de la 6.7.0, que fijaba las mesas antes
  /// de sortear: con eso adentro el cartel creía que no quedaba nada por dar.
  ConfigPlano get _config {
    final c = _plano!.config;
    return OrdenEnElSalon.sinFijadasDelOrden(c) ?? c;
  }

  /// Quién va a qué mesa por cumplimiento, con lo elegido en el cartel. Null
  /// si el tilde no está.
  OrdenParaElSorteo? get _ordenPorCumplimiento {
    if (!_cumplimiento) return null;
    final ex = _exclusion;
    final clave = [
      _recorrido.clave,
      _usarPasto,
      _alFinalActivo,
      _juntasConLaPrincipal,
      (ex.sinMesa.toList()..sort()).join(','),
      (ex.soloBase.toList()..sort()).join(','),
    ].join('|');
    if (clave != _claveOrden || _ordenMemo == null) {
      _claveOrden = clave;
      _ordenMemo = OrdenEnElSalon.paraElSorteo(
        eventoId: widget.eventoId!,
        armado: _plano!.armado,
        config: _config,
        alumnos: widget.alumnos,
        pagos: widget.pagosCrudos!,
        hoyAr: widget.hoyAr ?? ArTime.nowAr(),
        ahora: DateTime.now().toUtc(),
        exclusion: ex,
        modo: _modo,
        recorrido: _recorrido,
        usarPasto: _usarPasto,
        adicionalesAlFinal: _alFinalActivo,
        juntasConLaPrincipal: _juntasConLaPrincipal,
      );
    }
    return _ordenMemo;
  }

  /// Los "lejos" que valen. Con "Al final", los de las familias sin mesa no
  /// cuentan (los reemplazan la regla por cantidad y "dejar juntas"); los de
  /// quien ya tiene mesa y le falta otra, sí.
  Map<String, int> get _separacionesQueValen => !_alFinalActivo
      ? _separaciones
      : {
          for (final e in _separaciones.entries)
            if (!_sinNingunaMesa.contains(e.key)) e.key: e.value,
        };

  Map<String, DistanciaLejos> get _distanciasQueValen => {
        for (final id in _separacionesQueValen.keys)
          id: _distancias[id] ?? DistanciaLejos.cerca,
      };
  late final Set<int> _ocupadas;
  late final CandidatosPorPago _candidatos;

  // ── Con plano ──
  late ModoSorteo _modo;

  /// Claves de división ([Divisiones.clave]) en el orden de los bloques.
  late List<String> _orden;
  bool _usarPasto = false;
  late final TextEditingController _hastaCtrl;
  String? _claveMemo;
  PlanSorteo? _memo;

  /// El plano sobre el que se sortea. Null si la fiesta no tiene, y también
  /// si lo tiene pero no se puede leer ([_planoIlegible]): ahí no se sortea.
  PlanoEvento? get _plano => _planoIlegible ? null : widget.plano;

  /// La fiesta tiene plano pero su armado no se puede leer. Sortear como si
  /// no tuviera ignoraría sus mesas fijas y libres: se avisa y no se sortea.
  /// (La pantalla ya frena antes; esto es para que el diálogo nunca rompa.)
  bool get _planoIlegible =>
      widget.plano != null && widget.plano!.armadoONull == null;

  // ── Las mesas que faltan, con el sorteo ya hecho (6.5.1) ──

  /// "En mesas nuevas, al fondo" (true) o "en las mesas libres del salón".
  /// Viene elegido lo primero: es lo que pidió el jefe para quien llega
  /// después del sorteo. Solo vale si se puede ([_motivoSinMesasNuevas]).
  late bool _alFondo;
  String? _claveNuevas;
  PlanMesasNuevas? _nuevasMemo;

  /// Por qué no se ofrecen mesas nuevas, o null si se puede: hace falta un
  /// salón a medida y que alguna familia ya tenga mesa.
  String? get _motivoSinMesasNuevas {
    final plano = _plano;
    if (plano == null) return 'La fiesta no tiene plano.';
    return MesasNuevasAlFondo.motivoSinMesasNuevas(
      plano.armado,
      widget.alumnos,
    );
  }

  /// A quiénes les falta mesa y cuántas mesas nuevas harían falta, se elija lo
  /// que se elija: con esto se decide si se muestra la pregunta.
  Map<String, int> get _faltantes {
    final plano = _plano;
    // Con "Cumplimiento debido" no hay mesas nuevas: se reacomoda el salón.
    if (plano == null || _cumplimiento || _motivoSinMesasNuevas != null) {
      return const {};
    }
    return MesasNuevasAlFondo.faltantes(
      armado: plano.armado,
      config: _config,
      pedidos: _pedidos,
    );
  }

  /// Las mesas nuevas que se agregarían al salón. Null si se eligió "en las
  /// mesas libres", si no se puede o si no falta ninguna.
  PlanMesasNuevas? get _nuevas {
    final plano = _plano;
    if (plano == null ||
        _cumplimiento ||
        !_alFondo ||
        _motivoSinMesasNuevas != null) {
      return null;
    }
    final ex = _exclusion;
    final clave = [
      (ex.sinMesa.toList()..sort()).join(','),
      (ex.soloBase.toList()..sort()).join(','),
    ].join('|');
    if (clave != _claveNuevas) {
      _claveNuevas = clave;
      final plan = MesasNuevasAlFondo.planear(
        armado: plano.armado,
        config: _config,
        alumnos: widget.alumnos,
        pedidos: _pedidos,
        llegada: llegadaPorPago(widget.pagos),
      );
      _nuevasMemo = plan.vacio ? null : plan;
    }
    return _nuevasMemo;
  }

  /// El salón sobre el que se sortea: el del plano, con las mesas nuevas si
  /// las hay.
  ArmadoSalon get _armado => _nuevas?.armado ?? _plano!.armado;

  EntradaSorteoPlano _entrada() {
    // Con "Cumplimiento debido" el orden ya dice quién va a qué mesa: al
    // sorteo de siempre le queda entregarlas.
    final orden = _ordenPorCumplimiento;
    if (orden != null && orden.sePuede) {
      return OrdenEnElSalon.entrada(
        orden,
        armado: _plano!.armado,
        usarPasto: _usarPasto,
      );
    }
    return _entradaDeSiempre();
  }

  EntradaSorteoPlano _entradaDeSiempre() => EntradaSorteoPlano(
        armado: _armado,
        config: _nuevas?.config ?? _config,
        alumnos: widget.alumnos,
        exclusion: _exclusion,
        separaciones: _separacionesQueValen,
        distancias: _alFinalActivo ? _distanciasQueValen : _distancias,
        modo: _modo,
        ordenDivisiones: _orden,
        usarPasto: _usarPasto,
        hastaMesa: int.tryParse(_hastaCtrl.text.trim()),
        zonas: _zonasElegidas,
        alFinal: _alFinal,
      );

  /// Lo que va a hacer el sorteo sobre el plano. Se recalcula solo si cambió
  /// algo que lo decide (tildar "ya revisé" no lo recalcula).
  PlanSorteo _plan() {
    final ex = _exclusion;
    final clave = [
      _cumplimiento,
      _recorrido.clave,
      _alFinalActivo,
      _juntasConLaPrincipal,
      _modo.name,
      _alFondo,
      _orden.join(','),
      _usarPasto,
      _hastaCtrl.text.trim(),
      (ex.sinMesa.toList()..sort()).join(','),
      (ex.soloBase.toList()..sort()).join(','),
      (_separacionesQueValen.entries
              .map((e) => '${e.key}=${e.value}')
              .toList()
            ..sort())
          .join(','),
      (_distancias.entries.map((e) => '${e.key}=${e.value.name}').toList()..sort())
          .join(','),
      (_alFinal.entries.map((e) => '${e.key}=${e.value}').toList()..sort())
          .join(','),
      (_zonasElegidas.entries
              .map((e) => '${e.key}=${(e.value.toList()..sort()).join('.')}')
              .toList()
            ..sort())
          .join(','),
    ].join('|');
    if (clave != _claveMemo || _memo == null) {
      _memo = SorteoConPlano.preparar(_entrada());
      _claveMemo = clave;
    }
    return _memo!;
  }

  /// "Solo a lo que tiene algo pagado". Arranca elegido: es para lo que existe.
  late bool _soloPagado;

  /// Casillas "sortear igual" (ver [exclusionSorteo]).
  late final Set<String> _incluirBase;
  late final Set<String> _incluirExtras;
  bool _revisado = false;

  List<ContratoAlumno> get _activos =>
      widget.alumnos.where((a) => !a.esBajaTemporal).toList();

  ExclusionSorteo get _exclusion => exclusionSorteo(
        candidatos: _candidatos,
        soloPagado: _soloPagado,
        incluirBase: _incluirBase,
        incluirExtras: _incluirExtras,
      );

  List<PedidoSorteo> get _pedidos {
    final ex = _exclusion;
    return SorteoMesasMotor.pedidos(
      widget.alumnos,
      // Los "lejos" tal como están tildados: acá solo cambian cuántas van
      // sueltas, no quién entra ni con cuántas mesas.
      separaciones: _separaciones,
      sinMesa: ex.sinMesa,
      soloBase: ex.soloBase,
    );
  }

  int _minima(List<PedidoSorteo> pedidos) =>
      SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: _ocupadas);

  PagoAlumno _pago(ContratoAlumno a) => widget.pagos[a.id] ?? PagoAlumno.nada;

  @override
  void initState() {
    super.initState();
    _ocupadas = SorteoMesasMotor.ocupadas(widget.alumnos);
    _separaciones = Map<String, int>.from(widget.inicial?.separaciones ?? {});
    _distancias = Map<String, DistanciaLejos>.from(
      widget.inicial?.distancias ?? const {},
    );
    _candidatos = candidatosPorPago(widget.alumnos, widget.pagos);
    _soloPagado = widget.inicial?.soloPagado ?? true;
    _incluirBase = {...?widget.inicial?.incluirBase};
    _incluirExtras = {...?widget.inicial?.incluirExtras};
    _alFondo = widget.inicial?.mesasNuevasAlFondo ?? true;
    _porCumplimiento = widget.inicial?.porCumplimiento ?? false;
    _recorrido = widget.inicial?.recorrido ?? RecorridoDelOrden.columnas;
    _adicionalesAlFinal = widget.inicial?.adicionalesAlFinal ?? false;
    _juntasConLaPrincipal = widget.inicial?.juntasConLaPrincipal ?? 0;
    _dejarJuntas = {...?widget.inicial?.dejarJuntas};
    _sinNingunaMesa = {
      for (final a in widget.alumnos)
        if (MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isEmpty) a.id,
    };
    _zonas = {
      for (final e in (widget.inicial?.zonas ?? const <String, Set<int>>{})
          .entries)
        e.key: {...e.value},
    };
    // Más de 3 mesas (pedido del usuario, 9-nov): la principal y 2 adicionales
    // van juntas y las de más, lejos. La primera vez vienen tildadas; el jefe
    // las destilda o elige dónde.
    // Con todas sus mesas, pagas o no: si después se pasa a "todo lo cargado",
    // ya viene tildada (y a una que va solo con la base no le cambia nada).
    if (widget.inicial == null) {
      for (final p in SorteoMesasMotor.pedidos(widget.alumnos)) {
        if (!p.esNuevo || p.mesas <= kMesasJuntasEnElSorteo) continue;
        _separaciones[p.alumnoId] = p.mesas - kMesasJuntasEnElSorteo;
        _distancias[p.alumnoId] = DistanciaLejos.bienLejos;
      }
    }
    final minima = _minima(_pedidos);
    final inicial = widget.inicial?.capacidadSalon ?? minima;
    _capacidadCtrl = TextEditingController(
      text: '${inicial < minima ? minima : inicial}',
    );

    final plano = _plano;
    _hastaCtrl = TextEditingController(
      text: widget.inicial?.hastaMesa?.toString() ?? '',
    );
    _modo = widget.inicial?.modo ?? plano?.modoSorteo ?? ModoSorteo.entera;
    final claves = Divisiones.ordenNatural(
      _activos.map((a) => Divisiones.clave(a.cursoDivision)),
    );
    final previo = widget.inicial?.ordenDivisiones.isNotEmpty == true
        ? widget.inicial!.ordenDivisiones
        : plano?.config.ordenDivisiones ?? const <String>[];
    _orden = [
      for (final k in previo)
        if (claves.contains(k)) k,
      for (final k in claves)
        if (!previo.contains(k)) k,
    ];
    _usarPasto = widget.inicial?.usarPasto ?? false;
    if (plano != null && _hastaCtrl.text.isEmpty) {
      final min = _plan().hastaMesaMinima;
      if (min != null) _hastaCtrl.text = '$min';
    }
  }

  @override
  void dispose() {
    _capacidadCtrl.dispose();
    _hastaCtrl.dispose();
    super.dispose();
  }

  /// Aplica un cambio que mueve el mínimo. Si la capacidad escrita era la
  /// sugerida, sigue a la sugerida (sube o baja); si alguien la escribió a mano,
  /// solo sube cuando ya no alcanza. Con plano, lo mismo con "hasta la mesa".
  void _cambiar(VoidCallback cambio) {
    final antes = _minima(_pedidos);
    final antesPlano = _plano == null ? null : _plan().hastaMesaMinima;
    final avisosAntes = _plano == null ? '' : _plan().avisos.join('|');
    setState(() {
      cambio();
      if (_plano != null && _plan().avisos.join('|') != avisosAntes) {
        // Aparecieron avisos que nadie leyó (por ejemplo, al cambiar de modo):
        // el tilde de antes no los cubre.
        _revisado = false;
      }
      final minima = _minima(_pedidos);
      final actual = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
      if (actual == antes || actual < minima) _capacidadCtrl.text = '$minima';
      if (_plano != null) {
        final hasta = int.tryParse(_hastaCtrl.text.trim()) ?? 0;
        final nueva = _plan().hastaMesaMinima;
        if (nueva != null && (hasta == antesPlano || hasta < nueva)) {
          _hastaCtrl.text = '$nueva';
        }
      }
    });
  }

  void _cambiarSeparacion(String alumnoId, int? cantidad) => _cambiar(() {
        if (cantidad == null || cantidad < 1) {
          _separaciones.remove(alumnoId);
          _distancias.remove(alumnoId);
        } else {
          _separaciones[alumnoId] = cantidad;
          _distancias[alumnoId] ??= DistanciaLejos.cerca;
        }
      });

  void _cambiarDistancia(String alumnoId, DistanciaLejos distancia) =>
      _cambiar(() => _distancias[alumnoId] = distancia);

  /// ELEGIR EN EL PLANO: el salón se abre encima del cartel, y al volver queda
  /// la zona.
  Future<void> _elegirZona(ContratoAlumno a, int necesita) async {
    final plano = _plano;
    if (plano == null) return;
    final elegidas = await ElegirZonaDialog.abrir(
      context,
      plano: plano,
      alumnos: widget.alumnos,
      nombre: a.nombreAlumno,
      necesita: necesita,
      elegidas: _zonas[a.id] ?? const {},
    );
    if (elegidas == null || !mounted) return;
    _cambiar(() => _zonas[a.id] = elegidas);
  }

  void _alternar(Set<String> conjunto, String id, bool incluir) =>
      _cambiar(() => incluir ? conjunto.add(id) : conjunto.remove(id));

  @override
  Widget build(BuildContext context) {
    final exclusion = _exclusion;
    final pedidos = _pedidos;
    final demanda = SorteoMesasMotor.demanda(pedidos);
    final minima = _minima(pedidos);
    final capacidad = int.tryParse(_capacidadCtrl.text.trim());
    final factible = capacidad != null &&
        SorteoMesasMotor.esFactible(
          pedidos: pedidos,
          ocupadas: _ocupadas,
          capacidad: capacidad,
        );
    final plano = _plano;
    final plan = plano == null ? null : _plan();
    final hastaEscrita = int.tryParse(_hastaCtrl.text.trim());
    final hastaOk = plan == null ||
        plan.modo != ModoSorteo.entera ||
        (plan.hastaMesaMinima != null &&
            hastaEscrita != null &&
            hastaEscrita >= plan.hastaMesaMinima! &&
            _problemaDeHasta(plano!, hastaEscrita) == null);
    final avisosPlano = <String>[
      ...?plan?.avisos,
      if (plano != null)
        for (final (a, b) in Divisiones.parecidas(_orden))
          'Las divisiones "$a" y "$b" parecen la misma escrita distinto: '
              'corregilo en Editar alumno para que vayan en el mismo bloque.',
    ];
    final hayAvisos = widget.avisos.isNotEmpty || avisosPlano.isNotEmpty;
    // Con "Cumplimiento debido": no hay "hasta qué mesa", y con el sorteo ya
    // hecho alcanza con que alguna familia cambie de mesa.
    final orden = _ordenPorCumplimiento;
    final reacomoda = orden != null && orden.sePuede && orden.cambian > 0;
    final puedeSortear = !_planoIlegible &&
        (orden == null
            ? !demanda.vacia &&
                (plan == null ? factible : plan.entra && hastaOk)
            : orden.sePuede &&
                (plan?.entra ?? false) &&
                (!demanda.vacia || reacomoda)) &&
        (!hayAvisos || _revisado);

    final activos = _activos;
    final conMesa = activos
        .where((a) =>
            MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).isNotEmpty)
        .length;
    final reservadosBaja = widget.alumnos
        .where((a) => a.esBajaTemporal)
        .fold<int>(
          0,
          (s, a) =>
              s + MesasExtraUtils.numerosMesaDesdeTexto(a.numeroMesa).length,
        );
    final conMesasExtra =
        activos.where((a) => SalonMesas.mesasExtra(a) > 0).toList();
    final conSillasExtra =
        activos.where((a) => SalonMesas.sillasExtra(a) > 0).toList();
    final totalSillasExtra =
        conSillasExtra.fold<int>(0, (s, a) => s + SalonMesas.sillasExtra(a));
    final nuevosIds = {
      for (final p in pedidos)
        if (p.esNuevo) p.alumnoId,
    };
    // Los que ya tienen mesa y les falta otra (la compraron después).
    final faltanDe = {
      for (final p in pedidos)
        if (!p.esNuevo && p.faltan > 0) p.alumnoId: p.faltan,
    };
    final conMasDeTres = [
      for (final p in pedidos)
        if (p.esNuevo && p.mesas > kMesasJuntasEnElSorteo) p.alumnoId,
    ];
    final alFinal = _alFinal;

    return AlertDialog(
      title: const Text('Sorteo de mesas'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.tituloInstitucion,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (widget.novedad != null) ...[
                const SizedBox(height: 10),
                _Recuadro(
                  color: Colors.blue,
                  icono: Icons.sync_rounded,
                  child: Text(widget.novedad!),
                ),
              ],
              if (!_candidatos.vacio) ...[
                const SizedBox(height: 12),
                _preguntaPorPago(),
              ],
              const SizedBox(height: 12),
              _Recuadro(
                color: Colors.indigo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reacomoda
                          ? 'Se reacomoda el salón'
                          : demanda.vacia
                              ? 'No queda nadie por sortear'
                              : 'Se van a sortear ${demanda.total} mesas',
                      key: const Key('sorteo_resumen'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (demanda.alumnosNuevos > 0)
                      Text(
                        '· ${demanda.mesasBase} mesas base y '
                        '${demanda.mesasExtras} extra para '
                        '${demanda.alumnosNuevos} alumno(s) sin mesa',
                      ),
                    if (demanda.alumnosACompletar > 0)
                      Text(
                        '· ${demanda.mesasACompletar} mesa(s) para completar a '
                        '${demanda.alumnosACompletar} alumno(s), sin mover las '
                        'que ya tienen',
                      ),
                    if (exclusion.sinMesa.isNotEmpty)
                      Text(
                        '· ${exclusion.sinMesa.length} alumno(s) sin nada '
                        'pagado: no se les sortea mesa',
                      ),
                    if (exclusion.soloBase.isNotEmpty)
                      Text(
                        '· ${exclusion.soloBase.length} con mesas extra sin '
                        'pagar: solo la mesa base',
                      ),
                    if (reacomoda)
                      Text(
                        '· ${orden.cambian == 1 ? '1 familia cambia' : '${orden.cambian} familias cambian'} '
                        'de mesa. Nadie pierde mesas.',
                        key: const Key('sorteo_reacomoda'),
                      )
                    else if (conMesa > 0)
                      Text('· $conMesa alumno(s) ya tienen mesa: se respetan'),
                    if (reservadosBaja > 0)
                      Text(
                        '· $reservadosBaja número(s) reservado(s) por alumnos '
                        'de baja',
                      ),
                    if (totalSillasExtra > 0)
                      Text(
                        '· $totalSillasExtra sillas extra '
                        '(${conSillasExtra.length} alumno(s)): van a la mesa '
                        'de su familia',
                      ),
                  ],
                ),
              ),
              if (_faltantes.isNotEmpty) ...[
                const SizedBox(height: 12),
                _preguntaPorLasQueFaltan(),
              ],
              if (hayAvisos) ...[
                const SizedBox(height: 12),
                _Recuadro(
                  color: Colors.amber.shade800,
                  icono: Icons.warning_amber_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Revisar antes de sortear',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      for (final a in widget.avisos)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${a.alumno}: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(text: a.detalle),
                              ],
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      for (final a in avisosPlano)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            a,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Ya revisé estos casos'),
                        value: _revisado,
                        onChanged: (v) => setState(() => _revisado = v == true),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (plano != null && plan != null)
                _seccionPlano(plano, plan, demanda.vacia)
              else if (_planoIlegible)
                _Recuadro(
                  color: Colors.red,
                  icono: Icons.error_outline_rounded,
                  child: Text(
                    'El plano de esta fiesta no se puede leer. Cerrá esta '
                    'ventana, abrí PLANO y elegí el armado de nuevo antes de '
                    'sortear.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade800,
                    ),
                  ),
                )
              else
                TextField(
                  controller: _capacidadCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Capacidad del salón (mesas numeradas)',
                    helperText: 'Mínimo $minima para que entre todo.',
                    border: const OutlineInputBorder(),
                    errorText: demanda.vacia || factible
                        ? null
                        : 'Con esta capacidad no entran: mínimo $minima',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              // Con "Cumplimiento debido" no hay "lejos": la adicional va
              // detrás de su principal, o al final.
              if (conMesasExtra.isNotEmpty && !_cumplimiento) ...[
                const SizedBox(height: 16),
                _Titulo('Con mesas extra (${conMesasExtra.length})'),
                Text(
                  _alFinalActivo
                      ? 'Las adicionales van al final, después de las mesas de '
                          'todas las familias. Si una familia pidió estar '
                          'junta, tocá "Dejar juntas".'
                      : 'Van todas juntas. Si alguien pidió separarlas, tildalo y '
                          'elegí cuántas quedan lejos de su bloque y qué tan lejos.',
                  key: const Key('con_mesas_extra_explica'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (conMasDeTres.isNotEmpty && !_alFinalActivo) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const Key('aviso_mas_de_tres'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Text(
                      '${conMasDeTres.length == 1 ? '1 familia' : '${conMasDeTres.length} familias'} '
                      'con más de $kMesasJuntasEnElSorteo mesas: la principal y '
                      '2 adicionales van juntas, y las de más, lejos. Podés '
                      'destildarlas o elegir dónde.',
                      style: TextStyle(fontSize: 13, color: Colors.brown.shade800),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                for (final a in conMesasExtra)
                  _FilaMesasExtra(
                    alumno: a,
                    pagoMesas: _pago(a).mesas,
                    bloqueo: exclusion.sinMesa.contains(a.id)
                        ? 'no se sortea: sin nada pagado de la cuota base'
                        : exclusion.soloBase.contains(a.id)
                        ? 'solo mesa base: mesas extra sin pagar'
                        : nuevosIds.contains(a.id) || faltanDe.containsKey(a.id)
                        ? null
                        : 'ya tiene ${SalonMesas.textoMesas(a)}',
                    separadas: _separaciones[a.id],
                    distancia: _distancias[a.id] ?? DistanciaLejos.cerca,
                    onCambiar: (v) => _cambiarSeparacion(a.id, v),
                    onDistancia: (v) => _cambiarDistancia(a.id, v),
                    faltan: faltanDe[a.id] ?? 0,
                    conPlano: plano != null,
                    // Con "Al final", la familia sin mesa no se tilda "lejos":
                    // elige si queda junta.
                    alFinal: _alFinalActivo && nuevosIds.contains(a.id)
                        ? alFinal[a.id] ?? 0
                        : null,
                    dejarJuntas: _dejarJuntas.contains(a.id),
                    onDejarJuntas: (v) => _alternar(_dejarJuntas, a.id, v),
                    zona: _zonas[a.id] ?? const {},
                    onElegirZona: plano == null
                        ? null
                        : () => _elegirZona(
                              a,
                              faltanDe[a.id] ??
                                  MesasExtraUtils.cantidadAlejadasEfectivas(
                                    SalonMesas.mesas(a),
                                    _separaciones[a.id] ?? 1,
                                  ),
                            ),
                  ),
              ],
              if (conSillasExtra.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Titulo('Con sillas extra (${conSillasExtra.length})'),
                for (final a in conSillasExtra)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.chair_alt_outlined, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.nombreAlumno,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${SalonMesas.textoRepartoSillas(a)}'
                          '${_pago(a).pagoSillas ? '' : ' · sin pagar'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _pago(a).pagoSillas
                                ? null
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        ElevatedButton(
          onPressed: puedeSortear
              ? () => Navigator.pop(
                    context,
                    SorteoMesasDialogResult(
                      capacidadSalon: capacidad ?? 0,
                      // Con "Cumplimiento debido" el lugar lo decide el orden:
                      // no viajan los "lejos", las zonas ni "hasta qué mesa".
                      separaciones: _cumplimiento
                          ? const {}
                          : Map<String, int>.from(_separacionesQueValen),
                      distancias:
                          _cumplimiento ? const {} : _distanciasQueValen,
                      soloPagado: _soloPagado,
                      incluirBase: Set<String>.from(_incluirBase),
                      incluirExtras: Set<String>.from(_incluirExtras),
                      modo: plano == null ? null : _modo,
                      ordenDivisiones: List<String>.from(_orden),
                      usarPasto: _usarPasto,
                      hastaMesa: plano == null || _cumplimiento
                          ? null
                          : hastaEscrita,
                      zonas: plano == null || _cumplimiento
                          ? const {}
                          : _zonasElegidas,
                      mesasNuevasAlFondo:
                          plano != null && _alFondo && !_cumplimiento,
                      adicionalesAlFinal: _alFinalActivo,
                      juntasConLaPrincipal: _juntasConLaPrincipal,
                      dejarJuntas: _cumplimiento
                          ? const {}
                          : Set<String>.from(_dejarJuntas),
                      alFinal: _alFinal,
                      porCumplimiento: _cumplimiento,
                      recorrido: _recorrido,
                    ),
                  )
              : null,
          child: const Text('SORTEAR'),
        ),
      ],
    );
  }

  /// Por qué no vale la mesa escrita en "Usar de la mesa 1 a la". Null si
  /// vale. Sin esto, una mesa que el salón no tiene se ignoraba en silencio y
  /// el sorteo usaba la mínima.
  String? _problemaDeHasta(PlanoEvento plano, int hasta) {
    // Con las mesas nuevas, si las hay: "hasta la mesa" puede ser una de ellas.
    final armado = _armado;
    if (!armado.existe(hasta)) return 'La mesa $hasta no está en este salón.';
    if (!_usarPasto && armado.pasto.contains(hasta)) {
      return 'La mesa $hasta es del pasto.';
    }
    return null;
  }

  /// Con plano: cómo se sortea sobre el salón.
  ///
  /// - Por división: cada una en un bloque de mesas seguidas, en el orden de la
  ///   lista (se cambia con las flechas, A-Z o al azar).
  /// - Toda la escuela junta: "de la mesa 1 a la N", con la N mínima propuesta.
  /// - El pasto solo se ofrece si hace falta (o si ya se tildó).
  Widget _seccionPlano(PlanoEvento plano, PlanSorteo plan, bool nadaQueSortear) {
    final armado = plano.armado;
    final pasto = armado.pasto.toList()..sort();
    final porClave = {for (final f in plan.bloques) f.clave: f};
    final bloquesGuardados = plano.config.bloques.isNotEmpty &&
        plan.modo == ModoSorteo.bloques;
    final hasta = int.tryParse(_hastaCtrl.text.trim());
    final minima = plan.hastaMesaMinima;

    Widget chip(String texto, ModoSorteo modo) => ChoiceChip(
          label: Text(texto),
          selected: _modo == modo,
          onSelected: (_) => _cambiar(() => _modo = modo),
        );

    // Solo se dibujan las divisiones que tienen familias para sortear, así
    // que las flechas saltan a la vecina que se ve: moviendo de a un lugar en
    // la lista entera, "Subir" a veces no hacía nada a la vista.
    final visibles = [
      for (var i = 0; i < _orden.length; i++)
        if (porClave.containsKey(_orden[i])) i,
    ];
    void mover(int i, int delta) => _cambiar(() {
          final k = visibles.indexOf(i) + delta;
          if (k < 0 || k >= visibles.length) return;
          final j = visibles[k];
          final x = _orden.removeAt(i);
          _orden.insert(j, x);
        });

    return _Recuadro(
      color: Colors.deepPurple,
      icono: Icons.grid_view_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Salón: ${armado.nombre}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (_ofreceCumplimiento) ..._elCumplimiento(),
          const SizedBox(height: 8),
          // Con "Cumplimiento debido" va toda la escuela junta.
          if (!_cumplimiento)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                chip('Por división, cada una junta', ModoSorteo.bloques),
                chip('Toda la escuela junta', ModoSorteo.entera),
              ],
            ),
          if (plan.modoForzado && !_cumplimiento) ...[
            const SizedBox(height: 8),
            Text(
              'Ya hay mesas repartidas y el plano no tiene bloques guardados: '
              'se completa entero, sin mover a nadie.',
              style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
            ),
          ],
          if (_hayAdicionalesPorSortear) ..._lasAdicionales(plan),
          if (plan.modo == ModoSorteo.bloques && !_cumplimiento) ...[
            const SizedBox(height: 10),
            if (bloquesGuardados)
              Text(
                'El sorteo por bloques ya se hizo: los que faltan van a los '
                'huecos de su bloque.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Orden de los bloques, desde la mesa 1:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _cambiar(
                      () => _orden = Divisiones.ordenNatural(_orden),
                    ),
                    child: const Text('A-Z'),
                  ),
                  TextButton(
                    onPressed: () => _cambiar(
                      () => _orden = [..._orden]..shuffle(Random.secure()),
                    ),
                    child: const Text('AL AZAR'),
                  ),
                ],
              ),
            for (var i = 0; i < _orden.length; i++)
              if (porClave[_orden[i]] case final f?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          f.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          '${f.familias} familia${f.familias == 1 ? '' : 's'} · '
                          '${f.mesas} mesa${f.mesas == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          !f.entra
                              ? 'no entra'
                              : f.enReserva
                                  ? 'fuera de su bloque'
                                  : f.desde == null
                                      ? ''
                                      : 'mesas ${f.texto}'
                                          '${f.usaPasto ? ' (con pasto)' : ''}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: !f.entra
                                ? Colors.red.shade700
                                : f.enReserva
                                    ? Colors.orange.shade900
                                    : Colors.deepPurple,
                          ),
                        ),
                      ),
                      if (!bloquesGuardados) ...[
                        IconButton(
                          tooltip: 'Subir',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          onPressed:
                              i == visibles.first ? null : () => mover(i, -1),
                        ),
                        IconButton(
                          tooltip: 'Bajar',
                          visualDensity: VisualDensity.compact,
                          icon:
                              const Icon(Icons.arrow_downward_rounded, size: 18),
                          onPressed: i == visibles.last
                              ? null
                              : () => mover(i, 1),
                        ),
                      ],
                    ],
                  ),
                ),
          ],
          if (plan.modo == ModoSorteo.entera && !_cumplimiento) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _hastaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: plan.mesasAlFinal > 0
                    ? 'Las de adelante, de la mesa 1 a la'
                    : 'Usar de la mesa 1 a la',
                helperText: minima == null
                    ? null
                    : plan.mesasAlFinal > 0
                        ? 'Mínimo la $minima para que entren las de adelante.'
                        : 'Mínimo la $minima para que entre todo.',
                border: const OutlineInputBorder(),
                errorText: nadaQueSortear || minima == null
                    ? null
                    : hasta == null || hasta < minima
                        ? 'Con esas mesas no entran: mínimo la $minima'
                        : _problemaDeHasta(plano, hasta),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (pasto.isNotEmpty && (plan.necesitaPasto || _usarPasto))
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Usar las mesas del pasto (${pasto.first} a ${pasto.last})',
              ),
              subtitle: plan.necesitaPasto && !_usarPasto
                  ? const Text('Sin el pasto no entran todas las familias.')
                  : const Text('Solo las que hagan falta; hay que avisar a esas '
                      'familias.'),
              value: _usarPasto,
              onChanged: (v) => _cambiar(() => _usarPasto = v == true),
            ),
          if (!plan.entra && !plan.necesitaPasto && !nadaQueSortear) ...[
            const SizedBox(height: 8),
            Text(
              'No entran todas las familias en este salón. Elegí otro armado en '
              'PLANO, o dejá menos mesas libres.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Alguna familia que todavía no tiene mesa trae adicionales para sortear:
  /// solo ahí tiene sentido preguntar dónde van. Con "Cumplimiento debido"
  /// vale también para quien ya tiene mesa: se reacomodan todas.
  bool get _hayAdicionalesPorSortear =>
      _pedidos.any((p) => p.esNuevo && p.mesas > 1) ||
      (_ordenPorCumplimiento?.lugares.values.any((l) => l.length > 1) ?? false);

  /// El tilde "Cumplimiento debido" (6.7.1) y, tildado, el recorrido. Va en el
  /// cartel y no en el plano: el salón se ve repartido recién al sortear.
  List<Widget> _elCumplimiento() {
    final orden = _ordenPorCumplimiento;
    final problema = orden?.problema;
    return [
      CheckboxListTile(
        key: const Key('por_cumplimiento'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'Cumplimiento debido',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          problema ?? 'Las mejores mesas, para quien mejor cumplió.',
          key: const Key('por_cumplimiento_dice'),
          style: problema == null
              ? null
              : TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
        ),
        value: _porCumplimiento,
        onChanged: (v) => _cambiar(() {
          _porCumplimiento = v == true;
          // Por división todavía no: tildado, va toda la escuela junta.
          if (_porCumplimiento) _modo = ModoSorteo.entera;
        }),
      ),
      // Las mismas pastillas con tilde que el resto del cartel: en un botón de
      // dos partes, sobre este fondo, no se notaba cuál estaba elegido.
      if (_cumplimiento)
        Padding(
          key: const Key('cumplimiento_recorrido'),
          padding: const EdgeInsets.only(left: 40),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final r in RecorridoDelOrden.values)
                ChoiceChip(
                  key: Key('cumplimiento_${r.clave}'),
                  label: Text(r.rotulo),
                  selected: _recorrido == r,
                  onSelected: (_) => _cambiar(() => _recorrido = r),
                ),
            ],
          ),
        ),
    ];
  }

  /// "Las mesas adicionales: Con su familia · Al final" (6.6.1, pedido del
  /// jefe el 11-nov-2026). Va debajo de cómo se sortea porque es una decisión
  /// de todo el sorteo y cambia los números que el cartel muestra ahí mismo.
  /// Viene en "Con su familia": sin tocar nada, se sortea como siempre.
  List<Widget> _lasAdicionales(PlanSorteo plan) {
    // Lo que eligió el jefe, no lo que quedó: si el sorteo se completa entero
    // a la fuerza, la opción se prende eligiendo "Toda la escuela junta".
    final entera = _modo == ModoSorteo.entera;
    final gris = TextStyle(fontSize: 12.5, color: Colors.grey.shade800);
    final desde = plan.alFinalDesde, hasta = plan.alFinalHasta;
    return [
      const SizedBox(height: 12),
      const Text(
        'Las mesas adicionales',
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          ChoiceChip(
            key: const Key('adicionales_con_su_familia'),
            label: const Text('Con su familia'),
            selected: !_alFinalActivo,
            onSelected: entera
                ? (_) => _cambiar(() => _adicionalesAlFinal = false)
                : null,
          ),
          ChoiceChip(
            key: const Key('adicionales_al_final'),
            label: const Text('Al final, después de las principales'),
            selected: _alFinalActivo,
            onSelected: entera
                ? (_) => _cambiar(() => _adicionalesAlFinal = true)
                : null,
          ),
        ],
      ),
      if (!entera) ...[
        const SizedBox(height: 4),
        Text(
          'Para mandarlas al final, elegí "Toda la escuela junta": por '
          'división, cada bloque es de su división.',
          key: const Key('adicionales_motivo'),
          style: gris,
        ),
      ] else if (!_alFinalActivo) ...[
        const SizedBox(height: 4),
        Text(
          'Cada familia queda con todas sus mesas juntas, como siempre.',
          key: const Key('adicionales_explica'),
          style: gris,
        ),
      ] else ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Quedan pegadas a la principal:', style: gris),
            SegmentedButton<int>(
              key: const Key('adicionales_juntas'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: 0, label: Text('Ninguna')),
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
              ],
              selected: {_juntasConLaPrincipal},
              onSelectionChanged: (s) =>
                  _cambiar(() => _juntasConLaPrincipal = s.first),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_cumplimiento)
          Text(
            'Primero todas las principales; después, las adicionales.',
            key: const Key('adicionales_por_cumplimiento'),
            style: gris,
          )
        else ...[
        Text(
          plan.mesasAlFinal == 0
              ? 'Con lo elegido, ninguna mesa va al final: cada familia queda '
                  'con todas las suyas juntas.'
              : !plan.entra || desde == null || hasta == null
                  ? '${plan.mesasAlFinal == 1 ? '1 mesa va' : '${plan.mesasAlFinal} mesas van'} '
                      'al final, y no entran después de las de adelante.'
                  : 'Adelante: de la 1 a la ${plan.hastaMesa} · Al final: '
                      '${desde == hasta ? 'la $desde' : 'de la $desde a la $hasta'} '
                      '(${plan.mesasAlFinal == 1 ? '1 mesa' : '${plan.mesasAlFinal} mesas'}).',
          key: const Key('adicionales_rangos'),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: plan.mesasAlFinal > 0 && !plan.entra
                ? Colors.red.shade700
                : Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Las del final se sortean entre ellas. Si una familia pidió estar '
          'junta, tocá "Dejar juntas" en su renglón, más abajo.',
          style: gris,
        ),
        ],
      ],
    ];
  }

  /// "¿Dónde van las mesas que faltan?" (6.5.1): con el sorteo ya hecho, quien
  /// llega después recibe una mesa nueva al fondo, con el número que sigue, o
  /// una de las que quedaron libres en el salón. Abajo dice qué número le toca
  /// a cada uno, antes de sortear.
  Widget _preguntaPorLasQueFaltan() {
    final nuevas = _nuevas;
    final nombres = {
      for (final a in widget.alumnos) a.id: CambiosDeMesa.apellido(a),
    };
    final total = _faltantes.values.fold<int>(0, (s, n) => s + n);
    return _Recuadro(
      key: const Key('faltan_donde'),
      color: Colors.deepPurple,
      icono: Icons.add_location_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total == 1
                ? '¿Dónde va la mesa que falta?'
                : '¿Dónde van las $total mesas que faltan?',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                key: const Key('faltan_al_fondo'),
                label: Text(
                  total == 1
                      ? 'En una mesa nueva, al fondo'
                      : 'En mesas nuevas, al fondo',
                ),
                selected: _alFondo,
                onSelected: (_) => _cambiar(() => _alFondo = true),
              ),
              ChoiceChip(
                key: const Key('faltan_en_libres'),
                label: const Text('En las mesas libres del salón'),
                selected: !_alFondo,
                onSelected: (_) => _cambiar(() => _alFondo = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (nuevas != null) ...[
            Text(
              nuevas.mesas.length == 1
                  ? 'Se agrega 1 mesa al plano, al fondo a la derecha, con el '
                      'número que sigue:'
                  : 'Se agregan ${nuevas.mesas.length} mesas al plano, al '
                      'fondo a la derecha, con los números que siguen, por '
                      'orden de llegada:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 4),
            Text(
              [
                for (final e in nuevas.porAlumno.entries)
                  '${e.value.join(', ')} → ${nombres[e.key] ?? 'una familia'}',
              ].join('  ·  '),
              key: const Key('faltan_numeros'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Nadie más cambia de mesa.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
          ] else
            Text(
              'Van en mesas que ya están en el salón y quedaron libres, sin '
              'mover a nadie.',
              key: const Key('faltan_en_libres_explica'),
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
            ),
        ],
      ),
    );
  }

  /// "¿A quién se le sortea?": lo pagado, o todo lo cargado como antes. Con lo
  /// pagado, las dos listas de quienes quedan afuera, cada uno con su casilla
  /// para sortearlo igual.
  Widget _preguntaPorPago() {
    final sinBase = _candidatos.sinPagoBase;
    final sinExtras = _candidatos.sinPagoMesasExtra;
    return _Recuadro(
      color: Colors.teal,
      icono: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿A quién se le sortea?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Solo a lo que tiene algo pagado'),
                selected: _soloPagado,
                onSelected: (_) => _cambiar(() => _soloPagado = true),
              ),
              ChoiceChip(
                label: const Text('A todo lo cargado'),
                selected: !_soloPagado,
                onSelected: (_) => _cambiar(() => _soloPagado = false),
              ),
            ],
          ),
          if (_soloPagado) ...[
            const SizedBox(height: 8),
            Text(
              'Lo cargado sigue en la cuenta de cada uno. Tildá a quien quieras '
              'sortear igual (por ejemplo, pagó y todavía no se cargó). Si pagan '
              'después, "Sortear" de nuevo les da la mesa sin mover a nadie.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (sinBase.isNotEmpty)
              _ListaPorPago(
                titulo: 'Sin nada pagado de la cuota base '
                    '(${sinBase.length}): no se les sortea mesa',
                alumnos: sinBase,
                detalle: (a) {
                  final base = (a.montoTotalPactado -
                          a.mesaExtraPrecio -
                          a.sillasExtraPrecioTotal)
                      .clamp(0.0, double.infinity);
                  final conExtras =
                      _candidatos.sinPagoBaseConExtras.contains(a.id);
                  return '\$0 de ${base.toCurrency()}'
                      '${conExtras ? ' · mesa extra sin pagar: va solo con la base' : ''}';
                },
                incluidos: _incluirBase,
                onCambiar: (id, v) => _alternar(_incluirBase, id, v),
              ),
            if (sinExtras.isNotEmpty)
              _ListaPorPago(
                titulo: 'Con mesas extra sin nada pagado '
                    '(${sinExtras.length}): solo mesa base',
                alumnos: sinExtras,
                detalle: (a) {
                  final n = SalonMesas.mesasExtra(a);
                  return '${n == 1 ? '1 mesa extra' : '$n mesas extra'} · '
                      '\$0 de ${a.mesaExtraPrecio.toCurrency()}';
                },
                incluidos: _incluirExtras,
                onCambiar: (id, v) => _alternar(_incluirExtras, id, v),
              ),
          ],
        ],
      ),
    );
  }
}

/// Lista desplegable de los que quedan afuera por no tener nada pagado. La
/// casilla tildada es "sortear igual".
class _ListaPorPago extends StatelessWidget {
  final String titulo;
  final List<ContratoAlumno> alumnos;
  final String Function(ContratoAlumno) detalle;
  final Set<String> incluidos;
  final void Function(String id, bool incluir) onCambiar;

  const _ListaPorPago({
    required this.titulo,
    required this.alumnos,
    required this.detalle,
    required this.incluidos,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final igual = alumnos.where((a) => incluidos.contains(a.id)).length;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        titulo,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: igual > 0
          ? Text(
              '$igual tildado(s) para sortear igual',
              style: const TextStyle(fontSize: 12),
            )
          : null,
      children: [
        for (final a in alumnos)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(a.nombreAlumno, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              detalle(a),
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            secondary: incluidos.contains(a.id)
                ? const Text(
                    'se sortea igual',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  )
                : null,
            value: incluidos.contains(a.id),
            onChanged: (v) => onCambiar(a.id, v == true),
          ),
      ],
    );
  }
}

class _FilaMesasExtra extends StatelessWidget {
  final ContratoAlumno alumno;
  final double pagoMesas;

  /// Por qué a este alumno no se le sortean las mesas extra ahora (ya las tiene,
  /// o no pagó). `null` si se sortean: ahí se puede pedir separarlas.
  final String? bloqueo;
  final int? separadas;
  final DistanciaLejos distancia;
  final ValueChanged<int?> onCambiar;
  final ValueChanged<DistanciaLejos> onDistancia;

  /// Si ya tiene mesa y le faltan (compró otra después del sorteo): cuántas.
  /// Cero si es una familia nueva.
  final int faltan;

  /// Con plano se puede elegir la zona ([DistanciaLejos.enLaZona]).
  final bool conPlano;

  /// Las mesas de la zona elegida.
  final Set<int> zona;
  final VoidCallback? onElegirZona;

  /// Con "Las mesas adicionales: Al final" (6.6.1) y una familia sin mesa:
  /// cuántas de las suyas van al final (0 si quedan todas juntas). Null si la
  /// opción no está elegida o no le toca: ahí el renglón es el de siempre.
  final int? alFinal;

  /// Tildada "dejar juntas": queda entera, adelante.
  final bool dejarJuntas;
  final ValueChanged<bool>? onDejarJuntas;

  const _FilaMesasExtra({
    required this.alumno,
    required this.pagoMesas,
    required this.bloqueo,
    required this.separadas,
    required this.distancia,
    required this.onCambiar,
    required this.onDistancia,
    this.faltan = 0,
    this.conPlano = false,
    this.zona = const {},
    this.onElegirZona,
    this.alFinal,
    this.dejarJuntas = false,
    this.onDejarJuntas,
  });

  static const _ambar = Color(0xFF8A5A00);

  /// El renglón con "Al final": sin el tilde de "lejos". Dice dónde va cada
  /// mesa y deja elegir que la familia quede junta.
  Widget _conAlFinal(int mesas, String detalle, int atras) {
    final adelante = mesas - atras;
    final String queda;
    if (atras == 0) {
      queda = 'Sus $mesas mesas van juntas, adelante.';
    } else {
      final cuales = adelante == 1
          ? 'La principal va adelante'
          : 'La principal y ${adelante - 1} '
              '${adelante == 2 ? 'adicional' : 'adicionales'} van juntas, '
              'adelante';
      final van = atras == 1
          ? 'la otra va al final'
          : 'las otras $atras van al final, juntas entre sí';
      queda = '$cuales; $van.';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alumno.nombreAlumno, overflow: TextOverflow.ellipsis),
                      Text(
                        detalle,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: Key('dejar_juntas_${alumno.id}'),
                  label: const Text('Dejar juntas'),
                  selected: dejarJuntas,
                  onSelected: onDejarJuntas,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              queda,
              key: Key('explicacion_al_final_${alumno.id}'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _ambar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mesas = SalonMesas.mesas(alumno);
    final extras = mesas - 1;
    final sillas = SalonMesas.sillasExtra(alumno);
    final sortea = bloqueo == null;
    final pagadas = pagoMesas >= alumno.mesaExtraPrecio - 0.01;
    final completa = faltan > 0;
    final detalle = [
      '$extras extra · $mesas en total',
      if (sillas > 0) '$sillas silla(s) extra',
      pagadas
          ? 'pagadas'
          : 'pagó ${pagoMesas.toCurrency()} de '
              '${alumno.mesaExtraPrecio.toCurrency()}',
      if (completa)
        'ya tiene ${SalonMesas.textoMesas(alumno)} · le '
            '${faltan == 1 ? 'falta 1' : 'faltan $faltan'}',
      ?bloqueo,
    ].join(' · ');
    final atras = alFinal;
    if (atras != null && sortea && !completa) {
      return _conAlFinal(mesas, detalle, atras);
    }
    final marcado = separadas != null;
    final lejos = completa ? faltan : (separadas ?? 0).clamp(1, extras);
    final masDeTres = !completa && mesas > kMesasJuntasEnElSorteo;

    // Lo que va a pasar, en palabras: la principal y cuántas juntas, cuántas
    // lejos (6.5.0).
    String explicacion() {
      if (completa) {
        return faltan == 1
            ? 'La que le falta va lejos de las suyas.'
            : 'Las $faltan que le faltan van lejos de las suyas.';
      }
      final juntas = mesas - lejos;
      final cuales = juntas == 1
          ? 'La principal'
          : 'La principal y ${juntas - 1} '
              '${juntas == 2 ? 'adicional' : 'adicionales'} juntas';
      final van = lejos == 1 ? 'la otra va lejos' : 'las otras $lejos van lejos';
      return '$cuales; $van.';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(alumno.nombreAlumno, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                detalle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              value: sortea && marcado,
              onChanged: sortea
                  ? (v) => onCambiar(v == true ? 1 : null)
                  : null,
              secondary: sortea
                  ? null
                  : Tooltip(
                      message: bloqueo!,
                      child: const Icon(Icons.lock_outline, size: 18),
                    ),
            ),
            if (sortea && marcado)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  explicacion(),
                  key: Key('explicacion_lejos_${alumno.id}'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _ambar,
                  ),
                ),
              ),
            if (sortea && !marcado && masDeTres)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: Text(
                  'Más de $kMesasJuntasEnElSorteo mesas, destildada: van todas '
                  'juntas.',
                  key: Key('explicacion_lejos_${alumno.id}'),
                  style: const TextStyle(fontSize: 12, color: _ambar),
                ),
              ),
            if (sortea && marcado && !completa)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    const Text('Separadas:'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      key: Key('separadas_${alumno.id}'),
                      value: separadas!.clamp(1, extras),
                      items: [
                        for (var k = 1; k <= extras; k++)
                          DropdownMenuItem(value: k, child: Text('$k')),
                      ],
                      onChanged: (v) {
                        if (v != null) onCambiar(v);
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _resumen(mesas, separadas!.clamp(1, extras)),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (sortea && marcado)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    const Text('Qué tan lejos:'),
                    const SizedBox(width: 12),
                    DropdownButton<DistanciaLejos>(
                      key: Key('distancia_lejos_${alumno.id}'),
                      value: distancia,
                      items: [
                        for (final d in DistanciaLejos.values)
                          if (conPlano || d != DistanciaLejos.enLaZona)
                            DropdownMenuItem(value: d, child: Text(d.rotulo)),
                      ],
                      onChanged: (v) {
                        if (v != null) onDistancia(v);
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        switch (distancia) {
                          DistanciaLejos.cerca =>
                            'Una mesa de por medio, sin tocarse.',
                          DistanciaLejos.aUnasMesas =>
                            'Otra zona, a la vista.',
                          DistanciaLejos.bienLejos =>
                            'La otra punta del salón, o de su bloque.',
                          DistanciaLejos.enLaZona =>
                            'En las mesas que marques en el plano.',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (sortea && marcado && distancia == DistanciaLejos.enLaZona)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: Key('elegir_zona_${alumno.id}'),
                      onPressed: onElegirZona,
                      icon: const Icon(Icons.touch_app_outlined, size: 18),
                      label: const Text('ELEGIR EN EL PLANO'),
                    ),
                    Text(
                      zona.isEmpty
                          ? 'Ninguna elegida todavía: van bien lejos.'
                          : '${zona.length == 1 ? '1 mesa elegida' : '${zona.length} mesas elegidas'}: '
                              '${(zona.toList()..sort()).join(', ')}',
                      key: Key('zona_elegida_${alumno.id}'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _resumen(int mesas, int separadas) {
    final juntas = mesas - separadas;
    final lejos = separadas == 1 ? '1 lejos' : '$separadas lejos, sin tocarse';
    return juntas == 1 ? '1 + $lejos' : '$juntas juntas + $lejos';
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          texto,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      );
}

class _Recuadro extends StatelessWidget {
  final Color color;
  final IconData? icono;
  final Widget child;

  const _Recuadro({
    super.key,
    required this.color,
    required this.child,
    this.icono,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: icono == null
            ? child
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icono, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: child),
                ],
              ),
      );
}
