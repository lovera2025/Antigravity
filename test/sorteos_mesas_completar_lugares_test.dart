import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/eventos/repositories/sorteos_mesas_repository.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

/// Aceptar la lista de PRECIOS de una fiesta ya sorteada le agrega al renglón
/// del sorteo lo que cada familia tenía cargado (`_lugares`). **Es la única
/// vez que se toca un renglón ya escrito**: lo demás del renglón tiene que
/// quedar idéntico, y la fila tiene que subir.
///
/// Corre sobre una base en memoria, nunca sobre la real.
void main() {
  sqfliteFfiInit();
  late Database db;
  const evento = 'e0000000-0000-4000-8000-000000000001';
  const idSorteo = 'a0000000-0000-4000-8000-000000000001';
  const idDeshacer = 'a0000000-0000-4000-8000-000000000002';
  final cuando = DateTime.utc(2026, 11, 13, 0, 40);

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
    await LocalDatabase.crearTablasV72(db);
  });

  tearDown(() => db.close());

  SorteoMesasRegistro sorteo() => SorteoMesasRegistro(
        id: idSorteo,
        eventoId: evento,
        tipo: TipoRegistroSorteo.sorteo,
        resultado: const {'alumno-1': '12, 13', 'alumno-2': '14'},
        antes: const {},
        nuevas: const {'alumno-1': '13'},
        hechoPor: 'Jefe',
        createdAt: cuando,
      );

  Future<Map<String, dynamic>> fila(String id) async =>
      (await db.query('sorteos_mesas', where: 'id = ?', whereArgs: [id])).single;

  Future<List<Map<String, dynamic>>> cola() => db.query('_sync_queue');

  /// El renglón ya subió: la cola quedó vacía.
  Future<void> yaSubio() => db.delete('_sync_queue');

  test('agrega los lugares y deja todo lo demás del renglón como estaba', () async {
    await SorteosMesasRepository.registrarEn(db, sorteo());
    await yaSubio();
    final antes = await fila(idSorteo);

    final bien = await SorteosMesasRepository.completarLugaresEn(
      db,
      idSorteo,
      const {'alumno-1': '2,0'},
      ahora: cuando.add(const Duration(days: 5)),
    );
    expect(bien, isTrue);

    final despues = await fila(idSorteo);
    for (final c in ['id', 'evento_id', 'tipo', 'alumnos', 'hecho_por', 'created_at']) {
      expect(despues[c], antes[c], reason: c);
    }
    final textoAntes = jsonDecode(antes['resultado'] as String) as Map;
    final textoDespues = jsonDecode(despues['resultado'] as String) as Map;
    expect(textoDespues['_lugares'], {'alumno-1': '2,0'});
    textoDespues.remove('_lugares');
    expect(textoDespues, textoAntes);

    final leido = SorteoMesasRegistro.fromMap(despues);
    expect(leido.resultado, sorteo().resultado);
    expect(leido.antes, isEmpty);
    expect(leido.nuevas, {'alumno-1': '13'});
    expect(leido.lugares, {'alumno-1': '2,0'});
    expect(leido.createdAt, cuando);
  });

  test('la fila entera queda en la cola para subir, como un insert (en la '
      'nube, un upsert)', () async {
    await SorteosMesasRepository.registrarEn(db, sorteo());
    await yaSubio();
    await SorteosMesasRepository.completarLugaresEn(db, idSorteo, const {});

    final entrada = (await cola()).single;
    expect(entrada['tabla'], 'sorteos_mesas');
    expect(entrada['registro_id'], idSorteo);
    expect(entrada['operacion'], 'insert');
    final payload = jsonDecode(entrada['payload'] as String) as Map;
    final guardada = await fila(idSorteo);
    expect(payload.keys.toSet(), guardada.keys.toSet());
    expect(payload['resultado'], guardada['resultado']);
    expect(
      (jsonDecode(payload['resultado'] as String) as Map).containsKey('_lugares'),
      isTrue,
      reason: 'vacío también se anota: nadie tenía adicionales',
    );
  });

  test('si el sorteo todavía no había subido, sube una sola vez y ya con los '
      'lugares', () async {
    await SorteosMesasRepository.registrarEn(db, sorteo());
    await SorteosMesasRepository.completarLugaresEn(
      db,
      idSorteo,
      const {'alumno-2': '1,2'},
    );
    final entrada = (await cola()).single;
    expect(entrada['operacion'], 'insert');
    final texto =
        jsonDecode((jsonDecode(entrada['payload'] as String) as Map)['resultado']
            as String) as Map;
    expect(texto['_lugares'], {'alumno-2': '1,2'});
    expect(texto['alumno-1'], '12, 13');
  });

  test('no pierde una clave que esta versión no conoce', () async {
    await db.insert('sorteos_mesas', {
      ...sorteo().toMap(),
      'resultado': jsonEncode({
        'alumno-1': '12',
        '_de_otra_version': {'x': 'y'},
      }),
    });
    await SorteosMesasRepository.completarLugaresEn(db, idSorteo, const {});
    final texto =
        jsonDecode((await fila(idSorteo))['resultado'] as String) as Map;
    expect(texto['_de_otra_version'], {'x': 'y'});
    expect(texto['alumno-1'], '12');
  });

  test('un renglón que no está en esta PC: no escribe nada', () async {
    final bien = await SorteosMesasRepository.completarLugaresEn(
      db,
      idSorteo,
      const {'alumno-1': '2,0'},
    );
    expect(bien, isFalse);
    expect(await cola(), isEmpty);
    expect(await db.query('sorteos_mesas'), isEmpty);
  });

  test('un deshacer no lleva lugares: no se toca', () async {
    final deshacer = SorteoMesasRegistro(
      id: idDeshacer,
      eventoId: evento,
      tipo: TipoRegistroSorteo.deshacer,
      resultado: const {'alumno-1': '12, 13'},
      hechoPor: 'Jefe',
      createdAt: cuando.add(const Duration(hours: 1)),
    );
    await SorteosMesasRepository.registrarEn(db, deshacer);
    await yaSubio();
    final antes = await fila(idDeshacer);
    final bien = await SorteosMesasRepository.completarLugaresEn(
      db,
      idDeshacer,
      const {'alumno-1': '2,0'},
    );
    expect(bien, isFalse);
    expect(await fila(idDeshacer), antes);
    expect(await cola(), isEmpty);
  });

  test('un texto que no se puede leer no se reescribe', () async {
    await db.insert('sorteos_mesas', {
      ...sorteo().toMap(),
      'resultado': 'esto no es un json',
    });
    final bien =
        await SorteosMesasRepository.completarLugaresEn(db, idSorteo, const {});
    expect(bien, isFalse);
    expect((await fila(idSorteo))['resultado'], 'esto no es un json');
    expect(await cola(), isEmpty);
  });

  test('los otros renglones de la fiesta no cambian', () async {
    await SorteosMesasRepository.registrarEn(db, sorteo());
    final otro = SorteoMesasRegistro(
      id: idDeshacer,
      eventoId: evento,
      tipo: TipoRegistroSorteo.sorteo,
      resultado: const {'alumno-3': '20'},
      antes: const {},
      hechoPor: 'Jefe',
      createdAt: cuando.add(const Duration(days: 2)),
    );
    await SorteosMesasRepository.registrarEn(db, otro);
    await yaSubio();
    final antes = await fila(idDeshacer);
    await SorteosMesasRepository.completarLugaresEn(
      db,
      idSorteo,
      const {'alumno-1': '2,0'},
    );
    expect(await fila(idDeshacer), antes);
    expect((await cola()).single['registro_id'], idSorteo);
  });
}
