import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../models/totem_config.dart';

/// La foto del evento para el tótem: en la web, de internet como siempre; en
/// la PC, la guardada ([FotoGuardada]). Null si el evento no tiene foto.
ImageProvider? fotoDelEvento(TotemConfig cfg) {
  final url = cfg.imagenUrl;
  if (url == null) return null;
  if (kIsWeb) return NetworkImage(url);
  return FotoGuardada(url, eventoId: cfg.eventoId);
}

/// El fondo de "Tu fondo", como la foto: en la web, de internet; en la PC, el
/// guardado, **en su propia carpeta** ([FotosDelTotem.fondosEnLaPc]). Null si
/// el evento no tiene fondo.
ImageProvider? fondoDelEvento(TotemConfig cfg) {
  final url = cfg.fondoUrl;
  if (url == null) return null;
  if (kIsWeb) return NetworkImage(url);
  return FotoGuardada(
    url,
    eventoId: cfg.eventoId,
    fotos: FotosDelTotem.fondosEnLaPc,
  );
}

/// La foto del evento guardada en la PC (sección 5 de la 6.0.0).
///
/// Antes era `NetworkImage`: sin internet el tótem caía al logo. Ahora la foto
/// se baja una vez y queda en `Documentos\Junior Eventos\fotos_totem`. La
/// guardan el tótem la primera vez que la ve y Recepción al abrir el evento
/// con internet ("Lista para trabajar sin internet"). Si no hay foto en la PC
/// ni internet, la escena muestra el logo, como antes.
@immutable
class FotoGuardada extends ImageProvider<FotoGuardada> {
  final String url;
  final String eventoId;

  /// Dónde se guarda. Los tests ponen una carpeta temporal.
  final FotosDelTotem? fotos;

  const FotoGuardada(this.url, {required this.eventoId, this.fotos});

  @override
  Future<FotoGuardada> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<FotoGuardada>(this);

  @override
  ImageStreamCompleter loadImage(FotoGuardada key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _cargar(key, decode),
        scale: 1,
        debugLabel: key.url,
      );

  static Future<ui.Codec> _cargar(
    FotoGuardada key,
    ImageDecoderCallback decode,
  ) async {
    final fotos = key.fotos ?? FotosDelTotem.enLaPc;
    final bytes = await fotos.bytes(key.url, eventoId: key.eventoId);
    if (bytes == null) {
      throw StateError('${fotos.que} no está en la PC y no se pudo bajar');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is FotoGuardada &&
      other.url == url &&
      other.eventoId == eventoId &&
      identical(other.fotos, fotos);

  @override
  int get hashCode => Object.hash(url, eventoId, fotos);

  @override
  String toString() => 'FotoGuardada($url)';
}

/// Las fotos de los eventos en la PC: una por evento, la última que se vio.
///
/// Cada foto se guarda con el nombre de su dirección: cuando se cambia la
/// foto en Personalizar la dirección cambia (`?v=`), así que se baja la nueva
/// y se borra la vieja **recién cuando la nueva quedó guardada**. Sin
/// internet y sin la nueva, se usa la vieja: mejor la foto anterior que el
/// logo.
///
/// **Cada carpeta guarda una sola imagen por evento**: al guardar la nueva se
/// borran las otras, y sin internet se usa la última. Por eso el fondo de "Tu
/// fondo" va en otra carpeta ([fondosEnLaPc]): en la misma, guardar uno
/// borraba el otro, y sin internet el círculo podía mostrar el fondo.
class FotosDelTotem {
  FotosDelTotem({
    Future<Directory> Function()? carpeta,
    http.Client Function()? cliente,
    this.espera = const Duration(seconds: 20),
    this.que = 'La foto del evento',
  })  : _carpeta = carpeta ?? carpetaEnDocumentos(carpetaFotos),
        _cliente = cliente ?? http.Client.new;

  /// Las carpetas, dentro de `Documentos\Junior Eventos`.
  static const carpetaFotos = 'fotos_totem';
  static const carpetaFondos = 'fondos_totem';

  /// Las de la app: andan en la ventana principal y en la del tótem, que
  /// leen y escriben las mismas carpetas.
  static final enLaPc = FotosDelTotem();
  static final fondosEnLaPc = FotosDelTotem(
    carpeta: carpetaEnDocumentos(carpetaFondos),
    que: 'El fondo del tótem',
  );

  final Future<Directory> Function() _carpeta;
  final http.Client Function() _cliente;

  /// Cuánto se espera a que baje la foto.
  final Duration espera;

  /// Qué se guarda, para los avisos: "La foto del evento", "El fondo del
  /// tótem".
  final String que;

  /// Lo que se está bajando: dos pantallas que piden la misma foto a la vez
  /// la bajan una sola vez.
  final _enCurso = <String, Future<Uint8List?>>{};

  /// `Documentos\Junior Eventos\<nombre>`. Los tests le pasan otra carpeta de
  /// documentos.
  static Future<Directory> Function() carpetaEnDocumentos(
    String nombre, {
    Future<Directory> Function() documentos = getApplicationDocumentsDirectory,
  }) =>
      () async {
        final docs = await documentos();
        return Directory(
          '${docs.path}${Platform.pathSeparator}Junior Eventos'
          '${Platform.pathSeparator}$nombre',
        );
      };

  Future<Directory> _delEvento(String eventoId) async {
    final base = await _carpeta();
    // Solo letras, números y guiones: el id es un UUID, y nada más entra en
    // el nombre de una carpeta.
    final limpio = eventoId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '');
    return Directory('${base.path}${Platform.pathSeparator}$limpio');
  }

  static String _nombre(String url) =>
      '${sha1.convert(url.codeUnits).toString()}.foto';

  Future<File> _archivo(String url, String eventoId) async {
    final dir = await _delEvento(eventoId);
    return File('${dir.path}${Platform.pathSeparator}${_nombre(url)}');
  }

  /// Si esa foto, la de esa dirección, ya está en la PC.
  Future<bool> estaGuardada(String url, {required String eventoId}) async {
    try {
      return await (await _archivo(url, eventoId)).exists();
    } catch (_) {
      return false;
    }
  }

  /// La guarda si falta. Devuelve si quedó en la PC.
  Future<bool> guardar(String url, {required String eventoId}) async {
    if (await estaGuardada(url, eventoId: eventoId)) return true;
    await _bajar(url, eventoId);
    return estaGuardada(url, eventoId: eventoId);
  }

  /// La foto: la guardada, o la baja y la guarda; sin internet, la última que
  /// se guardó de ese evento. Null si no hay ninguna.
  Future<Uint8List?> bytes(String url, {required String eventoId}) async {
    try {
      final archivo = await _archivo(url, eventoId);
      if (await archivo.exists()) return await archivo.readAsBytes();
    } catch (e) {
      debugPrint('No se pudo leer lo guardado ($que): $e');
    }
    return await _bajar(url, eventoId) ?? await _laUltima(eventoId);
  }

  Future<Uint8List?> _bajar(String url, String eventoId) {
    final clave = '$eventoId|$url';
    // Con llaves: `=> _enCurso.remove(clave)` devolvería esta misma descarga,
    // y `whenComplete` se quedaría esperándose a sí misma para siempre.
    return _enCurso[clave] ??= _bajarYGuardar(url, eventoId).whenComplete(() {
      _enCurso.remove(clave);
    });
  }

  Future<Uint8List?> _bajarYGuardar(String url, String eventoId) async {
    final cliente = _cliente();
    try {
      final r = await cliente.get(Uri.parse(url)).timeout(espera);
      final tipo = r.headers['content-type'];
      if (r.statusCode != 200 ||
          r.bodyBytes.isEmpty ||
          (tipo != null && !tipo.startsWith('image/'))) {
        debugPrint('$que no bajó (${r.statusCode}, $tipo)');
        return null;
      }
      await _escribir(url, eventoId, r.bodyBytes);
      return r.bodyBytes;
    } catch (e) {
      debugPrint('$que no bajó: $e');
      return null;
    } finally {
      cliente.close();
    }
  }

  /// La escribe entera antes de darle su nombre (si se corta a la mitad no
  /// queda una foto rota) y, ya guardada, borra las otras de ese evento.
  Future<void> _escribir(String url, String eventoId, Uint8List bytes) async {
    try {
      final archivo = await _archivo(url, eventoId);
      await archivo.parent.create(recursive: true);
      final temporal = File('${archivo.path}.bajando');
      await temporal.writeAsBytes(bytes, flush: true);
      if (await archivo.exists()) await archivo.delete();
      await temporal.rename(archivo.path);
      await for (final otro in archivo.parent.list()) {
        if (otro is File && otro.path != archivo.path) {
          try {
            await otro.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('No se pudo guardar en la PC ($que): $e');
    }
  }

  /// La última foto guardada de ese evento, para cuando no baja la nueva.
  Future<Uint8List?> _laUltima(String eventoId) async {
    try {
      final dir = await _delEvento(eventoId);
      if (!await dir.exists()) return null;
      File? ultima;
      DateTime? cuando;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.foto')) continue;
        final m = await f.lastModified();
        if (cuando == null || m.isAfter(cuando)) {
          ultima = f;
          cuando = m;
        }
      }
      return await ultima?.readAsBytes();
    } catch (e) {
      debugPrint('No se pudo leer la última guardada ($que): $e');
      return null;
    }
  }
}
