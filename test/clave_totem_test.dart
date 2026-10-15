// La clave del tótem de cada evento (`clave_totem.dart`, sección 8): se pide a
// la nube con usuario una vez y queda guardada en la PC.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/totem/services/clave_totem.dart';

const _ev = 'e0000000-0000-4000-8000-00000000000a';
const _otro = 'e0000000-0000-4000-8000-00000000000b';

void main() {
  late List<String> pedidas;
  String? Function(String) daLaNube = (_) => 'clave-de-la-nube';

  ClaveTotem armar() => ClaveTotem(
        pedirALaNube: (id) async {
          pedidas.add(id);
          return daLaNube(id);
        },
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pedidas = [];
    daLaNube = (_) => 'clave-de-la-nube';
  });

  test('la pide a la nube una sola vez', () async {
    final c = armar();
    expect(await c.de(_ev), 'clave-de-la-nube');
    expect(await c.de(_ev), 'clave-de-la-nube');
    expect(pedidas, [_ev]);
  });

  test('queda guardada en la PC: al volver a abrir el programa no la pide',
      () async {
    await armar().de(_ev);
    final otraVez = armar();
    expect(await otraVez.de(_ev), 'clave-de-la-nube');
    expect(pedidas, [_ev]);
  });

  test('cada evento tiene la suya', () async {
    daLaNube = (id) => 'clave-$id';
    final c = armar();
    expect(await c.de(_ev), 'clave-$_ev');
    expect(await c.de(_otro), 'clave-$_otro');
  });

  test('sin internet no hay clave, y no se guarda nada', () async {
    final c = ClaveTotem(
      pedirALaNube: (_) async => throw Exception('SocketException'),
    );
    expect(await c.de(_ev), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);

    // Con internet, la consigue.
    expect(await armar().de(_ev), 'clave-de-la-nube');
  });

  test('una respuesta vacía no es una clave', () async {
    daLaNube = (_) => '  ';
    expect(await armar().de(_ev), isNull);
    daLaNube = (_) => null;
    expect(await armar().de(_ev), isNull);
  });

  test('olvidada, se pide de nuevo', () async {
    final c = armar();
    await c.de(_ev);
    await c.olvidar(_ev);
    daLaNube = (_) => 'otra-clave';
    expect(await c.de(_ev), 'otra-clave');
    expect(await armar().de(_ev), 'otra-clave', reason: 'y queda guardada');
    expect(pedidas, [_ev, _ev]);
  });

  test('con un id que no es de evento no pregunta', () async {
    expect(await armar().de('corto'), isNull);
    expect(pedidas, isEmpty);
  });

  test('el link del navegador lleva el evento y la clave, y abre el tótem', () {
    final link = linkDelTotemWeb(
      base: 'https://arguello-events.vercel.app',
      eventoId: _ev,
      clave: 'abc123',
    );
    expect(link,
        'https://arguello-events.vercel.app/?totem&evento=$_ev&clave=abc123');
    final uri = Uri.parse(link);
    expect(uri.queryParameters['evento'], _ev);
    expect(uri.queryParameters['clave'], 'abc123');
    // `main.dart` elige la pantalla con `contains`: tiene que ser el tótem y
    // ninguna de las que se miran antes.
    expect(link, contains('totem'));
    for (final otra in ['cotizar', '/op']) {
      expect(link.contains(otra), isFalse, reason: otra);
    }
  });
}
