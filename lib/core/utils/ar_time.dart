/// Anclaje temporal ESTRICTO para Argentina (America/Argentina/Buenos_Aires, GMT-3).
///
/// Política de diseño (no-destructiva):
///  - No se tocan los esquemas: las fechas siguen almacenándose en columnas existentes
///    (`fecha_pago`, `fecha`, `created_at`) como ISO-8601 UTC, instante exacto.
///  - Para TODA lectura visible (recibos, listados, PDFs) se convierte a hora local de
///    Buenos Aires con offset fijo de -3h (Argentina no adhiere a DST desde 2009),
///    garantizando validez legal/administrativa independientemente del reloj del equipo.
///
/// Uso rápido:
///   - `ArTime.nowUtcIso()` → string para guardar en DB (instante preciso).
///   - `ArTime.nowAr()` → DateTime con paredes (horas/minutos) en huso AR.
///   - `ArTime.toAr(dt)` → convierte cualquier DateTime al huso AR.
///   - `ArTime.formatFechaHora(dt)` → "18/04/2026 14:37 hs".
///   - `ArTime.operacionGestionada(dt)` → "Operación gestionada el 18 de abril a las 14:37 hs".
library;

class ArTime {
  /// Identificador legal de la zona horaria de referencia.
  static const String tzName = 'America/Argentina/Buenos_Aires';

  /// Offset fijo -3h. Argentina no observa DST desde 2009, por lo que el offset
  /// es constante y la conversión por suma/resta es jurídicamente equivalente a
  /// la zona IANA sin requerir tzdata embebida.
  static const Duration offset = Duration(hours: -3);

  static const List<String> _mesesLargos = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static const List<String> _diasSemana = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];

  // ── Instante preciso ──────────────────────────────────────────────────────

  /// Instante actual en UTC (canónico). Usar como origen de verdad temporal.
  static DateTime nowUtc() => DateTime.now().toUtc();

  /// ISO-8601 UTC del instante actual. Formato recomendado para persistencia.
  static String nowUtcIso() => nowUtc().toIso8601String();

  // ── Conversión a huso AR ─────────────────────────────────────────────────

  /// Convierte cualquier [dt] (local o UTC) al reloj de pared de Buenos Aires.
  ///
  /// El [DateTime] retornado porta los componentes (year/month/day/hour/minute)
  /// ya ajustados a AR. Internamente se marca como UTC para evitar que el SO
  /// vuelva a aplicarle su propio offset al leer las partes.
  static DateTime toAr(DateTime dt) => dt.toUtc().add(offset);

  /// Instante actual expresado en reloj AR.
  static DateTime nowAr() => toAr(nowUtc());

  // ── Formatos legibles (Argentina) ────────────────────────────────────────

  /// "DD/MM/YYYY"
  static String formatFechaCorta(DateTime dt) {
    final ar = toAr(dt);
    return '${_pad2(ar.day)}/${_pad2(ar.month)}/${ar.year}';
  }

  /// "HH:mm hs" (24 h)
  static String formatHora(DateTime dt) {
    final ar = toAr(dt);
    return '${_pad2(ar.hour)}:${_pad2(ar.minute)} hs';
  }

  /// "DD/MM/YYYY HH:mm hs"
  static String formatFechaHora(DateTime dt) {
    final ar = toAr(dt);
    return '${_pad2(ar.day)}/${_pad2(ar.month)}/${ar.year} '
        '${_pad2(ar.hour)}:${_pad2(ar.minute)} hs';
  }

  /// "18 de abril de 2026"
  static String formatFechaLarga(DateTime dt) {
    final ar = toAr(dt);
    return '${ar.day} de ${_mesesLargos[ar.month - 1]} de ${ar.year}';
  }

  /// "Sábado 18 de abril"
  static String formatDiaMes(DateTime dt) {
    final ar = toAr(dt);
    final diaSemana = _diasSemana[(ar.weekday - 1).clamp(0, 6)];
    final cap = diaSemana.substring(0, 1).toUpperCase() + diaSemana.substring(1);
    return '$cap ${ar.day} de ${_mesesLargos[ar.month - 1]}';
  }

  /// Frase canónica para recibos/comprobantes:
  /// "Operación gestionada el Sábado 18 de abril a las 14:37 hs"
  static String operacionGestionada(DateTime dt) {
    return 'Operación gestionada el ${formatDiaMes(dt)} a las ${formatHora(dt)}';
  }

  /// Variante compacta para encabezados (sin día de la semana):
  /// "18/04/2026 · 14:37 hs"
  static String formatCompactoRecibo(DateTime dt) {
    final ar = toAr(dt);
    return '${_pad2(ar.day)}/${_pad2(ar.month)}/${ar.year} · '
        '${_pad2(ar.hour)}:${_pad2(ar.minute)} hs';
  }

  // ── Comparación por mes/día en huso AR ───────────────────────────────────

  /// `true` si [dt] cae en el mismo mes/año de [ref] (ambos comparados en AR).
  static bool mismoMes(DateTime dt, DateTime ref) {
    final a = toAr(dt);
    final b = toAr(ref);
    return a.year == b.year && a.month == b.month;
  }

  /// `true` si [dt] cae en el mismo día calendario de [ref] (ambos en AR).
  static bool mismoDia(DateTime dt, DateTime ref) {
    final a = toAr(dt);
    final b = toAr(ref);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}
