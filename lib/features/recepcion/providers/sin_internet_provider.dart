import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_engine.dart';
import '../../totem/providers/totem_config_provider.dart';
import '../../totem/services/foto_guardada.dart';
import '../../totem/widgets/totem_local.dart' show eventoMasivoProvider;
import '../repositories/invitados_repository.dart';
import '../services/lista_sin_internet.dart';

/// Con qué se pone al día un evento en esta PC: la lista de la puerta, los
/// alumnos del motor, la carpeta de fotos y la cola de subida. Los tests lo
/// reemplazan.
final accesosPuertaProvider = Provider<AccesosPuerta>((ref) {
  final invitados = ref.watch(invitadosRepositoryProvider);
  final motor = ref.watch(syncEngineProvider);
  return AccesosPuerta(
    bajarLista: invitados.bajarListaDelEvento,
    bajarAlumnos: motor.bajarParaLaPuerta,
    guardarFoto: (url, eventoId) =>
        FotosDelTotem.enLaPc.guardar(url, eventoId: eventoId),
    fotoGuardada: (url, eventoId) =>
        FotosDelTotem.enLaPc.estaGuardada(url, eventoId: eventoId),
    contarSinSubir: (eventoId) async =>
        (await invitados.idsSinSubir(eventoId)).length,
  );
});

/// "Lista para trabajar sin internet" de un evento: se pone al día mientras
/// Recepción lo tiene abierto, y sigue a la conexión, al tipo de evento y a la
/// foto del tótem.
final puestaAlDiaProvider =
    Provider.autoDispose.family<PuestaAlDiaPuerta, String>((ref, eventoId) {
  final conexion = ref.watch(connectivityServiceProvider);
  final puesta = PuestaAlDiaPuerta(
    eventoId: eventoId,
    accesos: ref.watch(accesosPuertaProvider),
    hayInternet: conexion.currentStatus == AppConnectivity.online,
  );
  ref.listen(
    totemConfigValueProvider(eventoId),
    (_, cfg) => puesta.fotoUrl = cfg.imagenUrl,
    fireImmediately: true,
  );
  // Arranca cuando se sabe si es masivo: si no, la primera puesta al día no
  // bajaría los alumnos.
  ref.listen(
    eventoMasivoProvider(eventoId),
    (_, masivo) {
      if (masivo == null) return;
      puesta.masivo = masivo;
      unawaited(puesta.arrancar());
    },
    fireImmediately: true,
  );
  final sub = conexion.stream
      .listen((estado) => puesta.conexion(estado == AppConnectivity.online));
  ref.onDispose(() {
    sub.cancel();
    puesta.dispose();
  });
  return puesta;
});
