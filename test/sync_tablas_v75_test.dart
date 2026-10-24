import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/repositories/mora_congelada_repository.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/models/mora_congelada_alumno.dart';

/// La tabla de la v75 (la mora congelada) en el motor de sincronización y en su
/// repositorio. Mismo modelo que `sync_tablas_v74_test.dart`: las listas del
/// motor son privadas y se leen del texto del archivo.
void main() {
  sqfliteFfiInit();
  const contrato = 'c0000000-0000-4000-8000-000000000001';

  final motor = File('lib/core/services/sync_engine.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final cola = File('lib/core/database/sync_queue.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!)) c.group(1)!,
    };
  }

  tearDown(MoraCongelada.vaciar);

  group('mora_congelada en las listas del motor', () {
    test('sube y baja todas sus columnas: las del modelo y las de la base', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV75(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info(mora_congelada)'))
          c['name'] as String,
      };
      final fila = MoraCongeladaAlumno.para(
        contratoAlumnoId: contrato,
        mora: MoraCongelada.nada,
        ahora: DateTime.utc(2026, 10, 23),
      );
      expect(columnasDelMotor('mora_congelada'), enLaBase, reason: 'motor y base');
      expect(columnasDelMotor('mora_congelada'), fila.toMap().keys.toSet(),
          reason: 'motor y modelo');
      await db.close();
    });

    test('baja con lo del cobro, cada 10 s, y en la bajada general', () {
      expect(declaracion('_incrementalColumns', '}'),
          contains("'mora_congelada': 'updated_at'"));
      expect(declaracion('_tablasDelCobro', ']'), contains("'mora_congelada'"));
      expect(motor, contains("_pullTable(db, 'mora_congelada', 'updated_at')"));
    });

    test('es hija del alumno: sube después del contrato', () {
      expect(motor, contains("if (table == 'mora_congelada') return 4;"));
      expect(cola, contains("'mora_congelada': 'contrato_alumno_id'"));
    });

    test('no está en ninguna lista que borre filas locales', () {
      expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'mora_congelada'")));
      expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'mora_congelada'")));
      expect(declaracion('_tablasSinRevisarBorrados', '}'), contains("'mora_congelada':"));
    });

    test('la revisión de la mora carga lo congelado antes de repasar', () {
      final i = motor.indexOf('Future<void> revisarMora(');
      final cuerpo = motor.substring(i, motor.indexOf('reconciliarTodos(', i));
      expect(cuerpo, contains('MoraCongeladaRepository.cargarRegistroEn(db)'));
    });

    test('el arranque carga lo congelado antes de la primera pantalla', () {
      final main = File('lib/main.dart').readAsStringSync();
      final i = main.indexOf('await LocalDatabase.instance');
      final f = main.indexOf('runApp(const ProviderScope(child: JuniorEventsApp()))');
      expect(main.substring(i, f), contains('MoraCongeladaRepository.cargarRegistroEn(db)'));
    });
  });

  group('el repositorio', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE _sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tabla TEXT NOT NULL,
          operacion TEXT NOT NULL,
          registro_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          intentos INTEGER DEFAULT 0,
          ultimo_error TEXT
        )
      ''');
      await LocalDatabase.crearTablasV75(db);
    });

    tearDown(() => db.close());

    test('congelar guarda la fila con id fijo y la encola', () async {
      final mora = MoraCongelada.nada.congelar(todas: true, dia: DateTime(2026, 10, 23));
      await db.transaction((txn) => MoraCongeladaRepository.guardarEn(
            txn,
            contratoAlumnoId: contrato,
            eventoId: 'e0000000-0000-4000-8000-000000000001',
            mora: mora,
            ahora: DateTime.utc(2026, 10, 23, 12),
          ));
      final fila = (await db.query('mora_congelada')).single;
      expect(fila['id'], UuidUtils.moraCongeladaId(contrato));
      expect(MoraCongelada.fromJson(fila['pausas'] as String).pausas, mora.pausas);
      final enCola = (await db.query('_sync_queue')).single;
      expect(enCola['tabla'], 'mora_congelada');
      expect(enCola['operacion'], 'insert');
      expect(jsonDecode(enCola['payload'] as String)['contrato_alumno_id'], contrato);
    });

    test('descongelar no borra la fila: la guarda con otras pausas', () async {
      Future<void> guardar(MoraCongelada m, DateTime cuando) => db.transaction(
            (txn) => MoraCongeladaRepository.guardarEn(
              txn,
              contratoAlumnoId: contrato,
              eventoId: 'e0000000-0000-4000-8000-000000000001',
              mora: m,
              ahora: cuando,
            ),
          );
      final congelada = MoraCongelada.nada.congelar(cuotas: {4}, dia: DateTime(2026, 10, 23));
      await guardar(congelada, DateTime.utc(2026, 10, 23, 12));
      final recalculada = congelada.recalcular(cuotas: {4}, cuotasPagadas: 3, dia: DateTime(2026, 11, 2));
      await guardar(recalculada, DateTime.utc(2026, 11, 2, 12));

      final fila = (await db.query('mora_congelada')).single;
      expect(MoraCongelada.fromJson(fila['pausas'] as String).vacia, isTrue);
      expect(fila['created_at'], '2026-10-23T12:00:00.000Z', reason: 'conserva cuándo nació');
      expect(fila['evento_id'], 'e0000000-0000-4000-8000-000000000001');
    });

    test('cargar el registro lo deja como en la base', () async {
      final mora = MoraCongelada.nada.congelar(cuotas: {4, 5}, dia: DateTime(2026, 10, 23));
      await db.transaction((txn) => MoraCongeladaRepository.guardarEn(
            txn,
            contratoAlumnoId: contrato,
            mora: mora,
            ahora: DateTime.utc(2026, 10, 23),
          ));
      await MoraCongeladaRepository.cargarRegistroEn(db);
      expect(MoraCongelada.de(contrato).cuotasCongeladas, {4, 5});
    });

    test('una base sin la tabla (que no migró) no tira', () async {
      // Otra base de verdad: la de memoria es una sola y ya tiene la tabla.
      final tmp = await Directory.systemTemp.createTemp('sin_tabla_');
      final sinTabla = await databaseFactoryFfi
          .openDatabase('${tmp.path}${Platform.pathSeparator}data.db');
      MoraCongelada.poner(contrato, MoraCongelada.nada.congelar(todas: true, dia: DateTime(2026, 10, 23)));
      await MoraCongeladaRepository.cargarRegistroEn(sinTabla);
      // No pudo leer: se queda con lo que tenía, sin tirar.
      expect(MoraCongelada.de(contrato).todasCongeladas, isTrue);
      await sinTabla.close();
      await tmp.delete(recursive: true);
    });
  });
}
