import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';

export 'mora_tracked_origen.dart' show MoraPendientePreviaDetalle;

/// Una cuota dentro del reparto de un pago de mora: lo que se debe por ella
/// ([pleno]) y lo que este cobro le [asignado].
class _ItemMora {
  final int numeroCuota;
  final String mesLabel;
  final int diasMora;
  final double pleno;

  /// `MoraCuotaDetalle` o `MoraPendientePreviaDetalle` de origen, para poder
  /// reconstruir la entrada con el importe recortado sin perder sus datos.
  final Object? origen;

  double asignado = 0;

  _ItemMora({
    required this.numeroCuota,
    required this.mesLabel,
    required this.diasMora,
    required this.pleno,
    this.origen,
  });

  /// La cuota queda cubierta a medias: hay que decirlo en el papel.
  bool get parcial => asignado < pleno - 0.01;
}

/// Copy y construcción de conceptos/PDF de mora (calendario vs pendiente previas).
///
/// Opción B: la mora de cuotas ya liquidadas nombra número(s) de cuota.
class MoraConceptoRotulo {
  MoraConceptoRotulo._();

  /// Fallback cuando no hay detalle de cuotas.
  static const conceptoPendientePreviasGenerico =
      'Mora pendiente de cuotas ya pagadas';

  static const checkboxSubtitle =
      'Quedó pendiente al cobrar cuotas sin toda la mora';

  static String labelPendientePrevias({
    List<MoraPendientePreviaDetalle> detalle = const [],
  }) {
    if (detalle.isEmpty) return conceptoPendientePreviasGenerico;
    return _tituloPendiente(detalle.map((d) => d.numeroCuota).toList());
  }

  /// Compat: label corto tipo perdón/admin.
  static const labelPendientePreviasCorto = 'Mora pendiente de cuotas ya pagadas';

  /// Concepto solo-pendiente persistido.
  static String conceptoPendientePrevias({
    List<MoraPendientePreviaDetalle> detalle = const [],
  }) {
    if (detalle.isEmpty) {
      return '$conceptoPendientePreviasGenerico$sufijoNoCobradaAlPagar';
    }
    final titulo = _tituloPendiente(detalle.map((d) => d.numeroCuota).toList());
    return '$titulo$sufijoNoCobradaAlPagar';
  }

  /// Sufijo del concepto persistido de un arrastre. Nombra el **origen** ("no se
  /// cobró cuando se pagó esa cuota"), no el estado de este movimiento.
  static const sufijoNoCobradaAlPagar = ' (no cobrada al pagar)';

  /// Cómo se lee en la ficha una fila de mora ya cobrada.
  ///
  /// El concepto persistido es una clave (`esPagoInteresMoraPorConcepto`,
  /// `MoraTrackedRecovery`, `recalcularSaldoDesdePagos`) escrita en idioma de
  /// origen: "Mora pendiente cuota 3 (no cobrada al pagar)" quiere decir que esa
  /// mora quedó sin cobrar **cuando se pagó la cuota 3**. En el estado de cuenta
  /// esa misma frase queda arriba de $3.150 que sí entraron, y se lee como que el
  /// cobro no se hizo (recibo Nº 11408158, VIZGARRA 08/07/2026). Acá se traduce:
  /// el título dice de qué cuota es y el subtexto dice que se cobró en este pago.
  ///
  /// Los conceptos que ya se entienden —`Interés mora cuota 3 (vto Jun 2026)`—
  /// vuelven intactos y sin subtexto.
  static ({String titulo, String? subtexto}) rotuloFichaMora(String concepto) {
    final t = concepto.trim();
    if (!t.contains(sufijoNoCobradaAlPagar)) {
      return (titulo: t, subtexto: null);
    }
    final sinSufijo = t.replaceAll(sufijoNoCobradaAlPagar, '').trim();

    final nums = numerosCuotaPendienteDesdeConcepto(sinSufijo);
    if (nums.isEmpty) {
      return (
        titulo: 'Mora de cuotas ya pagadas',
        subtexto: 'Quedaba de cobros anteriores · se cobró en este pago',
      );
    }
    if (nums.length == 1) {
      return (
        titulo: 'Mora de la cuota ${nums.first}',
        subtexto:
            'Quedaba de cuando se pagó la cuota ${nums.first} · se cobró en este pago',
      );
    }
    final head = nums.sublist(0, nums.length - 1).join(', ');
    return (
      titulo: 'Mora de las cuotas $head y ${nums.last}',
      subtexto: 'Quedaba de cuando se pagaron esas cuotas · se cobró en este pago',
    );
  }

  /// Números de "Mora pendiente cuota 3" / "Mora pendiente cuotas 2 y 3".
  /// Vacío en el genérico "Mora pendiente de cuotas ya pagadas".
  ///
  /// El concepto persistido ya sabe de qué cuota es el arrastre. Cuando la
  /// reconstrucción desde el historial no llega (`MoraTrackedOrigen.inferir`
  /// vuelve vacía), esto evita que el papel diga "de cuotas ya pagadas" mientras
  /// la ficha, leyendo el mismo texto, dice "cuota 3".
  static List<int> numerosCuotaPendienteDesdeConcepto(String concepto) {
    final titulo = concepto.replaceAll(sufijoNoCobradaAlPagar, '').trim();
    final m = RegExp(
      r'mora pendiente cuotas?\s+([\d,\sy]+)$',
      caseSensitive: false,
    ).firstMatch(titulo);
    if (m == null) return const [];
    final nums = RegExp(r'\d+')
        .allMatches(m.group(1)!)
        .map((x) => int.parse(x.group(0)!))
        .toSet()
        .toList()
      ..sort();
    return nums;
  }

  /// `Interés mora cuota 3 (vto Jun 2026)` → 3. Null si no nombra una cuota.
  static int? numeroCuotaCalendarioDesdeConcepto(String concepto) {
    final m = RegExp(
      r'int[eé]r[eé]s\s*mora\s*cuota\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(concepto);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static String? subtextoPendientePrevias({
    List<MoraPendientePreviaDetalle> detalle = const [],
  }) {
    if (detalle.isEmpty) {
      return 'No cobrada en cobros anteriores';
    }
    if (detalle.length == 1) return detalle.first.subtextoDetalle;
    return detalle.map((d) => 'C${d.numeroCuota}: ${d.subtextoDetalle}').join(' · ');
  }

  static String resumenPendientePrevias(
    String montoFmt, {
    List<MoraPendientePreviaDetalle> detalle = const [],
  }) {
    final titulo = labelPendientePrevias(detalle: detalle);
    return '$titulo: $montoFmt';
  }

  static String checkboxPendientePrevias(
    String montoFmt, {
    List<MoraPendientePreviaDetalle> detalle = const [],
  }) {
    final titulo = labelPendientePrevias(detalle: detalle);
    return 'Incluir $titulo ($montoFmt)';
  }

  /// Desglose del arrastre, una entrada por cuota, con sus días y su monto.
  ///
  /// Ej.: `C2 (May) 23 días $6.900 · C3 (Jun) 27 días $8.100`. El arrastre queda
  /// congelado al momento del cobro, así que los días son los que tenía la
  /// cuota cuando se liquidó, no los de hoy.
  static String desgloseArrastre(
    List<MoraPendientePreviaDetalle> detalle, {
    required String Function(double) formatoMonto,
  }) {
    if (detalle.isEmpty) return '';
    return detalle.map((d) {
      final mes = d.mesLabel.split(' ').first;
      final cuota = mes.isEmpty ? 'C${d.numeroCuota}' : 'C${d.numeroCuota} ($mes)';
      final dias = d.diasMora > 0
          ? ' ${d.diasMora} ${d.diasMora == 1 ? 'día' : 'días'}'
          : '';
      return '$cuota$dias ${formatoMonto(d.montoAtribuido)}';
    }).join(' · ');
  }

  /// De dónde viene la mora que queda debiendo, para el aviso del recibo.
  ///
  /// Dos bloques, para que la familia distinga:
  ///  - cuotas vencidas todavía impagas;
  ///  - remanente: interés que no se cobró cuando se pagó esa cuota.
  ///
  /// [maxCuotas] recorta **cada** bloque (el recibo entra en una hoja; el
  /// detalle completo vive en el estado de cuenta).
  static String origenMoraPendienteLinea({
    required List<MoraCuotaDetalle> desglose,
    required String Function(double) formatoMonto,
    double tracked = 0,
    List<MoraPendientePreviaDetalle> trackedDetalle = const [],
    int maxCuotas = 3,
  }) {
    String parte(int numeroCuota, String mesLabel, int diasMora, double monto) {
      final mes = mesLabel.split(' ').first;
      final entre = [
        if (mes.isNotEmpty) mes,
        if (diasMora > 0) '$diasMora d',
      ].join(', ');
      final cuando = entre.isEmpty ? '' : ' ($entre)';
      return 'cuota $numeroCuota$cuando ${formatoMonto(monto)}';
    }

    String recortar(List<({int cuota, String texto})> items) {
      final ordenados = [...items]..sort((a, b) => a.cuota.compareTo(b.cuota));
      final partes = <String>[];
      var omitidas = 0;
      for (final i in ordenados) {
        if (partes.length >= maxCuotas) {
          omitidas++;
          continue;
        }
        partes.add(i.texto);
      }
      if (omitidas > 0) {
        partes.add('y $omitidas ${omitidas == 1 ? 'cuota' : 'cuotas'} más');
      }
      return partes.join(' · ');
    }

    final vencidas = <({int cuota, String texto})>[
      for (final d in desglose)
        if (d.interesBruto > 0.01)
          (
            cuota: d.numeroCuota,
            texto: parte(
              d.numeroCuota,
              d.mesLabel,
              d.diasMora,
              d.interesBruto,
            ),
          ),
    ];

    final remanentes = <({int cuota, String texto})>[];
    String? remanenteSinDetalle;
    if (tracked > 0.01) {
      final previas =
          trackedDetalle.where((d) => d.montoAtribuido > 0.01).toList();
      if (previas.isEmpty) {
        remanenteSinDetalle = 'cuotas ya pagadas ${formatoMonto(tracked)}';
      } else {
        for (final d in previas) {
          remanentes.add((
            cuota: d.numeroCuota,
            texto: parte(
              d.numeroCuota,
              d.mesLabel,
              d.diasMora,
              d.montoAtribuido,
            ),
          ));
        }
      }
    }

    final bloques = <String>[];
    if (vencidas.isNotEmpty) {
      bloques.add('Mora de cuotas vencidas: ${recortar(vencidas)}');
    }
    if (remanentes.isNotEmpty) {
      bloques.add('Mora no cobrada al pagar: ${recortar(remanentes)}');
    } else if (remanenteSinDetalle != null) {
      bloques.add('Mora no cobrada al pagar ($remanenteSinDetalle)');
    }
    if (bloques.isEmpty) return '';
    return '${bloques.join('. ')}.';
  }

  static String calendarioCuota({
    required int numeroCuota,
    required String mesLabel,
  }) =>
      'Interés mora cuota $numeroCuota (vto $mesLabel)';

  // Sin subtexto de días: el rótulo de la línea ya los dice ("Mora — 27 días
  // fuera de término") y una segunda línea con el mismo número gasta papel.

  static String _tituloPendiente(List<int> nums) {
    final uniq = nums.toSet().toList()..sort();
    if (uniq.isEmpty) return conceptoPendientePreviasGenerico;
    if (uniq.length == 1) return 'Mora pendiente cuota ${uniq.first}';
    if (uniq.length == 2) {
      return 'Mora pendiente cuotas ${uniq[0]} y ${uniq[1]}';
    }
    final head = uniq.sublist(0, uniq.length - 1).join(', ');
    return 'Mora pendiente cuotas $head y ${uniq.last}';
  }

  static String _sufijoPendiente(List<MoraPendientePreviaDetalle> detalle) {
    if (detalle.isEmpty) return ' + mora pendiente de cuotas ya pagadas';
    final nums = detalle.map((d) => d.numeroCuota).toList();
    final uniq = nums.toSet().toList()..sort();
    if (uniq.length == 1) return ' + mora pendiente cuota ${uniq.first}';
    if (uniq.length == 2) {
      return ' + mora pendiente cuotas ${uniq[0]} y ${uniq[1]}';
    }
    final head = uniq.sublist(0, uniq.length - 1).join(', ');
    return ' + mora pendiente cuotas $head y ${uniq.last}';
  }

  /// Concepto único persistido en `pagos_contrato_alumno.concepto`.
  static String conceptoPersistido({
    required List<MoraCuotaDetalle> detallesCalendario,
    required double montoPendientePrevias,
    required double montoTotal,
    List<MoraPendientePreviaDetalle> detallePendiente = const [],
  }) {
    final pendiente = montoPendientePrevias > 0.01;
    final dets = detallesCalendario
        .where((d) => d.interesBruto > 0.01)
        .toList();

    if (dets.isEmpty && pendiente) {
      return conceptoPendientePrevias(detalle: detallePendiente);
    }
    if (dets.length == 1 && !pendiente) {
      return calendarioCuota(
        numeroCuota: dets.first.numeroCuota,
        mesLabel: dets.first.mesLabel,
      );
    }
    if (dets.length == 1 && pendiente) {
      final d = dets.first;
      return '${calendarioCuota(numeroCuota: d.numeroCuota, mesLabel: d.mesLabel)}'
          '${_sufijoPendiente(detallePendiente)}';
    }
    if (dets.length > 1 && !pendiente) {
      final nums = dets.map((d) => d.numeroCuota).join(', ');
      final meses = dets.map((d) => d.mesLabel.split(' ').first).join(', ');
      return 'Interés mora cuotas $nums (vto $meses)';
    }
    if (dets.length > 1 && pendiente) {
      final nums = dets.map((d) => d.numeroCuota).join(', ');
      return 'Interés mora cuotas $nums${_sufijoPendiente(detallePendiente)}';
    }
    if (montoTotal > 0.01) {
      return 'Interés mora (cuota base — este cobro)';
    }
    return conceptoPendientePrevias(detalle: detallePendiente);
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));

  /// Sufijo de la cuota que este cobro cubre solo en parte.
  static const sufijoParcial = ' (parcial)';

  /// Reparto de un pago **parcial** de mora entre las cuotas involucradas.
  ///
  /// El monto que entrega la familia puede ser menor que la mora seleccionada
  /// (mora $45.000, entrega $15.000). Sin este reparto, cada línea se emite por
  /// su importe completo y el papel termina sumando más de lo que se cobró.
  ///
  /// Orden espejado de `MoraCuotaCalculator.postCobroTrackedOffset`, para que el
  /// papel no contradiga el saldo que queda en la ficha:
  ///  - si el pago entra entero en el arrastre, va todo al arrastre;
  ///  - si no, primero las cuotas vencidas del calendario (de la más vieja a la
  ///    más nueva) y el resto al arrastre.
  ///
  /// **No hace nada** si lo cobrado alcanza para todo: un cobro de mora completa
  /// y las reimpresiones históricas salen exactamente igual que antes.
  static ({
    List<MoraCuotaDetalle> calendario,
    double pendientePrevias,
    List<MoraPendientePreviaDetalle> detallePendiente,
  })
  repartirMoraParcial({
    required double montoTotal,
    required List<MoraCuotaDetalle> calendario,
    required double pendientePrevias,
    required List<MoraPendientePreviaDetalle> detallePendiente,
  }) {
    final total = _r2(montoTotal.clamp(0.0, double.infinity));
    final pend = _r2(pendientePrevias.clamp(0.0, double.infinity));
    final sumCal = _r2(
      calendario.fold<double>(0, (s, d) => s + d.interesBruto),
    );

    if (_r2(sumCal + pend) <= total + 0.01) {
      return (
        calendario: calendario,
        pendientePrevias: pend,
        detallePendiente: detallePendiente,
      );
    }

    final calItems = [
      for (final d in calendario)
        _ItemMora(
          numeroCuota: d.numeroCuota,
          mesLabel: d.mesLabel,
          diasMora: d.diasMora,
          pleno: _r2(d.interesBruto),
          origen: d,
        ),
    ]..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));
    final arrItems = [
      for (final d in detallePendiente)
        _ItemMora(
          numeroCuota: d.numeroCuota,
          mesLabel: d.mesLabel,
          diasMora: d.diasMora,
          pleno: _r2(d.montoAtribuido),
          origen: d,
        ),
    ]..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));

    final double pendAsignado;
    if (pend > 0.01 && total <= pend + 0.01) {
      pendAsignado = total;
      _asignarFifo(arrItems, total);
    } else {
      final usadoCal = _asignarFifo(calItems, total);
      pendAsignado = _r2((total - usadoCal).clamp(0.0, pend));
      _asignarFifo(arrItems, pendAsignado);
    }

    return (
      calendario: [
        for (final it in calItems)
          if (it.asignado > 0.01)
            _conInteres(it.origen as MoraCuotaDetalle, it.asignado),
      ],
      pendientePrevias: pendAsignado,
      detallePendiente: [
        for (final it in arrItems)
          if (it.asignado > 0.01)
            _conAtribuido(
              it.origen as MoraPendientePreviaDetalle,
              it.asignado,
            ),
      ],
    );
  }

  /// Consume [disponible] saldando cada ítem entero hasta agotarlo; el último
  /// queda parcial y los siguientes en cero. Devuelve lo efectivamente usado.
  /// La lista tiene que venir ordenada FIFO.
  static double _asignarFifo(List<_ItemMora> items, double disponible) {
    var resto = disponible;
    var usado = 0.0;
    for (final it in items) {
      if (resto <= 0.01) break;
      final a = _r2(it.pleno <= resto ? it.pleno : resto);
      if (a <= 0.01) continue;
      it.asignado = a;
      resto = _r2(resto - a);
      usado = _r2(usado + a);
    }
    return usado;
  }

  /// Copia con otro importe. `moraDebida`, `diasMora`, `vencimiento` y
  /// `fechaPagoCuota` se conservan: son los que explican **cuánto se debía**, y
  /// si se recortaran el recibo diría que solo se debía lo parcial.
  static MoraPendientePreviaDetalle _conAtribuido(
    MoraPendientePreviaDetalle d,
    double monto,
  ) => MoraPendientePreviaDetalle(
    numeroCuota: d.numeroCuota,
    mesLabel: d.mesLabel,
    montoAtribuido: monto,
    fechaPagoCuota: d.fechaPagoCuota,
    moraDebida: d.moraDebida > 0.01 ? d.moraDebida : d.montoAtribuido,
    moraCobrada: d.moraCobrada,
    diasMora: d.diasMora,
    vencimiento: d.vencimiento,
  );

  static MoraCuotaDetalle _conInteres(MoraCuotaDetalle d, double monto) =>
      MoraCuotaDetalle(
        numeroCuota: d.numeroCuota,
        vencimiento: d.vencimiento,
        diasMora: d.diasMora,
        interesBruto: monto,
        mesLabel: d.mesLabel,
      );

  /// Preview de una línea de mora para el modal (una fila en `previewConceptos`).
  static Map<String, dynamic> construirPreviewMora({
    required double montoTotal,
    required List<MoraCuotaDetalle> detallesCalendario,
    required double montoPendientePrevias,
    required String lineKind,
    List<MoraPendientePreviaDetalle> detallePendiente = const [],
  }) {
    final g = double.parse(
      montoTotal.clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    // El rótulo tiene que nombrar solo las cuotas que este cobro cubre. Sin
    // esto, un parcial sobre las cuotas 3 y 5 se guardaba como "Interés mora
    // cuotas 3, 5" aunque solo se hubiera cubierto la 3.
    final repartido = repartirMoraParcial(
      montoTotal: g,
      calendario: detallesCalendario,
      pendientePrevias: montoPendientePrevias,
      detallePendiente: detallePendiente,
    );
    final pendiente = repartido.pendientePrevias;
    final dets = List<MoraCuotaDetalle>.from(repartido.calendario);
    final detPrev = List<MoraPendientePreviaDetalle>.from(
      repartido.detallePendiente,
    );
    final concepto = conceptoPersistido(
      detallesCalendario: dets,
      montoPendientePrevias: pendiente,
      montoTotal: g,
      detallePendiente: detPrev,
    );
    return {
      'concepto': concepto,
      'monto': g,
      'gross': g,
      'cuotas': 0,
      'lineKind': lineKind,
      'moraPendientePrevias': pendiente,
      // `montoPleno` es lo que se debe por esa cuota; `monto` lo que este cobro
      // le asigna. Guardar los dos es lo que después permite emitir la línea por
      // el importe parcial y marcarla como tal.
      'moraDesglose': dets
          .map(
            (d) => <String, dynamic>{
              'numeroCuota': d.numeroCuota,
              'mesLabel': d.mesLabel,
              'monto': d.interesBruto,
              'montoPleno': _plenoCalendario(detallesCalendario, d),
              'diasMora': d.diasMora,
            },
          )
          .toList(),
      'moraPendientePreviasDetalle': detPrev
          .map(
            (d) => <String, dynamic>{
              'numeroCuota': d.numeroCuota,
              'mesLabel': d.mesLabel,
              'monto': d.montoAtribuido,
              'montoPleno': _plenoArrastre(detallePendiente, d),
              'moraDebida': d.moraDebida,
              'moraCobrada': d.moraCobrada,
              'fechaPagoCuota': d.fechaPagoCuota?.toIso8601String(),
              'subtexto': d.subtextoDetalle,
            },
          )
          .toList(),
    };
  }

  static double _plenoCalendario(
    List<MoraCuotaDetalle> originales,
    MoraCuotaDetalle reducida,
  ) {
    for (final o in originales) {
      if (o.numeroCuota == reducida.numeroCuota) return o.interesBruto;
    }
    return reducida.interesBruto;
  }

  static double _plenoArrastre(
    List<MoraPendientePreviaDetalle> originales,
    MoraPendientePreviaDetalle reducida,
  ) {
    for (final o in originales) {
      if (o.numeroCuota == reducida.numeroCuota) return o.montoAtribuido;
    }
    return reducida.montoAtribuido;
  }

  /// Expande preview de mora a filas UI (calendario + pendiente), como el PDF.
  static List<Map<String, dynamic>> filasPreviewDesdeMora(
    Map<String, dynamic> conc,
  ) {
    final desg =
        (conc['moraDesglose'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final detRaw =
        (conc['moraPendientePreviasDetalle'] as List?)
            ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final pendiente = (conc['moraPendientePrevias'] as num?)?.toDouble() ?? 0;
    final total = (conc['monto'] as num?)?.toDouble() ?? 0;
    final lineas = lineasPdfDesdePreviewMora(
      montoTotal: total,
      moraDesglose: desg,
      moraPendientePrevias: pendiente,
      detallePendiente: _detalleDesdeMaps(detRaw),
      conceptoFallback: conc['concepto'] as String?,
    );
    return lineas
        .map(
          (l) => <String, dynamic>{
            'concepto': l['concepto'],
            'monto': l['monto'],
            'gross': l['monto'],
            'cuotas': 0,
            'lineKind': conc['lineKind'],
            'esMora': true,
            if (l['numeroCuota'] != null) 'numeroCuota': l['numeroCuota'],
            if (l['cuotaPrevia'] != null) 'cuotaPrevia': l['cuotaPrevia'],
            if (l['diasMora'] != null) 'diasMora': l['diasMora'],
            if (l['mesCuotaPrevia'] != null)
              'mesCuotaPrevia': l['mesCuotaPrevia'],
            if (l['subtexto'] != null) 'subtexto': l['subtexto'],
          },
        )
        .toList();
  }

  static List<MoraPendientePreviaDetalle> _detalleDesdeMaps(
    List<Map<String, dynamic>> raw,
  ) {
    return raw.map((m) {
      DateTime? fp;
      final fs = m['fechaPagoCuota']?.toString();
      if (fs != null && fs.isNotEmpty) fp = DateTime.tryParse(fs);
      return MoraPendientePreviaDetalle(
        numeroCuota: (m['numeroCuota'] as num?)?.toInt() ?? 0,
        mesLabel: (m['mesLabel'] as String?) ?? '',
        // Lo pleno, no lo ya recortado: el reparto se rehace en la emisión y
        // necesita saber cuánto se debe para marcar la cuota como parcial.
        montoAtribuido:
            ((m['montoPleno'] ?? m['monto']) as num?)?.toDouble() ?? 0,
        fechaPagoCuota: fp,
        moraDebida: (m['moraDebida'] as num?)?.toDouble() ?? 0,
        moraCobrada: (m['moraCobrada'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  /// Líneas de PDF/recibo: calendario + pendiente por cuota (Opción B).
  static List<Map<String, dynamic>> lineasPdfDesdePreviewMora({
    required double montoTotal,
    List<Map<String, dynamic>>? moraDesglose,
    double? moraPendientePrevias,
    List<MoraPendientePreviaDetalle>? detallePendiente,
    String? conceptoFallback,
  }) {
    final total = double.parse(
      montoTotal.clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    final desg = moraDesglose ?? const <Map<String, dynamic>>[];
    final sumDesg = desg.fold<double>(
      0,
      (s, d) => s + ((d['monto'] as num?)?.toDouble() ?? 0),
    );
    var pendiente = moraPendientePrevias;
    if (pendiente == null || pendiente < 0) {
      pendiente = double.parse(
        (total - sumDesg).clamp(0.0, double.infinity).toStringAsFixed(2),
      );
    } else {
      pendiente = double.parse(pendiente.toStringAsFixed(2));
    }

    final out = <Map<String, dynamic>>[];
    final dets = detallePendiente ?? const <MoraPendientePreviaDetalle>[];

    // Reparto del pago parcial. `montoPleno` (si viene) es lo que se debe por
    // esa cuota; si no viene, el propio `monto` hace de pleno — así el camino
    // histórico, que arma el desglose desde el pago ya guardado, también queda
    // acotado a lo que realmente se cobró.
    final calItems = [
      for (final d in desg)
        _ItemMora(
          numeroCuota: (d['numeroCuota'] as num?)?.toInt() ?? 0,
          mesLabel: (d['mesLabel'] as String?)?.trim() ?? '',
          diasMora: (d['diasMora'] as num?)?.toInt() ?? 0,
          pleno: _r2(
            ((d['montoPleno'] ?? d['monto']) as num?)?.toDouble() ?? 0,
          ),
        ),
    ]..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));
    final arrItems = [
      for (final d in dets)
        _ItemMora(
          numeroCuota: d.numeroCuota,
          mesLabel: d.mesLabel,
          diasMora: d.diasMora,
          pleno: _r2(d.montoAtribuido),
          origen: d,
        ),
    ]..sort((a, b) => a.numeroCuota.compareTo(b.numeroCuota));

    // Mismo orden que el libro mayor: si el pago entra entero en el arrastre va
    // todo ahí; si no, primero el calendario y el resto al arrastre.
    final double pendAsignado;
    if (pendiente > 0.01 && total <= pendiente + 0.01) {
      pendAsignado = _r2(total.clamp(0.0, pendiente));
      _asignarFifo(arrItems, pendAsignado);
    } else {
      final usadoCal = _asignarFifo(calItems, total);
      pendAsignado = _r2((total - usadoCal).clamp(0.0, pendiente));
      _asignarFifo(arrItems, pendAsignado);
    }

    for (final it in calItems) {
      if (it.asignado <= 0.01) continue;
      out.add({
        'concepto':
            calendarioCuota(numeroCuota: it.numeroCuota, mesLabel: it.mesLabel) +
            (it.parcial ? sufijoParcial : ''),
        'monto': it.asignado,
        'esMora': true,
        // Para anidar la mora bajo su cuota en el PDF (no altera [concepto],
        // que es la clave que reconocen los detectores de pago_interes_mora).
        if (it.numeroCuota > 0) 'numeroCuota': it.numeroCuota,
        if (it.diasMora > 0) 'diasMora': it.diasMora,
      });
    }

    if (pendAsignado > 0.01) {
      var sumDet = 0.0;
      for (final it in arrItems) {
        if (it.asignado <= 0.01) continue;
        final d = it.origen as MoraPendientePreviaDetalle;
        sumDet = _r2(sumDet + it.asignado);
        out.add({
          'concepto':
              'Mora pendiente cuota ${it.numeroCuota}'
              '${it.parcial ? sufijoParcial : ''}',
          'monto': it.asignado,
          'esMora': true,
          // Cuota ya pagada en un cobro anterior: no se anida bajo ninguna
          // línea de este cobro, va al bloque de arrastre.
          'cuotaPrevia': it.numeroCuota,
          if (it.mesLabel.isNotEmpty) 'mesCuotaPrevia': it.mesLabel,
          if (it.diasMora > 0) 'diasMora': it.diasMora,
          'subtexto': d.subtextoDetalle,
        });
      }
      // Lo que quedó sin detalle que lo explique: línea genérica residual. El
      // rótulo ya dice "no cobrada en su momento", así que no lleva subtexto.
      final resto = _r2(pendAsignado - sumDet);
      if (resto > 0.01) {
        out.add({
          'concepto': conceptoPendientePreviasGenerico,
          'monto': resto,
          'esMora': true,
        });
      }
    }

    if (out.isEmpty && total > 0.01) {
      final c = (conceptoFallback ?? '').trim();
      out.add({
        'concepto': c.isNotEmpty
            ? c
            : 'Interés mora (cuota base — este cobro)',
        'monto': total,
        'esMora': true,
      });
    }

    if (out.isNotEmpty) {
      final sumOut = out.fold<double>(
        0,
        (s, e) => s + (e['monto'] as num).toDouble(),
      );
      final delta = double.parse((total - sumOut).toStringAsFixed(2));
      if (delta.abs() > 0.001 && delta.abs() <= 0.05) {
        final last = Map<String, dynamic>.from(out.last);
        last['monto'] = double.parse(
          ((last['monto'] as num).toDouble() + delta).toStringAsFixed(2),
        );
        out[out.length - 1] = last;
      }
    }

    return out;
  }
}
