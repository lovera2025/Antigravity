import 'dart:io';

/// **Sirve una página armada con `flutter build web`** desde una carpeta de la PC, por el
/// wifi del salón y sin internet. La usan las dos centrales: la de la puerta (la página
/// del celular, carpeta `puesto`) y la de la barra (la página del iPhone de la encargada
/// y del repositor, carpeta `barra_pagina`, 28-nov-2026).
///
/// Nunca sale de [raiz]: un tramo `.`, `..` o con barras o dos puntos da 404, igual que un
/// archivo que no está o una raíz que no hay.
abstract final class ServirArchivos {
  static const tipos = {
    'html': 'text/html; charset=utf-8',
    'js': 'application/javascript',
    'mjs': 'application/javascript',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'css': 'text/css',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
  };

  /// Lo que cambia con cada versión se pide de nuevo siempre; el resto (letras, el motor
  /// de dibujo) se guarda un día en el celular.
  static const sinGuardar = {'html', 'js', 'mjs', 'json'};

  /// El archivo de [raiz] que pide [pedido], o null si no se puede servir.
  static File? archivoDe(Directory? raiz, Uri pedido) {
    final partes = [
      for (final p in pedido.pathSegments)
        if (p.isNotEmpty) p,
    ];
    if (partes.isEmpty) partes.add('index.html');
    final valida = partes.every(
      (p) => p != '.' && p != '..' && !p.contains('/') && !p.contains(r'\') && !p.contains(':'),
    );
    if (raiz == null || !valida) return null;
    return File([raiz.path, ...partes].join(Platform.pathSeparator));
  }

  static Future<void> servir(HttpRequest pedido, Directory? raiz) async {
    final respuesta = pedido.response;
    final archivo = archivoDe(raiz, pedido.uri);
    if (archivo == null || !await archivo.exists()) {
      respuesta.statusCode = HttpStatus.notFound;
      await respuesta.close();
      return;
    }
    final nombre = archivo.path.split(Platform.pathSeparator).last.toLowerCase();
    final punto = nombre.lastIndexOf('.');
    final extension = punto < 0 ? '' : nombre.substring(punto + 1);
    respuesta.headers
      ..set(HttpHeaders.contentTypeHeader, tipos[extension] ?? 'application/octet-stream')
      ..set(HttpHeaders.cacheControlHeader, sinGuardar.contains(extension) ? 'no-cache' : 'max-age=86400');
    if (pedido.method == 'HEAD') {
      await respuesta.close();
      return;
    }
    await respuesta.addStream(archivo.openRead());
    await respuesta.close();
  }
}
