import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

void main() async {
  final supabase = SupabaseClient(
    'https://bucnrydgojyzntgesxqb.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA'
  );

  try {
    final response = await supabase
        .from('solicitudes_cotizacion')
        .select('*')
        .limit(1);
    
    if (response.isEmpty) {
      debugPrint('No hay solicitudes para analizar.');
    } else {
      final first = response.first;
      debugPrint('Estructura de la primera solicitud:');
      first.forEach((key, value) {
        debugPrint(' - $key: $value (${value.runtimeType})');
      });
    }
  } catch (e) {
    debugPrint('Error: $e');
  }
}
