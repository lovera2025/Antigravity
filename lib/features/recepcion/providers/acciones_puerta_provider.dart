import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../central/central_provider.dart';
import '../central/cliente_central.dart';
import '../repositories/invitados_repository.dart';
import '../services/puerta_del_evento.dart';

/// Lo que el panel de la puerta (`PanelPuerta`) hace con una persona, y lo que
/// dice de ella además de "ADENTRO · 22:41".
///
/// El panel es el mismo en la Recepción de la PC y en el celular de la puerta
/// (lo visual se hace una sola vez); lo que cambia es quién marca:
/// - en la PC, la base de esta PC ([AccionesDeEstaPc]);
/// - en el celular, la central del salón por el wifi ([AccionesDelCelular]).
abstract class AccionesPuerta {
  /// Ingresa a [persona]. En un masivo antes del sorteo su fila puede no
  /// existir: se crea.
  Future<void> ingresar(String eventoId, PersonaPuerta persona);

  Future<void> deshacer(PersonaPuerta persona);

  /// Sacar de la lista lo cargado a mano. Solo en la PC.
  Future<void> eliminar(PersonaPuerta persona);

  bool get puedeEliminar;

  /// Si marca en la base de esta PC. Solo entonces tiene sentido decir si la
  /// PC está lista para trabajar sin internet (`LineaSinInternet`).
  bool get enEstaPc;

  /// Lo que va después de la hora: quién lo ingresó ("Juli"), o "por mandar"
  /// si el celular todavía no pudo avisarle a la central.
  String? marca(String personaId);

  /// Lo que hay que decir aunque nadie haya tocado nada en este panel: "ya
  /// ingresó a las 22:41 · Pato" cuando la central no hizo lo que se pidió.
  Stream<String> get avisos;
}

/// En la PC: el repositorio de siempre. Quién marcó desde un celular lo sabe la
/// central de la puerta, si está prendida.
class AccionesDeEstaPc implements AccionesPuerta {
  AccionesDeEstaPc(this._invitados, this._quien);

  final InvitadosRepository _invitados;
  final String? Function(String personaId) _quien;

  @override
  Future<void> ingresar(String eventoId, PersonaPuerta persona) =>
      persona.fila != null
          ? _invitados.marcarIngreso(persona.id)
          : _invitados.ingresarDesdeLaPuerta(
              eventoId: eventoId,
              id: persona.id,
              nombre: persona.nombre,
              mesa: persona.mesa,
            );

  @override
  Future<void> deshacer(PersonaPuerta persona) =>
      _invitados.deshacerIngreso(persona.id);

  @override
  Future<void> eliminar(PersonaPuerta persona) =>
      _invitados.eliminar(persona.id);

  @override
  bool get puedeEliminar => true;

  @override
  bool get enEstaPc => true;

  @override
  String? marca(String personaId) => _quien(personaId);

  @override
  Stream<String> get avisos => const Stream.empty();
}

/// En el celular de la puerta: lo marca la central (`ClienteCentral`).
class AccionesDelCelular implements AccionesPuerta {
  AccionesDelCelular(this._cliente);
  final ClienteCentral _cliente;

  @override
  Future<void> ingresar(String eventoId, PersonaPuerta persona) =>
      _cliente.ingresar(persona);

  @override
  Future<void> deshacer(PersonaPuerta persona) => _cliente.deshacer(persona);

  @override
  Future<void> eliminar(PersonaPuerta persona) async {}

  @override
  bool get puedeEliminar => false;

  @override
  bool get enEstaPc => false;

  @override
  String? marca(String personaId) => _cliente.marca(personaId);

  @override
  Stream<String> get avisos => _cliente.avisos;
}

final accionesPuertaProvider = Provider<AccionesPuerta>((ref) {
  final central = ref.watch(centralDeLaPuertaProvider.notifier);
  return AccionesDeEstaPc(
    ref.watch(invitadosRepositoryProvider),
    central.quienMarco,
  );
});
