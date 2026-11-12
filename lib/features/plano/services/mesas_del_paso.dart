import '../modelo/armado_salon.dart';

/// Dónde está una mesa respecto del paso de los egresados.
class LugarEnElPaso {
  /// 1 es la pegada al paso; 2, la que tiene detrás; y así hacia afuera.
  final int linea;

  /// 1 es la fila más cercana al escenario.
  final int fila;

  /// 0: a la izquierda del paso (o encima); 1: a la derecha.
  final int lado;

  const LugarEnElPaso({
    required this.linea,
    required this.fila,
    required this.lado,
  });
}

/// Las mesas del salón, de la mejor a la peor según el paso de los egresados
/// (pedido del usuario, 12-nov-2026): la pasarela y su continuación hasta el
/// fondo. Primero toda la columna pegada al paso, de punta a punta; después la
/// que sigue hacia afuera; y así hasta el borde.
///
/// Sale del dibujo del salón (posiciones y sectores), sin familias y **sin
/// mirar ni cambiar ningún número de mesa**.
///
/// - **La hoja:** la que tiene la pasarela; si ninguna, la del escenario.
/// - **El eje:** la recta por el medio de la pasarela, a lo largo. Sin
///   pasarela, la que sale del medio del escenario hacia las mesas.
/// - **Fila:** las mesas a la misma distancia del escenario. Una mesa corrida a
///   mano en Acomodar sigue en su fila (se agrupan con medio diámetro de
///   margen).
/// - **Línea:** el puesto de la mesa en su fila y su lado, contando desde el
///   eje. Es el puesto y no los metros: donde la pasarela deja un hueco, la
///   primera mesa de la fila es primera línea igual.
/// - Las mesas de las otras hojas y las del pasto van al final, por número.
class MesasDelPaso {
  /// Todas las mesas del salón, de la mejor a la peor.
  final List<int> enOrden;
  final Map<int, LugarEnElPaso> _lugar;
  final Map<int, MesaPlano> _mesa;

  /// La hoja del paso.
  final String hoja;

  const MesasDelPaso._(this.enOrden, this._lugar, this._mesa, this.hoja);

  /// Dónde está la mesa. Null: no es de la hoja del paso, o es del pasto.
  LugarEnElPaso? lugar(int mesa) => _lugar[mesa];

  /// Cuántas mesas hay en esa línea.
  int enLaLinea(int linea) =>
      _lugar.values.where((l) => l.linea == linea).length;

  /// La que tiene detrás: la misma fila y el mismo lado, una línea más
  /// afuera. Null si es la última de su fila.
  int? detras(int mesa) {
    final l = _lugar[mesa];
    if (l == null) return null;
    for (final e in _lugar.entries) {
      final o = e.value;
      if (o.fila == l.fila && o.lado == l.lado && o.linea == l.linea + 1) {
        return e.key;
      }
    }
    return null;
  }

  /// De [libres], la más cercana a [mesa] de su mismo lado; si no hay, la más
  /// cercana de la hoja. Null si [libres] no tiene ninguna de la hoja.
  int? laMasCercana(int mesa, Iterable<int> libres) {
    final m = _mesa[mesa];
    final l = _lugar[mesa];
    if (m == null) return null;
    int? mejor;
    var puntaje = double.infinity;
    for (final n in libres) {
      final o = _mesa[n];
      final ol = _lugar[n];
      if (o == null || ol == null) continue;
      final dx = o.x - m.x, dy = o.y - m.y;
      // Del otro lado del paso queda lejos aunque esté cerca: la familia
      // quedaría partida por la pasarela.
      final otroLado = l != null && ol.lado != l.lado ? 1e12 : 0.0;
      final p = dx * dx + dy * dy + otroLado;
      if (p < puntaje) {
        puntaje = p;
        mejor = n;
      }
    }
    return mejor;
  }

  /// Null si el salón no tiene mesas, o no tiene pasarela ni escenario: sin
  /// eso no hay paso que medir.
  static MesasDelPaso? de(ArmadoSalon a) {
    if (a.mesas.isEmpty) return null;
    SectorPlano? pasarela;
    SectorPlano? escenario;
    String? hoja;
    for (final tipo in [TipoSector.pasarela, TipoSector.escenario]) {
      for (final h in a.hojas) {
        if (a.mesasDeHoja(h.id).every((m) => m.pasto)) continue;
        for (final s in a.sectoresDeHoja(h.id)) {
          if (s.tipo == tipo) {
            hoja = h.id;
            break;
          }
        }
        if (hoja != null) break;
      }
      if (hoja != null) break;
    }
    if (hoja == null) return null;
    for (final s in a.sectoresDeHoja(hoja)) {
      if (s.tipo == TipoSector.pasarela) pasarela ??= s;
      if (s.tipo == TipoSector.escenario) escenario ??= s;
    }
    final delPaso = [
      for (final m in a.mesasDeHoja(hoja))
        if (!m.pasto) m,
    ];
    if (delPaso.isEmpty) return null;

    // El medio de las mesas: dice para qué lado del escenario están.
    var cx = 0.0, cy = 0.0;
    for (final m in delPaso) {
      cx += m.x;
      cy += m.y;
    }
    cx /= delPaso.length;
    cy /= delPaso.length;

    // ¿El paso va de arriba abajo (por las y) o de costado (por las x)?
    final bool vertical;
    final double eje;
    if (pasarela != null) {
      vertical = pasarela.caja.alto >= pasarela.caja.ancho;
      eje = vertical ? pasarela.caja.centroX : pasarela.caja.centroY;
    } else {
      final e = escenario!.caja;
      vertical = (cy - e.centroY).abs() >= (cx - e.centroX).abs();
      eje = vertical ? e.centroX : e.centroY;
    }
    double aLoLargo(MesaPlano m) => vertical ? m.y : m.x;
    double alCostado(MesaPlano m) => vertical ? m.x : m.y;

    // Dónde está el escenario sobre el eje: de ahí se cuentan las filas. Sin
    // escenario, la punta de la pasarela más lejana a las mesas.
    final double origen;
    if (escenario != null) {
      origen = vertical ? escenario.caja.centroY : escenario.caja.centroX;
    } else {
      final p = pasarela!.caja;
      final medio = vertical ? cy : cx;
      final a0 = vertical ? p.y : p.x;
      final a1 = vertical ? p.abajo : p.derecha;
      origen = (a0 - medio).abs() >= (a1 - medio).abs() ? a0 : a1;
    }

    // Las filas: las mesas a la misma distancia del escenario.
    final porDistancia = [...delPaso]..sort((x, y) {
        final c = (aLoLargo(x) - origen)
            .abs()
            .compareTo((aLoLargo(y) - origen).abs());
        return c != 0 ? c : x.numero.compareTo(y.numero);
      });
    final filas = <List<MesaPlano>>[];
    double? ultima;
    for (final m in porDistancia) {
      final d = (aLoLargo(m) - origen).abs();
      if (ultima != null && (d - ultima).abs() < a.radio) {
        filas.last.add(m);
      } else {
        filas.add([m]);
      }
      ultima = d;
    }

    // La línea: el puesto en su fila y su lado, desde el eje hacia afuera. Una
    // mesa sobre el eje (donde la pasarela ya terminó y el medio se llenó)
    // cuenta del lado izquierdo, primera.
    final lugar = <int, LugarEnElPaso>{};
    final sobreElEje = a.radio * 0.5;
    for (var f = 0; f < filas.length; f++) {
      for (final lado in [0, 1]) {
        final suyas = [
          for (final m in filas[f])
            if ((alCostado(m) - eje > sobreElEje ? 1 : 0) == lado) m,
        ]..sort((x, y) {
            final c = (alCostado(x) - eje)
                .abs()
                .compareTo((alCostado(y) - eje).abs());
            return c != 0 ? c : x.numero.compareTo(y.numero);
          });
        for (var i = 0; i < suyas.length; i++) {
          lugar[suyas[i].numero] =
              LugarEnElPaso(linea: i + 1, fila: f + 1, lado: lado);
        }
      }
    }

    final delPasoEnOrden = [for (final m in delPaso) m.numero]..sort((x, y) {
        final lx = lugar[x]!, ly = lugar[y]!;
        var c = lx.linea.compareTo(ly.linea);
        if (c != 0) return c;
        c = lx.fila.compareTo(ly.fila);
        if (c != 0) return c;
        c = lx.lado.compareTo(ly.lado);
        return c != 0 ? c : x.compareTo(y);
      });
    final resto = [
      for (final m in a.mesas)
        if (!lugar.containsKey(m.numero)) m.numero,
    ]..sort();
    return MesasDelPaso._(
      [...delPasoEnOrden, ...resto],
      lugar,
      {for (final m in delPaso) m.numero: m},
      hoja,
    );
  }
}
