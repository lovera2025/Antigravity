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
  String out = '';
  for (var r in res) {
    out += 'Alumno: ${r['nombre_alumno']}\n';
    out += 'Mesa Precio: ${r['mesa_extra_precio']}\n';
    out += 'Mesa Pagado: ${r['mesa_extra_pagado']}\n';
    out += '---\n';
  }

  File('scripts/out.txt').writeAsStringSync(out);
  print('Escrito a out.txt');
  await db.close();
}
