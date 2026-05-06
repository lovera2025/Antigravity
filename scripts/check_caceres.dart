import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(p.join('C:/Users/lover/Documents', 'JuniorEventos', 'data.db'));
  
  final res = await db.rawQuery('SELECT e.id, c.nombre_completo, e.bonificacion_global_pct, (SELECT SUM(precio_final_acordado * cantidad) FROM eventos_servicios WHERE evento_id = e.id) as pres FROM eventos e JOIN clientes c ON e.cliente_id = c.id WHERE c.nombre_completo LIKE \'%CACERES%\'');
  print(res);
  await db.close();
}
