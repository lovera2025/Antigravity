import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/vigia_de_la_red.dart';

import 'helpers/barra_en_memoria.dart';

late QuienEsQuienEnMemoria _personas;

/// **La falla del 26-nov-2026**: el usuario probaba la barra con un aparato en otro wifi
/// (no se actualizaba, bien). Al volver al wifi de la barra **siguió sin actualizarse
/// hasta que apagó y prendió la central** en la notebook. Tiene que volver sola.
///
/// Un cambio de red mata los sockets que estaban abiertos (el de la notebook que contesta
/// "acá estoy" y el de la tablet que pregunta), sin que nadie los cierre; y la dirección de
/// la notebook puede cambiar. Acá se hace lo mismo a propósito, por la red de esta PC
/// (loopback), con la central de verdad.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

/// Espera hasta que [listo] o tira a los [segundos].
Future<void> hasta(bool Function() listo, {String? que, int segundos = 8}) async {
  final limite = DateTime.now().add(Duration(seconds: segundos));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<int> puertoLibre() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  s.close();
  return p;
}

void main() {
  late BarraEnMemoria notebook;
  late CentralBarra central;
  late int puertoBusqueda;
  final aCerrar = <void Function()>[];

  setUp(() async {
    notebook = BarraEnMemoria()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    _personas = QuienEsQuienEnMemoria();
    central = CentralBarra(eventoId: _fiesta, barra: notebook, quienEsQuien: _personas);
    await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    puertoBusqueda = await puertoLibre();
  });

  tearDown(() async {
    for (final c in aCerrar.reversed) {
      c();
    }
    aCerrar.clear();
    await central.cerrar();
  });

  RespondeBusqueda contestar() {
    final r = RespondeBusqueda(eventoId: _fiesta, puertoCentral: central.puerto!);
    aCerrar.add(r.cerrar);
    return r;
  }

  BuscaCentral buscador() => BuscaCentral(
        eventoId: _fiesta,
        puerto: puertoBusqueda,
        cada: const Duration(milliseconds: 100),
        destinos: () async => [InternetAddress.loopbackIPv4],
      );

  ClienteDeLaCentral tablet(String equipo, BuscaCentral busca) {
    final barra = BarraEnMemoria()..equipo = equipo;
    barra.reloj = () => DateTime.now().toUtc();
    final cred = _personas.persona('op-$equipo', equipo);
    final c = ClienteDeLaCentral(
      credencial: () async => cred,
      eventoId: _fiesta,
      equipo: equipo,
      nombreCaja: 'Caja · $equipo',
      barra: barra,
      buscador: busca,
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    aCerrar.add(c.dispose);
    c.arrancar();
    return c;
  }

  test('a la notebook se le muere lo que contesta la búsqueda: vuelve a contestar sola, sin apagar la central', () async {
    final responde = contestar();
    expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
    final a = tablet('tablet-a', buscador());
    await hasta(() => a.conectada, que: 'la primera tablet la encontró');

    // Cambia la red de la notebook: el socket que contesta se muere.
    responde.matarElSocketParaPrueba();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Una tablet que llega ahora (o que vuelve de otro wifi) la tiene que encontrar igual.
    final b = tablet('tablet-b', buscador());
    await hasta(() => b.conectada, que: 'la tablet que llegó después la encontró sin apagar la central');
  });

  test('a la tablet se le muere el socket con que pregunta: vuelve a preguntar sola', () async {
    final busca = buscador();
    final a = tablet('tablet-a', busca);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(a.conectada, isFalse, reason: 'todavía no hay quién conteste');

    // La tablet se va a otro wifi y vuelve: su socket se muere.
    busca.matarElSocketParaPrueba();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Ya de vuelta, la notebook contesta.
    final responde = contestar();
    expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
    await hasta(() => a.conectada, que: 'la tablet volvió a preguntar y se conectó');
  });

  test('la notebook cambia de red: se vuelve a abrir lo que contesta, aunque parezca vivo', () async {
    final responde = contestar();
    expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
    await responde.reabrir();
    final a = tablet('tablet-a', buscador());
    await hasta(() => a.conectada, que: 'contesta después de reabrir');
    // Cerrada a propósito (se apagó la central), no se vuelve a abrir sola.
    responde.cerrar();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final b = tablet('tablet-b', buscador());
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(b.conectada, isFalse, reason: 'apagada es apagada');
  });

  test('mientras nadie contesta, la tablet renueva su socket cada tanto y sigue buscando', () async {
    var sockets = 0;
    final busca = BuscaCentral(
      eventoId: _fiesta,
      puerto: puertoBusqueda,
      cada: const Duration(milliseconds: 50),
      renovarCada: const Duration(milliseconds: 200),
      destinos: () async {
        sockets++;
        return [InternetAddress.loopbackIPv4];
      },
    );
    final a = tablet('tablet-a', busca);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(sockets, greaterThan(10), reason: 'sigue preguntando');
    expect(busca.socketsAbiertos, greaterThan(2), reason: 'con un socket nuevo cada tanto');
    final responde = contestar();
    expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
    await hasta(() => a.conectada, que: 'con el socket renovado, la encuentra');
  });

  group('el vigía de la red', () {
    test('avisa solo cuando cambian las direcciones del equipo, no la primera vez ni si siguen iguales', () async {
      var dirs = {'Wi-Fi/192.168.0.10'};
      final vigia = VigiaDeLaRed(direcciones: () async => dirs, cada: const Duration(milliseconds: 30));
      var avisos = 0;
      final s = vigia.cambios.listen((_) => avisos++);
      vigia.arrancar();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(avisos, 0, reason: 'la primera lectura no es un cambio');

      dirs = {'Wi-Fi/10.0.0.7'}; // otro wifi
      await hasta(() => avisos == 1, que: 'avisó el cambio');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(avisos, 1, reason: 'una sola vez por cambio');

      dirs = {'Ethernet/10.0.0.7'}; // la misma dirección por otra conexión también es otra red
      await hasta(() => avisos == 2, que: 'avisó la otra conexión');
      await s.cancel();
      await vigia.cerrar();
    });

    test('la tablet que estaba en otra red busca de nuevo enseguida, sin esperar sus reintentos', () async {
      // La notebook está en el puerto de antes y se apaga: la tablet se queda probando
      // esa dirección, con reintentos lentos (como pasaría con la dirección de otro wifi).
      final responde = contestar();
      expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
      final cambios = StreamController<void>.broadcast();
      addTearDown(cambios.close);
      final barra = BarraEnMemoria()..equipo = 'tablet-a';
      barra.reloj = () => DateTime.now().toUtc();
      final cred = _personas.persona('op-a', 'Marta');
      final a = ClienteDeLaCentral(
        credencial: () async => cred,
        eventoId: _fiesta,
        equipo: 'tablet-a',
        nombreCaja: 'Caja 1',
        barra: barra,
        buscador: buscador(),
        latido: const Duration(milliseconds: 100),
        silencioMaximo: const Duration(seconds: 2),
        pausa: const Duration(seconds: 30), // reintentos lentos: sin el aviso, no vuelve en la prueba
        cambiosDeRed: cambios.stream,
      );
      aCerrar.add(a.dispose);
      a.arrancar();
      await hasta(() => a.conectada, que: 'conectada al principio');

      // La notebook se reinicia en otra dirección (otro puerto) y la tablet queda colgada.
      responde.cerrar();
      await central.cerrar();
      await hasta(() => a.estado == EstadoDeLaCentral.sinCentral, que: 'se dio cuenta');
      central = CentralBarra(eventoId: _fiesta, barra: notebook, quienEsQuien: _personas);
      await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
      final otra = contestar();
      expect(await otra.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(a.conectada, isFalse, reason: 'sin el aviso espera sus 30 s');

      // Vuelve al wifi de la barra: el vigía avisa.
      cambios.add(null);
      await hasta(() => a.conectada, que: 'buscó de nuevo y se conectó a la nueva');
      expect(a.donde?.puerto, central.puerto);
    });
  });
}
