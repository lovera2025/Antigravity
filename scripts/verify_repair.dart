
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Eliminado mockito por no estar en pubspec
import '../lib/features/eventos/repositories/contratos_repository.dart';
import '../lib/core/services/connectivity_service.dart';

// Mock manual para ConnectivityService
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
  
  final dbPath = 'c:\\Users\\melga\\OneDrive\\Documentos\\JuniorEventos\\data.db';
  print('--- VERIFICACIÓN DE SANEAMIENTO ---');
  
  // No necesitamos Supabase real para el recálculo local
  final repo = ContratosRepository(SupabaseClient('http://localhost', 'key'), MockConnectivity());
  
  // 1. Identificar el evento PRUEBA
  final db = await databaseFactory.openDatabase(dbPath);
  final eventos = await db.query('eventos', where: "observaciones LIKE '%PRUEBA%' OR id IN (SELECT evento_id FROM contratos_alumnos WHERE nombre_alumno LIKE '%Lovera%')");
  
  if (eventos.isEmpty) {
    print('Evento PRUEBA no encontrado por observaciones. Buscando por alumno...');
  }
  
  final alumnos = await db.query('contratos_alumnos', where: "nombre_alumno LIKE '%Lovera%'");
  if (alumnos.isEmpty) {
    print('Alumno Lovera no encontrado.');
    return;
  }
  
  final eventoId = alumnos.first['evento_id'] as String;
  print('Ejecutando recalcularTodoElEvento para evento: $eventoId');
  
  await repo.recalcularTodoElEvento(eventoId);
  print('✅ Recálculo completado.');
  
  // 3. Verificar estado post-saneamiento
  final a = (await db.query('contratos_alumnos', where: "id = ?", whereArgs: [alumnos.first['id']])).first;
  print('\nESTADO ACTUALIZADO:');
  print('Alumno: ${a['nombre_alumno']}');
  print('Monto Pactado: ${a['monto_total_pactado']}');
  print('Saldo Deudor: ${a['saldo_deudor']}');
  print('Cuotas Pagadas: ${a['cuotas_pagadas']}');
  
  final pagos = await db.query('pagos_contrato_alumno', where: "contrato_alumno_id = ?", whereArgs: [a['id']]);
  print('\nHistorial de Pagos (Saneado):');
  for (var p in pagos) {
    print('  - ${p['concepto']} | Neto: ${p['monto']} | Gross: ${p['monto_gross']}');
  }
  
  await db.close();
}
