// El chat de la puerta (6.5.0, pedido del usuario el 9-nov): las recepcionistas
// se hablan entre ellas, la PC y los celulares, por la notebook del salón. Al
// abrirlo se elige **a quién**: una recepcionista o Todos.
//
// Vive solo en la memoria de la central, como quién marcó a cada uno
// (`MarcasDeLaNoche`): sin tabla ni nube, anda sin internet, y si la notebook se
// reinicia se vacía. Dura la noche.

/// El puesto de la PC, en el chat: los celulares tienen el suyo, que inventan la
/// primera vez.
const kPuestoDeLaPc = 'pc';

/// Lo más largo que puede ser un mensaje.
const kLargoDelMensaje = 300;

/// Cuántos mensajes guarda la central: los más viejos se van.
const kMensajesDeLaNoche = 200;

/// Un mensaje entre puestos.
class MensajeDePuesto {
  /// Lo pone quien lo manda: si llega dos veces, es el mismo.
  final String id;

  /// De qué puesto (el id del celular, o [kPuestoDeLaPc]) y cómo se llama.
  final String de;
  final String deNombre;

  /// A qué puesto. Null: a todos.
  final String? para;

  final String texto;
  final DateTime hora;

  const MensajeDePuesto({
    required this.id,
    required this.de,
    required this.deNombre,
    this.para,
    required this.texto,
    required this.hora,
  });

  bool get aTodos => para == null;

  /// Si lo ve [puesto]: los de todos, los que le mandaron y los que mandó.
  bool loVe(String puesto) => aTodos || para == puesto || de == puesto;

  /// La conversación de [puesto] donde va: [kTodos] o la del otro puesto.
  String conversacionDe(String puesto) {
    if (aTodos) return kTodos;
    return de == puesto ? para! : de;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'de': de,
        'deNombre': deNombre,
        'para': ?para,
        'texto': texto,
        'hora': hora.toUtc().toIso8601String(),
      };

  /// Null si no se entiende: de la red puede llegar cualquier cosa.
  static MensajeDePuesto? fromJson(Object? json) {
    if (json is! Map) return null;
    String? texto(String clave, int largo) {
      final v = json[clave];
      if (v is! String) return null;
      final t = v.trim();
      if (t.isEmpty) return null;
      return t.length > largo ? t.substring(0, largo) : t;
    }

    final id = texto('id', 64);
    final de = texto('de', 64);
    final deNombre = texto('deNombre', 40);
    final cuerpo = texto('texto', kLargoDelMensaje);
    final hora = DateTime.tryParse('${json['hora'] ?? ''}');
    if (id == null || de == null || deNombre == null || cuerpo == null) {
      return null;
    }
    return MensajeDePuesto(
      id: id,
      de: de,
      deNombre: deNombre,
      para: texto('para', 64),
      texto: cuerpo,
      hora: hora ?? DateTime.now(),
    );
  }
}

/// La conversación con todos.
const kTodos = '*';

/// Un puesto con el que se puede hablar.
class PuestoDelChat {
  /// El id del celular, o [kPuestoDeLaPc].
  final String id;
  final String nombre;
  final bool conectado;

  const PuestoDelChat({
    required this.id,
    required this.nombre,
    required this.conectado,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'nombre': nombre,
        'conectado': conectado,
      };

  static PuestoDelChat? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final nombre = json['nombre'];
    if (id is! String || id.isEmpty || nombre is! String || nombre.isEmpty) {
      return null;
    }
    return PuestoDelChat(
      id: id,
      nombre: nombre,
      conectado: json['conectado'] != false,
    );
  }
}

/// Los mensajes de la noche, en la central. De a uno, sin repetir.
class ChatDeLaNoche {
  final _mensajes = <MensajeDePuesto>[];
  final _ids = <String>{};

  /// Lo agrega si es nuevo. Devuelve si lo era.
  bool agregar(MensajeDePuesto m) {
    if (!_ids.add(m.id)) return false;
    _mensajes.add(m);
    while (_mensajes.length > kMensajesDeLaNoche) {
      _ids.remove(_mensajes.removeAt(0).id);
    }
    return true;
  }

  /// Lo que ve [puesto], del más viejo al más nuevo.
  List<MensajeDePuesto> paraElPuesto(String puesto) => [
        for (final m in _mensajes)
          if (m.loVe(puesto)) m,
      ];

  List<MensajeDePuesto> get todos => List.unmodifiable(_mensajes);
}
