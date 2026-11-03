import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/widgets/pesos_enteros_formatter.dart';

/// La plata de la barra se escribe como se dice: "20000" se ve "20.000", en pesos
/// enteros, sin centavos ni números que entren por la derecha.
void main() {
  const f = PesosEnterosFormatter();

  String escribir(String antes, String despues) =>
      f.formatEditUpdate(TextEditingValue(text: antes), TextEditingValue(text: despues)).text;

  test('los puntos aparecen mientras se escribe', () {
    var t = '';
    final vistos = <String>[];
    for (final d in '20000'.split('')) {
      t = escribir(t, '$t$d');
      vistos.add(t);
    }
    expect(vistos, ['2', '20', '200', '2.000', '20.000']);
  });

  test('solo números: lo demás no entra', () {
    expect(escribir('', '1a2,5'), '125');
    expect(escribir('', r'$ 3.500'), '3.500');
  });

  test('borrar el punto se lleva el número de al lado', () {
    expect(escribir('2.000', '2000'), '200');
    expect(escribir('20.000', '20.00'), '2.000');
  });

  test('sin ceros adelante, y vacío queda vacío', () {
    expect(escribir('', '00500'), '500');
    expect(escribir('5', ''), '');
  });

  test('leer y escribir', () {
    expect(PesosEnterosFormatter.leer('20.000'), 20000);
    expect(PesosEnterosFormatter.leer(''), isNull);
    expect(PesosEnterosFormatter.escribir(1234567), '1.234.567');
    expect(PesosEnterosFormatter.escribir(0), '0');
    expect(PesosEnterosFormatter.escribir(null), '');
  });

  test('el cursor queda al final', () {
    final v = f.formatEditUpdate(const TextEditingValue(text: '200'), const TextEditingValue(text: '2000'));
    expect(v.selection.baseOffset, v.text.length);
  });
}
