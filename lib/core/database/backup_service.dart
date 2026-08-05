import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import 'local_database.dart';

/// Copia de seguridad automática y semanal de TODO lo que la app guarda en
/// disco: la base y los PDFs emitidos, en un solo ZIP fechado.
///
/// Corre sola al abrir la app: si la copia más nueva tiene una semana o más,
/// saca una nueva y borra las viejas dejando las últimas [conservar].
///
/// La base no se copia como archivo suelto: se le pide a SQLite un
/// `VACUUM INTO` a un temporal y ESE va al ZIP. Copiar un `.db` abierto puede
/// dejar una copia cortada a la mitad de una escritura, que después no abre.
///
/// El "cuándo fue la última" se deduce de los archivos que hay en la carpeta,
/// no de una preferencia guardada: si alguien borra las copias, la próxima
/// apertura saca una nueva, que es lo que uno querría.
class BackupService {
  static const Duration cada = Duration(days: 7);
  static const int conservar = 8; // ~2 meses de historia
  static const String _carpeta = 'backups';
  static const String _prefijo = 'junior_eventos_';
  static const String _extension = '.zip';

  /// Carpeta donde vive todo lo de la app (la que contiene `data.db`).
  static Future<Directory> carpetaDatos() async {
    final ruta = await LocalDatabase.dbPath;
    return File(ruta).parent;
  }

  /// Carpeta de copias, adentro de la de datos. La crea si no existe.
  static Future<Directory> carpetaBackups() async {
    final datos = await carpetaDatos();
    final dir = Directory('${datos.path}${Platform.pathSeparator}$_carpeta');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copias existentes, de la más nueva a la más vieja.
  static Future<List<File>> copias() async {
    final dir = await carpetaBackups();
    final files = (await dir.list().toList()).whereType<File>().where((f) {
      final nombre = f.uri.pathSegments.last;
      return nombre.startsWith(_prefijo) && nombre.endsWith(_extension);
    }).toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  /// Saca una copia completa si corresponde. Nunca tira: si falla, la app
  /// sigue. Devuelve el ZIP generado, o `null` si no hacía falta o no se pudo.
  static Future<File?> ejecutarSiCorresponde({bool forzar = false}) async {
    if (kIsWeb) return null;
    File? snapshotDb;
    try {
      final previas = await copias();
      if (!forzar && previas.isNotEmpty) {
        final antiguedad = DateTime.now().difference(
          previas.first.statSync().modified,
        );
        if (antiguedad < cada) {
          debugPrint(
            '💾 Backup: la última tiene ${antiguedad.inDays} días, no toca',
          );
          return null;
        }
      }

      final datos = await carpetaDatos();

      // 1) Snapshot consistente de la base, fuera de la carpeta de datos para
      //    que no se cuele dos veces en el recorrido de abajo.
      //
      //    `VACUUM INTO` falla si la base está en medio de una transacción, y
      //    al abrir la app el sync suele estar escribiendo. Por eso se le da
      //    aire y se reintenta: si no, el error se lo comía el catch y esa
      //    semana quedaba sin copia, en silencio.
      snapshotDb = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        '_je_snapshot_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      final db = await LocalDatabase.instance;
      final escapada = snapshotDb.path.replaceAll("'", "''");
      var intentos = 0;
      while (true) {
        try {
          await db.execute("VACUUM INTO '$escapada'");
          break;
        } catch (e) {
          intentos++;
          if (intentos >= 3) rethrow;
          debugPrint('💾 Backup: base ocupada, reintento $intentos en 20s ($e)');
          if (await snapshotDb.exists()) await snapshotDb.delete();
          await Future<void>.delayed(const Duration(seconds: 20));
        }
      }

      // 2) ZIP con la base + todo lo demás que haya en la carpeta.
      final destino = await _rutaNueva();
      final zip = ZipFileEncoder();
      zip.create(destino);
      try {
        zip.addFile(snapshotDb, 'data.db');
        for (final item in datos.listSync()) {
          final nombre = item.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
          // La carpeta de copias no entra: se copiaría a sí misma.
          if (item is Directory && nombre == _carpeta) continue;
          // La base ya entró arriba, consistente.
          if (item is File && nombre == 'data.db') continue;
          if (item is File) {
            zip.addFile(item, nombre);
          } else if (item is Directory) {
            zip.addDirectory(item);
          }
        }
      } finally {
        zip.close();
      }

      final archivo = File(destino);
      final mb = (await archivo.length()) / (1024 * 1024);
      debugPrint('💾 Backup completo: $destino (${mb.toStringAsFixed(1)} MB)');

      await _podar();
      return archivo;
    } catch (e) {
      // Un backup que falla no puede impedir que se trabaje.
      debugPrint('⚠️ Backup: no se pudo generar ($e)');
      return null;
    } finally {
      if (snapshotDb != null && snapshotDb.existsSync()) {
        try {
          snapshotDb.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// `backups/junior_eventos_2026-08-03.zip`, con sufijo si ya hay una de hoy.
  static Future<String> _rutaNueva() async {
    final dir = await carpetaBackups();
    final h = DateTime.now();
    String dd(int v) => v.toString().padLeft(2, '0');
    final base = '$_prefijo${h.year}-${dd(h.month)}-${dd(h.day)}';
    var ruta = '${dir.path}${Platform.pathSeparator}$base$_extension';
    var n = 2;
    while (await File(ruta).exists()) {
      ruta = '${dir.path}${Platform.pathSeparator}$base($n)$_extension';
      n++;
    }
    return ruta;
  }

  /// Deja las [conservar] más nuevas y borra el resto.
  static Future<void> _podar() async {
    final previas = await copias();
    if (previas.length <= conservar) return;
    for (final vieja in previas.skip(conservar)) {
      try {
        await vieja.delete();
        debugPrint('🧹 Backup viejo borrado: ${vieja.uri.pathSegments.last}');
      } catch (e) {
        debugPrint('⚠️ No se pudo borrar ${vieja.path}: $e');
      }
    }
  }
}
