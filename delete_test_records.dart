import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  const supabaseUrl = 'https://bucnrydgojyzntgesxqb.supabase.co';
  const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ1Y25yeWRnb2p5em50Z2VzeHFiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyNzI1MTQsImV4cCI6MjA4ODg0ODUxNH0.iW08JEDYM7s2SOVIKqHYK05Td-t6GdBNvEdnec5gJQA';
      
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  
  try {
    print('Fetching test egresos...');
    final result = await client.from('egresos').select().ilike('proveedor', '%maximiliano1523%');
    print('Found: \${result.length} records.');
    
    for (var r in result) {
      print('Deleting: \${r['id']} - \${r['proveedor']} - \${r['monto']}');
      await client.from('egresos').delete().eq('id', r['id']);
    }
    
    print('Also fetching "Cierre por maximiliano1523"...');
    final result2 = await client.from('egresos').select().ilike('proveedor', '%maximiliano1523%');
    print('Found: \${result2.length} records.');
    for (var r in result2) {
      print('Deleting: \${r['id']} - \${r['proveedor']} - \${r['monto']}');
      await client.from('egresos').delete().eq('id', r['id']);
    }
    print('Done.');
  } catch(e) {
    print('Error: \$e');
  }
}
