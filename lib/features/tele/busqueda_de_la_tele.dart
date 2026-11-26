import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'red_de_la_tele.dart';

/// **La Tele 1 contesta a la Tele 2, sea de la escuela que sea** (25-nov-2026).
///
/// La Tele 2 pregunta por el wifi "¿dónde está la Tele 1 de esta escuela?"
/// con la misma pregunta que las cajas de la barra (`BuscaCentral`, en el
/// puerto [kPuertoBusquedaTele]). Hasta el 25-nov la Tele 1 contestaba solo
/// por su escuela; ahora **atiende las dos escuelas de la noche**, así que
/// contesta por cualquiera de las suyas ([conoce]: la que muestra, las que
/// atiende y las que vienen), con la escuela que le preguntaron (así la Tele
/// 2 la reconoce). La Tele 1 empieza a atender la de la Tele 2 cuando se
/// conecta. **No dice cuáles atiende** (revisión del 26-nov): el id del
/// evento es lo que trae la Tele 2 para conectarse.
///
/// Va aparte de `RespondeBusqueda` (la de la barra) a propósito: la barra
/// contesta solo por su fiesta.
class RespondeLaTele1 {
  RespondeLaTele1({required this.puertoCentral, required this.conoce});

  final int puertoCentral;

  /// Si la escuela es de esta tele.
  final bool Function(String eventoId) conoce;

  RawDatagramSocket? _socket;

  /// Lo que contesta a una pregunta, o null si no es una pregunta de la
  /// Tele 2.
  @visibleForTesting
  Map<String, Object?>? respuesta(Object? pregunta) {
    if (pregunta is! Map || pregunta['t'] != 'buscar') return null;
    final evento = pregunta['evento'];
    if (evento is! String || evento.length != 36 || !conoce(evento)) return null;
    return {
      't': 'central',
      'evento': evento,
      'puerto': puertoCentral,
      'tele': true,
    };
  }

  /// Empieza a escuchar en [puerto] ([en] en las pruebas: solo esta PC). Si no
  /// puede, sigue sin contestar: la dirección se escribe en la Tele 2.
  Future<bool> escuchar({int puerto = kPuertoBusquedaTele, InternetAddress? en}) async {
    try {
      final s = await RawDatagramSocket.bind(en ?? InternetAddress.anyIPv4, puerto, reuseAddress: true);
      _socket = s;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null || d.data.length > 512) return;
        try {
          final r = respuesta(jsonDecode(utf8.decode(d.data)));
          if (r != null) s.send(utf8.encode(jsonEncode(r)), d.address, d.port);
        } catch (_) {}
      });
      return true;
    } catch (e) {
      debugPrint('La Tele 1 no pudo escuchar la búsqueda: $e');
      return false;
    }
  }

  void cerrar() {
    _socket?.close();
    _socket = null;
  }
}
