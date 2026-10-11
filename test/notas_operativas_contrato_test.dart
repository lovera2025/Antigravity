import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/eventos/repositories/notas_operativas_contrato_repository.dart';
import 'package:arguello_events/models/nota_operativa_contrato.dart';

/// Las notas de un alumno: con qué id viajan a la nube, y cuándo se escribieron.
///
/// Corre sobre una base en memoria, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  late Database db;
  const alumno = 'c0000000-0000-4000-8000-000000000001';
  final fijo = UuidUtils.notaOperativaContratoId(alumno);

  /// El id de una nota que no escribió la app (las de mora condonada de julio
  /// de 2026 las cargó una herramienta, con un id cualquiera).
  const viejo = '62f2bc80-0b26-4339-915e-8d2ff38370a4';

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
    // La misma tabla de `local_database.dart`.
    await db.execute('''
      CREATE TABLE notas_operativas_contrato (
        id TEXT PRIMARY KEY,
        contrato_alumno_id TEXT NOT NULL UNIQUE,
        texto TEXT NOT NULL DEFAULT '',
        resuelto INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  });

  tearDown(() => db.close());

  Future<void> cargarVieja() => db.insert('notas_operativas_contrato', {
        'id': viejo,
        'contrato_alumno_id': alumno,
        'texto': 'MORA CONDONADA — 29/07/2026',
        'resuelto': 1,
        'created_at': '2026-07-29T15:00:00.000Z',
        'updated_at': '2026-07-29T15:00:00.000Z',
      });

  Future<Map<String, Object?>> nota() async =>
      (await db.query('notas_operativas_contrato')).single;

  Future<Map<String, Object?>> enCola() async =>
      (await db.query('_sync_queue')).single;

  group('con qué id viaja una nota', () {
    test('una nueva lleva el id fijo de su alumno, y sube como alta', () async {
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: '  le quedó 300 a favor  ',
        resuelto: false,
        ahoraIso: '2026-10-11T18:00:00.000Z',
      );
      final n = await nota();
      expect(n['id'], fijo);
      expect(n['texto'], 'le quedó 300 a favor');
      expect(n['created_at'], '2026-10-11T18:00:00.000Z');
      final c = await enCola();
      expect(c['operacion'], 'insert');
      expect(c['registro_id'], fijo);
      expect(jsonDecode(c['payload'] as String)['resuelto'], isFalse);
    });

    test('al editarla conserva su id y cuándo se escribió', () async {
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: 'pasa el viernes',
        resuelto: false,
        ahoraIso: '2026-10-11T18:00:00.000Z',
      );
      await db.delete('_sync_queue');
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: 'pasó y pagó',
        resuelto: true,
        ahoraIso: '2026-10-14T13:30:00.000Z',
      );
      final n = await nota();
      expect(n['id'], fijo);
      expect(n['texto'], 'pasó y pagó');
      expect(n['resuelto'], 1);
      expect(n['created_at'], '2026-10-11T18:00:00.000Z');
      expect(n['updated_at'], '2026-10-14T13:30:00.000Z');
      final c = await enCola();
      expect(c['operacion'], 'update');
      expect(c['registro_id'], fijo);
      final paquete = jsonDecode(c['payload'] as String) as Map<String, dynamic>;
      expect(paquete['created_at'], '2026-10-11T18:00:00.000Z');
    });

    test('una que no escribió la app se edita con el id que tiene en la nube',
        () async {
      await cargarVieja();
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: 'MORA CONDONADA — revisado',
        resuelto: true,
      );
      // Con el id fijo, la nube no encontraba la fila y el cambio no llegaba
      // a ninguna otra PC.
      expect((await nota())['id'], viejo);
      final c = await enCola();
      expect(c['operacion'], 'update');
      expect(c['registro_id'], viejo);
      expect(jsonDecode(c['payload'] as String)['id'], viejo);
    });

    test('y se borra con ese mismo id', () async {
      await cargarVieja();
      final habia =
          await NotasOperativasContratoRepository.eliminarEn(db, alumno);
      expect(habia, isTrue);
      expect(await db.query('notas_operativas_contrato'), isEmpty);
      // Con el id fijo, la nota seguía en la nube y en las otras PCs.
      final c = await enCola();
      expect(c['operacion'], 'delete');
      expect(c['registro_id'], viejo);
    });

    test('una de la app se borra con su id fijo', () async {
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: 'REVISAR',
        resuelto: false,
      );
      await db.delete('_sync_queue');
      await NotasOperativasContratoRepository.eliminarEn(db, alumno);
      expect(await db.query('notas_operativas_contrato'), isEmpty);
      expect((await enCola())['registro_id'], fijo);
    });

    test('borrar donde no hay nota no encola nada', () async {
      expect(
        await NotasOperativasContratoRepository.eliminarEn(db, alumno),
        isFalse,
      );
      expect(await db.query('_sync_queue'), isEmpty);
    });

    test('una fila sin id (de antes) queda con el fijo al editarla', () async {
      await db.insert('notas_operativas_contrato', {
        'id': '',
        'contrato_alumno_id': alumno,
        'texto': 'vieja',
        'resuelto': 0,
        'created_at': '2026-05-13T23:16:19.000Z',
        'updated_at': '2026-05-13T23:16:19.000Z',
      });
      await NotasOperativasContratoRepository.guardarEn(
        db,
        contratoAlumnoId: alumno,
        texto: 'vieja, corregida',
        resuelto: false,
      );
      expect((await nota())['id'], fijo);
      expect((await enCola())['registro_id'], fijo);
    });

    test('una nota vacía no se guarda', () async {
      await expectLater(
        NotasOperativasContratoRepository.guardarEn(
          db,
          contratoAlumnoId: alumno,
          texto: '   ',
          resuelto: false,
        ),
        throwsArgumentError,
      );
      expect(await db.query('notas_operativas_contrato'), isEmpty);
      expect(await db.query('_sync_queue'), isEmpty);
    });
  });

  group('la nota y su subida van juntas', () {
    // Una nota guardada sin su entrada en la cola no sube nunca, y nada la
    // reporta como pendiente: así quedaron 17 notas en una sola PC.
    test('si no se puede encolar, la nota no queda guardada', () async {
      await db.execute('DROP TABLE _sync_queue');
      await expectLater(
        db.transaction(
          (txn) => NotasOperativasContratoRepository.guardarEn(
            txn,
            contratoAlumnoId: alumno,
            texto: 'no tiene que quedar',
            resuelto: false,
          ),
        ),
        throwsA(anything),
      );
      expect(await db.query('notas_operativas_contrato'), isEmpty);
    });

    test('si no se puede encolar el borrado, la nota sigue', () async {
      await cargarVieja();
      await db.execute('DROP TABLE _sync_queue');
      await expectLater(
        db.transaction(
          (txn) => NotasOperativasContratoRepository.eliminarEn(txn, alumno),
        ),
        throwsA(anything),
      );
      expect((await nota())['id'], viejo);
    });
  });

  group('cuándo se escribió', () {
    NotaOperativaContrato hecha(String creada, String tocada) =>
        NotaOperativaContrato.fromMap({
          'id': fijo,
          'contrato_alumno_id': alumno,
          'texto': 'A FAVOR \$50',
          'resuelto': 0,
          'created_at': creada,
          'updated_at': tocada,
        });

    test('sin tocar, dice solo cuándo se escribió, en hora de Argentina', () {
      // 23:16 UTC son las 20:16 en Argentina.
      final n = hecha('2026-05-13T23:16:19.759Z', '2026-05-13T23:16:19.759Z');
      expect(n.seModifico, isFalse);
      expect(n.cuando(), 'Escrita el 13/05/2026 20:16 hs');
      expect(n.cuando(conHora: false), 'Escrita el 13/05/2026');
    });

    test('pasada la medianoche de Londres sigue siendo el día de acá', () {
      // 01:30 UTC del 14 son las 22:30 del 13 en Argentina.
      final n = hecha('2026-05-14T01:30:00.000Z', '2026-05-14T01:30:00.000Z');
      expect(n.cuando(conHora: false), 'Escrita el 13/05/2026');
    });

    test('si se tocó después, dice también cuándo', () {
      final n = hecha('2026-05-13T23:16:19.759Z', '2026-06-10T12:35:00.000Z');
      expect(n.seModifico, isTrue);
      expect(
        n.cuando(),
        'Escrita el 13/05/2026 20:16 hs · modificada el 10/06/2026 09:35 hs',
      );
      expect(
        n.cuando(conHora: false),
        'Escrita el 13/05/2026 · modificada el 10/06/2026',
      );
    });

    test('la hora que le pone la nube al subirla no cuenta como modificada',
        () {
      // El trigger de Supabase reescribe `updated_at` también al insertar.
      final n = hecha('2026-05-13T23:16:19.759Z', '2026-05-13T23:16:41.102Z');
      expect(n.seModifico, isFalse);
      expect(n.cuando(), 'Escrita el 13/05/2026 20:16 hs');
    });

    test('una nota sin fecha no inventa una', () {
      final n = NotaOperativaContrato.fromMap({
        'id': fijo,
        'contrato_alumno_id': alumno,
        'texto': 'sin fecha',
        'resuelto': 0,
        'created_at': 'no es una fecha',
        'updated_at': '',
      });
      expect(n.cuando(), '');
      expect(n.cuando(conHora: false), '');
    });
  });
}
