// Prueba la migración v72 sobre una COPIA de la base real y compara, tabla por
// tabla, que no cambió ni un dato de lo que ya existía.
//
// La base real se abre SOLO LECTURA, y de ahí sale la copia con `VACUUM INTO`:
// una foto consistente aunque la app esté abierta y cobrando. Todo lo demás
// pasa sobre la copia, en una carpeta temporal, que se borra al terminar.
//
//   flutter test tool/verificar_migracion_v72_test.dart
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

class _Foto {
  final Map<String, int> filas;
  final Map<String, String> huellas;
  _Foto(this.filas, this.huellas);
}

Future<_Foto> _foto(Database db) async {
  final tablas = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  final filas = <String, int>{};
  final huellas = <String, String>{};
  for (final t in tablas) {
    final nombre = t['name'] as String;
    final rows = await db.rawQuery('SELECT * FROM "$nombre" ORDER BY rowid');
    filas[nombre] = rows.length;
    huellas[nombre] = sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  }
  return _Foto(filas, huellas);
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  test('la migración v72 no cambia ni un dato de la base real (sobre copia)',
      () async {
    final real = _baseReal();
    if (!File(real).existsSync()) {
      fail('No encuentro la base en $real');
    }

    final tmp = await Directory.systemTemp.createTemp('verificar_v72_');
    final copia = '${tmp.path}${Platform.pathSeparator}copia.db';
    try {
      // 1. La copia, desde la real abierta solo lectura.
      final origen = await factory.openDatabase(
        real,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final versionReal = await origen.getVersion();
      await origen.execute("VACUUM INTO '${copia.replaceAll("'", "''")}'");
      await origen.close();
      print('Base real: $real (v$versionReal), copiada a la carpeta temporal.');

      // 2. La foto de antes, sobre la copia.
      var db = await factory.openDatabase(copia);
      final antes = await _foto(db);
      await db.close();

      // 3. Migrar la copia con el mismo onUpgrade que usa la app.
      db = await factory.openDatabase(
        copia,
        options: OpenDatabaseOptions(
          version: 72,
          onUpgrade: LocalDatabase.onUpgradeParaTest,
        ),
      );
      final versionFinal = await db.getVersion();
      final despues = await _foto(db);
      await db.close();

      // 4. Comparar.
      const nuevas = {'sillas_reparto', 'entradas_retiro', 'sorteos_mesas'};
      final distintas = <String>[];
      for (final t in antes.filas.keys) {
        final igual = antes.huellas[t] == despues.huellas[t] &&
            antes.filas[t] == despues.filas[t];
        print('  ${igual ? 'igual   ' : 'DISTINTA'}  $t  '
            '(${antes.filas[t]} filas)');
        if (!igual) distintas.add(t);
      }
      final faltan = antes.filas.keys.where((t) => !despues.filas.containsKey(t));
      final aparecieron =
          despues.filas.keys.where((t) => !antes.filas.containsKey(t)).toSet();
      print('Tablas nuevas: ${aparecieron.join(', ')}');
      print('Versión después: v$versionFinal');

      expect(versionFinal, 72);
      expect(faltan, isEmpty, reason: 'desapareció una tabla');
      expect(distintas, isEmpty, reason: 'cambiaron datos existentes');
      expect(aparecieron.difference(nuevas), isEmpty,
          reason: 'apareció una tabla que no es de la v72');
      for (final t in aparecieron) {
        expect(despues.filas[t], 0, reason: '$t tiene que nacer vacía');
      }
    } finally {
      // La copia tiene datos reales: no se deja tirada.
      await tmp.delete(recursive: true);
    }
  });
}
