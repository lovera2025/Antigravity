import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v77 (la barra) tiene que agregar sus tablas y **nada más**: ni una
/// fila de lo que ya existe puede cambiar, se tiene que poder correr dos veces, y si
/// alguien reinstala la 6.2.1 la base tiene que seguir abriendo. Mismo modelo que
/// `migracion_v76_test.dart`.
///
/// Las PCs reales están en la 75 (la 6.2.1): al instalar saltan de 75 a 77 de una
/// vez. También se prueba el salto de 76 a 77, el de esta PC de desarrollo si corrió
/// la rama. Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV76 = ['permisos_operador', 'permisos_operador_cambios'];
  const tablasV77 = [
    'barra_productos',
    'barra_precios',
    'barra_cajas',
    'barra_ventas',
    'barra_anulaciones',
  ];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v77_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base con la plata, los operadores, un alumno con la mora congelada y un
  /// marcador de sync; en la 76, además, un operador con permisos.
  Future<void> crearBase(int version) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              mora_pendiente_tracked REAL DEFAULT 0,
              mora_tracked_ajuste REAL DEFAULT 0, updated_at TEXT)
          ''');
          await db.execute('''
            CREATE TABLE pagos_contrato_alumno (
              id TEXT PRIMARY KEY, contrato_alumno_id TEXT NOT NULL,
              monto REAL NOT NULL, concepto TEXT, fecha_pago TEXT)
          ''');
          await db.execute(
            'CREATE TABLE _sync_meta (clave TEXT PRIMARY KEY, valor TEXT)',
          );
          await db.execute('''
            CREATE TABLE _sync_queue (
              id INTEGER PRIMARY KEY AUTOINCREMENT, tabla TEXT, operacion TEXT,
              registro_id TEXT, payload TEXT, created_at TEXT,
              intentos INTEGER DEFAULT 0, ultimo_error TEXT)
          ''');
          await LocalDatabase.crearTablasV72(db);
          await LocalDatabase.crearTablasV73(db);
          await LocalDatabase.crearTablasV74(db);
          await LocalDatabase.crearTablasV75(db);
          if (version >= 76) await LocalDatabase.crearTablasV76(db);
          await db.execute('''
            CREATE TABLE operadores_caja (
              id TEXT PRIMARY KEY, nombre TEXT NOT NULL, pin TEXT NOT NULL,
              activo INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL)
          ''');
          await db.insert('operadores_caja', {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'nombre': 'Maxi',
            'pin': '1234',
            'activo': 1,
            'created_at': '2026-05-01T00:00:00.000Z',
            'updated_at': '2026-05-01T00:00:00.000Z',
          });
          if (version >= 76) {
            await db.insert('permisos_operador', {
              'id': 'f0000000-0000-4000-8000-000000000001',
              'operador_id': 'a0000000-0000-4000-8000-000000000001',
              'cobros': 1,
              'entradas': 0,
              'barra': 1,
              'created_at': '2026-11-02T00:00:00.000Z',
              'updated_at': '2026-11-02T00:00:00.000Z',
            });
          }
          await db.insert('mora_congelada', {
            'id': 'f0000000-0000-4000-8000-000000000009',
            'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
            'pausas': '[{"cuota":4,"desde":"2026-10-23"}]',
            'created_at': '2026-10-23T00:00:00.000Z',
            'updated_at': '2026-10-23T00:00:00.000Z',
          });
          for (var i = 0; i < 40; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'mora_pendiente_tracked': i % 3 == 0 ? 6900.0 : 0.0,
              'mora_tracked_ajuste': i % 7 == 0 ? 3300.0 : 0.0,
              'updated_at': '2026-10-1${i % 5}T10:00:00.000Z',
            });
            await db.insert('pagos_contrato_alumno', {
              'id': 'p0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'contrato_alumno_id': id,
              'monto': 70000.0 + i,
              'concepto': 'Cuota Base',
              'fecha_pago': '2026-09-1${i % 9}',
            });
          }
          await db.insert('_sync_meta', {
            'clave': 'last_pull_contratos_alumnos',
            'valor': '2026-10-23T21:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'pagos_contrato_alumno',
            'operacion': 'insert',
            'registro_id': 'p0000000-0000-4000-8000-000000000003',
            'payload': '{"id":"p0000000-0000-4000-8000-000000000003"}',
            'created_at': '2026-10-23T21:00:00.000Z',
          });
        },
      ),
    );
    await db.close();
  }

  Future<Map<String, String>> foto(Database db) async {
    final tablas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final out = <String, String>{};
    for (final t in tablas) {
      final nombre = t['name'] as String;
      final filas = await db.rawQuery('SELECT * FROM $nombre ORDER BY 1');
      out[nombre] = jsonEncode(filas);
    }
    return out;
  }

  Future<List<String>> esquemaSin(Database db, List<String> nuevas) async {
    final filas = await db.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    return [
      for (final f in filas)
        if (!nuevas.contains(f['tbl_name']))
          '${f['type']}|${f['name']}|${f['sql']}',
    ];
  }

  Future<Database> abrirEnVersion(int version) => factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onUpgrade: LocalDatabase.onUpgradeParaTest,
        ),
      );

  Map<String, String> sin(Map<String, String> f, List<String> tablas) =>
      Map.of(f)..removeWhere((k, _) => tablas.contains(k));

  for (final desde in [75, 76]) {
    test('de $desde a 77: aparecen las tablas de la barra y lo demás igual', () async {
      await crearBase(desde);
      final nuevas = [if (desde == 75) ...tablasV76, ...tablasV77];
      final antes = await factory.openDatabase(path);
      final fotoAntes = await foto(antes);
      final esquemaAntes = await esquemaSin(antes, nuevas);
      await antes.close();
      expect(fotoAntes.containsKey('barra_ventas'), isFalse);

      final db = await abrirEnVersion(77);
      expect(await db.getVersion(), 77);
      final fotoDespues = await foto(db);
      expect(await esquemaSin(db, nuevas), esquemaAntes,
          reason: 'la migración no toca el esquema de lo que ya existía');
      await db.close();

      for (final t in nuevas) {
        expect(fotoDespues[t], '[]', reason: '$t nace vacía');
      }
      expect(sin(fotoDespues, nuevas), fotoAntes);
    });
  }

  test('pidiendo la 76, las tablas de la v77 no aparecen', () async {
    await crearBase(75);
    final db = await abrirEnVersion(76);
    await LocalDatabase.onUpgradeParaTest(db, 74, 76);
    final f = await foto(db);
    for (final t in tablasV77) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('las tablas nuevas tienen las columnas que usa el sync', () async {
    await crearBase(76);
    final db = await abrirEnVersion(77);
    Future<Set<String>> columnas(String t) async => {
          for (final c in await db.rawQuery('PRAGMA table_info($t)')) c['name'] as String,
        };
    const comunes = {'hecho_por', 'device_id', 'created_at', 'updated_at'};
    expect(await columnas('barra_productos'), {
      'id', 'nombre', 'categoria', 'activo', 'orden', 'imagen_url', ...comunes,
    });
    expect(await columnas('barra_precios'), {
      'id', 'evento_id', 'producto_id', 'precio', 'activo', 'orden', 'stock_inicial',
      'aviso_stock', ...comunes,
    });
    expect(await columnas('barra_cajas'), {
      'id', 'evento_id', 'operador_id', 'operador_nombre', 'numero_caja', 'sede',
      'cambio_inicial', 'abierta_at', 'cerrada_at', 'efectivo_contado', 'diferencia',
      'nota_cierre', ...comunes,
    });
    expect(await columnas('barra_ventas'), {
      'id', 'caja_barra_id', 'evento_id', 'numero', 'renglones', 'total', 'medio',
      'efectivo', 'transferencia', 'recibe', 'vuelto', 'recargo', 'recargo_pct', ...comunes,
    });
    expect(await columnas('barra_anulaciones'), {
      'id', 'venta_id', 'caja_barra_id', 'evento_id', 'motivo', ...comunes,
    });
    await db.close();
  });

  test('ningún índice único fuera del id: al bajar, un REPLACE no borra otra fila', () async {
    await crearBase(76);
    final db = await abrirEnVersion(77);
    for (final t in tablasV77) {
      for (final i in await db.rawQuery('PRAGMA index_list($t)')) {
        if (i['origin'] == 'pk') continue;
        expect(i['unique'], 0, reason: '$t tiene el índice único ${i['name']}');
      }
    }
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBase(76);
    final db = await abrirEnVersion(77);
    await db.insert('barra_productos', {
      'id': 'b0000000-0000-4000-8000-000000000001',
      'nombre': 'Cerveza lata',
      'activo': 1,
      'orden': 0,
      'created_at': '2026-11-03T00:00:00.000Z',
      'updated_at': '2026-11-03T00:00:00.000Z',
    });
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV77(db);
    await LocalDatabase.onUpgradeParaTest(db, 76, 77);
    await LocalDatabase.onUpgradeParaTest(db, 71, 77);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v77 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
    final fuente = File('lib/core/database/local_database.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    String tramo(String desde, String hasta) {
      final i = fuente.indexOf(desde);
      expect(i, greaterThanOrEqualTo(0), reason: 'no encontré "$desde"');
      final f = fuente.indexOf(hasta, i + desde.length);
      expect(f, greaterThan(i), reason: 'no encontré el final de "$desde"');
      return fuente.substring(i, f);
    }

    final crear = tramo(
      'static Future<void> crearTablasV77(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 77 && newVersion >= 77) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV77', crear), ('el bloque de la v77', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    for (final t in tablasV77) {
      expect(crear, contains('CREATE TABLE IF NOT EXISTS $t ('));
    }
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    expect(fuente, contains('await crearTablasV77(db);'));
  });

  test('si se reinstala la 6.2.1 la base abre, y al volver a la nueva también', () async {
    await crearBase(75);
    var db = await abrirEnVersion(77);
    await db.insert('barra_ventas', {
      'id': 'b1000000-0000-4000-8000-000000000001',
      'caja_barra_id': 'b2000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'numero': 1,
      'renglones': '[]',
      'total': 7000.0,
      'medio': 'efectivo',
      'efectivo': 7000.0,
      'created_at': '2026-12-04T23:41:00.000Z',
      'updated_at': '2026-12-04T23:41:00.000Z',
    });
    await db.insert('_sync_queue', {
      'tabla': 'barra_ventas',
      'operacion': 'insert',
      'registro_id': 'b1000000-0000-4000-8000-000000000001',
      'payload': '{}',
      'created_at': '2026-12-04T23:41:00.000Z',
    });
    final fotoV77 = await foto(db);
    await db.close();

    // La 6.2.1 pide la versión 75 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 75));
    expect(await db.getVersion(), 75);
    expect(await foto(db), fotoV77);
    await db.close();

    db = await abrirEnVersion(77);
    expect(await db.getVersion(), 77);
    expect(await foto(db), fotoV77);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('la copia usa la versión de la app: una base en 75 se copia', () async {
      await crearBase(75);
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 77);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v77.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 75);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBase(75);
      final db = await abrirEnVersion(77);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 77), isNull);
    });
  });
}
