import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    return guardada;
  }

  /// Sube la portada del evento y devuelve su URL pública.
  ///
  /// Recibe **bytes** y no un path porque en web `PlatformFile.path` es siempre
  /// `null`; el resto del repo usa `.path` y por eso no funcionaría ahí.
  Future<String> subirImagen({
    required String eventoId,
    required Uint8List bytes,
    required String extension,
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

    // Path convenido en la migración: una portada por evento.
    final path = '$eventoId/portada.$ext';

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
  ///
  /// Se intentan todas las extensiones porque no sabemos con cuál se subió;
  /// `remove` no falla por un path que no existe.
  Future<void> borrarImagen(String eventoId) async {
    final paths = tiposPermitidos.keys
        .map((ext) => '$eventoId/portada.$ext')
        .toList();
    await _client.storage.from(bucket).remove(paths);
  }
}
