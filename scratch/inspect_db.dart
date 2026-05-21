import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  final docsDir = 'C:\\Users\\lover\\Documents';
  final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
  
  print('Opening SQLite database at $dbPath...');
  final db = await databaseFactory.openDatabase(dbPath);
  
  print('\n--- CONTRACT INFO ---');
  final contracts = await db.query(
    'contratos_alumnos',
    where: 'nombre_alumno LIKE ?',
    whereArgs: ['%MORATO%'],
  );
  
  for (final c in contracts) {
    print('ID: ${c['id']}');
    print('Nombre: ${c['nombre_alumno']}');
    print('Colegio: ${c['institucion']}');
    print('Created At: ${c['created_at']}');
    print('Total Cuotas: ${c['total_cuotas']}');
    print('Cuotas Pagadas: ${c['cuotas_pagadas']}');
    print('Saldo Deudor: ${c['saldo_deudor']}');
    print('Mora Tracked: ${c['mora_pendiente_tracked']}');
    print('Mesa Extra: ${c['mesa_extra_precio']}');
    print('Sillas Extra: ${c['sillas_extra_precio_total']}');
    print('Monto Pactado: ${c['monto_total_pactado']}');
  }
  
  await db.close();
}
