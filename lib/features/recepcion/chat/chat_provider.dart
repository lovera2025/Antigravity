import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../central/central_provider.dart';
import 'chat_del_puesto.dart';

/// El chat de la puerta de este puesto (6.5.0). En la PC, el de la central:
/// existe mientras está prendida (los celulares se suman por ella). En el
/// celular lo reemplaza `PantallaPuesto` con el suyo.
final chatDeLaPuertaProvider = Provider<ChatDelPuesto?>((ref) {
  final estado = ref.watch(centralDeLaPuertaProvider);
  if (!estado.prendida) return null;
  return ref.read(centralDeLaPuertaProvider.notifier).chat;
});
