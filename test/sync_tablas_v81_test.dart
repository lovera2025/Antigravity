import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/eventos/repositories/entradas_entregas_repository.dart';
import 'package:arguello_events/models/entradas_retiro.dart';
import 'package:arguello_events/models/entrega_entradas.dart';

/// La tabla de la v81 (la entrega de entradas en dos partes) en el motor de
/// sincronización, en el SQL de la nube y en la base: **la nube y la PC dicen lo
/// mismo**. Mismo modelo que `sync_tablas_v80_test.dart`: las listas del motor
/// son privadas y se leen del texto del archivo. Y el repositorio, sobre una
/// base en memoria: solo agrega renglones, cada uno con su entrada en la cola.
void main() {
  sqfliteFfiInit();

  String leer(String ruta) =>
      File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

  final motor = leer('lib/core/services/sync_engine.dart');
  final cola = leer('lib/core/database/sync_queue.dart');
  final sql = leer('supabase/migrations/20261120120000_entradas_entregas.sql');
  const tabla = 'entradas_entregas';

  String sinComentarios(String texto) => [
        for (final l in texto.split('\n'))
          if (!l.trimLeft().startsWith('--')) l,
      ].join('\n');

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
      for (final c in RegExp("'([a-z_0-9]+)'").allMatches(m!.group(1)!)) c.group(1)!,
    };
  }

  Set<String> columnasDelSql(String tabla) {
    final crear = RegExp(
      'create table if not exists public\\.$tabla \\(([\\s\\S]*?)\\n\\);',
    ).firstMatch(sql);
    expect(crear, isNotNull, reason: '$tabla no está en el SQL');
    return {
      for (final l in crear!.group(1)!.split('\n'))
        if (l.trim().isNotEmpty) l.trim().split(' ').first,
    };
  }

  final ahora = DateTime.utc(2026, 11, 20, 15);
  const evento = 'e0000000-0000-4000-8000-000000000001';
  const alumno = 'c0000000-0000-4000-8000-000000000001';

  final entrega = EntregaEntradas.entrega(
    contratoAlumnoId: alumno,
    eventoId: evento,
    parte: ParteEntrega.generales,
    cantidad: 5,
    tramos: const [TramoTalonario(1043, 1045), TramoTalonario(1101, 1102)],
    menores10: 1,
    parentesco: ParentescoRetiro.otraPersona,
    nombre: '  vecina   de la familia ',
    motivoOtraPersona: 'la madre trabaja',
    autorizacionFirmada: true,
    escribioEnPlanilla: true,
    hechoPor: 'Carla',
    deviceId: 'tablet-1',
    ahora: ahora,
  );
  final anulacion = EntregaEntradas.anulacion(
    contratoAlumnoId: alumno,
    eventoId: evento,
    parte: ParteEntrega.generales,
    cantidad: 5,
    tramos: entrega.tramos,
    motivo: 'se anotaron mal los números',
    hechoPor: 'Jefe',
    deviceId: 'pc-1',
    ahora: ahora.add(const Duration(hours: 1)),
  );

  group('la nube y la PC dicen lo mismo', () {
    test('el modelo, la base, el motor y el SQL tienen las mismas columnas',
        () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV81(db);
      final enLaBase = {
        for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
          c['name'] as String,
      };
      await db.close();
      final delModelo = entrega.toMap().keys.toSet();
      expect(delModelo, hasLength(18));
      expect(enLaBase, delModelo, reason: 'base y modelo');
      expect(columnasDelMotor(tabla), delModelo, reason: 'motor y modelo');
      expect(columnasDelSql(tabla), delModelo, reason: 'SQL y modelo');
      expect(EntradasEntregasRepository.tabla, tabla);
    });

    test('va y vuelve de la base igual', () {
      expect(EntregaEntradas.fromMap(entrega.toMap()).toMap(), entrega.toMap());
      expect(EntregaEntradas.fromMap(anulacion.toMap()).toMap(), anulacion.toMap());
      final m = entrega.toMap();
      expect(m['parte'], 'generales');
      expect(m['accion'], 'entrega');
      expect(m['tramos'], '1043-1045,1101-1102');
      expect(m['retiro_nombre'], 'VECINA DE LA FAMILIA');
      expect(m['autorizacion_firmada'], 1);
      expect(m['escribio_en_planilla'], 1);
      expect(anulacion.toMap()['accion'], 'anulacion');
      expect(anulacion.toMap()['motivo'], 'se anotaron mal los números');
    });

    test('y de la nube también: las casillas como 0 y 1, las fechas con zona', () {
      final deLaNube = Map<String, dynamic>.from(entrega.toMap())
        ..['autorizacion_firmada'] = 0
        ..['cantidad'] = 5.0
        ..['created_at'] = '2026-11-20T15:00:00+00:00';
      final r = EntregaEntradas.fromMap(deLaNube);
      expect(r.autorizacionFirmada, isFalse);
      expect(r.cantidad, 5);
      expect(r.createdAt.isAtSameMomentAs(ahora), isTrue);
      expect(r.tramos, entrega.tramos);
    });

    test('una parte o una acción que esta versión no conoce vuelven igual', () {
      final rara = EntregaEntradas.fromMap({
        ...entrega.toMap(),
        'parte': 'vasos',
        'accion': 'prestamo',
      });
      expect(rara.parte, isNull);
      expect(rara.accion, isNull);
      expect(rara.toMap()['parte'], 'vasos');
      expect(rara.toMap()['accion'], 'prestamo');
    });

    test('las pulseras van sin número, y anular lleva motivo', () {
      final pulseras = EntregaEntradas.entrega(
        contratoAlumnoId: alumno,
        eventoId: evento,
        parte: ParteEntrega.pulseras,
        cantidad: 3,
        tramos: const [TramoTalonario(1, 3)],
        parentesco: ParentescoRetiro.madre,
        nombre: 'MADRE, UNA',
        escribioEnPlanilla: true,
        hechoPor: 'Carla',
        deviceId: 'pc-1',
        ahora: ahora,
      );
      expect(pulseras.tramos, isEmpty);
      expect(pulseras.toMap()['tramos'], '');
      expect(
        () => EntregaEntradas.anulacion(
          contratoAlumnoId: alumno,
          eventoId: evento,
          parte: ParteEntrega.pulseras,
          cantidad: 3,
          motivo: '   ',
          hechoPor: 'Jefe',
          deviceId: 'pc-1',
          ahora: ahora,
        ),
        throwsArgumentError,
      );
    });
  });

  group('en las listas del motor', () {
    test('baja, en la bajada general y por su marca de tiempo', () {
      final incrementales = declaracion('_incrementalColumns', '}');
      expect(incrementales, contains("'$tabla': 'updated_at'"));
      expect(motor, contains("_pullTable(db, '$tabla', 'updated_at')"));
      expect(SyncEngine.tablasQueSeBajan, contains(tabla));
    });

    test('baja con lo del cobro: es de mostrador, como la fila de la entrega', () {
      expect(SyncEngine.tablasDelCobro, contains(tabla));
      expect(SyncEngine.tablasDeCarga, isNot(contains(tabla)));
      expect(SyncEngine.tablasDelCobro, contains('entradas_retiro'));
    });

    test('baja con "Lista para trabajar sin internet": la tablet entrega sin red',
        () {
      expect(SyncEngine.tablasDeLaPuerta, contains(tabla));
      expect(SyncEngine.tablasDeLaPuerta, contains('entradas_retiro'));
    });

    test('sube después del contrato, como la fila de la entrega', () {
      expect(motor, contains("if (table == '$tabla') return 4;"));
      expect(
        motor,
        contains("if (table == 'sillas_reparto' || table == 'entradas_retiro') return 4;"),
      );
    });

    test('un renglón encolado no se descarta nunca: no es hija en la limpieza de la cola',
        () {
      expect(cola, isNot(contains("'$tabla'")));
    });

    test('no está en ninguna lista que borre filas locales, y dice por qué', () {
      final reconciliar = declaracion('_tablasAReconciliar', ']');
      final cascada = declaracion('_hijasEnCascada', '}');
      expect(reconciliar, isNot(contains("'$tabla'")));
      expect(cascada, isNot(contains("'$tabla'")));
      expect(SyncEngine.tablasSinRevisarBorrados[tabla], contains('solo se agregan'));
    });
  });

  group('el SQL de la nube', () {
    final codigo = sinComentarios(sql).toLowerCase();

    test('sin CHECK, sin clave foránea y sin índice único', () {
      // `with check (...)` es de la policy, no un CHECK de la tabla.
      expect(codigo, isNot(matches(RegExp(r'(?<!with )\bcheck\s*\('))));
      expect(codigo, isNot(contains('references')));
      expect(codigo, isNot(contains('unique')));
    });

    test('solo crea: no toca ninguna tabla que ya exista', () {
      expect(
        codigo,
        isNot(matches(RegExp(r'\b(drop table|delete from|update public\.|insert into)\b'))),
      );
      expect(RegExp(r'create table (?!if not exists)').hasMatch(codigo), isFalse);
      expect(RegExp(r'create index (?!if not exists)').hasMatch(codigo), isFalse);
      final nombradas = {
        for (final m in RegExp(r'public\.([a-z_]+)').allMatches(codigo)) m.group(1)!,
      }..remove('update_updated_at_column');
      expect(nombradas, {tabla});
      for (final ajena in [
        'contratos_alumnos',
        'pagos_contrato_alumno',
        'sesiones_caja',
        'entradas_retiro',
        'entradas_ventas',
      ]) {
        expect(codigo, isNot(contains(ajena)), reason: ajena);
      }
    });

    test('índices por alumno, por fiesta y por fecha de cambio', () {
      expect(codigo, contains('on public.entradas_entregas(contrato_alumno_id)'));
      expect(codigo, contains('on public.entradas_entregas(evento_id)'));
      expect(codigo, contains('on public.entradas_entregas(updated_at desc)'));
    });

    test('con la policy de los usuarios logueados y los dos disparadores de updated_at',
        () {
      final lista = RegExp(r'array\[([\s\S]*?)\]').firstMatch(sql)!.group(1)!;
      final conRls = {
        for (final m in RegExp(r"'([a-z_]+)'").allMatches(lista)) m.group(1)!,
      };
      expect(conRls, {tabla});
      expect(sql, contains("t || '_all_authenticated'"));
      expect(sql, contains("auth.role() = ''authenticated''"));
      expect(sql, contains('set_updated_at_ins_'));
      expect(sql, contains('set_updated_at_upd_'));
      expect(sql, contains('update_updated_at_column()'));
    });

    test('no entra a Realtime', () {
      expect(codigo, isNot(contains('supabase_realtime')));
    });

    test('trae su ROLLBACK, y al final las consultas de antes y después', () {
      expect(sql, contains('-- ROLLBACK: drop table if exists public.$tabla;'));
      expect(sql, contains('(select count(*) from public.contratos_alumnos)'));
      expect(sql, contains('(select count(*) from public.entradas_retiro)'));
    });
  });

  group('el repositorio', () {
    late Database db;
    late EntradasEntregasRepository repo;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 81,
          onCreate: LocalDatabase.onCreateParaTest,
        ),
      );
      repo = EntradasEntregasRepository(null, abrir: () async => db);
    });

    tearDown(() => db.close());

    Future<List<Map<String, Object?>>> enCola() =>
        db.query('_sync_queue', where: 'tabla = ?', whereArgs: [tabla]);

    test('agrega cada renglón con su entrada en la cola', () async {
      await repo.agregar([entrega, anulacion]);
      final filas = await db.query(tabla, orderBy: 'created_at');
      expect(filas, hasLength(2));
      expect(EntregaEntradas.fromMap(filas.first).toMap(), entrega.toMap());
      final cola = await enCola();
      expect({for (final c in cola) c['registro_id']}, {entrega.id, anulacion.id});
      expect({for (final c in cola) c['operacion']}, {'insert'});
    });

    test('un renglón que ya está no se vuelve a escribir ni a encolar', () async {
      await repo.agregar([entrega]);
      await db.delete('_sync_queue');
      final distinto = EntregaEntradas.fromMap({
        ...entrega.toMap(),
        'cantidad': 99,
      });
      await repo.agregar([distinto]);
      final filas = await db.query(tabla);
      expect(filas.single['cantidad'], 5, reason: 'un renglón nunca cambia');
      expect(await enCola(), isEmpty);
    });

    test('si la cola falla, no queda el renglón sin subir', () async {
      await db.execute('ALTER TABLE _sync_queue RENAME TO _sync_queue_tapada');
      await expectLater(repo.agregar([entrega]), throwsA(anything));
      await db.execute('ALTER TABLE _sync_queue_tapada RENAME TO _sync_queue');
      expect(await db.query(tabla), isEmpty, reason: 'la misma transacción');
    });

    test('lee por alumno y por fiesta, del más viejo al más nuevo', () async {
      final otro = EntregaEntradas.entrega(
        contratoAlumnoId: 'c0000000-0000-4000-8000-000000000002',
        eventoId: 'e0000000-0000-4000-8000-000000000002',
        parte: ParteEntrega.pulseras,
        cantidad: 2,
        parentesco: ParentescoRetiro.padre,
        nombre: 'PADRE, UNO',
        escribioEnPlanilla: true,
        hechoPor: 'Carla',
        deviceId: 'pc-1',
        ahora: ahora,
      );
      await repo.agregar([anulacion, otro, entrega]);
      final porAlumno = await repo.deContratos([alumno, otro.contratoAlumnoId]);
      expect([for (final r in porAlumno[alumno]!) r.id], [entrega.id, anulacion.id]);
      expect(porAlumno[otro.contratoAlumnoId]!.single.id, otro.id);
      expect([for (final r in await repo.delEvento(evento)) r.id],
          [entrega.id, anulacion.id]);
      expect(await repo.deContratos(const []), isEmpty);
    });

    test('el código nunca edita ni borra un renglón', () {
      final fuente = leer(
        'lib/features/eventos/repositories/entradas_entregas_repository.dart',
      );
      final codigo = fuente
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final prohibido in [
        '.update(',
        '.delete(',
        'rawUpdate(',
        'rawDelete(',
        'ConflictAlgorithm.replace',
        'SyncOperation.update',
        'SyncOperation.delete',
        'upsert(',
      ]) {
        expect(codigo, isNot(contains(prohibido)), reason: prohibido);
      }
    });
  });
}
