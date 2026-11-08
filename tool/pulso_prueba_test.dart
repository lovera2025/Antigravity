// La prueba que faltó del aviso entre PCs: contra Supabase de verdad
// (docs/SPEC_pulso_por_el_socket_2026-11-07.md, sección 7.9).
//
// **Pide el OK del usuario antes de correrla**: su regla es no probar contra la
// nube. No lee ni escribe ninguna tabla: solo manda dos avisos por un canal de
// prueba, `sync_pulse_prueba`, **nunca `sync_pulse`**, así las PCs no
// reaccionan.
//
//   flutter test tool/pulso_prueba_test.dart --dart-define=nube=si
//
// Un cliente se suscribe y escucha. Otro, suscripto, manda el aviso por el
// socket; un tercero, sin suscribir, lo manda por REST. Imprime la forma cruda
// de cada uno y comprueba que la app saque de los dos el mismo trabajo.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/cuerpo_del_broadcast.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/main.dart' show supabaseAnonKey, supabaseUrl;

const _canal = 'sync_pulse_prueba';
const _evento = 'cambios';
const _tablas = {'pagos_contrato_alumno', 'contratos_alumnos'};
const _pago = 'e27b01aa-0000-4000-8000-0000000000aa';

Map<String, dynamic> _aviso(String por) => {
      'origen': 'prueba-$por',
      'tablas': ['pagos_contrato_alumno', 'contratos_alumnos'],
      'borrados': {
        'pagos_contrato_alumno': [_pago],
      },
    };

Future<void> _unido(RealtimeChannel c) {
  final listo = Completer<void>();
  c.subscribe((estado, error) {
    if (estado == RealtimeSubscribeStatus.subscribed && !listo.isCompleted) {
      listo.complete();
    } else if (estado != RealtimeSubscribeStatus.subscribed &&
        !listo.isCompleted) {
      listo.completeError(StateError('el canal no se unió: $estado $error'));
    }
  });
  return listo.future.timeout(const Duration(seconds: 15));
}

void main() {
  const nube = String.fromEnvironment('nube');

  test('el aviso por el socket y por REST dan el mismo trabajo', () async {
    final receptor = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final porSocket = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final porRest = SupabaseClient(supabaseUrl, supabaseAnonKey);
    addTearDown(() async {
      await receptor.removeAllChannels();
      await porSocket.removeAllChannels();
      await porRest.removeAllChannels();
      await receptor.dispose();
      await porSocket.dispose();
      await porRest.dispose();
    });

    final llegados = <Map<String, dynamic>>[];
    final dos = Completer<void>();
    final escucha = receptor.channel(_canal)
      ..onBroadcast(
        event: _evento,
        callback: (m) {
          llegados.add(m);
          if (llegados.length == 2 && !dos.isCompleted) dos.complete();
        },
      );
    await _unido(escucha);

    final socket = porSocket.channel(_canal);
    await _unido(socket);
    await socket.sendBroadcastMessage(event: _evento, payload: _aviso('socket'));

    // Sin suscribir: la librería cae sola al REST.
    await porRest
        .channel(_canal)
        .sendBroadcastMessage(event: _evento, payload: _aviso('rest'));

    await dos.future.timeout(const Duration(seconds: 15));

    for (final m in llegados) {
      // ignore: avoid_print
      print('LLEGÓ: ${jsonEncode(m)}');
    }
    final trabajos = <String, TrabajoDelPulso>{};
    for (final m in llegados) {
      final cuerpo = cuerpoDelBroadcast(m);
      trabajos['${cuerpo?['origen']}'] = trabajoDelPulso(
        cuerpo,
        yo: 'esta-pc',
        tablasConocidas: _tablas,
      );
    }
    expect(trabajos.keys, unorderedEquals(['prueba-socket', 'prueba-rest']));
    for (final t in trabajos.values) {
      expect(t.tablas, _tablas);
      expect(t.borrados, {
        'pagos_contrato_alumno': {_pago},
      });
    }
  }, skip: nube == 'si' ? false : 'contra la nube real: pide el OK del usuario');
}
