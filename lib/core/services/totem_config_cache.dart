import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/totem_config.dart';

/// Guarda la última [TotemConfig] conocida de cada evento en disco.
///
/// El tótem se proyecta en salones donde el wifi es una lotería. Sin esto, una
/// caída de red al arrancar dejaría la pantalla con el branding genérico en
/// medio del evento. Con esto arranca con lo último que vio y, cuando el
/// stream conecta, se actualiza sola.
///
/// Misma mecánica que [UserRoleCache]: SharedPreferences + JSON.
class TotemConfigCache {
  static const _keyPrefix = 'totem_config_v1_';

  static String _key(String eventoId) => '$_keyPrefix$eventoId';

  static Future<void> save(TotemConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(config.eventoId), jsonEncode(config.toJson()));
    } catch (e) {
      debugPrint('TotemConfigCache.save: $e');
    }
  }

  static Future<TotemConfig?> load(String eventoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(eventoId));
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(eventoId));
    } catch (e) {
      debugPrint('TotemConfigCache.clear: $e');
    }
  }
}
