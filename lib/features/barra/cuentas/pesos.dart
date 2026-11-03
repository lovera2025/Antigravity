/// La plata de la barra: las cuentas van en centavos enteros, así 3 x 1.333,33 da
/// 3.999,99 y no 3.999,9900000000002.
library;

int centavos(double pesos) => (pesos * 100).round();

double deCentavos(int c) => c / 100;

/// "$ 7.000", "$ 3.999,99", "$ -500": sin decimales si no hay centavos, que es lo que
/// entra en un renglón de 58 mm. No depende del idioma del equipo.
String pesos(double monto) {
  final c = centavos(monto);
  final negativo = c < 0;
  final abs = c.abs();
  final enteros = (abs ~/ 100).toString();
  final resto = abs % 100;
  final conPuntos = StringBuffer();
  for (var i = 0; i < enteros.length; i++) {
    if (i > 0 && (enteros.length - i) % 3 == 0) conPuntos.write('.');
    conPuntos.write(enteros[i]);
  }
  final decimales = resto == 0 ? '' : ',${resto.toString().padLeft(2, '0')}';
  return '\$ ${negativo ? '-' : ''}$conPuntos$decimales';
}
