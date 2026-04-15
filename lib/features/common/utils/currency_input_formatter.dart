import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formateador de entrada para moneda argentina (ARS).
/// Maneja miles con '.' y decimales con ','.
/// El usuario ingresa dígitos y el sistema calcula los decimales automáticamente.
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Si el nuevo texto está vacío, permitirlo
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Filtrar solo dígitos de ambos estados
    String oldDigits = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    String newDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Si el usuario borró un caracter no numérico (símbolo, punto, coma), 
    // forzamos el borrado del último dígito para que el usuario sienta que "borra" algo.
    if (newValue.text.length < oldValue.text.length && oldDigits == newDigits && newDigits.isNotEmpty) {
      newDigits = newDigits.substring(0, newDigits.length - 1);
    }
    
    // Si el resultado es vacío o solo ceros al borrar, permitir limpiar
    if (newDigits.isEmpty || (newValue.text.length < oldValue.text.length && int.tryParse(newDigits) == 0)) {
       return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Convertir a double asumiendo que los últimos 2 dígitos son decimales
    double value = double.parse(newDigits) / 100;
    
    // Formatear usando NumberFormat de es_AR (sin símbolo)
    final formatter = NumberFormat.decimalPattern('es_AR');
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    
    String formattedText = formatter.format(value);
    
    // El símbolo puede estar al inicio o al final según el locale.
    // Buscamos la posición del último dígito para poner el cursor ahí.
    int lastDigitIndex = formattedText.lastIndexOf(RegExp(r'[0-9]'));
    int cursorOffset = lastDigitIndex != -1 ? lastDigitIndex + 1 : formattedText.length;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  /// Método utilitario para convertir el texto formateado de vuelta a double puro.
  static double parse(String text) {
    // Eliminar puntos de miles y cambiar coma por punto decimal
    String clean = text
        .replaceAll('.', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }
}
