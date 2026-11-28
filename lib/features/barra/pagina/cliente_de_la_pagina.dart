import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../recepcion/central/cliente_central.dart' show GuardadoDelCelular;
import '../central/llave_de_la_barra.dart';
import '../cuentas/reglas_de_la_barra.dart';
import 'barra_de_la_pagina.dart';

/// Cómo está la página del iPhone con la notebook de la barra.
enum EstadoDeLaPagina {
  /// Pide el PIN (la primera vez, o la notebook se reinició).
  pidePin,

  /// Probando el PIN o la ficha de la noche.
  entrando,

  /// Conectada: lo que se anota llega a la notebook.
  conectada,

  /// Entró, pero se cortó: vuelve a conectarse sola, sin el PIN.
  sinConexion,
}

/// Quién entró a la página: la encargada, el repositor o el jefe (con el PIN maestro).
@immutable
class QuienEnLaPagina {
  final RolEnLaBarra rol;
  final String nombre;
  final String? operadorId;

  const QuienEnLaPagina({required this.rol, required this.nombre, this.operadorId});
}

/// No hay conexión con la notebook: nada se anotó.
class SinConexionConLaNotebook implements Exception {
  const SinConexionConLaNotebook();

  @override
  String toString() => 'Sin conexión con la notebook: no se anotó nada.';
}

/// La notebook no lo guardó, con el motivo (no le toca, la caja ya cerró…).
class LaNotebookNoLoGuardo implements Exception {
  final String motivo;
  const LaNotebookNoLoGuardo(this.motivo);

  @override
  String toString() => motivo;
}

/// **La página del iPhone de la encargada y del repositor** (28-nov-2026), hablando con
/// la central de la notebook de su barra por el wifi del salón, sin internet.
///
/// - **Entra solo con el PIN**, que no viaja: firma el reto de la central con las dos
///   llaves que salen del PIN (la de operador y la del maestro) y la central prueba
///   contra quien corresponda. La central firma de vuelta: una notebook de afuera no se
///   hace pasar por ella.
/// - **La ficha de la noche**: con ella, si el iPhone se bloquea o se cierra Safari,
///   vuelve a entrar sola, sin el PIN. Se guarda en el navegador la llave de la ficha
///   (no el PIN). Si la notebook se reinició, la ficha no vale y pide el PIN de nuevo.
/// - **Lo que anota no queda hecho hasta que la notebook contesta** ([escribir]): sin
///   conexión, no se anota nada.
/// - Todo lo de la fiesta llega de la notebook a [barra], en memoria.
class ClienteDeLaPagina extends ChangeNotifier {
  ClienteDeLaPagina({
    required this.servidor,
    required GuardadoDelCelular guardado,
    WebSocketChannel Function(Uri)? abrir,
    DateTime Function()? ahora,
    this.latido = const Duration(seconds: 5),
    this.silencioMaximo = const Duration(seconds: 12),
    this.esperaDeRespuesta = const Duration(seconds: 10),
    this.pausas = const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 3), Duration(seconds: 5)],
    @visibleForTesting this.escucharTodo,
  })  : _guardado = guardado,
        _abrir = abrir ?? WebSocketChannel.connect,
        _ahoraDelTelefono = ahora ?? DateTime.now {
    barra = BarraDeLaPagina(this);
  }

  static const _claveEquipo = 'barra_pagina_equipo';
  static const _claveFicha = 'barra_pagina_ficha';

  /// De dónde se abrió la página: la notebook (`http://192.168.0.10:8797/`).
  final Uri servidor;
  final GuardadoDelCelular _guardado;
  final WebSocketChannel Function(Uri) _abrir;
  final DateTime Function() _ahoraDelTelefono;
  final Duration latido;
  final Duration silencioMaximo;
  final Duration esperaDeRespuesta;
  final List<Duration> pausas;

  /// Las pruebas miran todo lo que llega (que nunca llegue el precio de lista).
  final void Function(String mensaje)? escucharTodo;

  /// Lo de la fiesta, en memoria: lo que leen LAS CAJAS y STOCK.
  late final BarraDeLaPagina barra;

  EstadoDeLaPagina estado = EstadoDeLaPagina.pidePin;

  /// Lo que salió mal, dicho en palabras (null si nada).
  String? problema;

  /// Lo que dijo la central antes del PIN.
  String? fiesta;
  String? barraDelSalon;
  String? eventoId;

  QuienEnLaPagina? quien;

  /// La fiesta como la tiene la notebook (`Evento.toJson`, sin PIN ni observaciones).
  Map<String, dynamic>? evento;

  /// El id de este teléfono (se inventa la primera vez y se guarda).
  String equipo = '';

  final _llegoAlgo = StreamController<void>.broadcast();

  /// Llegó algo nuevo de la notebook: las pantallas se rehacen.
  Stream<void> get cambios => _llegoAlgo.stream;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escucha;
  Timer? _latido;
  Timer? _vuelta;
  var _intento = 0;
  var _cerrado = false;
  DateTime _ultimo = DateTime.now();

  /// La diferencia entre la hora de la notebook y la del teléfono: lo que anota la página
  /// va con la hora de la notebook, como lo de las tablets.
  Duration _corrimiento = Duration.zero;

  /// El PIN mientras se prueba; se olvida apenas entra.
  String? _pin;
  String? _reto;
  ({String id, List<int> secreto})? _ficha;
  final _pendientes = <String, Completer<String?>>{};

  /// La hora de la notebook (con la del teléfono corregida).
  DateTime ahora() => _ahoraDelTelefono().add(_corrimiento);

  bool get conectada => estado == EstadoDeLaPagina.conectada;

  /// Al abrir la página: si tiene la ficha de la noche, entra sola.
  Future<void> iniciar() async {
    var id = await _guardado.leer(_claveEquipo);
    if (id == null || id.length < 8) {
      id = 'pagina-${const Uuid().v4()}';
      await _guardado.guardar(_claveEquipo, id);
    }
    equipo = id;
    final guardada = await _guardado.leer(_claveFicha);
    if (guardada != null) {
      try {
        final m = jsonDecode(guardada) as Map<String, dynamic>;
        final secreto = [
          for (var i = 0; i + 1 < (m['s'] as String).length; i += 2)
            int.parse((m['s'] as String).substring(i, i + 2), radix: 16),
        ];
        _ficha = (id: m['f'] as String, secreto: secreto);
      } catch (_) {
        await _guardado.guardar(_claveFicha, null);
      }
    }
    if (_ficha != null) {
      _cambiar(EstadoDeLaPagina.entrando);
      _conectar();
    } else {
      _cambiar(EstadoDeLaPagina.pidePin);
    }
  }

  /// Entrar con el PIN.
  void entrar(String pin) {
    final p = pin.trim();
    if (p.isEmpty || estado == EstadoDeLaPagina.entrando) return;
    _pin = p;
    problema = null;
    _cambiar(EstadoDeLaPagina.entrando);
    _conectar();
  }

  /// Salir: se olvida la ficha y vuelve a pedir el PIN.
  Future<void> salir() async {
    _ficha = null;
    quien = null;
    await _guardado.guardar(_claveFicha, null);
    _cortar();
    problema = null;
    _cambiar(EstadoDeLaPagina.pidePin);
  }

  /// La pantalla volvió a la vista (se desbloqueó el iPhone): si estaba cortada, vuelve
  /// a conectarse ya; si estaba conectada, pregunta por las dudas.
  void alVolverALaVista() {
    if (_cerrado) return;
    if (estado == EstadoDeLaPagina.sinConexion && _ficha != null) {
      _vuelta?.cancel();
      _intento = 0;
      _conectar();
    } else if (conectada) {
      _mandar({'t': 'hola'});
    }
  }

  /// **Anota una fila nueva en la notebook** y espera que conteste. Recién entonces queda
  /// en [barra]. Sin conexión tira [SinConexionConLaNotebook]; si la notebook no la
  /// guarda, [LaNotebookNoLoGuardo] con el motivo.
  Future<void> escribir(String tabla, Map<String, Object?> fila) async {
    if (!conectada) throw const SinConexionConLaNotebook();
    final pedido = LlaveDeLaBarra.reto();
    final espera = Completer<String?>();
    _pendientes[pedido] = espera;
    _mandar({'t': 'escribe', 'pedido': pedido, 'tabla': tabla, 'fila': fila});
    final String? motivo;
    try {
      motivo = await espera.future.timeout(esperaDeRespuesta);
    } on TimeoutException {
      throw const SinConexionConLaNotebook();
    } finally {
      _pendientes.remove(pedido);
    }
    if (motivo != null) throw LaNotebookNoLoGuardo(motivo);
    barra.poner(tabla, fila);
    if (!_llegoAlgo.isClosed) _llegoAlgo.add(null);
  }

  // ── La conexión ──────────────────────────────────────────────────────────

  void _conectar() {
    _cortar();
    if (_cerrado) return;
    final reto = LlaveDeLaBarra.reto();
    _reto = reto;
    final uri = Uri(
      scheme: servidor.scheme == 'https' ? 'wss' : 'ws',
      host: servidor.host,
      port: servidor.hasPort ? servidor.port : null,
      path: '/pagina',
      queryParameters: {'equipo': equipo, 'r': reto},
    );
    final WebSocketChannel canal;
    try {
      canal = _abrir(uri);
    } catch (_) {
      _seCorto(null);
      return;
    }
    _canal = canal;
    _ultimo = _ahoraDelTelefono();
    _escucha = canal.stream.listen(
      (m) => _alRecibir(m, canal),
      onDone: () => _seCerro(canal),
      onError: (Object _) => _seCerro(canal),
      cancelOnError: true,
    );
    _latido = Timer.periodic(latido, (_) {
      if (!identical(_canal, canal)) return;
      if (_ahoraDelTelefono().difference(_ultimo) > silencioMaximo) {
        // La notebook no contesta (se fue del wifi, se bloqueó el iPhone): de nuevo.
        _seCerro(canal, porSilencio: true);
        return;
      }
      if (conectada) _mandar({'t': 'hola'});
    });
  }

  void _cortar() {
    _latido?.cancel();
    _latido = null;
    _vuelta?.cancel();
    _vuelta = null;
    unawaited(_escucha?.cancel());
    _escucha = null;
    final c = _canal;
    _canal = null;
    if (c != null) {
      try {
        unawaited(c.sink.close());
      } catch (_) {}
    }
  }

  void _mandar(Map<String, Object?> mensaje) {
    try {
      _canal?.sink.add(jsonEncode(mensaje));
    } catch (_) {}
  }

  void _alRecibir(dynamic mensaje, WebSocketChannel canal) {
    if (!identical(_canal, canal) || mensaje is! String) return;
    escucharTodo?.call(mensaje);
    _ultimo = _ahoraDelTelefono();
    final Object? json;
    try {
      json = jsonDecode(mensaje);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'reto':
        _alReto(json);
      case 'adelante':
        unawaited(_adelante(json));
      case 'catalogo':
      case 'filas':
        if (json['evento'] case final Map<String, dynamic> e) evento = e;
        final filas = json['filas'];
        if (filas is Map) {
          barra.recibir(filas);
          if (!_llegoAlgo.isClosed) _llegoAlgo.add(null);
        }
      case 'respuesta':
        final espera = _pendientes[json['pedido']];
        if (espera != null && !espera.isCompleted) {
          espera.complete(json['ok'] == true ? null : (json['motivo']?.toString() ?? 'La notebook no lo guardó.'));
        }
      case 'hola':
        _ajustarLaHora(json['hora']);
      case 'espera':
        problema = 'Demasiados intentos con un PIN equivocado: esperá un minuto.';
    }
  }

  void _alReto(Map<String, dynamic> json) {
    final n = json['n'];
    final evento = json['evento'];
    if (n is! String || evento is! String) return;
    eventoId = evento;
    fiesta = json['fiesta'] as String?;
    barraDelSalon = json['barra'] as String?;
    String firmar(List<int> llave) => LlaveDeLaBarra.firma(llave, lado: 'caja', reto: n, evento: evento, equipo: equipo);
    final pin = _pin;
    final ficha = _ficha;
    if (pin != null) {
      _mandar({
        't': 'soy',
        'quien': 'pin',
        'operador': firmar(LlaveDeLaBarra.deOperador(pin)),
        'maestro': firmar(LlaveDeLaBarra.deMaestro(pin)),
      });
    } else if (ficha != null) {
      _mandar({'t': 'soy', 'quien': 'ficha', 'ficha': ficha.id, 'prueba': firmar(ficha.secreto)});
    } else {
      _cortar();
      _cambiar(EstadoDeLaPagina.pidePin);
    }
  }

  Future<void> _adelante(Map<String, dynamic> json) async {
    final evento = eventoId, reto = _reto;
    final rol = RolEnLaBarra.values.where((r) => r.name == json['rol']).firstOrNull;
    final quienFue = json['quien'];
    final pin = _pin;
    List<int>? llave;
    if (quienFue == 'maestro' && pin != null) llave = LlaveDeLaBarra.deMaestro(pin);
    if (quienFue == 'operador' && pin != null) llave = LlaveDeLaBarra.deOperador(pin);
    if (quienFue == 'ficha') llave = _ficha?.secreto;
    final prueba = json['prueba'];
    final esperada = llave == null || evento == null || reto == null
        ? null
        : LlaveDeLaBarra.firma(llave, lado: 'central', reto: reto, evento: evento, equipo: equipo);
    if (rol == null || esperada == null || prueba is! String || !LlaveDeLaBarra.iguales(prueba, esperada)) {
      // No es la notebook de la barra (o algo raro): no se le cree.
      _cortar();
      problema = 'No es la notebook de la barra. Abrí la página desde el QR de la notebook.';
      _cambiar(EstadoDeLaPagina.pidePin);
      return;
    }
    final fichaNueva = json['ficha'];
    if (fichaNueva is String && llave != null) {
      final secreto = LlaveDeLaBarra.deLaFicha(llave, ficha: fichaNueva, equipo: equipo);
      _ficha = (id: fichaNueva, secreto: secreto);
      await _guardado.guardar(
        _claveFicha,
        jsonEncode({'f': fichaNueva, 's': [for (final b in secreto) b.toRadixString(16).padLeft(2, '0')].join()}),
      );
    }
    _pin = null;
    _intento = 0;
    quien = QuienEnLaPagina(
      rol: rol,
      nombre: (json['nombre'] as String?) ?? (rol == RolEnLaBarra.jefe ? 'Jefe' : ''),
      operadorId: json['operador'] as String?,
    );
    _ajustarLaHora(json['hora']);
    problema = null;
    _cambiar(EstadoDeLaPagina.conectada);
  }

  void _ajustarLaHora(Object? hora) {
    final h = hora is String ? DateTime.tryParse(hora) : null;
    if (h == null) return;
    _corrimiento = h.difference(_ahoraDelTelefono());
  }

  void _seCerro(WebSocketChannel canal, {bool porSilencio = false}) {
    if (!identical(_canal, canal)) return;
    _seCorto(porSilencio ? null : canal.closeCode);
  }

  void _seCorto(int? codigo) {
    _cortar();
    for (final p in _pendientes.values) {
      if (!p.isCompleted) p.completeError(const SinConexionConLaNotebook());
    }
    _pendientes.clear();
    if (_cerrado) return;
    final probandoPin = _pin != null;
    switch (codigo) {
      case 4006:
        _pin = null;
        problema = 'Ese PIN no es de una encargada ni de un repositor de barra.';
        _cambiar(EstadoDeLaPagina.pidePin);
        return;
      case 4008:
        _ficha = null;
        quien = null;
        unawaited(_guardado.guardar(_claveFicha, null));
        problema = 'La notebook se reinició: poné tu PIN de nuevo.';
        _cambiar(EstadoDeLaPagina.pidePin);
        return;
      case 4029:
        _pin = null;
        problema = 'Demasiados intentos con un PIN equivocado: esperá un minuto.';
        _cambiar(EstadoDeLaPagina.pidePin);
        return;
      case 4003:
        problema = 'La página se abrió en otra pestaña: seguí allá.';
        _cambiar(EstadoDeLaPagina.sinConexion);
        return;
    }
    if (probandoPin) {
      _pin = null;
      problema = 'No se encontró la notebook. ¿El teléfono está en el wifi de la barra?';
      _cambiar(EstadoDeLaPagina.pidePin);
      return;
    }
    if (_ficha == null) {
      _cambiar(EstadoDeLaPagina.pidePin);
      return;
    }
    // Ya había entrado: vuelve sola, sin el PIN.
    _cambiar(EstadoDeLaPagina.sinConexion);
    final pausa = pausas[_intento.clamp(0, pausas.length - 1)];
    _intento++;
    _vuelta = Timer(pausa, () {
      if (!_cerrado) _conectar();
    });
  }

  void _cambiar(EstadoDeLaPagina nuevo) {
    estado = nuevo;
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _cortar();
    unawaited(_llegoAlgo.close());
    super.dispose();
  }
}
