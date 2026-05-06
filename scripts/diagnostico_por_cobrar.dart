
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../lib/models/contrato_alumno.dart';
import '../lib/core/utils/ar_time.dart';

void main() {
  test('Diagnostico POR COBRAR HUD', () async {
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;
    final docsDir = 'C:/Users/lover/Documents';
    final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
    final db = await databaseFactory.openDatabase(dbPath);

    final now = DateTime.now();
    final hoySolo = DateTime(now.year, now.month, now.day);

    print('========================================');
    print('  DIAGNÓSTICO "POR COBRAR" HUD');
    print('  Fecha: $now');
    print('========================================\n');

    // ─────────────────────────────────────────────────────────
    // 1. PARTICULARES
    // ─────────────────────────────────────────────────────────
    final particularesRes = await db.rawQuery('''
      SELECT 
        e.id, e.tipo, e.fecha_evento, e.bonificacion_global_pct, e.estado,
        c.nombre_completo,
        (SELECT SUM(precio_final_acordado * cantidad) FROM eventos_servicios WHERE evento_id = e.id) as presupuesto_raw,
        (SELECT SUM(pfa * cant) FROM (
           SELECT DISTINCT servicio_id, precio_final_acordado as pfa, cantidad as cant, grupo, combo_orden
           FROM eventos_servicios WHERE evento_id = e.id
        )) as presupuesto_base,
        (SELECT COUNT(*) FROM eventos_servicios WHERE evento_id = e.id) as filas_raw,
        (SELECT COUNT(*) FROM (
           SELECT DISTINCT servicio_id, precio_final_acordado, cantidad, grupo, combo_orden
           FROM eventos_servicios WHERE evento_id = e.id
        )) as filas_dedup,
        (SELECT SUM(monto) FROM transacciones WHERE evento_id = e.id) as recaudado
      FROM eventos e
      JOIN clientes c ON e.cliente_id = c.id
      WHERE e.modalidad = 'particular' AND e.estado IN ('Confirmado', 'Planificacion')
      ORDER BY e.fecha_evento
    ''');

    double morosidadPart = 0.0;
    double aVencerPart = 0.0;
    double pendienteSinFecha = 0.0;
    double pendienteLejano = 0.0;
    double totalPendientePart = 0.0;

    print('--- EVENTOS PARTICULARES (${particularesRes.length} activos) ---\n');

    for (var ev in particularesRes) {
      double presupuesto = (ev['presupuesto_base'] as num?)?.toDouble() ?? 0;
      final double bonificacion = (ev['bonificacion_global_pct'] as num?)?.toDouble() ?? 0;
      if (bonificacion > 0) {
        presupuesto = presupuesto * (1 - (bonificacion / 100));
      }
      final double recaudado = (ev['recaudado'] as num?)?.toDouble() ?? 0;
      final double saldoReal = (presupuesto - recaudado).clamp(0.0, double.infinity);

      final String nombre = ev['nombre_completo']?.toString() ?? 'Sin Nombre';
      final String estado = ev['estado']?.toString() ?? '';
      final String? fechaStr = ev['fecha_evento']?.toString();
      DateTime? fechaEvento = fechaStr != null ? DateTime.tryParse(fechaStr) : null;
      final String fechaDisplay = fechaStr != null ? fechaStr.substring(0, 10) : 'SIN FECHA';

      String categoria = '';

      if (saldoReal > 0.01) {
        totalPendientePart += saldoReal;
        if (fechaEvento != null && fechaEvento.isBefore(now)) {
          morosidadPart += saldoReal;
          categoria = 'VENCIDO (mora)';
        } else if (fechaEvento != null && fechaEvento.difference(now).inDays <= 30) {
          aVencerPart += saldoReal;
          categoria = 'A VENCER (<=30d) <- SUMA AL HUD';
        } else if (fechaEvento != null) {
          pendienteLejano += saldoReal;
          final dias = fechaEvento.difference(now).inDays;
          categoria = 'FUTURO (${dias}d) <- NO SUMA';
        } else {
          pendienteSinFecha += saldoReal;
          categoria = 'SIN FECHA <- NO SUMA';
        }
      } else {
        categoria = 'PAGADO';
      }

      final double presupuestoRaw = (ev['presupuesto_raw'] as num?)?.toDouble() ?? 0;
      final int filasRaw = (ev['filas_raw'] as num?)?.toInt() ?? 0;
      final int filasDedup = (ev['filas_dedup'] as num?)?.toInt() ?? 0;
      final bool tieneDups = filasRaw != filasDedup;

      print('  $nombre | $estado | $fechaDisplay');
      print('    Presup DEDUP: \$${presupuesto.toStringAsFixed(0)} | Pagado: \$${recaudado.toStringAsFixed(0)} | Saldo: \$${saldoReal.toStringAsFixed(0)} | $categoria');
      if (tieneDups) print('    *** DUPLICADOS: $filasRaw filas raw vs $filasDedup dedup (raw=\$${presupuestoRaw.toStringAsFixed(0)}) ***');
      if (bonificacion > 0) print('    (Bonificación: ${bonificacion}%)');
      print('');
    }

    print('--- RESUMEN PARTICULARES ---');
    print('  Morosidad (eventos pasados):      \$${morosidadPart.toStringAsFixed(2)}');
    print('  A Vencer (<=30 dias):              \$${aVencerPart.toStringAsFixed(2)}');
    print('  Pendiente lejano (>30d, NO suma):  \$${pendienteLejano.toStringAsFixed(2)}');
    print('  Pendiente sin fecha (NO suma):     \$${pendienteSinFecha.toStringAsFixed(2)}');
    print('  TOTAL pendiente particulares:      \$${totalPendientePart.toStringAsFixed(2)}');
    print('  -> Suma al HUD "POR COBRAR":      \$${(morosidadPart + aVencerPart).toStringAsFixed(2)}');

    // ─────────────────────────────────────────────────────────
    // 2. MASIVOS
    // ─────────────────────────────────────────────────────────
    final contratosRes = await db.rawQuery('''
      SELECT ca.*, ev.tipo as evento_tipo, c.nombre_completo as cliente_nombre, ev.id as ev_id
      FROM contratos_alumnos ca
      JOIN eventos ev ON ca.evento_id = ev.id
      JOIN clientes c ON ev.cliente_id = c.id
      WHERE ev.estado IN ('Confirmado', 'Planificacion')
      AND ca.nombre_alumno NOT LIKE '[BAJA]%%'
    ''');

    double morosidadMasivos = 0.0;
    double aVencerMasivos = 0.0;
    int alumnosConMora = 0;
    int alumnosAVencer = 0;
    double totalSaldoMasivos = 0.0;

    final Map<String, Map<String, dynamic>> porEvento = {};

    for (var row in contratosRes) {
      final double saldoTotal = (row['saldo_deudor'] as num?)?.toDouble() ?? 0;
      if (saldoTotal < 0.01) continue;

      totalSaldoMasivos += saldoTotal;

      final String eventoId = row['evento_id'].toString();
      final String eventoNombre = row['cliente_nombre']?.toString() ?? 'Institucion';

      porEvento.putIfAbsent(eventoId, () => ({
        'nombre': eventoNombre,
        'tipo': row['evento_tipo']?.toString() ?? '',
        'mora': 0.0,
        'aVencer': 0.0,
        'saldoTotal': 0.0,
        'alumnosMora': 0,
        'alumnosAVencer': 0,
        'totalAlumnos': 0,
      }));
      porEvento[eventoId]!['totalAlumnos'] = (porEvento[eventoId]!['totalAlumnos'] as int) + 1;
      porEvento[eventoId]!['saldoTotal'] = (porEvento[eventoId]!['saldoTotal'] as double) + saldoTotal;

      final c = ContratoAlumno.fromJson(Map<String, dynamic>.from(row));
      final inscrip = c.createdAt ?? now;
      final inscAr = ArTime.toAr(inscrip);
      final tCuotas = c.totalCuotas > 0 ? c.totalCuotas : 1;

      final totalBase = (c.montoTotalPactado - c.mesaExtraPrecio - c.sillasExtraPrecioTotal).clamp(0.0, double.infinity);
      final cuotaBase = tCuotas > 0 ? totalBase / tCuotas : 0.0;
      final cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));

      int cuotasVencidasCount = 0;
      bool proximaAVencer = false;

      for (int k = c.cuotasPagadas + 1; k <= tCuotas; k++) {
        var m = inscAr.month + k;
        var y = inscAr.year;
        while (m > 12) { m -= 12; y++; }
        final vK = DateTime(y, m, DateTime(y, m + 1, 0).day);
        final vKSolo = DateTime(vK.year, vK.month, vK.day);

        if (hoySolo.isAfter(vKSolo)) {
          cuotasVencidasCount++;
        } else if (vKSolo.difference(hoySolo).inDays <= 30) {
          proximaAVencer = true;
          break;
        } else {
          break;
        }
      }

      if (cuotasVencidasCount > 0) {
        final double montoMora = (cuotasVencidasCount * cuotaBaseR).clamp(0.0, saldoTotal);
        morosidadMasivos += montoMora;
        alumnosConMora++;
        porEvento[eventoId]!['mora'] = (porEvento[eventoId]!['mora'] as double) + montoMora;
        porEvento[eventoId]!['alumnosMora'] = (porEvento[eventoId]!['alumnosMora'] as int) + 1;
      }

      if (proximaAVencer) {
        final double restanteTrasMora = (saldoTotal - (cuotasVencidasCount * cuotaBaseR)).clamp(0.0, saldoTotal);
        final double cuotaAVencer = cuotaBaseR.clamp(0.0, restanteTrasMora);
        aVencerMasivos += cuotaAVencer;
        alumnosAVencer++;
        porEvento[eventoId]!['aVencer'] = (porEvento[eventoId]!['aVencer'] as double) + cuotaAVencer;
        porEvento[eventoId]!['alumnosAVencer'] = (porEvento[eventoId]!['alumnosAVencer'] as int) + 1;
      }
    }

    print('\n\n--- EVENTOS MASIVOS (${porEvento.length} eventos, ${contratosRes.length} contratos) ---\n');
    for (var entry in porEvento.entries) {
      final d = entry.value;
      print('  ${d["nombre"]} (${d["tipo"]})');
      print('    Alumnos con deuda: ${d["totalAlumnos"]}');
      print('    Saldo total deudor: \$${(d["saldoTotal"] as double).toStringAsFixed(2)}');
      print('    Mora vencida: \$${(d["mora"] as double).toStringAsFixed(2)} (${d["alumnosMora"]} alumnos)');
      print('    A vencer (30d): \$${(d["aVencer"] as double).toStringAsFixed(2)} (${d["alumnosAVencer"]} alumnos)');
      print('');
    }

    print('--- RESUMEN MASIVOS ---');
    print('  Morosidad total:             \$${morosidadMasivos.toStringAsFixed(2)} ($alumnosConMora alumnos)');
    print('  A Vencer (prox cuota 30d):   \$${aVencerMasivos.toStringAsFixed(2)} ($alumnosAVencer alumnos)');
    print('  Saldo total deudor real:     \$${totalSaldoMasivos.toStringAsFixed(2)}');
    print('  -> Suma al HUD "POR COBRAR": \$${(morosidadMasivos + aVencerMasivos).toStringAsFixed(2)}');

    // ─────────────────────────────────────────────────────────
    // 3. TOTALES
    // ─────────────────────────────────────────────────────────
    final double hudTotal = morosidadMasivos + aVencerMasivos + morosidadPart + aVencerPart;
    final double hudMorosidad = morosidadMasivos + morosidadPart;
    final double hudAVencer = aVencerMasivos + aVencerPart;

    print('\n\n========================================');
    print('  RESULTADO FINAL HUD "POR COBRAR"');
    print('========================================');
    print('  VENCIDO (morosidad):   \$${hudMorosidad.toStringAsFixed(2)}');
    print('  A VENCER:              \$${hudAVencer.toStringAsFixed(2)}');
    print('  TOTAL POR COBRAR:     \$${hudTotal.toStringAsFixed(2)}');
    print('========================================');
    print('');
    print('  (lo que NO se cuenta en el HUD:)');
    print('  Particulares >30d:      \$${pendienteLejano.toStringAsFixed(2)}');
    print('  Particulares sin fecha: \$${pendienteSinFecha.toStringAsFixed(2)}');
    print('  Saldo total masivos:    \$${totalSaldoMasivos.toStringAsFixed(2)} (HUD solo cuenta cuota proxima)');

    await db.close();
  });
}
