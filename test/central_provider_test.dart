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
        syncEngineProvider.overrideWithValue(puerta.motor),
        connectivityServiceProvider.overrideWithValue(puerta.conexion),
        escuchaCentralProvider
            .overrideWithValue(escucha ?? InternetAddress.loopbackIPv4),
        puertoCentralProvider.overrideWithValue(0),
        direccionesDeEstaPcProvider
            .overrideWithValue(() async => ['192.168.0.10']),
        codigoCentralProvider.overrideWithValue((_) async => codigos[siguiente]),
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
}
