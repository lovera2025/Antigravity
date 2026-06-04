import 'dart:io';
import 'dart:convert';

void main() {
  final file = File(r'c:\Users\lover\Documents\Antigravity (Gemini)\arguello_events\.dart_tool\flutter_build\17c192a1f7ddde2f93e1146b4f74020b\app.dill');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  
  print('Reading file...');
  final bytes = file.readAsBytesSync();
  print('File size: ${bytes.length} bytes');
  
  // Vamos a buscar la cadena "ejecutarAuditoriaInteligente" en los bytes
  final pattern = utf8.encode('ejecutarAuditoriaInteligente');
  final indices = <int>[];
  
  for (var i = 0; i < bytes.length - pattern.length; i++) {
    var match = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      indices.add(i);
    }
  }
  
  print('Found ${indices.length} occurrences of "ejecutarAuditoriaInteligente"');
  
  for (final idx in indices) {
    print('Occurrence at index $idx:');
    // Intentemos extraer 5000 caracteres antes y después codificados como UTF-8
    final start = (idx - 2000).clamp(0, bytes.length);
    final end = (idx + 4000).clamp(0, bytes.length);
    final slice = bytes.sublist(start, end);
    
    // Decodificar con escape para bytes no válidos
    final decoded = String.fromCharCodes(slice.map((b) => (b >= 32 && b <= 126) || b == 10 || b == 13 ? b : 46));
    print('--- CUT ---');
    print(decoded);
    print('--- END ---');
  }
}
