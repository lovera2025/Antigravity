import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../totem/services/foto_guardada.dart';
import '../datos/barra_repositorio.dart';
import '../estilos/fotos_de_la_barra.dart';

/// Dónde se guardan en el equipo las fotos propias que suba el jefe (etapa 7):
/// `Documentos\Junior Eventos\imagenes_barra`, una por producto. Se bajan una vez y
/// después se ven sin internet, como la foto del tótem.
final fotosPropiasDeLaBarra = FotosDelTotem(
  carpeta: FotosDelTotem.carpetaEnDocumentos('imagenes_barra'),
  que: 'La foto del producto',
);

/// La foto de un producto, o null (la tarjeta muestra la inicial). En este orden:
/// 1. una foto propia que subió el jefe (`imagenUrl` con `http`): en la web desde
///    internet; en la PC y la tablet, la guardada en el equipo, **nunca
///    `NetworkImage`**, que sin internet no se ve;
/// 2. una de la biblioteca que eligió a mano (`biblioteca:<clave>`);
/// 3. la que sale de su nombre (`FotoDeLaBarra.para`): así se ve con foto aunque
///    nadie haya cargado ninguna.
ImageProvider? imagenDelProducto(ProductoBarra p) {
  final url = p.imagenUrl?.trim() ?? '';
  if (url.startsWith('http')) {
    if (kIsWeb) return NetworkImage(url);
    return FotoGuardada(url, eventoId: p.id, fotos: fotosPropiasDeLaBarra);
  }
  if (url.startsWith(FotoDeLaBarra.prefijo)) {
    final clave = url.substring(FotoDeLaBarra.prefijo.length).trim();
    if (FotoDeLaBarra.claves.contains(clave)) return AssetImage(FotoDeLaBarra.ruta(clave));
  }
  final clave = FotoDeLaBarra.para(p.nombre, p.categoria);
  return clave == null ? null : AssetImage(FotoDeLaBarra.ruta(clave));
}

/// La foto de cada producto en VENDER. Los tests la reemplazan para no leer archivos.
final imagenDelProductoProvider =
    Provider<ImageProvider? Function(ProductoBarra)>((ref) => imagenDelProducto);
