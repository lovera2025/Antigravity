// Un signo que la Outfit no tiene sale en el papel como un cuadradito, sin
// error y sin aviso.
//
// Así salía la flechita "↳" del resumen de cobro (DETALLE DE PAGO), delante de
// la mora de la cuota que se paga, desde antes de la 5.0.0. Se vio el
// 15-oct-2026 al comparar los papeles de la 5.0.0 y la 6.0.0 con los datos del
// usuario (tool/cobro_igual_que_hoy_test.dart). Ahora es "→".
//
// Este test lee el texto de los archivos que arman los papeles y falla si
// aparece un signo que la Outfit (regular y negrita) no tiene. No cuentan los
// comentarios ni lo que es solo de consola (`debugPrint`), y tampoco los
// espacios: un espacio que la letra no tiene sale en blanco, igual que uno
// común (se miró en un PDF de prueba).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

const _archivos = [
  'lib/features/common/services/pdf_service.dart',
  'lib/features/common/services/planilla_entrega_pdf.dart',
  'lib/features/common/services/planilla_sorteo_pdf.dart',
  'lib/features/common/services/planilla_tema.dart',
  'lib/features/common/services/presupuesto_pdf_sections.dart',
  'lib/features/eventos/services/cobro_masivo_conceptos_pdf.dart',
  'lib/features/eventos/services/mora_concepto_rotulo.dart',
  'lib/features/eventos/services/concepto_pago_display.dart',
];

TtfParser _letra(String archivo) => TtfParser(
  ByteData.sublistView(
    File('assets/google_fonts/$archivo').readAsBytesSync(),
  ),
);

bool _esEspacio(int r) =>
    r == 0x00A0 || (r >= 0x2000 && r <= 0x200B) || r == 0x202F || r == 0x205F;

/// Los signos de [archivo] que no están en las dos letras, con sus líneas.
Map<String, List<int>> _faltantes(
  String archivo,
  TtfParser regular,
  TtfParser negrita,
) {
  final out = <String, List<int>>{};
  final lineas = File(archivo).readAsLinesSync();
  for (var i = 0; i < lineas.length; i++) {
    final l = lineas[i].trimLeft();
    if (l.startsWith('//') || l.contains('debugPrint(')) continue;
    for (final r in l.runes) {
      if (r < 128 || _esEspacio(r)) continue;
      // Selector de variante (el que acompaña a un emoji): no se dibuja solo.
      if (r == 0xFE0F) continue;
      if (regular.charToGlyphIndexMap.containsKey(r) &&
          negrita.charToGlyphIndexMap.containsKey(r)) {
        continue;
      }
      out.putIfAbsent(String.fromCharCode(r), () => []).add(i + 1);
    }
  }
  return out;
}

void main() {
  final regular = _letra('Outfit-Regular.ttf');
  final negrita = _letra('Outfit-Bold.ttf');

  test('la Outfit tiene la flecha del resumen y no la de antes', () {
    expect(regular.charToGlyphIndexMap.containsKey('→'.runes.first), isTrue);
    expect(regular.charToGlyphIndexMap.containsKey('↳'.runes.first), isFalse,
        reason: 'Si un día la Outfit tiene "↳", este test ya no explica nada.');
  });

  for (final archivo in _archivos) {
    test('$archivo no usa signos que la Outfit no tiene', () {
      final faltan = _faltantes(archivo, regular, negrita);
      expect(
        faltan,
        isEmpty,
        reason: faltan.entries
            .map((e) => '"${e.key}" en las líneas ${e.value.join(', ')}')
            .join('; '),
      );
    });
  }
}
