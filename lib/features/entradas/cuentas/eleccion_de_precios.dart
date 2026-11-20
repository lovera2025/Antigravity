import '../datos/config_entradas.dart';
import 'precio_de_entradas.dart';

/// Lo que se vende ahora en una fiesta: lo que el jefe elige arriba de PRECIOS.
enum QueSeVende { anticipada, general }

/// PRECIOS (6.9.3): primero "¿Qué se vende ahora? Anticipada · General" y
/// después sus precios, **sin nada opcional**. Sin pantalla ni base: lo que
/// la pantalla muestra al abrir ([EleccionDePrecios.leer]), lo que falta para
/// guardar ([loQueFalta]) y cómo queda en `entradas_config` ([enColumnas]).
///
/// **Lo elegido no se guarda en ningún lado: sale de las tres columnas de
/// siempre.** La General es `valor_entrada`; la anticipada,
/// `precio_anticipada` y `anticipada_hasta`. Se lee con la misma regla que
/// cobra ([PrecioDeEntradas.rigeLaAnticipada]), así:
/// - una PC o una tablet con la 6.9.x lee las mismas columnas y cobra lo mismo,
///   sin SQL ni migración;
/// - **la anticipada termina sola en su fecha** (decisión del usuario, 20-nov),
///   también en una tablet sin internet: cada equipo mira su reloj, no espera
///   que le llegue un cambio.
///
/// **Con la anticipada se pide también la General:** sin `valor_entrada` la
/// fiesta no tiene precio (`ConfigEntradas.tienePrecio`), una 6.9.x no abre la
/// caja, y la mesa adicional no tiene de dónde sacar el suyo: su descuento va
/// siempre sobre la General ([PrecioDeEntradas.deLugar]).
class EleccionDePrecios {
  /// Null: todavía no se eligió (la fiesta no tiene precio).
  final QueSeVende? queSeVende;

  /// El precio de la General (`valor_entrada`).
  final double? general;

  /// El precio de la anticipada. Solo con [QueSeVende.anticipada].
  final double? anticipada;

  /// El último día de la anticipada, `AAAA-MM-DD`, inclusive. Solo con
  /// [QueSeVende.anticipada].
  final String? hasta;

  /// El descuento de las entradas de la mesa adicional y las sillas extra.
  /// **Null: el casillero quedó vacío, y vacío no vale 0.**
  final double? descuentoLugaresPct;

  /// El recargo por pagar por transferencia. Null: vacío, como arriba.
  final double? recargoPct;

  /// Si quien vende puede poner descuentos a mano.
  final bool descuentoAMano;

  /// La anticipada guardada que ya terminó (`AAAA-MM-DD`): no se vuelve a
  /// ofrecer, solo se dice ([notaDeLaAnticipada]).
  final String? anticipadaTermino;

  const EleccionDePrecios({
    this.queSeVende,
    this.general,
    this.anticipada,
    this.hasta,
    this.descuentoLugaresPct,
    this.recargoPct,
    this.descuentoAMano = false,
    this.anticipadaTermino,
  });

  /// Lo que PRECIOS muestra al abrir, con la config guardada ([c], null si la
  /// fiesta no tiene ninguna) y el día de hoy en Argentina ([hoyAr]):
  /// - sin precio, **nada elegido**;
  /// - si hoy rige la anticipada, ANTICIPADA con sus tres precios;
  /// - si no, GENERAL. **Una anticipada que ya terminó se ve como GENERAL**, con
  ///   la nota "La anticipada terminó el dd/mm", y no se ofrece de nuevo: una
  ///   anticipada nueva se escribe a mano.
  ///
  /// El día de la anticipada, si no hay una que rija, es el que propone
  /// [diaPropuesto] con la fecha de la fiesta ([fiesta]).
  factory EleccionDePrecios.leer(
    ConfigEntradas? c,
    DateTime hoyAr, {
    DateTime? fiesta,
  }) {
    final propuesto = diaPropuesto(fiesta, hoyAr);
    final pct =
        c?.descuentoLugaresPct ?? ConfigEntradas.kDescuentoDeLosLugares;
    final recargo = c?.recargoPct ?? 0;
    final aMano = c?.descuentoAMano ?? false;
    if (c == null || !c.tienePrecio) {
      return EleccionDePrecios(
        hasta: propuesto,
        descuentoLugaresPct: pct,
        recargoPct: recargo,
        descuentoAMano: aMano,
      );
    }
    if (PrecioDeEntradas.rigeLaAnticipada(c, hoyAr)) {
      return EleccionDePrecios(
        queSeVende: QueSeVende.anticipada,
        general: c.valorEntrada,
        anticipada: c.precioAnticipada,
        hasta: c.anticipadaHasta,
        descuentoLugaresPct: pct,
        recargoPct: recargo,
        descuentoAMano: aMano,
      );
    }
    return EleccionDePrecios(
      queSeVende: QueSeVende.general,
      general: c.valorEntrada,
      hasta: propuesto,
      descuentoLugaresPct: pct,
      recargoPct: recargo,
      descuentoAMano: aMano,
      // Completa y sin regir hoy: ya pasó su día.
      anticipadaTermino: c.tieneAnticipada ? c.anticipadaHasta : null,
    );
  }

  /// El día que se propone para terminar la anticipada: **el anterior a la
  /// fiesta**. Null si no se sabe la fecha de la fiesta o si ese día ya pasó
  /// (no se propone un día que no se puede guardar).
  static String? diaPropuesto(DateTime? fiesta, DateTime hoyAr) {
    if (fiesta == null) return null;
    // En UTC para que el cambio de horario no corra el día.
    final dia = ConfigEntradas.diaDe(
      DateTime.utc(fiesta.year, fiesta.month, fiesta.day - 1),
    );
    return _yaPaso(dia, hoyAr) ? null : dia;
  }

  /// Si [dia] (`AAAA-MM-DD`) es anterior a hoy en Argentina. Hoy no pasó: el
  /// último día de la anticipada rige entero.
  static bool _yaPaso(String dia, DateTime hoyAr) =>
      dia.compareTo(ConfigEntradas.diaDe(hoyAr)) < 0;

  /// "La anticipada terminó el 28/11". Null si no hay una que haya terminado.
  String? get notaDeLaAnticipada {
    final dia = anticipadaTermino;
    if (!ConfigEntradas.diaValido(dia)) return null;
    final p = dia!.split('-');
    return 'La anticipada terminó el ${p[2]}/${p[1]}';
  }

  /// Qué falta o está mal, en palabras, para el jefe. **Null: se puede
  /// guardar.** Son las reglas nuevas de PRECIOS; las de siempre (pesos
  /// enteros, la anticipada con su día y con la General, los porcentajes de 0
  /// a 100) las vuelve a frenar `ConfigEntradas.conPrecios` en [enColumnas].
  String? loQueFalta(DateTime hoyAr) {
    final que = queSeVende;
    if (que == null) {
      return 'Elegí qué se vende ahora: ANTICIPADA o GENERAL.';
    }
    if (que == QueSeVende.anticipada) {
      final a = anticipada;
      if (a == null || a <= 0) return 'Poné el precio de la anticipada.';
      if (!_pesosEnteros(a)) {
        return 'El precio de la anticipada va en pesos, sin centavos.';
      }
      final dia = hasta?.trim();
      if (dia == null || dia.isEmpty) {
        return 'Poné hasta qué día vale la anticipada.';
      }
      if (!ConfigEntradas.diaValido(dia)) {
        return 'Ese día no existe: escribilo como 28/11/2026.';
      }
      if (_yaPaso(dia, hoyAr)) {
        return 'Ese día ya pasó: la anticipada vale hasta hoy o un día que '
            'viene.';
      }
    }
    final g = general;
    if (g == null || g <= 0) {
      return que == QueSeVende.anticipada
          ? 'Poné también el precio de la General: es el que se cobra cuando '
              'termina la anticipada, y de ahí sale el de la mesa adicional y '
              'las sillas.'
          : 'Poné el precio de la General.';
    }
    if (!_pesosEnteros(g)) {
      return 'El precio de la General va en pesos, sin centavos.';
    }
    final lugares = descuentoLugaresPct;
    if (lugares == null) {
      return 'Escribí el descuento de la mesa adicional y las sillas: 0 si no '
          'tienen descuento.';
    }
    if (!_deCeroACien(lugares)) {
      return 'El descuento de la mesa adicional y las sillas va de 0 a 100.';
    }
    final recargo = recargoPct;
    if (recargo == null) {
      return 'Escribí el recargo por transferencia: 0 si no hay recargo.';
    }
    if (!_deCeroACien(recargo)) return 'El recargo va de 0 a 100.';
    return null;
  }

  static bool _pesosEnteros(double v) =>
      !v.isNaN && v >= 0 && v == v.roundToDouble();

  static bool _deCeroACien(double v) => !v.isNaN && v >= 0 && v <= 100;

  /// Lo elegido en las columnas de `entradas_config`, sobre la config que
  /// había ([base]: de ahí salen el id y cuándo nació):
  /// - **General** → `valor_entrada`, y la anticipada queda vacía (precio y
  ///   día): una 6.9.x lo lee como "un solo precio";
  /// - **Anticipada** → `precio_anticipada`, `anticipada_hasta` y
  ///   `valor_entrada` con la General.
  ///
  /// **Tira `ArgumentError` con [loQueFalta] si algo falta**, y después arma la
  /// config con `ConfigEntradas.conPrecios`, que sigue siendo la segunda llave
  /// de las reglas de siempre.
  ConfigEntradas enColumnas(ConfigEntradas base, {required DateTime hoyAr}) {
    final falta = loQueFalta(hoyAr);
    if (falta != null) throw ArgumentError(falta);
    final esAnticipada = queSeVende == QueSeVende.anticipada;
    return base.conPrecios(
      valorEntrada: general,
      precioAnticipada: esAnticipada ? anticipada : null,
      anticipadaHasta: esAnticipada ? hasta!.trim() : null,
      descuentoLugaresPct: descuentoLugaresPct!,
      recargoPct: recargoPct!,
      descuentoAMano: descuentoAMano,
    );
  }
}
