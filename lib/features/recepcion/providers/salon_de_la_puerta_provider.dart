import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../totem/providers/tiempos_a_mano_provider.dart';
import '../../totem/widgets/totem_local.dart' show planoDelEventoProvider;
import '../services/plano_de_la_puerta.dart';

/// El salón que ve la puerta (6.5.0): el plano de la fiesta y la config del
/// tótem de esa noche. Null sin plano o sin mesas: entonces no aparecen VER EN
/// EL PLANO ni "Ver el plano entero".
///
/// En la PC sale de la base, como el tótem de Recepción. En el celular lo
/// reemplaza `PantallaPuesto` con el que manda la central (`CentralPuerta`).
final salonDeLaPuertaProvider =
    Provider.autoDispose.family<SalonParaLaPuerta?, String>((ref, eventoId) {
  final plano = ref.watch(planoDelEventoProvider(eventoId)).value;
  return SalonParaLaPuerta.de(
    plano,
    ref.watch(totemConfigDeLaNocheProvider(eventoId)),
  );
});
