import '../../../models/totem_config.dart';

/// Los segundos de la llegada cambiados a mano la noche de la fiesta, desde
/// Recepción o desde el celular de la puerta (6.4.0, pedido del usuario: "deberían
/// estar a mano, el recepcionista a cargo debería poder").
///
/// Personalizar es para dejar la fiesta armada; esto es para la noche: vive en la
/// PC (anda sin internet), le llega a la tele al instante y se sube a la nube
/// cuando se puede. Mientras está, manda sobre lo guardado en Personalizar.
class TiemposAMano {
  /// Los segundos del nombre en grande.
  final int nombre;

  /// Los segundos del salón con el camino.
  final int camino;

  const TiemposAMano._(this.nombre, this.camino);

  /// Dentro de los topes de [TotemConfig].
  factory TiemposAMano({required int nombre, required int camino}) =>
      TiemposAMano._(
        nombre.clamp(
          TotemConfig.llegadaNombreMinimo,
          TotemConfig.llegadaNombreMaximo,
        ),
        camino.clamp(
          TotemConfig.llegadaCaminoMinimo,
          TotemConfig.llegadaCaminoMaximo,
        ),
      );

  /// Los que tiene [cfg]: de donde se parte al tocar − o +.
  factory TiemposAMano.de(TotemConfig cfg) =>
      TiemposAMano(nombre: cfg.llegadaNombreSeg, camino: cfg.llegadaCaminoSeg);

  /// [cfg] con estos segundos.
  TotemConfig aplicarA(TotemConfig cfg) =>
      cfg.copyWith(llegadaNombreSeg: nombre, llegadaCaminoSeg: camino);

  TiemposAMano conNombre(int s) => TiemposAMano(nombre: s, camino: camino);
  TiemposAMano conCamino(int s) => TiemposAMano(nombre: nombre, camino: s);

  Map<String, Object?> toJson() => {'n': nombre, 'c': camino};

  /// Null si no se entiende: de la red o del disco puede llegar cualquier cosa.
  static TiemposAMano? fromJson(Object? json) {
    if (json is! Map) return null;
    final n = json['n'];
    final c = json['c'];
    if (n is! num || c is! num) return null;
    return TiemposAMano(nombre: n.round(), camino: c.round());
  }

  @override
  bool operator ==(Object other) =>
      other is TiemposAMano && other.nombre == nombre && other.camino == camino;

  @override
  int get hashCode => Object.hash(nombre, camino);

  @override
  String toString() => 'TiemposAMano($nombre s + $camino s)';
}
