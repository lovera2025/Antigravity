import '../../../models/calculo_rentabilidad.dart';

enum EstadoRentabilidad { saludable, ajustado, equilibrio, perdida }

class ResultadoRentabilidad {
  final double precio;
  final double costoVariableTotal;
  final double costoFijoTotal;
  final double honorarioAdrian;
  final double margenBruto;
  final double gananciaNetaEmpresa;
  final double puntoEquilibrio;
  final EstadoRentabilidad estado;
  final double markupEmpresaPct;

  ResultadoRentabilidad({
    required this.precio,
    required this.costoVariableTotal,
    required this.costoFijoTotal,
    required this.honorarioAdrian,
    required this.margenBruto,
    required this.gananciaNetaEmpresa,
    required this.puntoEquilibrio,
    required this.estado,
    required this.markupEmpresaPct,
  });
}

class CalculadorRentabilidadService {
  ResultadoRentabilidad calcular(CalculoRentabilidad param) {
    double precio = param.precioVenta;
    
    double cvTotal = param.costosVariables.fold(0, (sum, i) => sum + i.monto);
    double cfTotal = param.costosFijos.fold(0, (sum, i) => sum + i.monto);
    
    double honorarioAdrian = 0;
    if (param.honorarioModo == 'porcentaje') {
      honorarioAdrian = precio * (param.honorarioAdrianPct / 100.0);
    } else {
      honorarioAdrian = param.honorarioAdrianMonto;
    }

    double margenBruto = precio - cvTotal - cfTotal;
    double gne = margenBruto - honorarioAdrian;
    double puntoEq = cvTotal + cfTotal + honorarioAdrian;

    double markup = (cvTotal + cfTotal + honorarioAdrian) > 0 
                    ? (gne / (cvTotal + cfTotal + honorarioAdrian)) * 100.0 
                    : 0.0;

    EstadoRentabilidad estado;
    if (gne < 0) {
      estado = EstadoRentabilidad.perdida;
    } else if (gne.abs() <= (precio * 0.01)) { // +- 1% tolerance
      estado = EstadoRentabilidad.equilibrio;
    } else if (gne < precio * 0.15) {
      estado = EstadoRentabilidad.ajustado;
    } else {
      estado = EstadoRentabilidad.saludable;
    }

    return ResultadoRentabilidad(
      precio: precio,
      costoVariableTotal: cvTotal,
      costoFijoTotal: cfTotal,
      honorarioAdrian: honorarioAdrian,
      margenBruto: margenBruto,
      gananciaNetaEmpresa: gne,
      puntoEquilibrio: puntoEq,
      estado: estado,
      markupEmpresaPct: markup,
    );
  }
}
