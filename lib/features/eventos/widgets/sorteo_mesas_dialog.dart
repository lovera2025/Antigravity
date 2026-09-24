import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../../common/utils/currency_extensions.dart';
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
Future<SorteoMesasDialogResult?> mostrarSorteoMesasDialog({
  required BuildContext context,
  required String tituloInstitucion,
  required List<ContratoAlumno> alumnos,
  required List<AvisoSalon> avisos,
  required Map<String, PagoAlumno> pagos,
  SorteoMesasDialogResult? inicial,
  String? novedad,
}) {
  return showDialog<SorteoMesasDialogResult>(
    context: context,
    builder: (context) => _SorteoMesasDialog(
      tituloInstitucion: tituloInstitucion,
      alumnos: alumnos,
      avisos: avisos,
      pagos: pagos,
      inicial: inicial,
      novedad: novedad,
    ),
  );
}

class _SorteoMesasDialog extends StatefulWidget {
  final String tituloInstitucion;
  final List<ContratoAlumno> alumnos;
  final List<AvisoSalon> avisos;
  final Map<String, PagoAlumno> pagos;
  final SorteoMesasDialogResult? inicial;
  final String? novedad;

  const _SorteoMesasDialog({
    required this.tituloInstitucion,
    required this.alumnos,
    required this.avisos,
    required this.pagos,
    this.inicial,
    this.novedad,
  });

  @override
  State<_SorteoMesasDialog> createState() => _SorteoMesasDialogState();
}

class _SorteoMesasDialogState extends State<_SorteoMesasDialog> {
  late final TextEditingController _capacidadCtrl;
  late final Map<String, int> _separaciones;
  late final Set<int> _ocupadas;
  late final CandidatosPorPago _candidatos;

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
  }

  @override
  void dispose() {
    _capacidadCtrl.dispose();
    super.dispose();
  }

  /// Aplica un cambio que mueve el mínimo. Si la capacidad escrita era la
  /// sugerida, sigue a la sugerida (sube o baja); si alguien la escribió a mano,
  /// solo sube cuando ya no alcanza.
  void _cambiar(VoidCallback cambio) {
    final antes = _minima(_pedidos);
    setState(() {
      cambio();
      final minima = _minima(_pedidos);
      final actual = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
      if (actual == antes || actual < minima) _capacidadCtrl.text = '$minima';
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
    final hayAvisos = widget.avisos.isNotEmpty;
    final puedeSortear =
        !demanda.vacia && factible && (!hayAvisos || _revisado);

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
                      capacidadSalon: capacidad,
                      separaciones: Map<String, int>.from(_separaciones),
                      soloPagado: _soloPagado,
                      incluirBase: Set<String>.from(_incluirBase),
                      incluirExtras: Set<String>.from(_incluirExtras),
                    ),
                  )
              : null,
          child: const Text('SORTEAR'),
        ),
      ],
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
