import 'dart:io';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/sillas_reparto_repository.dart';
import 'package:arguello_events/features/recepcion/central/central_provider.dart';
import 'package:arguello_events/features/recepcion/central/codigo_central.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/repositories/como_lo_nombran_repository.dart';
import 'package:arguello_events/features/recepcion/repositories/sillas_puerta_repository.dart';
import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/models/evento.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/puerta_en_memoria.dart';

/// La central de la tele desde el programa (`CentralDeLaPuerta` con
/// `comoTele`, 25-nov-2026): **cambiar de escuela no la reinicia**, el código
/// es uno por noche, y lo que pide un celular (otra escuela, girar) le llega a
/// la tele. Recepción en memoria; la central escucha de verdad, solo en esta
/// PC.
void main() {
  late PuertaEnMemoria puerta;
  late ProviderContainer container;
  final pedidos = <String>[];
  final celulares = <CelularDePrueba>[];
  var ahora = DateTime(2026, 11, 25, 22);
  late List<Evento> eventos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // La escuela elegida de otra prueba no queda (es de la clase).
    await ModoTeleGuardado.cargar();
    pedidos.clear();
    ahora = DateTime(2026, 11, 25, 22);
    eventos = [
      eventoDePrueba(eventoMasivo, 'masivo'),
      eventoDePrueba(eventoParticular, 'particular'),
    ];
    puerta = PuertaEnMemoria(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      alumnos: [alumnoDePrueba('c1000000-0000-4000-8000-000000000001', 'CEIBO, JUAN')],
    );
    container = ProviderContainer(overrides: [
      eventosActivosProvider.overrideWith((ref) async => eventos),
      invitadosRepositoryProvider.overrideWithValue(puerta.invitados),
      contratosRepositoryProvider.overrideWithValue(puerta.contratos),
      sillasRepartoRepositoryProvider.overrideWithValue(puerta.sillas),
      sillasPuertaRepositoryProvider.overrideWithValue(puerta.sillasPuerta),
      comoLoNombranRepositoryProvider.overrideWithValue(puerta.comoLoNombran),
      barraDelJefeProvider.overrideWithValue(puerta.barra),
      syncEngineProvider.overrideWithValue(puerta.motor),
      connectivityServiceProvider.overrideWithValue(puerta.conexion),
      escuchaCentralProvider.overrideWithValue(InternetAddress.loopbackIPv4),
      puertoCentralProvider.overrideWithValue(0),
      direccionesDeEstaPcProvider.overrideWithValue(() async => ['192.168.0.10']),
      codigoCentralProvider.overrideWithValue((id) async {
        pedidos.add(id);
        return '4821';
      }),
      paginaDelCelularProvider.overrideWithValue(null),
      relojDeLaCentralProvider.overrideWithValue(() => ahora),
    ]);
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

  Future<CelularDePrueba> celular(String nombre, {int tele = 1}) async {
    final c = await CelularDePrueba.conectar(
      estado().puerto!,
      codigo: estado().codigo!,
      id: 'cel-$nombre',
      nombre: nombre,
      tele: tele,
    );
    celulares.add(c);
    return c;
  }

  test('en la tele, el código es uno por noche, no por escuela', () async {
    await central().prender(eventoMasivo, comoTele: true);
    expect(pedidos, ['tele-2026-11-25']);
    // En la notebook, como siempre: por evento.
    await central().apagar();
    await central().prender(eventoMasivo);
    expect(pedidos.last, eventoMasivo);
  });

  test('la noche va de mediodía a mediodía: a las 3 sigue la misma; pasadas las 12, '
      'la tele se prende con otro código (revisión del 26-nov)', () async {
    expect(CodigoCentral.claveDeLaNoche(DateTime(2026, 11, 26, 3)), 'tele-2026-11-25');
    expect(CodigoCentral.claveDeLaNoche(DateTime(2026, 11, 26, 11, 59)), 'tele-2026-11-25');
    expect(CodigoCentral.claveDeLaNoche(DateTime(2026, 11, 26, 12)), 'tele-2026-11-26');
    expect(CodigoCentral.claveDeLaNoche(DateTime(2026, 12, 1, 2)), 'tele-2026-11-30');
    await central().prender(eventoMasivo, comoTele: true);
    final puerto = estado().puerto;
    // A las 3 de la mañana, otra escuela: la misma central, sin otro código.
    ahora = DateTime(2026, 11, 26, 3);
    await central().prender(eventoParticular, comoTele: true);
    expect(pedidos, ['tele-2026-11-25']);
    expect(estado().puerto, puerto);
    // Al día siguiente a la tarde: la noche nueva, con su código.
    ahora = DateTime(2026, 11, 26, 18);
    await central().prender(eventoParticular, comoTele: true);
    expect(pedidos, ['tele-2026-11-25', 'tele-2026-11-26']);
    expect(estado().prendida, isTrue);
    expect(estado().eventoId, eventoParticular);
  });

  test('apagar mientras se prende no deja ninguna central abierta (revisión del 26-nov)',
      () async {
    final prendiendo = central().prender(eventoMasivo, comoTele: true);
    await central().apagar();
    await prendiendo;
    expect(estado().prendida, isFalse);
    expect(estado().puerto, isNull);
  });

  test('la Tele 1 cambia de escuela con el control: la central no se reinicia, y los '
      'celulares siguen conectados', () async {
    await central().prender(eventoMasivo, comoTele: true);
    final puerto = estado().puerto;
    final juli = await celular('Juli');
    await juli.espera('puerta', cumple: (m) => m['evento'] == eventoMasivo);
    await central().prender(eventoParticular, comoTele: true);
    expect(estado().puerto, puerto);
    expect(estado().codigo, '4821');
    expect(pedidos, ['tele-2026-11-25'], reason: 'no se pidió otro código');
    expect(estado().eventoId, eventoParticular);
    // La de antes ya no la muestra ninguna tele: se suelta (revisión del 26-nov).
    expect(estado().atiende, [eventoParticular]);
    // Juli pasa sola a la escuela nueva, con el aviso.
    await juli.espera('puerta', cumple: (m) => m['evento'] == eventoParticular);
    expect((await juli.espera('aviso'))['texto'], startsWith('La Tele 1 pasó a'));
  });

  test('un celular pide otra escuela o girar la Tele 1: le llega a la tele, sin PIN',
      () async {
    await central().prender(eventoMasivo, comoTele: true);
    final caro = await celular('Caro');
    await caro.espera('puerta');
    // Las escuelas que se pueden elegir, con su nombre.
    final teles = await caro.espera('teles', cumple: (m) => (m['escuelas'] as List).isNotEmpty);
    expect([for (final e in teles['escuelas'] as List) e['id']],
        containsAll([eventoMasivo, eventoParticular]));
    caro.mandar({'t': 'escuela', 'tele': 1, 'evento': eventoParticular});
    caro.mandar({'t': 'girar', 'tele': 1, 'como': 'vertical'});
    await caro.espera('aviso');
    expect(container.read(fiestaDeLaTeleProvider), eventoParticular);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(giroDeLaTeleProvider), 1);
    final aviso = container.read(avisoEnLaTeleProvider);
    expect(aviso?.$2, startsWith('Caro pasó la Tele 1 a'));
  });

  test('una escuela que la tele ya no muestra (pasó el mediodía después de su fiesta): la '
      'central vuelve a la de la tele (revisión del 26-nov)', () async {
    // La particular fue anoche: a las 22 todavía estaba entre las que vienen.
    eventos = [
      eventoDePrueba(eventoMasivo, 'masivo'),
      Evento(
        id: eventoParticular,
        clienteId: 'c0000000-0000-4000-8000-000000000001',
        tipo: 'Cumpleaños',
        fechaEvento: DateTime(2026, 11, 25),
        estado: EstadoEvento.confirmado,
        modalidad: 'particular',
      ),
    ];
    await central().prender(eventoMasivo, comoTele: true);
    final caro = await celular('Caro');
    await caro.espera('puerta');
    // Al otro día a la tarde la tele ya no la tiene, aunque la central la
    // conocía de anoche.
    ahora = DateTime(2026, 11, 26, 13);
    caro.mandar({'t': 'escuela', 'tele': 1, 'evento': eventoParticular});
    await caro.espera('aviso');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(fiestaDeLaTeleProvider), isNot(eventoParticular));
    expect(estado().eventoId, eventoMasivo);
    expect(container.read(avisoEnLaTeleProvider)?.$2, contains('no tiene esa escuela'));
  });

  test('la escuela que se soltó vuelve con su lista (revisión del 26-nov)', () async {
    await central().prender(eventoMasivo, comoTele: true);
    final juli = await celular('Juli');
    await juli.espera('puerta', cumple: (m) => m['evento'] == eventoMasivo);
    await central().prender(eventoParticular, comoTele: true);
    await juli.espera('puerta', cumple: (m) => m['evento'] == eventoParticular);
    expect(estado().atiende, [eventoParticular]);
    // De vuelta a la primera: se la vuelve a escuchar, y su lista llega.
    await central().prender(eventoMasivo, comoTele: true);
    await juli.espera('puerta', cumple: (m) => m['evento'] == eventoMasivo);
  });

  test('"Pasar a principal": la escuela de la Tele 1 apagada, también, para la Tele 2',
      () async {
    await central().prender(eventoMasivo, comoTele: true);
    central().atenderTambien(eventoParticular);
    expect(estado().atiende, [eventoMasivo, eventoParticular]);
    final caro = await celular('Caro', tele: 2);
    await caro.espera('puerta', cumple: (m) => m['evento'] == eventoParticular);
  });
}
