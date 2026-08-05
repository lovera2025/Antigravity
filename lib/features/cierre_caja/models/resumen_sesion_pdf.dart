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

  /// La cerró el sistema, no una persona: cambio de día, caja tomada en otra PC
  /// o duplicado por apertura sin conexión.
  ///
  /// Se marca en el cierre para que el jefe distinga de un vistazo quién cerró
  /// como corresponde y quién se fue sin cerrar, sin que se pierda ni un cobro.
  final bool cierreAutomatico;

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
    this.cierreAutomatico = false,
  });

  /// Cerrada sin que nadie contara la plata.
  bool get cerradaSinArqueo => horaCierre != null && arqueo == null;

  double get total => efectivo + transferencia;

  /// Efectivo que debería haber en el cajón al cerrar.
  double get efectivoEsperado => cambioInicial + efectivo - egresosEfectivo;

  /// Arqueo − esperado: positivo sobra, negativo falta. Null sin arqueo.
  double? get diferencia => arqueo == null ? null : arqueo! - efectivoEsperado;
}
