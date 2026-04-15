// ignore_for_file: avoid_print
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  final docsDir = 'C:\\Users\\melga\\OneDrive\\Documentos';
  final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
  
  if (!File(dbPath).existsSync()) {
    print('DB not found at $dbPath');
    return;
  }
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  print('--- Analyzing Student: INSAURRALDE, ANGEL IVAN ---');
  final students = await db.query('contratos_alumnos', 
    where: 'nombre_alumno LIKE ?', 
    whereArgs: ['%INSAURRALDE%']);
  
  if (students.isEmpty) {
    print('Student not found');
  } else {
    for (var s in students) {
      print('ID: ${s['id']}');
      print('Nombre: ${s['nombre_alumno']}');
      print('Monto Pactado: ${s['monto_total_pactado']}');
      print('Saldo Deudor: ${s['saldo_deudor']}');
      print('Mesa Extra Precio: ${s['mesa_extra_precio']}');
      print('Mesa Extra Pagado: ${s['mesa_extra_pagado']}');
      print('Mesa Extra Cuotas Pagadas: ${s['mesa_extra_cuotas_pagadas']}');
      
      print('\n--- Payments for this student ---');
      final payments = await db.query('pagos_contrato_alumno', 
        where: 'contrato_alumno_id = ?', 
        whereArgs: [s['id']]);
      for (var p in payments) {
        print('Concepto: ${p['concepto']} | Monto: ${p['monto']} | Fecha: ${p['fecha_pago']}');
      }
      print('-------------------------------------------');
    }
  }
  
  await db.close();
}
