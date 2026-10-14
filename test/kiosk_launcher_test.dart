import 'package:arguello_events/core/services/kiosk_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La ventana del tótem (`KioskLauncher`).
///
/// Lo que se cuida: que un aviso que no llega no desconecte el tótem por el
/// resto de la noche, y que reabrirlo no deje dos ventanas.
class _VentanasDeMentira implements VentanasTotem {
  /// Las ventanas que "siguen abiertas".
  final abiertasAhora = <int>[];

  /// Cada mensaje que se intentó mandar, llegue o no: `id:metodo`.
  final intentos = <String>[];

  /// Los que llegaron.
  final llegaron = <String>[];

  final creadas = <String>[];
  final mostradas = <int>[];
  final escondidas = <int>[];

  /// Cuántos de los próximos mensajes fallan.
  int fallanLosProximos = 0;

  /// Si preguntar por las ventanas abiertas falla.
  bool noSeSabe = false;

  int _proximoId = 1;

  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) async {
    intentos.add('$id:$metodo');
    if (fallanLosProximos > 0) {
      fallanLosProximos--;
      throw Exception('no llegó');
    }
    llegaron.add('$id:$metodo');
    return null;
  }

  @override
  Future<List<int>> abiertas() async {
    if (noSeSabe) throw Exception('no se sabe');
    return List.of(abiertasAhora);
  }

  @override
  Future<int> crear(
    String argumentos, {
    required Size tamanio,
    required String titulo,
  }) async {
    final id = _proximoId++;
    creadas.add(argumentos);
    abiertasAhora.add(id);
    return id;
  }

  @override
  Future<void> mostrar(int id) async => mostradas.add(id);

  @override
  Future<void> esconder(int id) async => escondidas.add(id);
}

const _eventoA = '11111111-1111-1111-1111-111111111111';
const _eventoB = '22222222-2222-2222-2222-222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _VentanasDeMentira ventanas;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    KioskLauncher.reiniciar();
    ventanas = _VentanasDeMentira();
    KioskLauncher.ventanas = ventanas;
    KioskLauncher.esperaEntreIntentos = Duration.zero;
  });

  tearDown(KioskLauncher.reiniciar);

  test('abrir el tótem crea una ventana y la deja anotada', () async {
    expect(KioskLauncher.isTotemActive, isFalse);
    await KioskLauncher.launch(_eventoA);
    expect(ventanas.creadas, hasLength(1));
    expect(ventanas.creadas.single, contains(_eventoA));
    expect(KioskLauncher.isTotemActive, isTrue);
    expect(KioskLauncher.totemEventoId, _eventoA);
  });

  test('dos clics seguidos abren un solo tótem', () async {
    await Future.wait([
      KioskLauncher.launch(_eventoA),
      KioskLauncher.launch(_eventoA),
    ]);
    expect(ventanas.creadas, hasLength(1));
  });

  group('un aviso que no llega', () {
    setUp(() => KioskLauncher.launch(_eventoA));

    test('se reintenta una vez, y si llega no pasó nada', () async {
      ventanas.fallanLosProximos = 1;
      await KioskLauncher.notifyGuestCheckin({'id': 'x'});
      expect(ventanas.intentos, ['1:guest_checkin', '1:guest_checkin']);
      expect(ventanas.llegaron, ['1:guest_checkin']);
      expect(KioskLauncher.isTotemActive, isTrue);
    });

    test('con la ventana abierta, no desconecta el tótem', () async {
      ventanas.fallanLosProximos = 2;
      await KioskLauncher.notifyGuestCheckin({'id': 'x'});
      expect(ventanas.llegaron, isEmpty);
      expect(KioskLauncher.isTotemActive, isTrue,
          reason: 'se perdió un mensaje, no la ventana');
      expect(KioskLauncher.totemEventoId, _eventoA);

      // Y el aviso siguiente llega: Recepción no quedó muda.
      await KioskLauncher.notifyGuestCheckin({'id': 'y'});
      expect(ventanas.llegaron, ['1:guest_checkin']);
    });

    test('lo mismo para borrar, vaciar la lista y cambiar el diseño',
        () async {
      for (final avisar in <Future<void> Function()>[
        () => KioskLauncher.notifyGuestRemoved('x'),
        KioskLauncher.notifyListReset,
        () => KioskLauncher.notifyConfigUpdated({'evento_id': _eventoA}),
        KioskLauncher.notifyUpdate,
      ]) {
        ventanas.fallanLosProximos = 2;
        await avisar();
        expect(KioskLauncher.isTotemActive, isTrue);
      }
    });

    test('con la ventana cerrada, sí se la olvida', () async {
      ventanas.abiertasAhora.clear();
      ventanas.fallanLosProximos = 2;
      await KioskLauncher.notifyGuestCheckin({'id': 'x'});
      expect(KioskLauncher.isTotemActive, isFalse);
      expect(KioskLauncher.totemEventoId, isNull);
    });

    test('si no se puede saber si sigue abierta, no se la olvida', () async {
      ventanas.noSeSabe = true;
      ventanas.fallanLosProximos = 2;
      await KioskLauncher.notifyGuestCheckin({'id': 'x'});
      expect(KioskLauncher.isTotemActive, isTrue);
    });
  });

  group('volver a abrir el tótem', () {
    test('con la ventana viva la muestra y la reanuda, sin crear otra',
        () async {
      await KioskLauncher.launch(_eventoA);
      await KioskLauncher.close();
      expect(ventanas.escondidas, [1]);
      expect(ventanas.llegaron, ['1:pausar']);

      await KioskLauncher.launch(_eventoA);
      expect(ventanas.creadas, hasLength(1));
      expect(ventanas.mostradas, [1]);
      expect(ventanas.llegaron, ['1:pausar', '1:reanudar']);
    });

    test('con otro evento, se lo cambia en la misma ventana', () async {
      await KioskLauncher.launch(_eventoA);
      await KioskLauncher.launch(_eventoB);
      expect(ventanas.creadas, hasLength(1));
      expect(ventanas.llegaron, ['1:set_evento', '1:reanudar']);
      expect(KioskLauncher.totemEventoId, _eventoB);
    });

    test('si la cerraron con la cruz, abre una nueva', () async {
      await KioskLauncher.launch(_eventoA);
      ventanas.abiertasAhora.clear();
      await KioskLauncher.launch(_eventoA);
      expect(ventanas.creadas, hasLength(2));
      expect(KioskLauncher.isTotemActive, isTrue);
    });

    test('si hay una abierta que no estaba anotada, la adopta', () async {
      // Lo que dejaba la versión anterior después de un aviso fallido: la
      // ventana viva y nadie que la tuviera anotada.
      ventanas.abiertasAhora.add(7);
      await KioskLauncher.launch(_eventoA);
      expect(ventanas.creadas, isEmpty, reason: 'no nace una segunda ventana');
      expect(KioskLauncher.isTotemActive, isTrue);
      expect(KioskLauncher.totemEventoId, _eventoA);
      expect(ventanas.mostradas, [7]);
      expect(ventanas.llegaron, ['7:set_evento', '7:reanudar']);

      // Y de ahí en más los avisos van a esa.
      await KioskLauncher.notifyGuestCheckin({'id': 'x'});
      expect(ventanas.llegaron.last, '7:guest_checkin');
    });

    test('si quedaron dos, sigue con una y esconde la otra', () async {
      ventanas.abiertasAhora.addAll([7, 9]);
      await KioskLauncher.launch(_eventoA);
      expect(ventanas.creadas, isEmpty);
      expect(ventanas.escondidas, [9]);
      expect(ventanas.llegaron,
          ['9:pausar', '7:set_evento', '7:reanudar']);
      expect(ventanas.mostradas, [7]);
    });

    test('sin poder saber qué hay abierto y sin tótem anotado, abre uno',
        () async {
      ventanas.noSeSabe = true;
      await KioskLauncher.launch(_eventoA);
      expect(ventanas.creadas, hasLength(1));
    });
  });
}
