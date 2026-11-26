import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/instalacion_id.dart';
import '../../../core/services/pulso_entre_equipos.dart';
import '../../../core/services/totem_config_cache.dart';
import '../../../main.dart';
import '../../../models/totem_config.dart';

/// Escritura de la identidad visual del tótem.
///
/// El provider de lectura (`totemConfigProvider`) no escribe a propósito: lo
/// consume la ventana del salón, que solo mira. Todo lo que guarda pasa por acá.
///
/// Lee `supabaseProvider` y **nunca** `Supabase.instance`: en la ventana
/// secundaria de escritorio ese provider está sobreescrito con un cliente
/// independiente.
final totemConfigRepositoryProvider = Provider<TotemConfigRepository>((ref) {
  return TotemConfigRepository(ref.watch(supabaseProvider));
});

class TotemConfigRepository {
  /// Bucket creado por `supabase/migracion_totem_config.sql`.
  static const String bucket = 'totem';

  /// Mismo tope que declara el bucket. Se valida acá también porque del otro
  /// lado el error llega como un 413 ilegible.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Únicos formatos que el bucket acepta (`allowed_mime_types`).
  static const Map<String, String> tiposPermitidos = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  final SupabaseClient _client;

  TotemConfigRepository(this._client);

  static String normalizarExtension(String extension) =>
      extension.toLowerCase().replaceFirst('.', '');

  static String? mimeDe(String extension) =>
      tiposPermitidos[normalizarExtension(extension)];

  /// Cuánto se espera la lectura de antes de guardar ([sigueComoSeAbrio]).
  static const esperaDeLaLectura = Duration(seconds: 5);

  /// Lo que no cuenta para saber si dos configs son la misma: cuándo y quién la
  /// guardó, y los segundos de la llegada, que esa noche se cambian a mano
  /// desde Recepción sin pasar por Personalizar ([guardarTiempos]).
  static const _noCuentan = {
    'updated_at',
    'updated_by',
    'llegada_nombre_seg',
    'llegada_camino_seg',
  };

  /// Si [enLaNube] (null: el evento no tiene fila) es la misma config que
  /// [abierta], la que Personalizar mostró al abrirse.
  static bool mismaConfig(TotemConfig abierta, TotemConfig? enLaNube) {
    Map<String, dynamic> loQueCuenta(TotemConfig c) =>
        // Ida y vuelta por el JSON: así las dos pasan por el mismo camino,
        // venga una de la caché y la otra de la nube.
        TotemConfig.fromJson(c.toJson()).toJson()
          ..removeWhere((clave, _) => _noCuentan.contains(clave));
    final a = loQueCuenta(abierta);
    final b = loQueCuenta(enLaNube ?? TotemConfig.defaults(abierta.eventoId));
    return jsonEncode(a) == jsonEncode(b);
  }

  /// Si lo guardado en la nube sigue siendo [abierta], lo que Personalizar
  /// mostró al abrirse. **Personalizar lo pregunta antes de guardar, y si no,
  /// no guarda:** guarda la fila entera, así que abierto sobre algo viejo o
  /// sobre los valores de fábrica (la config todavía no se había leído, o la
  /// cambió otra PC: la tabla no está en Realtime) pisaba en la nube la foto,
  /// el fondo, la apariencia y los textos (revisión del 13-nov).
  ///
  /// **Tira si no se pudo leer** (sin internet): sin saber qué hay, no se
  /// guarda. Si cambió, deja en esta PC lo de la nube, para que al volver a
  /// abrir Personalizar se parta de eso.
  Future<bool> sigueComoSeAbrio(TotemConfig abierta) async {
    final fila = await _client
        .from('totem_config')
        .select()
        .eq('evento_id', abierta.eventoId)
        .maybeSingle()
        .timeout(esperaDeLaLectura);
    final enLaNube = fila == null ? null : TotemConfig.fromJson(fila);
    if (mismaConfig(abierta, enLaNube)) return true;
    if (enLaNube != null) {
      await TotemConfigCache.save(enLaNube);
    } else {
      await TotemConfigCache.clear(abierta.eventoId);
    }
    return false;
  }

  /// Guarda la config del evento y devuelve la versión persistida.
  Future<TotemConfig> guardar(TotemConfig cfg) async {
    final ahora = DateTime.now().toUtc();

    final fila = cfg.toJson()
      // `toJson()` emite `updated_at: null`. Como el upsert manda la columna
      // explícitamente, el `DEFAULT now()` de la tabla no llega a aplicarse y la
      // auditoría quedaría siempre vacía.
      ..['updated_at'] = ahora.toIso8601String()
      ..['updated_by'] = _client.auth.currentUser?.id;

    await _client.from('totem_config').upsert(fila, onConflict: 'evento_id');

    final guardada = TotemConfig.fromJson(fila);
    await TotemConfigCache.save(guardada);
    // Sin esperarlo: Personalizar no queda trabado si el aviso tarda
    // (revisión del 26-nov).
    unawaited(_avisarALasTeles(cfg.eventoId));
    return guardada;
  }

  RealtimeChannel? _canalDelAviso;

  /// Les avisa a las teles que cambió la apariencia de [eventoId], para que la
  /// lean ya (25-nov-2026): `totem_config` no está en Realtime. Es el mismo
  /// aviso entre equipos que el del motor (`pulso_entre_equipos.dart`); sin
  /// suscribirse, va por REST. Que no salga no rompe nada: lo guardado ya está
  /// en la nube, y la tele la vuelve a leer al prepararse.
  Future<void> _avisarALasTeles(String eventoId) async {
    try {
      final canal = _canalDelAviso ??= _client.channel(kCanalDelPulso);
      await canal
          .sendBroadcastMessage(
            event: kEventoDelPulso,
            payload: avisoDeLaApariencia(
              origen: InstalacionId.valor ?? 'pc',
              eventoId: eventoId,
            ),
          )
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('El aviso de la apariencia a las teles no salió: $e');
    }
  }

  /// Los segundos de la llegada cambiados a mano esa noche (`TiemposAMano`):
  /// solo esas dos columnas, sin tocar lo demás de la config (otra PC pudo
  /// haber cambiado algo en Personalizar). Si el evento todavía no tiene fila,
  /// se crea con lo de siempre y estos segundos.
  ///
  /// Necesita las columnas de la 6.4.0 en la nube
  /// (`20261105100000_totem_config_llegada.sql`).
  Future<void> guardarTiempos(
    String eventoId, {
    required int nombre,
    required int camino,
  }) async {
    final filas = await _client
        .from('totem_config')
        .update({
          'llegada_nombre_seg': nombre,
          'llegada_camino_seg': camino,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': _client.auth.currentUser?.id,
        })
        .eq('evento_id', eventoId)
        .select('evento_id');
    if (filas.isEmpty) {
      await guardar(
        TotemConfig(
          eventoId: eventoId,
          llegadaNombreSeg: nombre,
          llegadaCaminoSeg: camino,
        ),
      );
    } else {
      unawaited(_avisarALasTeles(eventoId));
    }
  }

  /// Los nombres de las imágenes de un evento en el bucket: la foto del
  /// círculo y el fondo de "Tu fondo".
  static const portada = 'portada';
  static const fondo = 'fondo';

  /// Dónde va una imagen en el bucket.
  static String rutaDe(String eventoId, String nombre, String extension) =>
      '$eventoId/$nombre.${normalizarExtension(extension)}';

  /// Sube la portada del evento y devuelve su URL pública.
  ///
  /// Recibe **bytes** y no un path porque en web `PlatformFile.path` es siempre
  /// `null`; el resto del repo usa `.path` y por eso no funcionaría ahí.
  Future<String> subirImagen({
    required String eventoId,
    required Uint8List bytes,
    required String extension,
  }) =>
      _subir(eventoId: eventoId, bytes: bytes, extension: extension, nombre: portada);

  /// Sube el fondo de "Tu fondo" y devuelve su URL pública. Mismas reglas que
  /// la portada, en `<evento>/fondo.<ext>`.
  Future<String> subirFondo({
    required String eventoId,
    required Uint8List bytes,
    required String extension,
  }) =>
      _subir(eventoId: eventoId, bytes: bytes, extension: extension, nombre: fondo);

  Future<String> _subir({
    required String eventoId,
    required Uint8List bytes,
    required String extension,
    required String nombre,
  }) async {
    final ext = normalizarExtension(extension);
    final mime = mimeDe(ext);

    if (mime == null) {
      throw ArgumentError(
        'Formato no permitido (.$ext). Tiene que ser JPG, PNG o WEBP.',
      );
    }
    if (bytes.length > maxBytes) {
      throw ArgumentError('La imagen pesa más de 5 MB. Elegí una más liviana.');
    }

    // Path convenido en la migración: una portada (y un fondo) por evento.
    final path = rutaDe(eventoId, nombre, ext);

    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: mime),
        );

    // El path es fijo y con `upsert` la URL pública nunca cambia, así que sin
    // este parámetro el CDN de Supabase y el caché de `Image.network` seguirían
    // sirviendo la foto anterior: el usuario guarda y "no pasa nada".
    final url = _client.storage.from(bucket).getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Quita la portada del evento.
  Future<void> borrarImagen(String eventoId) => _borrar(eventoId, portada);

  /// Quita el fondo de "Tu fondo".
  Future<void> borrarFondo(String eventoId) => _borrar(eventoId, fondo);

  /// Se intentan todas las extensiones porque no sabemos con cuál se subió;
  /// `remove` no falla por un path que no existe.
  Future<void> _borrar(String eventoId, String nombre) async {
    final paths =
        tiposPermitidos.keys.map((ext) => rutaDe(eventoId, nombre, ext)).toList();
    await _client.storage.from(bucket).remove(paths);
  }
}
