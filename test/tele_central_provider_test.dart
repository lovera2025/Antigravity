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
import 'package:arguello_events/features/recepcion/repositories/sillas_puerta_repository.dart';
import 'package:arguello_events/features/tele/giro_de_la_tele.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pedidos.clear();
    puerta = PuertaEnMemoria(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      alumnos: [alumnoDePrueba('c1000000-0000-4000-8000-000000000001', 'PÉREZ, JUAN')],
    );
    container = ProviderContainer(overrides: [
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
    expect(pedidos, [CodigoCentral.deLaNoche]);
    // En la notebook, como siempre: por evento.
    await central().apagar();
    await central().prender(eventoMasivo);
    expect(pedidos.last, eventoMasivo);
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
    expect(pedidos, [CodigoCentral.deLaNoche], reason: 'no se pidió otro código');
    expect(estado().eventoId, eventoParticular);
    expect(estado().atiende, containsAll([eventoMasivo, eventoParticular]));
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
}
