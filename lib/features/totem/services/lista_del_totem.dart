import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/invitado.dart';

/// No hay clave del tótem para este evento: sin internet la primera vez, o el
/// link del navegador sin `&clave=`.
class SinClaveDelTotem implements Exception {
  const SinClaveDelTotem();

  @override
  String toString() => 'El tótem no tiene la clave del evento';
}

/// Lee de la nube la lista de la puerta de un evento, para el tótem (sección 8
/// de la 6.0.0).
///
/// Va por la función `totem_lista` con la clave del tótem, no por la tabla:
/// con los permisos cerrados, un anónimo que lee `invitados` recibe **una
/// lista vacía, sin error**, y el tótem sacaría a todos de la pantalla. La
/// función, en cambio, con una clave que no es la del evento da error. Llega
/// sin DNI ni intentos, y en un solo JSON (no la corta el tope de 1000 filas).
///
/// Si no puede leer, **tira**: nunca devuelve una lista vacía por no poder.
class ListaDelTotem {
  ListaDelTotem({
    required this.llamar,
    required this.clave,
    this.claveMala,
  });

  /// Para el tótem de verdad: [cliente] es el de la ventana (anónimo en la
  /// ventana del tótem y en la web).
  factory ListaDelTotem.deSupabase(
    SupabaseClient cliente, {
    required Future<String?> Function(String eventoId) clave,
    Future<void> Function(String eventoId)? claveMala,
  }) =>
      ListaDelTotem(
        llamar: (funcion, params) => cliente.rpc(funcion, params: params),
        clave: clave,
        claveMala: claveMala,
      );

  /// Llama a una función de la nube (`SupabaseClient.rpc`).
  final Future<dynamic> Function(String funcion, Map<String, dynamic> params)
      llamar;

  /// De dónde sale la clave: el puente en la ventana del tótem, el link en la
  /// web.
  final Future<String?> Function(String eventoId) clave;

  /// La nube dijo que la clave no es la del evento: quien la guardó la olvida.
  final Future<void> Function(String eventoId)? claveMala;

  String? _eventoDeLaClave;
  String? _clave;

  /// El código con que la nube contesta una clave que no es la del evento.
  static const codigoClaveMala = '28000';

  Future<List<Invitado>> leer(String eventoId) async {
    if (eventoId.length != 36) {
      throw ArgumentError.value(eventoId, 'eventoId', 'no es un id de evento');
    }
    var k = _eventoDeLaClave == eventoId ? _clave : null;
    if (k == null) {
      k = (await clave(eventoId))?.trim();
      if (k == null || k.isEmpty) throw const SinClaveDelTotem();
      _eventoDeLaClave = eventoId;
      _clave = k;
    }

    final dynamic respuesta;
    try {
      respuesta = await llamar(
        'totem_lista',
        {'p_evento': eventoId, 'p_clave': k},
      );
    } on PostgrestException catch (e) {
      if (e.code == codigoClaveMala) {
        // La próxima vez se pide de nuevo.
        _clave = null;
        _eventoDeLaClave = null;
        await claveMala?.call(eventoId);
      }
      rethrow;
    }

    if (respuesta is! List) {
      throw FormatException('totem_lista no devolvió una lista', '$respuesta');
    }
    return [
      for (final fila in respuesta)
        Invitado.fromJson(Map<String, dynamic>.from(fila as Map)),
    ];
  }
}
