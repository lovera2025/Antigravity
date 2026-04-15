import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final docsDir = 'C:\\Users\\melga\\OneDrive\\Documentos\\JuniorEventos';
  final dbPath = p.join(docsDir, 'data.db');

  final db = await openDatabase(dbPath);
  
  final res = await db.query('servicios', where: "nombre LIKE '%vajilla%'");
  print('Resultados para vajilla: ${res.length}');
  for (final s in res) {
    print(s);
  }

  await db.close();
}
