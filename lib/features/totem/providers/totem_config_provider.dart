import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/totem_config_cache.dart';
import '../../../main.dart';
import '../../../models/totem_config.dart';

/// Cuánto se espera para volver a pedirle la config a la nube cuando todavía no
/// se la pudo leer: 5, 10, 20 y 40 segundos, y de ahí cada minuto.
Duration esperaDeReintentoDeLaConfig(int intentos) {
  final n = intentos < 0 ? 0 : (intentos > 4 ? 4 : intentos);
  final segundos = 5 << n;
  return Duration(seconds: segundos > 60 ? 60 : segundos);
}

/// La espera entre reintentos. Solo las pruebas la cambian.
final esperaDeLaConfigProvider = Provider<Duration Function(int intentos)>(
  (ref) => esperaDeReintentoDeLaConfig,
);

/// Config visual del tótem para un evento, en vivo.
///
/// Emite en este orden:
///   1. La caché en disco, si hay (arranque instantáneo y a prueba de wifi malo);
///      si no hay, los valores de siempre.
///   2. Lo que diga la nube, cuando se la puede leer.
///
/// **Si la nube no se puede leer, se queda con lo que ya mostró.** Hasta la
/// 6.8.0, al fallar la lectura emitía [TotemConfig.defaults] *después* de la
/// caché: la notebook que abría el tótem sin internet mostraba un instante la
/// foto y el título del evento y enseguida quedaba en "JUNIOR EVENTOS", sin
/// foto. Y Personalizar, abierto en ese estado, guardaba eso encima de lo de la
/// nube (revisión del 13-nov).
///
/// **Y vuelve a pedirla sola** ([esperaDeReintentoDeLaConfig]) hasta que la lee
/// una vez: el stream del paquete se cierra con el primer error y nadie lo
/// volvía a abrir, así que aunque volviera internet seguía así hasta esconder y
/// mostrar el tótem. Una vez leída no se reintenta más: en reposo no se le pide
/// nada a la nube. `totem_config` no está en Realtime (a propósito): lo que
/// guarda otra PC no llega solo; lo de esta PC llega por el puente
/// (`config_updated`).
///
/// Lee `supabaseProvider` en vez del singleton para funcionar también en la
/// ventana secundaria de escritorio, donde ese provider está sobreescrito con
/// un cliente independiente (`main.dart:60`). Escondida, esa ventana deja de
/// mirar este provider (`_pausado`), y con eso se corta también el reintento.
final totemConfigProvider =
    StreamProvider.autoDispose.family<TotemConfig, String>((ref, eventoId) {
  final defaults = TotemConfig.defaults(eventoId);

  // Blindaje igual al del repositorio de invitados: con un id malformado
  // Supabase devuelve 22P02, así que ni lo intentamos.
  if (eventoId.length != 36) {
    return Stream.value(defaults);
  }

  final client = ref.watch(supabaseProvider);
  final espera = ref.watch(esperaDeLaConfigProvider);
  final controller = StreamController<TotemConfig>();
  StreamSubscription<List<Map<String, dynamic>>>? sub;
  Timer? reintento;
  var intentos = 0;
  var emitioAlgoDelServidor = false;
  var soltado = false;

  // 1. Caché primero, para no mostrar el branding genérico mientras conecta.
  //    Es la única que emite los valores de siempre cuando no hay nada.
  TotemConfigCache.load(eventoId).then((cacheada) {
    if (controller.isClosed || emitioAlgoDelServidor) return;
    controller.add(cacheada ?? defaults);
  }).catchError((_) {
    if (!controller.isClosed && !emitioAlgoDelServidor) controller.add(defaults);
  });

  // 2. La nube.
  late final void Function() suscribir;

  void reintentar() {
    // Con una lectura buena alcanza; y un solo reintento vivo.
    if (soltado || emitioAlgoDelServidor || reintento != null) return;
    reintento = Timer(espera(intentos++), () {
      reintento = null;
      if (!soltado && !emitioAlgoDelServidor) suscribir();
    });
  }

  suscribir = () {
    unawaited(sub?.cancel());
    sub = null;
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
              // Sin emitir nada: lo que ya se mostró (la caché) queda.
              debugPrint('totemConfigProvider stream: $e');
              reintentar();
            },
            onDone: reintentar,
            cancelOnError: false,
          );
    } catch (e) {
      debugPrint('totemConfigProvider no pudo suscribirse: $e');
      reintentar();
    }
  };
  suscribir();

  ref.onDispose(() {
    soltado = true;
    reintento?.cancel();
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
