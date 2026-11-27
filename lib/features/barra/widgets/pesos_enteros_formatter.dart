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

/// El **precio de lista** mientras se escribe (lo que cobra el proveedor por unidad):
/// como [PesosEnterosFormatter], con los puntos de mil, y **con centavos si hacen falta**
/// después de una coma ("1.333,33"), porque una caja dividida por unidades los puede dar
/// (audio 77 del jefe).
class PesosConCentavosFormatter extends TextInputFormatter {
  const PesosConCentavosFormatter();

  /// "1.333,33" → 1333.33; "11.740" → 11740. Vacío: null.
  static double? leer(String texto) {
    final partes = texto.split(',');
    final enteros = partes.first.replaceAll(RegExp(r'[^0-9]'), '');
    final decimales = partes.length > 1 ? partes[1].replaceAll(RegExp(r'[^0-9]'), '') : '';
    if (enteros.isEmpty && decimales.isEmpty) return null;
    final c = decimales.isEmpty ? 0 : int.parse(decimales.padRight(2, '0').substring(0, 2));
    return (int.tryParse(enteros.isEmpty ? '0' : enteros) ?? 0) + c / 100;
  }

  /// 1333.33 → "1.333,33"; 11740 → "11.740". Null: vacío.
  static String escribir(num? valor) {
    if (valor == null) return '';
    final c = (valor * 100).round().abs();
    final enteros = PesosEnterosFormatter.escribir(c ~/ 100);
    final resto = c % 100;
    return resto == 0 ? enteros : '$enteros,${resto.toString().padLeft(2, '0')}';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final texto = newValue.text.replaceAll('.', '');
    final coma = texto.indexOf(',');
    var enteros = (coma < 0 ? texto : texto.substring(0, coma)).replaceAll(RegExp(r'[^0-9]'), '');
    enteros = enteros.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (enteros.length > 12) enteros = enteros.substring(0, 12);
    var salida = enteros.isEmpty ? '' : PesosEnterosFormatter.escribir(int.parse(enteros));
    if (coma >= 0) {
      final dec = texto.substring(coma + 1).replaceAll(RegExp(r'[^0-9]'), '');
      salida = '${salida.isEmpty ? '0' : salida},${dec.length > 2 ? dec.substring(0, 2) : dec}';
    }
    return TextEditingValue(text: salida, selection: TextSelection.collapsed(offset: salida.length));
  }
}
