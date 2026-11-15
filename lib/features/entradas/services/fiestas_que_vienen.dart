import '../../../models/evento.dart';
import '../../common/utils/dia_de_la_fiesta.dart';

/// Los eventos masivos que quedan por hacer, de la fecha más cercana a la más
/// lejana. Los de hoy cuentan: el día de la fiesta todavía se entrega. **El de
/// anoche sigue hasta el mediodía** ([primerDiaDeLasFiestasQueVienen]), como en
/// la barra: la fiesta pasa las 00:00.
///
/// **Y una fiesta que ya pasó sigue mientras quien entró tenga su caja de entradas
/// abierta ahí, en este equipo** ([conCajaAbierta]; revisión final de la 6.9.0): si
/// no, una caja que no se cerró antes del mediodía quedaba abierta para siempre,
/// sin camino para cerrarla.
List<Evento> fiestasQueVienen(
  Iterable<Evento> eventos,
  DateTime hoy, {
  Set<String> conCajaAbierta = const {},
}) {
  final desde = primerDiaDeLasFiestasQueVienen(hoy);
  bool sigue(Evento e) {
    final f = e.fechaEvento;
    if (e.modalidad != 'masivo') return false;
    if (conCajaAbierta.contains(e.id)) return true;
    return e.estado != EstadoEvento.finalizado &&
        e.estado != EstadoEvento.cancelado &&
        !DateTime(f.year, f.month, f.day).isBefore(desde);
  }

  return eventos.where(sigue).toList()
    ..sort((a, b) => a.fechaEvento.compareTo(b.fechaEvento));
}
