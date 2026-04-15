import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../lib/core/database/local_database.dart';
import 'dart:io';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  print('🔍 Verificando migración v16...');

  final dbPath = await LocalDatabase.dbPath;
  print('📂 DB Path: $dbPath');

  if (!await File(dbPath).exists()) {
    print('❌ La base de datos no existe en esta ruta.');
    return;
  }

  final db = await openDatabase(dbPath);
  
  try {
    // Verificar versión
    final version = await db.getVersion();
    print('📌 Versión actual: $version');
    if (version != 16) {
      print('❌ Error: La versión debería ser 16.');
    }

    // Verificar tabla servicios
    final serviciosColumns = await db.rawQuery('PRAGMA table_info(servicios)');
    final hasEventoId = serviciosColumns.any((c) => c['name'] == 'evento_id');
    print('✅ Columna evento_id en servicios: ${hasEventoId ? 'SÍ' : 'NO'}');

    // Verificar tabla eventos_servicios
    final esColumns = await db.rawQuery('PRAGMA table_info(eventos_servicios)');
    final hasCantidad = esColumns.any((c) => c['name'] == 'cantidad');
    print('✅ Columna cantidad en eventos_servicios: ${hasCantidad ? 'SÍ' : 'NO'}');

    if (hasEventoId && hasCantidad) {
      print('🚀 MIGRACIÓN VERIFICADA EXITOSAMENTE');
    } else {
      print('⚠️ Faltan columnas críticas.');
    }
  } catch (e) {
    print('❌ Error durante la verificación: $e');
  } finally {
    await db.close();
  }
}
