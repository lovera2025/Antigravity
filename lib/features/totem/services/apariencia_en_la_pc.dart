import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/totem_config_cache.dart';
import '../../../models/totem_config.dart';

/// **La apariencia del tótem, de la nube a este equipo** (25-nov-2026): lo de
/// Personalizar (la apariencia, los colores, las letras, los textos, la foto y
/// el fondo elegidos) queda en [TotemConfigCache], así el tótem sale igual sin
/// internet. "Lista para trabajar sin internet" lo mira, y la tele prepara así
/// todas las fiestas que vienen (`preparar_las_fiestas.dart`).
class AparienciaEnLaPc {
  AparienciaEnLaPc(this._client);
  final SupabaseClient _client;

  static const espera = Duration(seconds: 15);

  /// Las apariencias de [eventoIds] en la nube, **en una sola consulta**. Una
  /// fiesta sin fila va con la de siempre: no está en lo que vuelve. Tira si
  /// no se pudo leer.
  Future<Map<String, TotemConfig>> leer(List<String> eventoIds) async {
    // Con un id malformado la nube contesta 22P02: ni se pregunta.
    final ids = [for (final id in eventoIds) if (id.length == 36) id];
    if (ids.isEmpty) return const {};
    final filas = await _client
        .from('totem_config')
        .select()
        .inFilter('evento_id', ids)
        .timeout(espera);
    return {
      for (final f in filas)
        if (f['evento_id'] is String) f['evento_id'] as String: TotemConfig.fromJson(f),
    };
  }

  /// La lee de la nube y la deja en el equipo. True: guardada; null: la fiesta
  /// va con la de siempre; false: no se pudo leer y no había ninguna guardada.
  Future<bool?> guardar(String eventoId) async {
    try {
      final cfg = (await leer([eventoId]))[eventoId];
      if (cfg == null) return null;
      await TotemConfigCache.save(cfg);
      return true;
    } catch (e) {
      debugPrint('La apariencia del tótem no se pudo leer: $e');
      // La de antes sigue guardada: con esa sale igual.
      return await TotemConfigCache.load(eventoId) != null ? true : false;
    }
  }

  /// Sin internet: si hay una guardada (true), o null (no se sabe: puede ir
  /// con la de siempre).
  static Future<bool?> estaGuardada(String eventoId) async =>
      await TotemConfigCache.load(eventoId) != null ? true : null;
}
