import 'package:flutter/material.dart';

/// Identidad visual del tótem para un evento puntual.
///
/// Si un evento no tiene fila en `totem_config`, [TotemConfig.defaults]
/// devuelve los textos y el dorado de siempre.
class TotemConfig {
  /// Dorado histórico de la app.
  static const Color acentoPorDefecto = Color(0xFFD4AF37);

  final String eventoId;
  final String titulo;
  final String subtitulo;
  final String mensajeBienvenida;
  final String mensajeQr;
  final String? imagenUrl;
  final Color colorAcento;

  /// En un evento masivo, si la bienvenida muestra la música que eligió cada
  /// alumno. Prendida salvo que alguien la apague en Personalizar: vacía en la
  /// nube (una fila de antes de la 6.0.0) también cuenta como prendida.
  final bool mostrarMusica;

  // ── La foto del evento (6.2.1) ───────────────────────────────────────────
  //
  // En la espera, la foto (o el logo de la empresa, sin foto) va arriba del
  // título. Desde la 6.2.1 se puede sacar, cambiar de forma y agrandar. Las tres
  // vacías en la nube (una fila de antes) son lo de siempre: la foto, en
  // círculo y al 100 %.

  /// Si se muestra. Se apaga cuando el fondo ya trae el logo y la pantalla
  /// tiene que quedar limpia. Vale también en Póster, donde la foto es el
  /// fondo: sin ella van las luces.
  final bool mostrarFoto;

  /// La forma (`circulo`, `corazon`, `tal_cual`, …; ver `FormaFoto`), tal como
  /// vino. Null: el círculo.
  final String? fotoForma;

  /// El tamaño, en % del de siempre, de [fotoTamanoMinimo] a
  /// [fotoTamanoMaximo]. En Póster no se usa.
  final int fotoTamano;

  /// El tamaño de las frases de la espera (el título, el subtítulo, el saludo
  /// y el QR), en % del de siempre, de [textoTamanoMinimo] a
  /// [textoTamanoMaximo]. En Póster no se usa.
  final int textoTamano;

  /// Dónde van juntas la foto y las frases de la espera, para que no pisen el
  /// logo o lo importante del fondo: de -100 (a la izquierda, arriba) a 100 (a
  /// la derecha, abajo), dentro del lugar que deja cada apariencia. 0 (o vacía
  /// en la nube): al medio, como siempre. Van juntas, así la foto nunca tapa
  /// las frases. En Póster no se usa: ahí las frases van abajo, sobre la foto.
  final int ubicacionX;
  final int ubicacionY;

  /// La apariencia elegida en Personalizar (`neon`, `cristal`, `poster`,
  /// `gala` o `tu_fondo`, ver `EstiloTotem`). Null: la del tipo de evento.
  final String? estilo;

  // ── "Tu fondo" ────────────────────────────────────────────────────────────
  //
  // La quinta apariencia: una imagen propia de fondo, con su animación, sus
  // efectos y sus colores. La receta la arma la imagen al guardar
  // (`LecturaDelFondo`) y se guarda entera, así la PC y el tótem por el
  // navegador muestran lo mismo sin volver a leerla. Lo que esta versión no
  // conoce (una animación o un efecto nuevos) se guarda como vino, como
  // `estilo`: si no, guardar Personalizar pisaría lo que eligió una más nueva.

  /// La imagen del fondo, con `?v=`. Null: sin fondo.
  final String? fondoUrl;

  /// Si la receta sale de la imagen ("Automático · según la imagen"). Vacía
  /// en la nube = automático.
  final bool fondoAutomatico;

  /// La animación de la imagen (`acercarse`, `ondular`, …; ver
  /// `AnimacionFondo`), tal como vino. Null: la de siempre.
  final String? fondoAnimacion;

  /// Los efectos que van encima (`destellos`, `bruma`, …; ver `EfectoFondo`),
  /// tal como vinieron. Vacía: sin efectos; null: los de siempre.
  final List<String>? fondoEfectos;

  /// Cuánto se mueve la imagen, de 0 a 100.
  final int fondoIntensidad;

  /// Cuánto se notan los efectos, de 0 a 100.
  final int fondoIntensidadEfectos;

  /// Cuánto se oscurece la imagen para que se lea, de 0 a 80.
  final int fondoOscurecer;

  /// Los tres colores sacados de la imagen: el brillo (marco, título, borde
  /// del círculo), el saludo y la tarjeta de la llegada. Null: salen del color
  /// del evento.
  final List<Color>? fondoPaleta;

  /// Hacia dónde va la animación: lo importante de la imagen, de 0 a 1 en
  /// cada eje. Null: el centro.
  final Offset? fondoFoco;

  /// Las letras de "Tu fondo" (`clasica`, `suave`, `fiesta`, `moderna`; ver
  /// `LetrasFondo`), tal como vinieron. Null: las de siempre.
  final String? fondoLetras;

  /// Qué tan clara es la imagen, de 0 (negra) a 100 (blanca). Con una imagen
  /// clara y poco oscurecida el texto va oscuro. Null: oscura.
  final int? fondoLuz;

  final DateTime? updatedAt;

  /// El saludo de siempre. Si nadie lo cambió y entra una familia, se dice
  /// en plural.
  static const saludoPorDefecto = '¡Bienvenido!';

  const TotemConfig({
    required this.eventoId,
    this.titulo = 'JUNIOR EVENTOS',
    this.subtitulo = '',
    this.mensajeBienvenida = saludoPorDefecto,
    this.mensajeQr = 'ESCANEÁ PARA INGRESAR',
    this.imagenUrl,
    this.colorAcento = acentoPorDefecto,
    this.mostrarMusica = true,
    this.mostrarFoto = true,
    this.fotoForma,
    this.fotoTamano = fotoTamanoPorDefecto,
    this.textoTamano = textoTamanoPorDefecto,
    this.ubicacionX = 0,
    this.ubicacionY = 0,
    this.estilo,
    this.fondoUrl,
    this.fondoAutomatico = true,
    this.fondoAnimacion,
    this.fondoEfectos,
    this.fondoIntensidad = intensidadPorDefecto,
    this.fondoIntensidadEfectos = intensidadEfectosPorDefecto,
    this.fondoOscurecer = oscurecerPorDefecto,
    this.fondoPaleta,
    this.fondoFoco,
    this.fondoLetras,
    this.fondoLuz,
    this.updatedAt,
  });

  /// El tope de la foto es el que deja el ancho de la pantalla con su margen:
  /// al 300 % mide más de la mitad del ancho de una tele vertical. Si con los
  /// textos no entra, la espera se achica entera (`Centrado`): nunca se corta.
  static const fotoTamanoMinimo = 50;
  static const fotoTamanoMaximo = 300;
  static const fotoTamanoPorDefecto = 100;

  /// Las frases, del 50 % al doble.
  static const textoTamanoMinimo = 50;
  static const textoTamanoMaximo = 200;
  static const textoTamanoPorDefecto = 100;

  static const intensidadPorDefecto = 40;
  static const intensidadEfectosPorDefecto = 50;
  static const oscurecerPorDefecto = 30;

  /// El oscurecido más fuerte: más, y la imagen ya no se ve.
  static const oscurecerMaximo = 80;

  /// Valores idénticos a los que hoy están escritos en el código.
  factory TotemConfig.defaults(String eventoId) =>
      TotemConfig(eventoId: eventoId);

  factory TotemConfig.fromJson(Map<String, dynamic> json) {
    String texto(String clave, String siVacio) {
      final v = json[clave] as String?;
      if (v == null || v.trim().isEmpty) return siVacio;
      return v;
    }

    final imagen = json['imagen_url'] as String?;
    final estilo = json['estilo'];

    /// Un texto con algo, o null.
    String? crudo(String clave) {
      final v = json[clave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    /// Un número entero acotado; vacío o basura, [siVacio].
    int entero(String clave, int siVacio, int maximo) {
      final v = json[clave];
      final n = v is num ? v.round() : int.tryParse('${v ?? ''}'.trim());
      return n == null ? siVacio : n.clamp(0, maximo);
    }

    final efectos = json['fondo_efectos'];
    final luz = json['fondo_luz'];

    return TotemConfig(
      eventoId: json['evento_id'] as String,
      titulo: texto('titulo', 'JUNIOR EVENTOS'),
      subtitulo: texto('subtitulo', ''),
      mensajeBienvenida: texto('mensaje_bienvenida', saludoPorDefecto),
      mensajeQr: texto('mensaje_qr', 'ESCANEÁ PARA INGRESAR'),
      imagenUrl: (imagen == null || imagen.trim().isEmpty) ? null : imagen,
      colorAcento: parseHex(json['color_acento'] as String?),
      mostrarMusica: json['mostrar_musica'] != false,
      mostrarFoto: json['mostrar_foto'] != false,
      fotoForma: crudo('foto_forma'),
      fotoTamano: entero(
        'foto_tamano',
        fotoTamanoPorDefecto,
        fotoTamanoMaximo,
      ).clamp(fotoTamanoMinimo, fotoTamanoMaximo),
      textoTamano: entero(
        'texto_tamano',
        textoTamanoPorDefecto,
        textoTamanoMaximo,
      ).clamp(textoTamanoMinimo, textoTamanoMaximo),
      ubicacionX: _ubicacionDe(json['ubicacion_x']),
      ubicacionY: _ubicacionDe(json['ubicacion_y']),
      estilo: estilo is String && estilo.trim().isNotEmpty ? estilo.trim() : null,
      fondoUrl: crudo('fondo_url'),
      fondoAutomatico: json['fondo_automatico'] != false,
      fondoAnimacion: crudo('fondo_animacion'),
      fondoEfectos: efectos is String
          ? [
              for (final e in efectos.split(','))
                if (e.trim().isNotEmpty) e.trim(),
            ]
          : null,
      fondoIntensidad: entero('fondo_intensidad', intensidadPorDefecto, 100),
      fondoIntensidadEfectos: entero(
        'fondo_intensidad_efectos',
        intensidadEfectosPorDefecto,
        100,
      ),
      fondoOscurecer:
          entero('fondo_oscurecer', oscurecerPorDefecto, oscurecerMaximo),
      fondoPaleta: leerPaleta(json['fondo_paleta'] as String?),
      fondoFoco: leerFoco(json['fondo_foco'] as String?),
      fondoLetras: crudo('fondo_letras'),
      fondoLuz: luz == null ? null : entero('fondo_luz', 0, 100),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  /// Dónde va lo de la espera, acotado; vacío o basura, al medio.
  static int _ubicacionDe(Object? v) {
    final n = v is num ? v.round() : int.tryParse('${v ?? ''}'.trim());
    return (n ?? 0).clamp(-100, 100);
  }

  Map<String, dynamic> toJson() => {
        'evento_id': eventoId,
        'titulo': titulo,
        'subtitulo': subtitulo,
        'mensaje_bienvenida': mensajeBienvenida,
        'mensaje_qr': mensajeQr,
        'imagen_url': imagenUrl,
        'color_acento': colorAcentoHex,
        // Necesita la columna en la nube (SQL de la 6.0.0,
        // `20261014120000_totem_config_estilo_y_musica.sql`): sin ella,
        // guardar Personalizar falla. Se corre antes de instalar.
        'mostrar_musica': mostrarMusica,
        // Las de la foto necesitan sus columnas en la nube (SQL de la 6.2.1,
        // `20261023200000_totem_config_foto.sql`): sin ellas, guardar
        // Personalizar falla. Se corre antes de instalar y de publicar la web.
        'mostrar_foto': mostrarFoto,
        'foto_forma': fotoForma,
        'foto_tamano': fotoTamano.clamp(fotoTamanoMinimo, fotoTamanoMaximo),
        'texto_tamano': textoTamano.clamp(textoTamanoMinimo, textoTamanoMaximo),
        'ubicacion_x': ubicacionX.clamp(-100, 100),
        'ubicacion_y': ubicacionY.clamp(-100, 100),
        'estilo': estilo,
        // Las de "Tu fondo" necesitan sus columnas en la nube (SQL
        // `20261023120000_totem_config_tu_fondo.sql`): sin ellas, guardar
        // Personalizar falla. Se corre antes de instalar y de publicar la web.
        'fondo_url': fondoUrl,
        'fondo_automatico': fondoAutomatico,
        'fondo_animacion': fondoAnimacion,
        'fondo_efectos': fondoEfectos?.join(','),
        'fondo_intensidad': fondoIntensidad.clamp(0, 100),
        'fondo_intensidad_efectos': fondoIntensidadEfectos.clamp(0, 100),
        'fondo_oscurecer': fondoOscurecer.clamp(0, oscurecerMaximo),
        'fondo_paleta': paletaATexto(fondoPaleta),
        'fondo_foco': focoATexto(fondoFoco),
        'fondo_letras': fondoLetras,
        'fondo_luz': fondoLuz?.clamp(0, 100),
        'updated_at': updatedAt?.toIso8601String(),
      };

  TotemConfig copyWith({
    String? titulo,
    String? subtitulo,
    String? mensajeBienvenida,
    String? mensajeQr,
    String? imagenUrl,
    bool limpiarImagen = false,
    Color? colorAcento,
    bool? mostrarMusica,
    bool? mostrarFoto,
    String? fotoForma,
    int? fotoTamano,
    int? textoTamano,
    int? ubicacionX,
    int? ubicacionY,
    String? estilo,
    bool limpiarEstilo = false,
    String? fondoUrl,
    bool limpiarFondo = false,
    bool? fondoAutomatico,
    String? fondoAnimacion,
    List<String>? fondoEfectos,
    int? fondoIntensidad,
    int? fondoIntensidadEfectos,
    int? fondoOscurecer,
    List<Color>? fondoPaleta,
    Offset? fondoFoco,
    String? fondoLetras,
    int? fondoLuz,
  }) {
    return TotemConfig(
      eventoId: eventoId,
      titulo: titulo ?? this.titulo,
      subtitulo: subtitulo ?? this.subtitulo,
      mensajeBienvenida: mensajeBienvenida ?? this.mensajeBienvenida,
      mensajeQr: mensajeQr ?? this.mensajeQr,
      imagenUrl: limpiarImagen ? null : (imagenUrl ?? this.imagenUrl),
      colorAcento: colorAcento ?? this.colorAcento,
      mostrarMusica: mostrarMusica ?? this.mostrarMusica,
      mostrarFoto: mostrarFoto ?? this.mostrarFoto,
      fotoForma: fotoForma ?? this.fotoForma,
      fotoTamano: (fotoTamano ?? this.fotoTamano)
          .clamp(fotoTamanoMinimo, fotoTamanoMaximo),
      textoTamano: (textoTamano ?? this.textoTamano)
          .clamp(textoTamanoMinimo, textoTamanoMaximo),
      ubicacionX: (ubicacionX ?? this.ubicacionX).clamp(-100, 100),
      ubicacionY: (ubicacionY ?? this.ubicacionY).clamp(-100, 100),
      estilo: limpiarEstilo ? null : (estilo ?? this.estilo),
      // Sin la imagen, la receta no se borra: no molesta, y si se vuelve a
      // cargar un fondo se arma otra.
      fondoUrl: limpiarFondo ? null : (fondoUrl ?? this.fondoUrl),
      fondoAutomatico: fondoAutomatico ?? this.fondoAutomatico,
      fondoAnimacion: fondoAnimacion ?? this.fondoAnimacion,
      fondoEfectos: fondoEfectos ?? this.fondoEfectos,
      fondoIntensidad: (fondoIntensidad ?? this.fondoIntensidad).clamp(0, 100),
      fondoIntensidadEfectos:
          (fondoIntensidadEfectos ?? this.fondoIntensidadEfectos).clamp(0, 100),
      fondoOscurecer:
          (fondoOscurecer ?? this.fondoOscurecer).clamp(0, oscurecerMaximo),
      fondoPaleta: fondoPaleta ?? this.fondoPaleta,
      fondoFoco: fondoFoco ?? this.fondoFoco,
      fondoLetras: fondoLetras ?? this.fondoLetras,
      fondoLuz: (fondoLuz ?? this.fondoLuz)?.clamp(0, 100),
      updatedAt: updatedAt,
    );
  }

  /// Esta config con todo lo de "Tu fondo" de [otra]. Personalizar arma la
  /// config campo por campo, y un campo que falte se borra en la nube: lo del
  /// fondo que no se tocó viaja así.
  TotemConfig conFondoDe(TotemConfig otra) => TotemConfig(
        eventoId: eventoId,
        titulo: titulo,
        subtitulo: subtitulo,
        mensajeBienvenida: mensajeBienvenida,
        mensajeQr: mensajeQr,
        imagenUrl: imagenUrl,
        colorAcento: colorAcento,
        mostrarMusica: mostrarMusica,
        mostrarFoto: mostrarFoto,
        fotoForma: fotoForma,
        fotoTamano: fotoTamano,
        textoTamano: textoTamano,
        ubicacionX: ubicacionX,
        ubicacionY: ubicacionY,
        estilo: estilo,
        fondoUrl: otra.fondoUrl,
        fondoAutomatico: otra.fondoAutomatico,
        fondoAnimacion: otra.fondoAnimacion,
        fondoEfectos: otra.fondoEfectos,
        fondoIntensidad: otra.fondoIntensidad,
        fondoIntensidadEfectos: otra.fondoIntensidadEfectos,
        fondoOscurecer: otra.fondoOscurecer,
        fondoPaleta: otra.fondoPaleta,
        fondoFoco: otra.fondoFoco,
        fondoLetras: otra.fondoLetras,
        fondoLuz: otra.fondoLuz,
        updatedAt: updatedAt,
      );

  // ── La paleta y el foco, como texto ─────────────────────────────────────────

  /// `#RRGGBB,#RRGGBB,#RRGGBB`: los tres colores, o null si falta alguno o
  /// alguno no es un color.
  static List<Color>? leerPaleta(String? texto) {
    if (texto == null) return null;
    final partes = texto.split(',').map((p) => p.trim()).toList();
    if (partes.length != 3) return null;
    final colores = <Color>[];
    for (final p in partes) {
      final limpio = p.replaceFirst('#', '');
      if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(limpio)) return null;
      colores.add(Color(0xFF000000 | int.parse(limpio, radix: 16)));
    }
    return colores;
  }

  static String? paletaATexto(List<Color>? paleta) {
    if (paleta == null || paleta.length != 3) return null;
    return paleta.map(hexDe).join(',');
  }

  /// `x,y`, cada uno de 0 a 1. Null si no se entiende.
  static Offset? leerFoco(String? texto) {
    if (texto == null) return null;
    final partes = texto.split(',');
    if (partes.length != 2) return null;
    final x = double.tryParse(partes[0].trim());
    final y = double.tryParse(partes[1].trim());
    if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
    return Offset(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
  }

  static String? focoATexto(Offset? foco) => foco == null
      ? null
      : '${foco.dx.clamp(0.0, 1.0).toStringAsFixed(3)},'
          '${foco.dy.clamp(0.0, 1.0).toStringAsFixed(3)}';

  // ── Color ─────────────────────────────────────────────────────────────────

  /// Acepta `#RRGGBB`, `RRGGBB` o `#AARRGGBB`. Ante cualquier basura devuelve
  /// el dorado, que es lo que corresponde para no romper la pantalla.
  static Color parseHex(String? hex) {
    if (hex == null) return acentoPorDefecto;
    var limpio = hex.trim().replaceFirst('#', '');
    if (limpio.length == 6) limpio = 'FF$limpio';
    if (limpio.length != 8) return acentoPorDefecto;
    final valor = int.tryParse(limpio, radix: 16);
    return valor == null ? acentoPorDefecto : Color(valor);
  }

  String get colorAcentoHex => hexDe(colorAcento);

  /// `#RRGGBB`, sin la transparencia.
  static String hexDe(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
