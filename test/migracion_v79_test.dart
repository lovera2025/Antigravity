import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v79 (el cierre de la barra con el OK de la encargada) tiene que
/// agregar su tabla y **nada más**: ni una fila de lo que ya existe puede cambiar,
/// se tiene que poder correr dos veces, y si alguien reinstala la 6.5.1 la base
/// tiene que seguir abriendo. Mismo modelo que `migracion_v78_test.dart`.
///
/// Las PCs reales están en la 78 (la 6.5.1): al instalar saltan de 78 a 79.
/// Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV79 = ['barra_cierres'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v79_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base en la 78 con la plata, una caja de barra abierta con su venta, un
  /// vale, un marcador de sync y algo en la cola.
  Future<void> crearBaseV78() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 78,
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
          // Una caja de barra abierta, a medio vender: lo que la v79 no puede tocar.
          await db.insert('barra_cajas', {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'operador_nombre': 'Marta',
            'numero_caja': 2,
            'cambio_inicial': 20000.0,
            'abierta_at': '2026-11-10T01:00:00.000Z',
            'created_at': '2026-11-10T01:00:00.000Z',
            'updated_at': '2026-11-10T01:00:00.000Z',
          });
          await db.insert('barra_recargos', {
            'id': 'f0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'recargo_pct': 5.0,
            'created_at': '2026-11-09T00:00:00.000Z',
            'updated_at': '2026-11-09T00:00:00.000Z',
          });
          await db.insert('_sync_meta', {
            'clave': 'last_pull_barra_cajas',
            'valor': '2026-11-10T03:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'barra_cajas',
            'operacion': 'insert',
            'registro_id': 'a0000000-0000-4000-8000-000000000001',
            'payload': '{"id":"a0000000-0000-4000-8000-000000000001"}',
            'created_at': '2026-11-10T01:00:00.000Z',
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

  const unPedido = {
    'id': 'd0000000-0000-4000-8000-000000000001',
    'caja_barra_id': 'a0000000-0000-4000-8000-000000000001',
    'evento_id': 'e0000000-0000-4000-8000-000000000001',
    'tipo': 'pedido',
    'efectivo_contado': 27000.0,
    'hecho_por': 'Marta',
    'created_at': '2026-11-10T08:00:00.000Z',
    'updated_at': '2026-11-10T08:00:00.000Z',
  };

  test('de 78 a 79: aparece barra_cierres, vacía, y lo demás queda igual', () async {
    await crearBaseV78();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV79);
    await antes.close();
    for (final t in tablasV79) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(79);
    expect(await db.getVersion(), 79);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV79), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in tablasV79) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, tablasV79), fotoAntes);
  });

  test('pidiendo la 78, la tabla de la v79 no aparece', () async {
    await crearBaseV78();
    final db = await abrirEnVersion(78);
    await LocalDatabase.onUpgradeParaTest(db, 77, 78);
    final f = await foto(db);
    for (final t in tablasV79) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('la tabla tiene las columnas que usa el sync, sin únicos fuera del id',
      () async {
    await crearBaseV78();
    final db = await abrirEnVersion(79);
    final columnas = {
      for (final c in await db.rawQuery('PRAGMA table_info(barra_cierres)'))
        c['name'] as String,
    };
    expect(columnas, {
      'id', 'caja_barra_id', 'evento_id', 'tipo', 'pedido_id', 'efectivo_contado',
      'nota', 'hecho_por', 'device_id', 'created_at', 'updated_at',
    });
    for (final i in await db.rawQuery('PRAGMA index_list(barra_cierres)')) {
      if (i['origin'] == 'pk') continue;
      expect(i['unique'], 0, reason: 'índice único ${i['name']}');
    }
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV78();
    final db = await abrirEnVersion(79);
    await db.insert('barra_cierres', unPedido);
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV79(db);
    await LocalDatabase.onUpgradeParaTest(db, 78, 79);
    await LocalDatabase.onUpgradeParaTest(db, 71, 79);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v79 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV79(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 79 && newVersion >= 79) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV79', crear), ('el bloque de la v79', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    expect(crear, contains('CREATE TABLE IF NOT EXISTS barra_cierres ('));
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    // No toca la caja: el cierre de verdad lo sigue escribiendo su equipo.
    expect(crear, isNot(contains('barra_cajas')));
    expect(fuente, contains('await crearTablasV79(db);'));
  });

  test('si se reinstala la 6.5.1 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV78();
    var db = await abrirEnVersion(79);
    await db.insert('barra_cierres', unPedido);
    final fotoV79 = await foto(db);
    await db.close();

    // La 6.5.1 pide la versión 78 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 78));
    expect(await db.getVersion(), 78);
    expect(await foto(db), fotoV79);
    await db.close();

    db = await abrirEnVersion(79);
    expect(await db.getVersion(), 79);
    expect(await foto(db), fotoV79);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('una base en 78 se copia antes de pasar a la 79', () async {
      await crearBaseV78();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v79.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 78);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV78();
      final db = await abrirEnVersion(79);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory), isNull);
    });
  });
}
