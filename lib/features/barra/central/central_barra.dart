import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'buscar_central.dart';
import 'cliente_de_la_central.dart';
import 'filas_de_la_red.dart';

/// El puerto de la central de la barra. Si está ocupado se prueban los siguientes nueve.
/// La de la puerta usa 8787 a 8796: no se pisan, y las dos pueden ir en la misma PC.
const kPuertoCentralBarra = 8797;

/// El tamaño máximo de un mensaje: una fiesta grande, entera, entra con lugar.
const kMensajeMaximoBarra = 8 * 1024 * 1024;

/// Una caja que se conectó a la central esta noche.
@immutable
class CajaConectada {
  /// El equipo (la tablet): el id que se inventa la primera vez y guarda.
  final String equipo;

  /// "Caja 2 · Sofía".
  final String nombre;
  final bool conectada;
  final DateTime ultimaVez;

  /// Lo que esa tablet tiene sin subir a la nube, según su último latido.
  final PendientesDeLaBarra porSubir;

  /// "Barra 2", si la caja lo dijo (25-nov-2026).
  final String? barra;

  /// **Es la central de otra barra**, enganchada con esta: se pasan todo.
  final bool esCentral;

  const CajaConectada({
    required this.equipo,
    required this.nombre,
    required this.conectada,
    required this.ultimaVez,
    this.porSubir = PendientesDeLaBarra.nada,
    this.barra,
    this.esCentral = false,
  });

  CajaConectada con({
    String? nombre,
    bool? conectada,
    DateTime? ultimaVez,
    PendientesDeLaBarra? porSubir,
    String? barra,
    bool? esCentral,
  }) =>
      CajaConectada(
        equipo: equipo,
        nombre: nombre ?? this.nombre,
        conectada: conectada ?? this.conectada,
        ultimaVez: ultimaVez ?? this.ultimaVez,
        porSubir: porSubir ?? this.porSubir,
        barra: barra ?? this.barra,
        esCentral: esCentral ?? this.esCentral,
      );
}

/// Cómo está el enganche de esta central con la de la otra barra (25-nov-2026).
@immutable
class EngancheConOtra {
  /// La otra central: "Barra 2" (null si no lo dijo).
  final String? barra;
  final bool conectada;

  const EngancheConOtra({this.barra, required this.conectada});

  @override
  bool operator ==(Object other) =>
      other is EngancheConOtra && other.barra == barra && other.conectada == conectada;

  @override
  int get hashCode => Object.hash(barra, conectada);
}

/// La central de la barra: **la notebook de la barra**, a la que las tablets de las cajas
/// se conectan por el wifi del salón, con o sin internet (decidido el 7-nov). Es la bajada
/// de la nube, pero por la red del salón:
/// - **Lo que escribe una caja** (abrir, vender, anular, sus vales, cerrar) llega acá, se
///   guarda en la base de la notebook **sin encolarlo** ([BarraDeLaRed.guardarDeOtroEquipo]:
///   ya lo sube la tablet que lo hizo) y se les manda a las demás cajas.
/// - **Al conectarse, cada caja recibe todo lo de la fiesta** y manda todo lo suyo: así se
///   pone al día sola después de un corte, sin cola que cuidar. Lo que ya estaba no se
///   vuelve a mandar ([cambiaLaFila]).
/// - **Lo que hace la notebook** (el jefe anula desde CAJAS) va igual a las cajas
///   ([difundirDeEstaPc]).
/// - Así "Quedan" baja en todas las cajas con lo que vendió cualquiera, y la notebook ve
///   las cajas en vivo, sin internet.
///
/// Habla por WebSocket en `/barra?evento=<id>&equipo=<id>&caja=<nombre>`, con mensajes
/// JSON que llevan su tipo en `t`:
/// - de la caja: `{t:'filas', filas:{tabla:[fila…]}}` y `{t:'hola', ventas, otros}` (el
///   latido, con lo que tiene sin subir a la nube);
/// - de la central: `{t:'filas', …}` y `{t:'hola', cajas}` (cuántas cajas están conectadas).
///
/// Solo atiende a su fiesta: una caja de otra fiesta se cierra con 4001.
///
/// **Una central por barra** (25-nov-2026): cada barra tiene su notebook y su router, y
/// [barra] dice cuál es. **Si ve a la central de la otra barra en la red, se engancha
/// sola** ([engancharConOtras]) y se pasan todo, en las dos direcciones: lo de sus cajas
/// va a la otra y lo de la otra a sus cajas. Cada fila tiene su id, así que repetirla no
/// cambia nada, y una fila solo se reparte si era nueva: no da vueltas. Si no se ven
/// (cada router por su lado), cada una sigue sola; lo de las dos se junta cuando se
/// vuelven a ver o cuando vuelve internet.
class CentralBarra {
  CentralBarra({
    required this.eventoId,
    required BarraDeLaRed barra,
    this.alGuardar,
    this.barraDelSalon,
    DateTime Function()? ahora,
  })  : _barra = barra,
        _ahora = ahora ?? DateTime.now;

  final String eventoId;

  /// "Barra 1": la barra de esta notebook. Null: la de antes, de toda la fiesta.
  final String? barraDelSalon;
  final BarraDeLaRed _barra;

  /// El enganche con la central de la otra barra, si se buscó ([engancharConOtras]).
  ClienteDeLaCentral? _puente;
  final _cambiosDelPuente = StreamController<void>.broadcast();

  /// Llegó algo nuevo y se guardó: las pantallas de la notebook (CAJAS) se rehacen.
  final void Function()? alGuardar;
  final DateTime Function() _ahora;

  HttpServer? _servidor;
  final _conexiones = <_Conexion>{};
  final _cajas = <String, CajaConectada>{};
  final _cambiosDeCajas = StreamController<List<CajaConectada>>.broadcast();

  /// Las filas se guardan de a una tanda por vez, en orden: dos cajas que mandan a la vez
  /// no se pisan en la base.
  Future<void> _fila = Future<void>.value();

  int? get puerto => _servidor?.port;

  /// Las cajas de esta noche: primero las conectadas, por nombre.
  List<CajaConectada> get cajas {
    final lista = _cajas.values.toList()
      ..sort((a, b) {
        if (a.conectada != b.conectada) return a.conectada ? -1 : 1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });
    return lista;
  }

  /// Cuántas cajas conectadas (sin contar otra central enganchada).
  int get conectadas => _cajas.values.where((c) => c.conectada && !c.esCentral).length;

  Stream<List<CajaConectada>> get cambiosDeCajas => _cambiosDeCajas.stream;

  /// Las otras centrales de la fiesta enganchadas con esta, de un lado o del otro: la
  /// que esta buscó ([engancharConOtras]) y las que se engancharon acá.
  List<EngancheConOtra> get otras {
    final lista = <EngancheConOtra>[];
    final puente = _puente;
    if (puente != null && puente.estado != EstadoDeLaCentral.apagada && puente.estado != EstadoDeLaCentral.buscando) {
      lista.add(EngancheConOtra(barra: puente.donde?.barra, conectada: puente.conectada));
    }
    for (final c in _cajas.values) {
      if (c.esCentral) lista.add(EngancheConOtra(barra: c.barra, conectada: c.conectada));
    }
    return lista;
  }

  /// Avisa cuando cambia el enganche que buscó esta central.
  Stream<void> get cambiosDelPuente => _cambiosDelPuente.stream;

  /// **Busca a las otras centrales de su fiesta y se engancha** (25-nov-2026). [equipo]
  /// es el id de esta notebook: con él la búsqueda no se encuentra a sí misma y, de cada
  /// par, se engancha una sola ([EleccionDeCentral.otraCentral]). Mientras no la
  /// encuentra, sigue sola, como siempre.
  void engancharConOtras({
    required String equipo,
    required BuscaCentral buscador,
    WebSocketChannel Function(Uri)? abrir,
    Duration latido = const Duration(seconds: 5),
    Duration silencioMaximo = const Duration(seconds: 12),
    Duration pausa = const Duration(seconds: 1),
  }) {
    if (_puente != null) return;
    final puente = ClienteDeLaCentral(
      eventoId: eventoId,
      equipo: equipo,
      nombreCaja: 'Central${barraDelSalon == null ? '' : ' · $barraDelSalon'}',
      barra: _barra,
      barraDeLaCaja: barraDelSalon,
      eleccion: EleccionDeCentral.otraCentral(equipo),
      buscador: buscador,
      abrir: abrir,
      ahora: _ahora,
      latido: latido,
      silencioMaximo: silencioMaximo,
      pausa: pausa,
      alGuardar: alGuardar,
      // Lo nuevo de la otra barra, a las cajas de esta.
      alRecibir: (nuevas) => _mandarATodas(nuevas),
    );
    puente.addListener(() {
      if (!_cambiosDelPuente.isClosed) _cambiosDelPuente.add(null);
    });
    _puente = puente;
    puente.arrancar();
  }

  /// El enganche con la otra central vuelve a buscarla desde cero: lo usan las ventanas
  /// de prueba para "separar" las dos redes.
  @visibleForTesting
  void volverABuscarLaOtra() => _puente?.volverABuscar();

  /// Abre la central y devuelve en qué puerto quedó. [en] es por dónde se escucha: en la
  /// app, todas las conexiones de la PC; en las pruebas, solo esta PC (así Windows no
  /// pregunta por el cortafuegos).
  Future<int> arrancar({int desde = kPuertoCentralBarra, InternetAddress? en}) async {
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
      onError: (Object e) => debugPrint('Central de la barra: $e'),
    );
    return servidor.port;
  }

  /// Lo que se hizo en esta notebook (el jefe anuló una venta): a todas las cajas, y a la
  /// central de la otra barra si están enganchadas.
  Future<void> difundirDeEstaPc(String tabla, String id) async {
    final fila = await _barra.filaDeLaRed(tabla, id);
    if (fila == null || !filaDeLaFiesta(tabla, fila, eventoId)) return;
    final filas = {
      tabla: [fila],
    };
    _mandarATodas(filas);
    _puente?.enviarFilas(filas);
  }

  Future<void> cerrar() async {
    final puente = _puente;
    _puente = null;
    puente?.dispose();
    await _cambiosDelPuente.close();
    final todas = _conexiones.toList();
    _conexiones.clear();
    for (final c in todas) {
      await c.cerrar(WebSocketStatus.goingAway, 'cerrada');
    }
    await _servidor?.close(force: true);
    _servidor = null;
    await _cambiosDeCajas.close();
  }

  // ── Lo que llega por la red ───────────────────────────────────────────────

  Future<void> _atender(HttpRequest pedido) async {
    try {
      if (pedido.uri.path != '/barra' || !WebSocketTransformer.isUpgradeRequest(pedido)) {
        pedido.response.statusCode = HttpStatus.notFound;
        await pedido.response.close();
        return;
      }
      final datos = pedido.uri.queryParameters;
      final ws = await WebSocketTransformer.upgrade(pedido);
      if (datos['evento'] != eventoId) {
        ws.add(jsonEncode({'t': 'otraFiesta'}));
        await ws.close(4001, 'otra fiesta');
        return;
      }
      final equipo = datos['equipo']?.trim() ?? '';
      final nombre = datos['caja']?.trim() ?? '';
      if (equipo.isEmpty || equipo.length > 64 || nombre.isEmpty || nombre.length > 60) {
        ws.add(jsonEncode({'t': 'faltanDatos'}));
        await ws.close(4002, 'faltan datos');
        return;
      }
      // Si la misma tablet vuelve (se cortó el wifi), la conexión vieja puede seguir
      // colgada un rato: se cierra.
      for (final vieja in _conexiones.where((c) => c.equipo == equipo).toList()) {
        _conexiones.remove(vieja);
        unawaited(vieja.cerrar(4003, 'reemplazada'));
      }
      ws.pingInterval = const Duration(seconds: 5);
      final barra = datos['barra']?.trim();
      final conexion = _Conexion(
        ws,
        equipo,
        nombre,
        barra: barra == null || barra.isEmpty || barra.length > 40 ? null : barra,
        esCentral: datos['central'] == '1',
      );
      _conexiones.add(conexion);
      _anotar(conexion, conectada: true);
      ws.listen(
        (mensaje) => _mensaje(conexion, mensaje),
        onDone: () => _seFue(conexion),
        onError: (Object _) => _seFue(conexion),
        cancelOnError: true,
      );
      // Todo lo de la fiesta, de todas las cajas: la que vuelve de un corte se pone al día.
      final todo = await _encolar(() => _barra.filasDeLaFiesta(eventoId));
      conexion.mandar(jsonEncode({'t': 'filas', 'filas': todo}));
    } catch (e) {
      debugPrint('Central de la barra, pedido ${pedido.uri.path}: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  void _seFue(_Conexion conexion) {
    if (!_conexiones.remove(conexion)) return;
    _anotar(conexion, conectada: false);
  }

  void _anotar(_Conexion c, {required bool conectada, PendientesDeLaBarra? porSubir}) {
    final antes = _cajas[c.equipo];
    _cajas[c.equipo] = antes == null
        ? CajaConectada(
            equipo: c.equipo,
            nombre: c.nombre,
            conectada: conectada,
            ultimaVez: _ahora(),
            porSubir: porSubir ?? PendientesDeLaBarra.nada,
            barra: c.barra,
            esCentral: c.esCentral,
          )
        : antes.con(
            nombre: c.nombre,
            conectada: conectada,
            ultimaVez: _ahora(),
            porSubir: porSubir,
            barra: c.barra,
            esCentral: c.esCentral,
          );
    if (!_cambiosDeCajas.isClosed) _cambiosDeCajas.add(cajas);
  }

  Future<T> _encolar<T>(Future<T> Function() hacer) {
    final resultado = _fila.then((_) => hacer());
    _fila = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  void _mensaje(_Conexion conexion, dynamic mensaje) {
    if (mensaje is! String || mensaje.length > kMensajeMaximoBarra) return;
    final Object? json;
    try {
      json = jsonDecode(mensaje);
    } catch (_) {
      return;
    }
    if (json is! Map<String, dynamic>) return;
    switch (json['t']) {
      case 'hola':
        final ventas = json['ventas'], otros = json['otros'];
        _anotar(
          conexion,
          conectada: _conexiones.contains(conexion),
          porSubir: PendientesDeLaBarra(
            ventas: ventas is int ? ventas : 0,
            otros: otros is int ? otros : 0,
          ),
        );
        conexion.mandar(jsonEncode({'t': 'hola', 'cajas': conectadas}));
      case 'filas':
        final filas = json['filas'];
        if (filas is Map) unawaited(_recibir(conexion, filas));
    }
  }

  /// Guarda lo que mandó una caja y les pasa a las demás solo lo que era nuevo.
  Future<void> _recibir(_Conexion de, Map<dynamic, dynamic> filas) async {
    final nuevas = await _encolar(() async {
      final nuevas = <String, List<Map<String, Object?>>>{};
      for (final tabla in tablasDeLaRed) {
        final lista = filas[tabla];
        if (lista is! List) continue;
        for (final f in lista) {
          if (!filaDeLaFiesta(tabla, f, eventoId)) continue;
          final fila = Map<String, Object?>.from(f as Map);
          try {
            if (await _barra.guardarDeOtroEquipo(tabla, fila)) {
              (nuevas[tabla] ??= []).add(fila);
            }
          } catch (e) {
            debugPrint('Central de la barra: no se guardó una fila de $tabla: $e');
          }
        }
      }
      return nuevas;
    });
    if (nuevas.isEmpty) return;
    alGuardar?.call();
    _mandarATodas(nuevas, menos: de);
    // Y a la central de la otra barra, si esta se enganchó con ella.
    _puente?.enviarFilas(nuevas);
  }

  void _mandarATodas(Map<String, List<Map<String, Object?>>> filas, {_Conexion? menos}) {
    final texto = jsonEncode({'t': 'filas', 'filas': filas});
    for (final c in _conexiones) {
      if (!identical(c, menos)) c.mandar(texto);
    }
  }
}

class _Conexion {
  _Conexion(this.ws, this.equipo, this.nombre, {this.barra, this.esCentral = false});

  final WebSocket ws;
  final String equipo;
  final String nombre;
  final String? barra;
  final bool esCentral;

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
