import 'dart:async';
import 'dart:io';

/// **Avisa cuando este equipo cambia de red** (26-nov-2026). El usuario probaba la barra
/// con un aparato en otro wifi; al volver al de la barra nada se actualizó hasta que apagó
/// y prendió la central. Un cambio de wifi deja muertos o atados a la red de antes los
/// sockets abiertos, y la dirección de la notebook puede cambiar.
///
/// Mira cada [cada] las direcciones IPv4 de este equipo y avisa por [cambios] cuando son
/// otras. Quien escucha vuelve a abrir lo suyo: la notebook, el socket que contesta "acá
/// estoy"; la tablet, la búsqueda de la central. **Solo mira este equipo**: no le pregunta
/// nada a la red ni a la nube.
class VigiaDeLaRed {
  VigiaDeLaRed({Future<Set<String>> Function()? direcciones, this.cada = const Duration(seconds: 5)})
      : _direcciones = direcciones ?? direccionesDeEsteEquipo;

  final Future<Set<String>> Function() _direcciones;
  final Duration cada;
  final _cambios = StreamController<void>.broadcast();
  Timer? _timer;
  Set<String>? _ultimas;
  var _mirando = false;

  /// Un aviso por cada cambio de las direcciones de este equipo.
  Stream<void> get cambios => _cambios.stream;

  void arrancar() {
    if (_timer != null || _cambios.isClosed) return;
    unawaited(_mirar());
    _timer = Timer.periodic(cada, (_) => unawaited(_mirar()));
  }

  Future<void> _mirar() async {
    if (_mirando) return;
    _mirando = true;
    try {
      final ahora = await _direcciones();
      final antes = _ultimas;
      _ultimas = ahora;
      if (antes != null && !_iguales(antes, ahora) && !_cambios.isClosed) _cambios.add(null);
    } catch (_) {
      // Sin poder leerlas (se está cambiando de wifi): la próxima vuelta.
    } finally {
      _mirando = false;
    }
  }

  static bool _iguales(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  void parar() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> cerrar() async {
    parar();
    await _cambios.close();
  }
}

/// Las direcciones IPv4 de este equipo, con su conexión ("Wi-Fi/192.168.0.10"): la misma
/// dirección en otra conexión también es otra red. Sin la de esta PC (127.0.0.1).
Future<Set<String>> direccionesDeEsteEquipo() async => {
      for (final c in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in c.addresses)
          if (!a.isLoopback) '${c.name}/${a.address}',
    };
