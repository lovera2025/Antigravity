import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'buscar_central.dart';
import 'filas_de_la_red.dart';

/// Cómo está una caja con la central de la barra.
enum EstadoDeLaCentral {
  /// Todavía no se la buscó (la cajera no abrió VENDER).
  apagada,

  /// Preguntando por la red del salón, sin haberla encontrado nunca.
  buscando,

  /// Conectada: lo que vende esta caja les llega a las demás, y al revés.
  conectada,

  /// Estuvo conectada y se cortó: se sigue vendiendo con lo de este equipo, y se la busca.
  sinCentral,
}

/// La caja de la barra, del lado de la tablet: busca la central de la fiesta por el wifi
/// del salón (o va a la dirección que escribió la cajera), le manda lo que escribe esta
/// caja y guarda lo que hacen las demás.
///
/// - **Vender nunca espera a la central.** Se guarda en la tablet como siempre, y después
///   se avisa ([mandar]). Sin central se sigue vendiendo: lo de esta caja queda contado en
///   [porMandar] y se manda al volver.
/// - **Al conectarse se manda todo lo de la fiesta que tiene este equipo y se recibe todo
///   lo de la central**: así un corte (el wifi, la notebook que se reinició) se arregla
///   solo, sin cola que cuidar. Lo repetido no cambia nada ([BarraDeLaRed.guardarDeOtroEquipo]).
/// - Lo que llega se guarda sin la cola de subida: lo sube el equipo que lo hizo.
class ClienteDeLaCentral extends ChangeNotifier {
  ClienteDeLaCentral({
    required this.eventoId,
    required this.equipo,
    required this.nombreCaja,
    required BarraDeLaRed barra,
    this.alGuardar,
    BuscaCentral? buscador,
    DondeEstaLaCentral? aMano,
    WebSocketChannel Function(Uri)? abrir,
    DateTime Function()? ahora,
    this.latido = const Duration(seconds: 5),
    this.silencioMaximo = const Duration(seconds: 12),
    this.pausa = const Duration(seconds: 1),
  })  : _barra = barra,
        _buscador = buscador ?? BuscaCentral(eventoId: eventoId),
        _aMano = aMano,
        _abrir = abrir ?? WebSocketChannel.connect,
        _ahora = ahora ?? DateTime.now;

  final String eventoId;
  final String equipo;

  /// "Caja 2 · Sofía": lo que ve la notebook.
  final String nombreCaja;
  final BarraDeLaRed _barra;

  /// Llegó algo de otra caja y se guardó: VENDER y CAJAS se rehacen.
  final void Function()? alGuardar;
  final BuscaCentral _buscador;
  final WebSocketChannel Function(Uri) _abrir;
  final DateTime Function() _ahora;
  final Duration latido;
  final Duration silencioMaximo;
  final Duration pausa;

  DondeEstaLaCentral? _aMano;
  DondeEstaLaCentral? _donde;
  EstadoDeLaCentral _estado = EstadoDeLaCentral.apagada;
  DateTime? _desde;
  int _cajas = 0;
  final _porMandar = <String>{};

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escucha;
  Timer? _latidos;
  Timer? _reintento;
  DateTime _ultimaNoticia = DateTime.fromMillisecondsSinceEpoch(0);
  var _intentos = 0;
  var _cerrado = false;

  EstadoDeLaCentral get estado => _estado;
  bool get conectada => _estado == EstadoDeLaCentral.conectada;

  /// Desde cuándo no hay central (null si está conectada o nunca estuvo).
  DateTime? get desde => _desde;

  /// Cuántas cajas tiene conectadas la central, contando esta.
  int get cajas => _cajas;

  /// Lo que hizo esta caja sin central, que se manda al volver.
  int get porMandar => _porMandar.length;

  /// A dónde está conectada (o la última vez que la encontró).
  DondeEstaLaCentral? get donde => _donde;

  /// La que escribió la cajera, si no se la encuentra sola.
  DondeEstaLaCentral? get aMano => _aMano;

  // ── Desde afuera ──────────────────────────────────────────────────────────

  /// Empieza a buscar la central (o va a la que se escribió a mano).
  void arrancar() {
    if (_cerrado || _estado != EstadoDeLaCentral.apagada) return;
    _poner(EstadoDeLaCentral.buscando);
    _buscarOIr();
  }

  /// La dirección que muestra la notebook, escrita a mano. Null: se la vuelve a buscar sola.
  void ponerAMano(DondeEstaLaCentral? donde) {
    _aMano = donde;
    if (_cerrado || _estado == EstadoDeLaCentral.apagada) return;
    _cortar();
    _intentos = 0;
    _buscarOIr();
  }

  /// Esta caja escribió [id] de [tabla]: se le manda a la central, o queda para cuando vuelva.
  Future<void> mandar(String tabla, String id) async {
    if (_cerrado || !tablasDeLaRed.contains(tabla)) return;
    if (!conectada || _canal == null) {
      if (_porMandar.add('$tabla/$id')) _avisar();
      return;
    }
    final fila = await _barra.filaDeLaRed(tabla, id);
    if (fila == null) return;
    _enviar({
      't': 'filas',
      'filas': {
        tabla: [fila],
      },
    });
  }

  @override
  void dispose() {
    _cerrado = true;
    _cortar();
    _buscador.parar();
    super.dispose();
  }

  // ── Por dentro ────────────────────────────────────────────────────────────

  void _poner(EstadoDeLaCentral nuevo) {
    _estado = nuevo;
    _avisar();
  }

  void _avisar() {
    if (!_cerrado) notifyListeners();
  }

  void _buscarOIr() {
    final aMano = _aMano;
    if (aMano != null) {
      _buscador.parar();
      _conectar(aMano);
      return;
    }
    unawaited(_buscador.buscar((donde) {
      if (_cerrado || _canal != null) return;
      _buscador.parar();
      _conectar(donde);
    }));
  }

  void _cortar() {
    _reintento?.cancel();
    _latidos?.cancel();
    unawaited(_escucha?.cancel());
    unawaited(_canal?.sink.close());
    _canal = null;
    _escucha = null;
  }

  void _conectar(DondeEstaLaCentral donde) {
    if (_cerrado) return;
    _cortar();
    _donde = donde;
    final uri = Uri(
      scheme: 'ws',
      host: donde.direccion,
      port: donde.puerto,
      path: '/barra',
      queryParameters: {'evento': eventoId, 'equipo': equipo, 'caja': nombreCaja},
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
      (m) {
        if (identical(_canal, canal)) unawaited(_mensaje(m));
      },
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
      unawaited(_latir());
    });
  }

  Future<void> _latir() async {
    final p = await _barra.pendientesDeLaBarra();
    _enviar({'t': 'hola', 'ventas': p.ventas, 'otros': p.otros});
  }

  void _seCorto(int? codigo) {
    if (_cerrado) return;
    _canal = null;
    _latidos?.cancel();
    final estaba = _estado == EstadoDeLaCentral.conectada || _estado == EstadoDeLaCentral.sinCentral;
    if (estaba) {
      _desde ??= _ahora();
      _poner(EstadoDeLaCentral.sinCentral);
    }
    if (codigo == 4001) {
      // Es la central de otra fiesta: se busca de nuevo.
      _donde = null;
    }
    _intentos++;
    final espera = pausa * (_intentos < 5 ? _intentos : 5);
    _reintento = Timer(espera, () {
      if (_cerrado) return;
      // Después de dos intentos a la misma dirección se vuelve a preguntar por la red:
      // la notebook pudo cambiar de dirección (otro router, se reinició).
      final donde = _donde;
      if (_aMano == null && (donde == null || _intentos > 2)) {
        _buscarOIr();
      } else {
        _conectar(_aMano ?? donde!);
      }
    });
  }

  void _enviar(Map<String, Object?> mensaje) {
    try {
      _canal?.sink.add(jsonEncode(mensaje));
    } catch (_) {}
  }

  Future<void> _mensaje(dynamic texto) async {
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
      case 'filas':
        final volvio = _estado != EstadoDeLaCentral.conectada;
        if (volvio) {
          _intentos = 0;
          _desde = null;
          _poner(EstadoDeLaCentral.conectada);
          // Lo de este equipo, entero: lo que se hizo sin central y lo que la central no
          // tenga (se reinició, es otra notebook).
          final mio = await _barra.filasDeLaFiesta(eventoId);
          _enviar({'t': 'filas', 'filas': mio});
          _porMandar.clear();
          unawaited(_latir());
          _avisar();
        }
        final filas = json['filas'];
        if (filas is Map) await _guardar(filas);
      case 'hola':
        final c = json['cajas'];
        if (c is int && c != _cajas) {
          _cajas = c;
          _avisar();
        }
    }
  }

  Future<void> _guardar(Map<dynamic, dynamic> filas) async {
    var algo = false;
    for (final tabla in tablasDeLaRed) {
      final lista = filas[tabla];
      if (lista is! List) continue;
      for (final f in lista) {
        if (!filaDeLaFiesta(tabla, f, eventoId)) continue;
        try {
          if (await _barra.guardarDeOtroEquipo(tabla, Map<String, Object?>.from(f as Map))) algo = true;
        } catch (e) {
          debugPrint('Barra: no se guardó una fila de la central ($tabla): $e');
        }
      }
    }
    if (algo) alGuardar?.call();
  }
}
