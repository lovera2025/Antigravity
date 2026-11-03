import '../../../models/evento.dart';

/// Los eventos masivos que quedan por hacer, de la fecha más cercana a la más
/// lejana. Los de hoy cuentan: el día de la fiesta todavía se entrega.
List<Evento> fiestasQueVienen(Iterable<Evento> eventos, DateTime hoy) {
  final desde = DateTime(hoy.year, hoy.month, hoy.day);
  bool sigue(Evento e) {
    final f = e.fechaEvento;
    return e.modalidad == 'masivo' &&
        e.estado != EstadoEvento.finalizado &&
        e.estado != EstadoEvento.cancelado &&
        !DateTime(f.year, f.month, f.day).isBefore(desde);
  }

  return eventos.where(sigue).toList()
    ..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
}
