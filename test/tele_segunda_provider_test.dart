// La Tele 2 desde el programa (`TeleSegunda`), contra la central de verdad de
// una Tele 1 por la red de esta PC (revisión del 26-nov-2026):
// - la Tele 1 le pide una escuela que esta tele no tiene: sigue con la suya;
// - al pasar a principal sube solo lo copiado de las escuelas que la Tele 1
//   atendía al final.
import 'dart:io';

import 'package:arguello_events/features/recepcion/central/central_puerta.dart';
import 'package:arguello_events/features/recepcion/providers/recepcion_provider.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/services/puerta_del_evento.dart';
import 'package:arguello_events/features/tele/modo_tele.dart';
import 'package:arguello_events/features/tele/tele_segunda_provider.dart';
import 'package:arguello_events/models/invitado.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/celular_de_prueba.dart';
import 'helpers/central_en_memoria.dart';
import 'helpers/puerta_en_memoria.dart';

const _a = 'e0000000-0000-4000-8000-0000000000a1';
const _b = 'e0000000-0000-4000-8000-0000000000b1';

/// Una escuela que la Tele 1 tiene y la Tele 2 no (por ejemplo, ya pasó para
/// el reloj de la Tele 2).
const _x = 'e0000000-0000-4000-8000-0000000000c1';

Invitado _fila(String evento, String id) => Invitado(
      id: id,
      eventoId: evento,
      nombreCompleto: 'TALA, $id',
      dni: '',
      estadoIngreso: EstadoIngreso.ingresado,
      updatedAt: DateTime.utc(2026, 12, 12, 23),
    );

Future<void> _hasta(bool Function() listo, [String que = '']) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) throw StateError('no pasó: $que');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late PuertaEnMemoria puerta;
  late ProviderContainer container;
  late CentralPuerta central;
  late int puerto;
  final abiertos = <CelularDePrueba>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    puerta = PuertaEnMemoria(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      alumnos: const [],
    );
    central = CentralPuerta(eventoId: _a, codigo: '4821', pc: PcEnMemoria(), esTele: true)
      ..ponerEscuelasParaElegir(const [
        EscuelaParaElegir(_a, 'ESCUELA A'),
        EscuelaParaElegir(_b, 'ESCUELA B'),
        EscuelaParaElegir(_x, 'ESCUELA X'),
      ]);
    // Como la app: cada escuela que se empieza a atender, con su lista y sus
    // filas.
    void armar(String e) => central
      ..ponerPuerta(PuertaDelEvento.particular(const []), de: e)
      ..ponerFilas([_fila(e, 'de-$e')], de: e);
    central.alAtender = armar;
    puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    armar(_a);
    container = ProviderContainer(overrides: [
      // Esta tele tiene la A y la B, no la X.
      eventosActivosProvider.overrideWith(
        (ref) async => [eventoDePrueba(_a, 'particular'), eventoDePrueba(_b, 'particular')],
      ),
      invitadosRepositoryProvider.overrideWithValue(puerta.invitados),
    ]);
    await container.read(eventosActivosProvider.future);
  });

  tearDown(() async {
    for (final c in abiertos) {
      try {
        await c.ws.close();
      } catch (_) {}
    }
    abiertos.clear();
    container.read(teleSegundaProvider.notifier).soltar();
    container.dispose();
    await central.cerrar();
  });

  Future<void> conectar(String evento) async {
    container.read(teleSegundaProvider.notifier).conectar(evento, direccionAMano: '127.0.0.1:$puerto');
    await _hasta(() => central.teles.any((t) => t.numero == 2 && t.conectada), 'la Tele 2 conectada');
  }

  Future<CelularDePrueba> caro() async {
    final c = await CelularDePrueba.conectar(puerto, codigo: '4821', id: 'c', nombre: 'Caro', tele: 2);
    abiertos.add(c);
    await c.espera('puerta');
    return c;
  }

  test('la Tele 1 le pide una escuela que esta tele no tiene: sigue con la suya, y la '
      'Tele 1 vuelve a saber cuál muestra', () async {
    await conectar(_a);
    final c = await caro();
    c.mandar({'t': 'escuela', 'tele': 2, 'evento': _x});
    await _hasta(() => container.read(avisoEnLaTeleProvider) != null, 'el cartel');
    expect(container.read(avisoEnLaTeleProvider)!.$2, contains('no tiene esa escuela'));
    await _hasta(() => central.escuelaDeTele(2) == _a, 'la Tele 1 vuelve a la A');
    expect(container.read(fiestaDeLaTeleProvider), isNot(_x));
    expect(container.read(teleSegundaProvider)!.eventoId, _a);
  });

  test('una que sí tiene: la muestra', () async {
    await conectar(_a);
    final c = await caro();
    c.mandar({'t': 'escuela', 'tele': 2, 'evento': _b});
    await _hasta(() => container.read(fiestaDeLaTeleProvider) == _b, 'la tele pasa a la B');
    expect(central.escuelaDeTele(2), _b);
    expect(container.read(avisoEnLaTeleProvider)!.$2, 'Caro pasó la Tele 2 a ${etiquetaEventoRecepcion(eventoDePrueba(_b, 'particular'))}');
  });

  test('al pasar a principal sube solo lo de las escuelas que la Tele 1 atendía al final',
      () async {
    // Con la B, la Tele 1 atiende las dos y esta copia las filas de las dos.
    await conectar(_b);
    await _hasta(
      () => puerta.invitados.copiadasDeOtraTele.toSet().containsAll({'de-$_a', 'de-$_b'}),
      'las filas de las dos',
    );
    // Vuelve a la A: ninguna tele muestra la B y la Tele 1 la suelta.
    container.read(teleSegundaProvider.notifier).conectar(_a, direccionAMano: '127.0.0.1:$puerto');
    await _hasta(() => central.atiende.length == 1, 'la Tele 1 suelta la B');
    await _hasta(
      () => container.read(teleSegundaProvider)!.atiende.length == 1,
      'la Tele 2 se entera',
    );
    await container.read(teleSegundaProvider.notifier).soltarParaSerPrincipal();
    expect(puerta.invitados.subidasPorEscuela.keys, [_a]);
    expect(puerta.invitados.subidasPorEscuela[_a], {'de-$_a'});
  });
}
