import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../models/invitado.dart';
import '../../totem/services/tiempos_a_mano.dart';
import '../chat/mensaje_de_puesto.dart';
import '../services/puerta_del_evento.dart';
import 'pedidos_de_la_puerta.dart';
import 'resolvedor_de_pedidos.dart';

export 'resolvedor_de_pedidos.dart' show PuertaDeEstaPc, ResolvedorDePedidos;

/// El puerto de la central. Si está ocupado se prueban los siguientes nueve.
const kPuertoCentral = 8787;

/// Cuántos códigos mal puestos seguidos se aceptan de un mismo celular antes de
/// frenarlo un minuto.
const kErroresDeCodigo = 5;
const kFrenoPorErrores = Duration(minutes: 1);

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

  /// La tele que eligió ("Tu tele", 24-nov-2026). Null: un celular de antes,
  /// o una noche con una sola tele.
  final int? tele;

  const PuestoConectado({
    required this.celular,
    required this.nombre,
    required this.conectado,
    required this.ultimaVez,
    required this.marcados,
    this.tele,
  });
}

/// La Tele 2, conectada a la central de la Tele 1 (24-nov-2026).
class TeleConectada {
  final int numero;
  final bool conectada;
  const TeleConectada(this.numero, {required this.conectada});
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
///   en ese momento ([ResolvedorDePedidos]): si dos celulares ingresan a la misma
///   persona, el segundo recibe "ya ingresó". Las sillas de la noche y los
///   segundos del tótem van por la misma fila, que también usa la PC.
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
    ResolvedorDePedidos? resolvedor,
    this.paginaDelCelular,
    DateTime Function()? ahora,
    this.esTele = false,
  }) : _codigo = codigo,
       // El mismo reloj para la central y sus marcas: cuánto hace que se
       // marcó a alguien se cuenta con uno solo.
       _resolvedor = resolvedor ??
           ResolvedorDePedidos(eventoId: eventoId, pc: pc, ahora: ahora),
       _ahora = ahora ?? DateTime.now;

  final String eventoId;

  /// La central es la Tele 1 (la tele es el tótem, 24-nov-2026): los celulares
  /// eligen "Tu tele" y se le puede conectar la Tele 2. En la notebook, false:
  /// como siempre.
  final bool esTele;

  /// La fila de los pedidos: la misma que usa la PC.
  final ResolvedorDePedidos _resolvedor;

  /// La carpeta con la página que abre el celular, o null si no hay (en las
  /// pruebas).
  final Directory? paginaDelCelular;
  final DateTime Function() _ahora;

  String _codigo;
  HttpServer? _servidor;
  PuertaDelEvento? _puerta;
  String? _lista;
  var _version = 0;
  TiemposAMano? _tiempos;
  final _conexiones = <_Conexion>{};
  final _puestos = <String, PuestoConectado>{};
  final _errores = <String, List<DateTime>>{};
  final _cambiosDePuestos = StreamController<List<PuestoConectado>>.broadcast();

  // ── Las teles (24-nov-2026) ───────────────────────────────────────────────

  /// La Tele 2 conectada, si está.
  final _teles = <int, _ConexionTele>{};

  /// Los segundos de la llegada de cada otra tele (la 2): cada recepcionista
  /// controla los de su tele. Los de la Tele 1 son [_tiempos].
  final _tiemposDeTele = <int, TiemposAMano>{};

  /// La lista de la puerta, fila por fila, para copiarla en la Tele 2.
  final _filas = <String, Invitado>{};

  final _cambiosDeTeles = StreamController<List<TeleConectada>>.broadcast();

  /// Se avisa cada vez que la Tele 2 se conecta o se va.
  Stream<List<TeleConectada>> get cambiosDeTeles => _cambiosDeTeles.stream;

  List<TeleConectada> get teles => [
    for (var n = 2; n <= kTelesDeLaNoche; n++)
      TeleConectada(n, conectada: _teles.containsKey(n)),
  ];

  /// Lo que cambia la Tele 2 en sus segundos lo avisa acá.
  void Function(int tele, TiemposAMano t)? alCambiarTiemposDeTele;

  String get codigo => _codigo;
  int? get puerto => _servidor?.port;
  MarcasDeLaNoche get marcas => _resolvedor.marcas;

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

  /// Cómo se llama el evento, para el encabezado del celular: "ESCUELA NORMAL —
  /// Egresados (12/12) · masivo".
  String? _titulo;

  /// La lista cambió (alguien entró, se sorteó, se cargó un acompañante): se
  /// les manda a todos los celulares.
  void ponerPuerta(PuertaDelEvento puerta) {
    _puerta = puerta;
    _resolvedor.puerta = puerta;
    _mandarLista();
  }

  /// Los segundos de la llegada de esa noche, para que el celular los muestre
  /// y los pueda cambiar.
  void ponerTiempos(TiemposAMano? tiempos) {
    if (tiempos == _tiempos) return;
    _tiempos = tiempos;
    if (_puerta != null) _mandarLista();
  }

  void ponerTitulo(String? titulo) {
    if (titulo == _titulo) return;
    _titulo = titulo;
    if (_puerta != null) _mandarLista();
  }

  /// Los segundos de la llegada de la Tele [tele] (la 2), cambiados desde un
  /// celular: se los manda a esa tele, que los pone en su pantalla.
  void ponerTiemposDeTele(int tele, TiemposAMano tiempos) {
    _tiemposDeTele[tele] = tiempos;
    _teles[tele]?.mandar(jsonEncode({'t': 'tiempos', 'tiempos': tiempos.toJson()}));
    if (_puerta != null) _mandarLista();
  }

  /// La lista de la puerta fila por fila (la de la base de esta tele): lo que
  /// cambió se le manda a la Tele 2, que lo copia en la suya. Con cada ingreso
  /// va cómo se saluda ([MarcasDeLaNoche.bienvenida]).
  void ponerFilas(List<Invitado> filas) {
    _filas
      ..clear()
      ..addEntries(filas.map((f) => MapEntry(f.id, f)));
    for (final t in _teles.values) {
      _mandarFilas(t);
    }
  }

  /// Lo que la Tele 2 todavía no tiene: todo al conectarse; después, lo que
  /// cambió.
  void _mandarFilas(_ConexionTele t) {
    final cambiadas = <Invitado>[];
    for (final f in _filas.values) {
      final firma = _firma(f);
      if (t.enviadas[f.id] == firma) continue;
      t.enviadas[f.id] = firma;
      cambiadas.add(f);
    }
    if (cambiadas.isEmpty) return;
    final ahora = _ahora();
    final bienvenidas = <String, Object?>{};
    for (final f in cambiadas) {
      final b = f.estadoIngreso == EstadoIngreso.ingresado
          ? _resolvedor.marcas.bienvenida(f.id)
          : null;
      if (b != null) bienvenidas[f.id] = b.toJson(ahora);
    }
    t.mandar(jsonEncode({
      't': 'filas',
      'filas': [for (final f in cambiadas) Invitado.sinDatosPrivados(f.toJson())],
      'bienvenidas': bienvenidas,
      'por': _resolvedor.marcas.todas,
    }));
  }

  static String _firma(Invitado f) =>
      '${f.estadoIngreso.name}|${f.updatedAt?.toIso8601String()}|'
      '${f.numeroMesa}|${f.nombreCompleto}';

  /// Lo que la Tele 2 tiene que saber de los celulares: quién la maneja.
  void _mandarManejan() {
    for (final t in _teles.values) {
      t.mandar(jsonEncode({
        't': 'maneja',
        'nombres': _quienesManejan(t.numero),
      }));
    }
    _avisarTeles();
  }

  /// Los nombres de los celulares conectados que eligieron la tele [n].
  List<String> _quienesManejan(int n) => [
    for (final c in _conexiones)
      if (c.tele == n || c.tele == kLasDosTeles) c.nombre,
  ];

  /// Las teles para el celular: cuáles hay y quién maneja cada una.
  String _textoDeTeles() => jsonEncode({
    't': 'teles',
    'lista': [
      {'n': 1, 'conectada': true, 'maneja': _quienesManejan(1)},
      for (final t in teles)
        {'n': t.numero, 'conectada': t.conectada, 'maneja': _quienesManejan(t.numero)},
    ],
  });

  void _avisarTeles() {
    if (!esTele) return;
    final texto = _textoDeTeles();
    for (final c in _conexiones) {
      c.mandar(texto);
    }
    if (!_cambiosDeTeles.isClosed) _cambiosDeTeles.add(teles);
  }

  // ── El chat de la puerta (6.5.0) ─────────────────────────────────────────

  /// Los mensajes de la noche, solo en la memoria de la central.
  final _chat = ChatDeLaNoche();

  /// Lo que le llega a la PC (los de todos y los que le mandan).
  void Function(MensajeDePuesto)? alLlegarALaPc;

  /// Cómo se llama la PC en el chat: quien la opera.
  String _nombreDeLaPc = 'PC';

  set nombreDeLaPc(String nombre) {
    final n = nombre.trim();
    if (n.isEmpty || n == _nombreDeLaPc) return;
    _nombreDeLaPc = n;
    _mandarPuestos();
  }

  /// Los puestos con los que se puede hablar: la PC y los celulares.
  List<PuestoDelChat> get puestosDelChat => [
    PuestoDelChat(id: kPuestoDeLaPc, nombre: _nombreDeLaPc, conectado: true),
    for (final p in puestos)
      PuestoDelChat(id: p.celular, nombre: p.nombre, conectado: p.conectado),
  ];

  /// Lo que manda la PC.
  void mandarDesdeLaPc(MensajeDePuesto m) => _repartir(m);

  /// Lo guarda y se lo da solo a quien le toca: a todos, o al otro puesto y a
  /// quien lo mandó. Si llega dos veces, la segunda no hace nada.
  void _repartir(MensajeDePuesto m) {
    if (!_chat.agregar(m)) return;
    final texto = jsonEncode({'t': 'chat', 'm': m.toJson()});
    for (final c in _conexiones) {
      if (m.loVe(c.celular)) c.mandar(texto);
    }
    if (m.loVe(kPuestoDeLaPc)) alLlegarALaPc?.call(m);
  }

  /// La última lista de puestos que se mandó: el latido de cada celular avisa
  /// los puestos cada 5 s, y la lista se manda solo si cambió.
  String? _ultimosPuestos;

  String _textoDePuestos() => jsonEncode({
    't': 'puestos',
    'lista': [for (final p in puestosDelChat) p.toJson()],
  });

  /// A [salvo] no: es el que recién llega, y a ese se le manda aparte.
  void _mandarPuestos({_Conexion? salvo}) {
    final texto = _textoDePuestos();
    if (texto == _ultimosPuestos) return;
    _ultimosPuestos = texto;
    for (final c in _conexiones) {
      if (identical(c, salvo)) continue;
      c.mandar(texto);
    }
  }

  /// El salón de la fiesta para VER EN EL PLANO del celular (6.5.0): el armado
  /// y la config del tótem sin foto ni fondo (`SalonParaLaPuerta`). Va en un
  /// mensaje aparte de la lista, que se manda muchas veces por noche: el armado
  /// pesa. Null: sin salón.
  String? _salon;

  /// Pone el salón y se lo manda a todos. [armado] y [cfg] ya en JSON (el de
  /// `ArmadoSalon.toJson` y `SalonParaLaPuerta.cfgParaElCelular`); null: sin
  /// salón.
  void ponerSalon(Map<String, dynamic>? armado, Map<String, dynamic>? cfg) {
    final nuevo = jsonEncode({
      't': 'salon',
      'armado': armado,
      'cfg': armado == null ? null : cfg,
    });
    if (nuevo == _salon) return;
    _salon = nuevo;
    for (final c in _conexiones) {
      c.mandar(nuevo);
    }
  }

  void _mandarLista() {
    _version++;
    _lista = jsonEncode({
      't': 'puerta',
      'v': _version,
      'evento': eventoId,
      'titulo': _titulo,
      'puerta': _puerta!.toJson(),
      'por': _resolvedor.marcas.todas,
      if (_tiempos != null) 'tiempos': _tiempos!.toJson(),
      // La tele es el tótem (24-nov-2026): el celular dice "Conectado a la
      // Tele 1" y, con dos teles, muestra los segundos de la suya.
      if (esTele) 'central': 'Tele 1',
      if (_tiemposDeTele.isNotEmpty)
        'tiemposTeles': {
          for (final e in _tiemposDeTele.entries) '${e.key}': e.value.toJson(),
        },
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
    final teles = _teles.values.toList();
    _teles.clear();
    for (final t in teles) {
      await t.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    await _servidor?.close(force: true);
    _servidor = null;
    await _cambiosDePuestos.close();
    await _cambiosDeTeles.close();
  }

  // ── Lo que llega por la red ───────────────────────────────────────────────

  Future<void> _atender(HttpRequest pedido) async {
    try {
      if (pedido.uri.path == '/vivo') {
        await _conectar(pedido);
        return;
      }
      if (pedido.uri.path == '/tele') {
        await _conectarTele(pedido);
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
    final tele = int.tryParse(datos['t'] ?? '');
    final conexion = _Conexion(
      ws,
      celular,
      nombre,
      tele: esTele && tele != null && esTeleValida(tele) ? tele : null,
    );
    _conexiones.add(conexion);
    _anotarPuesto(conexion, conectado: true, salvo: conexion);
    conexion.mandar(_lista ?? jsonEncode({'t': 'esperando'}));
    if (_salon != null) conexion.mandar(_salon!);
    // El chat: lo que ya hubo esta noche para ese celular, y con quién hablar.
    conexion.mandar(
      jsonEncode({
        't': 'chat',
        'todos': [for (final m in _chat.paraElPuesto(celular)) m.toJson()],
      }),
    );
    // Al que llega, siempre (aunque la lista no haya cambiado: vuelve el
    // mismo celular).
    conexion.mandar(_textoDePuestos());
    // Con la central en una tele: qué teles hay y quién maneja cada una.
    if (esTele) _mandarManejan();

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
    if (esTele) _mandarManejan();
  }

  void _anotarPuesto(_Conexion c, {required bool conectado, _Conexion? salvo}) {
    _puestos[c.celular] = PuestoConectado(
      celular: c.celular,
      nombre: c.nombre,
      conectado: conectado,
      ultimaVez: _ahora(),
      marcados: _resolvedor.marcas.cuantos(c.nombre),
      tele: c.tele,
    );
    _avisarPuestos(salvo: salvo);
  }

  void _avisarPuestos({_Conexion? salvo}) {
    for (final entrada in _puestos.entries.toList()) {
      final p = entrada.value;
      _puestos[entrada.key] = PuestoConectado(
        celular: p.celular,
        nombre: p.nombre,
        conectado: p.conectado,
        ultimaVez: p.ultimaVez,
        marcados: _resolvedor.marcas.cuantos(p.nombre),
        tele: p.tele,
      );
    }
    if (!_cambiosDePuestos.isClosed) _cambiosDePuestos.add(puestos);
    _mandarPuestos(salvo: salvo);
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
      case 'chat':
        final m = MensajeDePuesto.fromJson(json['m']);
        if (m == null) return;
        // De quién es lo dice la conexión, no el mensaje: nadie escribe con el
        // nombre de otro.
        _repartir(
          MensajeDePuesto(
            id: m.id,
            de: conexion.celular,
            deNombre: conexion.nombre,
            para: m.para,
            texto: m.texto,
            hora: _ahora(),
          ),
        );
      case 'tele':
        // "Tu tele" (24-nov-2026): el celular cambió de tele.
        final n = json['n'];
        if (!esTele || n is! int || !esTeleValida(n)) return;
        conexion.tele = n;
        _anotarPuesto(conexion, conectado: true);
        _mandarManejan();
      case 'pedido':
        final leido = PedidoPuerta.fromJson(json);
        if (leido == null) return;
        // Sin tele en el pedido, la que eligió el celular. Con la central en
        // la notebook no hay teles: como siempre.
        final pedido = esTele
            ? leido.conTele(leido.tele ?? conexion.tele)
            : leido.conTele(null);
        // De a uno, con la PC: cada pedido mira la base después del anterior.
        unawaited(
          _resolvedor.resolver(pedido, conexion.nombre).then((respuesta) {
            conexion.mandar(jsonEncode(respuesta));
            if (respuesta['ok'] == true && respuesta['hizo'] != 'nada') {
              _avisarPuestos();
            }
          }),
        );
    }
  }

  // ── La Tele 2 (24-nov-2026) ───────────────────────────────────────────────

  /// La Tele 2 se conecta con el número del evento, como las cajas de la barra:
  /// es la misma app, con la misma fiesta bajada en la oficina.
  Future<void> _conectarTele(HttpRequest pedido) async {
    if (!WebSocketTransformer.isUpgradeRequest(pedido)) {
      pedido.response.statusCode = HttpStatus.badRequest;
      await pedido.response.close();
      return;
    }
    final datos = pedido.uri.queryParameters;
    final ws = await WebSocketTransformer.upgrade(pedido);
    final numero = int.tryParse(datos['n'] ?? '');
    if (!esTele ||
        datos['evento'] != eventoId ||
        numero == null ||
        numero < 2 ||
        numero > kTelesDeLaNoche) {
      ws.add(jsonEncode({'t': 'evento'}));
      await ws.close(4001, 'evento');
      return;
    }
    final vieja = _teles.remove(numero);
    if (vieja != null) unawaited(vieja.cerrar(4003, 'reemplazada'));
    ws.pingInterval = const Duration(seconds: 5);
    final t = _ConexionTele(ws, numero);
    _teles[numero] = t;
    t.mandar(jsonEncode({'t': 'central', 'codigo': _codigo, 'evento': eventoId}));
    final tiempos = _tiemposDeTele[numero];
    if (tiempos != null) {
      t.mandar(jsonEncode({'t': 'tiempos', 'tiempos': tiempos.toJson()}));
    }
    _mandarFilas(t);
    _mandarManejan();
    ws.listen(
      (mensaje) => _mensajeDeTele(t, mensaje),
      onDone: () => _seFueTele(t),
      onError: (Object _) => _seFueTele(t),
      cancelOnError: true,
    );
  }

  void _seFueTele(_ConexionTele t) {
    if (!identical(_teles[t.numero], t)) return;
    _teles.remove(t.numero);
    _avisarTeles();
  }

  void _mensajeDeTele(_ConexionTele t, dynamic mensaje) {
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
        t.mandar(jsonEncode({'t': 'hola'}));
      case 'tiempos':
        // Los segundos con que la Tele 2 arrancó: los celulares de esa tele
        // los ven y los cambian desde ahí.
        final tiempos = TiemposAMano.fromJson(json['tiempos']);
        if (tiempos == null || _tiemposDeTele[t.numero] == tiempos) return;
        _tiemposDeTele[t.numero] = tiempos;
        alCambiarTiemposDeTele?.call(t.numero, tiempos);
        if (_puerta != null) _mandarLista();
    }
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
  _Conexion(this.ws, this.celular, this.nombre, {this.tele});

  final WebSocket ws;
  final String celular;
  final String nombre;

  /// "Tu tele": la que eligió el celular.
  int? tele;

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

/// La Tele 2, del lado de la Tele 1: qué filas ya tiene.
class _ConexionTele extends _Conexion {
  _ConexionTele(WebSocket ws, this.numero) : super(ws, 'tele-$numero', 'Tele $numero');

  final int numero;

  /// La firma de cada fila que ya se le mandó.
  final enviadas = <String, String>{};
}
