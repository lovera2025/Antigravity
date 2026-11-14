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

  /// El día como lo escribe el jefe en PRECIOS ("28/11/2026") pasado a como se
  /// guarda ("2026-11-28"). **Null si no es un día que existe.**
  static String? diaDeTexto(String texto) {
    final m = RegExp(r'^\s*(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})\s*$')
        .firstMatch(texto);
    if (m == null) return null;
    final dia = '${m[3]}-${m[2]!.padLeft(2, '0')}-${m[1]!.padLeft(2, '0')}';
    return ConfigEntradas.diaValido(dia) ? dia : null;
  }

  /// Lo guardado ("2026-11-28") como se lee en pantalla ("28/11/2026"). Vacío
  /// si no hay día.
  static String textoDelDia(String? dia) {
    if (!ConfigEntradas.diaValido(dia)) return '';
    final p = dia!.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  /// Lo que vale cada entrada de la mesa adicional y de las sillas extra.
  /// **Siempre sobre el valor de la entrada, nunca sobre la anticipada**: la
  /// regla es "el 50 % de su valor". Null sin precio.
  static double? deLugar(ConfigEntradas? c) {
    if (c == null || !c.tienePrecio) return null;
    return RenglonEntradas.precioCon(c.valorEntrada!, c.descuentoLugaresPct);
  }
}
