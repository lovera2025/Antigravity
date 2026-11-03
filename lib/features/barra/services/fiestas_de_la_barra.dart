import '../../../models/evento.dart';

/// Las fiestas que la cajera puede elegir: las que tienen precios de barra en este
/// equipo y quedan por hacer (las de hoy cuentan: la barra vende esa noche), de la más
/// cercana a la más lejana. Masivas o particulares: lo que decide es que el jefe les
/// haya puesto precios.
List<Evento> fiestasParaLaBarra(
  Iterable<Evento> eventos,
  Set<String> conPrecio,
  DateTime hoy,
) {
  final desde = DateTime(hoy.year, hoy.month, hoy.day);
  bool sirve(Evento e) {
    final f = e.fechaEvento;
    return conPrecio.contains(e.id) &&
        e.estado != EstadoEvento.finalizado &&
        e.estado != EstadoEvento.cancelado &&
        !DateTime(f.year, f.month, f.day).isBefore(desde);
  }

  return eventos.where(sirve).toList()
    ..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
}
