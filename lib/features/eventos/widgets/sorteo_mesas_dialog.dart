import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../services/mesas_extra_utils.dart';
import '../services/salon_mesas.dart';
import '../services/sorteo_mesas_motor.dart';

/// Diálogo previo al sorteo: qué se va a sortear, quién tiene mesas y sillas
/// extra, qué conviene revisar y con qué capacidad.
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
  SorteoMesasDialogResult? inicial,
  String? novedad,
}) {
  return showDialog<SorteoMesasDialogResult>(
    context: context,
    builder: (context) => _SorteoMesasDialog(
      tituloInstitucion: tituloInstitucion,
      alumnos: alumnos,
      avisos: avisos,
      inicial: inicial,
      novedad: novedad,
    ),
  );
}

class _SorteoMesasDialog extends StatefulWidget {
  final String tituloInstitucion;
  final List<ContratoAlumno> alumnos;
  final List<AvisoSalon> avisos;
  final SorteoMesasDialogResult? inicial;
  final String? novedad;

  const _SorteoMesasDialog({
    required this.tituloInstitucion,
    required this.alumnos,
    required this.avisos,
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
  bool _revisado = false;

  List<ContratoAlumno> get _activos =>
      widget.alumnos.where((a) => !a.esBajaTemporal).toList();

  List<PedidoSorteo> get _pedidos => SorteoMesasMotor.pedidos(
        widget.alumnos,
        separaciones: _separaciones,
      );

  int _minima(List<PedidoSorteo> pedidos) =>
      SorteoMesasMotor.capacidadMinima(pedidos: pedidos, ocupadas: _ocupadas);

  @override
  void initState() {
    super.initState();
    _ocupadas = SorteoMesasMotor.ocupadas(widget.alumnos);
    _separaciones = Map<String, int>.from(widget.inicial?.separaciones ?? {});
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

  /// Si separar sube el mínimo, la capacidad escrita sube con él.
  void _cambiarSeparacion(String alumnoId, int? cantidad) {
    setState(() {
      if (cantidad == null || cantidad < 1) {
        _separaciones.remove(alumnoId);
      } else {
        _separaciones[alumnoId] = cantidad;
      }
      final minima = _minima(_pedidos);
      final actual = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
      if (actual < minima) _capacidadCtrl.text = '$minima';
    });
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 12),
              _Recuadro(
                color: Colors.indigo,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demanda.vacia
                          ? 'Todos los alumnos ya tienen su mesa'
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
                    sortea: nuevosIds.contains(a.id),
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
                          SalonMesas.textoRepartoSillas(a),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
                    ),
                  )
              : null,
          child: const Text('SORTEAR'),
        ),
      ],
    );
  }
}

class _FilaMesasExtra extends StatelessWidget {
  final ContratoAlumno alumno;

  /// false si ya tiene sus mesas: se muestra, pero no se sortea.
  final bool sortea;
  final int? separadas;
  final ValueChanged<int?> onCambiar;

  const _FilaMesasExtra({
    required this.alumno,
    required this.sortea,
    required this.separadas,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final mesas = SalonMesas.mesas(alumno);
    final extras = mesas - 1;
    final sillas = SalonMesas.sillasExtra(alumno);
    final detalle = [
      '$extras extra · $mesas en total',
      if (sillas > 0) '$sillas silla(s) extra',
      if (!sortea) 'ya tiene ${SalonMesas.textoMesas(alumno)}',
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
              value: marcado,
              onChanged: sortea
                  ? (v) => onCambiar(v == true ? 1 : null)
                  : null,
              secondary: sortea
                  ? null
                  : const Tooltip(
                      message: 'Ya tiene sus mesas: el sorteo no las mueve',
                      child: Icon(Icons.lock_outline, size: 18),
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
