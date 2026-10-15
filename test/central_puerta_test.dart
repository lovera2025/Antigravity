import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/celular_de_prueba.dart';

/// La central de la puerta de verdad (`CentralPuerta`), escuchando solo en esta
/// PC, con celulares de mentira que se conectan por la red como los de
/// verdad. Lo único en memoria es la base ([_PcEnMemoria]).
const _evento = 'e0000000-0000-4000-8000-00000000000b';
const _codigo = '4821';
final _hora = DateTime.utc(2026, 12, 13, 1, 41);

Invitado _fila(String id, String nombre, {bool adentro = false}) => Invitado(
      id: id,
      eventoId: _evento,
      nombreCompleto: nombre,
      dni: '',
      estadoIngreso:
          adentro ? EstadoIngreso.ingresado : EstadoIngreso.pendiente,
      updatedAt: adentro ? _hora : null,
    );

/// La base de la notebook: las filas de la puerta y lo que se le pidió.
class _PcEnMemoria implements PuertaDeEstaPc {
  final filas = <String, Invitado>{};
  final ingresos = <(String, bool)>[];
  final deshechos = <String>[];
  var falla = false;

  /// Cuánto tarda en marcar: para que dos pedidos se crucen.
  var demora = Duration.zero;

  @override
  Future<Invitado?> fila(String id) async => filas[id];

  @override
  Future<void> ingresar(
    String eventoId,
    PersonaPuerta persona, {
    required bool saludar,
  }) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    ingresos.add((persona.id, saludar));
    filas[persona.id] = _fila(persona.id, persona.nombre, adentro: true);
  }

  @override
  Future<void> deshacer(String id) async {
    await Future<void>.delayed(demora);
    if (falla) throw StateError('la base no anda');
    deshechos.add(id);
    filas[id] = _fila(id, filas[id]!.nombreCompleto);
  }

  /// La lista como la armaría Recepción con estas filas.
  PuertaDelEvento lista() => PuertaDelEvento.particular(filas.values.toList());
}

void main() {
  late _PcEnMemoria pc;
  late CentralPuerta central;
  late int puerto;
  late DateTime ahora;
  final celulares = <CelularDePrueba>[];

  Future<CelularDePrueba> celular({
    String codigo = _codigo,
    String id = 'cel-juli',
    String nombre = 'Juli',
  }) async {
    final c = await CelularDePrueba.conectar(
      puerto,
      codigo: codigo,
      id: id,
      nombre: nombre,
    );
    celulares.add(c);
    return c;
  }

  setUp(() async {
    pc = _PcEnMemoria()
      ..filas['p1'] = _fila('p1', 'PÉREZ, JUAN')
      ..filas['p2'] = _fila('p2', 'ACOSTA, LUCÍA');
    ahora = DateTime(2026, 12, 12, 22);
    central = CentralPuerta(
      eventoId: _evento,
      codigo: _codigo,
      pc: pc,
      ahora: () => ahora,
    );
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    for (final c in celulares) {
      try {
        await c.ws.close();
      } catch (_) {}
    }
    celulares.clear();
    await central.cerrar();
  });

  group('el código', () {
    test('sin el código bueno no entra, y se le dice por qué', () async {
      final c = await celular(codigo: '1111');
      expect((await c.espera('codigo'))['t'], 'codigo');
      expect(await c.cerro(), 4001);
      expect(central.puestos, isEmpty);
    });

    test('cinco errores seguidos lo frenan un minuto, aunque después ponga el '
        'bueno', () async {
      for (var i = 0; i < kErroresDeCodigo; i++) {
        final c = await celular(codigo: '1111');
        expect(await c.cerro(), 4001);
      }
      final frenado = await celular();
      await frenado.espera('espera');
      expect(await frenado.cerro(), 4029);

      ahora = ahora.add(kFrenoPorErrores);
      final despues = await celular();
      // Entró: como la PC todavía no tiene la lista, espera.
      await despues.espera('esperando');
      expect(central.puestos.single.conectado, isTrue);
    });

    test('sin nombre no entra', () async {
      final c = await celular(nombre: '   ');
      await c.espera('nombre');
      expect(await c.cerro(), 4002);
    });

    test('cambiar el código saca a todos; con el viejo ya no entra', () async {
      central.ponerPuerta(pc.lista());
      final juli = await celular();
      await juli.espera('puerta');

      await central.cambiarCodigo('5555');
      await juli.espera('codigo');
      expect(await juli.cerro(), 4001);
      expect(central.puestos, isEmpty);

      final viejo = await celular(id: 'otro');
      expect(await viejo.cerro(), 4001);
      final nuevo = await celular(codigo: '5555', id: 'otro2');
      await nuevo.espera('puerta');
    });
  });

  group('la lista', () {
    test('al entrar recibe la lista de la puerta', () async {
      central.ponerPuerta(pc.lista());
      final c = await celular();
      final m = await c.espera('puerta');
      expect(m['evento'], _evento);
      final lista = PuertaDelEvento.fromJson(
        m['puerta'] as Map<String, dynamic>,
        eventoId: _evento,
      );
      expect(lista.total, 2);
      expect(lista.adentro, 0);
    });

    test('si la PC todavía no la tiene, espera, y le llega apenas está',
        () async {
      final c = await celular();
      await c.espera('esperando');
      central.ponerPuerta(pc.lista());
      await c.espera('puerta');
    });

    test('cada cambio les llega a todos, con quién marcó a cada uno', () async {
      central.ponerPuerta(pc.lista());
      final juli = await celular();
      final pato = await celular(id: 'cel-pato', nombre: 'Pato');
      final v1 = (await juli.espera('puerta'))['v'] as int;
      await pato.espera('puerta');

      await juli.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      central.ponerPuerta(pc.lista());

      for (final c in [juli, pato]) {
        final m = await c.espera('puerta');
        expect(m['v'], greaterThan(v1));
        expect(m['por'], {'p1': 'Juli'});
        final lista = PuertaDelEvento.fromJson(
          m['puerta'] as Map<String, dynamic>,
          eventoId: _evento,
        );
        expect(lista.adentro, 1);
      }
    });
  });

  group('los pedidos', () {
    setUp(() => central.ponerPuerta(pc.lista()));

    test('ingresar: se marca en la PC, se saluda y se contesta', () async {
      final c = await celular();
      final r = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r['ok'], isTrue);
      expect(r['hizo'], 'ingresar');
      expect(r['aviso'], isNull);
      expect(pc.ingresos, [('p1', true)]);
      expect(central.marcas.quien('p1'), 'Juli');
    });

    test('un ingreso que llega tarde se marca sin saludar', () async {
      final c = await celular();
      await c.pedirYEsperar(
        'a1',
        QuePide.ingresar,
        'p1',
        hace: const Duration(minutes: 3),
      );
      expect(pc.ingresos, [('p1', false)]);
    });

    test('un pedido repetido no se hace dos veces, y se contesta igual',
        () async {
      final c = await celular();
      final r1 = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      final r2 = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r2, r1);
      expect(pc.ingresos, hasLength(1));
    });

    test('un pedido viejo repetido no deshace lo que corrigió otro', () async {
      final juli = await celular();
      final pato = await celular(id: 'cel-pato', nombre: 'Pato');
      await juli.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      await pato.pedirYEsperar('b1', QuePide.deshacer, 'p1');
      // A Juli no le llegó la respuesta y lo vuelve a mandar.
      await juli.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(pc.ingresos, hasLength(1));
      expect(pc.filas['p1']!.estadoIngreso, EstadoIngreso.pendiente);
    });

    test('dos celulares ingresan a la misma persona a la vez: entra una vez y '
        'el otro recibe "ya ingresó"', () async {
      pc.demora = const Duration(milliseconds: 80);
      final juli = await celular();
      final pato = await celular(id: 'cel-pato', nombre: 'Pato');
      juli.pedir('a1', QuePide.ingresar, 'p1');
      pato.pedir('b1', QuePide.ingresar, 'p1');
      final rj = await juli.espera('respuesta');
      final rp = await pato.espera('respuesta');

      expect(pc.ingresos, [('p1', true)]);
      expect(rj['hizo'], 'ingresar');
      expect(rp['hizo'], 'nada');
      expect(rp['ok'], isTrue);
      expect(
        rp['aviso'],
        'PÉREZ, JUAN ya ingresó a las ${horaCorta(_hora)} · Juli.',
      );
    });

    test('deshacer: vuelve a faltar y deja de contarse como de ese puesto',
        () async {
      final c = await celular();
      await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      final r = await c.pedirYEsperar('a2', QuePide.deshacer, 'p1');
      expect(r['hizo'], 'deshacer');
      expect(pc.deshechos, ['p1']);
      expect(central.marcas.quien('p1'), isNull);
    });

    test('si la base falla, contesta que no se pudo y no lo guarda: al '
        'reintentarlo se hace', () async {
      final c = await celular();
      pc.falla = true;
      final r1 = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r1['ok'], isFalse);
      expect(pc.ingresos, isEmpty);

      pc.falla = false;
      final r2 = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r2['ok'], isTrue);
      expect(pc.ingresos, [('p1', true)]);
    });

    test('sin lista todavía, contesta que no se pudo (el celular reintenta)',
        () async {
      final sinLista = CentralPuerta(
        eventoId: _evento,
        codigo: _codigo,
        pc: pc,
      );
      final p = await sinLista.arrancar(
        desde: 0,
        en: InternetAddress.loopbackIPv4,
      );
      final c = await CelularDePrueba.conectar(p, codigo: _codigo);
      celulares.add(c);
      final r = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r['ok'], isFalse);
      expect(pc.ingresos, isEmpty);
      await c.irse();
      await sinLista.cerrar();
    });

    test('a quien se sacó de la lista no se lo vuelve a crear', () async {
      final c = await celular();
      // Se eliminó en la PC; la lista nueva todavía no salió.
      pc.filas.remove('p1');
      final r = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r['hizo'], 'nada');
      expect(r['aviso'], 'Esa persona ya no está en la lista de la puerta.');
      expect(pc.ingresos, isEmpty);
    });

    test('lo que no se entiende se ignora y la conexión sigue', () async {
      final c = await celular();
      c.ws
        ..add('no es json')
        ..add(jsonEncode([1, 2]))
        ..add(jsonEncode({'t': 'pedido', 'id': 'z', 'que': 'borrar'}))
        ..add(jsonEncode({'t': 'otra cosa'}));
      final r = await c.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r['id'], 'a1');
      expect(r['ok'], isTrue);
    });

    test('"hola" se contesta (así el celular sabe que sigue conectado)',
        () async {
      final c = await celular();
      c.ws.add(jsonEncode({'t': 'hola'}));
      await c.espera('hola');
    });
  });

  group('los puestos', () {
    setUp(() => central.ponerPuerta(pc.lista()));

    test('se ve quién está conectado y cuántos marcó', () async {
      final juli = await celular();
      await celular(id: 'cel-pato', nombre: 'Pato');
      await juli.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      await juli.pedirYEsperar('a2', QuePide.ingresar, 'p2');

      final puestos = central.puestos;
      expect([for (final p in puestos) p.nombre], ['Juli', 'Pato']);
      expect(puestos.every((p) => p.conectado), isTrue);
      expect(puestos.first.marcados, 2);
      expect(puestos.last.marcados, 0);
    });

    test('al irse queda en la lista, sin señal y con la hora', () async {
      final juli = await celular();
      await juli.espera('puerta');
      final se = central.cambiosDePuestos
          .firstWhere((l) => l.isNotEmpty && !l.single.conectado);
      ahora = ahora.add(const Duration(minutes: 2));
      await juli.irse();
      final puestos = await se.timeout(const Duration(seconds: 5));
      expect(puestos.single.nombre, 'Juli');
      expect(puestos.single.ultimaVez, ahora);
    });

    test('el mismo celular que vuelve reemplaza la conexión vieja', () async {
      final antes = await celular();
      await antes.espera('puerta');
      final despues = await celular();
      await despues.espera('puerta');
      expect(await antes.cerro(), 4003);
      expect(central.puestos, hasLength(1));
      expect(central.puestos.single.conectado, isTrue);

      // Y sigue andando por la nueva.
      final r = await despues.pedirYEsperar('a1', QuePide.ingresar, 'p1');
      expect(r['ok'], isTrue);
    });

    test('al cerrar la central, los celulares se enteran', () async {
      final c = await celular();
      await c.espera('puerta');
      await central.cerrar();
      expect(await c.cerro(), WebSocketStatus.goingAway);
      // Para el tearDown, una nueva que cerrar.
      central = CentralPuerta(eventoId: _evento, codigo: _codigo, pc: pc);
    });
  });

  group('la página del celular', () {
    late Directory pagina;
    late CentralPuerta conPagina;
    late int puertoPagina;
    final cliente = HttpClient();

    setUp(() async {
      pagina = Directory.systemTemp.createTempSync('pagina_celular');
      File('${pagina.path}/index.html').writeAsStringSync('<html>puesto</html>');
      Directory('${pagina.path}/canvaskit').createSync();
      File('${pagina.path}/canvaskit/canvaskit.wasm')
          .writeAsBytesSync([0, 97, 115, 109]);
      File('${pagina.path}/../secreto_central.txt')
          .writeAsStringSync('no se ve');
      conPagina = CentralPuerta(
        eventoId: _evento,
        codigo: _codigo,
        pc: pc,
        paginaDelCelular: pagina,
      );
      puertoPagina =
          await conPagina.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    });

    tearDown(() async {
      await conPagina.cerrar();
      final secreto = File('${pagina.path}/../secreto_central.txt');
      if (secreto.existsSync()) secreto.deleteSync();
      pagina.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> pedir(String camino, {String metodo = 'GET'}) async {
      final r = await cliente.openUrl(
        metodo,
        Uri.parse('http://127.0.0.1:$puertoPagina$camino'),
      );
      return r.close();
    }

    test('la dirección sola abre la página, y se pide de nuevo cada vez',
        () async {
      final r = await pedir('/');
      expect(r.statusCode, 200);
      expect(r.headers.contentType?.mimeType, 'text/html');
      expect(r.headers.value(HttpHeaders.cacheControlHeader), 'no-cache');
      expect(await utf8.decodeStream(r), '<html>puesto</html>');

      // Con el código en el enlace del QR, también.
      final q = await pedir('/?c=4821');
      expect(q.statusCode, 200);
      await q.drain<void>();
    });

    test('el motor de dibujo va como wasm y se guarda en el celular', () async {
      final r = await pedir('/canvaskit/canvaskit.wasm');
      expect(r.statusCode, 200);
      expect(r.headers.contentType?.mimeType, 'application/wasm');
      expect(r.headers.value(HttpHeaders.cacheControlHeader), 'max-age=86400');
      await r.drain<void>();
    });

    test('no se puede salir de la carpeta ni pedir lo que no está', () async {
      for (final camino in [
        '/%2E%2E/secreto_central.txt',
        '/canvaskit/%2E%2E/%2E%2E/secreto_central.txt',
        '/x%5C..%5C..%5Csecreto_central.txt',
        '/C:%5CWindows%5Cwin.ini',
        '/no_existe.js',
      ]) {
        final r = await pedir(camino);
        expect(r.statusCode, 404, reason: camino);
        await r.drain<void>();
      }
    });

    test('solo se lee: lo demás no se acepta', () async {
      final r = await pedir('/', metodo: 'POST');
      expect(r.statusCode, 405);
      await r.drain<void>();
    });

    test('sin página (no está instalada) no hay nada que ver', () async {
      final r = await HttpClient()
          .getUrl(Uri.parse('http://127.0.0.1:$puerto/'))
          .then((q) => q.close());
      expect(r.statusCode, 404);
      await r.drain<void>();
    });
  });
}
