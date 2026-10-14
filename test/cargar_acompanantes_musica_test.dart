// El guardado de lo que vino en el Excel del delegado: todos juntos o ninguno,
// y del alumno solo acompañantes y música.
//
// Corre contra una base SQLite **temporal**: se redirige el directorio de
// documentos, así que `LocalDatabase` crea una data.db vacía ahí. Nunca se toca
// la base de producción.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';

const _ev = 'eeeeeeee-0000-4000-8000-000000000001';
const _c1 = 'c1000000-0000-4000-8000-000000000001';
const _c2 = 'c2000000-0000-4000-8000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late ContratosRepository repo;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('delegado');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    repo = ContratosRepository(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      ConnectivityService(),
    );
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<void> sembrar(String id, String nombre) async {
    final db = await LocalDatabase.instance;
    await db.insert('contratos_alumnos', {
      'id': id,
      'evento_id': _ev,
      'nombre_alumno': nombre,
      'monto_total_pactado': 360000,
      'saldo_deudor': 120000,
      'cuotas_pagadas': 6,
      'total_cuotas': 9,
      'numero_mesa': '12',
      'telefono': '3777000000',
      'curso_division': '6° A',
      'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
    });
  }

  Future<Map<String, Object?>> fila(String id) async {
    final db = await LocalDatabase.instance;
    return (await db.query(
      'contratos_alumnos',
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;
  }

  Future<List<Map<String, Object?>>> cola() async {
    final db = await LocalDatabase.instance;
    return db.query('_sync_queue', orderBy: 'registro_id');
  }

  test('carga acompañantes y música, y no toca nada más de la ficha', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    final antes = await fila(_c1);

    await repo.cargarAcompanantesYMusica({
      _c1: {
        'nombres_acompanantes': ['Marta Pérez', 'Hugo Pérez'],
        'cantidad_acompanantes': 2,
        'musica_elegida': 'Viva la vida',
      },
    });

    final despues = await fila(_c1);
    expect(jsonDecode(despues['nombres_acompanantes'] as String), [
      'Marta Pérez',
      'Hugo Pérez',
    ]);
    expect(despues['cantidad_acompanantes'], 2);
    expect(despues['musica_elegida'], 'Viva la vida');

    // Todo lo demás, columna por columna, quedó como estaba.
    const cargadas = {
      'nombres_acompanantes',
      'cantidad_acompanantes',
      'musica_elegida',
    };
    for (final columna in antes.keys.where((k) => !cargadas.contains(k))) {
      expect(despues[columna], antes[columna], reason: columna);
    }
  });

  test('lo que sube a la nube es solo eso', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    await repo.cargarAcompanantesYMusica({
      _c1: {'musica_elegida': 'Titanium'},
    });
    final pendiente = (await cola()).single;
    expect(pendiente['tabla'], 'contratos_alumnos');
    expect(pendiente['operacion'], 'update');
    expect(jsonDecode(pendiente['payload'] as String), {
      'id': _c1,
      'musica_elegida': 'Titanium',
    });
  });

  test('los acompañantes suben como una lista, no como texto', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    await repo.cargarAcompanantesYMusica({
      _c1: {
        'nombres_acompanantes': ['ACOSTA, MARTA'],
        'cantidad_acompanantes': 1,
      },
    });
    final payload =
        jsonDecode((await cola()).single['payload'] as String) as Map;
    // Con coma adentro y todo: es un elemento de la lista.
    expect(payload['nombres_acompanantes'], ['ACOSTA, MARTA']);
    expect(payload['cantidad_acompanantes'], 1);
  });

  test('no pisa lo que ya esperaba subir de ese alumno', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    // Un cambio anterior todavía en la cola, como el saldo después de un pago.
    await repo.actualizarContrato(_c1, {'saldo_deudor': 80000.0});
    await repo.cargarAcompanantesYMusica({
      _c1: {'musica_elegida': 'Titanium'},
    });
    final payload =
        jsonDecode((await cola()).single['payload'] as String) as Map;
    expect(payload['saldo_deudor'], 80000.0);
    expect(payload['musica_elegida'], 'Titanium');
    expect((await fila(_c1))['saldo_deudor'], 80000.0);
  });

  test('entran todos o ninguno', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    await sembrar(_c2, 'GOMEZ, LUIS');

    // El segundo trae una columna que no existe: la base lo rechaza a mitad
    // de camino, y el primero no puede quedar cargado.
    final db = await LocalDatabase.instance;
    await db.execute('''
      CREATE TRIGGER rompe_el_segundo BEFORE UPDATE ON contratos_alumnos
      WHEN NEW.id = '$_c2'
      BEGIN SELECT RAISE(ABORT, 'falla a propósito'); END
    ''');
    await expectLater(
      repo.cargarAcompanantesYMusica({
        _c1: {'musica_elegida': 'Titanium'},
        _c2: {'musica_elegida': 'Thunderstruck'},
      }),
      throwsA(anything),
    );
    expect((await fila(_c1))['musica_elegida'], isNull);
    expect((await fila(_c2))['musica_elegida'], isNull);
    expect(await cola(), isEmpty);
  });

  test('cualquier otro dato del alumno se rechaza, y no se guarda nada',
      () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    await sembrar(_c2, 'GOMEZ, LUIS');
    await expectLater(
      repo.cargarAcompanantesYMusica({
        _c1: {'musica_elegida': 'Titanium'},
        _c2: {'musica_elegida': 'X', 'nombre_alumno': 'OTRO NOMBRE'},
      }),
      throwsArgumentError,
    );
    expect((await fila(_c1))['musica_elegida'], isNull);
    expect((await fila(_c2))['nombre_alumno'], 'GOMEZ, LUIS');
    expect(await cola(), isEmpty);
  });

  test('sin nada para cargar no escribe ni encola', () async {
    await sembrar(_c1, 'PEREZ, JUAN');
    await repo.cargarAcompanantesYMusica({});
    await repo.cargarAcompanantesYMusica({_c1: {}});
    expect(await cola(), isEmpty);
  });
}
