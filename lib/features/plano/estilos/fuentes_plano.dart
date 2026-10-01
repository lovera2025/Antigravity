import 'package:flutter/services.dart';

import 'estilo_plano.dart';

/// Los archivos de cada familia de letra del plano. Tiene que decir lo mismo
/// que `fonts:` en `pubspec.yaml`: un test los compara contra el
/// `FontManifest.json` que arma Flutter.
const Map<String, List<String>> archivosFuentesPlano = {
  FuentesPlano.gala: ['assets/google_fonts/CormorantGaramond-SemiBold.ttf'],
  FuentesPlano.neon: ['assets/google_fonts/TiltNeon-Regular.ttf'],
  FuentesPlano.linea: [
    'assets/google_fonts/Outfit-Regular.ttf',
    'assets/google_fonts/Outfit-Bold.ttf',
  ],
};

bool _cargadas = false;

/// Registra las letras del plano con [FontLoader].
///
/// En la app no hace falta: las declara `pubspec.yaml` y el motor las carga
/// solo. Sí hace falta en `flutter test` y en las muestras de `tool/`, que no
/// cargan las letras de la app y dibujarían todo con la letra de prueba.
Future<void> cargarFuentesPlano() async {
  if (_cargadas) return;
  for (final e in archivosFuentesPlano.entries) {
    final loader = FontLoader(e.key);
    for (final a in e.value) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }
  _cargadas = true;
}
