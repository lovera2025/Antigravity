// La cola de subida de la lista de la puerta: un cambio hecho mientras sube el
// anterior no se puede perder (la trampa de `SyncQueue.markCompleted`).
//
// Hasta la 6.8.0, agregar a alguien a mano, sacarlo o destrabarle el DNI subía
// "ya" por un camino que, al terminar, borraba de la cola todo lo de esa
// persona: si justo se la había marcado, ese ingreso quedaba sin subir para
// siempre (revisión del 13-nov). Sobre una base temporal, con una nube de
// mentira que contesta cuando la prueba quiere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/repositories/sillas_puerta_repository.dart';

const _ev = 'eeeeeeee-0000-4000-8000-000000000009';

class _ConConexion extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.online;
}

/// La nube: cada pedido queda esperando hasta que la prueba lo suelta, bien o
/// con error.
class _Nube {
  final pedidos = <({String metodo, Object? cuerpo, Completer<bool> suelta})>[];

  http.Client get cliente => MockClient((req) async {
        // Solo lo que va a la tabla: el aviso al tótem (un broadcast) también
        // sale por acá, y ese se contesta enseguida.
        if (req.url.pathSegments.last != 'invitados') {
          return http.Response('{}', 202, request: req);
        }
        final suelta = Completer<bool>();
        pedidos.add((
          metodo: req.method,
          cuerpo: req.body.isEmpty ? null : jsonDecode(req.body),
          suelta: suelta,
        ));
        final bien = await suelta.future;
        return http.Response(
          bien ? '[]' : jsonEncode({'message': 'se cortó', 'code': '500'}),
          bien ? 201 : 500,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      });
}

void main() {
  late Directory docs;
  late _Nube nube;
  late InvitadosRepository repo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('puerta_cola');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    nube = _Nube();
    final c = SupabaseClient(
      'https://nube.test',
      'anon-de-test',
      httpClient: nube.cliente,
    );
    c.auth.stopAutoRefresh();
    addTearDown(c.dispose);
    repo = InvitadosRepository(c, _ConConexion());
  });

  tearDown(() async {
    // Que ningún pedido quede colgado al cerrar.
    for (final p in nube.pedidos) {
      if (!p.suelta.isCompleted) p.suelta.complete(false);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> cola() async {
    final db = await LocalDatabase.instance;
    return db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['invitados']);
  }

  Future<void> unRato() => Future<void>.delayed(const Duration(milliseconds: 60));

  /// Espera a que la nube tenga [n] pedidos de los que cambian algo.
  Future<void> hastaTener(int n) async {
    final tope = DateTime.now().add(const Duration(seconds: 5));
    while (nube.pedidos.where((p) => p.metodo != 'GET').length < n) {
      if (DateTime.now().isAfter(tope)) fail('la nube no recibió $n pedidos');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  List<({String metodo, Object? cuerpo, Completer<bool> suelta})> cambios() =>
      [for (final p in nube.pedidos) if (p.metodo != 'GET') p];

  test('agregado a mano y marcado mientras el alta sube: el ingreso no se '
      'pierde', () async {
    final id = await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADA, UNA');
    await hastaTener(1); // el alta, subiendo

    // Mientras tanto la marcan: la entrada de la cola pasa a llevar el ingreso.
    await repo.marcarIngreso(id);
    await hastaTener(2);

    // El alta termina bien; la subida del ingreso se corta.
    cambios()[0].suelta.complete(true);
    await unRato();
    cambios()[1].suelta.complete(false);
    await unRato();

    final entradas = await cola();
    expect(entradas, hasLength(1),
        reason: 'el ingreso todavía no subió: tiene que seguir en la cola');
    final payload = jsonDecode(entradas.single['payload'] as String) as Map;
    expect(payload['estado_ingreso'], 'ingresado');
  });

  test('destrabado el DNI y marcada mientras eso sube: tampoco se pierde',
      () async {
    final id = await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADA, UNA');
    await hastaTener(1);
    cambios()[0].suelta.complete(true);
    await unRato();
    expect(await cola(), isEmpty);

    await repo.resetearIntentos(id);
    await hastaTener(2); // el destrabe, subiendo
    await repo.marcarIngreso(id);
    await hastaTener(3);
    cambios()[1].suelta.complete(true);
    await unRato();
    cambios()[2].suelta.complete(false);
    await unRato();

    final entrada = (await cola()).single;
    final payload = jsonDecode(entrada['payload'] as String) as Map;
    expect(payload['estado_ingreso'], 'ingresado');
  });

  test('vaciar la lista: lo borrado sube y sale de la cola', () async {
    await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADA, UNA');
    await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADO, OTRO');
    await hastaTener(2);
    cambios()[0].suelta.complete(true);
    cambios()[1].suelta.complete(true);
    await unRato();
    expect(await cola(), isEmpty);

    await repo.vaciarEvento(_ev);
    expect(await cola(), hasLength(2), reason: 'los dos borrados, esperando');
    await hastaTener(3);
    expect(cambios()[2].metodo, 'DELETE');
    cambios()[2].suelta.complete(true);
    await unRato();
    expect(await cola(), isEmpty);
    expect(await repo.getLocalesByEvento(_ev), isEmpty);
  });

  test('agregado a mano y nada más: sube y sale de la cola', () async {
    await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADA, UNA');
    await hastaTener(1);
    expect(await cola(), hasLength(1));
    cambios()[0].suelta.complete(true);
    await unRato();
    expect(await cola(), isEmpty);
  });

  test('si el alta no sube, queda en la cola para el motor', () async {
    await repo.agregar(eventoId: _ev, nombreCompleto: 'INVITADA, UNA');
    await hastaTener(1);
    cambios()[0].suelta.complete(false);
    await unRato();
    final entrada = (await cola()).single;
    expect(entrada['operacion'], 'insert');
  });

  // Para "Todo subido" de Recepción: las sillas de la noche también esperan.
  test('las sillas de la noche que esperan subir se cuentan, por evento',
      () async {
    const otro = 'eeeeeeee-0000-4000-8000-00000000000a';
    const familia = 'c1000000-0000-4000-8000-000000000001';
    final sillas = SillasPuertaRepository();
    expect(await sillas.sinSubir(_ev), 0);

    final una = await sillas.anotar(
      eventoId: _ev,
      contratoAlumnoId: familia,
      mesa: 12,
      vale: '2-17',
    );
    await sillas.anotar(
      eventoId: otro,
      contratoAlumnoId: familia,
      mesa: 3,
      vale: '1-4',
    );
    expect(await sillas.sinSubir(_ev), 1);
    expect(await sillas.sinSubir(otro), 1);

    // Quitarla reescribe la misma fila: sigue siendo una sola cosa por subir.
    await sillas.quitar(una.id, por: 'Recepción', motivo: 'se anotó mal');
    expect(await sillas.sinSubir(_ev), 1);
  });

  test('en el archivo no queda ningún borrado a mano de la cola', () {
    final fuente = File(
      'lib/features/recepcion/repositories/invitados_repository.dart',
    ).readAsStringSync();
    expect(
      RegExp(r"\.delete\(\s*'_sync_queue'").hasMatch(fuente),
      isFalse,
      reason: 'se saca con SyncQueue.markCompleted(leidaCon:), que no pisa un '
          'cambio hecho mientras subía el anterior',
    );
  });
}
