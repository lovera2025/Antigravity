import '../../../core/utils/ar_time.dart';

/// Qué pasa con la caja de un cobro al cambiarle la fecha en Mi Empresa → Corregir
/// medio de pago.
enum CajaTrasCambioDeFecha {
  /// No tenía caja, o el día nuevo es de su caja (una caja abierta a la noche sigue
  /// hasta la madrugada): queda donde estaba.
  igual,

  /// Otro día, con la caja todavía abierta: **sale de esa caja** y deja de contar en
  /// ese cierre. En Mi Empresa queda en su día nuevo.
  salioDeLaCaja,

  /// Otro día, pero la caja ya se cerró con esa plata contada: queda en esa caja (sacarla
  /// cambiaría un arqueo que ya se hizo).
  quedaEnCajaCerrada,
}

/// Los días (de Argentina) que abarca una caja: del que se abrió al que se cerró, o hasta
/// [ahora] si sigue abierta.
bool diaEsDeLaCaja({
  required DateTime dia,
  required DateTime abiertaAt,
  DateTime? cerradaAt,
  required DateTime ahora,
}) {
  DateTime soloDia(DateTime t) {
    final ar = ArTime.toAr(t);
    return DateTime.utc(ar.year, ar.month, ar.day);
  }

  final d = soloDia(dia);
  final desde = soloDia(abiertaAt);
  final hasta = soloDia(cerradaAt ?? ahora);
  return !d.isBefore(desde) && !d.isAfter(hasta);
}

/// Regla del usuario (7-nov-2026): **si el jefe cambia la fecha de un cobro a otro día,
/// esa plata no entró a la caja en la que se cargó**, así que sale de ella sola. Pasó con
/// ENRIQUE, MAXIMO: lo pagó el 23-oct, se cargó el 7-nov en la caja del modo jefe, se le
/// puso el 23 y seguía en el cierre del 7.
///
/// [caja] es la caja del cobro, o null si no tiene (un cobro de una versión vieja, o uno
/// que ya salió).
CajaTrasCambioDeFecha cajaTrasCambioDeFecha({
  required DateTime nuevaFecha,
  ({DateTime abiertaAt, DateTime? cerradaAt})? caja,
  required DateTime ahora,
}) {
  if (caja == null) return CajaTrasCambioDeFecha.igual;
  final mismoDia = diaEsDeLaCaja(
    dia: nuevaFecha,
    abiertaAt: caja.abiertaAt,
    cerradaAt: caja.cerradaAt,
    ahora: ahora,
  );
  if (mismoDia) return CajaTrasCambioDeFecha.igual;
  return caja.cerradaAt == null
      ? CajaTrasCambioDeFecha.salioDeLaCaja
      : CajaTrasCambioDeFecha.quedaEnCajaCerrada;
}
