import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/plano/estilos/estilo_plano.dart';
import 'package:arguello_events/features/plano/modelo/armados_predefinidos.dart';
import 'package:arguello_events/features/plano/repositories/planos_evento_repository.dart';
import 'package:arguello_events/models/plano_evento.dart';

/// El plano de una fiesta se guarda solo con su id fijo. Con otro, el REPLACE
/// local pisaría sin avisar el que ya está (por el UNIQUE de evento_id), y la
/// nube lo rechazaría por el `unique (evento_id)`: la fila quedaría trabada en
/// la cola y cada PC con un plano distinto.
///
/// Corre sobre una base en memoria, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  late Database db;
  const evento = 'e0000000-0000-4000-8000-000000000001';
  final ahora = DateTime.utc(2026, 9, 27);

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
    await LocalDatabase.crearTablasV73(db);
  });

  tearDown(() => db.close());

  PlanoEvento nuevo() => PlanoEvento.nuevo(
        eventoId: evento,
        armado: ArmadosPredefinidos.normal2aPagina3(),
        estilo: EstiloPlano.gala,
        modo: ModoSorteo.bloques,
        ahora: ahora,
      );

  Future<int> filas(String tabla) async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM $tabla')).first['n'] as int;

  test('el plano con su id fijo se guarda y se encola', () async {
    await db.transaction(
      (txn) => PlanosEventoRepository.guardarEn(txn, nuevo()),
    );
    expect(await filas('planos_evento'), 1);
    final cola = await db.query('_sync_queue');
    expect(cola.single['tabla'], 'planos_evento');
    expect(cola.single['registro_id'], UuidUtils.planoEventoId(evento));
  });

  test('uno con otro id no se guarda, y deshace la transacción entera',
      () async {
    final bueno = nuevo();
    final malo = PlanoEvento.fromMap(
      bueno.toMap()..['id'] = UuidUtils.generate(),
    );
    await expectLater(
      db.transaction((txn) async {
        await PlanosEventoRepository.guardarEn(txn, bueno);
        await PlanosEventoRepository.guardarEn(txn, malo);
      }),
      throwsArgumentError,
    );
    expect(await filas('planos_evento'), 0);
    expect(await filas('_sync_queue'), 0);
  });
}
