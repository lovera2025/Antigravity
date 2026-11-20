import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v80 (la venta de entradas) tiene que agregar sus cinco tablas y
/// **nada más**: ni una fila de lo que ya existe puede cambiar, se tiene que
/// poder correr dos veces, y si alguien reinstala la 6.8.0 la base tiene que
/// seguir abriendo. Mismo modelo que `migracion_v79_test.dart`.
///
/// Las PCs reales están en la 79 (de la 6.6.0 a la 6.8.0): al instalar saltan de
/// 79 a 80. Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV80 = [
    'entradas_config',
    'entradas_cajas',
    'entradas_ventas',
    'entradas_anulaciones',
    'entradas_verificaciones',
  ];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v80_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base en la 79 con la plata, una entrega de entradas, una caja de barra
  /// abierta con su pedido de cierre, un marcador de sync y algo en la cola.
  Future<void> crearBaseV79() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 79,
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
          // Una caja de barra abierta, a medio vender: lo que la v80 no puede tocar.
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
          // Un pedido de cierre de esa caja (v79) y una entrega de entradas (v72):
          // la venta de entradas no las toca.
          await db.insert('barra_cierres', {
            'id': 'd0000000-0000-4000-8000-000000000009',
            'caja_barra_id': 'a0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'tipo': 'pedido',
            'efectivo_contado': 27000.0,
            'created_at': '2026-11-10T08:00:00.000Z',
            'updated_at': '2026-11-10T08:00:00.000Z',
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

  const unaVenta = {
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
    'hecho_por': 'F1',
    'created_at': '2026-11-20T15:00:00.000Z',
    'updated_at': '2026-11-20T15:00:00.000Z',
  };

  test('de 79 a 80: aparecen las cinco tablas, vacías, y lo demás queda igual', () async {
    await crearBaseV79();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV80);
    await antes.close();
    for (final t in tablasV80) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(80);
    expect(await db.getVersion(), 80);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV80), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in tablasV80) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, tablasV80), fotoAntes);
  });

  test('pidiendo la 79, las tablas de la v80 no aparecen', () async {
    await crearBaseV79();
    final db = await abrirEnVersion(79);
    await LocalDatabase.onUpgradeParaTest(db, 78, 79);
    final f = await foto(db);
    for (final t in tablasV80) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
    await db.close();
  });

  test('ninguna tiene un índice único fuera del id', () async {
    await crearBaseV79();
    final db = await abrirEnVersion(80);
    for (final t in tablasV80) {
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
    await crearBaseV79();
    final db = await abrirEnVersion(80);
    await db.insert('entradas_ventas', unaVenta);
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV80(db);
    await LocalDatabase.onUpgradeParaTest(db, 79, 80);
    await LocalDatabase.onUpgradeParaTest(db, 71, 80);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('el código de la v80 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
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
      'static Future<void> crearTablasV80(DatabaseExecutor db) async {',
      '\n  }\n',
    );
    final bloque = tramo('if (oldVersion < 80 && newVersion >= 80) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV80', crear), ('el bloque de la v80', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    for (final t in tablasV80) {
      expect(crear, contains('CREATE TABLE IF NOT EXISTS $t ('), reason: t);
    }
    expect(
      RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear),
      isFalse,
      reason: 'todo lo que crea lleva IF NOT EXISTS',
    );
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    // Una venta de entradas no es un pago de cuota ni toca la entrega: ninguna de
    // esas tablas aparece en el código que crea las de la v80.
    final soloCodigo =
        crear.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final ajena in [
      'contratos_alumnos',
      'pagos_contrato_alumno',
      'sesiones_caja',
      'entradas_retiro',
      'barra_',
    ]) {
      expect(soloCodigo, isNot(contains(ajena)), reason: ajena);
    }
    expect(fuente, contains('await crearTablasV80(db);'));
  });

  test('si se reinstala la 6.8.0 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV79();
    var db = await abrirEnVersion(80);
    await db.insert('entradas_ventas', unaVenta);
    final fotoV80 = await foto(db);
    await db.close();

    // La 6.8.0 pide la versión 79 y no tiene onDowngrade.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 79));
    expect(await db.getVersion(), 79);
    expect(await foto(db), fotoV80);
    await db.close();

    db = await abrirEnVersion(80);
    expect(await db.getVersion(), 80);
    expect(await foto(db), fotoV80);
    await db.close();
  });

  group('la copia antes de migrar', () {
    test('una base en 79 se copia antes de pasar a la 80', () async {
      await crearBaseV79();
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 80);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v80.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 79);
      await abierta.close();
    });

    test('una base ya migrada no se copia', () async {
      await crearBaseV79();
      final db = await abrirEnVersion(80);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 80), isNull);
    });
  });
}
