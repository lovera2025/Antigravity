import '../../../models/invitado.dart';
import '../services/puerta_del_evento.dart';

/// Qué hace la central de la puerta con lo que le piden los celulares.
///
/// En el salón, una notebook hace de central (`CentralPuerta`): los celulares
/// de la puerta le piden "ingresar" o "deshacer" por el wifi del router, y
/// ella lo marca en su base como si lo hubieran tocado en su Recepción. Como
/// hay una sola lista, dos celulares no se pisan: el segundo que ingresa a la
/// misma persona recibe "ya ingresó a las 22:41 · Juli".
///
/// Sin pantalla, base ni red: la central le pasa a [decidirPedido] cómo está la
/// persona en ese momento y hace lo que sale.

/// Hasta cuánto después de tocado se saluda en el tótem. Un pedido que llega
/// más tarde es de un celular que estuvo sin wifi: la familia ya pasó, y como
/// después de un corte (`lecturaEnSilencio`), en el salón no se saluda a nadie
/// atrasado. Se marca igual.
const kSaludarHasta = Duration(minutes: 1);

enum QuePide { ingresar, deshacer }

/// Lo que dice el celular de un ingreso que todavía no pudo mandarle a la
/// central (`AccionesPuerta.marca`).
const kPorMandar = 'por mandar';

/// Un pedido de un celular.
class PedidoPuerta {
  /// Lo pone el celular. Si llega dos veces (se cortó antes de la respuesta y
  /// lo volvió a mandar), es el mismo pedido: no se hace de nuevo.
  final String id;
  final QuePide que;
  final String personaId;

  /// Cuánto hacía que se había tocado cuando el celular lo mandó. Se cuenta en
  /// el celular, con su reloj de un lado y del otro: no importa si está mal en
  /// hora.
  final Duration hace;

  const PedidoPuerta({
    required this.id,
    required this.que,
    required this.personaId,
    this.hace = Duration.zero,
  });

  Map<String, Object?> toJson() => {
        't': 'pedido',
        'id': id,
        'que': que.name,
        'persona': personaId,
        'hace': hace.inMilliseconds,
      };

  /// Null si no es un pedido que se entienda: de la red puede llegar
  /// cualquier cosa.
  static PedidoPuerta? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final que = json['que'];
    final persona = json['persona'];
    final hace = json['hace'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (persona is! String || persona.isEmpty || persona.length > 64) {
      return null;
    }
    final quePide = QuePide.values.where((q) => q.name == que).firstOrNull;
    if (quePide == null) return null;
    return PedidoPuerta(
      id: id,
      que: quePide,
      personaId: persona,
      hace: Duration(milliseconds: hace is int && hace > 0 ? hace : 0),
    );
  }
}

enum QueHaceLaCentral { ingresar, deshacer, nada }

/// Lo que sale de un pedido.
class DecisionPedido {
  final QueHaceLaCentral hace;

  /// Si el ingreso se saluda en el tótem.
  final bool saludar;

  /// Lo que se le dice al celular cuando no se hizo nada.
  final String? aviso;

  const DecisionPedido._(this.hace, {this.saludar = false, this.aviso});

  bool get haceAlgo => hace != QueHaceLaCentral.nada;
}

/// Qué hacer con [pedido].
///
/// [persona] es la de la lista que ve Recepción (null si ya no está: un alumno
/// dado de baja, una fila eliminada). [fila] es su fila en la base de la
/// central **en ese momento**, no la de la lista que se mandó: otro celular
/// pudo haberla marcado recién. [quien] es el puesto que la marcó esta noche,
/// si se sabe.
DecisionPedido decidirPedido({
  required PedidoPuerta pedido,
  required PersonaPuerta? persona,
  required Invitado? fila,
  String? quien,
}) {
  // Si la lista tenía su fila y la base ya no, alguien la sacó recién (se
  // eliminó, o se deshizo el sorteo): ingresarla la volvería a crear.
  if (persona == null || (persona.fila != null && fila == null)) {
    return const DecisionPedido._(
      QueHaceLaCentral.nada,
      aviso: 'Esa persona ya no está en la lista de la puerta.',
    );
  }
  final adentro = fila?.estadoIngreso == EstadoIngreso.ingresado;
  final hora = adentro ? fila?.updatedAt : null;
  switch (pedido.que) {
    case QuePide.ingresar:
      if (adentro) {
        return DecisionPedido._(
          QueHaceLaCentral.nada,
          aviso: yaIngreso(persona.nombre, hora: hora, quien: quien),
        );
      }
      return DecisionPedido._(
        QueHaceLaCentral.ingresar,
        saludar: pedido.hace <= kSaludarHasta,
      );
    case QuePide.deshacer:
      if (!adentro) {
        return DecisionPedido._(
          QueHaceLaCentral.nada,
          aviso: '${persona.nombre} no figuraba adentro.',
        );
      }
      return const DecisionPedido._(QueHaceLaCentral.deshacer);
  }
}

/// "PÉREZ, JUAN ya ingresó a las 22:41 · Juli".
String yaIngreso(String nombre, {DateTime? hora, String? quien}) {
  final b = StringBuffer('$nombre ya ingresó');
  if (hora != null) b.write(' a las ${horaCorta(hora)}');
  if (quien != null && quien.isNotEmpty) b.write(' · $quien');
  b.write('.');
  return b.toString();
}

/// "22:41", en la hora de esta PC.
String horaCorta(DateTime hora) {
  final h = hora.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(h.hour)}:${dos(h.minute)}';
}

/// Quién marcó a cada uno esta noche, desde qué puesto.
///
/// Vive en la memoria de la central y nada más: no hay columna para esto en la
/// lista de la puerta, y no se agrega una por un dato que sirve solo esa
/// noche. Si la notebook se reinicia, los ingresos siguen; solo se pierde el
/// nombre de quién los hizo.
class MarcasDeLaNoche {
  final _porPersona = <String, String>{};

  /// El puesto que marcó a [personaId], si fue esta noche por la central.
  String? quien(String personaId) => _porPersona[personaId];

  void ingreso(String personaId, String puesto) =>
      _porPersona[personaId] = puesto;

  void deshizo(String personaId) => _porPersona.remove(personaId);

  /// Cuántos marcó [puesto] y siguen adentro.
  int cuantos(String puesto) =>
      _porPersona.values.where((p) => p == puesto).length;

  Map<String, String> get todas => Map.unmodifiable(_porPersona);
}
