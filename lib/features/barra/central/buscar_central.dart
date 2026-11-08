import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// El puerto por el que las cajas preguntan "¿dónde está la central de esta fiesta?".
const kPuertoBusquedaBarra = 8777;

/// Dónde está la central: la dirección de la notebook en el wifi del salón y su puerto.
@immutable
class DondeEstaLaCentral {
  final String direccion;
  final int puerto;

  const DondeEstaLaCentral(this.direccion, this.puerto);

  /// "192.168.0.10:8797", como la muestra la notebook y como se escribe a mano.
  String get texto => '$direccion:$puerto';

  /// Lo que escribió la cajera ("192.168.0.10:8797" o "192.168.0.10 8797"). Null si no se
  /// entiende.
  static DondeEstaLaCentral? deTexto(String texto) {
    final m = RegExp(r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s*[:\s·]\s*(\d{2,5})\s*$').firstMatch(texto);
    if (m == null) return null;
    final puerto = int.parse(m.group(2)!);
    if (puerto <= 0 || puerto > 65535) return null;
    return DondeEstaLaCentral(m.group(1)!, puerto);
  }

  @override
  bool operator ==(Object other) =>
      other is DondeEstaLaCentral && other.direccion == direccion && other.puerto == puerto;

  @override
  int get hashCode => Object.hash(direccion, puerto);
}

/// En la notebook: contesta a las cajas que preguntan por la central de su fiesta.
///
/// **Pregunta la caja y contesta la notebook, y no al revés:** Android recibe bien una
/// respuesta dirigida a él y mal un anuncio a toda la red (necesitaría el permiso y el
/// bloqueo del multicast). Si el router no deja pasar la pregunta (algunos aíslan a los
/// equipos del wifi), la cajera escribe a mano lo que muestra la notebook.
class RespondeBusqueda {
  RespondeBusqueda({required this.eventoId, required this.puertoCentral});

  final String eventoId;
  final int puertoCentral;
  RawDatagramSocket? _socket;

  /// Empieza a escuchar en [puerto], en todas las conexiones de la PC ([en] en las
  /// pruebas: solo esta PC). Si no puede (el puerto está tomado), sigue sin contestar: la
  /// cajera todavía puede escribir la dirección.
  Future<bool> escuchar({int puerto = kPuertoBusquedaBarra, InternetAddress? en}) async {
    try {
      final s = await RawDatagramSocket.bind(en ?? InternetAddress.anyIPv4, puerto, reuseAddress: true);
      _socket = s;
      s.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null || d.data.length > 512) return;
        try {
          final json = jsonDecode(utf8.decode(d.data));
          if (json is Map && json['t'] == 'buscar' && json['evento'] == eventoId) {
            s.send(
              utf8.encode(jsonEncode({'t': 'central', 'evento': eventoId, 'puerto': puertoCentral})),
              d.address,
              d.port,
            );
          }
        } catch (_) {}
      });
      return true;
    } catch (e) {
      debugPrint('Central de la barra: no se pudo escuchar la búsqueda: $e');
      return false;
    }
  }

  void cerrar() {
    _socket?.close();
    _socket = null;
  }
}

/// En la caja: pregunta a toda la red del salón dónde está la central de la fiesta, hasta
/// que contesta o se la deja de buscar.
class BuscaCentral {
  BuscaCentral({
    required this.eventoId,
    this.cada = const Duration(seconds: 3),
    this.puerto = kPuertoBusquedaBarra,
    Future<List<InternetAddress>> Function()? destinos,
  }) : _destinos = destinos ?? destinosDeLaRed;

  final String eventoId;
  final Duration cada;
  final int puerto;
  final Future<List<InternetAddress>> Function() _destinos;

  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Busca. [encontrada] se llama una vez por cada respuesta.
  Future<void> buscar(void Function(DondeEstaLaCentral) encontrada) async {
    parar();
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.broadcastEnabled = true;
      _socket = s;
      s.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null || d.data.length > 512) return;
        try {
          final json = jsonDecode(utf8.decode(d.data));
          final p = json is Map ? json['puerto'] : null;
          if (json is Map && json['t'] == 'central' && json['evento'] == eventoId && p is int) {
            encontrada(DondeEstaLaCentral(d.address.address, p));
          }
        } catch (_) {}
      });
      final pregunta = utf8.encode(jsonEncode({'t': 'buscar', 'evento': eventoId}));
      Future<void> preguntar() async {
        final socket = _socket;
        if (socket == null) return;
        for (final a in await _destinos()) {
          try {
            socket.send(pregunta, a, puerto);
          } catch (_) {}
        }
      }

      await preguntar();
      _timer = Timer.periodic(cada, (_) => unawaited(preguntar()));
    } catch (e) {
      debugPrint('Barra: no se pudo buscar la central: $e');
    }
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// A dónde se pregunta: a toda la red (255.255.255.255) y a la de cada conexión del
/// equipo (192.168.0.255), porque algunos routers dejan pasar una y no la otra.
Future<List<InternetAddress>> destinosDeLaRed() async {
  final destinos = <String>{'255.255.255.255'};
  try {
    for (final c in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in c.addresses) {
        final p = a.address.split('.');
        if (p.length == 4) destinos.add('${p[0]}.${p[1]}.${p[2]}.255');
      }
    }
  } catch (_) {}
  return [for (final d in destinos) InternetAddress(d)];
}
