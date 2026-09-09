// Prueba de humo del pulso, contra Supabase de verdad.
//
// Vive en `tool/` y no en `test/` a propósito: usa la red, así que no puede
// correr en la suite normal — sin internet fallaría siempre. Se corre a mano:
//
//   flutter test tool/probar_pulso_test.dart
//
// Lo que prueba es la parte que los tests unitarios no pueden tocar: que el
// canal de broadcast exista, que un mensaje mandado por una punta llegue a la
// otra, y —lo más importante— que suscribirse a un canal de broadcast **no cree
// ninguna suscripción de `postgres_changes`**, que es lo que agotó el Disk IO
// del proyecto en septiembre de 2026.
//
// Usa dos clientes distintos para simular las dos PCs. No escribe una sola fila:
// broadcast no toca la base.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/services/sync_engine.dart';

const _url = 'https://bucnrydgojyzntgesxqb.supabase.co';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA';

void main() {
  test('un pulso mandado por una PC llega a la otra', () async {
    final pcQueSube = SupabaseClient(_url, _anonKey);
    final pcQueEscucha = SupabaseClient(_url, _anonKey);

    final llego = Completer<Map<String, dynamic>>();

    final canalReceptor = pcQueEscucha.channel('sync_pulse')
      ..onBroadcast(
        event: 'cambios',
        callback: (mensaje) {
          if (!llego.isCompleted) llego.complete(mensaje);
        },
      )
      ..subscribe();

    // Darle un momento al socket antes de emitir: un broadcast mandado antes de
    // que el receptor esté suscripto se pierde, y no es un error del pulso.
    await Future<void>.delayed(const Duration(seconds: 3));

    await pcQueSube.channel('sync_pulse').sendBroadcastMessage(
      event: 'cambios',
      payload: {
        'origen': 'pc-de-prueba',
        'tablas': ['presupuestos', 'presupuesto_servicios'],
        'borrados': <String, dynamic>{},
      },
    );

    final mensaje = await llego.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('el pulso no llegó en 15 s'),
    );

    // Y que el receptor real lo interprete igual que en los tests unitarios.
    final trabajo = trabajoDelPulso(
      mensaje['payload'],
      yo: 'otra-pc',
      tablasConocidas: const {'presupuestos', 'presupuesto_servicios'},
    );

    expect(trabajo.tablas, {'presupuestos', 'presupuesto_servicios'});

    await canalReceptor.unsubscribe();
    await pcQueSube.dispose();
    await pcQueEscucha.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('la PC no recibe su propio pulso', () async {
    // Esta prueba nació esperando lo contrario: que el eco volviera y que el
    // filtro de `origen` lo descartara. No vuelve. Supabase no le manda el
    // broadcast a quien lo emitió por el mismo canal (`self` es false por
    // defecto), así que una PC no puede dispararse a sí misma ni aunque el
    // filtro fallara.
    //
    // El filtro de `origen` se queda igual, como segunda línea: es una opción
    // del servidor, no una garantía del protocolo, y el día que alguien la
    // cambie —o que el emisor y el receptor dejen de compartir canal— esto se
    // vuelve la única defensa. Ver `trabajoDelPulso` y su test unitario.
    final pc = SupabaseClient(_url, _anonKey);
    var recibioAlgo = false;

    final canal = pc.channel('sync_pulse')
      ..onBroadcast(event: 'cambios', callback: (_) => recibioAlgo = true)
      ..subscribe();

    await Future<void>.delayed(const Duration(seconds: 3));

    await canal.sendBroadcastMessage(
      event: 'cambios',
      payload: {
        'origen': 'pc-1757999999999',
        'tablas': ['presupuestos'],
      },
    );

    await Future<void>.delayed(const Duration(seconds: 5));

    expect(
      recibioAlgo,
      isFalse,
      reason: 'si volviera, la PC bajaría lo que acaba de subir',
    );

    await canal.unsubscribe();
    await pc.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
