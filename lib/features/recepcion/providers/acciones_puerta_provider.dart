import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../main.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../common/providers/user_role_provider.dart';
import '../../common/utils/quien_opera.dart';
import '../central/central_provider.dart';
import '../central/cliente_central.dart';
import '../central/pedidos_de_la_puerta.dart';
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

  /// Suma una silla de la noche a la familia de [grupo] (6.4.0): con el vale de
  /// la barra, a la mesa de [datos] o, si se llenó, a otra de la familia. Lo
  /// decide el mismo candado que a los celulares. [puerta] es la lista que se ve.
  Future<ResultadoSilla> sumarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  );

  /// Quita una silla sumada esa noche, con el motivo. La fila queda, tachada.
  Future<ResultadoSilla> quitarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  );

  /// Quién queda anotado en la silla: el nombre del celular, o quien opera la
  /// PC.
  String get quienSoy;
}

/// Lo que pasó al sumar o quitar una silla, en palabras.
class ResultadoSilla {
  /// Si se hizo (o, en el celular, si se mandó).
  final bool hecho;
  final String texto;

  const ResultadoSilla({required this.hecho, required this.texto});

  /// De la respuesta del candado ([ResolvedorDePedidos]).
  factory ResultadoSilla.deRespuesta(
    Map<String, Object?> r, {
    required String nombre,
    required bool sumar,
  }) {
    if (r['ok'] != true) {
      return const ResultadoSilla(
        hecho: false,
        texto: 'No se pudo guardar en esta PC. Probá de nuevo.',
      );
    }
    final aviso = r['aviso'];
    if (r['hizo'] == QueHaceLaCentral.nada.name) {
      return ResultadoSilla(
        hecho: false,
        texto: aviso is String ? aviso : 'No se hizo nada.',
      );
    }
    final mesa = r['mesa'];
    final hecho = sumar
        ? 'Silla sumada a la mesa $mesa de $nombre.'
        : 'Silla quitada de la mesa $mesa de $nombre.';
    return ResultadoSilla(
      hecho: true,
      texto: aviso is String ? '$aviso $hecho' : hecho,
    );
  }
}

/// La función de [CentralDeLaPuerta.resolverDeEstaPc].
typedef ResolverDeEstaPc = Future<Map<String, Object?>> Function(
  String eventoId,
  PedidoPuerta pedido, {
  required String puesto,
  required PuertaDelEvento puerta,
});

/// En la PC: el repositorio de siempre. Quién marcó desde un celular lo sabe la
/// central de la puerta, si está prendida. Las sillas pasan por la misma fila
/// que los celulares ([ResolverDeEstaPc]).
class AccionesDeEstaPc implements AccionesPuerta {
  AccionesDeEstaPc(
    this._invitados,
    this._quien, {
    required ResolverDeEstaPc resolver,
    required String Function() quienOpera,
  })  : _resolver = resolver,
        _quienOpera = quienOpera;

  final InvitadosRepository _invitados;
  final String? Function(String personaId) _quien;
  final ResolverDeEstaPc _resolver;
  final String Function() _quienOpera;

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

  @override
  String get quienSoy => _quienOpera();

  @override
  Future<ResultadoSilla> sumarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  ) =>
      _silla(QuePide.sumarSilla, eventoId, puerta, grupo, datos);

  @override
  Future<ResultadoSilla> quitarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  ) =>
      _silla(QuePide.quitarSilla, eventoId, puerta, grupo, datos);

  Future<ResultadoSilla> _silla(
    QuePide que,
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  ) async {
    final respuesta = await _resolver(
      eventoId,
      PedidoPuerta(
        id: const Uuid().v4(),
        que: que,
        personaId: grupo.titular.id,
        silla: datos,
      ),
      puesto: quienSoy,
      puerta: puerta,
    );
    return ResultadoSilla.deRespuesta(
      respuesta,
      nombre: grupo.titular.nombre,
      sumar: que == QuePide.sumarSilla,
    );
  }
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

  @override
  String get quienSoy => _cliente.nombre ?? 'Celular';

  /// La central contesta después: si no la pudo sumar, lo dice por [avisos].
  ResultadoSilla get _mandado => _cliente.estado == EstadoDelPuesto.conectado
      ? const ResultadoSilla(
          hecho: true,
          texto: 'Se mandó a la central: aparece en la lista en un momento.',
        )
      : const ResultadoSilla(
          hecho: true,
          texto: 'Sin conexión con la central: se manda sola al volver.',
        );

  @override
  Future<ResultadoSilla> sumarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  ) async {
    await _cliente.sumarSilla(grupo, datos);
    return _mandado;
  }

  @override
  Future<ResultadoSilla> quitarSilla(
    String eventoId,
    PuertaDelEvento puerta,
    GrupoPuerta grupo,
    DatosSilla datos,
  ) async {
    await _cliente.quitarSilla(grupo, datos);
    return _mandado;
  }
}

/// Quien opera esta PC, para anotar en la silla: la caja o el modo jefe, el
/// perfil o el mail. "PC" si no se sabe.
String quienOperaEnEstaPc(Ref ref) {
  String? email;
  try {
    email = ref.read(supabaseProvider).auth.currentUser?.email;
  } catch (_) {}
  try {
    final q = quienOperaDe(
      app: ref.read(appRoleProvider),
      nombrePerfil: ref.read(userRoleProvider).asData?.value.nombre,
      email: email,
    );
    return q == 'Sin identificar' ? 'PC' : q;
  } catch (_) {
    return 'PC';
  }
}

final accionesPuertaProvider = Provider<AccionesPuerta>((ref) {
  final central = ref.watch(centralDeLaPuertaProvider.notifier);
  return AccionesDeEstaPc(
    ref.watch(invitadosRepositoryProvider),
    central.quienMarco,
    resolver: central.resolverDeEstaPc,
    quienOpera: () => quienOperaEnEstaPc(ref),
  );
});
