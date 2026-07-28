import 'mora_cuota_calculator.dart';
import 'mora_tracked_origen.dart';

export 'mora_tracked_origen.dart' show MoraPendientePreviaDetalle;

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
      return '$conceptoPendientePreviasGenerico (no cobrada al pagar)';
    }
    final titulo = _tituloPendiente(detalle.map((d) => d.numeroCuota).toList());
    return '$titulo (no cobrada al pagar)';
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

  static String calendarioCuota({
    required int numeroCuota,
    required String mesLabel,
  }) =>
      'Interés mora cuota $numeroCuota (vto $mesLabel)';

  static String? subtextoCalendario(int diasMora) =>
      diasMora > 0 ? '$diasMora días de atraso' : null;

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
    final pendiente = double.parse(
      montoPendientePrevias.clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    final dets = List<MoraCuotaDetalle>.from(detallesCalendario);
    final detPrev = List<MoraPendientePreviaDetalle>.from(detallePendiente);
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
      'moraDesglose': dets
          .map(
            (d) => <String, dynamic>{
              'numeroCuota': d.numeroCuota,
              'mesLabel': d.mesLabel,
              'monto': d.interesBruto,
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
              'moraDebida': d.moraDebida,
              'moraCobrada': d.moraCobrada,
              'fechaPagoCuota': d.fechaPagoCuota?.toIso8601String(),
              'subtexto': d.subtextoDetalle,
            },
          )
          .toList(),
    };
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
        montoAtribuido: (m['monto'] as num?)?.toDouble() ?? 0,
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

    if (desg.isNotEmpty) {
      for (final d in desg) {
        final n = (d['numeroCuota'] as num?)?.toInt() ?? 0;
        final mes = (d['mesLabel'] as String?)?.trim() ?? '';
        final monto = double.parse(
          ((d['monto'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
        );
        if (monto <= 0.01) continue;
        final dias = d['diasMora'] as int?;
        out.add({
          'concepto': calendarioCuota(numeroCuota: n, mesLabel: mes),
          'monto': monto,
          'esMora': true,
          // Para anidar la mora bajo su cuota en el PDF (no altera [concepto],
          // que es la clave que reconocen los detectores de pago_interes_mora).
          if (n > 0) 'numeroCuota': n,
          if (dias != null && dias > 0) 'diasMora': dias,
          if (dias != null && dias > 0) 'subtexto': subtextoCalendario(dias),
        });
      }
    }

    final dets = detallePendiente ?? const <MoraPendientePreviaDetalle>[];
    if (pendiente > 0.01) {
      if (dets.isNotEmpty) {
        var sumDet = 0.0;
        for (final d in dets) {
          final m = double.parse(d.montoAtribuido.toStringAsFixed(2));
          if (m <= 0.01) continue;
          sumDet += m;
          out.add({
            'concepto': 'Mora pendiente cuota ${d.numeroCuota}',
            'monto': m,
            'esMora': true,
            // Cuota ya pagada en un cobro anterior: no se anida bajo ninguna
            // línea de este cobro, va al bloque de arrastre.
            'cuotaPrevia': d.numeroCuota,
            if (d.mesLabel.isNotEmpty) 'mesCuotaPrevia': d.mesLabel,
            if (d.diasMora > 0) 'diasMora': d.diasMora,
            'subtexto': d.subtextoDetalle,
          });
        }
        // Ajuste si la suma de detalle ≠ pendiente (centavos / atribución).
        final delta = double.parse((pendiente - sumDet).toStringAsFixed(2));
        if (delta.abs() > 0.01 && out.isNotEmpty) {
          // Si falta monto sin detalle, línea genérica residual.
          if (delta > 0.01) {
            out.add({
              'concepto': conceptoPendientePreviasGenerico,
              'monto': delta,
              'esMora': true,
              'subtexto': 'No cobrada en cobros anteriores',
            });
          }
        }
      } else {
        out.add({
          'concepto': conceptoPendientePreviasGenerico,
          'monto': pendiente,
          'esMora': true,
          'subtexto': 'No cobrada en cobros anteriores',
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
