import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Pregunta dónde guardar el Excel del delegado y lo guarda. `false` si se
/// canceló. Tira si no se pudo escribir (por ejemplo, si el archivo de ese
/// nombre está abierto en Excel).
Future<bool> guardarPlanillaDelegado(Uint8List bytes, String nombre) async {
  var ruta = await FilePicker.platform.saveFile(
    dialogTitle: '¿Dónde guardás el Excel para el delegado?',
    fileName: nombre,
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (ruta == null) return false;
  if (!ruta.toLowerCase().endsWith('.xlsx')) ruta += '.xlsx';
  await File(ruta).writeAsBytes(bytes, flush: true);
  return true;
}

/// Deja elegir el Excel que devolvió el delegado y devuelve su contenido.
/// `null` si se canceló.
Future<Uint8List?> elegirPlanillaDelegado() async {
  final elegido = await FilePicker.platform.pickFiles(
    dialogTitle: 'Elegí el Excel que completó el delegado',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );
  if (elegido == null || elegido.files.isEmpty) return null;
  final archivo = elegido.files.single;
  if (archivo.bytes != null) return archivo.bytes;
  final ruta = archivo.path;
  return ruta == null ? null : File(ruta).readAsBytes();
}
