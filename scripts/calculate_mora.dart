import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final docsDir = 'C:/Users/lover/Documents';
  final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
  
  if (!File(dbPath).existsSync()) {
    print('DB no encontrada en $dbPath');
    return;
  }
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  final alumnos = await db.rawQuery('''
    SELECT id, nombre_alumno, institucion, created_at, total_cuotas, cuotas_pagadas, monto_total_pactado, saldo_deudor, mesa_extra_precio, sillas_extra_precio_total, mora_pendiente_tracked 
    FROM contratos_alumnos 
    WHERE institucion IS NOT NULL AND institucion != 'COLEGIO BUENA VISTA'
  ''');
  
  final hoy = DateTime.now();
  final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
  
  print('=== CÁLCULO TEÓRICO DE MORA (1% POR DÍA DESDE REGISTRO) ===');
  double totalMoraCalculada = 0;
  int countConMora = 0;
  
  for (var a in alumnos) {
    final double saldo = (a['saldo_deudor'] as num?)?.toDouble() ?? 0;
    if (saldo <= 0.01) continue;
    
    final String? createdStr = a['created_at']?.toString();
    if (createdStr == null) continue;
    
    final DateTime? createdAt = DateTime.tryParse(createdStr);
    if (createdAt == null) continue;
    
    final createdSolo = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final int dias = hoySolo.difference(createdSolo).inDays;
    if (dias <= 0) continue;
    
    final int tCuotas = (a['total_cuotas'] as num?)?.toInt() ?? 9;
    final int totalCuotas = tCuotas > 0 ? tCuotas : 9;
    
    final double pactado = (a['monto_total_pactado'] as num?)?.toDouble() ?? 0;
    final double mesa = (a['mesa_extra_precio'] as num?)?.toDouble() ?? 0;
    final double sillas = (a['sillas_extra_precio_total'] as num?)?.toDouble() ?? 0;
    
    final double totalBase = (pactado - mesa - sillas).clamp(0.0, double.infinity);
    final double cuotaBase = totalCuotas > 0 ? totalBase / totalCuotas : 0;
    final double cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));
    
    final double moraCalculada = cuotaBaseR * 0.01 * dias;
    final double moraCalculadaR = double.parse(moraCalculada.toStringAsFixed(2));
    
    totalMoraCalculada += moraCalculadaR;
    countConMora++;
    
    print('Alumno: ${a['nombre_alumno']} | Inst: ${a['institucion']}');
    print('  Reg: ${createdSolo.toIso8601String().substring(0,10)} | Días: $dias');
    print('  Cuota Base: \$$cuotaBaseR | Mora 1%/día: \$$moraCalculadaR');
    print('  Mora Tracked Actual: \$${a['mora_pendiente_tracked']}');
    print('---');
  }
  
  print('Total de contratos con mora: $countConMora');
  print('Total interés por mora calculado: \$${totalMoraCalculada.toStringAsFixed(2)}');
  
  await db.close();
}
