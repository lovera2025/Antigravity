import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final docsDir = 'C:\\Users\\melga\\OneDrive\\Documentos\\JuniorEventos';
  final dbPath = p.join(docsDir, 'data.db');

  print('🧹 Iniciando Exorcismo de Servicios Fantasma...');
  final db = await openDatabase(dbPath);
  
  // Lista blanca de servicios globales legítimos (según catálogo oficial)
  final listaBlanca = [
    'SONIDO', 'RECEPCION', 'PANTALLAS LED', 'MONITOREO', 
    'ILUMINACIÓN', 'FOTOGRAFÍA', 'ESTRUCTURAS', 'ESPEJO MÁGICO', 
    'ESCENARIO', 'EFECTOS ESPECIALES', 'DECORACIÓN', 'AMBIENTACIÓN',
    'recepcion' // Caso especial visto en logs
  ].map((e) => e.toUpperCase()).toList();

  // Buscar servicios globales (evento_id IS NULL)
  final serviciosGlobales = await db.query('servicios', where: 'evento_id IS NULL');
  
  int eliminados = 0;
  for (final s in serviciosGlobales) {
    final nombre = (s['nombre'] as String).toUpperCase();
    if (!listaBlanca.contains(nombre)) {
      print('🗑️ Eliminando servicio fantasma: "$nombre" (ID: ${s['id']})');
      await db.delete('servicios', where: 'id = ?', whereArgs: [s['id']]);
      eliminados++;
    }
  }

  print('\n✅ Operación completada.');
  print('📊 Servicios fantasma eliminados: $eliminados');
  
  await db.close();
}
