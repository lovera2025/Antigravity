import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/repositories/permisos_operador_repository.dart';

/// Los permisos de los operadores: lo que decide, el repositorio y su lugar en el
/// motor de sincronización. Mismo modelo que `sync_tablas_v75_test.dart`: las
/// listas del motor son privadas y se leen del texto del archivo.
void main() {
  sqfliteFfiInit();
  const operador = 'a0000000-0000-4000-8000-000000000001';
  final hoy = DateTime.utc(2026, 11, 3, 12);

  group('qué permisos tiene', () {
    test('sin fila, es de Cobros solo: los operadores de hoy siguen igual', () {
      final p = PermisosEfectivos.de(null);
      expect(p.cobros, isTrue);
      expect(p.entradas, isFalse);
      expect(p.barra, isFalse);
      expect(p.ninguno, isFalse);
      expect(p.lista, [PermisoOperador.cobros]);
    });

    test('con fila y todo en cero, no tiene permisos: es otra cosa que sin fila', () {
      final p = PermisosEfectivos.de(PermisosOperador.para(
        operadorId: operador,
        permisos: const PermisosEfectivos(),
        ahora: hoy,
      ));
      expect(p.ninguno, isTrue);
      expect(p.lista, isEmpty);
      expect(p, isNot(PermisosEfectivos.soloCobros));
    });

    test('con fila, lo que diga la fila, y vuelve igual de la base', () {
      final fila = PermisosOperador.para(
        operadorId: operador,
        permisos: const PermisosEfectivos(entradas: true, barra: true),
        hechoPor: 'Jefe',
        deviceId: 'pc-1',
        ahora: hoy,
      );
      final leida = PermisosOperador.fromMap(fila.toMap());
      expect(leida.permisos, fila.permisos);
      expect(leida.permisos.lista, [PermisoOperador.entradas, PermisoOperador.barra]);
      expect(leida.hechoPor, 'Jefe');
      expect(leida.deviceId, 'pc-1');
      expect(fila.toMap()['entradas'], 1);
      expect(fila.toMap()['cobros'], 0);
    });

    test('el id sale del operador: las dos PCs escriben la misma fila', () {
      final a = PermisosOperador.para(
        operadorId: operador,
        permisos: const PermisosEfectivos(),
        ahora: hoy,
      );
      expect(a.id, UuidUtils.permisosOperadorId(operador));
      expect(a.id, hasLength(36));
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
      await LocalDatabase.crearTablasV76(db);
    });

    tearDown(() => db.close());

    Future<List<CambioDePermiso>> guardar(
      PermisosEfectivos p, {
      DateTime? cuando,
    }) =>
        db.transaction((txn) => PermisosOperadorRepository.guardarEn(
              txn,
              operadorId: operador,
              permisos: p,
              quien: 'Jefe',
              deviceId: 'pc-1',
              ahora: cuando ?? hoy,
            ));

    test('guardar a uno de hoy sin tocar nada no le crea una fila', () async {
      final cambios = await guardar(PermisosEfectivos.soloCobros);
      expect(cambios, isEmpty);
      expect(await db.query('permisos_operador'), isEmpty);
      expect(await db.query('permisos_operador_cambios'), isEmpty);
      expect(await db.query('_sync_queue'), isEmpty);
    });

    test('darle Entradas a uno de hoy: la fila, un renglón y las dos subidas', () async {
      final cambios = await guardar(
        const PermisosEfectivos(cobros: true, entradas: true),
      );
      expect(cambios, hasLength(1));
      expect(cambios.single.permiso, PermisoOperador.entradas);
      expect(cambios.single.dado, isTrue);

      final fila = (await db.query('permisos_operador')).single;
      expect(fila['id'], UuidUtils.permisosOperadorId(operador));
      expect(fila['cobros'], 1);
      expect(fila['entradas'], 1);
      expect(fila['hecho_por'], 'Jefe');
      expect(fila['device_id'], 'pc-1');

      final cola = await db.query('_sync_queue');
      expect(
        cola.map((e) => e['tabla']).toSet(),
        {'permisos_operador', 'permisos_operador_cambios'},
      );
      for (final e in cola) {
        expect(e['operacion'], 'insert');
        expect(jsonDecode(e['payload'] as String)['operador_id'], operador);
      }
    });

    test('sacarle Cobros queda anotado: se dio de baja, y por quién', () async {
      final cambios = await guardar(const PermisosEfectivos(entradas: true));
      expect(cambios, hasLength(2), reason: 'Cobros sacado y Entradas dado');
      final renglones = await db.query(
        'permisos_operador_cambios',
        orderBy: 'permiso',
      );
      expect(renglones.first['permiso'], 'cobros');
      expect(renglones.first['dado'], 0);
      expect(renglones.first['hecho_por'], 'Jefe');
      expect(renglones.last['permiso'], 'entradas');
      expect(renglones.last['dado'], 1);
    });

    test('sacarlos todos no borra la fila: queda en cero', () async {
      await guardar(const PermisosEfectivos(entradas: true));
      await guardar(
        const PermisosEfectivos(),
        cuando: hoy.add(const Duration(minutes: 5)),
      );
      final fila = (await db.query('permisos_operador')).single;
      expect(fila['entradas'], 0);
      expect(fila['cobros'], 0);
      expect(fila['created_at'], '2026-11-03T12:00:00.000Z', reason: 'conserva cuándo nació');
      expect(fila['updated_at'], '2026-11-03T12:05:00.000Z');
      expect(await db.query('permisos_operador_cambios'), hasLength(3));
      expect(
        PermisosEfectivos.de(await PermisosOperadorRepository.deEn(db, operador)).ninguno,
        isTrue,
      );
    });

    test('guardar lo mismo otra vez no agrega renglones', () async {
      const p = PermisosEfectivos(entradas: true);
      await guardar(p);
      final antes = (await db.query('permisos_operador_cambios')).length;
      expect(await guardar(p, cuando: hoy.add(const Duration(minutes: 1))), isEmpty);
      expect(await db.query('permisos_operador_cambios'), hasLength(antes));
    });

    test('una base sin las tablas (que no migró) no tira: sigue de Cobros', () async {
      final tmp = await Directory.systemTemp.createTemp('sin_permisos_');
      final sinTabla = await databaseFactoryFfi
          .openDatabase('${tmp.path}${Platform.pathSeparator}data.db');
      expect(await PermisosOperadorRepository.deEn(sinTabla, operador), isNull);
      expect(await PermisosOperadorRepository.todasEn(sinTabla), isEmpty);
      await sinTabla.close();
      await tmp.delete(recursive: true);
    });
  });

  group('en las listas del motor', () {
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
        for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!)) c.group(1)!,
      };
    }

    test('suben y bajan todas sus columnas: las del modelo y las de la base', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV76(db);
      Future<Set<String>> enLaBase(String tabla) async => {
            for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
              c['name'] as String,
          };
      final fila = PermisosOperador.para(
        operadorId: operador,
        permisos: PermisosEfectivos.soloCobros,
        ahora: hoy,
      );
      final renglon = CambioDePermiso.entre(
        operadorId: operador,
        antes: PermisosEfectivos.soloCobros,
        despues: const PermisosEfectivos(),
        ahora: hoy,
      ).single;
      expect(columnasDelMotor('permisos_operador'), await enLaBase('permisos_operador'));
      expect(columnasDelMotor('permisos_operador'), fila.toMap().keys.toSet());
      expect(
        columnasDelMotor('permisos_operador_cambios'),
        await enLaBase('permisos_operador_cambios'),
      );
      expect(columnasDelMotor('permisos_operador_cambios'), renglon.toMap().keys.toSet());
      await db.close();
    });

    test('los permisos bajan con los operadores, cada 10 s; el registro, cada minuto', () {
      final columnas = declaracion('_incrementalColumns', '}');
      expect(columnas, contains("'permisos_operador': 'updated_at'"));
      expect(columnas, contains("'permisos_operador_cambios': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'permisos_operador'"));
      expect(declaracion('_tablasDeCarga', ']'), contains("'permisos_operador_cambios'"));
      expect(motor, contains("_pullTable(db, 'permisos_operador', 'updated_at')"));
      expect(motor, contains("_pullTable(db, 'permisos_operador_cambios', 'updated_at')"));
    });

    test('suben después de su operador', () {
      expect(motor, contains("if (table == 'operadores_caja') return 1;"));
      expect(
        RegExp(r"table == 'permisos_operador' \|\|\s+table == 'permisos_operador_cambios'\) \{\s+return 2;")
            .hasMatch(motor),
        isTrue,
      );
      expect(cola, contains("'permisos_operador': 'operador_id'"));
      expect(cola, contains("'permisos_operador_cambios': 'operador_id'"));
    });

    test('no están en ninguna lista que borre filas locales', () {
      for (final tabla in ['permisos_operador', 'permisos_operador_cambios']) {
        expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'$tabla'")));
        expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'$tabla'")));
        expect(declaracion('_tablasSinRevisarBorrados', '}'), contains("'$tabla':"));
      }
    });
  });
}
