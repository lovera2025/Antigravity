import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v73 tiene que agregar sus dos tablas y **nada más**: ni una fila
/// de lo que ya existe puede cambiar, se tiene que poder correr dos veces, y si
/// alguien reinstala la 5.0.0 la base tiene que seguir abriendo.
///
/// Las PCs reales están en la 71 (la 5.0.0): al instalar saltan de 71 a 73 en
/// un solo arranque, así que ese es el camino que más importa.
///
/// Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV72 = ['sillas_reparto', 'entradas_retiro', 'sorteos_mesas'];
  const tablasV73 = ['planos_evento', 'mesas_movimientos'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v73_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base "v71" con las tablas de la plata, el evento y un marcador de
  /// sync, con datos.
  Future<void> crearBaseV71() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 71,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE eventos (
              id TEXT PRIMARY KEY, cliente_id TEXT, estado TEXT, updated_at TEXT)
          ''');
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              numero_mesa TEXT, sillas_extra_cantidad INTEGER DEFAULT 0,
              curso_division TEXT, updated_at TEXT)
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

          await db.insert('eventos', {
            'id': 'e0000000-0000-4000-8000-000000000001',
            'cliente_id': 'k0000000-0000-4000-8000-000000000001',
            'estado': 'planificacion',
            'updated_at': '2026-09-20T10:00:00.000Z',
          });
          for (var i = 0; i < 40; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'numero_mesa': i.isEven ? '${i + 1}, ${i + 2}' : null,
              'sillas_extra_cantidad': i % 3,
              'curso_division': i < 20 ? '5° A' : '5° B',
              'updated_at': '2026-09-2${i % 5}T10:00:00.000Z',
            });
            await db.insert('pagos_contrato_alumno', {
              'id': 'p0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'contrato_alumno_id': id,
              'monto': 70000.0 + i,
              'concepto': 'Cuota Base',
              'fecha_pago': '2026-08-1${i % 9}',
            });
          }
          await db.insert('_sync_meta', {
            'clave': 'last_pull_contratos_alumnos',
            'valor': '2026-09-24T21:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'pagos_contrato_alumno',
            'operacion': 'insert',
            'registro_id': 'p0000000-0000-4000-8000-000000000003',
            'payload': '{"id":"p0000000-0000-4000-8000-000000000003"}',
            'created_at': '2026-09-24T21:00:00.000Z',
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

  /// El esquema de todo lo que no es de las tablas nuevas: tablas, índices y
  /// triggers, con su SQL. Un ALTER, un índice o un trigger agregado a algo
  /// que ya existía cambia esta foto aunque no cambie ninguna fila.
  Future<List<String>> esquemaDeLoDeSiempre(Database db) async {
    final nuevas = [...tablasV72, ...tablasV73];
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

  test('de 71 a 73 (el salto real): aparecen las cinco tablas y lo demás igual',
      () async {
    await crearBaseV71();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaDeLoDeSiempre(antes);
    await antes.close();

    final db = await abrirEnVersion(73);
    expect(await db.getVersion(), 73);
    final fotoDespues = await foto(db);
    expect(
      await esquemaDeLoDeSiempre(db),
      esquemaAntes,
      reason: 'la migración no toca el esquema de lo que ya existía',
    );
    await db.close();

    for (final t in [...tablasV72, ...tablasV73]) {
      expect(fotoDespues[t], '[]', reason: '$t tiene que nacer vacía');
    }
    expect(sin(fotoDespues, [...tablasV72, ...tablasV73]), fotoAntes);
  });

  test('de 72 a 73: aparecen las dos tablas y lo de la 72 queda igual',
      () async {
    await crearBaseV71();
    var db = await abrirEnVersion(72);
    await db.insert('sorteos_mesas', {
      'id': 'r0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'tipo': 'sorteo',
      'resultado': '{"c0000000-0000-4000-8000-000000000000":"1, 2"}',
      'alumnos': 1,
      'created_at': '2026-09-25T00:00:00.000Z',
      'updated_at': '2026-09-25T00:00:00.000Z',
    });
    final fotoV72 = await foto(db);
    await db.close();
    for (final t in tablasV73) {
      expect(fotoV72.containsKey(t), isFalse,
          reason: 'pidiendo la 72 no aparece $t');
    }

    db = await abrirEnVersion(73);
    final fotoV73 = await foto(db);
    await db.close();
    for (final t in tablasV73) {
      expect(fotoV73[t], '[]', reason: '$t tiene que nacer vacía');
    }
    expect(sin(fotoV73, tablasV73), fotoV72);
  });

  test('las tablas nuevas tienen las columnas que usa el sync', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(73);
    Future<Set<String>> columnas(String t) async => {
          for (final c in await db.rawQuery('PRAGMA table_info($t)'))
            c['name'] as String,
        };
    expect(await columnas('planos_evento'), {
      'id', 'evento_id', 'armado', 'armado_json', 'estilo', 'modo_sorteo',
      'config', 'hecho_por', 'created_at', 'updated_at',
    });
    expect(await columnas('mesas_movimientos'), {
      'id', 'evento_id', 'tipo', 'antes', 'despues', 'motivo', 'deshace_id',
      'avisos', 'hecho_por', 'created_at', 'updated_at',
    });
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(73);
    await db.insert('planos_evento', {
      'id': 'a0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'armado': 'normal_2a_p3@1',
      'armado_json': '{}',
      'estilo': 'gala',
      'modo_sorteo': 'bloques',
      'config': '{}',
      'created_at': '2026-09-26T00:00:00.000Z',
      'updated_at': '2026-09-26T00:00:00.000Z',
    });
    // También la otra tabla: con una sola con filas, un DROP y CREATE de
    // `mesas_movimientos` pasaría sin que nadie lo note.
    await db.insert('mesas_movimientos', {
      'id': 'b0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'tipo': 'cambio',
      'antes': '{}',
      'despues': '{}',
      'motivo': 'silla de ruedas',
      'created_at': '2026-09-26T00:00:00.000Z',
      'updated_at': '2026-09-26T00:00:00.000Z',
    });
    final fotoAntes = await foto(db);
    expect(fotoAntes['mesas_movimientos'], isNot('[]'));
    await LocalDatabase.crearTablasV73(db);
    await LocalDatabase.onUpgradeParaTest(db, 72, 73);
    await LocalDatabase.onUpgradeParaTest(db, 71, 73);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v73 solo crea: ni ALTER, ni DROP, ni escribe filas',
      () {
    // La migración traga sus errores para no trabar la caja, así que un ALTER
    // sobre una tabla que la base de prueba no tiene pasaría en verde. Por eso
    // se mira también el texto: lo que corre al pasar a la 73.
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
      'static Future<void> crearTablasV73(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo(
      'if (oldVersion < 73 && newVersion >= 73) {',
      '\n    }\n',
    );
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [
      ('crearTablasV73', crear),
      ('el bloque de la v73', bloque),
    ]) {
      // Los comentarios pueden nombrar lo que no se hace.
      final codigo = texto
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    expect(crear, contains('CREATE TABLE IF NOT EXISTS planos_evento'));
    expect(crear, contains('CREATE TABLE IF NOT EXISTS mesas_movimientos'));
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
  });

  test('una fiesta tiene un solo plano', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(73);
    Map<String, Object?> fila(String id) => {
          'id': id,
          'evento_id': 'e0000000-0000-4000-8000-000000000001',
          'armado': 'normal_2a_p3@1',
          'armado_json': '{}',
          'estilo': 'neon',
          'modo_sorteo': 'entera',
          'created_at': '2026-09-26T00:00:00.000Z',
          'updated_at': '2026-09-26T00:00:00.000Z',
        };
    await db.insert('planos_evento', fila('a0000000-0000-4000-8000-000000000001'));
    await expectLater(
      db.insert('planos_evento', fila('a0000000-0000-4000-8000-000000000002')),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.isUniqueConstraintError(),
          'es por el UNIQUE de evento_id',
          isTrue,
        ),
      ),
    );
    expect(
      await db.rawQuery('SELECT id FROM planos_evento'),
      [
        {'id': 'a0000000-0000-4000-8000-000000000001'},
      ],
    );
    await db.close();
  });

  test('si se reinstala la 5.0.0 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV71();
    var db = await abrirEnVersion(73);
    // Con la versión nueva ya se usó: hay un plano, un cambio de mesa y los dos
    // esperan subir. Nada de eso puede perderse ni molestar a la 5.0.0.
    await db.insert('planos_evento', {
      'id': 'a0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'armado': 'normal_2a_p3@1',
      'armado_json': '{}',
      'estilo': 'gala',
      'modo_sorteo': 'bloques',
      'config': '{"bloques":[{"division":"5A","desde":1,"hasta":20}]}',
      'created_at': '2026-10-05T00:00:00.000Z',
      'updated_at': '2026-10-05T00:00:00.000Z',
    });
    await db.insert('mesas_movimientos', {
      'id': 'b0000000-0000-4000-8000-000000000001',
      'evento_id': 'e0000000-0000-4000-8000-000000000001',
      'tipo': 'cambio',
      'antes': '{}',
      'despues': '{}',
      'motivo': 'silla de ruedas',
      'created_at': '2026-10-05T00:00:00.000Z',
      'updated_at': '2026-10-05T00:00:00.000Z',
    });
    for (final t in tablasV73) {
      await db.insert('_sync_queue', {
        'tabla': t,
        'operacion': 'insert',
        'registro_id': 'x',
        'payload': '{}',
        'created_at': '2026-10-05T00:00:00.000Z',
      });
    }
    final fotoV73 = await foto(db);
    await db.close();

    // La 5.0.0 pide la versión 71 y no tiene onDowngrade.
    db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 71),
    );
    expect(await db.getVersion(), 71);
    expect(await foto(db), fotoV73);
    await db.close();

    db = await abrirEnVersion(73);
    expect(await db.getVersion(), 73);
    expect(await foto(db), fotoV73);
    await db.close();
  });

  group('la copia antes de migrar', () {
    Future<File?> copiar({DateTime? ahora}) => LocalDatabase.copiaAntesDeMigrar(
          path,
          factory: factory,
          versionNueva: 73,
          ahora: ahora,
        );

    test('queda una copia completa de la base, en su versión de antes',
        () async {
      await crearBaseV71();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await copiar();
      expect(copia, isNotNull);
      expect(
        copia!.path,
        endsWith('${Platform.pathSeparator}backups'
            '${Platform.pathSeparator}antes_de_v73.db'),
      );
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 71);
      await abierta.close();
      expect(
        File('${copia.path}.tmp').existsSync(),
        isFalse,
        reason: 'el temporal se renombra al terminar',
      );
    });

    test('si se vuelve a la 5.0.0, se cobra y se reinstala, hay copia nueva',
        () async {
      // El camino de vuelta atrás: la copia del primer día no tiene lo que se
      // cobró después. No se pisa ni se da por buena: se saca otra.
      await crearBaseV71();
      final primera = await copiar();

      var db = await abrirEnVersion(73);
      await db.close();
      db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 71),
      );
      await db.insert('pagos_contrato_alumno', {
        'id': 'p0000000-0000-4000-8000-999999999999',
        'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
        'monto': 30000.0,
        'concepto': 'Cuota Base (cobrada después de volver atrás)',
        'fecha_pago': '2026-10-06',
      });
      await db.close();

      final segunda = await copiar(ahora: DateTime(2026, 10, 7, 9, 30));
      expect(segunda, isNotNull);
      expect(segunda!.path, isNot(primera!.path));
      expect(segunda.path, endsWith('antes_de_v73_2026-10-07_0930.db'));

      Future<int> pagos(File f) async {
        final c = await factory.openDatabase(f.path);
        final n = (await c.rawQuery(
          'SELECT COUNT(*) n FROM pagos_contrato_alumno',
        ))
            .first['n'] as int;
        await c.close();
        return n;
      }

      expect(await pagos(primera), 40, reason: 'la primera queda como estaba');
      expect(await pagos(segunda), 41, reason: 'la nueva trae el cobro');
    });

    test('una copia cortada de un arranque anterior no se toma por buena',
        () async {
      await crearBaseV71();
      final backups = Directory('${tmp.path}${Platform.pathSeparator}backups')
        ..createSync();
      final trunca = File(
        '${backups.path}${Platform.pathSeparator}antes_de_v73.db',
      )..writeAsBytesSync(const []);
      // Y un temporal que quedó de un corte de luz.
      File('${backups.path}${Platform.pathSeparator}antes_de_v73.db.tmp')
          .writeAsBytesSync(const [1, 2, 3]);

      final copia = await copiar(ahora: DateTime(2026, 10, 7, 9, 31));
      expect(copia, isNotNull);
      expect(copia!.path, isNot(trunca.path));
      final abierta = await factory.openDatabase(copia.path);
      expect(await abierta.getVersion(), 71);
      expect(
        (await abierta.rawQuery('SELECT COUNT(*) n FROM contratos_alumnos'))
            .first['n'],
        40,
      );
      await abierta.close();
    });

    test('dos arranques en el mismo minuto no sacan dos copias', () async {
      await crearBaseV71();
      await copiar();
      final ahora = DateTime(2026, 10, 7, 9, 32);
      final a = await copiar(ahora: ahora);
      final modificada = a!.lastModifiedSync();
      final b = await copiar(ahora: ahora);
      expect(b!.path, a.path);
      expect(b.lastModifiedSync(), modificada);
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV71();
      final db = await abrirEnVersion(73);
      await db.close();
      expect(await copiar(), isNull);
    });
  });

  test('la copia usa la versión de la app: una base en 72 también se copia',
      () async {
    await crearBaseV71();
    final db = await abrirEnVersion(72);
    await db.close();
    final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
    expect(copia, isNotNull);
    expect(copia!.path, endsWith('antes_de_v73.db'));
  });
}
