import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/connectivity_service.dart';
import '../../main.dart';
import 'datos/link_del_delegado.dart';
import 'datos/nube_del_delegado.dart';

/// Lo que la página del delegado le pide a la nube. Lee `supabaseProvider`,
/// nunca el singleton.
final nubeDelDelegadoProvider = Provider<NubeDelDelegado>(
  (ref) => NubeDelDelegadoSupabase(ref.watch(supabaseProvider)),
);

/// Lo que el programa le pide a la nube sobre el link de una fiesta.
final linkDelDelegadoProvider = Provider<LinkDelDelegado>(
  (ref) => LinkDelDelegadoSupabase(ref.watch(supabaseProvider)),
);

/// El link que se le manda al delegado.
String urlDelLinkDelDelegado(String clave) =>
    '$kWebBaseUrl/?delegado&clave=$clave';

/// Cuánto se espera a la nube por los avisos antes de seguir sin ellos.
const kEsperaDeLosAvisosDelDelegado = Duration(seconds: 6);

/// Lo que hay para traer, para ALERTAS del Centro de Comando: un aviso por
/// fiesta.
///
/// **No tiene reloj.** Se pregunta al abrir el programa y al volver a la
/// ventana (`OperationalSyncCoordinator` lo invalida), y después de traer. Sin
/// internet, o si la nube no contesta, no hay avisos: nunca frena nada.
final avisosDelDelegadoProvider =
    FutureProvider<List<AvisoDelDelegado>>((ref) async {
  if (ref.read(connectivityServiceProvider).currentStatus ==
      AppConnectivity.offline) {
    return const [];
  }
  try {
    return await ref
        .read(linkDelDelegadoProvider)
        .pendientes()
        .timeout(kEsperaDeLosAvisosDelDelegado);
  } catch (e) {
    debugPrint('Avisos del delegado: no se pudo preguntar ($e)');
    return const [];
  }
});
