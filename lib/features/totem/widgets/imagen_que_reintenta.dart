import 'dart:async';

import 'package:flutter/material.dart';

import '../services/foto_guardada.dart';

/// Una imagen del tótem (la foto del evento) que **vuelve a intentar si no
/// cargó**.
///
/// La foto se baja una vez y queda en la PC. Si esa primera vez falla (el wifi
/// del salón), un `Image` común muestra lo que va en su lugar y no la pide más:
/// se quedaba con el logo toda la noche aunque volviera internet (revisión del
/// 13-nov). Esta la vuelve a pedir a los 15 y a los 30 segundos, y después cada
/// minuto, mientras siga a la vista ([esperaDeReintentoDeLaFoto]).
///
/// Mientras no carga se ve [siFalla], como antes. Una imagen que cargó no se
/// vuelve a pedir nunca.
class ImagenQueReintenta extends StatefulWidget {
  final ImageProvider imagen;
  final BoxFit fit;

  /// Lo que se ve si no carga: el logo, o nada.
  final Widget siFalla;

  const ImagenQueReintenta({
    super.key,
    required this.imagen,
    required this.fit,
    required this.siFalla,
  });

  @override
  State<ImagenQueReintenta> createState() => _ImagenQueReintentaState();
}

class _ImagenQueReintentaState extends State<ImagenQueReintenta> {
  int _intento = 0;
  Timer? _reintento;

  @override
  void didUpdateWidget(covariant ImagenQueReintenta anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.imagen != widget.imagen) {
      // Otra foto: se empieza de cero.
      _reintento?.cancel();
      _reintento = null;
      _intento = 0;
    }
  }

  @override
  void dispose() {
    _reintento?.cancel();
    super.dispose();
  }

  /// La imagen falló: se programa un intento más. Uno solo vivo.
  void _fallo() {
    if (_reintento != null) return;
    _reintento = Timer(esperaDeReintentoDeLaFoto(_intento), () {
      _reintento = null;
      if (!mounted) return;
      // Fuera del caché de imágenes, por si el fallo quedó guardado ahí; y otra
      // clave, para que `Image` la vuelva a pedir.
      unawaited(widget.imagen.evict());
      setState(() => _intento++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      key: ValueKey(_intento),
      image: widget.imagen,
      fit: widget.fit,
      errorBuilder: (_, _, _) {
        // Solo arma un reloj: no cambia nada de lo que se está dibujando.
        _fallo();
        return widget.siFalla;
      },
    );
  }
}
