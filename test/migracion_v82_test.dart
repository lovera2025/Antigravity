import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/entradas/datos/movimiento_para_rendir.dart';
import 'package:arguello_events/models/entradas_retiro.dart' show TramoTalonario;

/// La migración v82 (las entradas para rendir) tiene que agregar su tabla y
/// **nada más**: ni una fila de lo que ya existe puede cambiar, se tiene que
/// poder correr dos veces, y si alguien reinstala la 6.9.2 la base tiene que
/// seguir abriendo. Mismo modelo que `migracion_v81_test.dart`.
///
/// Las PCs reales están en la 80 (la 6.9.2; la v81 nunca se instaló): al
/// instalar la 6.9.3 saltan de 80 a 82 en un solo arranque, con una sola copia
/// (`antes_de_v82.db`). Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV81 = ['entradas_entregas'];
  const tablasV82 = ['entradas_para_rendir'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v82_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  const unRenglonDeLaEntrega = {
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

  /// Una base en la 80 (o en la 81, con un renglón de la entrega en dos partes)
  /// con la plata, una entrega de las 8 juntas, una venta de entradas, un
  /// marcador de sync y algo en la cola.
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
          if (version >= 81) {
            await LocalDatabase.crearTablasV81(db);
            await db.insert('entradas_entregas', unRenglonDeLaEntrega);
          }
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
          // Una venta de entradas (v80): la de una rendición será una más.
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
            'clave': 'last_pull_entradas_ventas',
            'valor': '2026-11-19T15:00:00.000Z',
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

  /// Un bloque dado, como lo arma la app.
  Map<String, dynamic> unBloque() => MovimientoParaRendir.dio(
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        personaNombre: 'Juan Pérez',
        personaContacto: '3794000000',
        cantidad: 20,
        tramos: const [TramoTalonario(1201, 1220)],
        precio: 8000,
        nombrePrecio: 'Entrada anticipada',
        hechoPor: 'Jefe',
        deviceId: 'pc-1',
        ahora: DateTime.utc(2026, 11, 20, 15),
      ).toMap();

  test('de 80 a 82: aparecen las dos tablas, vacías, y lo demás queda igual',
      () async {
    // Lo de las PCs de verdad: la v81 nunca se instaló.
    await crearBase(80);
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, [...tablasV81, ...tablasV82]);
    await antes.close();
    for (final t in [...tablasV81, ...tablasV82]) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(82);
    expect(await db.getVersion(), 82);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, [...tablasV81, ...tablasV82]), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in [...tablasV81, ...tablasV82]) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, [...tablasV81, ...tablasV82]), fotoAntes);
  });

  test('de 81 a 82: aparece solo la de la v82, y la entrega en dos partes queda igual',
      () async {
    await crearBase(81);
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV82);
    await antes.close();
    expect(fotoAntes['entradas_entregas'], isNot('[]'));
    expect(fotoAntes.containsKey('entradas_para_rendir'), isFalse);

    final db = await abrirEnVersion(82);
    expect(await db.getVersion(), 82);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV82), esquemaAntes);
    await db.close();

    expect(fotoDespues['entradas_para_rendir'], '[]');
    expect(sin(fotoDespues, tablasV82), fotoAntes);
  });

  test('pidiendo la 81, la tabla de la v82 no aparece', () async {
    await crearBase(80);
    final db = await abrirEnVersion(81);
    await LocalDatabase.onUpgradeParaTest(db, 80, 81);
    final f = await foto(db);
    expect(f.containsKey('entradas_entregas'), isTrue);
    for (final t in tablasV82) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('tiene sus cuatro índices, y ninguno es único fuera del id', () async {
    await crearBase(80);
    final db = await abrirEnVersion(82);
    for (final t in tablasV82) {
      final columnas = await db.rawQuery('PRAGMA table_info($t)');
      expect(columnas, isNotEmpty, reason: t);
      final indices = await db.rawQuery('PRAGMA index_list($t)');
      for (final i in indices) {
        if (i['origin'] == 'pk') continue;
        expect(i['unique'], 0, reason: 'índice único ${i['name']} en $t');
      }
      final porColumna = <String>{};
      for (final i in indices) {
        if (i['origin'] == 'pk') continue;
        for (final c in await db.rawQuery('PRAGMA index_info(${i['name']})')) {
          porColumna.add('${c['name']}');
        }
      }
      expect(porColumna, {'evento_id', 'bloque_id', 'venta_id', 'updated_at'});
    }
    await db.close();
  });

  test('las columnas de la base son las del modelo', () async {
    await crearBase(80);
    final db = await abrirEnVersion(82);
    final columnas = {
      for (final c in await db.rawQuery('PRAGMA table_info(entradas_para_rendir)'))
        '${c['name']}',
    };
    expect(columnas, unBloque().keys.toSet());
    // Y lo que arma la app entra y vuelve igual.
    await db.insert('entradas_para_rendir', unBloque());
    final leido = MovimientoParaRendir.fromMap(
      (await db.query('entradas_para_rendir')).single,
    );
    expect(leido.esDio, isTrue);
    expect(leido.cantidad, 20);
    expect(leido.precio, 8000);
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBase(80);
    final db = await abrirEnVersion(82);
    await db.insert('entradas_entregas', unRenglonDeLaEntrega);
    await db.insert('entradas_para_rendir', unBloque());
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV82(db);
    await LocalDatabase.onUpgradeParaTest(db, 81, 82);
    await LocalDatabase.onUpgradeParaTest(db, 80, 82);
    await LocalDatabase.onUpgradeParaTest(db, 71, 82);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('una base nueva la trae desde el principio', () async {
    final db = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 82,
        onCreate: LocalDatabase.onCreateParaTest,
      ),
    );
    for (final t in [...tablasV81, ...tablasV82]) {
      expect(await db.rawQuery('PRAGMA table_info($t)'), isNotEmpty, reason: t);
    }
    await db.close();
  });

  test('el código de la v82 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV82(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 82 && newVersion >= 82) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV82', crear), ('el bloque de la v82', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    for (final t in tablasV82) {
      expect(crear, contains('CREATE TABLE IF NOT EXISTS $t ('), reason: t);
    }
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    expect(crear, isNot(contains('REFERENCES')), reason: 'sin claves foráneas');
    expect(crear, isNot(contains('CHECK')), reason: 'sin CHECK');
    // Las entradas para rendir son una tabla aparte: no nombra ninguna de las
    // que ya existen (la venta de la rendición es una venta común, que escribe
    // el repositorio, no la migración).
    final soloCodigo =
        crear.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final ajena in [
      'contratos_alumnos',
      'pagos_contrato_alumno',
      'sesiones_caja',
      'entradas_retiro',
      'entradas_ventas',
      'entradas_entregas',
      'entradas_config',
      'barra_',
    ]) {
      expect(soloCodigo, isNot(contains(ajena)), reason: ajena);
    }
    // Se crea al abrir, en una base nueva y al migrar.
    expect('await crearTablasV82(db);'.allMatches(fuente), hasLength(3));
    // Y la app va por la 82.
    expect(fuente, contains('static const int _version = 82;'));
  });

  test('si se reinstala la 6.9.2 la base abre, y al volver a la nueva también',
      () async {
    await crearBase(80);
    var db = await abrirEnVersion(82);
    await db.insert('entradas_para_rendir', unBloque());
    final fotoV82 = await foto(db);
    await db.close();

    // La 6.9.2 pide la versión 80 y no tiene onDowngrade: la tabla queda sin
    // leer, y al volver a la 6.9.3 reaparece todo.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 80));
    expect(await db.getVersion(), 80);
    expect(await foto(db), fotoV82);
    await db.close();

    db = await abrirEnVersion(82);
    expect(await db.getVersion(), 82);
    expect(await foto(db), fotoV82);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('una base en 80 se copia una sola vez, como antes_de_v82', () async {
      await crearBase(80);
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      // Sin versión fija: la de la app.
      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v82.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 80);
      await abierta.close();
      // Ni una copia de la 81 de paso.
      expect(File('${copia.parent.path}${Platform.pathSeparator}antes_de_v81.db').existsSync(),
          isFalse);
    });

    test('una base en 81 también se copia', () async {
      await crearBase(81);
      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v82.db'));
    });

    test('una base ya migrada no se copia', () async {
      await crearBase(80);
      final db = await abrirEnVersion(82);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory), isNull);
    });
  });
}
