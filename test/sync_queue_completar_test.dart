import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/sync_queue.dart';

/// Sacar de la cola una entrada que ya subió, sin perder un cambio que entró
/// mientras subía.
///
/// `enqueue` reescribe la entrada de un registro que ya estaba en la cola. Si
/// eso pasa con la versión anterior en vuelo, borrar la entrada al terminar
/// dejaba el cambio nuevo sin subir: la nube con el dato viejo, esta PC con el
/// nuevo y nada en la cola. Corre sobre una base en memoria, nunca la real.
void main() {
  sqfliteFfiInit();
  late Database db;
  const registro = 'c0000000-0000-4000-8000-000000000001';

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
  });

  tearDown(() => db.close());

  Future<void> encolar(Map<String, dynamic> datos) => SyncQueue.enqueue(
        tabla: 'contratos_alumnos',
        operacion: SyncOperation.update,
        registroId: registro,
        payload: {'id': registro, ...datos},
        executor: db,
      );

  /// La entrada como la lee el motor justo antes de subirla.
  Future<SyncQueueEntry> leer() async =>
      SyncQueueEntry.fromMap((await db.query('_sync_queue')).single);

  Future<int> enCola() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM _sync_queue')).first['n']
          as int;

  test('lo que subió y nadie tocó sale de la cola', () async {
    await encolar({'numero_mesa': '13'});
    final leida = await leer();
    final salio = await SyncQueue.markCompleted(
      leida.id!,
      leidaCon: leida.createdAt,
      executor: db,
    );
    expect(salio, isTrue);
    expect(await enCola(), 0);
  });

  test('si cambió mientras subía, queda en la cola con lo nuevo', () async {
    // Se cambia la mesa (12 → 13) y el motor empieza a subir eso.
    await encolar({'numero_mesa': '13'});
    final enVuelo = await leer();
    // Mientras sube, se deshace (13 → 12): la misma entrada, reescrita.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await encolar({'numero_mesa': '12'});

    // Termina de subir el 13. La entrada ya no es la que se leyó: no se borra.
    final salio = await SyncQueue.markCompleted(
      enVuelo.id!,
      leidaCon: enVuelo.createdAt,
      executor: db,
    );
    expect(salio, isFalse);
    expect(await enCola(), 1);
    final queda = await leer();
    expect(jsonDecode(jsonEncode(queda.payload))['numero_mesa'], '12');

    // El próximo ciclo sube el 12 y ahora sí sale.
    expect(
      await SyncQueue.markCompleted(
        queda.id!,
        leidaCon: queda.createdAt,
        executor: db,
      ),
      isTrue,
    );
    expect(await enCola(), 0);
  });

  test('una fecha escrita en otro formato no cuenta como un cambio', () async {
    // Una entrada vieja, con la fecha sin la "T" ni la zona.
    final id = await db.insert('_sync_queue', {
      'tabla': 'contratos_alumnos',
      'operacion': 'update',
      'registro_id': registro,
      'payload': '{"id":"$registro"}',
      'created_at': '2026-08-01 10:30:00',
    });
    final leida = await leer();
    expect(leida.createdAt.toIso8601String(), isNot('2026-08-01 10:30:00'));
    final salio = await SyncQueue.markCompleted(
      id,
      leidaCon: leida.createdAt,
      executor: db,
    );
    expect(salio, isTrue);
    expect(await enCola(), 0);
  });

  test('una entrada que ya no está no es un error', () async {
    expect(
      await SyncQueue.markCompleted(
        999,
        leidaCon: DateTime.utc(2026, 10, 1),
        executor: db,
      ),
      isTrue,
    );
  });

  test('sin la fecha de lectura borra por id, como antes', () async {
    await encolar({'numero_mesa': '13'});
    final leida = await leer();
    expect(await SyncQueue.markCompleted(leida.id!, executor: db), isTrue);
    expect(await enCola(), 0);
  });
}
