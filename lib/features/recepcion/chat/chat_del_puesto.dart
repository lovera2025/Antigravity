import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'mensaje_de_puesto.dart';

/// Una conversación del puesto: con todos ([kTodos]) o con otro puesto.
class ConversacionDelPuesto {
  /// [kTodos], o el id del otro puesto.
  final String id;
  final String nombre;

  /// Si el otro puesto está conectado (Todos, siempre).
  final bool conectado;
  final int sinLeer;
  final MensajeDePuesto? ultimo;

  const ConversacionDelPuesto({
    required this.id,
    required this.nombre,
    required this.conectado,
    required this.sinLeer,
    this.ultimo,
  });

  bool get esTodos => id == kTodos;
}

/// Lo que llegó de otro puesto con esa conversación cerrada: para el aviso de
/// arriba de la lista ("Juli, a vos: ¿alguien vio a GÓMEZ?"), el sonido de la PC
/// y la vibración del celular.
class MensajeNuevo {
  final MensajeDePuesto mensaje;

  /// La conversación donde está: tocar el aviso la abre.
  final String conversacion;

  const MensajeNuevo(this.mensaje, this.conversacion);

  /// "Juli, a vos" o "Juli, a todos".
  String get quien =>
      '${mensaje.deNombre}, ${mensaje.aTodos ? 'a todos' : 'a vos'}';
}

/// El chat de un puesto, la PC o un celular (6.5.0): sus conversaciones, cuántos
/// sin leer tiene cada una y lo que llega. Cómo viaja un mensaje lo pone quien lo
/// arma: en la PC va directo a la central, en el celular por el wifi.
class ChatDelPuesto extends ChangeNotifier {
  ChatDelPuesto({
    required this.yo,
    required String nombre,
    required void Function(MensajeDePuesto) enviar,
    DateTime Function()? ahora,
  })  : _nombre = nombre,
        _enviar = enviar,
        _ahora = ahora ?? DateTime.now;

  /// El id de este puesto.
  final String yo;
  String _nombre;
  final void Function(MensajeDePuesto) _enviar;
  final DateTime Function() _ahora;

  final _mensajes = <MensajeDePuesto>[];
  final _ids = <String>{};
  var _puestos = <PuestoDelChat>[];

  /// Cuántos mensajes de cada conversación ya se vieron.
  final _vistos = <String, int>{};

  /// La conversación abierta en pantalla, o null.
  String? _abierta;

  /// Si se puede mandar: en el celular, con conexión a la PC.
  bool _puedeMandar = true;
  bool _cerrado = false;

  final _nuevos = StreamController<MensajeNuevo>.broadcast();

  /// Lo que llega de otro puesto con esa conversación cerrada.
  Stream<MensajeNuevo> get nuevos => _nuevos.stream;

  String get nombre => _nombre;
  bool get puedeMandar => _puedeMandar;
  String? get abierta => _abierta;

  set nombre(String n) {
    if (n == _nombre) return;
    _nombre = n;
    _avisar();
  }

  set puedeMandar(bool v) {
    if (v == _puedeMandar) return;
    _puedeMandar = v;
    _avisar();
  }

  /// Cómo se llamaba cada puesto que se vio esta noche: uno que se fue sigue con
  /// su nombre en la lista, no con su código.
  final _nombres = <String, String>{};

  /// Los otros puestos de esta noche: los conectados primero, por nombre.
  void ponerPuestos(List<PuestoDelChat> puestos) {
    for (final p in puestos) {
      _nombres[p.id] = p.nombre;
    }
    _puestos = [
      for (final p in puestos)
        if (p.id != yo) p,
    ]..sort((a, b) {
        if (a.conectado != b.conectado) return a.conectado ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    _avisar();
  }

  /// Los mensajes de [conversacion], del más viejo al más nuevo.
  List<MensajeDePuesto> de(String conversacion) => [
        for (final m in _mensajes)
          if (m.conversacionDe(yo) == conversacion) m,
      ];

  /// Todos y un puesto por cada uno con el que se puede hablar, más los que ya
  /// no están pero dejaron mensajes.
  List<ConversacionDelPuesto> get conversaciones {
    ConversacionDelPuesto armar(String id, String nombre, bool conectado) {
      final suyos = de(id);
      return ConversacionDelPuesto(
        id: id,
        nombre: nombre,
        conectado: conectado,
        sinLeer: suyos.length - (_vistos[id] ?? 0),
        ultimo: suyos.isEmpty ? null : suyos.last,
      );
    }

    final lista = [armar(kTodos, 'Todos', true)];
    final ya = <String>{kTodos};
    for (final p in _puestos) {
      if (ya.add(p.id)) lista.add(armar(p.id, p.nombre, p.conectado));
    }
    // Uno que se fue pero dejó mensajes: se sigue viendo, apagado.
    for (final m in _mensajes) {
      final c = m.conversacionDe(yo);
      if (!ya.add(c)) continue;
      final nombre = m.de == yo ? _nombres[c] ?? 'Otro puesto' : m.deNombre;
      lista.add(armar(c, nombre, false));
    }
    return lista;
  }

  /// Sin leer, entre todas.
  int get sinLeer =>
      conversaciones.fold(0, (s, c) => s + (c.sinLeer > 0 ? c.sinLeer : 0));

  /// Se abrió [conversacion] en pantalla (null: se cerró el chat). Lo que tiene
  /// queda leído.
  void abrir(String? conversacion) {
    _abierta = conversacion;
    if (conversacion != null) _vistos[conversacion] = de(conversacion).length;
    _avisar();
  }

  /// Manda [texto] a [conversacion]. Devuelve el mensaje, o null si está vacío
  /// o no se puede mandar.
  MensajeDePuesto? mandar(String texto, String conversacion) {
    final t = texto.trim();
    if (t.isEmpty || !_puedeMandar) return null;
    final m = MensajeDePuesto(
      id: const Uuid().v4(),
      de: yo,
      deNombre: _nombre,
      para: conversacion == kTodos ? null : conversacion,
      texto: t.length > kLargoDelMensaje ? t.substring(0, kLargoDelMensaje) : t,
      hora: _ahora(),
    );
    recibir(m);
    _enviar(m);
    return m;
  }

  /// Llegó un mensaje (o volvió el propio). Lo repetido no cuenta.
  void recibir(MensajeDePuesto m) {
    if (!m.loVe(yo) || !_ids.add(m.id)) return;
    _mensajes.add(m);
    final conversacion = m.conversacionDe(yo);
    if (m.de == yo || _abierta == conversacion) {
      _vistos[conversacion] = de(conversacion).length;
    } else if (!_nuevos.isClosed) {
      _nuevos.add(MensajeNuevo(m, conversacion));
    }
    _avisar();
  }

  /// Lo que ya había esta noche, al conectarse, sin avisos. La primera vez queda
  /// leído (un celular que recién se suma no arranca con todo sin leer); al
  /// volver de un corte, lo que llegó mientras tanto queda sin leer.
  void ponerHistoria(List<MensajeDePuesto> historia) {
    final primera = _mensajes.isEmpty;
    for (final m in historia) {
      if (!m.loVe(yo) || !_ids.add(m.id)) continue;
      _mensajes.add(m);
    }
    _mensajes.sort((a, b) => a.hora.compareTo(b.hora));
    if (primera) {
      for (final m in _mensajes) {
        final c = m.conversacionDe(yo);
        _vistos[c] = (_vistos[c] ?? 0) + 1;
      }
    }
    _avisar();
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    unawaited(_nuevos.close());
    super.dispose();
  }
}
