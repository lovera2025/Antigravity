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
    SELECT id, nombre_alumno, institucion, created_at, total_cuotas, cuotas_pagadas, monto_total_pactado, saldo_deudor, mora_pendiente_tracked 
    FROM contratos_alumnos 
    WHERE institucion IS NOT NULL AND institucion != 'COLEGIO BUENA VISTA' AND saldo_deudor > 0.01
  ''');
  
  print('Total de alumnos con saldo deudor (excepto Buena Vista): ${alumnos.length}');
  
  int pagadasCero = 0;
  int pagadasMayorCero = 0;
  
  Map<String, int> porInstitucion = {};
  
  for (var a in alumnos) {
    final String inst = a['institucion']?.toString() ?? 'Sin institucion';
    porInstitucion[inst] = (porInstitucion[inst] ?? 0) + 1;
    
    final int pagadas = (a['cuotas_pagadas'] as num?)?.toInt() ?? 0;
    if (pagadas == 0) {
      pagadasCero++;
    } else {
      pagadasMayorCero++;
    }
  }
  
  print('\nBreakdown de pagos:');
  print(' - Con 0 cuotas pagadas (nunca pagaron): $pagadasCero');
  print(' - Con >0 cuotas pagadas: $pagadasMayorCero');
  
  print('\nAlumnos por institución con saldo deudor:');
  porInstitucion.forEach((inst, count) {
    print(' - $inst: $count');
  });
  
  await db.close();
}
