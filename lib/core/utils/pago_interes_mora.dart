/// Valor persistido en [pagos_contrato_alumno.line_kind] para cobros de mora
/// (solo ingreso; no liquidan capital del plan).
const String kLineKindInteresMora = 'interes_mora';

/// Heurística estable para reconocer líneas de **interés por mora** en
/// [pagos_contrato_alumno]. No liquidan capital del plan (solo ingreso accesorio).
///
/// Usa folding de vocales acentuadas para que NFC/NFD u orígenes sin tilde no
/// hagan pasar la línea como "cuota base" en [recalcularProgresoContrato].
bool esPagoInteresMoraPorConcepto(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  final lowered = raw.toLowerCase();
  final stripped = _stripCombiningMarks(lowered);
  final folded = foldDiacriticosLatin(stripped);
  // Firma del modal masivo aunque falte la palabra "mora" en el texto.
  if (folded.contains('este cobro') && folded.contains('interes')) return true;
  if (folded.contains('interes mora')) return true;
  return folded.contains('interes') && folded.contains('mora');
}

/// Elimina marcas combinantes Unicode (p. ej. NFD: `e` + ◌́) para poder detectar `interes`.
String _stripCombiningMarks(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r >= 0x0300 && r <= 0x036F) continue;
    if (r >= 0xFE20 && r <= 0xFE2F) continue;
    out.add(r);
  }
  return String.fromCharCodes(out);
}

/// Normaliza minúsculas latinas comunes (es-AR) a ASCII para comparar conceptos.
String foldDiacriticosLatin(String s) {
  var t = s;
  const pairs = [
    ['á', 'a'],
    ['à', 'a'],
    ['ä', 'a'],
    ['â', 'a'],
    ['ã', 'a'],
    ['å', 'a'],
    ['é', 'e'],
    ['è', 'e'],
    ['ë', 'e'],
    ['ê', 'e'],
    ['í', 'i'],
    ['ì', 'i'],
    ['ï', 'i'],
    ['î', 'i'],
    ['ó', 'o'],
    ['ò', 'o'],
    ['ö', 'o'],
    ['ô', 'o'],
    ['õ', 'o'],
    ['ú', 'u'],
    ['ù', 'u'],
    ['ü', 'u'],
    ['û', 'u'],
    ['ñ', 'n'],
    ['ç', 'c'],
  ];
  for (final e in pairs) {
    t = t.replaceAll(e[0], e[1]);
  }
  return t;
}
