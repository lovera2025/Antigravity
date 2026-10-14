import 'package:flutter/services.dart';

import '../../plano/estilos/estilo_plano.dart';
import '../../plano/estilos/fuentes_plano.dart';

/// Las letras de las cuatro apariencias del tótem. Vienen con la app
/// (`pubspec.yaml`, `fonts:`): el tótem tiene que saludar sin internet, y
/// nada se baja el día de la fiesta.
abstract final class FuentesTotem {
  /// Tilt Neon: el título y el nombre de Neón.
  static const tubo = 'TotemTubo';

  /// Neonderthaw: el cartel cursivo de Neón.
  static const cartel = 'TotemCartel';

  /// Cormorant Garamond, seminegrita (600) y cursiva (500): Gala.
  static const gala = 'TotemGala';

  /// Oswald, regular y negrita: Cristal y Póster.
  static const cartelera = 'TotemCartelera';

  /// Outfit, regular y negrita: lo chico de todas (sillas, música, "con…").
  static const linea = FuentesPlano.linea;
}

/// Los archivos de cada familia. Tiene que decir lo mismo que `fonts:` en
/// `pubspec.yaml`.
const Map<String, List<String>> archivosFuentesTotem = {
  FuentesTotem.tubo: ['assets/google_fonts/TiltNeon-Regular.ttf'],
  FuentesTotem.cartel: ['assets/google_fonts/Neonderthaw-Regular.ttf'],
  FuentesTotem.gala: [
    'assets/google_fonts/CormorantGaramond-SemiBold.ttf',
    'assets/google_fonts/CormorantGaramond-MediumItalic.ttf',
  ],
  FuentesTotem.cartelera: [
    'assets/google_fonts/Oswald-Regular.ttf',
    'assets/google_fonts/Oswald-Bold.ttf',
  ],
};

bool _cargadas = false;

/// Registra las letras del tótem con [FontLoader].
///
/// En la app no hace falta: las declara `pubspec.yaml`. Sí en `flutter test` y
/// en las muestras de `tool/`, que dibujarían todo con la letra de prueba.
Future<void> cargarFuentesTotem() async {
  if (_cargadas) return;
  await cargarFuentesPlano();
  for (final e in archivosFuentesTotem.entries) {
    final loader = FontLoader(e.key);
    for (final a in e.value) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }
  _cargadas = true;
}
