// Sandbox de la puerta: la central de verdad (`CentralDeLaPuerta`), la base en
// memoria y la página del celular de `build/puesto`. Sirve para probar de punta
// a punta con el navegador, con pestañas que hacen de celulares, **sin tocar la
// base real ni la nube** (regla del usuario del 6-nov: las pruebas las hace
// Claude, en un sandbox).
//
//   flutter build web -t lib/puesto_main.dart --no-web-resources-cdn -o <ruta absoluta>\build\puesto
//   flutter test tool/puerta_sandbox_test.dart --dart-define=carpeta=<carpeta de órdenes>
//
// Escucha solo en esta PC (127.0.0.1, puerto 8787 o el siguiente libre): sin el
// cartel del cortafuegos. Imprime el enlace con el código. Dos celulares
// distintos son dos orígenes distintos (`127.0.0.1` y `localhost`): cada uno
// guarda su nombre en su navegador.
//
// Órdenes: un archivo en <carpeta> con el nombre de la orden (el sandbox lo lee
// y lo borra):
//   estado        → escribe estado.txt: cada familia con sus líneas por mesa y
//                   sus sillas, el conteo de la noche, quién entró y los
//                   segundos del tótem.
//   pc_sumar      → adentro, "contrato vale [mesa]": la PC suma una silla, por
//                   el mismo candado que los celulares. Contesta en pc.txt.
//   apagar        → apaga la central (los celulares quedan sin conexión).
//   prender       → la vuelve a prender, con el mismo código.
//   parar         → termina.
//
// La institución inventada: PÉREZ, JULIANA (mesa 12, 1 silla del contrato: le
// entra una más), GÓMEZ, ANA (13, sin extra: 2 más), ACOSTA, LUCÍA (14-15, 3 del
// contrato: 1 más en la 15), BENÍTEZ, TOMÁS (16, 2 del contrato: en el tope) y
// RUIZ, MARTA (17, sin extra).

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/recepcion/services/sillas_de_la_puerta.dart';
import 'package:arguello_events/features/totem/providers/tiempos_a_mano_provider.dart';
import 'package:arguello_events/features/totem/providers/totem_config_provider.dart';
import 'package:arguello_events/features/totem/repositories/totem_config_repository.dart';
import 'package:arguello_events/models/totem_config.dart';

import '../test/helpers/personalizar_en_memoria.dart' show RepoTotemEnMemoria;
import '../test/helpers/puerta_en_memoria.dart';

const _carpeta = String.fromEnvironment('carpeta', defaultValue: '');

const _julia = 'c1000000-0000-4000-8000-000000000001';
const _ana = 'c2000000-0000-4000-8000-000000000002';
const _lucia = 'c3000000-0000-4000-8000-000000000003';
const _tomas = 'c4000000-0000-4000-8000-000000000004';
const _marta = 'c5000000-0000-4000-8000-000000000005';

void main() {
  test('sandbox de la puerta', () async {
    if (_carpeta.isEmpty) fail('Falta --dart-define=carpeta=<carpeta de órdenes>');
    // Los segundos a mano se guardan acá, en memoria: nada en el disco.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final ordenes = Directory(_carpeta)..createSync(recursive: true);
    for (final f in ordenes.listSync()) {
      f.deleteSync(recursive: true);
    }

    final puerta = PuertaEnMemoria(
      // A ningún lado: como sin internet.
      SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba'),
      alumnos: [
        alumnoDePrueba(_julia, 'PÉREZ, JULIANA',
            mesas: [12], sillas: 1, acomp: ['PÉREZ, OMAR']),
        alumnoDePrueba(_ana, 'GÓMEZ, ANA', mesas: [13]),
        alumnoDePrueba(_lucia, 'ACOSTA, LUCÍA',
            mesas: [14, 15], extras: 1, sillas: 3, division: '5° A'),
        alumnoDePrueba(_tomas, 'BENÍTEZ, TOMÁS', mesas: [16], sillas: 2),
        alumnoDePrueba(_marta, 'RUIZ, MARTA', mesas: [17]),
      ],
    );
    puerta.invitados.hora = () => DateTime.now().toUtc();
    puerta.sillasPuerta.hora = () => DateTime.now().toUtc();

    final container = ProviderContainer(overrides: [
      eventosActivosProvider.overrideWith(
        (ref) async => [eventoDePrueba(eventoMasivo, 'masivo')],
      ),
      invitadosRepositoryProvider.overrideWithValue(puerta.invitados),
      contratosRepositoryProvider.overrideWithValue(puerta.contratos),
      sillasRepartoRepositoryProvider.overrideWithValue(puerta.sillas),
      sillasPuertaRepositoryProvider.overrideWithValue(puerta.sillasPuerta),
      syncEngineProvider.overrideWithValue(puerta.motor),
      connectivityServiceProvider.overrideWithValue(puerta.conexion),
      totemConfigProvider(eventoMasivo).overrideWith(
        (ref) => Stream.value(TotemConfig.defaults(eventoMasivo)),
      ),
      totemConfigRepositoryProvider.overrideWithValue(RepoTotemEnMemoria()),
      escuchaCentralProvider.overrideWithValue(InternetAddress.loopbackIPv4),
      puertoCentralProvider.overrideWithValue(8787),
      direccionesDeEstaPcProvider.overrideWithValue(() async => ['127.0.0.1']),
      codigoCentralProvider.overrideWithValue((_) async => '4821'),
      codigoVigenteCentralProvider.overrideWithValue((_) async => '4821'),
      paginaDelCelularProvider.overrideWithValue(Directory('build/puesto')),
    ]);
    final lista = container.listen(
      puertaDelEventoProvider(eventoMasivo),
      (_, _) {},
    );
    final central = container.read(centralDeLaPuertaProvider.notifier);

    Future<void> prender() async {
      await central.prender(eventoMasivo);
      final e = container.read(centralDeLaPuertaProvider);
      print(e.error ?? 'CENTRAL: ${e.enlace}');
    }

    PuertaDelEvento? ahora() =>
        container.read(puertaDelEventoProvider(eventoMasivo)).value;

    String estado() {
      final p = ahora();
      if (p == null) return 'la lista todavía no está';
      final b = StringBuffer()
        ..writeln('${p.adentro} de ${p.total} adentro')
        ..writeln(p.conteoDeLaNoche.texto ?? 'Esta noche: nada');
      for (final g in p.grupos) {
        b.writeln('· ${g.titular.nombre}'
            '${g.titular.ingresado ? ' (ADENTRO)' : ''}'
            '${g.puedeSumarSilla ? '' : ' [SUMAR apagado]'}');
        for (final m in g.sillasPorMesa.mesas) {
          b.writeln('    ${m.texto}');
        }
        for (final s in g.movimientos) {
          b.writeln('    ${textoSillaSumada(s)}'
              '${s.vigente ? '' : ' — ${textoSillaQuitada(s)}'}');
        }
      }
      b
        ..writeln('Filas en la base: ${puerta.sillasPuerta.filas.length}')
        ..writeln('Segundos a mano: '
            '${container.read(tiemposAManoProvider(eventoMasivo)) ?? 'los de Personalizar'}')
        ..writeln('Celulares: ${[
          for (final c in container.read(centralDeLaPuertaProvider).puestos)
            '${c.nombre}${c.conectado ? '' : ' (desconectado)'} · ${c.marcados} marcados',
        ].join(', ')}');
      return b.toString();
    }

    await prender();
    var seguir = true;
    while (seguir) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final f in ordenes.listSync().whereType<File>()) {
        final orden = f.uri.pathSegments.last;
        if (orden.endsWith('.txt')) continue;
        final contenido = f.readAsStringSync().trim();
        f.deleteSync();
        print('ORDEN: $orden $contenido');
        switch (orden) {
          case 'estado':
            File('${ordenes.path}/estado.txt').writeAsStringSync(estado());
          case 'pc_sumar':
            final partes = contenido.split(RegExp(r'\s+'));
            final p = ahora()!;
            final grupo = p.grupos.firstWhere((g) => g.contratoId == partes[0]);
            final r = await container.read(accionesPuertaProvider).sumarSilla(
                  eventoMasivo,
                  p,
                  grupo,
                  DatosSilla(
                    vale: partes[1],
                    mesa: partes.length > 2 ? int.parse(partes[2]) : null,
                  ),
                );
            final linea = '${r.hecho ? 'HECHO' : 'NO'}: ${r.texto}';
            print('PC: $linea');
            File('${ordenes.path}/pc.txt').writeAsStringSync(linea);
          case 'apagar':
            await central.apagar();
            print('CENTRAL: apagada');
          case 'prender':
            await prender();
          case 'parar':
            seguir = false;
        }
      }
    }
    print(estado());
    await central.apagar();
    lista.close();
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 90)));
}
