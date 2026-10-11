import 'package:flutter/material.dart';

import '../../../core/utils/ar_time.dart';
import '../services/planilla_sorteo.dart';
import '../services/ultimos_sorteados.dart';

/// Qué planilla del sorteo se imprime.
typedef OpcionesPlanillaSorteo = ({
  VersionPlanillaSorteo version,
  bool blancoYNegro,

  /// Solo las familias del último sorteo, en una hoja corrida.
  bool soloUltimos,
});

/// Pregunta qué planilla se imprime: la interna (con teléfonos y
/// observaciones) o la de repartir, y en color o en blanco y negro. `null` si
/// se cancela.
///
/// Con [ultimos], y si hay familias con mesa que no son de ese sorteo, pregunta
/// además **quiénes**: toda la escuela o solo los últimos sorteados. Con
/// [sugerirUltimos] viene elegida la segunda: es lo que se quiere imprimir
/// recién sorteados los que faltaban.
Future<OpcionesPlanillaSorteo?> elegirOpcionesPlanillaSorteo({
  required BuildContext context,
  UltimosSorteados? ultimos,
  bool sugerirUltimos = false,
}) {
  final hayUltimos = ultimos != null && ultimos.planillaSolaCambiaAlgo;
  var version = VersionPlanillaSorteo.interna;
  var blancoYNegro = false;
  var soloUltimos = hayUltimos && sugerirUltimos && ultimos.enPie.length > 1;
  return showDialog<OpcionesPlanillaSorteo>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('Planilla del sorteo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hayUltimos) ...[
                const Text('Quiénes'),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  key: const Key('planilla_quienes'),
                  segments: [
                    const ButtonSegment(
                      value: false,
                      icon: Icon(Icons.school_outlined),
                      label: Text('Toda la escuela'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(
                        'Solo los últimos sorteados '
                        '(${ultimos.familias.length})',
                      ),
                    ),
                  ],
                  selected: {soloUltimos},
                  onSelectionChanged: (s) =>
                      setDialog(() => soloUltimos = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  soloUltimos
                      ? 'Las del sorteo del '
                          '${ArTime.formatFechaHora(ultimos.sorteo.createdAt)}'
                          ', en una sola hoja.'
                      : 'El resumen del salón y una hoja por división.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              const Text('Versión'),
              const SizedBox(height: 8),
              SegmentedButton<VersionPlanillaSorteo>(
                segments: const [
                  ButtonSegment(
                    value: VersionPlanillaSorteo.interna,
                    icon: Icon(Icons.lock_outline_rounded),
                    label: Text('Interna'),
                  ),
                  ButtonSegment(
                    value: VersionPlanillaSorteo.paraRepartir,
                    icon: Icon(Icons.groups_rounded),
                    label: Text('Para repartir'),
                  ),
                ],
                selected: {version},
                onSelectionChanged: (s) => setDialog(() => version = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                version == VersionPlanillaSorteo.interna
                    ? 'Con teléfonos, observaciones y a quién llamar por el '
                        'reparto de sillas.'
                    : 'Sin teléfonos ni observaciones: son datos de otras '
                        'familias.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const Text('Impresión'),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.palette_outlined),
                    label: Text('Color'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.contrast_rounded),
                    label: Text('Blanco y negro'),
                  ),
                ],
                selected: {blancoYNegro},
                onSelectionChanged: (s) =>
                    setDialog(() => blancoYNegro = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            key: const Key('planilla_generar'),
            onPressed: () => Navigator.pop(
              context,
              (
                version: version,
                blancoYNegro: blancoYNegro,
                soloUltimos: soloUltimos,
              ),
            ),
            child: const Text('GENERAR'),
          ),
        ],
      ),
    ),
  );
}
