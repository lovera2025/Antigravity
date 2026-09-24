// La lista de la puerta armada desde los alumnos: con su mesa, repetible, sin
// pisar ingresos y sin borrar nada.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/invitado.dart';

ContratoAlumno alumno(
  String id,
  String nombre, {
  String? mesa,
  List<String> acomp = const [],
}) => ContratoAlumno(
  id: id,
  eventoId: 'ev',
  nombreAlumno: nombre,
  cantidadAcompanantes: acomp.length,
  nombresAcompanantes: acomp,
  montoTotalPactado: 300000,
  saldoDeudor: 0,
  numeroMesa: mesa,
);

Invitado invitado(
  String id,
  String nombre, {
  String? mesa,
  EstadoIngreso estado = EstadoIngreso.pendiente,
}) => Invitado(
  id: id,
  eventoId: 'ev',
  nombreCompleto: nombre,
  dni: '',
  numeroMesa: mesa,
  estadoIngreso: estado,
);

void main() {
  group('texto de la mesa en la puerta', () {
    test('sin notas de planilla', () {
      expect(SalonMesas.textoMesasPuerta(alumno('a', 'A', mesa: '12, 13, 14')), '12-14');
      expect(SalonMesas.textoMesasPuerta(alumno('a', 'A', mesa: '7')), '7');
      expect(
        SalonMesas.textoMesasPuerta(alumno('a', 'A', mesa: '12, 13, 40')),
        '12-13 y 40',
      );
      expect(SalonMesas.textoMesasPuerta(alumno('a', 'A')), isNull);
    });
  });

  group('filas desde los alumnos', () {
    test('alumno y acompañantes con nombre, con la mesa del alumno', () {
      final filas = filasPuertaDesdeAlumnos([
        alumno('c1', 'PEREZ, JUAN', mesa: '12, 13', acomp: ['MAMÁ PEREZ', ' ', 'PAPÁ PEREZ']),
      ]);
      expect(filas.map((f) => f.nombre), ['PEREZ, JUAN', 'MAMÁ PEREZ', 'PAPÁ PEREZ']);
      expect(filas.map((f) => f.mesa).toSet(), {'12-13'});
      expect(filas.first.esAlumno, isTrue);
      expect(filas.map((f) => f.id).toSet(), hasLength(3));
    });

    test('los de baja no entran', () {
      final filas = filasPuertaDesdeAlumnos([alumno('c1', '[BAJA] PEREZ, JUAN')]);
      expect(filas, isEmpty);
    });

    test('los ids son siempre los mismos', () {
      final a = filasPuertaDesdeAlumnos([alumno('c1', 'X', acomp: ['Y'])]);
      final b = filasPuertaDesdeAlumnos([alumno('c1', 'X', acomp: ['Y'])]);
      expect(a.map((f) => f.id), b.map((f) => f.id));
      expect(a.first.id, hasLength(36));
    });
  });

  group('plan', () {
    final alumnos = [
      alumno('c1', 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']),
      alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
    ];

    test('primera vez: todo nuevo', () {
      final plan = planListaPuerta(alumnos: alumnos, existentes: []);
      expect(plan.nuevas, hasLength(3));
      expect(plan.aActualizar, isEmpty);
      expect(plan.hayCambios, isTrue);
    });

    test('si cambia el sorteo se actualiza la mesa, y el que ingresó sigue ingresado', () {
      final existentes = [
        invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '5', estado: EstadoIngreso.ingresado),
        invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        invitado(idInvitadoPuerta('c2', 0), 'GOMEZ, LUIS', mesa: '13'),
      ];
      final plan = planListaPuerta(alumnos: alumnos, existentes: existentes);
      expect(plan.nuevas, isEmpty);
      expect(plan.aActualizar.map((f) => f.nombre), ['PEREZ, JUAN']);
      expect(plan.iguales, 2);
      expect(plan.yaIngresados, 1);
    });

    test('lo cargado a mano o por CSV no se toca ni se cuenta', () {
      final plan = planListaPuerta(
        alumnos: alumnos,
        existentes: [invitado('11111111-2222-3333-4444-555555555555', 'TÍO INVITADO', mesa: '1')],
      );
      expect(plan.nuevas, hasLength(3));
      expect(plan.sobrantes, isEmpty);
    });

    test('un acompañante que se quitó queda como sobrante, no se borra', () {
      final existentes = [
        invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '12'),
        invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        invitado(idInvitadoPuerta('c1', 2), 'PRIMO PEREZ', mesa: '12'),
      ];
      final plan = planListaPuerta(alumnos: alumnos, existentes: existentes);
      expect(plan.sobrantes.map((i) => i.nombreCompleto), ['PRIMO PEREZ']);
    });
  });

  group('escritura (base temporal)', () {
    late Directory docs;
    late InvitadosRepository repo;
    const ev = 'eeeeeeee-0000-4000-8000-000000000001';

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('lista_puerta');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => docs.path,
          );
      repo = InvitadosRepository(
        SupabaseClient('http://localhost:1', 'anon-de-test'),
        ConnectivityService(),
      );
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    test('pasar dos veces no duplica, y no toca el ingreso', () async {
      final alumnos = [alumno('c1', 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ'])];
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: alumnos, existentes: await repo.getLocalesByEvento(ev)),
      );
      final db = await LocalDatabase.instance;
      await db.update(
        'invitados',
        {'estado_ingreso': 'ingresado'},
        where: 'id = ?',
        whereArgs: [idInvitadoPuerta('c1', 0)],
      );

      // Cambia el sorteo y se vuelve a pasar.
      final despues = [alumno('c1', 'PEREZ, JUAN', mesa: '20, 21', acomp: ['ANA PEREZ'])];
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: despues, existentes: await repo.getLocalesByEvento(ev)),
      );

      final filas = await repo.getLocalesByEvento(ev);
      expect(filas, hasLength(2));
      final juan = filas.firstWhere((i) => i.id == idInvitadoPuerta('c1', 0));
      expect(juan.numeroMesa, '20-21');
      expect(juan.estadoIngreso, EstadoIngreso.ingresado);
    });

    test('lo que sube de una fila nueva no lleva estado_ingreso', () async {
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: [alumno('c1', 'PEREZ, JUAN', mesa: '12')], existentes: []),
      );
      final db = await LocalDatabase.instance;
      final cola = await db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['invitados']);
      expect(cola, hasLength(1));
      final payload = jsonDecode(cola.single['payload'] as String) as Map;
      expect(payload.containsKey('estado_ingreso'), isFalse);
      expect(payload['numero_mesa'], '12');
    });
  });
}
