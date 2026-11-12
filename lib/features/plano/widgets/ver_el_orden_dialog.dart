import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/plano_evento.dart';
import '../services/cambios_de_mesa.dart';

/// "Ver el orden" (6.7.0): las familias de la mejor ubicada a la última, con
/// sus mesas y la oración que dice por qué quedó cada una ahí. Es el respaldo
/// para cuando una familia reclama (pedido del usuario, 12-nov-2026).
///
/// Muestra lo que se guardó al prender el orden, no una cuenta de hoy: dice lo
/// mismo aunque después se corrija un cobro. Solo en modo jefe, y no se
/// imprime.
Future<void> mostrarElOrden(
  BuildContext context, {
  required OrdenDelPlano orden,
  required List<ContratoAlumno> alumnos,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => VerElOrdenDialog(orden: orden, alumnos: alumnos),
    );

class VerElOrdenDialog extends StatelessWidget {
  final OrdenDelPlano orden;
  final List<ContratoAlumno> alumnos;

  const VerElOrdenDialog({
    super.key,
    required this.orden,
    required this.alumnos,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final nombre = {
      for (final a in alumnos) a.id: a.nombreAlumno,
    };
    final apellido = {
      for (final a in alumnos) a.id: CambiosDeMesa.apellido(a),
    };
    final conMesa = orden.lugares.where((l) => l.mesas.isNotEmpty).length;
    final cuando = orden.el == null
        ? null
        : ArTime.formatFechaHora(orden.el!);
    return AlertDialog(
      title: const Text('Cumplimiento debido'),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$conMesa ${conMesa == 1 ? 'familia ubicada' : 'familias ubicadas'}'
              ' ${orden.recorrido.rotulo.toLowerCase()}'
              '${cuando == null ? '' : ' · calculado el $cuando'}'
              '${orden.por == null ? '' : ' · ${orden.por}'}',
              key: const Key('orden_resumen'),
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: orden.lugares.length,
                itemBuilder: (context, i) {
                  final l = orden.lugares[i];
                  // Una raya entre los grupos, sin título.
                  final cambiaElGrupo =
                      i > 0 && orden.lugares[i - 1].grupo != l.grupo;
                  final mesas = l.mesas.isEmpty
                      ? 'sin mesa en el salón'
                      : l.mesas.length == 1
                          ? 'mesa ${l.mesas.single}'
                          : 'mesas ${l.mesas.join(' y ')}';
                  return Column(
                    key: Key('orden_${l.puesto}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (cambiaElGrupo) const Divider(thickness: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${l.puesto}.',
                                style: tema.textTheme.titleSmall,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${nombre[l.alumnoId] ?? apellido[l.alumnoId] ?? 'Una familia que ya no está'}'
                                    ' · $mesas',
                                    style: tema.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (l.frase.isNotEmpty)
                                    Text(l.frase,
                                        style: tema.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CERRAR'),
        ),
      ],
    );
  }
}
