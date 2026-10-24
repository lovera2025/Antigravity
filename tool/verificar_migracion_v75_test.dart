// Prueba la migración a la v75 (6.2.1, la mora congelada) sobre una COPIA de la
// base real y compara, tabla por tabla, que no cambió ni un dato de lo que ya
// existía. Mismo modelo que `verificar_migracion_v74_test.dart`.
//
// La base real se abre SOLO LECTURA, y de ahí sale la copia con `VACUUM INTO`:
// una foto consistente aunque la app esté abierta. Todo lo demás pasa sobre la
// copia, en una carpeta temporal, que se borra al terminar.
//
// Las PCs están en la v74 (la 6.1.0 a la 6.2.0): la copia salta de 74 a 75, como
// va a pasar al instalar. Tiene que aparecer la tabla `mora_congelada`, vacía.
//
// Además comprueba:
//   • que la base real quedó idéntica: mismo tamaño, misma fecha y mismo
//     SHA-256 antes y después (correrlo con la app cerrada: si alguien cobra
//     mientras corre, la base cambia por eso y la prueba lo dice);
//   • que la migración se hizo de verdad: la base estaba en una versión
//     anterior y apareció la tabla;
//   • que no cambió el esquema de nada de lo que ya existía;
//   • que se puede volver a la 6.2.0: la copia migrada abre con la versión 74,
//     con los mismos datos, y vuelve a la 75.
//
//   flutter test tool/verificar_migracion_v75_test.dart
//
// Opcional: --dart-define=base=<ruta> para otra base (siempre solo lectura).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

String _baseReal() {
  const elegida = String.fromEnvironment('base');
  if (elegida.isNotEmpty) return elegida;
  final perfil = Platform.environment['USERPROFILE'] ?? '';
  return '$perfil\\Documents\\Junior Eventos\\data.db';
}

const _nuevas = {'mora_congelada'};

class _Foto {
  final Map<String, int> filas;
  final Map<String, String> huellas;
  final List<String> esquema;
  _Foto(this.filas, this.huellas, this.esquema);
}

Future<_Foto> _foto(Database db) async {
  final objetos = await db.rawQuery(
    "SELECT type, name, tbl_name, sql FROM sqlite_master "
    "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
  );
  final filas = <String, int>{};
  final huellas = <String, String>{};
  for (final t in objetos.where((o) => o['type'] == 'table')) {
    final nombre = t['name'] as String;
    final rows = await db.rawQuery('SELECT * FROM "$nombre" ORDER BY rowid');
    filas[nombre] = rows.length;
    huellas[nombre] = sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  }
  return _Foto(filas, huellas, [
    for (final o in objetos)
      if (!_nuevas.contains(o['tbl_name'])) '${o['type']}|${o['name']}|${o['sql']}',
  ]);
}

({int bytes, DateTime modificado, String sha}) _huellaDelArchivo(String ruta) {
  final f = File(ruta);
  return (
    bytes: f.lengthSync(),
    modificado: f.lastModifiedSync(),
    sha: sha256.convert(f.readAsBytesSync()).toString(),
  );
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  test('la migración v75 no cambia ni un dato de la base real (sobre copia)', () async {
    final real = _baseReal();
    if (!File(real).existsSync()) fail('No encuentro la base en $real');

    final realAntes = _huellaDelArchivo(real);
    final tmp = await Directory.systemTemp.createTemp('verificar_v75_');
    final copia = '${tmp.path}${Platform.pathSeparator}copia.db';
    Database? abierta;
    try {
      abierta = await factory.openDatabase(real, options: OpenDatabaseOptions(readOnly: true));
      final versionReal = await abierta.getVersion();
      await abierta.execute("VACUUM INTO '${copia.replaceAll("'", "''")}'");
      await abierta.close();
      abierta = null;
      print('Base real: $real (v$versionReal), copiada a la carpeta temporal.');
      expect(versionReal, lessThan(75),
          reason: 'la base ya está en la v75: esta prueba no migraría nada');

      abierta = await factory.openDatabase(copia);
      final antes = await _foto(abierta);
      await abierta.close();
      abierta = null;

      abierta = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(version: 75, onUpgrade: LocalDatabase.onUpgradeParaTest),
      );
      final versionFinal = await abierta.getVersion();
      final despues = await _foto(abierta);
      await abierta.close();
      abierta = null;

      final distintas = <String>[];
      print('');
      print('  TABLA                          FILAS ANTES  FILAS DESPUÉS  ESTADO');
      for (final t in antes.filas.keys) {
        final igual = antes.huellas[t] == despues.huellas[t] && antes.filas[t] == despues.filas[t];
        print('  ${t.padRight(30)} ${'${antes.filas[t]}'.padLeft(11)}  '
            '${'${despues.filas[t] ?? '-'}'.padLeft(13)}  ${igual ? 'igual' : 'DISTINTA'}');
        if (!igual) distintas.add(t);
      }
      final faltan = antes.filas.keys.where((t) => !despues.filas.containsKey(t));
      final aparecieron = despues.filas.keys.where((t) => !antes.filas.containsKey(t)).toSet();
      for (final t in aparecieron) {
        print('  ${t.padRight(30)} ${'-'.padLeft(11)}  ${'${despues.filas[t]}'.padLeft(13)}  nueva');
      }
      print('');
      print('Versión después: v$versionFinal');

      expect(versionFinal, 75);
      expect(faltan, isEmpty, reason: 'desapareció una tabla');
      expect(distintas, isEmpty, reason: 'cambiaron datos existentes');
      expect(aparecieron, _nuevas, reason: 'tiene que aparecer solo la tabla de la v75');
      expect(despues.filas['mora_congelada'], 0, reason: 'mora_congelada nace vacía');
      expect(despues.esquema, antes.esquema, reason: 'cambió el esquema de algo que ya existía');
      print('Esquema de lo que ya existía: igual (${antes.esquema.length} tablas, índices y triggers).');

      // La vuelta atrás: la 6.2.0 pide la versión 74 y no tiene onDowngrade.
      abierta = await factory.openDatabase(copia, options: OpenDatabaseOptions(version: 74));
      expect(await abierta.getVersion(), 74);
      final conLaVieja = await _foto(abierta);
      await abierta.close();
      abierta = null;
      expect(conLaVieja.huellas, despues.huellas, reason: 'al volver a la 6.2.0 cambió algún dato');

      abierta = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(version: 75, onUpgrade: LocalDatabase.onUpgradeParaTest),
      );
      expect(await abierta.getVersion(), 75);
      final otraVez = await _foto(abierta);
      await abierta.close();
      abierta = null;
      expect(otraVez.huellas, despues.huellas, reason: 'al reinstalar la versión nueva cambió algún dato');
      print('Vuelta a la 6.2.0 y de nuevo a la versión nueva: los datos igual.');
    } finally {
      try {
        await abierta?.close();
      } catch (_) {}
      try {
        await tmp.delete(recursive: true);
      } catch (e) {
        print('⚠️ No pude borrar la copia en ${tmp.path}: $e. Borrala a mano.');
      }
    }
    expect(tmp.existsSync(), isFalse, reason: 'la copia quedó en ${tmp.path}');

    final realDespues = _huellaDelArchivo(real);
    print('Base real antes:   ${realAntes.bytes} bytes · ${realAntes.modificado.toIso8601String()} · ${realAntes.sha}');
    print('Base real después: ${realDespues.bytes} bytes · ${realDespues.modificado.toIso8601String()} · ${realDespues.sha}');
    const siCambio = 'la base real cambió mientras corría la prueba. Esta prueba no la escribe: '
        'si la app estaba abierta, cerrala y corré de nuevo';
    expect(realDespues.bytes, realAntes.bytes, reason: siCambio);
    expect(realDespues.modificado, realAntes.modificado, reason: siCambio);
    expect(realDespues.sha, realAntes.sha, reason: siCambio);
  });
}
