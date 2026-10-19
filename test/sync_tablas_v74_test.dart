import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/plano/modelo/medidas_salon.dart';
import 'package:arguello_events/features/plano/repositories/predios_repository.dart';
import 'package:arguello_events/features/plano/services/armar_a_medida.dart';
import 'package:arguello_events/features/plano/services/predios_del_salon.dart';
import 'package:arguello_events/models/predio.dart';

/// La tabla de la v74 (los predios con nombre) en el motor de sincronización y
/// en su repositorio.
///
/// Las listas del motor son privadas, así que se leen del texto del archivo,
/// igual que `sync_tablas_v73_test`. Una tabla que falte en una lista no cruza
/// nunca, una columna que falte se pierde en silencio, y una tabla que aparezca
/// en una lista que borra pierde filas.
void main() {
  sqfliteFfiInit();
  final ahora = DateTime.utc(2026, 10, 20, 12);

  final motor = File('lib/core/services/sync_engine.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final cola = File('lib/core/database/sync_queue.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!))
        c.group(1)!,
    };
  }

  Predio buenaVista({String? id}) => PrediosDelSalon.guardarComo(
        nombre: 'Buena Vista',
        armado: ArmarAMedida.vacio(PlayonReal.costaSurubi),
        playon: PlayonReal.costaSurubi,
        guardados: const [],
        hechoPor: 'Jefe',
        ahora: ahora,
        idNuevo: id ?? 'd0000000-0000-4000-8000-000000000001',
      ).predio!;

  group('predios en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV74(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(predios)'))
          c['name'] as String,
      };
      expect(columnasDelMotor('predios'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('predios'), buenaVista().toMap().keys.toSet(),
          reason: 'motor y modelo');
      await db.close();
    });

    test('está en la bajada incremental y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'),
          contains("'predios': 'updated_at'"));
      expect(declaracion('_tablasDeCarga', ']'), contains("'predios'"));
      expect(motor, contains("_pullTable(db, 'predios', 'updated_at')"));
    });

    test('no cuelga de nada: sube temprano y no es hija de ninguna tabla', () {
      expect(motor, contains("if (table == 'predios') return 1;"));
      expect(cola, isNot(contains("'predios':")));
    });

    test('no está en ninguna lista que borre filas locales', () {
      expect(declaracion('_tablasAReconciliar', ']'),
          isNot(contains("'predios'")));
      expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'predios'")));
    });
  });

  group('el repositorio', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE _sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tabla TEXT NOT NULL,
          operacion TEXT NOT NULL,
          registro_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          intentos INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
      await LocalDatabase.crearTablasV74(db);
    });

    tearDown(() => db.close());

    test('el predio se guarda, se encola y vuelve igual', () async {
      final p = buenaVista();
      await db.transaction((txn) => PrediosRepository.guardarEn(txn, p));
      final guardado = await db.query('predios');
      expect(Predio.fromMap(guardado.single).toMap(), p.toMap());
      final enCola = await db.query('_sync_queue');
      expect(enCola.single['tabla'], 'predios');
      expect(enCola.single['registro_id'], p.id);
      expect(jsonDecode(enCola.single['payload'] as String), p.toMap());
    });

    test('los borrados no se ofrecen, pero la fila queda', () async {
      final a = buenaVista();
      final b = buenaVista(id: 'd0000000-0000-4000-8000-000000000002');
      final otro = PrediosDelSalon.renombrar(b, 'Arenas',
              guardados: [a], hechoPor: 'Jefe', ahora: ahora)
          .predio!;
      await db.transaction((txn) async {
        await PrediosRepository.guardarEn(txn, a);
        await PrediosRepository.guardarEn(txn, otro);
        await PrediosRepository.guardarEn(
          txn,
          PrediosDelSalon.borrar(a, hechoPor: 'Jefe', ahora: ahora),
        );
      });
      expect((await PrediosRepository.todosEn(db)).map((p) => p.nombre),
          ['Arenas']);
      expect(await db.query('predios'), hasLength(2),
          reason: 'borrar no saca la fila');
    });

    test('vienen por nombre, sin importar mayúsculas', () async {
      final nombres = ['buenos aires', 'Arenas', 'Costanera'];
      for (final (i, n) in nombres.indexed) {
        final p = PrediosDelSalon.guardarComo(
          nombre: n,
          armado: ArmarAMedida.vacio(PlayonReal.costaSurubi),
          playon: PlayonReal.costaSurubi,
          guardados: const [],
          hechoPor: null,
          ahora: ahora,
          idNuevo: 'd0000000-0000-4000-8000-00000000001$i',
        ).predio!;
        await db.transaction((txn) => PrediosRepository.guardarEn(txn, p));
      }
      expect((await PrediosRepository.todosEn(db)).map((p) => p.nombre),
          ['Arenas', 'buenos aires', 'Costanera']);
    });

    test('lo de la nube se guarda, salvo lo que acá espera subir', () async {
      final mio = buenaVista();
      await db.transaction((txn) => PrediosRepository.guardarEn(txn, mio));
      final renombradoEnLaOtra = mio.toMap()..['nombre'] = 'Otro nombre';
      final nuevoDeLaOtra = buenaVista(id: 'd0000000-0000-4000-8000-000000000003')
          .toMap()
        ..['nombre'] = 'La Rural';
      await db.transaction(
        (txn) => PrediosRepository.guardarLoDeLaNubeEn(txn, [
          renombradoEnLaOtra,
          nuevoDeLaOtra,
          {'id': 'mal'},
        ]),
      );
      final nombres = {
        for (final p in await PrediosRepository.todosEn(db)) p.id: p.nombre,
      };
      expect(nombres, {
        mio.id: 'Buena Vista',
        'd0000000-0000-4000-8000-000000000003': 'La Rural',
      });

      // Ya subido, manda la nube.
      await db.delete('_sync_queue');
      await db.transaction(
        (txn) => PrediosRepository.guardarLoDeLaNubeEn(txn, [renombradoEnLaOtra]),
      );
      expect(
        (await PrediosRepository.todosEn(db))
            .firstWhere((p) => p.id == mio.id)
            .nombre,
        'Otro nombre',
      );
    });
  });

  group('una fila que baja de la nube', () {
    test('se lee con las medidas en texto, como las manda Supabase', () {
      final fila = buenaVista().toMap()
        ..['medidas'] = '{"playon":{"frente":20,"fondo":20,"profundidad":25}}'
        ..['borrado_at'] = '2026-10-21T10:00:00+00:00';
      final p = Predio.fromMap(fila);
      expect(p.playon.frenteM, 20);
      expect(p.playon.profundidadM, 25);
      expect(p.borrado, isTrue);
    });

    test('con las medidas rotas queda el playón de fábrica, no se rompe', () {
      final p = Predio.fromMap(buenaVista().toMap()..['medidas'] = '{roto');
      expect(p.playon, PlayonReal.costaSurubi);
      expect(p.espacioONull, isNotNull);
    });

    test('con el espacio roto no se puede arrancar desde él', () {
      final p = Predio.fromMap(buenaVista().toMap()..['armado_json'] = '[1]');
      expect(p.espacioONull, isNull);
      expect(PrediosDelSalon.salonDe(p, lugarM: 2), isNull);
    });
  });
}
