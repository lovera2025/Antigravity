import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../models/invitado.dart';
import '../services/puerta_del_evento.dart';
import 'pedidos_de_la_puerta.dart';

/// El puerto de la central. Si está ocupado se prueban los siguientes nueve.
const kPuertoCentral = 8787;

/// Cuántos códigos mal puestos seguidos se aceptan de un mismo celular antes de
/// frenarlo un minuto.
const kErroresDeCodigo = 5;
const kFrenoPorErrores = Duration(minutes: 1);

/// Lo que la central necesita de esta PC: leer una fila y marcar, igual que
/// Recepción. En la app es la base (`PuertaDeEstaPcConBase`); en las pruebas,
/// una en memoria.
abstract class PuertaDeEstaPc {
  /// La fila de la lista de la puerta, como está ahora en la base.
  Future<Invitado?> fila(String id);

  /// Ingresa a [persona]; si su fila no existe (un masivo antes del sorteo), la
  /// crea, como "Ingresar" en Recepción.
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  });

  Future<void> deshacer(String id);
}

/// Un celular que se conectó a la central esta noche.
class PuestoConectado {
  /// Lo inventa el celular la primera vez y lo guarda: así se lo reconoce al
  /// volver.
  final String celular;

  /// El nombre que puso quien lo usa: "Juli".
  final String nombre;
  final bool conectado;

  /// Cuándo se supo de él por última vez.
  final DateTime ultimaVez;

  /// Cuántos ingresó esta noche que siguen adentro.
  final int marcados;

  const PuestoConectado({
    required this.celular,
    required this.nombre,
    required this.conectado,
    required this.ultimaVez,
    required this.marcados,
  });
}

/// La central de la puerta: una notebook del salón a la que los celulares de
/// la puerta le piden ingresar o deshacer por el wifi del router, con o sin
/// internet.
///
/// - **A cada celular le manda la lista** (la misma [PuertaDelEvento] que ve
///   Recepción) apenas se conecta y cada vez que cambia ([ponerPuerta]).
/// - **Lo que le piden lo marca en la base de esta PC** ([PuertaDeEstaPc]),
///   como si lo hubieran tocado en su Recepción: la cola de subida y el aviso
///   al tótem quedan iguales. Los pedidos se atienden de a uno, mirando la base
///   en ese momento ([decidirPedido]): si dos celulares ingresan a la misma
///   persona, el segundo recibe "ya ingresó".
/// - **Solo atiende a quien trae el código** del QR (`CodigoCentral`).
/// - También sirve la página del celular ([paginaDelCelular]): sin internet,
///   el celular no tiene de dónde más bajarla.
///
/// Habla por WebSocket en `/vivo?c=<código>&id=<celular>&p=<nombre>`, con
/// mensajes JSON que llevan su tipo en `t`.
class CentralPuerta {
  CentralPuerta({
    required this.eventoId,
    required String codigo,
    required PuertaDeEstaPc pc,
    this.paginaDelCelular,
    DateTime Function()? ahora,
  })  : _codigo = codigo,
        _pc = pc,
        _ahora = ahora ?? DateTime.now;

  final String eventoId;
  final PuertaDeEstaPc _pc;

  /// La carpeta con la página que abre el celular, o null si no hay (en las
  /// pruebas).
  final Directory? paginaDelCelular;
  final DateTime Function() _ahora;

  String _codigo;
  HttpServer? _servidor;
  PuertaDelEvento? _puerta;
  String? _lista;
  var _version = 0;
  final _marcas = MarcasDeLaNoche();
  final _respuestas = <String, Map<String, Object?>>{};
  final _conexiones = <_Conexion>{};
  final _puestos = <String, PuestoConectado>{};
  final _errores = <String, List<DateTime>>{};
  var _fila = Future<void>.value();
  final _cambiosDePuestos =
      StreamController<List<PuestoConectado>>.broadcast();

  String get codigo => _codigo;
  int? get puerto => _servidor?.port;
  MarcasDeLaNoche get marcas => _marcas;

  /// Los celulares de esta noche: primero los conectados, por nombre.
  List<PuestoConectado> get puestos {
    final lista = _puestos.values.toList()
      ..sort((a, b) {
        if (a.conectado != b.conectado) return a.conectado ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return lista;
  }

  Stream<List<PuestoConectado>> get cambiosDePuestos =>
      _cambiosDePuestos.stream;

  /// Abre la central y devuelve en qué puerto quedó. [en] es por dónde se
  /// escucha: en la app, todas las conexiones de la PC; en las pruebas, solo
  /// esta PC (así Windows no pregunta por el cortafuegos).
  Future<int> arrancar({
    int desde = kPuertoCentral,
    InternetAddress? en,
  }) async {
    final donde = en ?? InternetAddress.anyIPv4;
    final intentos = desde == 0 ? 1 : 10;
    SocketException? ultimo;
    for (var i = 0; i < intentos && _servidor == null; i++) {
      try {
        _servidor = await HttpServer.bind(donde, desde == 0 ? 0 : desde + i);
      } on SocketException catch (e) {
        ultimo = e;
      }
    }
    final servidor = _servidor;
    if (servidor == null) throw ultimo!;
    servidor.listen(
      (pedido) => unawaited(_atender(pedido)),
      onError: (Object e) => debugPrint('Central de la puerta: $e'),
    );
    return servidor.port;
  }

  /// La lista cambió (alguien entró, se sorteó, se cargó un acompañante): se
  /// les manda a todos los celulares.
  void ponerPuerta(PuertaDelEvento puerta) {
    _puerta = puerta;
    _version++;
    _lista = jsonEncode({
      't': 'puerta',
      'v': _version,
      'evento': eventoId,
      'puerta': puerta.toJson(),
      'por': _marcas.todas,
    });
    for (final c in _conexiones) {
      c.mandar(_lista!);
    }
  }

  /// Otro código: los celulares conectados quedan afuera y tienen que volver a
  /// escanear.
  Future<void> cambiarCodigo(String nuevo) async {
    _codigo = nuevo;
    final viejas = _conexiones.toList();
    _conexiones.clear();
    _puestos.clear();
    for (final c in viejas) {
      c.mandar(jsonEncode({'t': 'codigo'}));
      await c.cerrar(4001, 'codigo');
    }
    _avisarPuestos();
  }

  Future<void> cerrar() async {
    final todas = _conexiones.toList();
    _conexiones.clear();
    for (final c in todas) {
      await c.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    await _servidor?.close(force: true);
    _servidor = null;
    await _cambiosDePuestos.close();
  }

  // ── Lo que llega por la red ───────────────────────────────────────────────

  Future<void> _atender(HttpRequest pedido) async {
    try {
      if (pedido.uri.path == '/vivo') {
        await _conectar(pedido);
        return;
      }
      if (pedido.method != 'GET' && pedido.method != 'HEAD') {
        pedido.response.statusCode = HttpStatus.methodNotAllowed;
        await pedido.response.close();
        return;
      }
      await _servirArchivo(pedido);
    } catch (e) {
      debugPrint('Central de la puerta, pedido ${pedido.uri.path}: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  bool _frenado(String ip) {
    final ahora = _ahora();
    final lista = _errores[ip];
    if (lista == null) return false;
    lista.removeWhere((t) => ahora.difference(t) >= kFrenoPorErrores);
    return lista.length >= kErroresDeCodigo;
  }

  Future<void> _conectar(HttpRequest pedido) async {
    if (!WebSocketTransformer.isUpgradeRequest(pedido)) {
      pedido.response.statusCode = HttpStatus.badRequest;
      await pedido.response.close();
      return;
    }
    final ip = pedido.connectionInfo?.remoteAddress.address ?? '';
    final datos = pedido.uri.queryParameters;
    final ws = await WebSocketTransformer.upgrade(pedido);

    // Se acepta la conexión antes de mirar el código: un navegador no deja
    // leer por qué se rechazó, así el celular puede decir qué pasó.
    if (_frenado(ip)) {
      ws.add(jsonEncode({'t': 'espera'}));
      await ws.close(4029, 'espera');
      return;
    }
    if (datos['c'] != _codigo) {
      (_errores[ip] ??= []).add(_ahora());
      ws.add(jsonEncode({'t': 'codigo'}));
      await ws.close(4001, 'codigo');
      return;
    }
    _errores.remove(ip);
    final celular = datos['id']?.trim() ?? '';
    final nombre = datos['p']?.trim() ?? '';
    if (celular.isEmpty ||
        celular.length > 64 ||
        nombre.isEmpty ||
        nombre.length > 40) {
      ws.add(jsonEncode({'t': 'nombre'}));
      await ws.close(4002, 'nombre');
      return;
    }

    // Si el mismo celular vuelve (se cortó el wifi y se reconectó), la conexión
    // vieja puede seguir colgada un rato: se cierra.
    for (final vieja
        in _conexiones.where((c) => c.celular == celular).toList()) {
      _conexiones.remove(vieja);
      unawaited(vieja.cerrar(4003, 'reemplazada'));
    }

    // El ping lo contesta solo el navegador: una conexión que no contesta en
    // ese tiempo se da por caída.
    ws.pingInterval = const Duration(seconds: 5);
    final conexion = _Conexion(ws, celular, nombre);
    _conexiones.add(conexion);
    _anotarPuesto(conexion, conectado: true);
    conexion.mandar(_lista ?? jsonEncode({'t': 'esperando'}));

    ws.listen(
      (mensaje) => _mensaje(conexion, mensaje),
      onDone: () => _seFue(conexion),
      onError: (Object _) => _seFue(conexion),
      cancelOnError: true,
    );
  }

  void _seFue(_Conexion conexion) {
    if (!_conexiones.remove(conexion)) return;
    _anotarPuesto(conexion, conectado: false);
  }

  void _anotarPuesto(_Conexion c, {required bool conectado}) {
    _puestos[c.celular] = PuestoConectado(
      celular: c.celular,
      nombre: c.nombre,
      conectado: conectado,
      ultimaVez: _ahora(),
      marcados: _marcas.cuantos(c.nombre),
    );
    _avisarPuestos();
  }

  void _avisarPuestos() {
    for (final entrada in _puestos.entries.toList()) {
      final p = entrada.value;
      _puestos[entrada.key] = PuestoConectado(
        celular: p.celular,
        nombre: p.nombre,
        conectado: p.conectado,
        ultimaVez: p.ultimaVez,
        marcados: _marcas.cuantos(p.nombre),
      );
    }
    if (!_cambiosDePuestos.isClosed) _cambiosDePuestos.add(puestos);
  }

  void _mensaje(_Conexion conexion, dynamic mensaje) {
    if (mensaje is! String || mensaje.length > 4096) return;
    final Object? json;
    try {
      json = jsonDecode(mensaje);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'hola':
        conexion.mandar(jsonEncode({'t': 'hola'}));
        final antes = _puestos[conexion.celular];
        if (antes != null && _conexiones.contains(conexion)) {
          _anotarPuesto(conexion, conectado: true);
        }
      case 'pedido':
        final pedido = PedidoPuerta.fromJson(json);
        if (pedido == null) return;
        // De a uno: cada pedido mira la base después del anterior.
        _fila = _fila.then((_) async {
          final respuesta = await _resolver(pedido, conexion.nombre);
          conexion.mandar(jsonEncode(respuesta));
        });
    }
  }

  Future<Map<String, Object?>> _resolver(
    PedidoPuerta pedido,
    String puesto,
  ) async {
    final previa = _respuestas[pedido.id];
    if (previa != null) return previa;
    final noSePudo = {'t': 'respuesta', 'id': pedido.id, 'ok': false};
    final puerta = _puerta;
    if (puerta == null) return noSePudo;

    final persona =
        puerta.personas.where((p) => p.id == pedido.personaId).firstOrNull;
    final DecisionPedido decision;
    try {
      final fila = persona == null ? null : await _pc.fila(persona.id);
      decision = decidirPedido(
        pedido: pedido,
        persona: persona,
        fila: fila,
        quien: _marcas.quien(pedido.personaId),
      );
      switch (decision.hace) {
        case QueHaceLaCentral.ingresar:
          await _pc.ingresar(eventoId, persona!, saludar: decision.saludar);
          _marcas.ingreso(persona.id, puesto);
        case QueHaceLaCentral.deshacer:
          await _pc.deshacer(persona!.id);
          _marcas.deshizo(persona.id);
        case QueHaceLaCentral.nada:
          break;
      }
    } catch (e) {
      // No se guarda: el celular lo vuelve a mandar.
      debugPrint('Central de la puerta, pedido ${pedido.id}: $e');
      return noSePudo;
    }

    final respuesta = {
      't': 'respuesta',
      'id': pedido.id,
      'ok': true,
      'hizo': decision.hace.name,
      if (decision.aviso != null) 'aviso': decision.aviso,
    };
    _respuestas[pedido.id] = respuesta;
    if (decision.haceAlgo) _avisarPuestos();
    return respuesta;
  }

  // ── La página del celular ─────────────────────────────────────────────────

  static const _tipos = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'css': 'text/css',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
  };

  /// Lo que cambia con cada versión se pide de nuevo siempre; el resto (letras,
  /// el motor de dibujo) se guarda un día en el celular.
  static const _sinGuardar = {'html', 'js', 'mjs', 'json'};

  Future<void> _servirArchivo(HttpRequest pedido) async {
    final respuesta = pedido.response;
    final raiz = paginaDelCelular;
    final partes = [
      for (final p in pedido.uri.pathSegments)
        if (p.isNotEmpty) p,
    ];
    if (partes.isEmpty) partes.add('index.html');
    final valida = partes.every(
      (p) =>
          p != '.' &&
          p != '..' &&
          !p.contains('/') &&
          !p.contains(r'\') &&
          !p.contains(':'),
    );
    final archivo = raiz == null || !valida
        ? null
        : File([raiz.path, ...partes].join(Platform.pathSeparator));
    if (archivo == null || !await archivo.exists()) {
      respuesta.statusCode = HttpStatus.notFound;
      await respuesta.close();
      return;
    }
    final nombre = partes.last.toLowerCase();
    final punto = nombre.lastIndexOf('.');
    final extension = punto < 0 ? '' : nombre.substring(punto + 1);
    respuesta.headers
      ..set(
        HttpHeaders.contentTypeHeader,
        _tipos[extension] ?? 'application/octet-stream',
      )
      ..set(
        HttpHeaders.cacheControlHeader,
        _sinGuardar.contains(extension) ? 'no-cache' : 'max-age=86400',
      );
    if (pedido.method == 'HEAD') {
      await respuesta.close();
      return;
    }
    await respuesta.addStream(archivo.openRead());
    await respuesta.close();
  }
}

class _Conexion {
  _Conexion(this.ws, this.celular, this.nombre);

  final WebSocket ws;
  final String celular;
  final String nombre;

  void mandar(String mensaje) {
    try {
      ws.add(mensaje);
    } catch (_) {
      // Ya se cerró: el aviso de que se fue llega por su lado.
    }
  }

  Future<void> cerrar(int codigo, String motivo) async {
    try {
      await ws.close(codigo, motivo).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
