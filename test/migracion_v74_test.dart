import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v74 (6.1.0) tiene que agregar su tabla y **nada más**: ni una
/// fila de lo que ya existe puede cambiar, se tiene que poder correr dos veces,
/// y si alguien reinstala la 6.0.0 la base tiene que seguir abriendo.
///
/// Las PCs reales están en la 73 (la 6.0.0): al instalar saltan de 73 a 74.
///
/// Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV73 = ['planos_evento', 'mesas_movimientos'];
  const tablasV74 = ['predios'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v74_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base "v73" (la 6.0.0) con las tablas de la plata, el evento, un plano
  /// y un marcador de sync, con datos.
  Future<void> crearBaseV73() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 73,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE eventos (
              id TEXT PRIMARY KEY, cliente_id TEXT, estado TEXT, updated_at TEXT)
          ''');
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              numero_mesa TEXT, mora_tracked_ajuste REAL DEFAULT 0,
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

          await db.insert('eventos', {
            'id': 'e0000000-0000-4000-8000-000000000001',
            'cliente_id': 'k0000000-0000-4000-8000-000000000001',
            'estado': 'planificacion',
            'updated_at': '2026-10-15T10:00:00.000Z',
          });
          for (var i = 0; i < 40; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'numero_mesa': i.isEven ? '${i + 1}, ${i + 2}' : null,
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
          await db.insert('planos_evento', {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'armado': 'vacio@1',
            'armado_json': '{"clave":"vacio@1"}',
            'estilo': 'gala',
            'modo_sorteo': 'bloques',
            'config': '{}',
            'created_at': '2026-10-16T00:00:00.000Z',
            'updated_at': '2026-10-16T00:00:00.000Z',
          });
          await db.insert('_sync_meta', {
            'clave': 'last_pull_contratos_alumnos',
            'valor': '2026-10-18T21:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'pagos_contrato_alumno',
            'operacion': 'insert',
            'registro_id': 'p0000000-0000-4000-8000-000000000003',
            'payload': '{"id":"p0000000-0000-4000-8000-000000000003"}',
            'created_at': '2026-10-18T21:00:00.000Z',
          });
        },
      ),
    );
    await db.close();
  }

  /// Todas las filas de todas las tablas, ordenadas: si cambia un solo valor,
  /// cambia la foto.
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

  /// El esquema de todo lo que no es de la tabla nueva: tablas, índices y
  /// triggers, con su SQL.
  Future<List<String>> esquemaDeLoDeSiempre(Database db) async {
    final filas = await db.rawQuery(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    return [
      for (final f in filas)
        if (!tablasV74.contains(f['tbl_name']))
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

  test('de 73 a 74 (el salto real): aparece la tabla y lo demás igual',
      () async {
    await crearBaseV73();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaDeLoDeSiempre(antes);
    await antes.close();
    expect(fotoAntes.containsKey('predios'), isFalse);

    final db = await abrirEnVersion(74);
    expect(await db.getVersion(), 74);
    final fotoDespues = await foto(db);
    expect(
      await esquemaDeLoDeSiempre(db),
      esquemaAntes,
      reason: 'la migración no toca el esquema de lo que ya existía',
    );
    await db.close();

    expect(fotoDespues['predios'], '[]', reason: 'predios nace vacía');
    expect(sin(fotoDespues, tablasV74), fotoAntes);
  });

  test('pidiendo la 73, la tabla de la v74 no aparece', () async {
    await crearBaseV73();
    final db = await abrirEnVersion(73);
    await LocalDatabase.onUpgradeParaTest(db, 72, 73);
    expect((await foto(db)).containsKey('predios'), isFalse);
    await db.close();
  });

  test('la tabla nueva tiene las columnas que usa el sync', () async {
    await crearBaseV73();
    final db = await abrirEnVersion(74);
    expect(
      {
        for (final c in await db.rawQuery('PRAGMA table_info(predios)'))
          c['name'] as String,
      },
      {
        'id', 'nombre', 'armado_json', 'medidas', 'borrado_at', 'hecho_por',
        'created_at', 'updated_at',
      },
    );
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV73();
    final db = await abrirEnVersion(74);
    await db.insert('predios', {
      'id': 'd0000000-0000-4000-8000-000000000001',
      'nombre': 'Buena Vista',
      'armado_json': '{}',
      'medidas': '{}',
      'created_at': '2026-10-20T00:00:00.000Z',
      'updated_at': '2026-10-20T00:00:00.000Z',
    });
    final fotoAntes = await foto(db);
    expect(fotoAntes['predios'], isNot('[]'));
    await LocalDatabase.crearTablasV74(db);
    await LocalDatabase.onUpgradeParaTest(db, 73, 74);
    await LocalDatabase.onUpgradeParaTest(db, 71, 74);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v74 solo crea: ni ALTER, ni DROP, ni escribe filas',
      () {
    // La migración traga sus errores para no trabar la caja, así que se mira
    // también el texto: lo que corre al pasar a la 74.
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
      'static Future<void> crearTablasV74(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo(
      'if (oldVersion < 74 && newVersion >= 74) {',
      '\n    }\n',
    );
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [
      ('crearTablasV74', crear),
      ('el bloque de la v74', bloque),
    ]) {
      final codigo = texto
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    expect(crear, contains('CREATE TABLE IF NOT EXISTS predios'));
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    // La base nueva y el arranque también la crean.
    expect(fuente, contains('await crearTablasV74(db);'));
  });

  test('si se reinstala la 6.0.0 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV73();
    var db = await abrirEnVersion(74);
    // Con la versión nueva ya se usó: hay un predio, uno borrado, y uno espera
    // subir. Nada de eso puede perderse ni molestar a la 6.0.0.
    for (final (i, borrado) in [(1, null), (2, '2026-10-21T00:00:00.000Z')]) {
      await db.insert('predios', {
        'id': 'd0000000-0000-4000-8000-00000000000$i',
        'nombre': 'Predio $i',
        'armado_json': '{"clave":"predio@d0000000-0000-4000-8000-00000000000$i"}',
        'medidas': '{"playon":{"frente":30,"fondo":46,"profundidad":39}}',
        'borrado_at': borrado,
        'created_at': '2026-10-20T00:00:00.000Z',
        'updated_at': '2026-10-20T00:00:00.000Z',
      });
    }
    await db.insert('_sync_queue', {
      'tabla': 'predios',
      'operacion': 'insert',
      'registro_id': 'd0000000-0000-4000-8000-000000000001',
      'payload': '{}',
      'created_at': '2026-10-20T00:00:00.000Z',
    });
    final fotoV74 = await foto(db);
    await db.close();

    // La 6.0.0 pide la versión 73 y no tiene onDowngrade.
    db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 73),
    );
    expect(await db.getVersion(), 73);
    expect(await foto(db), fotoV74);
    await db.close();

    db = await abrirEnVersion(74);
    expect(await db.getVersion(), 74);
    expect(await foto(db), fotoV74);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('queda una copia completa de la base, en su versión de antes',
        () async {
      await crearBaseV73();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(
        path,
        factory: factory,
        versionNueva: 74,
      );
      expect(copia, isNotNull);
      expect(
        copia!.path,
        endsWith('${Platform.pathSeparator}backups'
            '${Platform.pathSeparator}antes_de_v74.db'),
      );
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 73);
      await abierta.close();
    });

    // Con la versión fija: desde la 6.2.1 la app va por la 75 (lo de la versión
    // de la app lo prueba `migracion_v75_test.dart`).
    test('una base en 73, yendo a la 74, se copia', () async {
      await crearBaseV73();
      final copia = await LocalDatabase.copiaAntesDeMigrar(
        path,
        factory: factory,
        versionNueva: 74,
      );
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v74.db'));
    });

    test('una base ya en la 74 no se copia para ir a la 74', () async {
      await crearBaseV73();
      final db = await abrirEnVersion(74);
      await db.close();
      expect(
        await LocalDatabase.copiaAntesDeMigrar(
          path,
          factory: factory,
          versionNueva: 74,
        ),
        isNull,
      );
    });
  });

  test('las tablas de la v73 no cambian con la v74', () async {
    await crearBaseV73();
    var db = await factory.openDatabase(path);
    final antes = await foto(db);
    await db.close();
    db = await abrirEnVersion(74);
    final despues = await foto(db);
    await db.close();
    for (final t in tablasV73) {
      expect(despues[t], antes[t], reason: t);
    }
  });
}
