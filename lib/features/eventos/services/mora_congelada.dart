import 'dart:convert';

/// Congelar la mora (6.2.1): el jefe congela la mora de un alumno, cuota por
/// cuota o entera ("Todas", también las cuotas que se venzan mientras dure).
///
/// **Nunca cambia una fecha: resta días.** La mora de una cuota sigue siendo
/// 1 % por día desde su vencimiento; los días que estuvo congelada no cuentan.
/// La vieja "fecha de corte" (`mora_fecha_referencia`, sacada en la 6.1.0)
/// reemplazaba la fecha: borrarla no cruzaba entre PCs y, al repasar cobros
/// viejos, inventaba mora. Acá cada pausa tiene su `desde`, y un repaso a una
/// fecha anterior no la ve.
///
/// Es Dart puro: la calculadora de la mora (`MoraCuotaCalculator`) lo lee por
/// el registro en memoria ([MoraCongelada.de]) y también entra en lo que se
/// arma para la web, que no tiene base local (ahí el registro queda vacío).
/// Quien lo carga desde la base es `MoraCongeladaRepository`.

/// Un tramo en que la mora no corre.
///
/// [cuota] null = todas las cuotas del alumno. [hasta] null = sigue. Los días
/// quietos son los de `(desde, hasta]`: el día que se congela todavía suma (la
/// mora queda en lo que tenía ese día) y el día que se descongela con
/// "Mantener" también queda quieto.
class PausaMora {
  final int? cuota;
  final DateTime desde;
  final DateTime? hasta;

  PausaMora({this.cuota, required DateTime desde, DateTime? hasta})
      : desde = _dia(desde),
        hasta = hasta == null ? null : _dia(hasta);

  bool get abierta => hasta == null;
  bool get esDeTodas => cuota == null;
  bool tocaA(int n) => cuota == null || cuota == n;

  PausaMora cerradaEl(DateTime dia) =>
      PausaMora(cuota: cuota, desde: desde, hasta: dia);

  Map<String, dynamic> toJson() => {
        'cuota': cuota,
        'desde': _texto(desde),
        if (hasta != null) 'hasta': _texto(hasta!),
      };

  factory PausaMora.fromJson(Map<String, dynamic> j) => PausaMora(
        cuota: (j['cuota'] as num?)?.toInt(),
        desde: DateTime.parse(j['desde'] as String),
        hasta: j['hasta'] == null ? null : DateTime.parse(j['hasta'] as String),
      );

  @override
  bool operator ==(Object other) =>
      other is PausaMora &&
      other.cuota == cuota &&
      other.desde == desde &&
      other.hasta == hasta;

  @override
  int get hashCode => Object.hash(cuota, desde, hasta);

  @override
  String toString() =>
      'PausaMora(${cuota ?? 'todas'}, ${_texto(desde)} → ${hasta == null ? 'sigue' : _texto(hasta!)})';
}

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

String _texto(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Las pausas de un alumno.
class MoraCongelada {
  final List<PausaMora> pausas;

  const MoraCongelada(this.pausas);

  static const nada = MoraCongelada([]);

  bool get vacia => pausas.isEmpty;

  // ── El registro en memoria ───────────────────────────────────────────────
  //
  // La calculadora de la mora es estática y la usan unos quince lugares: en vez
  // de pasarle las pausas a cada uno, las lee de acá por el id del contrato.
  // Vacío por defecto: los tests y las herramientas de hoy dan lo mismo que
  // antes. No va en `ContratoAlumno`: esa fila se reescribe entera en tres
  // lugares y un campo nuevo se perdería en silencio.

  static final Map<String, MoraCongelada> _registro = {};

  static MoraCongelada de(String contratoId) => _registro[contratoId] ?? nada;

  /// Reemplaza todo el registro (al abrir y antes de revisar la mora).
  static void cargar(Map<String, MoraCongelada> todo) {
    _registro
      ..clear()
      ..addAll({
        for (final e in todo.entries)
          if (!e.value.vacia) e.key: e.value,
      });
  }

  /// Deja al día un solo alumno (al guardar desde esta PC).
  static void poner(String contratoId, MoraCongelada m) {
    if (m.vacia) {
      _registro.remove(contratoId);
    } else {
      _registro[contratoId] = m;
    }
  }

  /// Para los tests: el registro vuelve a vacío.
  static void vaciar() => _registro.clear();

  /// Corre [cuenta] como si el alumno tuviera las pausas [m], y deja el
  /// registro como estaba. Es para mostrar "Recalcular · $Y" antes de tocar:
  /// la cuenta es la misma de siempre, con otras pausas. Sincrónico a
  /// propósito: en el medio no corre nada más.
  static T conPausas<T>(String contratoId, MoraCongelada m, T Function() cuenta) {
    final antes = _registro[contratoId];
    poner(contratoId, m);
    try {
      return cuenta();
    } finally {
      if (antes == null) {
        _registro.remove(contratoId);
      } else {
        _registro[contratoId] = antes;
      }
    }
  }

  // ── La cuenta ────────────────────────────────────────────────────────────

  /// Días en que la mora de la cuota [cuota] no corrió, contados hasta [al]
  /// (el día de la cuenta: hoy, o el de un cobro viejo).
  ///
  /// Se cuentan solo desde [vencimientoEfectivo]: antes de vencer no había mora
  /// que congelar, y una cuota que vence durante una pausa de "Todas" queda en
  /// $0 mientras dure. Las pausas que se pisan se cuentan una sola vez.
  int diasQuietos({
    required int cuota,
    required DateTime vencimientoEfectivo,
    required DateTime al,
  }) {
    if (pausas.isEmpty) return 0;
    final venc = _dia(vencimientoEfectivo);
    final x = _dia(al);
    final tramos = <(DateTime, DateTime)>[];
    for (final p in pausas) {
      if (!p.tocaA(cuota)) continue;
      final ini = p.desde.isAfter(venc) ? p.desde : venc;
      final hastaP = p.hasta ?? x;
      final fin = hastaP.isBefore(x) ? hastaP : x;
      if (fin.isAfter(ini)) tramos.add((ini, fin));
    }
    if (tramos.isEmpty) return 0;
    tramos.sort((a, b) => a.$1.compareTo(b.$1));
    var total = 0;
    var (curIni, curFin) = tramos.first;
    for (final (ini, fin) in tramos.skip(1)) {
      if (!ini.isAfter(curFin)) {
        if (fin.isAfter(curFin)) curFin = fin;
      } else {
        total += curFin.difference(curIni).inDays;
        curIni = ini;
        curFin = fin;
      }
    }
    total += curFin.difference(curIni).inDays;
    return total;
  }

  /// ¿La mora de esta cuota está congelada hoy? (para el aviso celeste)
  bool congeladaHoy(int cuota) =>
      pausas.any((p) => p.abierta && p.tocaA(cuota));

  /// Congelada con "Todas": también las cuotas que se venzan.
  bool get todasCongeladas => pausas.any((p) => p.abierta && p.esDeTodas);

  /// Las cuotas congeladas una por una (sin contar "Todas").
  Set<int> get cuotasCongeladas => {
        for (final p in pausas)
          if (p.abierta && p.cuota != null) p.cuota!,
      };

  /// ¿Hay algo congelado hoy?
  bool get algoCongelado => pausas.any((p) => p.abierta);

  /// Desde cuándo está congelada (la pausa abierta más vieja), para "Mora
  /// congelada desde dd/mm".
  DateTime? get desde {
    DateTime? d;
    for (final p in pausas) {
      if (!p.abierta) continue;
      if (d == null || p.desde.isBefore(d)) d = p.desde;
    }
    return d;
  }

  /// Congela el día [dia]: las [cuotas] elegidas, o todas si [todas].
  MoraCongelada congelar({
    Set<int> cuotas = const {},
    bool todas = false,
    required DateTime dia,
  }) {
    final nuevas = <PausaMora>[...pausas];
    if (todas) {
      if (!todasCongeladas) nuevas.add(PausaMora(desde: dia));
    } else {
      for (final n in cuotas) {
        if (!congeladaHoy(n)) nuevas.add(PausaMora(cuota: n, desde: dia));
      }
    }
    return MoraCongelada(nuevas);
  }

  /// "Mantener ese precio": las pausas abiertas de esas cuotas se cierran el
  /// día [dia]. Lo congelado queda quieto para siempre y desde mañana vuelve a
  /// sumar. [cuotas] null = todo (lo que se congeló con "Todas").
  MoraCongelada mantener({Set<int>? cuotas, required DateTime dia}) {
    return MoraCongelada([
      for (final p in pausas)
        if (p.abierta && (cuotas == null || (p.cuota != null && cuotas.contains(p.cuota))))
          p.cerradaEl(dia)
        else
          p,
    ]._sinVacias());
  }

  /// "Recalcular": como si nunca se hubieran congelado, pero **solo las cuotas
  /// que todavía se deben**. Una cuota que se pagó mientras estaba congelada se
  /// cobró con la mora congelada, así quedó en la ficha y en el recibo: su
  /// pausa queda, para que el repaso de ese cobro dé lo mismo.
  ///
  /// [cuotas] null = todo. Con "Todas", la pausa se cambia por una cerrada para
  /// cada cuota ya pagada (`n ≤ cuotasPagadas`).
  MoraCongelada recalcular({
    Set<int>? cuotas,
    required int cuotasPagadas,
    required DateTime dia,
  }) {
    final out = <PausaMora>[];
    for (final p in pausas) {
      if (p.cuota != null) {
        final pagada = p.cuota! <= cuotasPagadas;
        final elegida = cuotas == null || cuotas.contains(p.cuota);
        if (pagada || !elegida) out.add(p);
        continue;
      }
      // Pausa de "Todas".
      if (cuotas != null) {
        out.add(p);
        continue;
      }
      for (var k = 1; k <= cuotasPagadas; k++) {
        out.add(PausaMora(cuota: k, desde: p.desde, hasta: p.hasta ?? dia));
      }
    }
    return MoraCongelada(out._sinVacias());
  }

  // ── El texto que va a la base ────────────────────────────────────────────

  String toJson() => jsonEncode([for (final p in pausas) p.toJson()]);

  factory MoraCongelada.fromJson(String? texto) {
    if (texto == null || texto.trim().isEmpty) return nada;
    final lista = jsonDecode(texto);
    if (lista is! List) return nada;
    return MoraCongelada([
      for (final e in lista)
        if (e is Map) PausaMora.fromJson(Map<String, dynamic>.from(e)),
    ]);
  }
}

extension on List<PausaMora> {
  /// Una pausa que se cerró el mismo día que se abrió no deja ningún día
  /// quieto: no hace falta guardarla.
  List<PausaMora> _sinVacias() =>
      where((p) => p.abierta || p.hasta!.isAfter(p.desde)).toList();
}
