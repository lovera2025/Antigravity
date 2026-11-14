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
  // Cobro solo del tracked remanente (cuota pagada sin mora en su día).
  if (folded.contains('mora remanente')) return true;
  if (folded.contains('mora de cuotas ya pagadas')) return true;
  if (folded.contains('mora cuotas ya pagadas')) return true;
  if (folded.contains('mora pendiente cuota')) return true;
  if (folded.contains('mora pendiente de cuotas')) return true;
  return folded.contains('interes') && folded.contains('mora');
}

/// Heurística estable para reconocer líneas de **cargo por canal** (recargo de transferencia)
/// en [pagos_contrato_alumno]. Solo ingreso; no liquidan capital.
bool esPagoCargoCanalPorConcepto(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  final lowered = raw.toLowerCase();
  final stripped = _stripCombiningMarks(lowered);
  final folded = foldDiacriticosLatin(stripped);
  return folded.contains('cargo canal') || folded.contains('cargo oper') || folded.contains('recargo transfer');
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


String _plegarConcepto(String raw) =>
    foldDiacriticosLatin(_stripCombiningMarks(raw.toLowerCase()));

/// La línea de mora dice que paga mora que **quedó sin cobrar** cuando se pagó
/// otra cuota (el arrastre): `Mora pendiente cuotas 1 y 2 (no cobrada al
/// pagar)`, o el sufijo `… + mora pendiente cuota 6` de una mixta.
///
/// Se usa solo sobre líneas que ya se sabe que son de mora: con eso alcanza
/// para que `MoraTrackedOrigen.inferir` reparta la plata donde la línea dice,
/// en vez de dársela a la cuota que se pagó ese mismo día.
bool mencionaArrastre(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  final f = _plegarConcepto(raw);
  return f.contains('mora pendiente') ||
      f.contains('cuotas ya pagadas') ||
      f.contains('mora remanente') ||
      f.contains('+ remanente') ||
      f.contains('no cobrada al pagar');
}

/// Las cuotas del calendario que nombra una línea de mora, en el orden en que
/// las escribe: `Interés mora cuotas 3, 4 + mora pendiente cuota 2` → `[3, 4]`.
///
/// Solo la lista de **antes** del primer ` + ` (lo de después es el arrastre),
/// y solo los números de la lista: el año de `(vto Oct 2026)` no cuenta.
/// `Interés mora (cuota base — este cobro)` no nombra ninguna: vacía.
List<int> cuotasDeCalendarioEnConcepto(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final f = _plegarConcepto(raw);
  final corte = f.indexOf(' + ');
  final antes = corte >= 0 ? f.substring(0, corte) : f;
  final m = RegExp(
    r'interes\s*mora\s*cuotas?\s+(\d+(?:\s*,\s*\d+)*)',
  ).firstMatch(antes);
  if (m == null) return const [];
  return RegExp(r'\d+')
      .allMatches(m.group(1)!)
      .map((x) => int.parse(x.group(0)!))
      .toList();
}
