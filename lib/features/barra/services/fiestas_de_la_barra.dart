import '../../../models/evento.dart';
import '../../common/utils/dia_de_la_fiesta.dart';

/// Las fiestas que la cajera puede elegir: las que tienen precios de barra en este
/// equipo y quedan por hacer (las de hoy cuentan: la barra vende esa noche), de la más
/// cercana a la más lejana. Masivas o particulares: lo que decide es que el jefe les
/// haya puesto precios.
///
/// **La de anoche sigue hasta el mediodía** ([primerDiaDeLasFiestasQueVienen]): la
/// fiesta pasa las 00:00 y las cajas se cierran de madrugada.
///
/// **Y una fiesta que ya pasó sigue mientras la cajera tenga su caja abierta ahí, en
/// este equipo** ([conCajaAbierta]; revisión final de la 6.9.0): si no, una caja que
/// no se cerró antes del mediodía quedaba abierta para siempre. **Esa va al final**
/// ([enElOrdenDeLasFiestas]) y la pantalla la marca.
List<Evento> fiestasParaLaBarra(
  Iterable<Evento> eventos,
  Set<String> conPrecio,
  DateTime hoy, {
  Set<String> conCajaAbierta = const {},
}) {
  bool sirve(Evento e) {
    if (!conPrecio.contains(e.id)) return false;
    if (conCajaAbierta.contains(e.id)) return true;
    return !laFiestaYaPaso(e, hoy);
  }

  return enElOrdenDeLasFiestas(eventos.where(sirve), hoy);
}
