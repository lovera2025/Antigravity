import 'dart:io';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sillas_reparto_repository.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/recepcion/central/pedidos_de_la_puerta.dart';
import 'package:arguello_events/features/recepcion/providers/acciones_puerta_provider.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/repositories/sillas_puerta_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

/// La central de la puerta prendida desde el programa (`CentralDeLaPuerta`):
/// toma la lista de Recepción de esta PC, la manda a los celulares y marca por
/// el mismo repositorio. Recepción va en memoria ([PuertaEnMemoria]); la
/// central escucha de verdad, solo en esta PC.
const _c1 = 'c1000000-0000-4000-8000-000000000001';
const _c2 = 'c2000000-0000-4000-8000-000000000002';

void main() {
  late PuertaEnMemoria puerta;
  late ProviderContainer container;
  const codigos = ['4821', '5555', '6666'];
  var siguiente = 0;
  String? vigente;
  final celulares = <CelularDePrueba>[];

  /// Recepción en memoria y la central escuchando solo en esta PC (o en
  /// [escucha]).
  List<Override> overrides({InternetAddress? escucha}) => [
        eventosActivosProvider.overrideWith(
          (ref) async => [
            eventoDePrueba(eventoMasivo, 'masivo'),
            eventoDePrueba(eventoParticular, 'particular'),
          ],
        ),
        invitadosRepositoryProvider.overrideWithValue(puerta.invitados),
        contratosRepositoryProvider.overrideWithValue(puerta.contratos),
        sillasRepartoRepositoryProvider.overrideWithValue(puerta.sillas),
        sillasPuertaRepositoryProvider.overrideWithValue(puerta.sillasPuerta),
        syncEngineProvider.overrideWithValue(puerta.motor),
        connectivityServiceProvider.overrideWithValue(puerta.conexion),
        escuchaCentralProvider
            .overrideWithValue(escucha ?? InternetAddress.loopbackIPv4),
        puertoCentralProvider.overrideWithValue(0),
        direccionesDeEstaPcProvider
            .overrideWithValue(() async => ['192.168.0.10']),
        codigoCentralProvider.overrideWithValue((_) async => codigos[siguiente]),
        codigoVigenteCentralProvider.overrideWithValue((_) async => vigente),
        cambiarCodigoCentralProvider.overrideWithValue(
          (_, _) async => codigos[++siguiente],
        ),
        paginaDelCelularProvider.overrideWithValue(null),
      ];

  setUp(() {
    puerta = PuertaEnMemoria(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      alumnos: [
        alumnoDePrueba(_c1, 'PÉREZ, JUAN', acomp: ['GÓMEZ, ANA']),
        alumnoDePrueba(_c2, 'ACOSTA, LUCÍA'),
      ],
    );
    siguiente = 0;
    vigente = null;
    container = ProviderContainer(overrides: overrides());
  });

  tearDown(() async {
    for (final c in celulares) {
      try {
        await c.ws.close();
      } catch (_) {}
    }
    celulares.clear();
    await container.read(centralDeLaPuertaProvider.notifier).apagar();
    container.dispose();
  });

  CentralDeLaPuerta central() => container.read(centralDeLaPuertaProvider.notifier);
  EstadoCentral estado() => container.read(centralDeLaPuertaProvider);

  Future<CelularDePrueba> celular({
    String id = 'cel-juli',
    String nombre = 'Juli',
    String? codigo,
  }) async {
    final c = await CelularDePrueba.conectar(
      estado().puerto!,
      codigo: codigo ?? estado().codigo!,
      id: id,
      nombre: nombre,
    );
    celulares.add(c);
    return c;
  }

  /// La lista de Recepción del masivo, cuando cumple [cumple] (o la primera).
  Future<PuertaDelEvento> leerPuerta({
    bool Function(PuertaDelEvento)? cumple,
  }) async {
    final limite = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final p = container.read(puertaDelEventoProvider(eventoMasivo)).value;
      if (p != null && (cumple == null || cumple(p))) return p;
      if (DateTime.now().isAfter(limite)) {
        throw StateError('la lista no llegó como se esperaba');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  PuertaDelEvento lista(Map<String, dynamic> m) => PuertaDelEvento.fromJson(
        m['puerta'] as Map<String, dynamic>,
        eventoId: eventoMasivo,
      );

  test('prendida, dice la dirección, el código y el enlace del QR', () async {
    expect(estado().prendida, isFalse);
    await central().prender(eventoMasivo);

    final e = estado();
    expect(e.prendida, isTrue);
    expect(e.eventoId, eventoMasivo);
    expect(e.codigo, '4821');
    expect(e.direccion, '192.168.0.10:${e.puerto}');
    expect(e.enlace, 'http://192.168.0.10:${e.puerto}/?c=4821');
    expect(e.error, isNull);
  });

  test('sin router (la PC sin ninguna dirección) no hay dirección ni QR que '
      'mostrar', () {
    const sinRouter = EstadoCentral(
      eventoId: eventoMasivo,
      codigo: '4821',
      puerto: 8787,
    );
    expect(sinRouter.prendida, isTrue);
    expect(sinRouter.direccion, isNull);
    expect(sinRouter.enlace, isNull);
  });

  test('el celular recibe la lista del masivo, armada con los alumnos de la PC',
      () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    final l = lista(await c.espera('puerta'));
    expect(l.masivo, isTrue);
    expect([for (final p in l.personas) p.nombre],
        containsAll(['PÉREZ, JUAN', 'GÓMEZ, ANA', 'ACOSTA, LUCÍA']));
    expect(l.adentro, 0);
  });

  test('lo que ingresa un celular se marca por el repositorio de Recepción y '
      'les llega a todos, con quién lo hizo', () async {
    await central().prender(eventoMasivo);
    final juli = await celular();
    final pato = await celular(id: 'cel-pato', nombre: 'Pato');
    await juli.espera('puerta');
    await pato.espera('puerta');

    final juan = idInvitadoPuerta(_c1, 0);
    final r = await juli.pedirYEsperar('a1', QuePide.ingresar, juan);
    expect(r['hizo'], 'ingresar');
    // Antes del sorteo no tenía fila: se crea, como "Ingresar" en Recepción.
    expect(puerta.invitados.creados, [juan]);
    expect(puerta.invitados.sinSaludo, isEmpty);

    for (final c in [juli, pato]) {
      final m = await c.espera('puerta', cumple: (m) => lista(m).adentro == 1);
      expect(m['por'], {juan: 'Juli'});
    }
    expect(central().quienMarco(juan), 'Juli');
    // La Recepción de la PC también lo dice, debajo de ADENTRO.
    expect(container.read(accionesPuertaProvider).marca(juan), 'Juli');
    expect(container.read(accionesPuertaProvider).enEstaPc, isTrue);

    // Pato lo busca después: ya entró.
    final otra = await pato.pedirYEsperar('b1', QuePide.ingresar, juan);
    expect(otra['hizo'], 'nada');
    expect(otra['aviso'], contains('ya ingresó'));
    expect(otra['aviso'], contains('· Juli'));
  });

  test('lo que se marca en la PC también les llega', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    await puerta.invitados.ingresarDesdeLaPuerta(
      eventoId: eventoMasivo,
      id: idInvitadoPuerta(_c2, 0),
      nombre: 'ACOSTA, LUCÍA',
    );
    await c.espera('puerta', cumple: (m) => lista(m).adentro == 1);
  });

  test('un ingreso atrasado (celular sin wifi) se marca sin saludar', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    final juan = idInvitadoPuerta(_c1, 0);
    await c.pedirYEsperar(
      'a1',
      QuePide.ingresar,
      juan,
      hace: const Duration(minutes: 5),
    );
    expect(puerta.invitados.sinSaludo, [juan]);
  });

  test('se ve quién está conectado', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(estado().conectados, 1);
    expect(estado().puestos.single.nombre, 'Juli');
  });

  test('prenderla de nuevo para el mismo evento no corta a nadie', () async {
    await central().prender(eventoMasivo);
    final puerto = estado().puerto;
    final c = await celular();
    await c.espera('puerta');
    await central().prender(eventoMasivo);
    expect(estado().puerto, puerto);
    final r = await c.pedirYEsperar(
      'a1',
      QuePide.ingresar,
      idInvitadoPuerta(_c2, 0),
    );
    expect(r['ok'], isTrue);
  });

  test('para otro evento, la del anterior se cierra', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    await central().prender(eventoParticular);
    expect(await c.cerro(), WebSocketStatus.goingAway);
    expect(estado().eventoId, eventoParticular);
  });

  test('cambiar el código saca a los celulares', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    await central().cambiarCodigo();
    expect(estado().codigo, '5555');
    expect(await c.cerro(), 4001);
    final otro = await celular(id: 'cel-2');
    await otro.espera('puerta');
  });

  test('apagada, los celulares se enteran', () async {
    await central().prender(eventoMasivo);
    final c = await celular();
    await c.espera('puerta');
    await central().apagar();
    expect(estado().prendida, isFalse);
    expect(await c.cerro(), WebSocketStatus.goingAway);
  });

  group('al reabrir Recepción', () {
    test('si la central no se usó esta noche, no se prende sola', () async {
      await central().reanudar(eventoMasivo);
      expect(estado().prendida, isFalse);
    });

    test('si se usó (la notebook se reinició), vuelve sola con el mismo '
        'código y los celulares se reconectan', () async {
      vigente = '4821';
      await central().reanudar(eventoMasivo);
      expect(estado().prendida, isTrue);
      expect(estado().codigo, '4821');
      final c = await celular();
      await c.espera('puerta');
    });

    test('si ya está prendida, no se toca', () async {
      await central().prender(eventoMasivo);
      final puerto = estado().puerto;
      vigente = '4821';
      await central().reanudar(eventoParticular);
      expect(estado().eventoId, eventoMasivo);
      expect(estado().puerto, puerto);
    });
  });

  test('si no se puede abrir, lo dice en palabras', () async {
    container.dispose();
    // Una dirección que no es de esta PC: no se puede escuchar ahí.
    container = ProviderContainer(
      overrides: overrides(escucha: InternetAddress('203.0.113.7')),
    );
    await central().prender(eventoMasivo);
    expect(estado().prendida, isFalse);
    expect(estado().error, contains('No se pudo abrir la central'));
  });
  group('las sillas de la noche desde la PC', () {
    /// PÉREZ, JUAN en la mesa 12 con 1 silla del contrato: le entra una más.
    Future<PuertaDelEvento> masivoSorteado() async {
      puerta.contratos.alumnos = [
        alumnoDePrueba(_c1, 'PÉREZ, JUAN', mesas: [12], sillas: 1),
        alumnoDePrueba(_c2, 'ACOSTA, LUCÍA', mesas: [13]),
      ];
      final sub = container.listen(
        puertaDelEventoProvider(eventoMasivo),
        (_, _) {},
      );
      addTearDown(sub.close);
      return leerPuerta();
    }

    test('con la central apagada, sumar escribe en la base de esta PC',
        () async {
      final p = await masivoSorteado();
      expect(estado().prendida, isFalse);
      final grupo = p.grupos.firstWhere((g) => g.contratoId == _c1);

      final r = await container.read(accionesPuertaProvider).sumarSilla(
            eventoMasivo,
            p,
            grupo,
            const DatosSilla(mesa: 12, vale: '1 0012'),
          );

      expect(r.hecho, isTrue);
      expect(r.texto, 'Silla sumada a la mesa 12 de PÉREZ, JUAN.');
      final s = puerta.sillasPuerta.filas.single;
      expect(s.vale, '1-12');
      expect(s.mesa, 12);
      expect(s.anotadoPor, 'PC', reason: 'sin caja ni usuario, la PC');
      // La lista de Recepción se vuelve a leer sola.
      final despues = await leerPuerta(
        cumple: (p) => p.conteoDeLaNoche.sumadas == 1,
      );
      expect(
        despues.grupos.firstWhere((g) => g.contratoId == _c1).puedeSumarSilla,
        isFalse,
      );
    });

    test('en el tope, desde la PC tampoco entra', () async {
      final p = await masivoSorteado();
      final grupo = p.grupos.firstWhere((g) => g.contratoId == _c1);
      final acciones = container.read(accionesPuertaProvider);
      await acciones.sumarSilla(
          eventoMasivo, p, grupo, const DatosSilla(vale: '1 0012'));
      final r = await acciones.sumarSilla(
          eventoMasivo, p, grupo, const DatosSilla(vale: '1 0013'));
      expect(r.hecho, isFalse);
      expect(r.texto, 'PÉREZ, JUAN ya no puede agregar: 2 extra por mesa.');
      expect(puerta.sillasPuerta.filas, hasLength(1));
    });

    test('quitar desde la PC pide el motivo y deja la huella', () async {
      final p = await masivoSorteado();
      final grupo = p.grupos.firstWhere((g) => g.contratoId == _c1);
      final acciones = container.read(accionesPuertaProvider);
      await acciones.sumarSilla(
          eventoMasivo, p, grupo, const DatosSilla(vale: '1 0012'));
      final id = puerta.sillasPuerta.filas.single.id;

      final sinMotivo = await acciones.quitarSilla(
          eventoMasivo, p, grupo, DatosSilla(sillaId: id));
      expect(sinMotivo.hecho, isFalse);
      final r = await acciones.quitarSilla(eventoMasivo, p, grupo,
          DatosSilla(sillaId: id, motivo: 'devolvieron el vale'));
      expect(r.hecho, isTrue);
      expect(r.texto, 'Silla quitada de la mesa 12 de PÉREZ, JUAN.');
      final s = puerta.sillasPuerta.filas.single;
      expect(s.vigente, isFalse);
      expect(s.quitadaPor, 'PC');
      expect(s.quitadaMotivo, 'devolvieron el vale');
    });

    test('un celular y la PC a la vez, a una familia con un lugar: entra una',
        () async {
      final p = await masivoSorteado();
      await central().prender(eventoMasivo);
      final c = await celular();
      await c.espera('puerta');
      final grupo = p.grupos.firstWhere((g) => g.contratoId == _c1);

      c.pedir('s1', QuePide.sumarSilla, grupo.titular.id,
          silla: const DatosSilla(vale: '2 0040'));
      final desdeLaPc = container.read(accionesPuertaProvider).sumarSilla(
          eventoMasivo, p, grupo, const DatosSilla(vale: '1 0012'));
      final delCelular = await c.espera('respuesta');
      final pc = await desdeLaPc;

      expect(puerta.sillasPuerta.filas, hasLength(1));
      expect(
        [pc.hecho, delCelular['hizo'] == 'sumarSilla'].where((x) => x),
        hasLength(1),
      );
    });
  });
}
