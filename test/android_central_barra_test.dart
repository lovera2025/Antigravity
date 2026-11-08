import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La tablet de la barra (Android) tiene que poder buscar la central por el wifi del salón
/// y conectarse a la notebook por `ws://`: sin esto, Android lo bloquea en silencio. Se lee
/// el manifest, como `instalador_puesto_test.dart` lee el instalador.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('internet, el estado del wifi y de la red', () {
    for (final p in ['INTERNET', 'ACCESS_WIFI_STATE', 'ACCESS_NETWORK_STATE']) {
      expect(manifest, contains('android.permission.$p'), reason: p);
    }
  });

  test('deja conectarse a la notebook del salón sin cifrar', () {
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
  });
}
