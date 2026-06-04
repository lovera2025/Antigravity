const String kLineKindInteresMora = 'interes_mora';

/// Valor persistido en [pagos_contrato_alumno.line_kind] para cargos de
/// operador/canal (transferencia MP u otro). Solo ingreso; no liquidan capital.
const String kLineKindCargoCanal = 'cargo_canal_ref';

/// Heur├¡stica estable para reconocer l├¡neas de **inter├®s por mora** en
/// [pagos_contrato_alumno]. No liquidan capital del plan (solo ingreso accesorio).
///
/// Usa folding de vocales acentuadas para que NFC/NFD u or├¡genes sin tilde no
/// hagan pasar la l├¡nea como "cuota base" en [recalcularProgresoContrato].
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

/// Elimina marcas combinantes Unicode (p. ej. NFD: `e` + Ôùî╠ü) para poder detectar `interes`.
String _stripCombiningMarks(String s) {
  final out = <int>[];
  for (final r in s.runes) {
    if (r >= 0x0300 && r <= 0x036F) continue;
    if (r >= 0xFE20 && r <= 0xFE2F) continue;
    out.add(r);
  }
  return String.fromCharCodes(out);
}

/// Normaliza min├║sculas latinas comunes (es-AR) a ASCII para comparar conceptos.
String foldDiacriticosLatin(String s) {
  var t = s;
  const pairs = [
    ['├í', 'a'],
    ['├á', 'a'],
    ['├ñ', 'a'],
    ['├ó', 'a'],
    ['├ú', 'a'],
    ['├Ñ', 'a'],
    ['├®', 'e'],
    ['├¿', 'e'],
    ['├½', 'e'],
    ['├¬', 'e'],
    ['├¡', 'i'],
    ['├¼', 'i'],
    ['├»', 'i'],
    ['├«', 'i'],
    ['├│', 'o'],
    ['├▓', 'o'],
    ['├Â', 'o'],
    ['├┤', 'o'],
    ['├Á', 'o'],
    ['├║', 'u'],
    ['├╣', 'u'],
    ['├╝', 'u'],
    ['├╗', 'u'],
    ['├▒', 'n'],
    ['├º', 'c'],
  ];
  for (final e in pairs) {
    t = t.replaceAll(e[0], e[1]);
  }
  return t;
}

DateTime inicioMoraPeriodoVigente(DateTime? fechaVencimientoProximaCuota) {
  if (fechaVencimientoProximaCuota == null) {
    return DateTime(2100);
  }
  return fechaVencimientoProximaCuota;
}

double moraCobradaDelPeriodoVigente(Iterable<Map<String, dynamic>> pagos, DateTime inicioMora) {
  double suma = 0.0;
  for (final p in pagos) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;
    final lk = (p['line_kind'] as String?)?.trim();
    final c = p['concepto']?.toString() ?? '';
    if (lk == kLineKindInteresMora || esPagoInteresMoraPorConcepto(c)) {
      final fp = p['fecha_pago']?.toString();
      if (fp == null) continue;
      final d = DateTime.tryParse(fp);
      if (d == null) continue;
      if (d.isAfter(inicioMora) || d.isAtSameMomentAs(inicioMora)) {
        suma += (p['monto'] as num).toDouble();
      }
    }
  }
  return double.parse(suma.toStringAsFixed(2));
}

