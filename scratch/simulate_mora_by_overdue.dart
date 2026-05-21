import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

DateTime _ultimoDiaMesK(DateTime inscripcion, int k) {
  var m = inscripcion.month + k;
  var y = inscripcion.year;
  while (m > 12) {
    m -= 12;
    y++;
  }
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, lastDay);
}

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
    WHERE institucion IS NOT NULL AND institucion != 'COLEGIO BUENA VISTA' AND saldo_deudor > 0.01
  ''');
  
  final hoy = DateTime.now();
  final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
  
  print('=== SIMULACIÓN: MORA DESDE REGISTRO SOLO PARA CUOTAS VENCIDAS ===');
  double totalMoraCalculada = 0;
  int countConMora = 0;
  int countSinMora = 0;
  
  for (var a in alumnos) {
    final String? createdStr = a['created_at']?.toString();
    if (createdStr == null) continue;
    
    final DateTime? createdAt = DateTime.tryParse(createdStr);
    if (createdAt == null) continue;
    
    final createdSolo = DateTime(createdAt.year, createdAt.month, createdAt.day);
    
    // Calcular si tiene cuota vencida
    final int tCuotas = (a['total_cuotas'] as num?)?.toInt() ?? 9;
    final int totalCuotas = tCuotas > 0 ? tCuotas : 9;
    final int cPag = (a['cuotas_pagadas'] as num?)?.toInt() ?? 0;
    
    if (cPag >= totalCuotas) {
      countSinMora++;
      continue;
    }
    
    final proxN = cPag + 1;
    final vProx = _ultimoDiaMesK(createdSolo, proxN);
    final vSolo = DateTime(vProx.year, vProx.month, vProx.day);
    
    // ¿Está vencida?
    if (!hoySolo.isAfter(vSolo)) {
      countSinMora++;
      continue; // No está vencida aún
    }
    
    // Si está vencida, la mora corre desde el día de alta ("reg")
    final int diasDesdeReg = hoySolo.difference(createdSolo).inDays;
    if (diasDesdeReg <= 0) {
      countSinMora++;
      continue;
    }
    
    final double pactado = (a['monto_total_pactado'] as num?)?.toDouble() ?? 0;
    final double mesa = (a['mesa_extra_precio'] as num?)?.toDouble() ?? 0;
    final double sillas = (a['sillas_extra_precio_total'] as num?)?.toDouble() ?? 0;
    
    final double totalBase = (pactado - mesa - sillas).clamp(0.0, double.infinity);
    final double cuotaBase = totalCuotas > 0 ? totalBase / totalCuotas : 0;
    final double cuotaBaseR = double.parse(cuotaBase.toStringAsFixed(2));
    
    final double moraCalculada = cuotaBaseR * 0.01 * diasDesdeReg;
    final double moraCalculadaR = double.parse(moraCalculada.toStringAsFixed(2));
    
    totalMoraCalculada += moraCalculadaR;
    countConMora++;
    
    print('Alumno: ${a['nombre_alumno']} | Inst: ${a['institucion']}');
    print('  Reg: ${createdSolo.toIso8601String().substring(0,10)} | Vencimiento Prox Cuota: ${vSolo.toIso8601String().substring(0,10)}');
    print('  Días desde Reg: $diasDesdeReg | Cuota Base: \$$cuotaBaseR | Mora: \$$moraCalculadaR');
    print('---');
  }
  
  print('\nResumen de Simulación:');
  print(' - Contratos evaluados: ${alumnos.length}');
  print(' - Contratos con cuotas vencidas (con mora desde reg): $countConMora');
  print(' - Contratos al día o sin vencimiento (sin mora): $countSinMora');
  print(' - Total interés por mora a restaurar: \$${totalMoraCalculada.toStringAsFixed(2)}');
  
  await db.close();
}
