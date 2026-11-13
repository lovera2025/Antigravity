import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/main.dart';
import 'package:arguello_events/models/totem_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// La config del tótem cuando la nube no se puede leer (revisión del 13-nov).
///
/// Hasta la 6.8.0, la notebook que abría el tótem sin internet mostraba un
/// instante lo guardado en la PC y enseguida volvía a "JUNIOR EVENTOS", sin
/// foto; y aunque volviera internet seguía así hasta esconder el tótem.
///
/// Va con la librería de Supabase de verdad contra esta misma PC: un puerto
/// donde nadie escucha es "sin internet", y un servidor chico en ese puerto es
/// "volvió internet". Sin la base, sin la nube y sin salir de la PC.
const _evento = '11111111-2222-4333-8444-555555555555';

final _guardada = TotemConfig.defaults(_evento).copyWith(
  titulo: 'PROMOCIÓN 2026',
  imagenUrl: 'https://ejemplo/foto.jpg',
);

/// Un puerto libre de esta PC, donde por ahora no escucha nadie.
Future<int> _puertoLibre() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final puerto = s.port;
  await s.close();
  return puerto;
}

String _como(TotemConfig c) => '${c.titulo} | foto=${c.imagenUrl}';

void main() {
  late SupabaseClient nube;
  late ProviderContainer c;
  late List<String> emitidos;
  late int puerto;
  HttpServer? servidor;

  setUp(() async {
    // HTTP de verdad: con el de las pruebas de pantallas, todo contesta 400.
    HttpOverrides.global = null;
    puerto = await _puertoLibre();
    nube = SupabaseClient('http://127.0.0.1:$puerto', 'x');
    emitidos = [];
  });

  tearDown(() async {
    c.dispose();
    await servidor?.close(force: true);
    servidor = null;
    // Sin esperarlo de más: cerrar un cliente que nunca llegó a conectarse
    // puede no terminar.
    try {
      await nube.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  });

  void abrir() {
    c = ProviderContainer(overrides: [
      supabaseProvider.overrideWithValue(nube),
      esperaDeLaConfigProvider
          .overrideWithValue((_) => const Duration(milliseconds: 150)),
    ]);
    c.listen<AsyncValue<TotemConfig>>(totemConfigProvider(_evento), (_, v) {
      v.whenData((cfg) => emitidos.add(_como(cfg)));
    }, fireImmediately: true);
  }

  Future<void> hasta(bool Function() listo, {int segundos = 8}) async {
    final tope = DateTime.now().add(Duration(seconds: segundos));
    while (!listo() && DateTime.now().isBefore(tope)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('sin internet, con lo guardado en la PC: se queda con eso', () async {
    SharedPreferences.setMockInitialValues({
      'totem_config_v1_$_evento': jsonEncode(_guardada.toJson()),
    });
    abrir();
    // Tiempo de sobra para varias lecturas fallidas y sus reintentos.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(emitidos, isNotEmpty);
    expect(emitidos.toSet(), {_como(_guardada)},
        reason: 'nunca vuelve a los valores de fábrica');
    expect(_como(c.read(totemConfigValueProvider(_evento))), _como(_guardada));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('sin internet y sin nada guardado: los valores de siempre, una vez',
      () async {
    SharedPreferences.setMockInitialValues({});
    abrir();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(emitidos, [_como(TotemConfig.defaults(_evento))]);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cuando vuelve internet, lee la de la nube sola', () async {
    SharedPreferences.setMockInitialValues({
      'totem_config_v1_$_evento': jsonEncode(_guardada.toJson()),
    });
    abrir();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(emitidos.toSet(), {_como(_guardada)});

    // Vuelve internet: ahora en ese puerto contesta "la nube".
    final deLaNube = _guardada.copyWith(titulo: 'DESDE LA NUBE');
    var pedidos = 0;
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, puerto);
    servidor!.listen((pedido) async {
      if (pedido.uri.path.endsWith('/totem_config')) {
        pedidos++;
        pedido.response.headers.contentType = ContentType.json;
        pedido.response.write(jsonEncode([deLaNube.toJson()]));
      } else {
        pedido.response.statusCode = HttpStatus.notFound;
      }
      await pedido.response.close();
    });

    await hasta(() => emitidos.contains(_como(deLaNube)));
    expect(emitidos.last, _como(deLaNube));
    expect(_como(c.read(totemConfigValueProvider(_evento))), _como(deLaNube));

    // Con una lectura buena alcanza: en reposo no se le pide nada a la nube.
    final hastaAca = pedidos;
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(pedidos, hastaAca, reason: 'ya la leyó: no sigue reintentando');

    // Y quedó guardada en la PC para la próxima vez sin internet.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('totem_config_v1_$_evento'), contains('DESDE LA NUBE'));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('la espera entre reintentos crece hasta un minuto y ahí se queda', () {
    expect(
      [for (var i = 0; i < 7; i++) esperaDeReintentoDeLaConfig(i).inSeconds],
      [5, 10, 20, 40, 60, 60, 60],
    );
    expect(esperaDeReintentoDeLaConfig(-3).inSeconds, 5);
    expect(esperaDeReintentoDeLaConfig(100000).inSeconds, 60);
  });
}
