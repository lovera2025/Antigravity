import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/features/eventos/repositories/contratos_repository.dart';
import '../lib/core/services/connectivity_service.dart';

class MockConnectivity implements ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
  
  @override
  void startMonitoring() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<AppConnectivity> recheckNow() async => AppConnectivity.offline;

  @override
  Future<bool> wakeUpCloud() async => false;

  @override
  Stream<AppConnectivity> get stream => const Stream.empty();
}

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbPath = r'C:\Users\lover\Documents\JuniorEventos\data.db';
  print('--- RECALCULANDO TODOS LOS CONTRATOS ---');
  
  final repo = ContratosRepository(SupabaseClient('http://localhost', 'key'), MockConnectivity());
  final db = await databaseFactory.openDatabase(dbPath);
  
  final contratos = await db.query('contratos_alumnos');
  print('Se encontraron ${contratos.length} contratos.');
  
  int updatedCount = 0;
  for (final c in contratos) {
    final String contratoId = c['id'] as String;
    final String nombre = c['nombre_alumno']?.toString() ?? 'Sin nombre';
    final double oldSaldo = (c['saldo_deudor'] as num).toDouble();
    
    // Ejecutar recalcular
    await repo.recalcularProgresoContrato(contratoId);
    
    // Leer nuevo saldo
    final updatedRows = await db.query('contratos_alumnos', where: 'id = ?', whereArgs: [contratoId]);
    if (updatedRows.isNotEmpty) {
      final double newSaldo = (updatedRows.first['saldo_deudor'] as num).toDouble();
      if ((oldSaldo - newSaldo).abs() > 0.01) {
        print('- $nombre: Saldo anterior $oldSaldo -> Nuevo saldo $newSaldo (Diferencia: ${(oldSaldo - newSaldo).toStringAsFixed(2)})');
        updatedCount++;
      }
    }
  }
  
  print('Saneamiento terminado. Contratos con cambios de saldo: $updatedCount');
  await db.close();
}
