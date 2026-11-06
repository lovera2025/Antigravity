import '../../../models/invitado.dart';
import '../../../models/silla_puerta.dart';
import '../../totem/services/tiempos_a_mano.dart';
import '../services/puerta_del_evento.dart';
import '../services/sillas_de_la_puerta.dart';
import '../services/vales_anulados.dart';

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

/// Lo que se le puede pedir a la central. Las sillas de la noche y los segundos
/// del tótem van por el mismo camino que los ingresos (6.4.0): de a uno, con la
/// base del momento, sea desde un celular o desde la PC.
enum QuePide {
  ingresar,
  deshacer,
  sumarSilla,
  quitarSilla,
  tiemposTotem;

  /// Ingresar o deshacer: lo que cambia si una persona está adentro.
  bool get esIngreso => this == ingresar || this == deshacer;
}

/// Lo que dice el celular de un ingreso que todavía no pudo mandarle a la
/// central (`AccionesPuerta.marca`).
const kPorMandar = 'por mandar';

/// Lo que viaja con un pedido de silla.
class DatosSilla {
  /// Sumar: la mesa elegida. Si ya está llena, va a otra de la familia.
  final int? mesa;

  /// Sumar: el número del vale de la barra, como lo escribió la recepcionista.
  final String? vale;
  final String? nota;

  /// Quitar: cuál.
  final String? sillaId;

  /// Quitar: por qué. Obligatorio.
  final String? motivo;

  const DatosSilla({this.mesa, this.vale, this.nota, this.sillaId, this.motivo});

  Map<String, Object?> toJson() => {
        if (mesa != null) 'mesa': mesa,
        if (vale != null) 'vale': vale,
        if (nota != null) 'nota': nota,
        if (sillaId != null) 'silla': sillaId,
        if (motivo != null) 'motivo': motivo,
      };

  /// Null si no se entiende.
  static DatosSilla? fromJson(Object? json) {
    if (json is! Map) return null;
    String? texto(String clave, int largo) {
      final v = json[clave];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : (t.length > largo ? t.substring(0, largo) : t);
    }

    final mesa = json['mesa'];
    return DatosSilla(
      mesa: mesa is int ? mesa : null,
      vale: texto('vale', 40),
      nota: texto('nota', 120),
      sillaId: texto('silla', 64),
      motivo: texto('motivo', 120),
    );
  }
}

/// Un pedido de un celular, o de la PC.
class PedidoPuerta {
  /// Lo pone el celular. Si llega dos veces (se cortó antes de la respuesta y
  /// lo volvió a mandar), es el mismo pedido: no se hace de nuevo.
  final String id;
  final QuePide que;

  /// A quién: la persona que entra o, en una silla, el titular de la familia.
  /// Vacío en los segundos del tótem.
  final String personaId;

  /// Cuánto hacía que se había tocado cuando el celular lo mandó. Se cuenta en
  /// el celular, con su reloj de un lado y del otro: no importa si está mal en
  /// hora.
  final Duration hace;

  /// En [QuePide.sumarSilla] y [QuePide.quitarSilla].
  final DatosSilla? silla;

  /// En [QuePide.tiemposTotem].
  final TiemposAMano? tiempos;

  const PedidoPuerta({
    required this.id,
    required this.que,
    required this.personaId,
    this.hace = Duration.zero,
    this.silla,
    this.tiempos,
  });

  /// El mismo, diciendo cuánto hace que se tocó.
  PedidoPuerta conHace(Duration hace) => PedidoPuerta(
        id: id,
        que: que,
        personaId: personaId,
        hace: hace,
        silla: silla,
        tiempos: tiempos,
      );

  Map<String, Object?> toJson() => {
        't': 'pedido',
        'id': id,
        'que': que.name,
        'persona': personaId,
        'hace': hace.inMilliseconds,
        if (silla != null) 'silla': silla!.toJson(),
        if (tiempos != null) 'tiempos': tiempos!.toJson(),
      };

  /// Null si no es un pedido que se entienda: de la red puede llegar
  /// cualquier cosa.
  static PedidoPuerta? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final que = json['que'];
    final persona = json['persona'];
    final hace = json['hace'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    final quePide = QuePide.values.where((q) => q.name == que).firstOrNull;
    if (quePide == null) return null;
    final sinPersona = quePide == QuePide.tiemposTotem;
    if (persona is! String ||
        (persona.isEmpty && !sinPersona) ||
        persona.length > 64) {
      return null;
    }
    final silla = DatosSilla.fromJson(json['silla']);
    final tiempos = TiemposAMano.fromJson(json['tiempos']);
    if ((quePide == QuePide.sumarSilla || quePide == QuePide.quitarSilla) &&
        silla == null) {
      return null;
    }
    if (sinPersona && tiempos == null) return null;
    return PedidoPuerta(
      id: id,
      que: quePide,
      personaId: persona,
      hace: Duration(milliseconds: hace is int && hace > 0 ? hace : 0),
      silla: silla,
      tiempos: tiempos,
    );
  }
}

enum QueHaceLaCentral { ingresar, deshacer, sumarSilla, quitarSilla, tiempos, nada }

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
    case QuePide.sumarSilla:
    case QuePide.quitarSilla:
    case QuePide.tiemposTotem:
      // Van por [decidirSilla] y por los segundos: acá no llegan.
      return const DecisionPedido._(QueHaceLaCentral.nada);
  }
}

/// Lo que sale de un pedido de silla.
class DecisionSilla {
  final QueHaceLaCentral hace;

  /// Sumar: a qué mesa va (puede no ser la pedida, si esa se llenó).
  final int? mesa;

  /// Sumar: el vale como se anota ([valeNormalizado]).
  final String? vale;

  /// Lo que se dice: por qué no se hizo, o que la silla fue a otra mesa.
  final String? aviso;

  const DecisionSilla._(this.hace, {this.mesa, this.vale, this.aviso});

  const DecisionSilla._nada(String aviso)
      : this._(QueHaceLaCentral.nada, aviso: aviso);

  bool get haceAlgo => hace != QueHaceLaCentral.nada;
}

/// Qué hacer con un pedido de silla ([QuePide.sumarSilla] o
/// [QuePide.quitarSilla]).
///
/// [grupo] es la familia de la lista que ve Recepción: de ahí salen sus mesas y
/// lo del contrato. [deLaNoche] son las sillas del evento **como están ahora en la
/// base** (vigentes y quitadas): otro celular pudo haber sumado recién, y el tope
/// se cuenta con eso. [nombreDe] dice de quién es un contrato, para "el vale ya
/// se usó para GÓMEZ".
DecisionSilla decidirSilla({
  required PedidoPuerta pedido,
  required GrupoPuerta? grupo,
  required List<SillaPuerta> deLaNoche,
  String? Function(String contratoId)? nombreDe,
  ValesAnulados valesAnulados = ValesAnulados.ninguno,
}) {
  final contratoId = grupo?.contratoId;
  if (grupo == null) {
    return const DecisionSilla._nada(
        'Esa persona ya no está en la lista de la puerta.');
  }
  if (contratoId == null) {
    return const DecisionSilla._nada(
        'Las sillas de la noche son de las familias de alumnos.');
  }
  final datos = pedido.silla ?? const DatosSilla();
  final vigentes = deLaNoche.where((s) => s.vigente).toList();
  switch (pedido.que) {
    case QuePide.sumarSilla:
      final familia = grupo.sillasPorMesa.conSumadas(contratoId, vigentes);
      if (!familia.tieneMesa) {
        return const DecisionSilla._nada('Esa familia no tiene mesa todavía.');
      }
      final vale = valeNormalizado(datos.vale);
      if (vale == null) {
        return const DecisionSilla._nada(
            'Hace falta el número del vale de la barra.');
      }
      if (valesAnulados.estaAnulado(vale)) {
        return DecisionSilla._nada('El vale $vale está anulado en la barra.');
      }
      final usada =
          vigentes.where((s) => valeNormalizado(s.vale) == vale).firstOrNull;
      if (usada != null) {
        final quien = nombreDe?.call(usada.contratoAlumnoId);
        return DecisionSilla._nada(quien == null
            ? 'El vale $vale ya se usó para otra silla.'
            : 'El vale $vale ya se usó para $quien.');
      }
      final mesa = familia.mesaConLugar(preferida: datos.mesa);
      if (mesa == null) {
        return DecisionSilla._nada(yaEnElTope(grupo.titular.nombre));
      }
      final pedida = datos.mesa;
      final String? aviso;
      if (pedida == null || pedida == mesa.numero) {
        aviso = null;
      } else if (familia.mesa(pedida) != null) {
        aviso = 'La mesa $pedida ya estaba llena: la silla va a la mesa '
            '${mesa.numero}.';
      } else {
        aviso = 'La mesa $pedida no es de la familia: la silla va a la mesa '
            '${mesa.numero}.';
      }
      return DecisionSilla._(
        QueHaceLaCentral.sumarSilla,
        mesa: mesa.numero,
        vale: vale,
        aviso: aviso,
      );
    case QuePide.quitarSilla:
      final silla = deLaNoche
          .where((s) => s.id == datos.sillaId && s.contratoAlumnoId == contratoId)
          .firstOrNull;
      if (silla == null || !silla.vigente) {
        return const DecisionSilla._nada('Esa silla ya se quitó.');
      }
      if ((datos.motivo ?? '').trim().isEmpty) {
        return const DecisionSilla._nada('Decí por qué se quita.');
      }
      return DecisionSilla._(QueHaceLaCentral.quitarSilla, mesa: silla.mesa);
    case QuePide.ingresar:
    case QuePide.deshacer:
    case QuePide.tiemposTotem:
      return const DecisionSilla._nada('No se entendió el pedido.');
  }
}

/// Lo que se dice cuando una silla se sumó o se quitó: "Silla sumada a la mesa
/// 13 de GÓMEZ, ANA.", con el aviso del candado adelante si lo hubo ("La mesa
/// 12 ya estaba llena: …"). Lo usan la PC y el celular, así dicen lo mismo.
String textoSillaHecha({
  required bool sumar,
  required Object? mesa,
  required String nombre,
  String? aviso,
}) {
  final hecho = sumar
      ? 'Silla sumada a la mesa $mesa de $nombre.'
      : 'Silla quitada de la mesa $mesa de $nombre.';
  return aviso == null || aviso.isEmpty ? hecho : '$aviso $hecho';
}

/// "PÉREZ, JULIANA ya no puede agregar: 2 extra por mesa."
String yaEnElTope(String nombre) =>
    '$nombre ya no puede agregar: ${SillasDeUnaMesa.tope} extra por mesa.';

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
