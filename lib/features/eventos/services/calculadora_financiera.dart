
/// Clase de servicio para centralizar todos los cálculos financieros de los contratos.
/// Asegura que la lógica de cuotas, descuentos y saldos sea consistente entre UI y Repositorio.
class CalculadoraFinanciera {
  
  /// Calcula el valor de una "Cuota Pura" (sin adicionales).
  static double calcularCuotaPura(double montoPactadoBase, int totalCuotas) {
    if (totalCuotas <= 0) return 0.0;
    return montoPactadoBase / totalCuotas;
  }

  /// Calcula cuánto se debe descontar de la deuda (Monto Gross) dado un efectivo (Neto) y un porcentaje de descuento.
  /// Ejemplo: Si el alumno paga $90 (neto) con un 10% de descuento, la deuda debe bajar $100 (gross).
  static double netoABruto(double montoNeto, double porcentajeDescuento) {
    if (porcentajeDescuento >= 100) return montoNeto; // Evitar división por cero
    final factor = 1.0 - (porcentajeDescuento / 100.0);
    if (factor <= 0) return montoNeto;
    return montoNeto / factor;
  }

  /// Calcula cuánto efectivo se debe recibir dado un monto de deuda a cancelar y un porcentaje de descuento.
  static double brutoANeto(double montoBruto, double porcentajeDescuento) {
    final factor = 1.0 - (porcentajeDescuento / 100.0);
    return montoBruto * factor;
  }

  /// Distribuye un pago bruto entre los diferentes conceptos de un contrato.
  /// Prioriza: Cuota Base -> Mesa Extra -> Sillas Extras (o según lógica de negocio).
  static Map<String, double> distribuirPago(
    double montoBrutoADistribuir, {
    required double deudaBasePendiente,
    required double deudaMesaPendiente,
    required double deudaSillasPendiente,
  }) {
    double restante = montoBrutoADistribuir;
    
    // 1. Cubrir Base
    double pagoBase = 0;
    if (restante > 0 && deudaBasePendiente > 0) {
      pagoBase = restante >= deudaBasePendiente ? deudaBasePendiente : restante;
      restante -= pagoBase;
    }

    // 2. Cubrir Mesa
    double pagoMesa = 0;
    if (restante > 0 && deudaMesaPendiente > 0) {
      pagoMesa = restante >= deudaMesaPendiente ? deudaMesaPendiente : restante;
      restante -= pagoMesa;
    }

    // 3. Cubrir Sillas
    double pagoSillas = 0;
    if (restante > 0 && deudaSillasPendiente > 0) {
      pagoSillas = restante >= deudaSillasPendiente ? deudaSillasPendiente : restante;
      restante -= pagoSillas;
    }

    return {
      'Base': pagoBase,
      'Mesa': pagoMesa,
      'Sillas': pagoSillas,
      'Excedente': restante,
    };
  }
}
