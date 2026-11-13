import 'package:flutter/foundation.dart';

import '../../core/services/preferencias_de_la_ventana.dart';

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
///
/// **Pasa por [PreferenciasDeLaVentana], nunca por `SharedPreferences` a mano:**
/// la guarda la ventana del tótem (GIRAR), que no puede escribir el archivo de
/// preferencias, y la lee la principal al abrirla. Guardada por la principal,
/// las dos ven lo mismo.
class TotemOrientationStore {
  static const _keyPrefix = 'totem_orient_v1_';

  static String _key(String eventoId) => '$_keyPrefix$eventoId';

  static Future<TotemOrientation> load(String eventoId) async {
    try {
      return TotemOrientation.desdeNombre(
        await PreferenciasDeLaVentana.leer(_key(eventoId)),
      );
    } catch (e) {
      debugPrint('TotemOrientationStore.load: $e');
      return TotemOrientation.auto;
    }
  }

  static Future<void> save(String eventoId, TotemOrientation orientacion) async {
    try {
      await PreferenciasDeLaVentana.guardar(_key(eventoId), orientacion.name);
    } catch (e) {
      debugPrint('TotemOrientationStore.save: $e');
    }
  }
}
