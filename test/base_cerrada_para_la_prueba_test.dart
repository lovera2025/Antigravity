// Las ventanas de prueba cierran la base de la PC al arrancar (6.9.0, etapa 7):
// desde ahí, abrirla o escribir al lado de ella falla en vez de abrir la de
// verdad. Va en su propio archivo: la base queda cerrada para todo lo que corra
// después en este proceso.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/database/local_database.dart';

void main() {
  test('cerrada para la prueba, la base no se abre ni se busca su carpeta',
      () async {
    LocalDatabase.cerrarParaLaPrueba();
    await expectLater(
      LocalDatabase.instance,
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'mensaje',
        LocalDatabase.kCerradaParaLaPrueba,
      )),
    );
    await expectLater(LocalDatabase.dbPath, throwsA(isA<StateError>()));
  });
}
