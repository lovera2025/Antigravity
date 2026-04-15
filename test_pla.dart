import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

const supabaseUrl = 'https://bucnrydgojyzntgesxqb.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA';

void main() async {
  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  debugPrint('Ejecutando PLA Verification...');
  try {
    final eventosRes = await supabase
        .from('eventos')
        .select('*, clientes(*)')
        .not('estado', 'eq', 'Finalizado')
        .not('estado', 'eq', 'Cancelado');

    final List eventosData = eventosRes as List;
    final List eventosActivosData = eventosData.where((e) => e['estado'] == 'Activo').toList();
    final List<String> eventosActivosIds = eventosActivosData.map((e) => e['id'].toString()).toList();

    double totalSaldo = 0.0;

    if (eventosActivosIds.isNotEmpty) {
      final resMasivos = await supabase
          .from('contratos_alumnos')
          .select('monto_total_pactado, saldo_deudor, nombre_alumno, evento_id')
          .inFilter('evento_id', eventosActivosIds)
          .not('nombre_alumno', 'ilike', '[BAJA]%');

      for (var row in (resMasivos as List)) {
        totalSaldo += (row['saldo_deudor'] ?? 0).toDouble();
      }

      final eventosParticularesActivos = eventosActivosData.where((e) => e['modalidad'] == 'particular').toList();
      for (var ev in eventosParticularesActivos) {
          final double presupuesto = (ev['presupuesto_total'] ?? 0).toDouble();
          final double pagado = (ev['total_pagado'] ?? 0).toDouble();
          final double deudaParticular = presupuesto - pagado;
          if (deudaParticular > 0) {
              totalSaldo += deudaParticular;
          }
      }
    }
    
    debugPrint('==============================');
    debugPrint('RESULTADO PLA ATÓMICO: \$$totalSaldo');
    debugPrint('==============================');

    if (totalSaldo == 240000.0) {
      debugPrint('[SUCCESS] Coincidencia exacta validada.');
    } else {
      debugPrint('[FAILURE] El total no fue 240,000. Diferencia: ${totalSaldo - 240000}');
    }

  } catch (e) {
    debugPrint('Error: $e');
  }
  exit(0);
}
