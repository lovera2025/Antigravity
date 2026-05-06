import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  // Use the user's documents directory
  final String path = 'C:\\Users\\lover\\Documents\\JuniorEventos\\data.db';
  print('Opening db at \$path');
  
  if (File(path).existsSync()) {
    var db = await databaseFactory.openDatabase(path);
    print('DB Opened.');
    var count = await db.delete('egresos', where: "proveedor LIKE '%maximiliano1523%'");
    print('Deleted \$count test egresos.');
    
    // Also clear sync_queue just in case
    var count2 = await db.delete('_sync_queue', where: "tabla = 'egresos' AND payload LIKE '%maximiliano1523%'");
    print('Deleted \$count2 test sync items.');
    await db.close();
  } else {
    print('DB not found.');
  }
}
