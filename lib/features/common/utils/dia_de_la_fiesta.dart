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
