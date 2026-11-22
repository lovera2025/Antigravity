import '../../barra/cuentas/pesos.dart';
import '../datos/config_entradas.dart';
import 'eleccion_de_precios.dart';
import 'precio_de_entradas.dart';

/// Hasta qué día vale la anticipada en las otras fiestas.
enum DiaDeLaAnticipada {
  /// El mismo día que se escribió (por ejemplo, todas hasta el 28/11).
  elMismo,

  /// El día anterior a cada fiesta: lo que PRECIOS propone siempre.
  elAnteriorDeCadaFiesta,
}

/// PRECIOS → "¿Poner estos precios también en otras fiestas?" (pedido del
/// usuario, 22-nov-2026: "sabés lo que es ir poniendo el precio fiesta por
/// fiesta"). Sin pantalla ni base: qué precios le tocan a cada fiesta, si se
/// pueden poner y cómo se dice lo que tiene hoy.
///
/// **Se copia todo lo de PRECIOS** (qué se vende, la anticipada, la General,
/// el descuento de los lugares, el recargo y si quien vende puede descontar),
/// con **una sola excepción: el día de la anticipada**, que se elige
/// ([DiaDeLaAnticipada]). Cada fiesta guarda en su propia fila, con su id, por
/// el mismo camino que PRECIOS ([EleccionDePrecios.enColumnas]): las mismas
/// reglas, las dos llaves.
class PreciosEnOtrasFiestas {
  const PreciosEnOtrasFiestas._();

  /// Lo que se le pone a una fiesta del día [fechaFiesta], a partir de lo
  /// elegido en PRECIOS ([elegido]). Con la General no cambia nada.
  static EleccionDePrecios paraLaFiesta(
    EleccionDePrecios elegido, {
    required DateTime? fechaFiesta,
    required DiaDeLaAnticipada dia,
    required DateTime hoyAr,
  }) {
    if (elegido.queSeVende != QueSeVende.anticipada ||
        dia == DiaDeLaAnticipada.elMismo) {
      return _copia(elegido, hasta: elegido.hasta);
    }
    return _copia(
      elegido,
      hasta: EleccionDePrecios.diaPropuesto(fechaFiesta, hoyAr),
    );
  }

  static EleccionDePrecios _copia(EleccionDePrecios e, {required String? hasta}) =>
      EleccionDePrecios(
        queSeVende: e.queSeVende,
        general: e.general,
        anticipada: e.anticipada,
        hasta: hasta,
        descuentoLugaresPct: e.descuentoLugaresPct,
        recargoPct: e.recargoPct,
        descuentoAMano: e.descuentoAMano,
      );

  /// Por qué no se le pueden poner estos precios a esa fiesta, o null si se
  /// puede:
  /// - con "el día anterior de cada fiesta", una fiesta sin fecha o cuyo día
  ///   anterior ya pasó no tiene a qué día ponerle la anticipada;
  /// - con "el mismo día", **una fiesta que es ese día o antes**: la anticipada
  ///   seguiría vigente su misma noche y en la puerta se cobraría la anticipada
  ///   en vez de la General (revisión del 22-nov-2026).
  static String? problema(
    EleccionDePrecios elegido, {
    required DateTime? fechaFiesta,
    required DiaDeLaAnticipada dia,
    required DateTime hoyAr,
  }) {
    final paraEsa =
        paraLaFiesta(elegido, fechaFiesta: fechaFiesta, dia: dia, hoyAr: hoyAr);
    if (elegido.queSeVende == QueSeVende.anticipada) {
      if (dia == DiaDeLaAnticipada.elAnteriorDeCadaFiesta && paraEsa.hasta == null) {
        return fechaFiesta == null
            ? 'No tiene fecha: no se sabe su día anterior.'
            : 'Su día anterior ya pasó: la anticipada no tendría días.';
      }
      final hasta = paraEsa.hasta?.trim();
      if (dia == DiaDeLaAnticipada.elMismo &&
          fechaFiesta != null &&
          ConfigEntradas.diaValido(hasta) &&
          ConfigEntradas.diaDe(fechaFiesta).compareTo(hasta!) <= 0) {
        return 'Es el ${_diaCorto(hasta)} o antes: la anticipada seguiría la noche '
            'de la fiesta.';
      }
    }
    return paraEsa.loQueFalta(hoyAr);
  }

  /// Si [fechaFiesta] se ofrece para poner los precios: de hoy en adelante.
  /// **La de anoche no** (revisión del 22-nov-2026): sigue en las listas de la
  /// venta hasta el mediodía, pero cambiarle el precio después de hecha no
  /// tiene sentido. Una sin fecha, sí: la regla del día la frena si hace falta.
  static bool seOfrece(DateTime? fechaFiesta, DateTime hoyAr) =>
      fechaFiesta == null ||
      ConfigEntradas.diaDe(fechaFiesta).compareTo(ConfigEntradas.diaDe(hoyAr)) >= 0;

  /// La opción que viene elegida: si en PRECIOS quedó el día anterior a la
  /// fiesta (lo que se propone), "el día anterior de cada fiesta"; si se
  /// escribió otro, "el mismo día".
  static DiaDeLaAnticipada diaQueViene(
    EleccionDePrecios elegido, {
    required DateTime? fechaDeEstaFiesta,
    required DateTime hoyAr,
  }) {
    final propuesto = EleccionDePrecios.diaPropuesto(fechaDeEstaFiesta, hoyAr);
    return propuesto != null && elegido.hasta?.trim() == propuesto
        ? DiaDeLaAnticipada.elAnteriorDeCadaFiesta
        : DiaDeLaAnticipada.elMismo;
  }

  /// Lo que una fiesta tiene hoy, en un renglón: "Sin precio", "General
  /// $ 10.000" o "Anticipada $ 8.000 hasta el 28/11 · General $ 10.000".
  static String loQueTieneHoy(ConfigEntradas? c, DateTime hoyAr) {
    if (c == null || !c.tienePrecio) return 'Sin precio';
    final general = 'General ${pesos(c.valorEntrada!)}';
    if (PrecioDeEntradas.rigeLaAnticipada(c, hoyAr)) {
      return 'Anticipada ${pesos(c.precioAnticipada!)} hasta el '
          '${_diaCorto(c.anticipadaHasta)} · $general';
    }
    return general;
  }

  /// "28/11" de un `AAAA-MM-DD`.
  static String _diaCorto(String? dia) {
    final texto = PrecioDeEntradas.textoDelDia(dia);
    return texto.length >= 5 ? texto.substring(0, 5) : texto;
  }

  /// Lo que se va a poner, en un renglón, para el cartel.
  static String loQueSePone(EleccionDePrecios e, DiaDeLaAnticipada dia) {
    final general = e.general == null ? '' : 'General ${pesos(e.general!)}';
    if (e.queSeVende != QueSeVende.anticipada) return general;
    final hasta = dia == DiaDeLaAnticipada.elMismo
        ? 'hasta el ${_diaCorto(e.hasta)}'
        : 'hasta el día anterior a cada fiesta';
    return 'Anticipada ${pesos(e.anticipada ?? 0)} $hasta · $general';
  }
}
