// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('Search student broadly in Supabase', () async {
    final supabase = SupabaseClient(
      'https://bucnrydgojyzntgesxqb.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA'
    );

    print('--- BUSCANDO "ANGEL" EN SUPABASE ---');
    final response = await supabase
        .from('contratos_alumnos')
        .select('*')
        .ilike('nombre_alumno', '%ANGEL%');

    if (response.isEmpty) {
      print('No se encontró a nadie con "ANGEL".');
    } else {
      for (var row in response) {
        print('ALUMNO: ${row['nombre_alumno']} | ID: ${row['id']} | Mesa Pagado: ${row['mesa_extra_pagado']}');
      }
    }
  });
}
