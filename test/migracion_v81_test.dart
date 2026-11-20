import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v81 (la entrega de entradas en dos partes) tiene que agregar su
/// tabla y **nada más**: ni una fila de lo que ya existe puede cambiar, se tiene
/// que poder correr dos veces, y si alguien reinstala la 6.9.2 la base tiene
/// que seguir abriendo. Mismo modelo que `migracion_v80_test.dart`.
///
/// Las PCs reales están en la 80 (la 6.9.x): al instalar saltan de 80 a 81. Corre
/// sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV81 = ['entradas_entregas'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v81_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base en la 80 con la plata, una entrega de entradas de las 8 juntas,
  /// una venta de entradas, un marcador de sync y algo en la cola.
  Future<void> crearBaseV80() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 80,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              updated_at TEXT)
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
          await LocalDatabase.crearTablasV76(db);
          await LocalDatabase.crearTablasV77(db);
          await LocalDatabase.crearTablasV78(db);
          await LocalDatabase.crearTablasV79(db);
          await LocalDatabase.crearTablasV80(db);
          for (var i = 0; i < 30; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'updated_at': '2026-11-0${1 + i % 4}T10:00:00.000Z',
            });
            await db.insert('pagos_contrato_alumno', {
              'id': 'p0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'contrato_alumno_id': id,
              'monto': 70000.0 + i,
              'concepto': 'Cuota Base',
              'fecha_pago': '2026-10-1${i % 9}',
            });
          }
          // Una entrega de las 8 juntas, hecha con la 6.9.x: la v81 no la toca.
          await db.insert('entradas_retiro', {
            'id': 'r0000000-0000-4000-8000-000000000001',
            'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
            'estado': 'entregado',
            'vip': 3,
            'generales': 5,
            'tramos': '1043-1047',
            'menores_10': 1,
            'parentesco': 'madre',
            'retiro_nombre': 'MADRE, UNA',
            'autorizacion_firmada': 0,
            'escribio_en_planilla': 1,
            'entregado_por': 'Carla',
            'entregado_at': '2026-11-18T15:00:00.000Z',
            'created_at': '2026-11-18T15:00:00.000Z',
            'updated_at': '2026-11-18T15:00:00.000Z',
          });
          // Una venta de entradas (v80).
          await db.insert('entradas_ventas', {
            'id': 'b0000000-0000-4000-8000-000000000001',
            'caja_entradas_id': 'b0000000-0000-4000-8000-0000000000c1',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'numero': 1,
            'comprador_nombre': 'COMPRADORA, UNA',
            'renglones': '[]',
            'cantidad': 2,
            'total': 20000.0,
            'medio': 'efectivo',
            'efectivo': 20000.0,
            'created_at': '2026-11-19T15:00:00.000Z',
            'updated_at': '2026-11-19T15:00:00.000Z',
          });
          await db.insert('_sync_meta', {
            'clave': 'last_pull_entradas_retiro',
            'valor': '2026-11-18T15:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'entradas_ventas',
            'operacion': 'insert',
            'registro_id': 'b0000000-0000-4000-8000-000000000001',
            'payload': '{"id":"b0000000-0000-4000-8000-000000000001"}',
            'created_at': '2026-11-19T15:00:00.000Z',
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

  const unRenglon = {
    'id': 'd0000000-0000-4000-8000-000000000001',
    'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000002',
    'evento_id': 'e0000000-0000-4000-8000-000000000001',
    'parte': 'pulseras',
    'accion': 'entrega',
    'cantidad': 3,
    'tramos': '',
    'menores_10': 0,
    'parentesco': 'padre',
    'retiro_nombre': 'PADRE, UNO',
    'autorizacion_firmada': 0,
    'escribio_en_planilla': 1,
    'hecho_por': 'Carla',
    'device_id': 'pc-1',
    'created_at': '2026-11-20T15:00:00.000Z',
    'updated_at': '2026-11-20T15:00:00.000Z',
  };

  test('de 80 a 81: aparece la tabla, vacía, y lo demás queda igual', () async {
    await crearBaseV80();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV81);
    await antes.close();
    for (final t in tablasV81) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(81);
    expect(await db.getVersion(), 81);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV81), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in tablasV81) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, tablasV81), fotoAntes);
  });

  test('pidiendo la 80, la tabla de la v81 no aparece', () async {
    await crearBaseV80();
    final db = await abrirEnVersion(80);
    await LocalDatabase.onUpgradeParaTest(db, 79, 80);
    final f = await foto(db);
    for (final t in tablasV81) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('no tiene un índice único fuera del id', () async {
    await crearBaseV80();
    final db = await abrirEnVersion(81);
    for (final t in tablasV81) {
      final columnas = await db.rawQuery('PRAGMA table_info($t)');
      expect(columnas, isNotEmpty, reason: t);
      for (final i in await db.rawQuery('PRAGMA index_list($t)')) {
        if (i['origin'] == 'pk') continue;
        expect(i['unique'], 0, reason: 'índice único ${i['name']} en $t');
      }
    }
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV80();
    final db = await abrirEnVersion(81);
    await db.insert('entradas_entregas', unRenglon);
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV81(db);
    await LocalDatabase.onUpgradeParaTest(db, 80, 81);
    await LocalDatabase.onUpgradeParaTest(db, 71, 81);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('una base nueva la trae desde el principio', () async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 81,
        onCreate: LocalDatabase.onCreateParaTest,
      ),
    );
    final columnas = await db.rawQuery('PRAGMA table_info(entradas_entregas)');
    expect(columnas, isNotEmpty);
    await db.close();
  });

  test('el código de la v81 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV81(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 81 && newVersion >= 81) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV81', crear), ('el bloque de la v81', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    for (final t in tablasV81) {
      expect(crear, contains('CREATE TABLE IF NOT EXISTS $t ('), reason: t);
    }
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    // La entrega en dos partes es una tabla aparte: no nombra ninguna de las que
    // ya existen (ni la fila de `entradas_retiro`, ni la plata).
    final soloCodigo =
        crear.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final ajena in [
      'contratos_alumnos',
      'pagos_contrato_alumno',
      'sesiones_caja',
      'entradas_retiro',
      'entradas_ventas',
      'barra_',
    ]) {
      expect(soloCodigo, isNot(contains(ajena)), reason: ajena);
    }
    // Se crea al abrir, en una base nueva y al migrar.
    expect('await crearTablasV81(db);'.allMatches(fuente), hasLength(3));
  });

  test('si se reinstala la 6.9.2 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV80();
    var db = await abrirEnVersion(81);
    await db.insert('entradas_entregas', unRenglon);
    final fotoV81 = await foto(db);
    await db.close();

    // La 6.9.2 pide la versión 80 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 80));
    expect(await db.getVersion(), 80);
    expect(await foto(db), fotoV81);
    await db.close();

    db = await abrirEnVersion(81);
    expect(await db.getVersion(), 81);
    expect(await foto(db), fotoV81);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('una base en 80 se copia antes de pasar a la 81', () async {
      await crearBaseV80();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v81.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 80);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV80();
      final db = await abrirEnVersion(81);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory), isNull);
    });
  });
}
