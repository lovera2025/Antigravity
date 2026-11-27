import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../cuentas/reglas_de_la_barra.dart';
import '../datos/barra_repositorio.dart';
import 'buscar_central.dart';
import 'cliente_de_la_central.dart';
import 'filas_de_la_red.dart';
import 'llave_de_la_barra.dart';

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

/// Lo que se le agrega al id de la notebook para su enganche con otra central.
const kSufijoDelEnganche = '-central';

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
/// - de la central: `{t:'filas', …}` y `{t:'hola', cajas, hora}` (cuántas cajas están
///   conectadas, y la hora de la notebook para que la tablet vea si su reloj está corrido).
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
    required QuienEsQuienEnLaBarra quienEsQuien,
    this.alGuardar,
    this.barraDelSalon,
    DateTime Function()? ahora,
    this.esperaDelPin = const Duration(seconds: 10),
  })  : _barra = barra,
        _quienEsQuien = quienEsQuien,
        _ahora = ahora ?? DateTime.now;

  /// Quién es quién: los operadores y el PIN maestro de esta notebook (26-nov-2026).
  final QuienEsQuienEnLaBarra _quienEsQuien;

  /// Cuánto espera que un aparato que se conecta pruebe su PIN.
  final Duration esperaDelPin;

  /// Lo que llegó por el wifi y no se guardó, con el motivo (los últimos 200): para que el
  /// jefe lo vea y para las pruebas.
  final rechazos = <RechazoDeLaCentral>[];
  final _cambiosDeRechazos = StreamController<void>.broadcast();

  /// Avisa cuando la central no guardó algo que le mandaron.
  Stream<void> get cambiosDeRechazos => _cambiosDeRechazos.stream;

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
    required Future<CredencialDeLaBarra?> Function() credencial,
    WebSocketChannel Function(Uri)? abrir,
    Duration latido = const Duration(seconds: 5),
    Duration silencioMaximo = const Duration(seconds: 12),
    Duration pausa = const Duration(seconds: 1),
    Stream<void>? cambiosDeRed,
  }) {
    if (_puente != null) return;
    final puente = ClienteDeLaCentral(
      cambiosDeRed: cambiosDeRed,
      credencial: credencial,
      eventoId: eventoId,
      // Su propio id, distinto del de esta notebook: si en esta notebook quedara también
      // una caja conectada a la otra central, la otra no los confunde ni los echa por turno
      // (cierra la conexión anterior del mismo equipo; 26-nov-2026).
      equipo: '$equipo$kSufijoDelEnganche',
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
    await _cambiosDeRechazos.close();
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
      final retoDeLaCaja = datos['r']?.trim() ?? '';
      if (equipo.isEmpty ||
          equipo.length > 64 ||
          nombre.isEmpty ||
          nombre.length > 60 ||
          retoDeLaCaja.length < 16 ||
          retoDeLaCaja.length > 64) {
        ws.add(jsonEncode({'t': 'faltanDatos'}));
        await ws.close(4002, 'faltan datos');
        return;
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
      // **Primero el PIN** (26-nov-2026): hasta probarlo no recibe nada ni se guarda nada
      // de lo que mande. Tampoco echa a la tablet de verdad que tenga ese mismo equipo.
      final reto = LlaveDeLaBarra.reto();
      ws.listen(
        (mensaje) {
          if (conexion.rol == null) {
            unawaited(_probarElPin(conexion, mensaje, reto: reto, retoDeLaCaja: retoDeLaCaja));
          } else {
            _mensaje(conexion, mensaje);
          }
        },
        onDone: () => _seFue(conexion),
        onError: (Object _) => _seFue(conexion),
        cancelOnError: true,
      );
      ws.add(jsonEncode({'t': 'reto', 'n': reto}));
      Timer(esperaDelPin, () {
        if (conexion.rol == null) unawaited(conexion.cerrar(4005, 'sin PIN'));
      });
    } catch (e) {
      debugPrint('Central de la barra, pedido ${pedido.uri.path}: $e');
      try {
        pedido.response.statusCode = HttpStatus.internalServerError;
        await pedido.response.close();
      } catch (_) {}
    }
  }

  /// La respuesta al reto: quién es y su firma. Si da, entra con su rol, recibe todo lo
  /// de la fiesta y la central le firma su reto. Si no, se cierra (4006 o 4007).
  Future<void> _probarElPin(
    _Conexion conexion,
    dynamic mensaje, {
    required String reto,
    required String retoDeLaCaja,
  }) async {
    if (conexion.probando || conexion.rol != null) return;
    conexion.probando = true;
    try {
      final Object? json = mensaje is String && mensaje.length < 4096 ? jsonDecode(mensaje) : null;
      if (json is! Map || json['t'] != 'soy') {
        await conexion.cerrar(4005, 'sin PIN');
        return;
      }
      final quien = json['quien'], prueba = json['prueba'];
      List<int>? llave;
      RolEnLaBarra? rol;
      String? operadorId;
      if (quien == 'operador' && json['id'] is String) {
        final persona = await _quienEsQuien.operador(json['id'] as String);
        if (persona != null) {
          llave = LlaveDeLaBarra.deOperador(persona.pin);
          rol = persona.rol;
          operadorId = persona.id;
        }
      } else if (quien == 'maestro') {
        final pin = await _quienEsQuien.pinMaestro();
        if (pin != null && pin.isNotEmpty) {
          llave = LlaveDeLaBarra.deMaestro(pin);
          rol = conexion.esCentral ? RolEnLaBarra.central : RolEnLaBarra.jefe;
        }
      }
      final esperada = llave == null
          ? null
          : LlaveDeLaBarra.firma(llave, lado: 'caja', reto: reto, evento: eventoId, equipo: conexion.equipo);
      if (esperada == null || prueba is! String || !LlaveDeLaBarra.iguales(prueba, esperada)) {
        await conexion.cerrar(4006, 'PIN no reconocido');
        return;
      }
      if (rol == null) {
        await conexion.cerrar(4007, 'sin permiso de barra');
        return;
      }
      conexion.rol = rol;
      conexion.operadorId = operadorId;
      // Si la misma tablet vuelve (se cortó el wifi), la conexión vieja puede seguir
      // colgada un rato: se cierra. Recién ahora, con el PIN probado.
      for (final vieja in _conexiones.where((c) => c.equipo == conexion.equipo).toList()) {
        _conexiones.remove(vieja);
        unawaited(vieja.cerrar(4003, 'reemplazada'));
      }
      _conexiones.add(conexion);
      _anotar(conexion, conectada: true);
      conexion.mandar(jsonEncode({
        't': 'adelante',
        'rol': rol.name,
        'prueba': LlaveDeLaBarra.firma(llave!, lado: 'central', reto: retoDeLaCaja, evento: eventoId, equipo: conexion.equipo),
      }));
      // Todo lo de la fiesta, de todas las cajas: la que vuelve de un corte se pone al día.
      final todo = await _encolar(() => _barra.filasDeLaFiesta(eventoId));
      conexion.mandar(jsonEncode({'t': 'filas', 'filas': todo}));
    } catch (e) {
      debugPrint('Central de la barra: no se pudo probar el PIN: $e');
      await conexion.cerrar(4006, 'PIN no reconocido');
    } finally {
      conexion.probando = false;
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
        // Con la hora de la notebook: la tablet ve si su reloj está corrido (26-nov-2026).
        conexion.mandar(jsonEncode({
          't': 'hola',
          'cajas': conectadas,
          'hora': _ahora().toUtc().toIso8601String(),
        }));
      case 'filas':
        final filas = json['filas'];
        if (filas is Map) unawaited(_recibir(conexion, filas));
    }
  }

  /// En qué orden se revisa lo que llega junto: los pasos del cierre antes que las cajas
  /// (una caja se cierra con su OK), y las cajas antes que sus ventas. Los retiros y el
  /// cambio de la encargada, primero: un retiro se anota con la caja abierta.
  static const _enOrden = [
    'barra_caja_movimientos',
    'barra_cierres',
    'barra_cajas',
    'barra_ventas',
    'barra_vales',
    'barra_anulaciones',
    'barra_stock_barras',
    'barra_stock_movimientos',
  ];

  /// Guarda lo que mandó una caja **si le toca a quien la manda** ([ReglasDeLaBarra]) y
  /// les pasa a las demás solo lo que era nuevo. Lo que no le toca no se guarda ni se
  /// reparte: queda en [rechazos] y se le avisa a ese aparato.
  Future<void> _recibir(_Conexion de, Map<dynamic, dynamic> filas) async {
    final rol = de.rol;
    if (rol == null) return;
    final nuevas = await _encolar(() async {
      final nuevas = <String, List<Map<String, Object?>>>{};
      // Las cajas que vienen en el mismo envío, para saber de quién es cada venta o paso.
      final cajasDelEnvio = <String, CajaBarra>{};
      final listaDeCajas = filas['barra_cajas'];
      if (listaDeCajas is List) {
        for (final f in listaDeCajas) {
          if (!filaDeLaFiesta('barra_cajas', f, eventoId)) continue;
          try {
            final c = CajaBarra.fromMap(Map<String, dynamic>.from(f as Map));
            cajasDelEnvio[c.id] = c;
          } catch (_) {}
        }
      }
      final orden = [..._enOrden, for (final t in tablasDeLaRed) if (!_enOrden.contains(t)) t];
      for (final tabla in orden) {
        if (!tablasDeLaRed.contains(tabla)) continue;
        final lista = filas[tabla];
        if (lista is! List) continue;
        for (final f in lista) {
          if (!filaDeLaFiesta(tabla, f, eventoId)) continue;
          final fila = Map<String, Object?>.from(f as Map);
          try {
            final id = fila['id'] as String;
            final yaEsta = await _barra.filaDeLaRed(tabla, id);
            // Lo que no cambia nada no se revisa ni se rechaza: es lo que ya estaba.
            if (yaEsta != null && !cambiaLaFila(nueva: fila, vieja: yaEsta)) continue;
            final motivo = await _porQueNo(de, rol, tabla, fila, yaEsta, cajasDelEnvio);
            if (motivo != null) {
              _rechazar(de, tabla, id, motivo);
              continue;
            }
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

  Future<String?> _porQueNo(
    _Conexion de,
    RolEnLaBarra rol,
    String tabla,
    Map<String, Object?> fila,
    Map<String, Object?>? yaEsta,
    Map<String, CajaBarra> cajasDelEnvio,
  ) async {
    if (rol == RolEnLaBarra.jefe || rol == RolEnLaBarra.central) return null;
    final cajaId = tabla == 'barra_cajas' ? fila['id'] : fila['caja_barra_id'];
    CajaBarra? caja;
    if (cajaId is String) {
      final enLaBase = await _barra.filaDeLaRed('barra_cajas', cajaId);
      caja = enLaBase != null ? CajaBarra.fromMap(Map<String, dynamic>.from(enLaBase)) : cajasDelEnvio[cajaId];
    }
    var pasos = const <PasoDelCierre>[];
    if (tabla == 'barra_cajas' && yaEsta != null && yaEsta['cerrada_at'] == null && fila['cerrada_at'] != null) {
      final todo = await _barra.filasDeLaFiesta(eventoId);
      pasos = [
        for (final p in todo['barra_cierres'] ?? const <Map<String, Object?>>[])
          if (p['caja_barra_id'] == cajaId) PasoDelCierre.fromMap(Map<String, dynamic>.from(p)),
      ];
    }
    var deUnaEncargada = false;
    if ((tabla == 'barra_cierres' || tabla == 'barra_anulaciones') && caja != null) {
      final firma = (fila['hecho_por'] as String?)?.trim() ?? '';
      deUnaEncargada = firma.isNotEmpty &&
          firma != (caja.operadorNombre ?? '').trim() &&
          await _quienEsQuien.esEncargada(firma);
    }
    return ReglasDeLaBarra.porQueNoSeGuarda(
      tabla: tabla,
      fila: fila,
      rol: rol,
      equipo: de.equipo,
      operadorId: de.operadorId,
      yaEsta: yaEsta,
      caja: caja,
      pasos: pasos,
      hechoPorUnaEncargada: deUnaEncargada,
    );
  }

  void _rechazar(_Conexion de, String tabla, String id, String motivo) {
    debugPrint('Central de la barra: no se guardó $tabla $id de ${de.nombre}: $motivo');
    rechazos.add(RechazoDeLaCentral(
      cuando: _ahora(),
      equipo: de.equipo,
      nombre: de.nombre,
      tabla: tabla,
      id: id,
      motivo: motivo,
    ));
    if (rechazos.length > 200) rechazos.removeAt(0);
    if (!_cambiosDeRechazos.isClosed) _cambiosDeRechazos.add(null);
    de.mandar(jsonEncode({'t': 'rechazada', 'tabla': tabla, 'id': id, 'motivo': motivo}));
  }

  void _mandarATodas(Map<String, List<Map<String, Object?>>> filas, {_Conexion? menos}) {
    final texto = jsonEncode({'t': 'filas', 'filas': filas});
    for (final c in _conexiones) {
      if (!identical(c, menos)) c.mandar(texto);
    }
  }
}

/// Algo que llegó por el wifi y la central no guardó, con el motivo.
@immutable
class RechazoDeLaCentral {
  final DateTime cuando;
  final String equipo;

  /// "Caja 2 · Sofía": lo que dijo el aparato.
  final String nombre;
  final String tabla;
  final String id;
  final String motivo;

  const RechazoDeLaCentral({
    required this.cuando,
    required this.equipo,
    required this.nombre,
    required this.tabla,
    required this.id,
    required this.motivo,
  });
}

class _Conexion {
  _Conexion(this.ws, this.equipo, this.nombre, {this.barra, this.esCentral = false});

  final WebSocket ws;
  final String equipo;
  final String nombre;
  final String? barra;
  final bool esCentral;

  /// Quién puso su PIN en ese aparato. Null: todavía no lo probó (no recibe ni manda).
  RolEnLaBarra? rol;
  String? operadorId;
  bool probando = false;

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
