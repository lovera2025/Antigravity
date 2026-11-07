import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v78 (las sillas de la noche y los vales de la barra) tiene que
/// agregar sus tablas y **nada más**: ni una fila de lo que ya existe puede cambiar, se tiene que poder
/// correr dos veces, y si alguien reinstala la 6.3.1 la base tiene que seguir
/// abriendo. Mismo modelo que `migracion_v77_test.dart`.
///
/// Las PCs reales están en la 77 (la 6.3.1): al instalar saltan de 77 a 78.
/// Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV78 = ['sillas_puerta', 'barra_vales', 'barra_recargos'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v78_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base en la 77 con la plata, un reparto de sillas, una venta de la
  /// barra y un marcador de sync.
  Future<void> crearBaseV77() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 77,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              sillas_extra_cantidad INTEGER DEFAULT 0, updated_at TEXT)
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
          for (var i = 0; i < 30; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'sillas_extra_cantidad': i % 3,
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
          await db.insert('sillas_reparto', {
            'id': 'r0000000-0000-4000-8000-000000000001',
            'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000002',
            'sillas_principal': 1,
            'sillas_extra': 2,
            'mesas': 2,
            'created_at': '2026-11-01T00:00:00.000Z',
            'updated_at': '2026-11-01T00:00:00.000Z',
          });
          await db.insert('barra_productos', {
            'id': 'b0000000-0000-4000-8000-000000000001',
            'nombre': 'Silla extra',
            'activo': 1,
            'orden': 0,
            'created_at': '2026-11-03T00:00:00.000Z',
            'updated_at': '2026-11-03T00:00:00.000Z',
          });
          await db.insert('_sync_meta', {
            'clave': 'last_pull_contratos_alumnos',
            'valor': '2026-11-04T21:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'pagos_contrato_alumno',
            'operacion': 'insert',
            'registro_id': 'p0000000-0000-4000-8000-000000000003',
            'payload': '{"id":"p0000000-0000-4000-8000-000000000003"}',
            'created_at': '2026-11-04T21:00:00.000Z',
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

  test('de 77 a 78: aparecen las sillas de la noche y los vales, y lo demás igual',
      () async {
    await crearBaseV77();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV78);
    await antes.close();
    for (final t in tablasV78) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(78);
    expect(await db.getVersion(), 78);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV78), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in tablasV78) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, tablasV78), fotoAntes);
  });

  test('pidiendo la 77, las tablas de la v78 no aparecen', () async {
    await crearBaseV77();
    final db = await abrirEnVersion(77);
    await LocalDatabase.onUpgradeParaTest(db, 76, 77);
    final f = await foto(db);
    for (final t in tablasV78) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('las tablas tienen las columnas que usa el sync, sin únicos fuera del id',
      () async {
    await crearBaseV77();
    final db = await abrirEnVersion(78);
    Future<Set<String>> columnas(String tabla) async => {
          for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
            c['name'] as String,
        };
    expect(await columnas('sillas_puerta'), {
      'id', 'evento_id', 'contrato_alumno_id', 'mesa', 'cantidad', 'vale',
      'anotado_por', 'nota', 'quitada_at', 'quitada_por', 'quitada_motivo',
      'created_at', 'updated_at',
    });
    expect(await columnas('barra_vales'), {
      'id', 'venta_id', 'caja_barra_id', 'evento_id', 'numero_vale', 'bebidas',
      'por_separado', 'copia_numero', 'motivo', 'hecho_por', 'device_id',
      'created_at', 'updated_at',
    });
    expect(await columnas('barra_recargos'), {
      'id', 'evento_id', 'recargo_pct', 'hecho_por', 'device_id', 'created_at',
      'updated_at',
    });
    for (final t in tablasV78) {
      for (final i in await db.rawQuery('PRAGMA index_list($t)')) {
        if (i['origin'] == 'pk') continue;
        expect(i['unique'], 0, reason: 'índice único ${i['name']}');
      }
    }
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV77();
    final db = await abrirEnVersion(78);
    await db.insert('sillas_puerta', {
      'id': 's0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000002',
      'mesa': 12,
      'vale': '0012',
      'created_at': '2026-12-01T23:05:00.000Z',
      'updated_at': '2026-12-01T23:05:00.000Z',
    });
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV78(db);
    await LocalDatabase.onUpgradeParaTest(db, 77, 78);
    await LocalDatabase.onUpgradeParaTest(db, 71, 78);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v78 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV78(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 78 && newVersion >= 78) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV78', crear), ('el bloque de la v78', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    expect(crear, contains('CREATE TABLE IF NOT EXISTS sillas_puerta ('));
    expect(crear, contains('CREATE TABLE IF NOT EXISTS barra_vales ('));
    expect(crear, contains('CREATE TABLE IF NOT EXISTS barra_recargos ('));
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    expect(fuente, contains('await crearTablasV78(db);'));
  });

  test('si se reinstala la 6.3.1 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV77();
    var db = await abrirEnVersion(78);
    await db.insert('sillas_puerta', {
      'id': 's0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000002',
      'mesa': 12,
      'vale': '0012',
      'created_at': '2026-12-01T23:05:00.000Z',
      'updated_at': '2026-12-01T23:05:00.000Z',
    });
    final fotoV78 = await foto(db);
    await db.close();

    // La 6.3.1 pide la versión 77 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 77));
    expect(await db.getVersion(), 77);
    expect(await foto(db), fotoV78);
    await db.close();

    db = await abrirEnVersion(78);
    expect(await db.getVersion(), 78);
    expect(await foto(db), fotoV78);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('una base en 77 se copia antes de pasar a la 78', () async {
      await crearBaseV77();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v78.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 77);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV77();
      final db = await abrirEnVersion(78);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory), isNull);
    });
  });
}
