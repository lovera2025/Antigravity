import 'package:flutter/material.dart';

import '../../../models/contrato_alumno.dart';
import '../services/salon_mesas.dart';

/// Una familia en el cartel de DAR MESA A TODOS.
typedef FamiliaSinMesa = ({
  ContratoAlumno alumno,

  /// No pagó nada de la cuota base: se dice "no pagó".
  bool noPago,
});

/// DAR MESA A TODOS (6.9.4): la lista de las familias a las que les falta
/// mesa, **todas tildadas**, y qué número recibiría cada una. Un solo DAR MESA
/// se las da a las tildadas. Devuelve las elegidas, o null si se cancela.
///
/// [previa] dice qué recibiría cada una con lo tildado (la misma cuenta que
/// guarda, con los datos de esta PC): se vuelve a pedir al tildar o destildar,
/// porque una mesa vacía del fondo puede pasar de una familia a otra. Null si
/// no se pudo calcular; al dar se vuelve a calcular con la nube.
Future<Set<String>?> mostrarDarMesaATodosDialog({
  required BuildContext context,
  required List<FamiliaSinMesa> familias,
  Map<String, List<int>>? Function(Set<String> elegidos)? previa,
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => DarMesaATodosDialog(familias: familias, previa: previa),
  );
}

class DarMesaATodosDialog extends StatefulWidget {
  final List<FamiliaSinMesa> familias;
  final Map<String, List<int>>? Function(Set<String> elegidos)? previa;

  const DarMesaATodosDialog({
    super.key,
    required this.familias,
    this.previa,
  });

  @override
  State<DarMesaATodosDialog> createState() => _DarMesaATodosDialogState();
}

class _DarMesaATodosDialogState extends State<DarMesaATodosDialog> {
  late final Set<String> _elegidos = {
    for (final f in widget.familias) f.alumno.id,
  };
  Map<String, List<int>>? _vista;

  @override
  void initState() {
    super.initState();
    _calcular();
  }

  void _calcular() {
    try {
      _vista = widget.previa?.call(_elegidos);
    } catch (_) {
      _vista = null;
    }
  }

  void _alternar(String id, bool tildar) => setState(() {
        tildar ? _elegidos.add(id) : _elegidos.remove(id);
        _calcular();
      });

  String _queLeFalta(FamiliaSinMesa f) {
    final a = f.alumno;
    final tiene = SalonMesas.tieneNumeros(a);
    if (!tiene) return f.noPago ? 'Sin mesa · no pagó' : 'Sin mesa';
    return SalonMesas.avisoMesas(a) ?? 'le falta una mesa';
  }

  @override
  Widget build(BuildContext context) {
    final n = _elegidos.length;
    return AlertDialog(
      title: const Text('Dar mesa a todos'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cada familia recibe su mesa fijada si la tiene, una mesa del '
                'fondo que quedó vacía o una nueva al fondo. Nadie más se '
                'mueve, y lo que deben sigue en su cuenta.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final f in widget.familias)
                CheckboxListTile(
                  key: Key('dar_mesa_${f.alumno.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _elegidos.contains(f.alumno.id),
                  onChanged: (v) => _alternar(f.alumno.id, v == true),
                  title: Text(
                    f.alumno.nombreAlumno,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if ((f.alumno.cursoDivision ?? '').trim().isNotEmpty)
                        f.alumno.cursoDivision!.trim(),
                      _queLeFalta(f),
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  secondary: _elegidos.contains(f.alumno.id) &&
                          (_vista?[f.alumno.id]?.isNotEmpty ?? false)
                      ? Text(
                          _vista![f.alumno.id]!.length == 1
                              ? 'Mesa ${_vista![f.alumno.id]!.single}'
                              : 'Mesas ${_vista![f.alumno.id]!.join(' y ')}',
                          key: Key('dar_mesa_numero_${f.alumno.id}'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.indigo,
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          key: const Key('dar_mesa_confirmar'),
          onPressed: n == 0 ? null : () => Navigator.pop(context, {..._elegidos}),
          child: Text(n == 1 ? 'DAR MESA' : 'DAR MESA A LAS $n'),
        ),
      ],
    );
  }
}
