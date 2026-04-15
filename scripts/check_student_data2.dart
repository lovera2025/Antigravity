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
    print('DB no encontrada en $dbPath');
    return;
  }
  
  var db = await databaseFactory.openDatabase(dbPath);
  
  final res = await db.rawQuery("SELECT id, nombre_alumno, mesa_extra_precio, mesa_extra_pagado FROM contratos_alumnos WHERE nombre_alumno LIKE '%INSAURRALDE%'");
  for (var r in res) {
    print('Alumno: ${r['nombre_alumno']}');
    print('Mesa Precio: ${r['mesa_extra_precio']}');
    print('Mesa Pagado: ${r['mesa_extra_pagado']}');
    print('---');
  }

  final res2 = await db.rawQuery("PRAGMA table_info(contratos_alumnos);");
  print('Columnas en contratos_alumnos:');
  for (var r in res2) {
    print(r['name']);
  }
  
  await db.close();
}
