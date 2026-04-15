
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  // Ruta de la DB en Windows
  final home = Platform.environment['USERPROFILE'];
  final dbPath = p.join(home!, 'OneDrive', 'Documentos', 'JuniorEventos', 'data.db');
  
  print('🔍 Inspeccionando base de datos en: $dbPath');
  
  if (!File(dbPath).existsSync()) {
    print('❌ No se encontró la base de datos.');
    return;
  }

  final db = await databaseFactory.openDatabase(dbPath);
  
  print('\n--- [COLA DE SINCRONIZACIÓN] ---');
  final queue = await db.query('_sync_queue');
  
  if (queue.isEmpty) {
    print('✅ La cola está vacía. No debería haber nubecitas.');
  } else {
    print('⚠️ Hay ${queue.length} cambios pendientes:');
    for (var row in queue) {
      print(' ID: ${row['id']} | Tabla: ${row['tabla']} | Operación: ${row['operacion']}');
      print(' Registro ID: ${row['registro_id']}');
      print(' Intentos: ${row['intentos']}');
      print(' Último Error: ${row['ultimo_error']}');
      print(' ---');
    }
  }

  print('\n--- [CONTEO POR TABLA] ---');
  final counts = await db.rawQuery('SELECT tabla, COUNT(*) as c FROM _sync_queue GROUP BY tabla');
  for (var c in counts) {
    print(' ${c['tabla']}: ${c['c']}');
  }

  await db.close();
}
