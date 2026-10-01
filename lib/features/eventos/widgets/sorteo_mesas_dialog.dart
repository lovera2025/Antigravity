import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../../common/utils/currency_extensions.dart';
import '../../plano/services/divisiones.dart';
import '../../plano/services/sorteo_con_plano.dart';
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
    ),
  );
}

@visibleForTesting
class SorteoMesasDialog extends StatefulWidget {
  final String tituloInstitucion;
  final List<ContratoAlumno> alumnos;
  final List<AvisoSalon> avisos;
  final Map<String, PagoAlumno> pagos;
  final SorteoMesasDialogResult? inicial;
  final String? novedad;
  final PlanoEvento? plano;

  const SorteoMesasDialog({
    super.key,
    required this.tituloInstitucion,
    required this.alumnos,
    required this.avisos,
    required this.pagos,
    this.inicial,
    this.novedad,
    this.plano,
  });

  @override
  State<SorteoMesasDialog> createState() => _SorteoMesasDialogState();
}

class _SorteoMesasDialogState extends State<SorteoMesasDialog> {
  late final TextEditingController _capacidadCtrl;
  late final Map<String, int> _separaciones;
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

  EntradaSorteoPlano _entrada() => EntradaSorteoPlano(
        armado: _plano!.armado,
        config: _plano!.config,
        alumnos: widget.alumnos,
        exclusion: _exclusion,
        separaciones: _separaciones,
        modo: _modo,
        ordenDivisiones: _orden,
        usarPasto: _usarPasto,
        hastaMesa: int.tryParse(_hastaCtrl.text.trim()),
      );

  /// Lo que va a hacer el sorteo sobre el plano. Se recalcula solo si cambió
  /// algo que lo decide (tildar "ya revisé" no lo recalcula).
  PlanSorteo _plan() {
    final ex = _exclusion;
    final clave = [
      _modo.name,
      _orden.join(','),
      _usarPasto,
      _hastaCtrl.text.trim(),
      (ex.sinMesa.toList()..sort()).join(','),
      (ex.soloBase.toList()..sort()).join(','),
      (_separaciones.entries.map((e) => '${e.key}=${e.value}').toList()..sort())
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
    _candidatos = candidatosPorPago(widget.alumnos, widget.pagos);
    _soloPagado = widget.inicial?.soloPagado ?? true;
    _incluirBase = {...?widget.inicial?.incluirBase};
    _incluirExtras = {...?widget.inicial?.incluirExtras};
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
        } else {
          _separaciones[alumnoId] = cantidad;
        }
      });

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
    final puedeSortear = !_planoIlegible &&
        !demanda.vacia &&
        (plan == null ? factible : plan.entra && hastaOk) &&
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
                      demanda.vacia
                          ? 'No queda nadie por sortear'
                          : 'Se van a sortear ${demanda.total} mesas',
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
                    if (conMesa > 0)
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
              if (conMesasExtra.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Titulo('Con mesas extra (${conMesasExtra.length})'),
                Text(
                  'Van todas juntas. Si alguien pidió separarlas, tildalo y '
                  'elegí cuántas quedan lejos de su bloque.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                for (final a in conMesasExtra)
                  _FilaMesasExtra(
                    alumno: a,
                    pagoMesas: _pago(a).mesas,
                    bloqueo: exclusion.sinMesa.contains(a.id)
                        ? 'no se sortea: sin nada pagado de la cuota base'
                        : exclusion.soloBase.contains(a.id)
                        ? 'solo mesa base: mesas extra sin pagar'
                        : nuevosIds.contains(a.id)
                        ? null
                        : 'ya tiene ${SalonMesas.textoMesas(a)}',
                    separadas: _separaciones[a.id],
                    onCambiar: (v) => _cambiarSeparacion(a.id, v),
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
                      separaciones: Map<String, int>.from(_separaciones),
                      soloPagado: _soloPagado,
                      incluirBase: Set<String>.from(_incluirBase),
                      incluirExtras: Set<String>.from(_incluirExtras),
                      modo: plano == null ? null : _modo,
                      ordenDivisiones: List<String>.from(_orden),
                      usarPasto: _usarPasto,
                      hastaMesa: plano == null ? null : hastaEscrita,
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
    final armado = plano.armado;
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
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              chip('Por división, cada una junta', ModoSorteo.bloques),
              chip('Toda la escuela junta', ModoSorteo.entera),
            ],
          ),
          if (plan.modoForzado) ...[
            const SizedBox(height: 8),
            Text(
              'Ya hay mesas repartidas y el plano no tiene bloques guardados: '
              'se completa entero, sin mover a nadie.',
              style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
            ),
          ],
          if (plan.modo == ModoSorteo.bloques) ...[
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
                                      : 'mesas ${f.desde} a ${f.hasta}'
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
          if (plan.modo == ModoSorteo.entera) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _hastaCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Usar de la mesa 1 a la',
                helperText:
                    minima == null ? null : 'Mínimo la $minima para que entre todo.',
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
  final ValueChanged<int?> onCambiar;

  const _FilaMesasExtra({
    required this.alumno,
    required this.pagoMesas,
    required this.bloqueo,
    required this.separadas,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final mesas = SalonMesas.mesas(alumno);
    final extras = mesas - 1;
    final sillas = SalonMesas.sillasExtra(alumno);
    final sortea = bloqueo == null;
    final pagadas = pagoMesas >= alumno.mesaExtraPrecio - 0.01;
    final detalle = [
      '$extras extra · $mesas en total',
      if (sillas > 0) '$sillas silla(s) extra',
      pagadas
          ? 'pagadas'
          : 'pagó ${pagoMesas.toCurrency()} de '
              '${alumno.mesaExtraPrecio.toCurrency()}',
      ?bloqueo,
    ].join(' · ');
    final marcado = separadas != null;

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
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    const Text('Separadas:'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
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

  const _Recuadro({required this.color, required this.child, this.icono});

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
