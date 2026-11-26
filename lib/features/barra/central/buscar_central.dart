import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/barras_del_salon.dart';

/// El puerto por el que las cajas preguntan "¿dónde está la central de esta fiesta?".
const kPuertoBusquedaBarra = 8777;

/// Dónde está la central: la dirección de la notebook en el wifi del salón y su puerto.
///
/// Si la encontró la búsqueda, también **de qué barra es** y **qué notebook es**
/// (25-nov-2026: una central por barra). No cuentan para comparar: la misma dirección es
/// la misma central.
@immutable
class DondeEstaLaCentral {
  final String direccion;
  final int puerto;

  /// "Barra 1", si la central lo dijo. Null: no lo dijo (una de antes, o escrita a mano).
  final String? barra;

  /// El id de la notebook, si lo dijo: con él dos centrales se reconocen.
  final String? equipo;

  const DondeEstaLaCentral(this.direccion, this.puerto, {this.barra, this.equipo});

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

/// **Qué central sirve**, entre las que contestan (25-nov-2026: una central por barra,
/// cada una en su notebook).
/// - **Una caja** se engancha a la de su barra. Una central que no dice su barra (una de
///   antes) sirve igual, y una caja sin barra (la encargada) toma cualquiera de la fiesta.
///   **Si la de su barra no aparece en [esperaPorSuBarra]** (la notebook se apagó) y otra
///   de la fiesta sí, se engancha a esa: las dos centrales se pasan todo, así que nada se
///   pierde.
/// - **Una central** busca a las otras de su fiesta para pasarse todo: nunca a ella misma,
///   y de cada par se engancha una sola (la de id menor), así no hay dos caminos.
@immutable
class EleccionDeCentral {
  const EleccionDeCentral.deLaCaja({this.barra, this.esperaPorSuBarra = const Duration(seconds: 10)})
      : esta = null;

  /// [esta] es el id de la notebook que busca.
  const EleccionDeCentral.otraCentral(String this.esta)
      : barra = null,
        esperaPorSuBarra = Duration.zero;

  /// La barra de la caja. Null: cualquiera.
  final String? barra;

  /// En la notebook: su id.
  final String? esta;
  final Duration esperaPorSuBarra;

  bool get esDeCentral => esta != null;

  /// Si [d] sirve, después de [buscando] de búsqueda.
  bool sirve(DondeEstaLaCentral d, {required Duration buscando}) {
    final esta = this.esta;
    if (esta != null) {
      final otra = d.equipo;
      return otra != null && otra != esta && esta.compareTo(otra) < 0;
    }
    final mia = barraDe(barra), suya = barraDe(d.barra);
    if (mia == null || suya == null || mia == suya) return true;
    return buscando >= esperaPorSuBarra;
  }
}

/// En la notebook: contesta a las cajas que preguntan por la central de su fiesta.
///
/// **Pregunta la caja y contesta la notebook, y no al revés:** Android recibe bien una
/// respuesta dirigida a él y mal un anuncio a toda la red (necesitaría el permiso y el
/// bloqueo del multicast). Si el router no deja pasar la pregunta (algunos aíslan a los
/// equipos del wifi), la cajera escribe a mano lo que muestra la notebook.
///
/// **Contesta con su barra y su equipo** (25-nov-2026): la caja elige la de su barra
/// ([EleccionDeCentral]), y otra central de la misma fiesta la reconoce para engancharse.
/// Contesta a todas las preguntas de su fiesta, sean de la barra que sean: la que elige
/// es la caja.
class RespondeBusqueda {
  RespondeBusqueda({required this.eventoId, required this.puertoCentral, this.barra, this.equipo});

  final String eventoId;
  final int puertoCentral;
  final String? barra;
  final String? equipo;
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
            // Con varias tablets preguntando a la vez, una respuesta podía perderse.
            unawaited(mandarDatagrama(
              s,
              utf8.encode(jsonEncode({
                't': 'central',
                'evento': eventoId,
                'puerto': puertoCentral,
                if (barra != null) 'barra': barra,
                if (equipo != null) 'equipo': equipo,
              })),
              d.address,
              d.port,
            ));
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
/// que contesta o se la deja de buscar. En la notebook, lo mismo para encontrar **la
/// central de la otra barra** y engancharse con ella.
class BuscaCentral {
  BuscaCentral({
    required this.eventoId,
    this.cada = const Duration(seconds: 3),
    int puerto = kPuertoBusquedaBarra,
    List<int>? puertos,
    Future<List<InternetAddress>> Function()? destinos,
  })  : puertos = puertos ?? [puerto],
        _destinos = destinos ?? destinosDeLaRed;

  final String eventoId;
  final Duration cada;

  /// A qué puertos se pregunta. En la app, uno solo (el 8777); las ventanas de prueba,
  /// con dos centrales en la misma PC, preguntan a los dos.
  final List<int> puertos;
  int get puerto => puertos.first;
  final Future<List<InternetAddress>> Function() _destinos;

  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Cuántas veces se empezó a buscar: si se vuelve a empezar mientras la anterior
  /// todavía abría su socket, la anterior se descarta (no quedan dos buscando).
  var _vuelta = 0;

  /// Busca. [encontrada] se llama una vez por cada respuesta.
  Future<void> buscar(void Function(DondeEstaLaCentral) encontrada) async {
    parar();
    final esta = ++_vuelta;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (esta != _vuelta) {
        s.close();
        return;
      }
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
            final barra = json['barra'], equipo = json['equipo'];
            encontrada(DondeEstaLaCentral(
              d.address.address,
              p,
              barra: barra is String && barra.length <= 40 ? barra : null,
              equipo: equipo is String && equipo.length <= 64 ? equipo : null,
            ));
          }
        } catch (_) {}
      });
      final pregunta = utf8.encode(jsonEncode({'t': 'buscar', 'evento': eventoId}));
      // Una ronda que falla (una conexión que desaparece en el medio) no corta la
      // búsqueda: la siguiente vuelve a preguntar. Antes, un error en la primera ronda
      // dejaba de buscar para siempre.
      Future<void> preguntar() async {
        try {
          final socket = _socket;
          if (socket == null) return;
          final destinos = await _destinos();
          for (final a in destinos) {
            for (final p in [...puertos]) {
              if (!identical(socket, _socket)) return;
              await mandarDatagrama(socket, pregunta, a, p);
            }
          }
        } catch (e) {
          debugPrint('Barra: una pregunta por la central no salió: $e');
        }
      }

      _timer = Timer.periodic(cada, (_) => unawaited(preguntar()));
      await preguntar();
    } catch (e) {
      debugPrint('Barra: no se pudo buscar la central: $e');
    }
  }

  void parar() {
    _vuelta++;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Manda un datagrama y, si el equipo no lo pudo mandar en ese momento, lo reintenta.
///
/// **El socket no espera:** `send` devuelve 0 si todavía está mandando el anterior, y ese
/// datagrama se pierde. Preguntando a varias direcciones seguidas (toda la red, la de cada
/// conexión), en Windows salía solo la primera pregunta (25-nov-2026, lo encontró la
/// prueba de las dos barras): si el router dejaba pasar justo la otra, la tablet no
/// encontraba la central.
Future<void> mandarDatagrama(RawDatagramSocket socket, List<int> datos, InternetAddress a, int puerto) async {
  for (var i = 0; i < 20; i++) {
    try {
      if (socket.send(datos, a, puerto) > 0) return;
    } catch (_) {
      return; // Esa dirección no sirve (otra red, sin permiso): se sigue con las demás.
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
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
