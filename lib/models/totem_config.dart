import 'package:flutter/material.dart';

/// Identidad visual del tótem para un evento puntual.
///
/// Si un evento no tiene fila en `totem_config`, [TotemConfig.defaults]
/// devuelve **exactamente** los literales que hoy están hardcodeados en
/// `totem_display.dart` y `totem_panel.dart`, así que la pantalla se ve igual
/// que siempre y no hay regresión.
class TotemConfig {
  /// Dorado histórico de la app (`_gold` en totem_display.dart).
  static const Color acentoPorDefecto = Color(0xFFD4AF37);

  /// Gradiente violeta del panel "YA LLEGARON" tal como está hoy.
  static const List<Color> _panelPorDefecto = [
    Color(0xFF1A0A2E),
    Color(0xFF0D0618),
    Color(0xFF080808),
  ];

  /// Gradiente violeta de la tarjeta de bienvenida tal como está hoy.
  static const List<Color> _cardPorDefecto = [
    Color(0xFF1C0F35),
    Color(0xFF0C0518),
  ];

  final String eventoId;
  final String titulo;
  final String subtitulo;
  final String mensajeBienvenida;
  final String mensajeQr;
  final String? imagenUrl;
  final Color colorAcento;
  final DateTime? updatedAt;

  const TotemConfig({
    required this.eventoId,
    this.titulo = 'JUNIOR EVENTOS',
    this.subtitulo = '',
    this.mensajeBienvenida = '¡Bienvenido!',
    this.mensajeQr = 'ESCANEÁ PARA INGRESAR',
    this.imagenUrl,
    this.colorAcento = acentoPorDefecto,
    this.updatedAt,
  });

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

    return TotemConfig(
      eventoId: json['evento_id'] as String,
      titulo: texto('titulo', 'JUNIOR EVENTOS'),
      subtitulo: texto('subtitulo', ''),
      mensajeBienvenida: texto('mensaje_bienvenida', '¡Bienvenido!'),
      mensajeQr: texto('mensaje_qr', 'ESCANEÁ PARA INGRESAR'),
      imagenUrl: (imagen == null || imagen.trim().isEmpty) ? null : imagen,
      colorAcento: parseHex(json['color_acento'] as String?),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'evento_id': eventoId,
        'titulo': titulo,
        'subtitulo': subtitulo,
        'mensaje_bienvenida': mensajeBienvenida,
        'mensaje_qr': mensajeQr,
        'imagen_url': imagenUrl,
        'color_acento': colorAcentoHex,
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
  }) {
    return TotemConfig(
      eventoId: eventoId,
      titulo: titulo ?? this.titulo,
      subtitulo: subtitulo ?? this.subtitulo,
      mensajeBienvenida: mensajeBienvenida ?? this.mensajeBienvenida,
      mensajeQr: mensajeQr ?? this.mensajeQr,
      imagenUrl: limpiarImagen ? null : (imagenUrl ?? this.imagenUrl),
      colorAcento: colorAcento ?? this.colorAcento,
      updatedAt: updatedAt,
    );
  }

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

  String get colorAcentoHex {
    final rgb = colorAcento.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  bool get usaAcentoPorDefecto =>
      colorAcento.toARGB32() == acentoPorDefecto.toARGB32();

  /// Fondo del panel "YA LLEGARON".
  ///
  /// Con el dorado de siempre devuelve el violeta original, para que un tótem
  /// sin configurar se vea exactamente como hoy. Con un acento elegido, deriva
  /// el fondo de ese tono: si el acento es rosa, el panel deja de ser violeta.
  List<Color> get gradientePanel {
    if (usaAcentoPorDefecto) return _panelPorDefecto;
    final base = HSLColor.fromColor(colorAcento);
    return [
      base.withSaturation(0.52).withLightness(0.11).toColor(),
      base.withSaturation(0.48).withLightness(0.05).toColor(),
      const Color(0xFF080808),
    ];
  }

  /// Fondo de la tarjeta de bienvenida. Misma lógica que [gradientePanel].
  List<Color> get gradienteCard {
    if (usaAcentoPorDefecto) return _cardPorDefecto;
    final base = HSLColor.fromColor(colorAcento);
    return [
      base.withSaturation(0.55).withLightness(0.13).toColor(),
      base.withSaturation(0.50).withLightness(0.05).toColor(),
    ];
  }

  /// Variante suave del acento, para bordes y resplandores.
  Color acentoConAlpha(double alpha) => colorAcento.withValues(alpha: alpha);
}
