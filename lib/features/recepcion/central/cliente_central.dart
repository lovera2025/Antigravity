import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/puerta_del_evento.dart';
import 'pedidos_de_la_puerta.dart';

/// El celular de la puerta, del lado del celular: se conecta a la central
/// (`CentralPuerta`) por el wifi del router, recibe la lista y le manda lo que
/// se ingresa.
///
/// - **Lo que se toca se ve al instante**, aunque la respuesta tarde: hasta que
///   la central contesta, la lista se muestra con eso puesto ([puerta]).
/// - **Sin conexión con la central se sigue marcando.** Lo marcado queda en el
///   celular ([pendientes], guardado, por si se cierra el navegador) y se manda
///   solo al volver, en el orden en que se tocó y diciendo cuánto hace: así la
///   central sabe si todavía se saluda en el tótem.
/// - **La central decide.** Si otro celular ya lo había ingresado, contesta "ya
///   ingresó a las 22:41 · Pato" y eso es lo que se dice ([avisos]).
///
/// Sin pantalla: la pantalla del celular (`PantallaPuesto`) lo escucha.
class ClienteCentral extends ChangeNotifier {
  ClienteCentral({
    required this.servidor,
    required GuardadoDelCelular guardado,
    DateTime Function()? ahora,
    WebSocketChannel Function(Uri)? abrir,
    this.latido = const Duration(seconds: 5),
    this.silencioMaximo = const Duration(seconds: 12),
    this.pausa = const Duration(seconds: 1),
  })  : _guardado = guardado,
        _ahora = ahora ?? DateTime.now,
        _abrir = abrir ?? WebSocketChannel.connect;

  /// La dirección de la central: la misma de la que se bajó la página.
  final Uri servidor;
  final GuardadoDelCelular _guardado;
  final DateTime Function() _ahora;
  final WebSocketChannel Function(Uri) _abrir;

  /// Cada cuánto se le pregunta a la central si sigue ahí.
  final Duration latido;

  /// Sin noticias de la central en este tiempo, se da la conexión por caída.
  final Duration silencioMaximo;

  /// La espera entre reintentos: una vez, dos, hasta cinco. Un pedido que la
  /// central no pudo hacer se vuelve a mandar a las tres.
  final Duration pausa;

  EstadoDelPuesto _estado = EstadoDelPuesto.cargando;
  EstadoDelPuesto get estado => _estado;

  String _celular = '';
  String? _nombre;
  String? _codigo;
  String? get nombre => _nombre;
  String? get codigo => _codigo;

  String? _eventoId;
  String? get eventoId => _eventoId;

  /// "ESCUELA NORMAL — Egresados (12/12) · masivo", como lo nombra la PC.
  String? _titulo;
  String? get titulo => _titulo;

  Map<String, dynamic>? _lista;
  var _version = 0;
  Map<String, String> _por = const {};

  final _pendientes = <PedidoPendiente>[];
  List<PedidoPendiente> get pendientes => List.unmodifiable(_pendientes);

  /// Los que la central ya contestó pero todavía no están en la lista que
  /// mandó: se siguen mostrando hasta que llegue una más nueva.
  final _confirmados = <(PedidoPendiente, int)>[];
  final _enCamino = <String>{};

  /// Cuántos se mandaron al volver la conexión, para decirlo un rato.
  int _seMandaron = 0;
  int get seMandaron => _seMandaron;
  Timer? _borrarSeMandaron;

  final _avisos = StreamController<String>.broadcast();

  /// Lo que la central contestó cuando no hizo lo que se pidió: "PÉREZ, JUAN ya
  /// ingresó a las 22:41 · Pato.".
  Stream<String> get avisos => _avisos.stream;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escucha;
  Timer? _reintento;
  Timer? _latidos;
  DateTime _ultimaNoticia = DateTime.fromMillisecondsSinceEpoch(0);
  var _intentos = 0;
  var _cerrado = false;

  PuertaDelEvento? _puertaArmada;
  var _sucia = true;

  // ── Desde afuera ──────────────────────────────────────────────────────────

  /// Lee lo guardado y, si ya se sabe el nombre, se conecta. [codigoDelEnlace]
  /// es el que trae el QR (`?c=4821`).
  Future<void> iniciar({String? codigoDelEnlace}) async {
    _celular = await _guardado.leer(_kCelular) ?? '';
    if (_celular.isEmpty) {
      _celular = const Uuid().v4();
      await _guardado.guardar(_kCelular, _celular);
    }
    _nombre = await _guardado.leer(_kNombre);
    if (codigoDelEnlace != null && _esCodigo(codigoDelEnlace)) {
      _codigo = codigoDelEnlace;
      await _guardado.guardar(_kCodigo, _codigo);
    } else {
      _codigo = await _guardado.leer(_kCodigo);
    }
    _pendientes
      ..clear()
      ..addAll(PedidoPendiente.listaDesdeTexto(await _guardado.leer(_kPendientes)));
    _sucia = true;
    if (_faltaAlgo) {
      _poner(EstadoDelPuesto.faltanDatos);
      return;
    }
    _conectar();
  }

  bool get _faltaAlgo =>
      (_nombre?.trim().isEmpty ?? true) || !_esCodigo(_codigo ?? '');

  static bool _esCodigo(String c) => RegExp(r'^\d{4}$').hasMatch(c.trim());

  /// El nombre de quien usa el celular y, si no vino en el QR, el código que
  /// muestra la PC.
  Future<void> ponerDatos({required String nombre, String? codigo}) async {
    _nombre = nombre.trim();
    await _guardado.guardar(_kNombre, _nombre);
    if (codigo != null && _esCodigo(codigo)) {
      _codigo = codigo.trim();
      await _guardado.guardar(_kCodigo, _codigo);
    }
    if (_faltaAlgo) {
      _poner(EstadoDelPuesto.faltanDatos);
      return;
    }
    _intentos = 0;
    _conectar();
  }

  /// La lista como se ve en este celular: la de la central, con lo que se
  /// tocó acá y todavía no está en ella.
  PuertaDelEvento? get puerta {
    final lista = _lista;
    final eventoId = _eventoId;
    if (lista == null || eventoId == null) return null;
    if (_sucia || _puertaArmada == null) {
      final cambios = [
        for (final (c, _) in _confirmados) c,
        ..._pendientes,
      ];
      _puertaArmada = PuertaDelEvento.fromJson(
        cambios.isEmpty ? lista : listaConCambios(lista, cambios),
        eventoId: eventoId,
      );
      _sucia = false;
    }
    return _puertaArmada;
  }

  /// Lo que se agrega a "ADENTRO · 22:41" de [personaId]: que todavía no se
  /// mandó (sin conexión), o quién lo ingresó.
  String? marca(String personaId) {
    final esperando = _pendientes.any((p) => p.pedido.personaId == personaId);
    if (esperando && _estado != EstadoDelPuesto.conectado) return kPorMandar;
    if (esperando ||
        _confirmados.any((c) => c.$1.pedido.personaId == personaId)) {
      final ultimo = [
        for (final (c, _) in _confirmados) c,
        ..._pendientes,
      ].lastWhere((p) => p.pedido.personaId == personaId);
      return ultimo.pedido.que == QuePide.ingresar ? _nombre : null;
    }
    return _por[personaId];
  }

  Future<void> ingresar(PersonaPuerta persona) =>
      _pedir(QuePide.ingresar, persona.id);

  Future<void> deshacer(PersonaPuerta persona) =>
      _pedir(QuePide.deshacer, persona.id);

  /// "Actualizar la lista": se vuelve a conectar ya, sin esperar el reintento.
  void reconectar() {
    if (_faltaAlgo || _cerrado) return;
    _intentos = 0;
    _conectar();
  }

  @override
  void dispose() {
    _cerrado = true;
    _reintento?.cancel();
    _latidos?.cancel();
    _borrarSeMandaron?.cancel();
    unawaited(_escucha?.cancel());
    unawaited(_canal?.sink.close());
    unawaited(_avisos.close());
    super.dispose();
  }

  // ── Por dentro ────────────────────────────────────────────────────────────

  void _poner(EstadoDelPuesto nuevo) {
    _estado = nuevo;
    _sucia = true;
    if (!_cerrado) notifyListeners();
  }

  Future<void> _pedir(QuePide que, String personaId) async {
    final p = PedidoPendiente(
      PedidoPuerta(id: const Uuid().v4(), que: que, personaId: personaId),
      marcado: _ahora(),
    );
    _pendientes.add(p);
    _sucia = true;
    await _guardarPendientes();
    if (!_cerrado) notifyListeners();
    _mandarPendientes();
  }

  Future<void> _guardarPendientes() => _guardado.guardar(
        _kPendientes,
        PedidoPendiente.listaATexto(_pendientes),
      );

  void _conectar() {
    if (_cerrado) return;
    _reintento?.cancel();
    _latidos?.cancel();
    unawaited(_escucha?.cancel());
    unawaited(_canal?.sink.close());
    _enCamino.clear();

    if (_estado != EstadoDelPuesto.conectado &&
        _estado != EstadoDelPuesto.sinConexion) {
      _poner(EstadoDelPuesto.conectando);
    }
    final esSeguro = servidor.scheme == 'https';
    final uri = servidor.replace(
      scheme: esSeguro ? 'wss' : 'ws',
      path: '/vivo',
      queryParameters: {'c': _codigo!, 'id': _celular, 'p': _nombre!},
    );
    final WebSocketChannel canal;
    try {
      canal = _abrir(uri);
    } catch (_) {
      _seCorto(null);
      return;
    }
    _canal = canal;
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
        // La central no contesta: el wifi se cortó sin avisar.
        unawaited(canal.sink.close());
        _seCorto(null);
        return;
      }
      _mandar({'t': 'hola'});
    });
  }

  void _seCorto(int? codigoDeCierre) {
    if (_cerrado) return;
    _canal = null;
    _latidos?.cancel();
    _enCamino.clear();
    switch (codigoDeCierre) {
      case 4001:
        _poner(EstadoDelPuesto.codigoMal);
        return;
      case 4002:
        _poner(EstadoDelPuesto.faltanDatos);
        return;
      case 4003:
        _poner(EstadoDelPuesto.otraPestana);
        return;
      case 4029:
        _poner(EstadoDelPuesto.frenado);
        _reintento = Timer(pausa * 60, _conectar);
        return;
    }
    // Con la lista ya bajada se sigue trabajando; sin ella, se espera.
    _poner(_lista == null ? EstadoDelPuesto.conectando : EstadoDelPuesto.sinConexion);
    _intentos++;
    _reintento = Timer(pausa * (_intentos < 5 ? _intentos : 5), _conectar);
  }

  void _mandar(Map<String, Object?> mensaje) {
    try {
      _canal?.sink.add(jsonEncode(mensaje));
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
      case 'puerta':
        _recibirLista(json);
      case 'esperando':
        _intentos = 0;
        _poner(EstadoDelPuesto.conectado);
      case 'respuesta':
        unawaited(_recibirRespuesta(json));
      case 'codigo':
      case 'espera':
      case 'nombre':
        // Llega antes del cierre, que es el que dice qué hacer.
        break;
    }
  }

  void _recibirLista(Map<String, dynamic> m) {
    final v = m['v'];
    final lista = m['puerta'];
    final evento = m['evento'];
    if (v is! int || lista is! Map<String, dynamic> || evento is! String) {
      return;
    }
    final volvio = _estado != EstadoDelPuesto.conectado;
    // Una central que se reinició vuelve a contar desde 1.
    if (v <= _version && !volvio && evento == _eventoId) return;
    _version = v;
    _lista = lista;
    _eventoId = evento;
    final titulo = m['titulo'];
    _titulo = titulo is String && titulo.isNotEmpty ? titulo : null;
    final por = m['por'];
    _por = por is Map
        ? {for (final e in por.entries) '${e.key}': '${e.value}'}
        : const {};
    _confirmados.removeWhere((c) => c.$2 < v || volvio);
    _intentos = 0;
    _poner(EstadoDelPuesto.conectado);
    if (volvio && _pendientes.isNotEmpty) _alVolverHay = _pendientes.length;
    _mandarPendientes();
  }

  /// Cuántos había para mandar cuando volvió la conexión.
  int _alVolverHay = 0;

  void _mandarPendientes() {
    if (_estado != EstadoDelPuesto.conectado || _canal == null) return;
    final ahora = _ahora();
    for (final p in _pendientes) {
      if (!_enCamino.add(p.pedido.id)) continue;
      final hace = ahora.difference(p.marcado);
      _mandar(PedidoPuerta(
        id: p.pedido.id,
        que: p.pedido.que,
        personaId: p.pedido.personaId,
        hace: hace.isNegative ? Duration.zero : hace,
      ).toJson());
    }
  }

  Future<void> _recibirRespuesta(Map<String, dynamic> m) async {
    final id = m['id'];
    final i = _pendientes.indexWhere((p) => p.pedido.id == id);
    if (i < 0) return;
    if (m['ok'] != true) {
      // La central no pudo: se vuelve a mandar en un rato.
      _enCamino.remove(id);
      Timer(pausa * 3, () {
        if (!_cerrado) _mandarPendientes();
      });
      return;
    }
    final hecho = _pendientes.removeAt(i);
    _enCamino.remove(id);
    // Si la central no hizo nada (ya había entrado por otro celular), lo que
    // vale es su lista, con su hora y su nombre: no se sigue mostrando lo que
    // se tocó acá.
    if (m['hizo'] != 'nada') _confirmados.add((hecho, _version));
    _sucia = true;
    await _guardarPendientes();
    final aviso = m['aviso'];
    if (aviso is String && aviso.isNotEmpty && !_avisos.isClosed) {
      _avisos.add(aviso);
    }
    if (_alVolverHay > 0 && _pendientes.isEmpty) {
      _seMandaron = _alVolverHay;
      _alVolverHay = 0;
      _borrarSeMandaron?.cancel();
      _borrarSeMandaron = Timer(const Duration(seconds: 6), () {
        _seMandaron = 0;
        if (!_cerrado) notifyListeners();
      });
    }
    if (!_cerrado) notifyListeners();
  }
}

/// En qué anda el celular.
enum EstadoDelPuesto {
  /// Leyendo lo guardado.
  cargando,

  /// Falta el nombre, o el código si no vino en el QR.
  faltanDatos,

  /// Buscando a la central, todavía sin la lista.
  conectando,

  conectado,

  /// Tenía la lista y se cortó: se sigue marcando.
  sinConexion,

  /// La central no reconoce el código: cambió, o se escribió mal.
  codigoMal,

  /// Demasiados códigos mal seguidos: hay que esperar un minuto.
  frenado,

  /// El mismo celular se abrió en otra pestaña, que quedó a cargo.
  otraPestana,
}

/// Algo que se tocó en el celular y la central todavía no contestó.
class PedidoPendiente {
  final PedidoPuerta pedido;

  /// Cuándo se tocó, con el reloj del celular.
  final DateTime marcado;

  const PedidoPendiente(this.pedido, {required this.marcado});

  static List<PedidoPendiente> listaDesdeTexto(String? texto) {
    if (texto == null || texto.isEmpty) return const [];
    try {
      final lista = jsonDecode(texto);
      if (lista is! List) return const [];
      return [
        for (final e in lista)
          if (e is Map<String, dynamic> &&
              PedidoPuerta.fromJson(e) != null &&
              e['marcado'] is int)
            PedidoPendiente(
              PedidoPuerta.fromJson(e)!,
              marcado:
                  DateTime.fromMillisecondsSinceEpoch(e['marcado'] as int),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String listaATexto(List<PedidoPendiente> lista) => jsonEncode([
        for (final p in lista)
          {...p.pedido.toJson(), 'marcado': p.marcado.millisecondsSinceEpoch},
      ]);
}

/// La lista que mandó la central ([PuertaDelEvento.toJson]) con [cambios]
/// puestos encima, en orden: ingresar deja a la persona adentro desde que se
/// tocó; deshacer, afuera. No toca [lista].
Map<String, dynamic> listaConCambios(
  Map<String, dynamic> lista,
  List<PedidoPendiente> cambios,
) {
  final copia = jsonDecode(jsonEncode(lista)) as Map<String, dynamic>;
  final personas = <String, Map<String, dynamic>>{};
  for (final g in copia['grupos'] as List) {
    final grupo = g as Map<String, dynamic>;
    final t = grupo['titular'] as Map<String, dynamic>;
    personas[t['id'] as String] = t;
    for (final a in grupo['acompanantes'] as List) {
      final ac = a as Map<String, dynamic>;
      personas[ac['id'] as String] = ac;
    }
  }
  for (final c in cambios) {
    final p = personas[c.pedido.personaId];
    if (p == null) continue;
    final adentro = c.pedido.que == QuePide.ingresar;
    final fila = (p['fila'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    if (!adentro && p['fila'] == null) continue;
    p['fila'] = {
      ...fila,
      'ingresado': adentro,
      'tocada': c.marcado.toUtc().toIso8601String(),
    };
  }
  return copia;
}

/// Lo que el celular guarda en el navegador.
abstract class GuardadoDelCelular {
  Future<String?> leer(String clave);
  Future<void> guardar(String clave, String? valor);
}

/// En el navegador del celular (el `localStorage` de la página).
class GuardadoEnElNavegador implements GuardadoDelCelular {
  @override
  Future<String?> leer(String clave) async {
    try {
      return (await SharedPreferences.getInstance()).getString(clave);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> guardar(String clave, String? valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (valor == null) {
        await prefs.remove(clave);
      } else {
        await prefs.setString(clave, valor);
      }
    } catch (_) {}
  }
}

const _kCelular = 'puesto_celular';
const _kNombre = 'puesto_nombre';
const _kCodigo = 'puesto_codigo';
const _kPendientes = 'puesto_pendientes';
