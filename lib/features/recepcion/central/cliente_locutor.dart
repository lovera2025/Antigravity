import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/lista_del_locutor.dart';
import 'cliente_central.dart' show GuardadoDelCelular;

/// En qué está la página del locutor.
enum EstadoDelLocutor {
  /// Falta el código del locutor (el QR no lo traía).
  pideCodigo,
  conectando,
  conectado,

  /// Se cortó: se ve lo último que llegó y vuelve sola.
  sinConexion,

  /// El código no es el del locutor de esta noche.
  codigoMal,

  /// La misma página se abrió en otra pestaña.
  otraPestana,

  /// Demasiados códigos equivocados: espera un minuto.
  frenado,
}

/// **El celular del locutor** (28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`, etapa 4):
/// se conecta a la central de la puerta por el wifi del salón con **su propio código**,
/// solo para mirar. Recibe la lista (institución → división → familias, con cómo
/// nombrarlos) cada vez que cambia. No puede ingresar a nadie ni cambiar nada.
///
/// Guarda lo último que llegó en el navegador: al recargar se ve igual mientras vuelve
/// la conexión. Sus claves son propias (`locutor_*`): un celular con una pestaña de puesto
/// y otra de locutor no se saca a sí mismo.
class ClienteLocutor extends ChangeNotifier {
  ClienteLocutor({
    required this.servidor,
    required GuardadoDelCelular guardado,
    WebSocketChannel Function(Uri)? abrir,
    this.latido = const Duration(seconds: 5),
    this.silencioMaximo = const Duration(seconds: 12),
    this.pausa = const Duration(seconds: 1),
    DateTime Function()? ahora,
  })  : _guardado = guardado,
        _abrir = abrir ?? WebSocketChannel.connect,
        _ahora = ahora ?? DateTime.now;

  /// La dirección de la notebook (la página la sirve ella).
  final Uri servidor;
  final Duration latido;
  final Duration silencioMaximo;
  final Duration pausa;
  final GuardadoDelCelular _guardado;
  final WebSocketChannel Function(Uri) _abrir;
  final DateTime Function() _ahora;

  static const _kCelular = 'locutor_celular';
  static const _kCodigo = 'locutor_codigo';
  static const _kLista = 'locutor_lista';
  static const _kVistos = 'locutor_vistos';

  /// Cuánto dura el NUEVO de una familia cambiada (o hasta tocarla).
  static const duraElNuevo = Duration(minutes: 30);

  EstadoDelLocutor estado = EstadoDelLocutor.conectando;

  /// La fiesta (el título que manda la central).
  String? titulo;

  /// Lo último que llegó (o lo guardado, al abrir).
  ListaDelLocutor lista = ListaDelLocutor.vacia;

  /// Si llegó alguna vez una lista (o había una guardada).
  bool hayLista = false;

  /// Conectado, pero la PC todavía no tiene la lista.
  bool esperando = false;

  /// Desde cuándo está sin conexión (la hora del celular).
  DateTime? sinConexionDesde;

  String _celular = '';
  String? _codigo;
  final _vistos = <String, int>{};
  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escucha;
  Timer? _latidos;
  Timer? _reintento;
  var _intentos = 0;
  var _cerrado = false;
  DateTime _ultimaNoticia = DateTime.now();

  /// La hora de la central menos la del celular: el NUEVO no depende de la hora del
  /// celular.
  Duration _corrimiento = Duration.zero;

  final _cambios = StreamController<List<FamiliaDelLocutor>>.broadcast();

  /// Las familias que cambiaron en la lista que acaba de llegar (para el aviso de arriba).
  Stream<List<FamiliaDelLocutor>> get cambios => _cambios.stream;

  bool get conectado => estado == EstadoDelLocutor.conectado;

  String? get codigo => _codigo;

  /// La hora de la central.
  DateTime ahoraDeLaCentral() => _ahora().add(_corrimiento);

  // ── Desde afuera ──────────────────────────────────────────────────────────

  /// Lee lo guardado y se conecta. [codigoDelEnlace] es el del QR (`?locutor=4821`).
  Future<void> iniciar({String? codigoDelEnlace}) async {
    _celular = await _guardado.leer(_kCelular) ?? '';
    if (_celular.isEmpty) {
      _celular = const Uuid().v4();
      await _guardado.guardar(_kCelular, _celular);
    }
    if (codigoDelEnlace != null && esCodigo(codigoDelEnlace)) {
      _codigo = codigoDelEnlace.trim();
      await _guardado.guardar(_kCodigo, _codigo);
    } else {
      _codigo = await _guardado.leer(_kCodigo);
    }
    _leerGuardado(await _guardado.leer(_kLista));
    try {
      final v = jsonDecode(await _guardado.leer(_kVistos) ?? '{}');
      if (v is Map) {
        for (final e in v.entries) {
          if (e.key is String && e.value is int) _vistos[e.key as String] = e.value as int;
        }
      }
    } catch (_) {}
    if (!esCodigo(_codigo ?? '')) {
      _poner(EstadoDelLocutor.pideCodigo);
      return;
    }
    _conectar();
  }

  static bool esCodigo(String c) => RegExp(r'^\d{4}$').hasMatch(c.trim());

  /// El código que dicta la PC (si el QR no lo traía).
  Future<void> ponerCodigo(String c) async {
    if (!esCodigo(c)) return;
    _codigo = c.trim();
    await _guardado.guardar(_kCodigo, _codigo);
    _intentos = 0;
    _conectar();
  }

  /// La pantalla volvió a la vista (se desbloqueó el celular): si estaba cortada, de nuevo
  /// ya; si estaba conectada, pregunta por las dudas.
  void alVolverALaVista() {
    if (_cerrado) return;
    if (estado == EstadoDelLocutor.sinConexion || estado == EstadoDelLocutor.conectando) {
      _intentos = 0;
      _conectar();
    } else if (conectado) {
      _mandar({'t': 'hola'});
    }
  }

  /// Si [f] tiene un cambio que el locutor todavía no tocó, de los últimos 30 minutos.
  bool esNueva(FamiliaDelLocutor f) {
    final ca = f.cambiadoAt;
    if (ca == null || _vistos[f.id] == ca) return false;
    final cuando = DateTime.fromMillisecondsSinceEpoch(ca, isUtc: true);
    return ahoraDeLaCentral().toUtc().difference(cuando) < duraElNuevo;
  }

  /// La tocó: deja de ser NUEVO.
  void visto(FamiliaDelLocutor f) {
    final ca = f.cambiadoAt;
    if (ca == null || _vistos[f.id] == ca) return;
    _vistos[f.id] = ca;
    unawaited(_guardado.guardar(_kVistos, jsonEncode(_vistos)));
    if (!_cerrado) notifyListeners();
  }

  // ── La conexión ──────────────────────────────────────────────────────────

  void _conectar() {
    if (_cerrado) return;
    _reintento?.cancel();
    _latidos?.cancel();
    unawaited(_escucha?.cancel());
    try {
      unawaited(_canal?.sink.close());
    } catch (_) {}
    if (estado != EstadoDelLocutor.conectado && estado != EstadoDelLocutor.sinConexion) {
      _poner(EstadoDelLocutor.conectando);
    }
    final uri = servidor.replace(
      scheme: servidor.scheme == 'https' ? 'wss' : 'ws',
      path: '/vivo',
      queryParameters: {'c': _codigo!, 'id': _celular, 'p': 'Locutor', 'r': 'locutor'},
    );
    final WebSocketChannel canal;
    try {
      canal = _abrir(uri);
    } catch (_) {
      _seCorto(null);
      return;
    }
    _canal = canal;
    unawaited(canal.ready.then<void>((_) {}, onError: (Object _) {}));
    _ultimaNoticia = _ahora();
    _escucha = canal.stream.listen(
      _mensaje,
      onDone: () {
        if (identical(_canal, canal)) _seCorto(canal.closeCode);
      },
      onError: (Object _) {
        if (identical(_canal, canal)) _seCorto(null);
      },
      cancelOnError: true,
    );
    _latidos = Timer.periodic(latido, (_) {
      if (!identical(_canal, canal)) return;
      if (_ahora().difference(_ultimaNoticia) > silencioMaximo) {
        try {
          unawaited(canal.sink.close());
        } catch (_) {}
        _seCorto(null);
        return;
      }
      _mandar({'t': 'hola'});
    });
  }

  void _seCorto(int? codigo) {
    if (_cerrado) return;
    _canal = null;
    _latidos?.cancel();
    switch (codigo) {
      case 4001:
        _poner(EstadoDelLocutor.codigoMal);
        return;
      case 4003:
        _poner(EstadoDelLocutor.otraPestana);
        return;
      case 4029:
        _poner(EstadoDelLocutor.frenado);
        _reintento = Timer(pausa * 60, _conectar);
        return;
    }
    if (estado == EstadoDelLocutor.conectado || (hayLista && estado != EstadoDelLocutor.sinConexion)) {
      sinConexionDesde ??= _ahora();
      _poner(EstadoDelLocutor.sinConexion);
    } else if (estado != EstadoDelLocutor.sinConexion) {
      _poner(EstadoDelLocutor.conectando);
    }
    _intentos++;
    _reintento = Timer(pausa * (_intentos < 5 ? _intentos : 5), _conectar);
  }

  void _mandar(Map<String, Object?> m) {
    try {
      _canal?.sink.add(jsonEncode(m));
    } catch (_) {}
  }

  void _mensaje(dynamic texto) {
    _ultimaNoticia = _ahora();
    if (texto is! String) return;
    final Object? json;
    try {
      json = jsonDecode(texto);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'locutor':
        _recibir(json);
      case 'esperando':
        esperando = !hayLista;
        _conectado();
      case 'hola':
        _ajustarLaHora(json['ahora']);
        if (!conectado) _conectado();
    }
  }

  void _conectado() {
    _intentos = 0;
    sinConexionDesde = null;
    _poner(EstadoDelLocutor.conectado);
  }

  void _ajustarLaHora(Object? hora) {
    final h = hora is String ? DateTime.tryParse(hora) : null;
    if (h != null) _corrimiento = h.difference(_ahora());
  }

  void _recibir(Map<String, dynamic> m) {
    final nueva = ListaDelLocutor.fromJson(m['lista']);
    _ajustarLaHora(m['ahora']);
    final antes = {for (final f in lista.familias) f.id: f.cambiadoAt};
    final cambiaron = [
      if (hayLista)
        for (final f in nueva.familias)
          if (f.cambiadoAt != null && antes[f.id] != f.cambiadoAt) f,
    ];
    lista = nueva;
    titulo = m['titulo'] is String ? m['titulo'] as String : titulo;
    hayLista = true;
    esperando = false;
    unawaited(_guardado.guardar(_kLista, jsonEncode({'titulo': titulo, 'lista': nueva.toJson()})));
    _conectado();
    if (cambiaron.isNotEmpty && !_cambios.isClosed) _cambios.add(cambiaron);
  }

  void _leerGuardado(String? texto) {
    if (texto == null) return;
    try {
      final m = jsonDecode(texto);
      if (m is! Map) return;
      lista = ListaDelLocutor.fromJson(m['lista']);
      titulo = m['titulo'] is String ? m['titulo'] as String : null;
      hayLista = !lista.estaVacia || m['lista'] is List;
    } catch (_) {}
  }

  void _poner(EstadoDelLocutor nuevo) {
    estado = nuevo;
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _reintento?.cancel();
    _latidos?.cancel();
    unawaited(_escucha?.cancel());
    try {
      unawaited(_canal?.sink.close());
    } catch (_) {}
    unawaited(_cambios.close());
    super.dispose();
  }
}
