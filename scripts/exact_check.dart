
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../lib/models/contrato_alumno.dart';
import '../lib/core/utils/ar_time.dart';

void main() {
  test('Exact Calculation check', () async {
    sqfliteFfiInit();
    final databaseFactory = databaseFactoryFfi;
    final docsDir = 'C:/Users/lover/Documents';
    final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
    final db = await databaseFactory.openDatabase(dbPath);
    
    final now = DateTime.now();

    // 1. MASIVOS
    final contratosRes = await db.rawQuery('''
      SELECT ca.*, ev.tipo as evento_tipo, c.nombre_completo as cliente_nombre
      FROM contratos_alumnos ca
      JOIN eventos ev ON ca.evento_id = ev.id
      JOIN clientes c ON ev.cliente_id = c.id
      WHERE ev.estado IN ('Confirmado', 'Planificacion')
      AND ca.nombre_alumno NOT LIKE '[BAJA]%'
    ''');

    double morosidadReal = 0.0;
    double saldoAVencerProximamente = 0.0;

    for (var row in contratosRes) {
      final double saldoTotal = (row['saldo_deudor'] as num?)?.toDouble() ?? 0;
      if (saldoTotal < 0.01) continue;

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
        final hoySolo = DateTime(now.year, now.month, now.day);

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
        morosidadReal += montoMora;
      }

      if (proximaAVencer) {
        final double restanteTrasMora = (saldoTotal - (cuotasVencidasCount * cuotaBaseR)).clamp(0.0, saldoTotal);
        saldoAVencerProximamente += cuotaBaseR.clamp(0.0, restanteTrasMora);
      }
    }

    print('--- MASIVOS ---');
    print('Morosidad Masivos: \$${morosidadReal}');
    print('A Vencer Masivos: \$${saldoAVencerProximamente}');

    // 2. PARTICULARES
    final particularesRes = await db.rawQuery('''
      SELECT 
        e.id, e.tipo, e.fecha_evento, e.bonificacion_global_pct, c.nombre_completo,
        (SELECT SUM(precio_final_acordado) FROM eventos_servicios WHERE evento_id = e.id) as presupuesto,
        (SELECT SUM(monto) FROM transacciones WHERE evento_id = e.id) as recaudado
      FROM eventos e
      JOIN clientes c ON e.cliente_id = c.id
      WHERE e.modalidad = 'particular' AND e.estado IN ('Confirmado', 'Planificacion')
    ''');

    double morosidadPart = 0.0;
    double aVencerPart = 0.0;

    print('--- DETALLE EVENTOS PARTICULARES ---');
    for (var ev in particularesRes) {
      double presupuesto = (ev['presupuesto'] as num?)?.toDouble() ?? 0;
      final double bonificacion = (ev['bonificacion_global_pct'] as num?)?.toDouble() ?? 0;
      if (bonificacion > 0) {
        presupuesto = presupuesto * (1 - (bonificacion / 100));
      }
      final double recaudado = (ev['recaudado'] as num?)?.toDouble() ?? 0;
      final double saldoReal = (presupuesto - recaudado).clamp(0.0, double.infinity); // use double.infinity instead of presupuesto just in case
      
      final String nombre = ev['nombre_completo']?.toString() ?? 'Sin Nombre';
      final String? fechaStr = ev['fecha_evento']?.toString();
      DateTime? fechaEvento = fechaStr != null ? DateTime.tryParse(fechaStr) : null;

      if (saldoReal > 0.01) {
        if (fechaEvento != null && fechaEvento.isBefore(now)) {
          morosidadPart += saldoReal;
          print('VENCIDO: \$${saldoReal} - \$nombre (Fecha: \$fechaStr)');
        } else if (fechaEvento != null && fechaEvento.difference(now).inDays <= 30) {
          aVencerPart += saldoReal;
          print('A VENCER (<=30d): \$${saldoReal} - \$nombre (Fecha: \$fechaStr)');
        } else {
          print('FUTURO (>30d): \$${saldoReal} - \$nombre (Fecha: \$fechaStr)');
        }
      } else {
        print('PAGADO: \$0 - \$nombre (Fecha: \$fechaStr)');
      }
    }

    print('--- PARTICULARES ---');
    print('Morosidad Particulares: \$${morosidadPart}');
    print('A Vencer Particulares: \$${aVencerPart}');

    double totalGeneral = morosidadReal + saldoAVencerProximamente + morosidadPart + aVencerPart;
    print('--- TOTAL GENERAL HUD ---');
    print('TOTAL: \$${totalGeneral}');

    await db.close();
  });
}
