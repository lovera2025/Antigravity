import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/utils/subir_ya.dart';

void main() {
  test('sube a la primera: listo', () async {
    var subidas = 0;
    final ok = await subirConReintentos(
      subir: () async => subidas++,
      pendiente: () async => subidas == 0,
      ocupado: () => false,
      espera: Duration.zero,
    );
    expect(ok, isTrue);
    expect(subidas, 1);
  });

  test('si el motor está ocupado, espera y vuelve a probar', () async {
    var subidas = 0;
    // Las dos primeras veces el motor estaba en otra sincronización y no subió.
    final ok = await subirConReintentos(
      subir: () async => subidas++,
      pendiente: () async => subidas < 3,
      ocupado: () => subidas < 3,
      espera: Duration.zero,
    );
    expect(ok, isTrue);
    expect(subidas, 3);
  });

  test('sin red no insiste: queda en la cola y avisa', () async {
    var subidas = 0;
    final ok = await subirConReintentos(
      subir: () async => subidas++,
      pendiente: () async => true,
      ocupado: () => false,
      espera: Duration.zero,
    );
    expect(ok, isFalse);
    expect(subidas, 1);
  });

  test('si el motor sigue ocupado todo el rato, se rinde y avisa', () async {
    var subidas = 0;
    final ok = await subirConReintentos(
      subir: () async => subidas++,
      pendiente: () async => true,
      ocupado: () => true,
      intentos: 4,
      espera: Duration.zero,
    );
    expect(ok, isFalse);
    expect(subidas, 4);
  });
}
