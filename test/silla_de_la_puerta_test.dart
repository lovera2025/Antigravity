import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/silla_de_la_puerta.dart';

/// Qué producto de la barra es una silla de la noche (6.4.0): por el nombre, sin
/// columna nueva en el catálogo.
void main() {
  test('las sillas, como las escriba el jefe', () {
    for (final nombre in ['Silla extra', 'SILLA', 'Sillas extra', 'silla de la noche', 'Silla']) {
      expect(esSillaDeLaPuerta(nombre), isTrue, reason: nombre);
    }
  });

  test('lo que no es una silla', () {
    for (final nombre in ['Fernet con coca', 'Cerveza lata', 'Sillón', 'Agua sin gas', '']) {
      expect(esSillaDeLaPuerta(nombre), isFalse, reason: nombre);
    }
  });
}
