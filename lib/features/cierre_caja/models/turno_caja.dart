import '../../../core/utils/ar_time.dart';

/// Categoría usada en la tabla `egresos` para etiquetar retiros de caja.
/// Se centraliza acá para que `cierre_caja_provider` y `finanzas_provider`
/// compartan la constante sin acoplarse entre sí.
const String kCategoriaRetiroCaja = 'Retiro de caja';

/// Egreso sin evento: plata retirada del negocio pero aún no gastada (retiro pendiente).
const String kCategoriaRetiroDueno = 'Retiro dueño';

/// Egreso sin evento: gasto personal ([empresa] sale del negocio; [pendiente] consume retiro previo).
const String kCategoriaGastoPersonal = 'Gasto personal';

/// Egreso sin evento: gasto directo del negocio registrado desde el panel del dueño.
const String kCategoriaGastoEmpresa = 'Gasto empresa';

/// Turnos de cierre de caja. El corte mañana/tarde se decide por hora AR
/// (default 14:00) y `dia` engloba ambos (00:00 a 23:59 AR).
enum TurnoCaja {
  manana,
  tarde,
  dia,
}

extension TurnoCajaX on TurnoCaja {
  String get label {
    switch (this) {
      case TurnoCaja.manana:
        return 'MAÑANA';
      case TurnoCaja.tarde:
        return 'TARDE';
      case TurnoCaja.dia:
        return 'DÍA';
    }
  }

  String get labelCorto {
    switch (this) {
      case TurnoCaja.manana:
        return 'Mañana';
      case TurnoCaja.tarde:
        return 'Tarde';
      case TurnoCaja.dia:
        return 'Día';
    }
  }

  /// Identificador estable para nombres de archivo / logs.
  String get slug {
    switch (this) {
      case TurnoCaja.manana:
        return 'manana';
      case TurnoCaja.tarde:
        return 'tarde';
      case TurnoCaja.dia:
        return 'dia';
    }
  }
}

/// Rango horario [inicio, fin) en reloj AR para un día calendario AR dado.
///
/// [inicioAr] y [finAr] usan la misma convención que [ArTime.toAr]: componentes
/// de reloj de pared AR en un [DateTime] marcado UTC (no instante real).
class RangoHorarioAr {
  final DateTime inicioAr;
  final DateTime finAr;

  const RangoHorarioAr({required this.inicioAr, required this.finAr});

  /// `dt` (UTC o local) cae dentro del rango (comparado en huso AR).
  bool contiene(DateTime dt) {
    final ar = ArTime.toAr(dt);
    return !ar.isBefore(inicioAr) && ar.isBefore(finAr);
  }
}

/// Instante “pared AR” para comparar con [ArTime.toAr] sin mezclar TZ del SO.
DateTime _arWall(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute);

/// Calcula el rango horario AR de un turno para un día calendario AR puntual.
///
/// `corteHora` (default 14): hora AR a partir de la cual termina mañana y arranca tarde.
RangoHorarioAr rangoHorarioAr(
  DateTime diaCalendarioAr,
  TurnoCaja turno, {
  int corteHora = 14,
}) {
  final y = diaCalendarioAr.year;
  final m = diaCalendarioAr.month;
  final d = diaCalendarioAr.day;
  final inicio0 = _arWall(y, m, d);
  final corte = _arWall(y, m, d, corteHora);
  final fin = inicio0.add(const Duration(days: 1));
  switch (turno) {
    case TurnoCaja.manana:
      return RangoHorarioAr(inicioAr: inicio0, finAr: corte);
    case TurnoCaja.tarde:
      return RangoHorarioAr(inicioAr: corte, finAr: fin);
    case TurnoCaja.dia:
      return RangoHorarioAr(inicioAr: inicio0, finAr: fin);
  }
}
