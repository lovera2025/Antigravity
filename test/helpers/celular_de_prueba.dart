// Un celular de la puerta que se conecta a la central como uno de verdad, por
// la red de esta PC. Lo usan `test/central_puerta_test.dart` y
// `test/central_provider_test.dart`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/totem/services/tiempos_a_mano.dart';

class CelularDePrueba {
  CelularDePrueba._(this.ws) {
    ws.listen(
      (m) {
        _llegados.add(jsonDecode(m as String) as Map<String, dynamic>);
        _aviso.add(null);
      },
      onDone: () {
        if (!_cerro.isCompleted) _cerro.complete(ws.closeCode);
      },
    );
  }

  final WebSocket ws;
  final _llegados = <Map<String, dynamic>>[];
  final _leidos = <int>{};
  final _aviso = StreamController<void>.broadcast();
  final _cerro = Completer<int?>();

  static Future<CelularDePrueba> conectar(
    int puerto, {
    required String codigo,
    String id = 'cel-juli',
    String nombre = 'Juli',
    int? tele,
  }) async {
    final q = Uri(queryParameters: {
      'c': codigo,
      'id': id,
      'p': nombre,
      if (tele != null) 't': '$tele',
    }).query;
    return CelularDePrueba._(
      await WebSocket.connect('ws://127.0.0.1:$puerto/vivo?$q'),
    );
  }

  /// La Tele 2 (la tele es el tótem, 24-nov-2026), conectada a la central de
  /// la Tele 1 como una de verdad.
  static Future<CelularDePrueba> conectarTele(
    int puerto, {
    required String evento,
    int numero = 2,
  }) async {
    final q = Uri(queryParameters: {'evento': evento, 'n': '$numero'}).query;
    return CelularDePrueba._(
      await WebSocket.connect('ws://127.0.0.1:$puerto/tele?$q'),
    );
  }

  /// "Tu tele": cambia la tele de este celular.
  void elegirTele(int n) => ws.add(jsonEncode({'t': 'tele', 'n': n}));

  /// Manda cualquier mensaje (25-nov-2026: CAMBIAR LA ESCUELA, GIRAR, la
  /// respuesta a MANTENER · CAMBIAR).
  void mandar(Map<String, Object?> m) => ws.add(jsonEncode(m));

  /// El próximo mensaje de tipo [tipo] que todavía no se miró. Con [cumple],
  /// el próximo de ese tipo que cumpla (los anteriores quedan mirados).
  Future<Map<String, dynamic>> espera(
    String tipo, {
    bool Function(Map<String, dynamic>)? cumple,
  }) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      for (var i = 0; i < _llegados.length; i++) {
        if (_leidos.contains(i) || _llegados[i]['t'] != tipo) continue;
        _leidos.add(i);
        if (cumple == null || cumple(_llegados[i])) return _llegados[i];
      }
      final falta = limite.difference(DateTime.now());
      if (falta.isNegative) throw TimeoutException('no llegó "$tipo"');
      await _aviso.stream.first.timeout(falta, onTimeout: () {});
    }
  }

  void pedir(
    String id,
    QuePide que,
    String persona, {
    Duration hace = Duration.zero,
    DatosSilla? silla,
    TiemposAMano? tiempos,
    int? tele,
    String? evento,
  }) => ws.add(
    jsonEncode(
      PedidoPuerta(
        id: id,
        que: que,
        personaId: persona,
        hace: hace,
        silla: silla,
        tiempos: tiempos,
        tele: tele,
        evento: evento,
      ).toJson(),
    ),
  );

  Future<Map<String, dynamic>> pedirYEsperar(
    String id,
    QuePide que,
    String persona, {
    Duration hace = Duration.zero,
    DatosSilla? silla,
    TiemposAMano? tiempos,
    int? tele,
    String? evento,
  }) {
    pedir(id, que, persona,
        hace: hace, silla: silla, tiempos: tiempos, tele: tele, evento: evento);
    return espera('respuesta', cumple: (m) => m['id'] == id);
  }

  /// Cuántos mensajes de tipo [tipo] llegaron hasta ahora.
  int cuantos(String tipo) => _llegados.where((m) => m['t'] == tipo).length;

  Future<int?> cerro() => _cerro.future.timeout(const Duration(seconds: 5));

  Future<void> irse() => ws.close();
}
