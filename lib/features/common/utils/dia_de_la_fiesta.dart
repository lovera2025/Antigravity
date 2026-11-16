import '../../../models/evento.dart';

/// Hasta cuándo la fiesta de anoche sigue siendo "la de hoy" para quien trabaja en
/// ella: **hasta el mediodía siguiente**.
///
/// Una fiesta empieza un día y termina de madrugada. Contando "desde hoy", a las
/// 00:00 la fiesta desaparecía de la lista de la barra: la cajera que salía de
/// VENDER no podía volver a su caja ni cerrarla, y la encargada perdía LAS CAJAS
/// (6.8.0, lo encontró la revisión del 13-nov).
///
/// No es "desde ayer": con fiestas dos noches seguidas, la de anoche saldría primera
/// en la lista de la segunda noche y se abriría la caja en la fiesta equivocada. A
/// la tarde del día siguiente la de anoche ya no está.
const kLaFiestaSigueHasta = Duration(hours: 12);

/// El primer día que se muestra en las listas de "las fiestas que vienen": el de
/// [ahora] menos [kLaFiestaSigueHasta], sin la hora.
DateTime primerDiaDeLasFiestasQueVienen(DateTime ahora) {
  final t = ahora.subtract(kLaFiestaSigueHasta);
  return DateTime(t.year, t.month, t.day);
}

/// Si [e] ya pasó para las listas de las fiestas que vienen: terminada,
/// cancelada o de un día anterior a [primerDiaDeLasFiestasQueVienen]. Solo sigue
/// en una lista por una caja abierta en este equipo.
bool laFiestaYaPaso(Evento e, DateTime ahora) {
  final f = e.fechaEvento;
  return e.estado == EstadoEvento.finalizado ||
      e.estado == EstadoEvento.cancelado ||
      DateTime(f.year, f.month, f.day).isBefore(primerDiaDeLasFiestasQueVienen(ahora));
}

/// El orden de esas listas: primero las que vienen, de la más cercana a la más
/// lejana, y **al final las que ya pasaron** (las de una caja abierta), que la
/// pantalla marca. Con fiestas dos noches seguidas, la de anoche con la caja
/// olvidada salía primera y sin marca, y se vendía en la fiesta equivocada
/// (revisión del 15-nov).
List<Evento> enElOrdenDeLasFiestas(Iterable<Evento> fiestas, DateTime ahora) =>
    fiestas.toList()
      ..sort((a, b) {
        final pasoA = laFiestaYaPaso(a, ahora) ? 1 : 0;
        final pasoB = laFiestaYaPaso(b, ahora) ? 1 : 0;
        if (pasoA != pasoB) return pasoA - pasoB;
        return a.fechaEvento.compareTo(b.fechaEvento);
      });
