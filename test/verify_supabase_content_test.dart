// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('List all students in Supabase to verify content', () async {
    final supabase = SupabaseClient(
      'https://bucnrydgojyzntgesxqb.supabase.co',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA'
    );

    print('--- LISTANDO PRIMEROS 50 ALUMNOS ---');
    final response = await supabase
        .from('contratos_alumnos')
        .select('nombre_alumno, id')
        .limit(50);

    if (response.isEmpty) {
      print('Supabase está vacío.');
    } else {
      for (var row in response) {
        print('ALUMNO: ${row['nombre_alumno']} | ID: ${row['id']}');
      }
    }
  });
}
