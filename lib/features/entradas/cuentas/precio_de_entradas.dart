import '../../../core/utils/ar_time.dart';
import '../datos/config_entradas.dart';
import '../datos/venta_entradas.dart';

/// El precio de la entrada de una fiesta: el de hoy y el de los lugares
/// adicionales. Sale todo de lo que el jefe puso en PRECIOS ([ConfigEntradas]);
/// acá no hay ningún precio escrito.
///
/// **El día es el de Argentina.** [hoyAr] es un momento ya pasado al reloj de
/// Argentina ([hoyEnArgentina], `ArTime.toAr`): la anticipada termina a la
/// medianoche de acá, no a la de UTC.
class PrecioDeEntradas {
  PrecioDeEntradas._();

  /// El momento de ahora en el reloj de Argentina.
  static DateTime hoyEnArgentina() => ArTime.nowAr();

  /// Si hoy rige la anticipada: tiene que estar completa (precio y hasta qué
  /// día) y hoy ser ese día o uno anterior. **El último día rige entero.**
  static bool rigeLaAnticipada(ConfigEntradas? c, DateTime hoyAr) {
    if (c == null || !c.tienePrecio || !c.tieneAnticipada) return false;
    // `AAAA-MM-DD` se compara como texto: el orden es el de los días.
    return ConfigEntradas.diaDe(hoyAr).compareTo(c.anticipadaHasta!) <= 0;
  }

  /// Lo que vale hoy una entrada suelta. **Null: la fiesta no tiene precio y
  /// no se vende.**
  static double? deHoy(ConfigEntradas? c, DateTime hoyAr) {
    if (c == null || !c.tienePrecio) return null;
    return rigeLaAnticipada(c, hoyAr) ? c.precioAnticipada : c.valorEntrada;
  }

  /// Lo que vale cada entrada de la mesa adicional y de las sillas extra.
  /// **Siempre sobre el valor de la entrada, nunca sobre la anticipada**: la
  /// regla es "el 50 % de su valor". Null sin precio.
  static double? deLugar(ConfigEntradas? c) {
    if (c == null || !c.tienePrecio) return null;
    return RenglonEntradas.precioCon(c.valorEntrada!, c.descuentoLugaresPct);
  }
}
