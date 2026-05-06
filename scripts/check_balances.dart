import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  final docsDir = 'C:/Users/lover/Documents';
  final dbPath = p.join(docsDir, 'JuniorEventos', 'data.db');
  final db = await databaseFactory.openDatabase(dbPath);
  
  final particularesRes = await db.rawQuery('''
    SELECT 
      e.id, e.tipo, e.estado, e.fecha_evento, e.bonificacion_global_pct, c.nombre_completo,
      (SELECT SUM(precio_final_acordado * cantidad) FROM eventos_servicios WHERE evento_id = e.id) as presupuesto,
      (SELECT SUM(monto) FROM transacciones WHERE evento_id = e.id) as recaudado
    FROM eventos e
    JOIN clientes c ON e.cliente_id = c.id
    WHERE e.modalidad = 'particular'
  ''');

  double totalBalance = 0;
  for (var ev in particularesRes) {
    double presupuesto = (ev['presupuesto'] as num?)?.toDouble() ?? 0;
    // IGNORING BONIFICACION FOR THIS TEST
    final double recaudado = (ev['recaudado'] as num?)?.toDouble() ?? 0;
    final double saldoReal = (presupuesto - recaudado).clamp(0.0, double.infinity);
    
    print(ev['nombre_completo'].toString() + ' (' + ev['estado'].toString() + ') - Presupuesto: ' + presupuesto.toString() + ', Recaudado: ' + recaudado.toString() + ', SALDO: ' + saldoReal.toString() + ' | Bonific: ' + ev['bonificacion_global_pct'].toString());
    totalBalance += saldoReal;
  }
  print('TOTAL SALDOS: ' + totalBalance.toString());
  await db.close();
}
