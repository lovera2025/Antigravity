import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';

/// Una nube de mentira para el motor de sincronización: contesta como
/// PostgREST y anota cada pedido ("GET tabla", "PATCH tabla", "HEAD tabla").
///
/// Nunca sale nada de la PC. Sacada de `test/borrados_de_otra_pc_test.dart`
/// (6.3.3) para las pruebas del sync en reposo.
class NubeDePrueba {
  final filas = <String, List<Map<String, Object?>>>{};

  /// Cada pedido, en orden: "MÉTODO tabla".
  final pedidas = <String>[];

  /// Una cuenta que no coincide con lo que se devuelve: una foto incompleta.
  final cuentaDe = <String, int>{};

  /// Lo que pasa en la PC mientras la nube contesta esa tabla.
  final alPedir = <String, Future<void> Function()>{};

  /// Pedidos que se quedan esperando: así la PC queda ocupada.
  final frenadas = <String, Completer<void>>{};

  /// "MÉTODO tabla" → el código con que la nube lo rechaza.
  final fallan = <String, int>{};

  /// Sin red: cada pedido falla antes de llegar.
  var caida = false;

  /// Lo que se pidió, sin las bajadas del arranque: para contar el reposo.
  List<String> desde(int marca) => pedidas.sublist(marca);

  http.Client get cliente => MockClient((req) async {
        final tabla = req.url.pathSegments.last;
        final pedido = '${req.method} $tabla';
        pedidas.add(pedido);
        if (caida) throw http.ClientException('sin red (prueba)', req.url);
        final freno = frenadas[tabla];
        if (freno != null) await freno.future;
        final antes = alPedir[tabla];
        if (antes != null) await antes();

        final codigo = fallan[pedido];
        if (codigo != null) {
          return http.Response(
            jsonEncode({
              'code': '$codigo',
              'message': 'rechazado (prueba)',
              'details': null,
              'hint': null,
            }),
            codigo,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }

        if (req.method == 'POST' || req.method == 'PATCH' || req.method == 'DELETE') {
          return http.Response('', req.method == 'POST' ? 201 : 204, request: req);
        }

        final q = req.url.queryParameters;
        var lista = List<Map<String, Object?>>.from(filas[tabla] ?? const []);
        for (final e in q.entries) {
          if (!e.value.startsWith('eq.')) continue;
          final v = e.value.substring(3);
          lista = lista.where((f) => f[e.key]?.toString() == v).toList();
        }
        final total = cuentaDe[tabla] ?? lista.length;
        final desde = int.tryParse(q['offset'] ?? '') ?? 0;
        final tope = int.tryParse(q['limit'] ?? '');
        var pagina = lista.skip(desde).toList();
        if (tope != null) pagina = pagina.take(tope).toList();
        final headers = {
          'content-type': 'application/json',
          'content-range': pagina.isEmpty
              ? '*/$total'
              : '$desde-${desde + pagina.length - 1}/$total',
        };
        if (req.method == 'HEAD') {
          return http.Response('', 200, headers: headers, request: req);
        }
        return http.Response(
          jsonEncode(pagina),
          200,
          headers: headers,
          request: req,
        );
      });

  /// Un cliente de Supabase que le habla a esta nube.
  SupabaseClient clienteSupabase() {
    final c = SupabaseClient('https://nube.test', 'anon-de-test',
        httpClient: cliente);
    c.auth.stopAutoRefresh();
    return c;
  }
}

/// La red de las pruebas del motor: la prueba la corta o la vuelve a poner
/// ([poner]), y despertar la nube no sale a ningún lado.
class RedDePrueba extends ConnectivityService {
  RedDePrueba([this.estado = AppConnectivity.online]);
  AppConnectivity estado;
  final _cambios = StreamController<AppConnectivity>.broadcast();

  /// Cuántas veces el motor pidió despertar la nube (el ping de antes de cada
  /// bajada o subida).
  var despertares = 0;

  @override
  AppConnectivity get currentStatus => estado;

  @override
  Stream<AppConnectivity> get stream => _cambios.stream;

  @override
  Future<bool> wakeUpCloud() async {
    despertares++;
    return estado == AppConnectivity.online;
  }

  void poner(AppConnectivity nuevo) {
    estado = nuevo;
    _cambios.add(nuevo);
  }
}
