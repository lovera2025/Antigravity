import 'dart:math';

import 'package:arguello_events/features/recepcion/central/codigo_central.dart';
import 'package:arguello_events/features/recepcion/central/direcciones_red.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// En qué dirección encuentran los celulares a la central, y su código.
void main() {
  group('la dirección para los celulares', () {
    test('el wifi del router primero, después el cable', () {
      expect(
        direccionesParaCelulares(const [
          DireccionDeLaPc('Ethernet', '192.168.1.20'),
          DireccionDeLaPc('Wi-Fi', '192.168.0.10'),
        ]),
        ['192.168.0.10', '192.168.1.20'],
      );
    });

    test('sin las de máquinas virtuales, VPN, esta misma PC ni las que '
        'Windows inventa sin router', () {
      expect(
        direccionesParaCelulares(const [
          DireccionDeLaPc('vEthernet (WSL)', '172.24.16.1'),
          DireccionDeLaPc('VirtualBox Host-Only Network', '192.168.56.1'),
          DireccionDeLaPc('Loopback Pseudo-Interface 1', '127.0.0.1'),
          DireccionDeLaPc('Wi-Fi', '169.254.10.3'),
          DireccionDeLaPc('Tailscale', '100.80.1.2'),
          DireccionDeLaPc('Conexión de red Bluetooth', '192.168.44.1'),
          DireccionDeLaPc('Wi-Fi', '10.0.0.7'),
        ]),
        ['10.0.0.7'],
      );
    });

    test('una que no es de router va al final, por las dudas', () {
      expect(
        direccionesParaCelulares(const [
          DireccionDeLaPc('Ethernet 2', '200.45.1.9'),
          DireccionDeLaPc('Ethernet', '172.20.0.5'),
        ]),
        ['172.20.0.5', '200.45.1.9'],
      );
    });

    test('sin router, ninguna', () {
      expect(
        direccionesParaCelulares(const [
          DireccionDeLaPc('Wi-Fi', '169.254.3.3'),
        ]),
        isEmpty,
      );
      expect(direccionesParaCelulares(const []), isEmpty);
    });

    test('las de router', () {
      expect(esDireccionDeRouter('192.168.0.1'), isTrue);
      expect(esDireccionDeRouter('10.20.30.40'), isTrue);
      expect(esDireccionDeRouter('172.16.0.1'), isTrue);
      expect(esDireccionDeRouter('172.31.255.1'), isTrue);
      expect(esDireccionDeRouter('172.32.0.1'), isFalse);
      expect(esDireccionDeRouter('8.8.8.8'), isFalse);
      expect(esDireccionDeRouter('192.168.0'), isFalse);
      expect(esDireccionDeRouter('fe80::1'), isFalse);
    });

    test('una repetida va una vez', () {
      expect(
        direccionesParaCelulares(const [
          DireccionDeLaPc('Wi-Fi', '192.168.0.10'),
          DireccionDeLaPc('Wi-Fi 2', '192.168.0.10'),
        ]),
        ['192.168.0.10'],
      );
    });
  });

  group('el código', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('cuatro cifras, sin cero adelante', () {
      final azar = Random(1);
      for (var i = 0; i < 2000; i++) {
        final c = nuevoCodigo(azar);
        expect(c, matches(RegExp(r'^[1-9]\d{3}$')));
      }
    });

    test('dura la noche: el mismo si la notebook se reinicia; otro al día '
        'siguiente', () async {
      final noche = DateTime(2026, 12, 12, 21);
      final primero = await CodigoCentral.delEvento('ev', ahora: noche);
      expect(
        await CodigoCentral.delEvento(
          'ev',
          ahora: noche.add(const Duration(hours: 5)),
        ),
        primero,
      );
      // Otro evento tiene el suyo.
      final otro = await CodigoCentral.delEvento('ev2', ahora: noche);
      expect(await CodigoCentral.delEvento('ev2', ahora: noche), otro);

      final manana = noche.add(kCodigoDura);
      final nuevo = await CodigoCentral.delEvento(
        'ev',
        ahora: manana,
        azar: _Fijo([primero == '4821' ? 4822 : 4821]),
      );
      expect(nuevo, isNot(primero));
    });

    test('cambiarlo da uno distinto del que había', () async {
      // El azar primero repite el de antes: se saca otro.
      final cambiado = await CodigoCentral.cambiar(
        'ev',
        anterior: '4821',
        azar: _Fijo([4821, 4821, 5555]),
      );
      expect(cambiado, '5555');
      expect(await CodigoCentral.delEvento('ev'), '5555');
    });

    test('lo guardado roto no sirve: se saca uno nuevo', () async {
      SharedPreferences.setMockInitialValues({
        'central_puerta_codigo_v1_ev': 'basura',
      });
      final c = await CodigoCentral.delEvento('ev', azar: _Fijo([7777]));
      expect(c, '7777');
    });

    test('un código "del futuro" (reloj atrasado) no vale', () {
      final ahora = DateTime(2026, 12, 12, 21);
      expect(codigoVigente(ahora, ahora), isTrue);
      expect(
        codigoVigente(ahora.add(const Duration(hours: 1)), ahora),
        isFalse,
      );
    });
  });
}

/// Un azar que da los códigos que se le piden (el número ya con las mil).
class _Fijo implements Random {
  _Fijo(this._codigos);
  final List<int> _codigos;
  var _i = 0;

  @override
  int nextInt(int max) {
    final c = _codigos[_i < _codigos.length ? _i++ : _codigos.length - 1];
    return c - 1000;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
