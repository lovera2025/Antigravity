// Prueba la migración a la v73 sobre una COPIA de la base real y compara, tabla
// por tabla, que no cambió ni un dato de lo que ya existía.
//
// La base real se abre SOLO LECTURA, y de ahí sale la copia con `VACUUM INTO`:
// una foto consistente aunque la app esté abierta y cobrando. Todo lo demás
// pasa sobre la copia, en una carpeta temporal, que se borra al terminar.
//
// Las PCs están en la v71 (la 5.0.0): la copia salta de 71 a 73 en un solo
// paso, como va a pasar al instalar. Tienen que aparecer las cinco tablas
// nuevas (tres de la v72 y dos de la v73), vacías.
//
// Además comprueba:
//   • que la base real quedó idéntica: mismo tamaño, misma fecha y mismo
//     SHA-256 antes y después (conviene correrlo con la app cerrada: si alguien
//     cobra mientras corre, la base cambia por eso y la prueba lo dice);
//   • que la migración se hizo de verdad: la base estaba en una versión
//     anterior y aparecieron las dos tablas de la v73;
//   • que no cambió el esquema de nada de lo que ya existía;
//   • que se puede volver a la 5.0.0: la copia migrada abre con la versión 71,
//     con los mismos datos, y vuelve a la 73.
//
//   flutter test tool/verificar_migracion_v73_test.dart
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

const _nuevas = {
  'sillas_reparto',
  'entradas_retiro',
  'sorteos_mesas',
  'planos_evento',
  'mesas_movimientos',
};

class _Foto {
  final Map<String, int> filas;
  final Map<String, String> huellas;

  /// Tablas, índices y triggers de lo que no es nuevo, con su SQL.
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
      if (!_nuevas.contains(o['tbl_name']))
        '${o['type']}|${o['name']}|${o['sql']}',
  ]);
}

/// Tamaño, fecha y SHA-256 del archivo, para saber si alguien lo tocó.
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

  test('la migración v73 no cambia ni un dato de la base real (sobre copia)',
      () async {
    final real = _baseReal();
    if (!File(real).existsSync()) {
      fail('No encuentro la base en $real');
    }

    final realAntes = _huellaDelArchivo(real);
    final tmp = await Directory.systemTemp.createTemp('verificar_v73_');
    final copia = '${tmp.path}${Platform.pathSeparator}copia.db';
    Database? abierta;
    try {
      // 1. La copia, desde la real abierta solo lectura.
      abierta = await factory.openDatabase(
        real,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final versionReal = await abierta.getVersion();
      await abierta.execute("VACUUM INTO '${copia.replaceAll("'", "''")}'");
      await abierta.close();
      abierta = null;
      print('Base real: $real (v$versionReal), copiada a la carpeta temporal.');
      expect(
        versionReal,
        lessThan(73),
        reason: 'la base ya está en la v73: esta prueba no migraría nada',
      );

      // 2. La foto de antes, sobre la copia.
      abierta = await factory.openDatabase(copia);
      final antes = await _foto(abierta);
      await abierta.close();
      abierta = null;

      // 3. Migrar la copia con el mismo onUpgrade que usa la app.
      abierta = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(
          version: 73,
          onUpgrade: LocalDatabase.onUpgradeParaTest,
        ),
      );
      final versionFinal = await abierta.getVersion();
      final despues = await _foto(abierta);
      await abierta.close();
      abierta = null;

      // 4. Comparar.
      final distintas = <String>[];
      print('');
      print('  TABLA                          FILAS ANTES  FILAS DESPUÉS  ESTADO');
      for (final t in antes.filas.keys) {
        final igual = antes.huellas[t] == despues.huellas[t] &&
            antes.filas[t] == despues.filas[t];
        print('  ${t.padRight(30)} ${'${antes.filas[t]}'.padLeft(11)}  '
            '${'${despues.filas[t] ?? '-'}'.padLeft(13)}  '
            '${igual ? 'igual' : 'DISTINTA'}');
        if (!igual) distintas.add(t);
      }
      final faltan =
          antes.filas.keys.where((t) => !despues.filas.containsKey(t));
      final aparecieron =
          despues.filas.keys.where((t) => !antes.filas.containsKey(t)).toSet();
      for (final t in aparecieron) {
        print('  ${t.padRight(30)} ${'-'.padLeft(11)}  '
            '${'${despues.filas[t]}'.padLeft(13)}  nueva');
      }
      print('');
      print('Versión después: v$versionFinal');

      expect(versionFinal, 73);
      expect(faltan, isEmpty, reason: 'desapareció una tabla');
      expect(distintas, isEmpty, reason: 'cambiaron datos existentes');
      expect(aparecieron.difference(_nuevas), isEmpty,
          reason: 'apareció una tabla que no es de la v72 ni de la v73');
      expect(
        despues.filas.keys,
        containsAll(['planos_evento', 'mesas_movimientos']),
        reason: 'las tablas de la v73 no se crearon',
      );
      for (final t in aparecieron) {
        expect(despues.filas[t], 0, reason: '$t tiene que nacer vacía');
      }
      expect(despues.esquema, antes.esquema,
          reason: 'cambió el esquema de algo que ya existía');
      print('Esquema de lo que ya existía: igual '
          '(${antes.esquema.length} tablas, índices y triggers).');

      // 5. La vuelta atrás: la 5.0.0 pide la versión 71 y no tiene onDowngrade.
      abierta = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(version: 71),
      );
      expect(await abierta.getVersion(), 71);
      final conLaVieja = await _foto(abierta);
      await abierta.close();
      abierta = null;
      expect(conLaVieja.huellas, despues.huellas,
          reason: 'al volver a la 5.0.0 cambió algún dato');

      abierta = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(
          version: 73,
          onUpgrade: LocalDatabase.onUpgradeParaTest,
        ),
      );
      expect(await abierta.getVersion(), 73);
      final otraVez = await _foto(abierta);
      await abierta.close();
      abierta = null;
      expect(otraVez.huellas, despues.huellas,
          reason: 'al reinstalar la versión nueva cambió algún dato');
      print('Vuelta a la 5.0.0 y de nuevo a la versión nueva: los datos igual.');
    } finally {
      // La copia tiene datos reales: no se deja tirada, falle lo que falle.
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

    // 6. La base real, intacta.
    final realDespues = _huellaDelArchivo(real);
    print('Base real antes:   ${realAntes.bytes} bytes · '
        '${realAntes.modificado.toIso8601String()} · ${realAntes.sha}');
    print('Base real después: ${realDespues.bytes} bytes · '
        '${realDespues.modificado.toIso8601String()} · ${realDespues.sha}');
    const siCambio = 'la base real cambió mientras corría la prueba. Esta '
        'prueba no la escribe: si la app estaba abierta, cerrala y corré de '
        'nuevo';
    expect(realDespues.bytes, realAntes.bytes, reason: siCambio);
    expect(realDespues.modificado, realAntes.modificado, reason: siCambio);
    expect(realDespues.sha, realAntes.sha, reason: siCambio);
  });
}
