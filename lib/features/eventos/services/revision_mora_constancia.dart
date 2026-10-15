import 'dart:io';

import '../../../core/database/local_database.dart';
import '../../../core/utils/ar_time.dart';

/// Lo que corrige sola la revisión de la mora queda escrito en
/// `revision_mora.txt`, en la carpeta de la base (Documentos\Junior Eventos):
/// cada vez, la fecha y un renglón por alumno con el antes y el después.
///
/// No va en las notas del alumno: hay una sola nota por alumno, y escribirla
/// pisaría la que el operador ya tenga.
class RevisionMoraConstancia {
  RevisionMoraConstancia._();

  static const archivo = 'revision_mora.txt';

  static Future<void> anotar(List<String> renglones) async {
    if (renglones.isEmpty) return;
    final base = File(await LocalDatabase.dbPath);
    final destino = File('${base.parent.path}${Platform.pathSeparator}$archivo');
    await destino.writeAsString(
      textoDe(renglones, ArTime.nowAr()),
      mode: FileMode.append,
      flush: true,
    );
  }

  /// El bloque que se agrega al archivo, aparte para poder probarlo.
  static String textoDe(List<String> renglones, DateTime ahoraAr) {
    String dos(int n) => n.toString().padLeft(2, '0');
    final cuando = '${dos(ahoraAr.day)}/${dos(ahoraAr.month)}/${ahoraAr.year} '
        '${dos(ahoraAr.hour)}:${dos(ahoraAr.minute)}';
    final b = StringBuffer()
      ..writeln(
        '$cuando · la revisión automática de la mora corrigió '
        '${renglones.length} alumno(s):',
      );
    for (final r in renglones) {
      b.writeln('  $r');
    }
    b.writeln();
    return b.toString();
  }
}
