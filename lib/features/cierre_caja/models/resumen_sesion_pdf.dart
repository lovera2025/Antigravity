/// Fila del desglose por sesión/operario en el PDF de cierre del día.
class ResumenSesionPdf {
  final String operador;
  final String etiqueta;
  final String horaApertura;
  final String? horaCierre;
  final double efectivo;
  final double transferencia;
  final double cambioInicial;
  final double egresosEfectivo;

  /// Arqueo declarado al cerrar; null si la sesión sigue abierta o no se cargó.
  final double? arqueo;

  const ResumenSesionPdf({
    required this.operador,
    required this.etiqueta,
    required this.horaApertura,
    this.horaCierre,
    required this.efectivo,
    required this.transferencia,
    required this.cambioInicial,
    required this.egresosEfectivo,
    this.arqueo,
  });

  double get total => efectivo + transferencia;

  /// Efectivo que debería haber en el cajón al cerrar.
  double get efectivoEsperado => cambioInicial + efectivo - egresosEfectivo;

  /// Arqueo − esperado: positivo sobra, negativo falta. Null sin arqueo.
  double? get diferencia => arqueo == null ? null : arqueo! - efectivoEsperado;
}
