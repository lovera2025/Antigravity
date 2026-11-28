import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/barra/datos/costo_barra.dart';
import 'package:arguello_events/features/barra/datos/movimiento_de_caja.dart';
import 'package:arguello_events/features/barra/datos/receta_barra.dart';

/// La migración v84 (el precio de lista, las recetas de los tragos y los retiros y el
/// cambio de la encargada; 26-nov-2026) tiene que agregar sus tres tablas y **nada más**:
/// ni una fila de lo que ya existe puede cambiar, se tiene que poder correr dos veces, y
/// si alguien reinstala la versión anterior la base tiene que seguir abriendo. Mismo
/// modelo que `migracion_v83_test.dart`.
///
/// Las PCs reales están en la 80 o en la 82; la v83 todavía no se publicó: al instalar
/// la versión nueva saltan a la 84 en un solo arranque. Corre sobre una base temporal,
/// nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasV81 = ['entradas_entregas'];
  const tablasV82 = ['entradas_para_rendir'];
  const tablasV83 = ['barra_stock_barras', 'barra_stock_movimientos'];
  const tablasV84 = ['barra_costos', 'barra_recetas', 'barra_caja_movimientos'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v84_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base en la 80 o en la 82, con la plata, la barra de una fiesta (un precio con
  /// stock, una caja y una venta), un marcador de sync y algo en la cola.
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
          await db.execute('CREATE TABLE _sync_meta (clave TEXT PRIMARY KEY, valor TEXT)');
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
          if (version >= 82) {
            await LocalDatabase.crearTablasV81(db);
            await LocalDatabase.crearTablasV82(db);
          }
          if (version >= 83) await LocalDatabase.crearTablasV83(db);
          for (var i = 0; i < 20; i++) {
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
          await db.insert('barra_precios', {
            'id': 'a0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'producto_id': 'f0000000-0000-4000-8000-000000000001',
            'precio': 4000.0,
            'activo': 1,
            'orden': 0,
            'stock_inicial': 240,
            'aviso_stock': 20,
            'created_at': '2026-11-20T15:00:00.000Z',
            'updated_at': '2026-11-20T15:00:00.000Z',
          });
          await db.insert('barra_cajas', {
            'id': 'b0000000-0000-4000-8000-000000000001',
            'evento_id': 'e0000000-0000-4000-8000-000000000001',
            'numero_caja': 1,
            'sede': 'Barra 1',
            'cambio_inicial': 0.0,
            'abierta_at': '2026-11-20T21:00:00.000Z',
            'created_at': '2026-11-20T21:00:00.000Z',
            'updated_at': '2026-11-20T21:00:00.000Z',
          });
          await db.insert('_sync_meta', {
            'clave': 'last_pull_barra_cajas',
            'valor': '2026-11-20T21:00:00.000Z',
          });
          await db.insert('_sync_queue', {
            'tabla': 'barra_cajas',
            'operacion': 'insert',
            'registro_id': 'b0000000-0000-4000-8000-000000000001',
            'payload': '{"id":"b0000000-0000-4000-8000-000000000001"}',
            'created_at': '2026-11-20T21:00:00.000Z',
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
      out[nombre] = jsonEncode(await db.rawQuery('SELECT * FROM $nombre ORDER BY 1'));
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
        if (!nuevas.contains(f['tbl_name'])) '${f['type']}|${f['name']}|${f['sql']}',
    ];
  }

  Future<Database> abrirEnVersion(int version) => factory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: version, onUpgrade: LocalDatabase.onUpgradeParaTest),
      );

  Map<String, String> sin(Map<String, String> f, List<String> tablas) =>
      Map.of(f)..removeWhere((k, _) => tablas.contains(k));

  final ahora = DateTime.utc(2026, 12, 4, 23);
  Map<String, dynamic> unCosto() => CostoBarra.para(
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        productoId: 'f0000000-0000-4000-8000-000000000002',
        precioLista: 11740,
        contenidoCc: 750,
        ahora: ahora,
      ).toMap();
  Map<String, dynamic> unaReceta() => RecetaBarra.para(
        eventoId: 'e0000000-0000-4000-8000-000000000001',
        productoId: 'f0000000-0000-4000-8000-000000000001',
        ingredienteId: 'f0000000-0000-4000-8000-000000000002',
        cantidad: 200,
        unidad: UnidadDeReceta.cc,
        ahora: ahora,
      ).toMap();
  final retiro = MovimientoDeCaja.nuevo(
    eventoId: 'e0000000-0000-4000-8000-000000000001',
    cajaBarraId: 'b0000000-0000-4000-8000-000000000001',
    tipo: TipoMovimientoDeCaja.retiro,
    monto: 200000,
    motivo: 'Mucho efectivo en la caja',
    hechoPor: 'Romi',
    ahora: ahora,
  ).toMap();

  Future<void> guardarLasTres(Database db) async {
    await db.insert('barra_costos', unCosto());
    await db.insert('barra_recetas', unaReceta());
    await db.insert('barra_caja_movimientos', retiro);
  }

  test('de 83 a 84: aparecen las tres tablas, vacías, y lo demás queda igual', () async {
    await crearBase(83);
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final esquemaAntes = await esquemaSin(antes, tablasV84);
    await antes.close();
    for (final t in tablasV84) {
      expect(fotoAntes.containsKey(t), isFalse, reason: t);
    }

    final db = await abrirEnVersion(84);
    expect(await db.getVersion(), 84);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, tablasV84), esquemaAntes,
        reason: 'la migración no toca el esquema de lo que ya existía');
    await db.close();

    for (final t in tablasV84) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, tablasV84), fotoAntes);
  });

  test('de 80 a 84: una PC que no instaló la 6.9.3 pasa por las cuatro de una', () async {
    await crearBase(80);
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    final nuevas = [...tablasV81, ...tablasV82, ...tablasV83, ...tablasV84];
    final esquemaAntes = await esquemaSin(antes, nuevas);
    await antes.close();

    final db = await abrirEnVersion(84);
    expect(await db.getVersion(), 84);
    final fotoDespues = await foto(db);
    expect(await esquemaSin(db, nuevas), esquemaAntes);
    await db.close();

    for (final t in nuevas) {
      expect(fotoDespues[t], '[]', reason: '$t nace vacía');
    }
    expect(sin(fotoDespues, nuevas), fotoAntes);
  });

  test('pidiendo la 83, las tablas de la v84 no aparecen', () async {
    await crearBase(80);
    final db = await abrirEnVersion(83);
    final f = await foto(db);
    await db.close();
    for (final t in tablasV84) {
      expect(f.containsKey(t), isFalse, reason: t);
    }
  });

  test('correrla dos veces no rompe ni borra lo guardado', () async {
    await crearBase(82);
    var db = await abrirEnVersion(84);
    await guardarLasTres(db);
    await LocalDatabase.crearTablasV84(db);
    final f = await foto(db);
    await db.close();
    for (final tabla in tablasV84) {
      expect(jsonDecode(f[tabla]!), hasLength(1), reason: tabla);
    }

    db = await factory.openDatabase(path);
    await LocalDatabase.crearTablasV84(db);
    expect(await foto(db), f);
    await db.close();
  });

  test('lo que guarda la app entra en las tablas y vuelve igual', () async {
    await crearBase(82);
    final db = await abrirEnVersion(84);
    await guardarLasTres(db);
    final c = (await db.query('barra_costos')).single;
    final r = (await db.query('barra_recetas')).single;
    final m = (await db.query('barra_caja_movimientos')).single;
    await db.close();
    expect(CostoBarra.fromMap(c).toMap(), unCosto());
    expect(RecetaBarra.fromMap(r).toMap(), unaReceta());
    expect(MovimientoDeCaja.fromMap(m).toMap(), retiro);
  });

  test('si se reinstala la versión anterior la base abre, y al volver a la nueva también', () async {
    await crearBase(82);
    var db = await abrirEnVersion(84);
    await guardarLasTres(db);
    final fotoV84 = await foto(db);
    await db.close();

    // La 6.9.4 pide la 82 y no tiene onDowngrade: las tablas quedan sin leer.
    db = await factory.openDatabase(path, options: OpenDatabaseOptions(version: 82));
    expect(await db.getVersion(), 82);
    expect(await foto(db), fotoV84);
    await db.close();

    // Al volver a la nueva, la migración corre de nuevo y no pierde nada.
    db = await abrirEnVersion(84);
    expect(await db.getVersion(), 84);
    expect(await foto(db), fotoV84);
    await db.close();
  });

  test('el código de la v84 solo crea: ni ALTER, ni DROP, ni escribe filas', () {
    final fuente = File('lib/core/database/local_database.dart').readAsStringSync().replaceAll('\r\n', '\n');
    String tramo(String desde, String hasta) {
      final i = fuente.indexOf(desde);
      expect(i, greaterThanOrEqualTo(0), reason: 'no encontré "$desde"');
      final f = fuente.indexOf(hasta, i + desde.length);
      expect(f, greaterThan(i), reason: 'no encontré el final de "$desde"');
      return fuente.substring(i, f);
    }

    final crear = tramo('static Future<void> crearTablasV84(DatabaseExecutor db) async {', '\n  }\n');
    final bloque = tramo('if (oldVersion < 84 && newVersion >= 84) {', '\n    }\n');
    final prohibido = RegExp(
      r'\b(ALTER|DROP|UPDATE|DELETE|INSERT|REPLACE)\b'
      r'|\.(delete|update|insert|rawDelete|rawUpdate|rawInsert)\(',
      caseSensitive: false,
    );
    for (final (nombre, texto) in [('crearTablasV84', crear), ('el bloque de la v84', bloque)]) {
      final codigo = texto.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(prohibido.allMatches(codigo), isEmpty, reason: nombre);
    }
    for (final t in tablasV84) {
      expect(crear, contains('CREATE TABLE IF NOT EXISTS $t ('), reason: t);
    }
    expect(RegExp('CREATE (UNIQUE )?(TABLE|INDEX) (?!IF NOT EXISTS)').hasMatch(crear), isFalse,
        reason: 'todo lo que crea lleva IF NOT EXISTS');
    expect(crear, isNot(contains('UNIQUE')), reason: 'sin únicos fuera del id');
    expect(crear, isNot(contains('REFERENCES')), reason: 'sin claves foráneas');
    expect(crear, isNot(contains('CHECK')), reason: 'sin CHECK');
    // Las tablas nuevas son aparte: no nombran ninguna de las que ya existen.
    final soloCodigo = crear.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final ajena in [
      'contratos_alumnos',
      'pagos_contrato_alumno',
      'barra_precios',
      'barra_cajas',
      'barra_ventas',
      'entradas_',
    ]) {
      expect(soloCodigo, isNot(contains(ajena)), reason: ajena);
    }
    // Se crea al abrir, en una base nueva y al migrar.
    expect('await crearTablasV84(db);'.allMatches(fuente), hasLength(3));
    // Y la app va por la 84 o una después (la v85, el locutor, 28-nov-2026).
    final version = int.parse(RegExp(r'static const int _version = (\d+);').firstMatch(fuente)!.group(1)!);
    expect(version, greaterThanOrEqualTo(84));
  });

  group('la copia antes de migrar', () {
    test('una base en 83 se copia una sola vez, como antes_de_v84', () async {
      await crearBase(83);
      final original = await factory.openDatabase(path);
      final fotoOriginal = await foto(original);
      await original.close();

      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 84);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v84.db'));
      final abierta = await factory.openDatabase(copia.path);
      expect(await foto(abierta), fotoOriginal);
      expect(await abierta.getVersion(), 83);
      await abierta.close();
    });

    test('una base en 80 también se copia, una sola vez', () async {
      await crearBase(80);
      final copia = await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 84);
      expect(copia, isNotNull);
      expect(copia!.path, endsWith('antes_de_v84.db'));
      expect(File('${copia.parent.path}${Platform.pathSeparator}antes_de_v83.db').existsSync(), isFalse);
    });

    test('una base ya migrada no se copia', () async {
      await crearBase(82);
      final db = await abrirEnVersion(84);
      await db.close();
      expect(await LocalDatabase.copiaAntesDeMigrar(path, factory: factory, versionNueva: 84), isNull);
    });
  });
}
