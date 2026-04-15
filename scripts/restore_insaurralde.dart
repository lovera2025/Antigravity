// ignore_for_file: avoid_print
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'dart:convert';


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
  
  // Obtener a Insaurralde
  final res = await db.rawQuery("SELECT * FROM contratos_alumnos WHERE nombre_alumno LIKE '%INSAURRALDE, ANGEL IVAN%' LIMIT 1");
  if (res.isNotEmpty) {
      final alumno = Map<String, dynamic>.from(res.first);
      final id = alumno['id'];
      
      // 1. Update local DB
      await db.rawUpdate("UPDATE contratos_alumnos SET mesa_extra_pagado = 15000 WHERE id = ?", [id]);
      
      // 2. Queue for Sync to Supabase
      final updatedPayload = {
          'id': id,
          'saldo_deudor': alumno['saldo_deudor'],
          'cuotas_pagadas': alumno['cuotas_pagadas'],
          'mesa_extra_pagado': 15000.0,
      };
      
      await db.insert('_sync_queue', {
          'tabla': 'contratos_alumnos',
          'operacion': 'update',
          'registro_id': id,
          'payload': jsonEncode(updatedPayload),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'intentos': 0,
      });
      
      print('====================================================');
      print('¡LISTO! Se restauraron los \$15.000 para Insaurralde.');
      print('El cambio ya está en la cola para subir a la nube.');
      print('Inicia la app presionando F5 (flutter run).');
      print('====================================================');
  } else {
      print('No se encontró al alumno.');
  }

  await db.close();
}
