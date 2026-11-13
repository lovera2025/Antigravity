import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/totem_config.dart';
import 'preferencias_de_la_ventana.dart';

/// Guarda la última [TotemConfig] conocida de cada evento en disco.
///
/// El tótem se proyecta en salones donde el wifi es una lotería. Sin esto, una
/// caída de red al arrancar dejaría la pantalla con el branding genérico en
/// medio del evento. Con esto arranca con lo último que vio y, cuando el
/// stream conecta, se actualiza sola.
///
/// **Pasa por [PreferenciasDeLaVentana], nunca por `SharedPreferences` a mano:**
/// esto corre también en la ventana del tótem, que no puede escribir el archivo
/// de preferencias (lo pisaría entero con una copia vieja). Ahí guardar es
/// pedírselo a la ventana principal.
class TotemConfigCache {
  static const _keyPrefix = 'totem_config_v1_';

  static String _key(String eventoId) => '$_keyPrefix$eventoId';

  static Future<void> save(TotemConfig config) async {
    try {
      await PreferenciasDeLaVentana.guardar(
        _key(config.eventoId),
        jsonEncode(config.toJson()),
      );
    } catch (e) {
      debugPrint('TotemConfigCache.save: $e');
    }
  }

  static Future<TotemConfig?> load(String eventoId) async {
    try {
      final raw = await PreferenciasDeLaVentana.leer(_key(eventoId));
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // El evento_id lo imponemos nosotros: si el JSON viniera corrupto o de
      // otro evento, la config igual queda atada al evento que se pidió.
      map['evento_id'] = eventoId;
      return TotemConfig.fromJson(map);
    } catch (e) {
      debugPrint('TotemConfigCache.load: $e');
      return null;
    }
  }

  static Future<void> clear(String eventoId) async {
    try {
      await PreferenciasDeLaVentana.guardar(_key(eventoId), null);
    } catch (e) {
      debugPrint('TotemConfigCache.clear: $e');
    }
  }
}
