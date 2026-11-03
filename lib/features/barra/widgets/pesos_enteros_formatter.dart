import 'package:flutter/services.dart';

/// La plata de la barra mientras se escribe: solo números, con los puntos de mil a
/// medida que se escribe ("20000" se ve "20.000") y en pesos enteros, sin centavos.
/// El "$" va puesto delante de la casilla (`prefixText`).
///
/// No es el `CurrencyInputFormatter` de las cuotas, que entra por la derecha con
/// centavos: en la barra se escribe como se dice (pedido del 3-nov).
class PesosEnterosFormatter extends TextInputFormatter {
  const PesosEnterosFormatter();

  /// "20.000" → 20000. Vacío o sin números: null.
  static int? leer(String texto) {
    final digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return null;
    return int.tryParse(digitos.length > 12 ? digitos.substring(0, 12) : digitos);
  }

  /// 20000 → "20.000". Null: vacío.
  static String escribir(num? valor) {
    if (valor == null) return '';
    final s = valor.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Borrar un punto no borra nada: se lleva el número de al lado.
    final viejos = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (newValue.text.length < oldValue.text.length && digitos == viejos && digitos.isNotEmpty) {
      digitos = digitos.substring(0, digitos.length - 1);
    }
    digitos = digitos.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digitos.length > 12) digitos = digitos.substring(0, 12);
    final texto = digitos.isEmpty ? '' : escribir(int.parse(digitos));
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
