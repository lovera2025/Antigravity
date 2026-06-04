import 'dart:io';
import 'package:kernel/kernel.dart';
import 'package:kernel/binary/ast_from_binary.dart';

void main() async {
  final bytes = File('.dart_tool/flutter_build/4f7e8fc81540df76d6048b341dd69ad5/app.dill').readAsBytesSync();
  final component = loadComponentFromBytes(bytes);
  
  for (final lib in component.libraries) {
    if (lib.fileUri.path.contains('finanzas_view.dart')) {
      print('Found: ');
      // Get source
      final source = component.uriToSource[lib.fileUri];
      if (source != null) {
        final text = String.fromCharCodes(source.source);
        File('_recovered_finanzas_view.dart').writeAsStringSync(text);
        print('Written  chars to _recovered_finanzas_view.dart');
      } else {
        print('No source found for library');
      }
      break;
    }
  }
}
