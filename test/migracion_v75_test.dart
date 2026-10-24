import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v75 (6.2.1, la mora congelada) tiene que agregar su tabla y
/// **nada más**: ni una fila de lo que ya existe puede cambiar, se tiene que
/// poder correr dos veces, y si alguien reinstala la 6.2.0 la base tiene que
/// seguir abriendo. Mismo modelo que `migracion_v74_test.dart`.
///
/// Las PCs reales están en la 74 (la 6.1.0 a la 6.2.0): al instalar saltan de
/// 74 a 75. Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV75 = ['mora_congelada'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v75_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base "v74" con las tablas de la plata, un predio y un marcador de sync.
  Future<void> crearBaseV74() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 74,
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
          await db.insert('predios', {
            'id': 'd0000000-0000-4000-8000-000000000001',
            'nombre': 'Buena Vista',
            'armado_json': '{}',
            'medidas': '{}',
            'created_at': '2026-10-20T00:00:00.000Z',
            'updated_at': '2026-10-20T00:00:00.000Z',
          });
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

  Future<List<String>> esquemaDeLoDeSiempre(Database db) async {
    final filas = await db.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    return [
      for (final f in filas)
        if (!tablasV75.contains(f['tbl_name']))
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

  test('de 74 a 75 (el salto real): aparece la tabla y lo demás igual', () async {
    await crearBaseV74();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaDeLoDeSiempre(antes);
    await antes.close();
    expect(fotoAntes.containsKey('mora_congelada'), isFalse);

    final db = await abrirEnVersion(75);
    expect(await db.getVersion(), 75);
    final fotoDespues = await foto(db);
    expect(await esquemaDeLoDeSiempre(db), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    expect(fotoDespues['mora_congelada'], '[]', reason: 'nace vacía');
    expect(sin(fotoDespues, tablasV75), fotoAntes);
  });

  test('pidiendo la 74, la tabla de la v75 no aparece', () async {
    await crearBaseV74();
    final db = await abrirEnVersion(74);
    await LocalDatabase.onUpgradeParaTest(db, 73, 74);
    expect((await foto(db)).containsKey('mora_congelada'), isFalse);
    await db.close();
  });

  test('la tabla nueva tiene las columnas que usa el sync', () async {
    await crearBaseV74();
    final db = await abrirEnVersion(75);
    expect(
      {
        for (final c in await db.rawQuery('PRAGMA table_info(mora_congelada)'))
          c['name'] as String,
      },
      {'id', 'contrato_alumno_id', 'evento_id', 'pausas', 'created_at', 'updated_at'},
    );
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV74();
    final db = await abrirEnVersion(75);
    await db.insert('mora_congelada', {
      'id': 'f0000000-0000-4000-8000-000000000001',
      'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
      'pausas': '[{"cuota":null,"desde":"2026-10-23"}]',
      'created_at': '2026-10-23T00:00:00.000Z',
      'updated_at': '2026-10-23T00:00:00.000Z',
    });
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV75(db);
    await LocalDatabase.onUpgradeParaTest(db, 74, 75);
    await LocalDatabase.onUpgradeParaTest(db, 71, 75);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v75 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV75(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 75 && newVersion >= 75) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV75', crear), ('el bloque de la v75', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    expect(crear, contains('CREATE TABLE IF NOT EXISTS mora_congelada'));
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(fuente, contains('await crearTablasV75(db);'));
  });

  test('si se reinstala la 6.2.0 la base abre, y al volver a la nueva también', () async {
    await crearBaseV74();
    var db = await abrirEnVersion(75);
    await db.insert('mora_congelada', {
      'id': 'f0000000-0000-4000-8000-000000000001',
      'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
      'pausas': '[{"cuota":4,"desde":"2026-10-23"}]',
      'created_at': '2026-10-23T00:00:00.000Z',
      'updated_at': '2026-10-23T00:00:00.000Z',
    });
    await db.insert('_sync_queue', {
      'tabla': 'mora_congelada',
      'operacion': 'insert',
      'registro_id': 'f0000000-0000-4000-8000-000000000001',
      'payload': '{}',
      'created_at': '2026-10-23T00:00:00.000Z',
    });
    final fotoV75 = await foto(db);
    await db.close();

    // La 6.2.0 pide la versión 74 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 74));
    expect(await db.getVersion(), 74);
    expect(await foto(db), fotoV75);
    await db.close();

    db = await abrirEnVersion(75);
    expect(await db.getVersion(), 75);
    expect(await foto(db), fotoV75);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('la copia usa la versión de la app: una base en 74 se copia', () async {
      await crearBaseV74();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v75.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 74);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV74();
      final db = await abrirEnVersion(75);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory), isNull);
    });
  });
}
