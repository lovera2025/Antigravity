
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  // Encontrar el directorio de documentos del usuario
  final home = Platform.environment['USERPROFILE'] ?? '';
  final docsDir = p.join(home, 'Documents');
  final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
  
  print('Buscando base de datos en: $dbPath');

  if (!File(dbPath).existsSync()) {
    print('Error: El archivo de base de datos no existe en $dbPath');
    return;
  }

  final db = await databaseFactory.openDatabase(dbPath);
  
  print('--- COLA DE SINCRONIZACIÓN PENDIENTE ---');
  final pending = await db.query('_sync_queue');
  print('Total pendientes en cola: ${pending.length}');
  
  for (var row in pending) {
    print('ID: ${row['id']}, Tabla: ${row['tabla']}, Op: ${row['operacion']}, Registro: ${row['registro_id']}, Intentos: ${row['intentos']}');
    print('Payload: ${row['payload']}');
    print('Error: ${row['ultimo_error']}');
    
    // Si es un servicio, busquemos su evento_id
    if (row['tabla'] == 'servicios') {
      final payload = jsonDecode(row['payload'] as String);
      final evId = payload['evento_id'];
      if (evId != null) {
        final ev = await db.query('eventos', where: 'id = ?', whereArgs: [evId]);
        if (ev.isEmpty) {
          print('!!! ADVERTENCIA: El evento padre $evId NO EXISTE en la tabla local eventos !!!');
        } else {
          print('Evento padre $evId encontrado localmente.');
          // Verificamos si el evento está en la cola también
          final evInQueue = await db.query('_sync_queue', where: 'tabla = ? AND registro_id = ?', whereArgs: ['eventos', evId]);
          if (evInQueue.isEmpty) {
            print('!!! ADVERTENCIA: El evento padre $evId NO ESTÁ en la cola de sincronización !!!');
            
            // Intentamos ver si el evento ya está en la tabla eventos (confirmado localmente pero no sincronizado?)
            print('El evento $evId existe localmente pero NO está en la cola de sync.');
          } else {
             print('Evento padre $evId está en la cola (ID: ${evInQueue.first['id']}).');
          }
        }
      }
    }
    print('-----------------------------------------');
  }
  
  await db.close();
}
