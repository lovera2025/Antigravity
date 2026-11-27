import 'dart:async';
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
  RespondeLaTele1({
    required this.puertoCentral,
    required this.conoce,
    this.esperaParaReabrir = const Duration(seconds: 1),
  });

  final int puertoCentral;

  /// Si la escuela es de esta tele.
  final bool Function(String eventoId) conoce;

  /// Cuánto espera para volver a abrir el socket que se murió.
  final Duration esperaParaReabrir;

  RawDatagramSocket? _socket;
  int _puerto = kPuertoBusquedaTele;
  InternetAddress? _en;
  var _cerrado = false;
  Timer? _reabrir;

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
  ///
  /// **Si después el socket se muere** (un cambio de wifi), **se vuelve a abrir
  /// solo** (26-nov-2026, como `RespondeBusqueda` de la barra): hasta ahí la Tele
  /// 1 dejaba de contestar y la Tele 2 no la encontraba más hasta reiniciarla.
  Future<bool> escuchar({int puerto = kPuertoBusquedaTele, InternetAddress? en}) async {
    _cerrado = false;
    _puerto = puerto;
    _en = en;
    return _abrir();
  }

  /// Cambió la red de esta tele: se cierra el socket y se abre otro, aunque el
  /// de antes parezca vivo.
  Future<void> reabrir() async {
    if (_cerrado) return;
    _reabrir?.cancel();
    final viejo = _socket;
    _socket = null;
    viejo?.close();
    if (!await _abrir()) _seMurio(null);
  }

  void _seMurio(RawDatagramSocket? s) {
    if (_cerrado || (s != null && !identical(s, _socket))) return;
    _socket = null;
    _reabrir?.cancel();
    _reabrir = Timer(esperaParaReabrir, () async {
      if (_cerrado || _socket != null) return;
      if (!await _abrir()) _seMurio(null);
    });
  }

  Future<bool> _abrir() async {
    try {
      final s = await RawDatagramSocket.bind(_en ?? InternetAddress.anyIPv4, _puerto, reuseAddress: true);
      if (_cerrado) {
        s.close();
        return false;
      }
      _socket = s;
      s.listen(
        (e) {
          if (e == RawSocketEvent.closed) {
            _seMurio(s);
            return;
          }
          if (e != RawSocketEvent.read) return;
          final d = s.receive();
          if (d == null || d.data.length > 512) return;
          try {
            final r = respuesta(jsonDecode(utf8.decode(d.data)));
            if (r != null) s.send(utf8.encode(jsonEncode(r)), d.address, d.port);
          } catch (_) {}
        },
        onError: (Object _) => _seMurio(s),
        onDone: () => _seMurio(s),
      );
      return true;
    } catch (e) {
      debugPrint('La Tele 1 no pudo escuchar la búsqueda: $e');
      return false;
    }
  }

  void cerrar() {
    _cerrado = true;
    _reabrir?.cancel();
    _socket?.close();
    _socket = null;
  }

  /// Lo que le hace al socket un cambio de red: se muere sin que nadie lo cierre.
  @visibleForTesting
  void matarElSocketParaPrueba() => _socket?.close();
}
