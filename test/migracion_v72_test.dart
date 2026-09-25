import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';

/// La migración v72 tiene que agregar sus tres tablas y **nada más**: ni una
/// fila de lo que ya existe puede cambiar, se tiene que poder correr dos veces,
/// y si alguien reinstala la 5.0.0 la base tiene que seguir abriendo.
///
/// Corre sobre una base temporal, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;
  late Directory tmp;
  late String path;

  const tablasNuevas = ['sillas_reparto', 'entradas_retiro', 'sorteos_mesas'];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('migracion_v72_');
    path = '${tmp.path}${Platform.pathSeparator}data.db';
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Una base "v71" con las tablas de la plata y un marcador de sync, con datos.
  Future<void> crearBaseV71() async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 71,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE contratos_alumnos (
              id TEXT PRIMARY KEY, evento_id TEXT NOT NULL,
              nombre_alumno TEXT NOT NULL, saldo_deudor REAL NOT NULL,
              numero_mesa TEXT, sillas_extra_cantidad INTEGER DEFAULT 0,
              updated_at TEXT)
          ''');
          await db.execute('''
            CREATE TABLE pagos_contrato_alumno (
              id TEXT PRIMARY KEY, contrato_alumno_id TEXT NOT NULL,
              monto REAL NOT NULL, concepto TEXT, fecha_pago TEXT)
          ''');
          await db.execute('''
            CREATE TABLE notas_operativas_contrato (
              id TEXT PRIMARY KEY, contrato_alumno_id TEXT NOT NULL UNIQUE,
              texto TEXT NOT NULL DEFAULT '', resuelto INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL)
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

          for (var i = 0; i < 40; i++) {
            final id = 'c0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
            await db.insert('contratos_alumnos', {
              'id': id,
              'evento_id': 'e0000000-0000-4000-8000-000000000001',
              'nombre_alumno': 'ALUMNO $i',
              'saldo_deudor': 1000.5 * i,
              'numero_mesa': i.isEven ? '${i + 1}' : null,
              'sillas_extra_cantidad': i % 3,
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
          await db.insert('notas_operativas_contrato', {
            'id': 'n0000000-0000-4000-8000-000000000001',
            'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
            'texto': 'Quedaron \$50 del mes pasado',
            'resuelto': 0,
            'created_at': '2026-09-01T00:00:00.000Z',
            'updated_at': '2026-09-01T00:00:00.000Z',
          });
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

  Future<Database> abrirEnVersion(int version) => factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onUpgrade: LocalDatabase.onUpgradeParaTest,
        ),
      );

  test('de 71 a 72: aparecen las tres tablas y lo demás queda igual', () async {
    await crearBaseV71();
    final antes = await factory.openDatabase(path);
    final fotoAntes = await foto(antes);
    await antes.close();

    final db = await abrirEnVersion(72);
    expect(await db.getVersion(), 72);
    final fotoDespues = await foto(db);
    await db.close();

    for (final t in tablasNuevas) {
      expect(fotoDespues[t], '[]', reason: '$t tiene que nacer vacía');
    }
    final viejasDespues = Map.of(fotoDespues)
      ..removeWhere((k, _) => tablasNuevas.contains(k));
    expect(viejasDespues, fotoAntes);
  });

  test('las tablas nuevas tienen las columnas que usa el sync', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(72);
    Future<Set<String>> columnas(String t) async => {
          for (final c in await db.rawQuery('PRAGMA table_info($t)'))
            c['name'] as String,
        };
    expect(await columnas('sillas_reparto'), {
      'id', 'contrato_alumno_id', 'sillas_principal', 'sillas_extra', 'mesas',
      'hecho_por', 'created_at', 'updated_at',
    });
    expect(await columnas('entradas_retiro'), {
      'id', 'contrato_alumno_id', 'estado', 'vip', 'generales', 'tramos',
      'menores_10', 'parentesco', 'retiro_nombre', 'otra_persona_motivo',
      'autorizacion_firmada', 'escribio_en_planilla', 'entregado_por',
      'entregado_at', 'anulado_por', 'anulado_at', 'anulado_motivo',
      'created_at', 'updated_at',
    });
    expect(await columnas('sorteos_mesas'), {
      'id', 'evento_id', 'tipo', 'resultado', 'alumnos', 'hecho_por',
      'created_at', 'updated_at',
    });
    await db.close();
  });

  test('se puede correr dos veces sin efecto', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(72);
    await db.insert('sillas_reparto', {
      'id': 's0000000-0000-4000-8000-000000000001',
      'contrato_alumno_id': 'c0000000-0000-4000-8000-000000000001',
      'sillas_principal': 2,
      'sillas_extra': 3,
      'mesas': 2,
      'created_at': '2026-09-25T00:00:00.000Z',
      'updated_at': '2026-09-25T00:00:00.000Z',
    });
    final fotoAntes = await foto(db);
    await LocalDatabase.crearTablasV72(db);
    await LocalDatabase.onUpgradeParaTest(db, 71, 72);
    expect(await foto(db), fotoAntes);
    await db.close();
  });

  test('si se reinstala la 5.0.0 la base abre, y al volver a la nueva también',
      () async {
    await crearBaseV71();
    var db = await abrirEnVersion(72);
    final fotoV72 = await foto(db);
    await db.close();

    // La 5.0.0 pide la versión 71 y no tiene onDowngrade.
    db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 71),
    );
    expect(await db.getVersion(), 71);
    expect(await foto(db), fotoV72);
    await db.close();

    db = await abrirEnVersion(72);
    expect(await db.getVersion(), 72);
    expect(await foto(db), fotoV72);
    await db.close();
  });

  test('antes de migrar queda una copia completa, una sola vez', () async {
    await crearBaseV71();
    final original = await factory.openDatabase(path);
    final fotoOriginal = await foto(original);
    await original.close();

    final copia = await LocalDatabase.copiaAntesDeMigrar(
      path,
      factory: factory,
      versionNueva: 72,
    );
    expect(copia, isNotNull);
    expect(
      copia!.path,
      endsWith('${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}antes_de_v72.db'),
    );

    final abierta = await factory.openDatabase(copia.path);
    expect(await foto(abierta), fotoOriginal);
    expect(await abierta.getVersion(), 71);
    await abierta.close();

    // La segunda vez no la pisa: la buena es la de antes de cualquier intento.
    final modificada = copia.lastModifiedSync();
    final otraVez = await LocalDatabase.copiaAntesDeMigrar(
      path,
      factory: factory,
      versionNueva: 72,
    );
    expect(otraVez!.path, copia.path);
    expect(otraVez.lastModifiedSync(), modificada);
  });

  test('una base ya migrada no se copia', () async {
    await crearBaseV71();
    final db = await abrirEnVersion(72);
    await db.close();
    final copia = await LocalDatabase.copiaAntesDeMigrar(
      path,
      factory: factory,
      versionNueva: 72,
    );
    expect(copia, isNull);
  });

  test('sin base todavía no hace nada', () async {
    final copia = await LocalDatabase.copiaAntesDeMigrar(
      path,
      factory: factory,
      versionNueva: 72,
    );
    expect(copia, isNull);
  });
}
