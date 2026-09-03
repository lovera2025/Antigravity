import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cómo se acomoda el tótem en pantalla.
///
/// Hasta ahora el layout se decidía solo por la relación de aspecto de la
/// ventana, y como la ventana nacía en 1280x720 el modo vertical no se
/// activaba nunca. Con esto se elige a mano desde la propia pantalla.
enum TotemOrientation {
  /// Decide por la forma de la ventana (comportamiento histórico).
  auto,

  /// Fuerza el layout de pantalla parada (9:16).
  vertical,

  /// Fuerza el layout apaisado (16:9).
  horizontal;

  /// Orden del botón de giro: auto → vertical → horizontal → auto.
  TotemOrientation get siguiente => switch (this) {
        TotemOrientation.auto => TotemOrientation.vertical,
        TotemOrientation.vertical => TotemOrientation.horizontal,
        TotemOrientation.horizontal => TotemOrientation.auto,
      };

  String get etiqueta => switch (this) {
        TotemOrientation.auto => 'AUTO',
        TotemOrientation.vertical => 'VERTICAL',
        TotemOrientation.horizontal => 'HORIZONTAL',
      };

  static TotemOrientation desdeNombre(String? nombre) {
    if (nombre == null) return TotemOrientation.auto;
    return TotemOrientation.values.firstWhere(
      (o) => o.name == nombre,
      orElse: () => TotemOrientation.auto,
    );
  }
}

/// Recuerda la orientación elegida por evento, para que el tótem abra como
/// quedó la última vez en ese salón.
class TotemOrientationStore {
  static const _keyPrefix = 'totem_orient_v1_';

  static String _key(String eventoId) => '$_keyPrefix$eventoId';

  static Future<TotemOrientation> load(String eventoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return TotemOrientation.desdeNombre(prefs.getString(_key(eventoId)));
    } catch (e) {
      debugPrint('TotemOrientationStore.load: $e');
      return TotemOrientation.auto;
    }
  }

  static Future<void> save(String eventoId, TotemOrientation orientacion) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(eventoId), orientacion.name);
    } catch (e) {
      debugPrint('TotemOrientationStore.save: $e');
    }
  }
}
