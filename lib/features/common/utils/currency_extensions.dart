import 'package:intl/intl.dart';

extension CurrencyFormatting on num {
  /// Formatea un número como moneda argentina (ARS).
  /// Ejemplo: 1234.56 -> $ 1.234,56
  String toCurrency() => '\$ ${toFormattedNumber()}';

  /// Formatea un número como moneda sin el símbolo.
  /// Ejemplo: 1234.56 -> 1.234,56
  String toFormattedNumber() {
    final formatter = NumberFormat.decimalPattern('es_AR');
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    return formatter.format(this);
  }
}

/// Convierte un número a su representación en letras (español).
String numeroALetras(double monto) {
  if (monto == 0) return "CERO PESOS";

  final int entero = monto.truncate();
  final int centavos = ((monto - entero) * 100).round();

  String resultado = _convertirGrupo(entero);

  if (entero == 1) {
    resultado += " PESO";
  } else {
    resultado += " PESOS";
  }

  if (centavos > 0) {
    resultado += " CON ${centavos.toString().padLeft(2, '0')}/100";
  }

  return resultado.toUpperCase();
}

String _convertirGrupo(int n) {
  if (n == 0) return "";
  if (n < 10) return ["", "UN", "DOS", "TRES", "CUATRO", "CINCO", "SEIS", "SIETE", "OCHO", "NUEVE"][n];
  if (n < 20) {
    return ["DIEZ", "ONCE", "DOCE", "TRECE", "CATORCE", "QUINCE", "DIECISEIS", "DIECISIETE", "DIECIOCHO", "DIECINUEVE"][n - 10];
  }
  if (n < 30) return n == 20 ? "VEINTE" : "VEINTI${_convertirGrupo(n - 20)}";
  if (n < 100) {
    final int u = n % 10;
    final int d = (n / 10).truncate();
    final String de = ["", "", "", "TREINTA", "CUARENTA", "CINCUENTA", "SESENTA", "SETENTA", "OCHENTA", "NOVENTA"][d];
    return u == 0 ? de : "$de Y ${_convertirGrupo(u)}";
  }
  if (n < 200) return n == 100 ? "CIEN" : "CIENTO ${_convertirGrupo(n - 100)}";
  if (n < 1000) {
    final int rest = n % 100;
    final int c = (n / 100).truncate();
    final String ce = ["", "", "DOSCIENTOS", "TRESCIENTOS", "CUATROCIENTOS", "QUINIENTOS", "SEISCIENTOS", "SETECIENTOS", "OCHOCIENTOS", "NOVECIENTOS"][c];
    return rest == 0 ? ce : "$ce ${_convertirGrupo(rest)}";
  }
  if (n < 2000) return "MIL ${_convertirGrupo(n - 1000)}";
  if (n < 1000000) {
    final int rest = n % 1000;
    final int m = (n / 1000).truncate();
    return "${_convertirGrupo(m)} MIL ${_convertirGrupo(rest)}";
  }
  return "MONTO MUY GRANDE";
}
