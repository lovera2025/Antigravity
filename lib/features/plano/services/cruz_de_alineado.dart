import '../modelo/armado_salon.dart';

/// La cruz que se ve mientras se arrastra una mesa o un sector en Acomodar
/// (6.7.1, pedido del usuario el 12-nov-2026: "esa cruz en el mismo mouse
/// cuando mantenés apretado", para dejar las cosas alineadas).
///
/// Dos líneas que cruzan la hoja por el medio de lo que se arrastra. Cada una
/// se pone verde cuando queda **en línea** con el medio de otra cosa de la
/// hoja, o con el medio del playón (si la hoja trae su borde).
///
/// Es cuenta pura: no mueve nada. Quien arrastra ([SesionAcomodo]) usa
/// [loQueFalta] para dejar lo arrastrado justo en la línea cuando está a menos
/// de medio paso de ella: sin eso, moviéndose de a un cuarto de metro, podía
/// no caer nunca en línea con algo que no está en esa grilla.
class CruzDeAlineado {
  final String hoja;

  /// El medio de lo que se arrastra, en unidades del plano.
  final double x;
  final double y;

  /// La línea de arriba abajo pasa por el medio de otra cosa.
  final bool enLineaX;

  /// La línea de lado a lado pasa por el medio de otra cosa.
  final bool enLineaY;

  const CruzDeAlineado({
    required this.hoja,
    required this.x,
    required this.y,
    required this.enLineaX,
    required this.enLineaY,
  });

  /// El medio de la mesa o del sector que se arrastra, y su hoja.
  static ({String hoja, double x, double y})? _centro(
    ArmadoSalon a, {
    int? mesa,
    int? sector,
  }) {
    if (mesa != null) {
      final m = a.mesa(mesa);
      return m == null ? null : (hoja: m.hoja, x: m.x, y: m.y);
    }
    if (sector != null && sector >= 0 && sector < a.sectores.length) {
      final s = a.sectores[sector];
      return (hoja: s.hoja, x: s.caja.centroX, y: s.caja.centroY);
    }
    return null;
  }

  /// Los medios con los que se puede quedar en línea. Un sector: los otros
  /// sectores de la hoja y el medio del playón (no las mesas: son tantas que
  /// la cruz estaría casi siempre en verde). Una mesa: las otras mesas.
  static List<({double x, double y})> _otros(
    ArmadoSalon a,
    String hoja, {
    int? mesa,
    int? sector,
  }) {
    final h = a.hoja(hoja);
    final out = <({double x, double y})>[];
    // Una mesa se alinea con las otras mesas: su fila y su columna. Con el
    // medio de un sector no: quedaba "en línea" con el medio de la pasarela
    // en vez de en su fila.
    if (mesa != null) {
      for (final m in a.mesas) {
        if (m.hoja != hoja || m.numero == mesa) continue;
        out.add((x: m.x, y: m.y));
      }
      return out;
    }
    for (final (i, s) in a.sectores.indexed) {
      if (s.hoja != hoja || i == sector) continue;
      out.add((x: s.caja.centroX, y: s.caja.centroY));
    }
    // El medio del playón, solo si la hoja trae su borde. Sin borde no hay un
    // medio que valga: la caja de la hoja crece mientras se arrastra.
    final puntos = h?.contorno?.puntos ?? const [];
    if (puntos.length >= 3) {
      var x0 = puntos.first.x, x1 = puntos.first.x;
      var y0 = puntos.first.y, y1 = puntos.first.y;
      for (final p in puntos) {
        if (p.x < x0) x0 = p.x;
        if (p.x > x1) x1 = p.x;
        if (p.y < y0) y0 = p.y;
        if (p.y > y1) y1 = p.y;
      }
      out.add((x: (x0 + x1) / 2, y: (y0 + y1) / 2));
    }
    return out;
  }

  /// Lo que no llega a verse: menos que esto es "en línea".
  static double _casiNada(ArmadoSalon a) => a.radio * 0.004;

  /// La cruz de la [mesa] o del [sector], como está ahora. Null si no existe.
  static CruzDeAlineado? de(ArmadoSalon a, {int? mesa, int? sector}) {
    final c = _centro(a, mesa: mesa, sector: sector);
    if (c == null) return null;
    final casi = _casiNada(a);
    var enX = false, enY = false;
    for (final o in _otros(a, c.hoja, mesa: mesa, sector: sector)) {
      if ((o.x - c.x).abs() <= casi) enX = true;
      if ((o.y - c.y).abs() <= casi) enY = true;
    }
    return CruzDeAlineado(
      hoja: c.hoja,
      x: c.x,
      y: c.y,
      enLineaX: enX,
      enLineaY: enY,
    );
  }

  /// Cuánto hay que correr la [mesa] o el [sector] para que quede justo en
  /// línea con lo más cercano, en cada sentido. Cero si no hay nada a menos de
  /// [margen] (en unidades del plano), o si ya está.
  static ({double dx, double dy}) loQueFalta(
    ArmadoSalon a, {
    int? mesa,
    int? sector,
    required double margen,
  }) {
    final c = _centro(a, mesa: mesa, sector: sector);
    if (c == null) return (dx: 0, dy: 0);
    double? dx, dy;
    for (final o in _otros(a, c.hoja, mesa: mesa, sector: sector)) {
      final fx = o.x - c.x, fy = o.y - c.y;
      if (fx.abs() <= margen && (dx == null || fx.abs() < dx.abs())) dx = fx;
      if (fy.abs() <= margen && (dy == null || fy.abs() < dy.abs())) dy = fy;
    }
    return (dx: dx ?? 0, dy: dy ?? 0);
  }
}
