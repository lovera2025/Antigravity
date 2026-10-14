// Marcar el ingreso de alguien de un evento masivo desde Recepción, tenga o no
// su fila en la lista de la puerta. Sobre una base temporal y sin red.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';

const _ev = 'eeeeeeee-0000-4000-8000-000000000009';
const _c1 = 'c1000000-0000-4000-8000-000000000001';

ContratoAlumno _alumno(String nombre, {List<int> mesas = const []}) =>
    ContratoAlumno(
      id: _c1,
      eventoId: _ev,
      nombreAlumno: nombre,
      cantidadAcompanantes: 1,
      nombresAcompanantes: const ['GÓMEZ, ANA'],
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

class _SinConexion extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
}

void main() {
  late Directory docs;
  late InvitadosRepository repo;
  final juan = idInvitadoPuerta(_c1, 0);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('ingresar_puerta');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    repo = InvitadosRepository(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      _SinConexion(),
    );
  });

  tearDown(() async {
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<List<Map<String, Object?>>> cola() async {
    final db = await LocalDatabase.instance;
    return db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['invitados']);
  }

  test('sin fila, la crea ya marcada; lo que sube no lleva mesa', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
      mesa: '12',
    );

    final filas = await repo.getLocalesByEvento(_ev);
    expect(filas, hasLength(1));
    expect(filas.single.id, juan);
    expect(filas.single.estadoIngreso, EstadoIngreso.ingresado);
    expect(filas.single.numeroMesa, isNull,
        reason: 'la mesa de la lista la pone el salón');

    final entrada = (await cola()).single;
    expect(entrada['operacion'], 'insert');
    final payload = jsonDecode(entrada['payload'] as String) as Map;
    expect(payload['estado_ingreso'], 'ingresado');
    expect(payload['nombre_completo'], 'PÉREZ, JUAN');
    expect(payload.containsKey('numero_mesa'), isFalse,
        reason: 'una PC atrasada no puede borrar ni cambiar una mesa de la nube');
  });

  test('con fila, la marca y no le toca ni el nombre ni la mesa', () async {
    await repo.aplicarListaPuerta(
      _ev,
      planListaPuerta(
        alumnos: [_alumno('PÉREZ, JUAN', mesas: [12])],
        existentes: [],
      ),
    );

    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'OTRO NOMBRE',
      mesa: '99',
    );

    final filas = await repo.getLocalesByEvento(_ev);
    expect(filas, hasLength(2));
    final j = filas.firstWhere((i) => i.id == juan);
    expect(j.estadoIngreso, EstadoIngreso.ingresado);
    expect(j.nombreCompleto, 'PÉREZ, JUAN');
    expect(j.numeroMesa, '12');

    // El alta del sorteo que todavía no subió lleva el ingreso adentro, y
    // conserva su mesa.
    final entrada = (await cola()).firstWhere((e) => e['registro_id'] == juan);
    expect(entrada['operacion'], 'insert');
    final payload = jsonDecode(entrada['payload'] as String) as Map;
    expect(payload['estado_ingreso'], 'ingresado');
    expect(payload['numero_mesa'], '12');
  });

  test('dos veces no duplica la fila ni la cola', () async {
    for (var i = 0; i < 2; i++) {
      await repo.ingresarDesdeLaPuerta(
        eventoId: _ev,
        id: juan,
        nombre: 'PÉREZ, JUAN',
      );
    }
    expect(await repo.getLocalesByEvento(_ev), hasLength(1));
    expect(await cola(), hasLength(1));
  });

  test('creada y desmarcada enseguida, el alta sigue en la cola', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
    );
    await repo.deshacerIngreso(juan);

    final entrada = (await cola()).single;
    expect(entrada['operacion'], 'insert',
        reason: 'si se perdiera el alta, la fila no llegaría nunca a la nube');
    final payload = jsonDecode(entrada['payload'] as String) as Map;
    expect(payload['estado_ingreso'], 'pendiente');
    expect(payload['evento_id'], _ev);
  });

  test('marcado antes del sorteo, el sorteo le pone la mesa y no le saca el '
      'ingreso', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
    );

    await repo.aplicarListaPuerta(
      _ev,
      planListaPuerta(
        alumnos: [_alumno('PÉREZ, JUAN', mesas: [12])],
        existentes: await repo.getLocalesByEvento(_ev),
      ),
    );

    final j = (await repo.getLocalesByEvento(_ev)).firstWhere((i) => i.id == juan);
    expect(j.numeroMesa, '12');
    expect(j.estadoIngreso, EstadoIngreso.ingresado);
  });

  // Sección 5: lo que el tótem que abre sin internet tiene que cuidar.
  test('sin internet, el ingreso queda entre los que esperan subir, y solo en '
      'su evento', () async {
    const otro = 'eeeeeeee-0000-4000-8000-00000000000a';
    await repo.ingresarDesdeLaPuerta(eventoId: _ev, id: juan, nombre: 'PÉREZ, JUAN');
    await repo.agregar(eventoId: otro, nombreCompleto: 'DE OTRA FIESTA');

    expect(await repo.idsSinSubir(_ev), {juan});
    expect(await repo.idsSinSubir(otro), hasLength(1));
    expect((await repo.idsSinSubir(otro)).contains(juan), isFalse);
  });
}
