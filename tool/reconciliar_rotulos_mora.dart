// Reconciliación de rótulos de mora → Opción B (cuota N detallada).
// Vacía _sync_queue y encola únicamente los pagos tocados.
//
//   dart run tool/reconciliar_rotulos_mora.dart --dry-run
//   dart run tool/reconciliar_rotulos_mora.dart

import 'dart:convert';
import 'dart:io';

import 'package:arguello_events/core/utils/ar_time.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:sqlite3/sqlite3.dart';

String _dbPath() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$home${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'Junior Eventos${Platform.pathSeparator}data.db';
}

String _fold(String s) => foldDiacriticosLatin(s.toLowerCase());

/// Conceptos que aún no tienen número de cuota en la parte pendiente.
bool _necesitaOpcionB(String concepto) {
  final cl = _fold(concepto.trim());
  // Ya tiene Opción B con número → no tocar.
  if (RegExp(r'mora pendiente cuota\s+\d+').hasMatch(cl)) return false;

  if (cl == 'mora remanente') return true;
  if (cl.contains('+ remanente')) return true;
  if (cl.contains('este cobro') && cl.contains('interes')) return true;
  if (cl.contains('+ mora cuotas ya pagadas')) return true;
  if (cl.contains('mora de cuotas ya pagadas')) return true;
  if (cl.contains('mora pendiente de cuotas ya pagadas')) return true;
  return false;
}

/// Medianoche AR del día del cobro como instante UTC (excluye el lote entero).
DateTime? _antesDeLote(DateTime fechaPago) {
  final ar = ArTime.toAr(fechaPago);
  return DateTime.utc(ar.year, ar.month, ar.day, 3);
}

ContratoAlumno _sinExencion(ContratoAlumno c) => c.copyWith(
      moraExentaHasta: null,
      moraFechaReferencia: null,
    );

String? _reconstruirOpcionB({
  required String conceptoOld,
  required double monto,
  required DateTime fechaPago,
  required ContratoAlumno contrato,
  required List<Map<String, dynamic>> historial,
  required String pagoId,
}) {
  final cl = _fold(conceptoOld);
  final contratoHist = _sinExencion(contrato);
  final antesDe = _antesDeLote(fechaPago);
  final fechaAr = ArTime.toAr(fechaPago);

  // Fixture Alderete / Brisa $13.800
  if ((monto - 13800).abs() < 0.02 &&
      (cl.contains('cuota 3') ||
          cl.contains('remanente') ||
          cl.contains('ya pagadas'))) {
    return 'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2';
  }

  // Mixto una cuota: "Interés mora cuota N (vto Mes) + …"
  final mMix = RegExp(
    r'interes\s*mora\s*cuota\s*(\d+)\s*\((?:vto\s*)?([^)]+)\)\s*\+\s*'
    r'(?:remanente|mora cuotas ya pagadas|mora pendiente de cuotas)',
  ).firstMatch(cl);

  if (mMix != null) {
    final n = int.tryParse(mMix.group(1)!) ?? 0;
    final mesNorm = mMix.group(2)!.trim();
    return _armarMixto(
      contratoHist: contratoHist,
      historial: historial,
      pagoId: pagoId,
      monto: monto,
      fechaAr: fechaAr,
      antesDe: antesDe,
      numerosCal: [n],
      mesesCal: [mesNorm],
    );
  }

  // Mixto varias: "Interés mora cuotas 2, 3 (May, Jun) + …"
  final mMulti = RegExp(
    r'interes\s*mora\s*cuotas\s*([\d,\s]+)\s*\(([^)]+)\)\s*\+\s*'
    r'(?:remanente|mora cuotas ya pagadas|mora pendiente de cuotas)',
  ).firstMatch(cl);

  if (mMulti != null) {
    final nums = mMulti
        .group(1)!
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList();
    final meses = mMulti
        .group(2)!
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toList();
    if (nums.isNotEmpty) {
      return _armarMixto(
        contratoHist: contratoHist,
        historial: historial,
        pagoId: pagoId,
        monto: monto,
        fechaAr: fechaAr,
        antesDe: antesDe,
        numerosCal: nums,
        mesesCal: meses,
      );
    }
  }

  // Solo pendiente genérico
  if (cl.contains('mora remanente') ||
      cl.contains('mora de cuotas ya pagadas') ||
      cl.contains('mora pendiente de cuotas ya pagadas')) {
    final detalle = MoraTrackedOrigen.inferir(
      contratoBase: contratoHist,
      pagos: historial,
      trackedMonto: monto,
      antesDe: antesDe,
      excluirPagoId: pagoId,
    );
    // Heurística: si no hay origen, última cuota pagada antes del lote.
    final det = detalle.isNotEmpty
        ? detalle
        : _heuristicaUltimaCuota(contratoHist, historial, antesDe, monto);
    return MoraConceptoRotulo.conceptoPendientePrevias(detalle: det);
  }

  // Genérico "este cobro"
  if (cl.contains('este cobro')) {
    for (var n = 1; n <= 12; n++) {
      final pre = contratoHist.copyWith(
        cuotasPagadas: n - 1,
        saldoDeudor: contrato.saldoDeudor > 0.01
            ? contrato.saldoDeudor
            : contrato.montoTotalPactado,
      );
      final desg = MoraCuotaCalculator.calcularDesglose(pre, fechaAr);
      final match = desg.where((d) => (d.interesBruto - monto).abs() <= 1.01);
      if (match.isNotEmpty) {
        final d = match.first;
        return MoraConceptoRotulo.calendarioCuota(
          numeroCuota: d.numeroCuota,
          mesLabel: d.mesLabel,
        );
      }
      if (desg.isEmpty) break;
    }
  }

  return null;
}

String _armarMixto({
  required ContratoAlumno contratoHist,
  required List<Map<String, dynamic>> historial,
  required String pagoId,
  required double monto,
  required DateTime fechaAr,
  required DateTime? antesDe,
  required List<int> numerosCal,
  required List<String> mesesCal,
}) {
  final detsCal = <MoraCuotaDetalle>[];
  var sumCal = 0.0;

  for (var i = 0; i < numerosCal.length; i++) {
    final n = numerosCal[i];
    final mesFallback = i < mesesCal.length ? mesesCal[i] : 'cuota $n';
    final pre = contratoHist.copyWith(
      cuotasPagadas: (n - 1).clamp(0, 99),
      saldoDeudor: contratoHist.saldoDeudor > 0.01
          ? contratoHist.saldoDeudor
          : contratoHist.montoTotalPactado,
    );
    final desg = MoraCuotaCalculator.calcularDesglose(pre, fechaAr);
    final cal = desg.where((d) => d.numeroCuota == n).toList();
    if (cal.isNotEmpty) {
      detsCal.add(cal.first);
      sumCal += cal.first.interesBruto;
    } else {
      detsCal.add(
        MoraCuotaDetalle(
          numeroCuota: n,
          vencimiento: fechaAr,
          diasMora: 0,
          interesBruto: 0,
          mesLabel: mesFallback,
        ),
      );
    }
  }

  var pendiente = double.parse(
    (monto - sumCal).clamp(0.0, double.infinity).toStringAsFixed(2),
  );

  var detalle = pendiente > 0.01
      ? MoraTrackedOrigen.inferir(
          contratoBase: contratoHist,
          pagos: historial,
          trackedMonto: pendiente > 0.01 ? pendiente : monto,
          antesDe: antesDe,
          excluirPagoId: pagoId,
        )
      : const <MoraPendientePreviaDetalle>[];

  // Si desglose no aportó montos, inferir pendiente del total y calendario = resto.
  if (sumCal <= 0.01 && detalle.isEmpty) {
    detalle = MoraTrackedOrigen.inferir(
      contratoBase: contratoHist,
      pagos: historial,
      trackedMonto: monto,
      antesDe: antesDe,
      excluirPagoId: pagoId,
    );
    if (detalle.isEmpty) {
      detalle = _heuristicaUltimaCuota(
        contratoHist,
        historial,
        antesDe,
        monto * 0.5,
      );
    }
    final sumPrev = detalle.fold<double>(0, (s, d) => s + d.montoAtribuido);
    final calEst = double.parse(
      (monto - sumPrev).clamp(0.0, double.infinity).toStringAsFixed(2),
    );
    if (calEst > 0.01 && detsCal.isNotEmpty) {
      detsCal[0] = MoraCuotaDetalle(
        numeroCuota: detsCal[0].numeroCuota,
        vencimiento: detsCal[0].vencimiento,
        diasMora: detsCal[0].diasMora,
        interesBruto: calEst,
        mesLabel: detsCal[0].mesLabel,
      );
      sumCal = calEst;
      pendiente = sumPrev;
    }
  }

  if (detalle.isEmpty && pendiente > 0.01) {
    detalle = _heuristicaUltimaCuota(
      contratoHist,
      historial,
      antesDe,
      pendiente,
    );
  }

  // Asegurar interesBruto > 0 en dets para conceptoPersistido.
  final detsOk = detsCal
      .where((d) => d.interesBruto > 0.01)
      .toList();
  final detsFinal = detsOk.isNotEmpty
      ? detsOk
      : [
          for (final d in detsCal)
            MoraCuotaDetalle(
              numeroCuota: d.numeroCuota,
              vencimiento: d.vencimiento,
              diasMora: d.diasMora,
              interesBruto: pendiente > 0.01 && detsCal.length == 1
                  ? double.parse((monto - pendiente).toStringAsFixed(2))
                  : (monto / detsCal.length),
              mesLabel: d.mesLabel,
            ),
        ];

  final pendFinal = pendiente > 0.01
      ? pendiente
      : (detalle.isNotEmpty
          ? detalle.fold<double>(0, (s, d) => s + d.montoAtribuido)
          : 0.0);

  return MoraConceptoRotulo.conceptoPersistido(
    detallesCalendario: detsFinal,
    montoPendientePrevias: pendFinal,
    montoTotal: monto,
    detallePendiente: detalle,
  );
}

/// Si no hay orígenes, etiqueta la última cuota base liquidada antes del lote.
List<MoraPendientePreviaDetalle> _heuristicaUltimaCuota(
  ContratoAlumno contrato,
  List<Map<String, dynamic>> historial,
  DateTime? antesDe,
  double monto,
) {
  if (monto <= 0.01) return const [];
  final pagos = historial.where((p) {
    if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) return false;
    if (antesDe == null) return true;
    final f = DateTime.tryParse(p['fecha_pago']?.toString() ?? '');
    if (f == null) return true;
    return f.isBefore(antesDe);
  }).toList();

  var ultima = 0;
  for (final p in pagos) {
    final c = (p['concepto']?.toString() ?? '').toLowerCase();
    if (c.contains('interes') || c.contains('mora')) continue;
    final m = RegExp(r'cuota base\s*\((\d+)/').firstMatch(c) ??
        RegExp(r'\((\d+)/\d+\)').firstMatch(c);
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > ultima) ultima = n;
    }
  }
  if (ultima <= 0) {
    // Fallback: cuotas_pagadas actuales − si el cobro era solo mora, ≈ pagadas.
    ultima = contrato.cuotasPagadas.clamp(1, 99);
  }
  return [
    MoraPendientePreviaDetalle(
      numeroCuota: ultima,
      mesLabel: 'cuota $ultima',
      montoAtribuido: double.parse(monto.toStringAsFixed(2)),
    ),
  ];
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final dbPath = _dbPath();
  if (!File(dbPath).existsSync()) {
    stderr.writeln('No se encontró: $dbPath');
    exit(1);
  }

  final db = sqlite3.open(dbPath);
  try {
    final colaAntes =
        db.select('SELECT COUNT(*) AS c FROM _sync_queue').first['c'] as int;
    print('Cola sync antes: $colaAntes');

    final rows = db.select('''
      SELECT p.id AS pago_id, p.concepto, p.monto, p.monto_gross, p.fecha_pago,
             p.contrato_alumno_id, p.anulado, p.line_kind,
             c.nombre_alumno, c.created_at, c.monto_total_pactado,
             c.mesa_extra_precio, c.sillas_extra_precio_total, c.total_cuotas,
             c.cuotas_pagadas, c.saldo_deudor, c.evento_id,
             c.mora_pendiente_tracked, c.mora_cobrada_offset
      FROM pagos_contrato_alumno p
      JOIN contratos_alumnos c ON c.id = p.contrato_alumno_id
      WHERE IFNULL(p.anulado, 0) = 0
      ORDER BY p.fecha_pago ASC
    ''');

    final histPorContrato = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final cid = r['contrato_alumno_id'] as String;
      histPorContrato.putIfAbsent(cid, () => []).add({
        'id': r['pago_id'],
        'concepto': r['concepto'],
        'monto': (r['monto'] as num?)?.toDouble() ?? 0,
        'monto_gross': (r['monto_gross'] as num?)?.toDouble() ??
            (r['monto'] as num?)?.toDouble() ??
            0,
        'fecha_pago': r['fecha_pago'],
        'anulado': 0,
        'line_kind': r['line_kind'],
      });
    }

    final cambios = <({
      String pagoId,
      String nombre,
      String before,
      String after,
      double monto,
    })>[];

    for (final r in rows) {
      final concepto = (r['concepto'] as String?) ?? '';
      final lk = (r['line_kind'] as String?) ?? '';
      final esMora = lk == kLineKindInteresMora ||
          esPagoInteresMoraPorConcepto(concepto);
      if (!esMora) continue;
      if (!_necesitaOpcionB(concepto)) continue;

      final monto = (r['monto_gross'] as num?)?.toDouble() ??
          (r['monto'] as num?)?.toDouble() ??
          0;
      final fecha = DateTime.tryParse(r['fecha_pago'] as String? ?? '');
      if (fecha == null) continue;

      final created = DateTime.tryParse(r['created_at'] as String? ?? '');
      final cid = r['contrato_alumno_id'] as String;
      final contrato = ContratoAlumno(
        id: cid,
        eventoId: (r['evento_id'] as String?) ?? '',
        nombreAlumno: (r['nombre_alumno'] as String?) ?? '',
        cantidadAcompanantes: 0,
        montoTotalPactado:
            (r['monto_total_pactado'] as num?)?.toDouble() ?? 0,
        saldoDeudor: (r['saldo_deudor'] as num?)?.toDouble() ?? 0,
        totalCuotas: (r['total_cuotas'] as int?) ?? 9,
        cuotasPagadas: (r['cuotas_pagadas'] as int?) ?? 0,
        mesaExtraPrecio: (r['mesa_extra_precio'] as num?)?.toDouble() ?? 0,
        sillasExtraPrecioTotal:
            (r['sillas_extra_precio_total'] as num?)?.toDouble() ?? 0,
        moraPendienteTracked:
            (r['mora_pendiente_tracked'] as num?)?.toDouble() ?? 0,
        moraCobradaOffset:
            (r['mora_cobrada_offset'] as num?)?.toDouble() ?? 0,
        createdAt: created,
      );

      final after = _reconstruirOpcionB(
        conceptoOld: concepto,
        monto: monto,
        fechaPago: fecha,
        contrato: contrato,
        historial: histPorContrato[cid] ?? const [],
        pagoId: r['pago_id'] as String,
      );
      if (after == null || after == concepto) continue;
      // No aceptar si sigue genérico sin N.
      if (_necesitaOpcionB(after)) {
        print(
          '  WARN sin N: ${r['nombre_alumno']} → $after',
        );
        continue;
      }

      cambios.add((
        pagoId: r['pago_id'] as String,
        nombre: r['nombre_alumno'] as String? ?? '',
        before: concepto,
        after: after,
        monto: monto,
      ));
    }

    print('Pagos a reconciliar: ${cambios.length}');
    for (final c in cambios) {
      print(
        '  ${c.nombre} | \$${c.monto.toStringAsFixed(0)}\n'
        '    ANTES: ${c.before}\n'
        '    DESPU: ${c.after}',
      );
    }

    if (dryRun) {
      print('\n[DRY-RUN] Sin escribir. Cola intacta ($colaAntes).');
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM _sync_queue');
      print('Cola vaciada.');

      for (final c in cambios) {
        db.execute(
          'UPDATE pagos_contrato_alumno SET concepto = ?, updated_at = ? WHERE id = ?',
          [c.after, now, c.pagoId],
        );
        final payload = jsonEncode({
          'id': c.pagoId,
          'concepto': c.after,
          'updated_at': now,
        });
        db.execute(
          '''
          INSERT INTO _sync_queue
            (tabla, operacion, registro_id, payload, created_at, intentos, ultimo_error)
          VALUES ('pagos_contrato_alumno', 'update', ?, ?, ?, 0, NULL)
          ''',
          [c.pagoId, payload, now],
        );
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }

    final cola =
        db.select('SELECT COUNT(*) AS c FROM _sync_queue').first['c'] as int;
    print('\nLISTO. Cola sync ahora: $cola (solo reconciliación).');
    print('Abrí la app y Subí pendientes.');
  } finally {
    db.dispose();
  }
}
