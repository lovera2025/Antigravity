import 'dart:convert';
import 'dart:typed_data';

/// Las letras del castellano en la tabla 850 ("PC850, multilingüe"), la que lee la
/// TP-POS58. Se vio en el papel el 3-nov-2026: pidiéndole la tabla 1252, la "á" salió
/// "ß" y la "Ú" salió "┌", que es lo que dibuja la 850 con esos bytes.
///
/// `esc_pos_utils_plus` manda el texto en Latin-1 si no se le da otra: esta tabla
/// se le pasa como `codec` al armar el ticket.
const Map<String, int> _letras850 = {
  'á': 0xA0, 'é': 0x82, 'í': 0xA1, 'ó': 0xA2, 'ú': 0xA3,
  'Á': 0xB5, 'É': 0x90, 'Í': 0xD6, 'Ó': 0xE0, 'Ú': 0xE9,
  'ñ': 0xA4, 'Ñ': 0xA5, 'ü': 0x81, 'Ü': 0x9A,
  '¿': 0xA8, '¡': 0xAD, '°': 0xF8, 'º': 0xA7, 'ª': 0xA6, '·': 0xFA,
};

final Map<int, String> _deLa850 = {
  for (final e in _letras850.entries) e.value: e.key,
};

/// Si [letra] se puede escribir en la tabla 850: lo de siempre (ASCII) y las letras
/// del castellano.
bool entraEnLa850(String letra) {
  final runas = letra.runes;
  if (runas.length != 1) return false;
  return runas.first < 0x80 || _letras850.containsKey(letra);
}

/// La tabla 850 como codec. Lo que no entra sale "?": nunca tira.
class Tabla850 extends Encoding {
  const Tabla850();

  @override
  String get name => 'cp850';

  @override
  Converter<String, List<int>> get encoder => const _Al850();

  @override
  Converter<List<int>, String> get decoder => const _Del850();
}

const tabla850 = Tabla850();

class _Al850 extends Converter<String, List<int>> {
  const _Al850();

  @override
  Uint8List convert(String input) {
    final salida = <int>[];
    for (final runa in input.runes) {
      if (runa < 0x80) {
        salida.add(runa);
      } else {
        salida.add(_letras850[String.fromCharCode(runa)] ?? 0x3F);
      }
    }
    return Uint8List.fromList(salida);
  }
}

/// Para leer de vuelta lo que se manda (en los tests). Un byte que no es letra del
/// castellano queda como su carácter de Latin-1, así los comandos se siguen viendo.
class _Del850 extends Converter<List<int>, String> {
  const _Del850();

  @override
  String convert(List<int> input) => String.fromCharCodes([
        for (final b in input) (_deLa850[b] ?? String.fromCharCode(b)).codeUnitAt(0),
      ]);
}
