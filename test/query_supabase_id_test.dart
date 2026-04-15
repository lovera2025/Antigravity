// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Query student by ID in Supabase', () async {
    final supabase = SupabaseClient(
      'https://bucnrydgojyzntgesxqb.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA'
    );

    final id = '39b31c35-2f41-46e8-9ce3-5bd20fe4755e';
    print('--- BUSCANDO ID $id EN SUPABASE ---');
    final response = await supabase
        .from('contratos_alumnos')
        .select('*')
        .eq('id', id);

    if (response.isEmpty) {
      print('ID no encontrado en Supabase.');
    } else {
      final row = response.first;
      print('ALUMNO: ${row['nombre_alumno']}');
      print('Mesa Extra Pagado (Cloud): ${row['mesa_extra_pagado']}');
    }
  });
}
