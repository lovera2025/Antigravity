import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../barra/central/buscar_central.dart';
import '../recepcion/central/pedidos_de_la_puerta.dart';
import '../totem/services/tiempos_a_mano.dart';
import 'red_de_la_tele.dart';

/// Cómo está la Tele 2 con la Tele 1.
enum EstadoDeLaSegunda {
  /// Preguntando por el wifi dónde está la Tele 1.
  buscando,

  /// La encontró y se está conectando.
  conectando,

  /// Conectada: recibe la lista y lo que tiene que saludar.
  conectada,

  /// Tenía la lista y se cortó: sigue con la copia y vuelve a probar.
  cortada,

  /// La Tele 1 tiene otra fiesta: no es la suya.
  otraFiesta,
}

/// **La Tele 2, del lado de la Tele 2** (la tele es el tótem, 24-nov-2026).
///
/// Busca a la Tele 1 por el wifi (`BuscaCentral`, puerto
/// `kPuertoBusquedaTele`), o va a la dirección escrita a mano, y se conecta a
/// su central por `/tele?evento=<id>&n=2`. Lo que le llega:
///
/// - **Las filas de la lista de la puerta** que cambiaron, con cómo se saluda a
///   cada ingreso ([BienvenidaDeLaNoche]): la Tele 2 anota primero la
///   bienvenida ([alRecibirBienvenidas]) y después copia las filas en su base
///   ([alRecibirFilas]), así su tótem ya sabe si saludar cuando la base avisa.
/// - **Los segundos de la llegada** que eligió su recepcionista.
/// - **Quién la maneja** ("Juli") y el código del QR de los celulares.
///
/// Sin pantalla ni base: la pantalla de la tele lo escucha.
class ClienteDeLaTele extends ChangeNotifier {
  ClienteDeLaTele({
    required this.eventoId,
    required this.numero,
    required this.alRecibirFilas,
    required this.alRecibirBienvenidas,
    this.alRecibirTiempos,
    this.tiemposAlConectar,
    this.direccionAMano,
    WebSocketChannel Function(Uri)? abrir,
    BuscaCentral? busca,
    DateTime Function()? ahora,
    this.latido = const Duration(seconds: 5),
    this.silencioMaximo = const Duration(seconds: 15),
  })  : _abrir = abrir ?? WebSocketChannel.connect,
        _busca = busca,
        _ahora = ahora ?? DateTime.now;

  final String eventoId;
  final int numero;

  /// Copia las filas en la base de esta tele (`guardarDeOtraTele`).
  final Future<void> Function(List<Map<String, dynamic>> filas) alRecibirFilas;

  /// Anota cómo se saluda a cada uno, antes de copiar sus filas.
  final void Function(Map<String, BienvenidaDeLaNoche> bienvenidas)
      alRecibirBienvenidas;

  /// Los segundos de la llegada de esta tele, cambiados desde un celular.
  final void Function(TiemposAMano t)? alRecibirTiempos;

  /// Los segundos con que arranca esta tele: se le cuentan a la Tele 1, que
  /// se los muestra a los celulares de esta tele.
  final TiemposAMano? Function()? tiemposAlConectar;

  /// "192.168.0.10:8787": si está, no se busca por el wifi.
  final String? direccionAMano;

  final WebSocketChannel Function(Uri) _abrir;
  BuscaCentral? _busca;
  final DateTime Function() _ahora;
  final Duration latido;
  final Duration silencioMaximo;

  EstadoDeLaSegunda _estado = EstadoDeLaSegunda.buscando;
  EstadoDeLaSegunda get estado => _estado;

  /// Dónde está la Tele 1 (la encontrada o la escrita).
  DondeEstaLaCentral? _donde;
  DondeEstaLaCentral? get donde => _donde;

  /// El código de los celulares: con esto la Tele 2 muestra un QR que los
  /// conecta a la Tele 1 con "Tele 2" ya elegida.
  String? _codigo;
  String? get codigo => _codigo;

  /// Quién maneja esta tele: los celulares que la eligieron.
  List<String> _manejan = const [];
  List<String> get manejan => _manejan;

  /// Los ids que se copiaron de la Tele 1 esta noche: si la Tele 1 se apaga y
  /// esta pasa a principal, se suben.
  final copiadas = <String>{};

  /// Desde cuándo está cortada.
  DateTime? _desde;
  DateTime? get cortadaDesde => _desde;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _escucha;
  Timer? _latidos;
  Timer? _reintento;
  DateTime _ultimaNoticia = DateTime.fromMillisecondsSinceEpoch(0);
  var _intentos = 0;
  var _cerrado = false;
  var _cadena = Future<void>.value();

  /// El link del QR para los celulares de esta tele, o null si todavía no se
  /// conectó.
  String? get enlaceParaCelulares {
    final d = _donde;
    final c = _codigo;
    if (d == null || c == null) return null;
    return 'http://${d.texto}/?c=$c&t=$numero';
  }

  void arrancar() {
    final aMano = direccionAMano == null
        ? null
        : DondeEstaLaCentral.deTexto(direccionAMano!);
    if (aMano != null) {
      _donde = aMano;
      _conectar();
      return;
    }
    _buscar();
  }

  void _buscar() {
    if (_cerrado) return;
    _poner(EstadoDeLaSegunda.buscando);
    final busca = _busca ??= BuscaCentral(eventoId: eventoId, puerto: kPuertoBusquedaTele);
    unawaited(busca.buscar((donde) {
      if (_cerrado || _canal != null) return;
      busca.parar();
      _donde = donde;
      _conectar();
    }));
  }

  void _conectar() {
    if (_cerrado) return;
    final donde = _donde;
    if (donde == null) return _buscar();
    _reintento?.cancel();
    _latidos?.cancel();
    unawaited(_escucha?.cancel());
    unawaited(_canal?.sink.close());
    if (_estado != EstadoDeLaSegunda.cortada) _poner(EstadoDeLaSegunda.conectando);
    final uri = Uri(
      scheme: 'ws',
      host: donde.direccion,
      port: donde.puerto,
      path: '/tele',
      queryParameters: {'evento': eventoId, 'n': '$numero'},
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
        unawaited(canal.sink.close());
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
    if (codigo == 4001) {
      _poner(EstadoDeLaSegunda.otraFiesta);
    } else {
      _desde ??= _ahora();
      _poner(_estado == EstadoDeLaSegunda.conectada ||
              _estado == EstadoDeLaSegunda.cortada
          ? EstadoDeLaSegunda.cortada
          : EstadoDeLaSegunda.conectando);
    }
    _intentos++;
    final espera = Duration(seconds: _intentos < 5 ? _intentos : 5);
    // Escrita a mano: se vuelve a probar ahí. Encontrada sola: también, y si
    // falla varias veces se busca de nuevo (la Tele 1 pudo cambiar de dirección).
    _reintento = Timer(espera, () {
      if (direccionAMano == null && _intentos > 3) {
        _donde = null;
        _buscar();
      } else {
        _conectar();
      }
    });
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
      case 'central':
        final c = json['codigo'];
        _codigo = c is String ? c : null;
        _intentos = 0;
        _desde = null;
        _poner(EstadoDeLaSegunda.conectada);
        final t = tiemposAlConectar?.call();
        if (t != null) _mandar({'t': 'tiempos', 'tiempos': t.toJson()});
      case 'filas':
        _recibirFilas(json);
      case 'tiempos':
        final t = TiemposAMano.fromJson(json['tiempos']);
        if (t != null) alRecibirTiempos?.call(t);
      case 'maneja':
        final n = json['nombres'];
        _manejan = n is List ? [for (final x in n) if (x is String) x] : const [];
        if (!_cerrado) notifyListeners();
    }
  }

  /// De a una tanda por vez, en el orden en que llegaron: primero cómo se
  /// saluda, después las filas.
  void _recibirFilas(Map<String, dynamic> m) {
    final filas = m['filas'];
    if (filas is! List) return;
    final lista = [
      for (final f in filas)
        if (f is Map<String, dynamic>) f,
    ];
    final ahora = _ahora();
    final crudas = m['bienvenidas'];
    final bienvenidas = <String, BienvenidaDeLaNoche>{};
    if (crudas is Map) {
      for (final e in crudas.entries) {
        final b = BienvenidaDeLaNoche.fromJson(e.value, ahora);
        if (b != null) bienvenidas['${e.key}'] = b;
      }
    }
    _cadena = _cadena.then((_) async {
      if (_cerrado) return;
      alRecibirBienvenidas(bienvenidas);
      try {
        await alRecibirFilas(lista);
        for (final f in lista) {
          final id = f['id'];
          if (id is String) copiadas.add(id);
        }
      } catch (e) {
        debugPrint('La Tele 2 no pudo copiar la lista: $e');
      }
    });
  }

  void _poner(EstadoDeLaSegunda e) {
    _estado = e;
    if (!_cerrado) notifyListeners();
  }

  @override
  void dispose() {
    _cerrado = true;
    _reintento?.cancel();
    _latidos?.cancel();
    _busca?.parar();
    unawaited(_escucha?.cancel());
    unawaited(_canal?.sink.close());
    super.dispose();
  }
}
