import '../../../models/evento.dart';
import '../../common/utils/dia_de_la_fiesta.dart';

/// Los eventos masivos que quedan por hacer, de la fecha más cercana a la más
/// lejana. Los de hoy cuentan: el día de la fiesta todavía se entrega. **El de
/// anoche sigue hasta el mediodía** ([primerDiaDeLasFiestasQueVienen]), como en
/// la barra: la fiesta pasa las 00:00.
List<Evento> fiestasQueVienen(Iterable<Evento> eventos, DateTime hoy) {
  final desde = primerDiaDeLasFiestasQueVienen(hoy);
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
