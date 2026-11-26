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
  RespondeBusqueda({
    required this.eventoId,
    required this.puertoCentral,
    this.barra,
    this.equipo,
    this.esperaParaReabrir = const Duration(seconds: 1),
  });

  final String eventoId;
  final int puertoCentral;
  final String? barra;
  final String? equipo;

  /// Cuánto espera para volver a abrir el socket que se murió.
  final Duration esperaParaReabrir;
  RawDatagramSocket? _socket;
  int _puerto = kPuertoBusquedaBarra;
  InternetAddress? _en;
  var _cerrado = false;
  Timer? _reabrir;

  /// Empieza a escuchar en [puerto], en todas las conexiones de la PC ([en] en las
  /// pruebas: solo esta PC). Si no puede (el puerto está tomado), sigue sin contestar: la
  /// cajera todavía puede escribir la dirección.
  ///
  /// **Si después el socket se muere** (un cambio de wifi, 26-nov-2026: la notebook dejaba
  /// de contestar hasta apagar y prender la central), **se vuelve a abrir solo**.
  Future<bool> escuchar({int puerto = kPuertoBusquedaBarra, InternetAddress? en}) async {
    _cerrado = false;
    _puerto = puerto;
    _en = en;
    return _abrir();
  }

  /// Cambió la red de este equipo: se cierra el socket y se abre otro, aunque el de antes
  /// parezca vivo.
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
        (evento) {
          if (evento == RawSocketEvent.closed) {
            _seMurio(s);
            return;
          }
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
        },
        onError: (Object _) => _seMurio(s),
        onDone: () => _seMurio(s),
      );
      return true;
    } catch (e) {
      debugPrint('Central de la barra: no se pudo escuchar la búsqueda: $e');
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

/// En la caja: pregunta a toda la red del salón dónde está la central de la fiesta, hasta
/// que contesta o se la deja de buscar. En la notebook, lo mismo para encontrar **la
/// central de la otra barra** y engancharse con ella.
class BuscaCentral {
  BuscaCentral({
    required this.eventoId,
    this.cada = const Duration(seconds: 3),
    this.renovarCada = const Duration(seconds: 30),
    int puerto = kPuertoBusquedaBarra,
    List<int>? puertos,
    Future<List<InternetAddress>> Function()? destinos,
  })  : puertos = puertos ?? [puerto],
        _destinos = destinos ?? destinosDeLaRed;

  final String eventoId;
  final Duration cada;

  /// **Mientras nadie contesta, cada tanto se pregunta con un socket nuevo** (26-nov-2026):
  /// el de antes pudo quedar atado a la red de antes (la tablet se fue a otro wifi y
  /// volvió) y no recibir más las respuestas, sin ningún error.
  final Duration renovarCada;

  /// A qué puertos se pregunta. En la app, uno solo (el 8777); las ventanas de prueba,
  /// con dos centrales en la misma PC, preguntan a los dos.
  final List<int> puertos;
  int get puerto => puertos.first;
  final Future<List<InternetAddress>> Function() _destinos;

  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Cuántos sockets abrió para preguntar (las pruebas miran que se renueve).
  @visibleForTesting
  int socketsAbiertos = 0;

  /// Cuántas veces se empezó a buscar: si se vuelve a empezar mientras la anterior
  /// todavía abría su socket, la anterior se descarta (no quedan dos buscando).
  var _vuelta = 0;

  /// Busca. [encontrada] se llama una vez por cada respuesta.
  ///
  /// **No deja de buscar nunca por un socket muerto** (26-nov-2026: un cambio de wifi lo
  /// mataba y la tablet ya no encontraba la central hasta que se apagaba y prendía): si el
  /// socket se muere o no se puede abrir, se vuelve a empezar al segundo; y cada
  /// [renovarCada] sin respuesta, también.
  Future<void> buscar(void Function(DondeEstaLaCentral) encontrada) async {
    parar();
    final esta = ++_vuelta;
    void empezarDeNuevo(Duration espera) {
      Timer(espera, () {
        if (esta == _vuelta) unawaited(buscar(encontrada));
      });
    }

    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (esta != _vuelta) {
        s.close();
        return;
      }
      s.broadcastEnabled = true;
      _socket = s;
      socketsAbiertos++;
      void murio() {
        if (esta != _vuelta || !identical(s, _socket)) return;
        _timer?.cancel();
        _timer = null;
        _socket = null;
        empezarDeNuevo(const Duration(seconds: 1));
      }

      s.listen(
        (evento) {
          if (evento == RawSocketEvent.closed) {
            murio();
            return;
          }
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
        },
        onError: (Object _) => murio(),
        onDone: murio,
      );
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

      final rondasPorSocket = (renovarCada.inMilliseconds / cada.inMilliseconds).ceil().clamp(1, 1 << 20);
      var rondas = 0;
      _timer = Timer.periodic(cada, (_) {
        if (esta != _vuelta) return;
        if (++rondas >= rondasPorSocket) {
          // Un socket nuevo, por si el de antes quedó atado a la red de antes.
          unawaited(buscar(encontrada));
          return;
        }
        unawaited(preguntar());
      });
      await preguntar();
    } catch (e) {
      debugPrint('Barra: no se pudo buscar la central: $e');
      // Sin red en este momento (se está cambiando de wifi): se prueba de nuevo.
      if (esta == _vuelta) empezarDeNuevo(const Duration(seconds: 2));
    }
  }

  void parar() {
    _vuelta++;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  /// Lo que le hace al socket un cambio de red: se muere sin que nadie lo cierre.
  @visibleForTesting
  void matarElSocketParaPrueba() => _socket?.close();
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
