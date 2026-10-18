import '../../../models/contrato_alumno.dart';

/// Lo que se guarda al dar de baja temporal a un alumno o al reincorporarlo.
///
/// La baja es un estado del alumno, no de su mora (6.1.0): mientras dura sale
/// de los cobros y de los totales, pero no se escribe ningún campo de mora.
/// Hasta la 6.0.0 se guardaba el día en `mora_fecha_referencia` y la mora
/// quedaba cortada ahí, también después de reincorporarlo.
class BajaTemporal {
  BajaTemporal._();

  static const prefijo = '[BAJA]';

  /// El nombre sin el `[BAJA]` de adelante.
  static String nombreLimpio(String nombre) =>
      nombre.replaceFirst(prefijo, '').trim();

  /// Dar de baja: el nombre con el `[BAJA]` delante y cuándo fue
  /// ([ahoraUtcIso]; esa columna queda solo en la PC).
  static Map<String, dynamic> alDarDeBaja(
    ContratoAlumno alumno, {
    required String ahoraUtcIso,
  }) =>
      {
        'nombre_alumno': '$prefijo ${nombreLimpio(alumno.nombreAlumno)}',
        'baja_temporal_desde': ahoraUtcIso,
      };

  /// Reincorporar: vuelve solo el nombre. La mora de cada cuota corre desde su
  /// vencimiento, igual que la de cualquiera que no pagó.
  static Map<String, dynamic> alReincorporar(ContratoAlumno alumno) => {
        'nombre_alumno': nombreLimpio(alumno.nombreAlumno),
      };
}
