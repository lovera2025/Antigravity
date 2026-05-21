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
    LIMIT 15
  ''');
  
  print('=== EJEMPLO DE ALUMNOS (EXCEPTO BUENA VISTA) ===');
  for (var a in alumnos) {
    print('Alumno: ${a['nombre_alumno']} | Inst: ${a['institucion']}');
    print('  Created At: ${a['created_at']}');
    print('  Cuotas Totales: ${a['total_cuotas']} | Pagadas: ${a['cuotas_pagadas']}');
    print('  Monto Pactado: ${a['monto_total_pactado']} | Saldo: ${a['saldo_deudor']}');
    print('  Mesa Extra: ${a['mesa_extra_precio']} | Sillas Extra: ${a['sillas_extra_precio_total']}');
    print('  Mora Tracked: ${a['mora_pendiente_tracked']}');
    print('---');
  }
  
  await db.close();
}
