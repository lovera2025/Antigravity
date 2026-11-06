import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/kiosk_launcher.dart';
import '../../../models/totem_config.dart';
import '../repositories/totem_config_repository.dart';
import '../services/tiempos_a_mano.dart';
import 'totem_config_provider.dart';

/// Los segundos de la llegada cambiados a mano esa noche, por evento
/// ([TiemposAMano]). Null: los de Personalizar.
///
/// Viven en la ventana principal de esta PC (la notebook del salón): se
/// guardan en el disco, así sobreviven a un reinicio sin internet; le llegan
/// a la ventana del tótem al instante (y en la ficha de cada minuto); y se
/// suben a la nube cuando se puede, así Personalizar y las otras PCs los ven.
final tiemposAManoProvider =
    NotifierProvider.family<TiemposDeLaNoche, TiemposAMano?, String>(
  TiemposDeLaNoche.new,
);

/// La config del tótem del evento con los segundos de esa noche encima: la
/// que dibuja el tótem de esta PC y la que se le manda al del salón.
final totemConfigDeLaNocheProvider =
    Provider.autoDispose.family<TotemConfig, String>((ref, eventoId) {
  final cfg = ref.watch(totemConfigValueProvider(eventoId));
  final aMano = ref.watch(tiemposAManoProvider(eventoId));
  return aMano == null ? cfg : aMano.aplicarA(cfg);
});

class TiemposDeLaNoche extends Notifier<TiemposAMano?> {
  TiemposDeLaNoche(this.eventoId);

  final String eventoId;

  /// En el disco: los segundos y si ya se subieron.
  static String clave(String eventoId) => 'tiempos_a_mano_v1_$eventoId';

  /// Si se tocó algo antes de terminar de leer el disco: lo de ahora manda.
  bool _tocado = false;

  @override
  TiemposAMano? build() {
    unawaited(_leerDelDisco());
    return null;
  }

  Future<void> _leerDelDisco() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final crudo = prefs.getString(clave(eventoId));
      if (crudo == null || _tocado) return;
      final datos = jsonDecode(crudo);
      final t = TiemposAMano.fromJson(datos);
      if (t == null) return;
      state = t;
      // Lo que no se pudo subir esa noche, se sube ahora.
      if (datos is Map && datos['subido'] != true) unawaited(_subir(t));
    } catch (e) {
      debugPrint('Los segundos de la llegada no se pudieron leer: $e');
    }
  }

  /// Los segundos de esa noche: la tele cambia al instante.
  Future<void> poner(TiemposAMano t) async {
    _tocado = true;
    if (t == state) return;
    state = t;
    await _guardarEnElDisco(t, subido: false);
    await KioskLauncher.notifyTiempos(eventoId, t.toJson());
    unawaited(_subir(t));
  }

  /// Vuelve a lo de Personalizar: se guardó la config entera.
  Future<void> olvidar() async {
    _tocado = true;
    if (state == null) return;
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(clave(eventoId));
    } catch (e) {
      debugPrint('Los segundos de la llegada no se pudieron borrar: $e');
    }
    await KioskLauncher.notifyTiempos(eventoId, null);
  }

  Future<void> _guardarEnElDisco(TiemposAMano t, {required bool subido}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        clave(eventoId),
        jsonEncode({...t.toJson(), 'subido': subido}),
      );
    } catch (e) {
      debugPrint('Los segundos de la llegada no se pudieron guardar: $e');
    }
  }

  /// A la nube, a mejor esfuerzo: sin internet quedan en la PC y se intenta
  /// de nuevo al abrir.
  Future<void> _subir(TiemposAMano t) async {
    try {
      await ref.read(totemConfigRepositoryProvider).guardarTiempos(
            eventoId,
            nombre: t.nombre,
            camino: t.camino,
          );
      if (state == t) await _guardarEnElDisco(t, subido: true);
    } catch (e) {
      debugPrint('Los segundos de la llegada quedan en la PC, sin subir: $e');
    }
  }
}
