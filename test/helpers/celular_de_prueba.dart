// Un celular de la puerta que se conecta a la central como uno de verdad, por
// la red de esta PC. Lo usan `test/central_puerta_test.dart` y
// `test/central_provider_test.dart`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';

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
  }) async {
    final q = Uri(queryParameters: {'c': codigo, 'id': id, 'p': nombre}).query;
    return CelularDePrueba._(
      await WebSocket.connect('ws://127.0.0.1:$puerto/vivo?$q'),
    );
  }

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
  }) =>
      ws.add(jsonEncode(
        PedidoPuerta(id: id, que: que, personaId: persona, hace: hace)
            .toJson(),
      ));

  Future<Map<String, dynamic>> pedirYEsperar(
    String id,
    QuePide que,
    String persona, {
    Duration hace = Duration.zero,
  }) {
    pedir(id, que, persona, hace: hace);
    return espera('respuesta', cumple: (m) => m['id'] == id);
  }

  Future<int?> cerro() => _cerro.future.timeout(const Duration(seconds: 5));

  Future<void> irse() => ws.close();
}
