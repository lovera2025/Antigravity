import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/totem_config_cache.dart';
import '../../../main.dart';
import '../../../models/totem_config.dart';

/// Config visual del tótem para un evento, en vivo.
///
/// Emite en este orden:
///   1. La caché en disco, si hay (arranque instantáneo y a prueba de wifi malo).
///   2. Lo que llegue por el stream de Supabase, cada vez que alguien guarda
///      desde el editor. Por eso la ventana del tótem se actualiza sola, sin
///      reiniciarla.
///
/// Nunca falla hacia una pantalla rota: ante cualquier error (tabla que todavía
/// no existe, sin red, evento sin fila) devuelve [TotemConfig.defaults], que
/// son los valores con los que el tótem viene funcionando desde siempre.
///
/// Lee `supabaseProvider` en vez del singleton para funcionar también en la
/// ventana secundaria de escritorio, donde ese provider está sobreescrito con
/// un cliente independiente (`main.dart:60`).
final totemConfigProvider =
    StreamProvider.autoDispose.family<TotemConfig, String>((ref, eventoId) {
  final defaults = TotemConfig.defaults(eventoId);

  // Blindaje igual al del repositorio de invitados: con un id malformado
  // Supabase devuelve 22P02, así que ni lo intentamos.
  if (eventoId.length != 36) {
    return Stream.value(defaults);
  }

  final client = ref.watch(supabaseProvider);
  final controller = StreamController<TotemConfig>();
  StreamSubscription<List<Map<String, dynamic>>>? sub;
  var emitioAlgoDelServidor = false;

  // 1. Caché primero, para no mostrar el branding genérico mientras conecta.
  TotemConfigCache.load(eventoId).then((cacheada) {
    if (controller.isClosed) return;
    if (cacheada != null && !emitioAlgoDelServidor) {
      controller.add(cacheada);
    } else if (cacheada == null && !emitioAlgoDelServidor) {
      controller.add(defaults);
    }
  }).catchError((_) {
    if (!controller.isClosed && !emitioAlgoDelServidor) controller.add(defaults);
  });

  // 2. Stream en vivo.
  try {
    sub = client
        .from('totem_config')
        .stream(primaryKey: ['evento_id'])
        .eq('evento_id', eventoId)
        .listen(
          (rows) {
            if (controller.isClosed) return;
            emitioAlgoDelServidor = true;
            final config = rows.isEmpty
                ? defaults
                : TotemConfig.fromJson(rows.first);
            controller.add(config);
            // Solo cacheamos configuraciones reales, no los defaults: si el
            // evento no tiene fila no hay nada que recordar.
            if (rows.isNotEmpty) {
              TotemConfigCache.save(config);
            }
          },
          onError: (Object e) {
            debugPrint('totemConfigProvider stream: $e');
            if (!controller.isClosed && !emitioAlgoDelServidor) {
              controller.add(defaults);
            }
          },
          cancelOnError: false,
        );
  } catch (e) {
    debugPrint('totemConfigProvider no pudo suscribirse: $e');
    if (!controller.isClosed) controller.add(defaults);
  }

  ref.onDispose(() {
    sub?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Igual que [totemConfigProvider] pero ya resuelto: mientras carga o si algo
/// falla devuelve los valores por defecto.
///
/// Los widgets del tótem lo usan así y se olvidan de manejar estados: la
/// pantalla del salón nunca debe mostrar un spinner ni un error.
final totemConfigValueProvider =
    Provider.autoDispose.family<TotemConfig, String>((ref, eventoId) {
  return ref.watch(totemConfigProvider(eventoId)).when(
        data: (config) => config,
        loading: () => TotemConfig.defaults(eventoId),
        error: (_, _) => TotemConfig.defaults(eventoId),
      );
});
