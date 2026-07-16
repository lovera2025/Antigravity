import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/contrato_alumno.dart';
import '../services/mesas_extra_utils.dart';

/// Diálogo previo al sorteo: demanda + alumnos con extras a separar.
Future<SorteoMesasDialogResult?> mostrarSorteoMesasDialog({
  required BuildContext context,
  required String tituloInstitucion,
  required List<ContratoAlumno> alumnosSinMesa,
  required DemandaSorteoMesas demanda,
}) {
  return showDialog<SorteoMesasDialogResult>(
    context: context,
    builder: (context) => _SorteoMesasDialog(
      tituloInstitucion: tituloInstitucion,
      alumnosSinMesa: alumnosSinMesa,
      demanda: demanda,
    ),
  );
}

class _SorteoMesasDialog extends StatefulWidget {
  final String tituloInstitucion;
  final List<ContratoAlumno> alumnosSinMesa;
  final DemandaSorteoMesas demanda;

  const _SorteoMesasDialog({
    required this.tituloInstitucion,
    required this.alumnosSinMesa,
    required this.demanda,
  });

  @override
  State<_SorteoMesasDialog> createState() => _SorteoMesasDialogState();
}

class _SorteoMesasDialogState extends State<_SorteoMesasDialog> {
  late final TextEditingController _capacidadCtrl;
  bool _separarExtras = false;

  /// alumnoId → cantidad de mesas alejadas pedidas.
  final Map<String, int> _alejadasPorId = {};

  List<ContratoAlumno> get _alumnosConExtras => widget.alumnosSinMesa
      .where((a) => MesasExtraUtils.cantidadMesasFisicasSorteo(a) > 1)
      .toList();

  int get _totalAlejadas {
    if (!_separarExtras) return 0;
    var sum = 0;
    for (final a in _alumnosConExtras) {
      final pedidas = _alejadasPorId[a.id];
      if (pedidas == null) continue;
      final fisicas = MesasExtraUtils.cantidadMesasFisicasSorteo(a);
      sum += MesasExtraUtils.cantidadAlejadasEfectivas(fisicas, pedidas);
    }
    return sum;
  }

  int get _minCapacidad => MesasExtraUtils.capacidadMinimaSorteo(
        demanda: widget.demanda,
        totalAlejadas: _totalAlejadas,
      );

  @override
  void initState() {
    super.initState();
    _capacidadCtrl = TextEditingController(
      text: widget.demanda.total.toString(),
    );
  }

  @override
  void dispose() {
    _capacidadCtrl.dispose();
    super.dispose();
  }

  void _sincronizarCapacidadMinima() {
    final min = _minCapacidad;
    final actual = int.tryParse(_capacidadCtrl.text.trim()) ?? 0;
    if (actual < min) {
      _capacidadCtrl.text = '$min';
    }
  }

  void _toggleAlumno(ContratoAlumno a, bool? checked) {
    setState(() {
      if (checked == true) {
        _alejadasPorId[a.id] = 1;
      } else {
        _alejadasPorId.remove(a.id);
      }
      _sincronizarCapacidadMinima();
    });
  }

  void _setAlejadas(ContratoAlumno a, int value) {
    final fisicas = MesasExtraUtils.cantidadMesasFisicasSorteo(a);
    final maxAlej = fisicas - 1;
    setState(() {
      _alejadasPorId[a.id] = value < 1 ? 1 : (value > maxAlej ? maxAlej : value);
      _sincronizarCapacidadMinima();
    });
  }

  void _confirmar() {
    _sincronizarCapacidadMinima();
    final capacidad = int.tryParse(_capacidadCtrl.text.trim());
    if (capacidad == null || capacidad < _minCapacidad) return;

    final separaciones = <AlumnoMesasSeparadas>[];
    if (_separarExtras) {
      for (final a in _alumnosConExtras) {
        final pedidas = _alejadasPorId[a.id];
        if (pedidas == null) continue;
        final fisicas = MesasExtraUtils.cantidadMesasFisicasSorteo(a);
        final efectivas =
            MesasExtraUtils.cantidadAlejadasEfectivas(fisicas, pedidas);
        if (efectivas < 1) continue;
        separaciones.add(
          AlumnoMesasSeparadas(
            alumnoId: a.id,
            cantidadAlejadas: efectivas,
          ),
        );
      }
    }

    Navigator.pop(
      context,
      SorteoMesasDialogResult(
        capacidadSalon: capacidad,
        separaciones: separaciones,
      ),
    );
  }

  String _resumenSeparacion(int fisicas, int alejadas) {
    final juntas = fisicas - alejadas;
    if (juntas <= 1 && alejadas == 1) {
      return '1 + 1 lejos';
    }
    if (juntas == 1) {
      return '1 + $alejadas lejos';
    }
    return '$juntas juntas + $alejadas lejos';
  }

  @override
  Widget build(BuildContext context) {
    final capacidad = int.tryParse(_capacidadCtrl.text.trim());
    final min = _minCapacidad;
    final capacidadValida = capacidad != null && capacidad >= min;
    final conExtras = _alumnosConExtras;

    return AlertDialog(
      title: const Text('Sorteo de mesas'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.tituloInstitucion,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.demanda.alumnos} alumno(s) sin mesa asignada',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Necesitarás ${widget.demanda.total} mesas',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('· ${widget.demanda.mesasBase} mesas base (contrato)'),
                    Text('· ${widget.demanda.mesasExtras} mesas extra'),
                    const SizedBox(height: 4),
                    Text(
                      'Por defecto extras juntas (ej. 40, 41, 42). '
                      'Si separás, elegís cuántas quedan lejos del bloque.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _capacidadCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Capacidad del salón (mesas numeradas)',
                  helperText: _totalAlejadas > 0
                      ? 'Mínimo $min (demanda + huecos para alejadas).'
                      : 'Mínimo $min.',
                  border: const OutlineInputBorder(),
                  errorText:
                      capacidadValida ? null : 'Debe ser al menos $min',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Separar mesas extras'),
                subtitle: Text(
                  conExtras.isEmpty
                      ? 'No hay alumnos con mesas extras en este sorteo.'
                      : 'Tildá alumnos con extras y elegí cuántas mesas '
                          'querés alejadas del bloque principal.',
                ),
                value: _separarExtras,
                onChanged: conExtras.isEmpty
                    ? null
                    : (v) => setState(() {
                          _separarExtras = v;
                          if (!v) _alejadasPorId.clear();
                          _sincronizarCapacidadMinima();
                        }),
              ),
              if (_separarExtras && conExtras.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...conExtras.map((a) {
                  final fisicas =
                      MesasExtraUtils.cantidadMesasFisicasSorteo(a);
                  final extras = fisicas - 1;
                  final marcado = _alejadasPorId.containsKey(a.id);
                  final alejadas = _alejadasPorId[a.id] ?? 1;
                  final maxAlej = fisicas - 1;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              a.nombreAlumno,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$extras mesa(s) extra · $fisicas físicas',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            value: marcado,
                            onChanged: (v) => _toggleAlumno(a, v),
                          ),
                          if (marcado) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Row(
                                children: [
                                  const Text('Mesas alejadas:'),
                                  const SizedBox(width: 12),
                                  DropdownButton<int>(
                                    value: alejadas.clamp(1, maxAlej),
                                    items: [
                                      for (var k = 1; k <= maxAlej; k++)
                                        DropdownMenuItem(
                                          value: k,
                                          child: Text('$k'),
                                        ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) _setAlejadas(a, v);
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _resumenSeparacion(
                                        fisicas,
                                        alejadas.clamp(1, maxAlej),
                                      ),
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
                        ],
                      ),
                    ),
                  );
                }),
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
          onPressed: capacidadValida ? _confirmar : null,
          child: const Text('SORTEAR'),
        ),
      ],
    );
  }
}
