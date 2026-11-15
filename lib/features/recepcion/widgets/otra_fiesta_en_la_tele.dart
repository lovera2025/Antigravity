import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/kiosk_launcher.dart';
import '../../../models/evento.dart';
import '../providers/recepcion_provider.dart';
import '../services/puerta_del_evento.dart';

/// Si antes de cambiar de evento en Recepción hay que preguntar por la tele: el
/// tótem está abierto y con **otra** fiesta.
///
/// Sin tótem, con el tótem ya en esa fiesta o al limpiar la selección, no se
/// pregunta nada: es el camino de siempre.
bool hayQuePreguntarPorLaTele({
  required bool hayTotem,
  required String? enLaTele,
  required String? nuevo,
}) =>
    hayTotem && nuevo != null && enLaTele != null && enLaTele != nuevo;

/// Cómo se nombra una fiesta en la pregunta: como en el desplegable.
String _nombreDe(String id, Iterable<Evento> eventos) {
  for (final e in eventos) {
    if (e.id == id) return etiquetaEventoRecepcion(e);
  }
  return 'otra fiesta';
}

/// El desplegable de Recepción eligió [eventoId].
///
/// **Si la tele ya está con otra fiesta, pregunta antes:** pasarla a la nueva o
/// solo mirar acá. Hasta la 6.8.0 la tele seguía al desplegable sin avisar: un
/// clic equivocado en plena fiesta ponía en el salón la portada de la fiesta de
/// mañana (revisión del 13-nov). Cerrar la pregunta sin elegir no cambia nada.
Future<void> elegirEventoEnRecepcion(
  BuildContext context,
  WidgetRef ref,
  String? eventoId, {
  Iterable<Evento> eventos = const [],
}) async {
  final notifier = ref.read(selectedEventProvider.notifier);
  final enLaTele = KioskLauncher.totemEventoId;
  if (!hayQuePreguntarPorLaTele(
    hayTotem: KioskLauncher.isTotemActive,
    enLaTele: enLaTele,
    nuevo: eventoId,
  )) {
    notifier.select(eventoId);
    return;
  }

  final pasarla = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('otra_fiesta_en_la_tele'),
      title: const Text('El tótem está con otra fiesta'),
      content: Text(
        'El tótem de la tele está con:\n'
        '${_nombreDe(enLaTele!, eventos)}\n\n'
        'Elegiste:\n'
        '${_nombreDe(eventoId!, eventos)}\n\n'
        '¿Pasás el tótem a esta, o solo la querés mirar en esta pantalla?',
      ),
      actions: [
        TextButton(
          key: const Key('tele_solo_mirar'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('SOLO MIRAR ACÁ'),
        ),
        FilledButton(
          key: const Key('tele_pasarla'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('PASAR EL TÓTEM'),
        ),
      ],
    ),
  );
  if (pasarla == null) return;
  notifier.select(eventoId, moverLaTele: pasarla);
}

/// El botón TÓTEM del Centro de Comando va a proyectar [elegido] (el evento de
/// Recepción). Devuelve la fiesta con la que se abre la tele, o null si se cerró
/// la pregunta sin elegir.
///
/// **Si la tele ya está con otra fiesta, pregunta** (revisión final del 15-nov):
/// después de un SOLO MIRAR ACÁ, Recepción queda en otra fiesta que la tele, y
/// volver a mostrar la tele desde acá la pasaba a esa sin avisar; con el filtro
/// de la 6.9.0 la tele dejaba de saludar a los de esa noche. SEGUIR CON LA DE LA
/// TELE la vuelve a mostrar con la fiesta que tenía.
Future<String?> fiestaParaAbrirLaTele(
  BuildContext context, {
  required String elegido,
  Iterable<Evento> eventos = const [],
}) async {
  final enLaTele = KioskLauncher.totemEventoId;
  if (!hayQuePreguntarPorLaTele(
    hayTotem: KioskLauncher.isTotemActive,
    enLaTele: enLaTele,
    nuevo: elegido,
  )) {
    return elegido;
  }
  final pasarla = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('otra_fiesta_al_abrir_la_tele'),
      title: const Text('El tótem está con otra fiesta'),
      content: Text(
        'El tótem de la tele está con:\n'
        '${_nombreDe(enLaTele!, eventos)}\n\n'
        'En Recepción estás mirando:\n'
        '${_nombreDe(elegido, eventos)}\n\n'
        '¿Pasás el tótem a esa, o lo volvés a mostrar con la que tenía?',
      ),
      actions: [
        TextButton(
          key: const Key('tele_seguir_con_la_suya'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('SEGUIR CON LA DE LA TELE'),
        ),
        FilledButton(
          key: const Key('tele_pasarla_al_abrir'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('PASAR EL TÓTEM'),
        ),
      ],
    ),
  );
  if (pasarla == null) return null;
  return pasarla ? elegido : enLaTele;
}
