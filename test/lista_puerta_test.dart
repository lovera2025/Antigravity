// La lista de la puerta armada desde los alumnos: con su mesa, repetible, sin
// pisar ingresos y sin borrar nada.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/services/salon_mesas.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/features/recepcion/services/puerta_al_dia.dart';
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

  test('la lista de la puerta está habilitada: sigue al sorteo', () {
    // Estuvo trabada hasta el 13-oct-2026. Desde la 6.0.0 se arma sola al
    // sortear y se vacía sola al deshacer; si esta bandera se apaga, el sorteo
    // deja de llegar a Recepción y al tótem.
    expect(
      kListaPuertaHabilitada,
      isTrue,
      reason: 'Con la lista trabada, el sorteo no llega a Recepción ni al '
          'tótem. Apagarla es una decisión del usuario, no un descuido.',
    );
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

    test('un acompañante que se quitó sobra, y se saca', () {
      final existentes = [
        invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '12'),
        invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        invitado(idInvitadoPuerta('c1', 2), 'PRIMO PEREZ', mesa: '12'),
      ];
      final plan = planListaPuerta(alumnos: alumnos, existentes: existentes);
      expect(plan.sobrantes.map((i) => i.nombreCompleto), ['PRIMO PEREZ']);
      expect(plan.hayCambios, isTrue);
      expect(plan.sinSorteo, isFalse);
    });

    test('un alumno que pasó a baja sale de la lista, con su familia', () {
      final existentes = [
        invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '12'),
        invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        invitado(idInvitadoPuerta('c2', 0), 'GOMEZ, LUIS', mesa: '13'),
      ];
      final plan = planListaPuerta(
        alumnos: [
          alumno('c1', '[BAJA] PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']),
          alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
        ],
        existentes: existentes,
      );
      expect(
        plan.sobrantes.map((i) => i.nombreCompleto),
        unorderedEquals(['PEREZ, JUAN', 'ANA PEREZ']),
      );
      expect(plan.iguales, 1);
    });

    test('un alumno sin mesa, con la fiesta sorteada, va igual: sin mesa', () {
      final plan = planListaPuerta(
        alumnos: [...alumnos, alumno('c3', 'SOSA, LUZ')],
        existentes: [],
      );
      final sosa = plan.nuevas.firstWhere((f) => f.nombre == 'SOSA, LUZ');
      expect(sosa.mesa, isNull);
      expect(plan.sinSorteo, isFalse);
    });
  });

  // Lo que pidió el usuario el 13-oct-2026: se sortea y aparece en Recepción y
  // en el tótem; se deshace y no aparece nada.
  group('la puerta sigue al sorteo', () {
    final sinMesa = [
      alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ']),
      alumno('c2', 'GOMEZ, LUIS'),
    ];
    final yaPasados = [
      invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '12'),
      invitado(
        idInvitadoPuerta('c1', 1),
        'ANA PEREZ',
        mesa: '12',
        estado: EstadoIngreso.ingresado,
      ),
      invitado(idInvitadoPuerta('c2', 0), 'GOMEZ, LUIS', mesa: '13'),
    ];

    test('sin sortear no va nadie a la lista', () {
      final plan = planListaPuerta(alumnos: sinMesa, existentes: []);
      expect(plan.sinSorteo, isTrue);
      expect(plan.nuevas, isEmpty);
      expect(plan.hayCambios, isFalse);
      expect(plan.personas, 0);
    });

    test('al deshacer el sorteo entero se sacan todos los que salieron de los '
        'alumnos', () {
      final plan = planListaPuerta(alumnos: sinMesa, existentes: yaPasados);
      expect(plan.sinSorteo, isTrue);
      expect(plan.sobrantes, hasLength(3));
      expect(plan.nuevas, isEmpty);
      expect(plan.aActualizar, isEmpty);
      expect(plan.personas, 0);
      expect(plan.hayCambios, isTrue);
      // El aviso de Deshacer lo tiene que decir antes, con el número.
      expect(plan.adentroQueSeVan, 1);
    });

    test('al deshacer no se toca lo que alguien cargó a mano', () {
      final aMano =
          invitado('11111111-2222-3333-4444-555555555555', 'DJ INVITADO');
      final plan = planListaPuerta(
        alumnos: sinMesa,
        existentes: [...yaPasados, aMano],
      );
      expect(plan.sobrantes.map((i) => i.id), isNot(contains(aMano.id)));
      expect(plan.sobrantes, hasLength(3));
    });

    test('si los únicos con mesa son alumnos de baja, la fiesta no está '
        'sorteada', () {
      final plan = planListaPuerta(
        alumnos: [
          alumno('c1', '[BAJA] PEREZ, JUAN', mesa: '12'),
          alumno('c2', 'GOMEZ, LUIS'),
        ],
        existentes: [],
      );
      expect(plan.sinSorteo, isTrue);
      expect(plan.nuevas, isEmpty);
    });

    test('al deshacer solo a algunos, la lista queda con los que siguen con '
        'mesa y con los demás sin mesa', () {
      final plan = planListaPuerta(
        alumnos: [
          alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ']),
          alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
        ],
        existentes: yaPasados,
      );
      expect(plan.sinSorteo, isFalse);
      expect(plan.sobrantes, isEmpty);
      expect(
        plan.aActualizar.map((f) => f.nombre),
        unorderedEquals(['PEREZ, JUAN', 'ANA PEREZ']),
      );
      expect(plan.aActualizar.every((f) => f.mesa == null), isTrue);
      expect(plan.personas, 3);
    });
  });

  // Editar a un alumno corrige sus filas, y nada más.
  group('el plan de unos alumnos solos', () {
    final alumnos = [
      alumno('c1', 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']),
      alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
    ];
    final existentes = [
      invitado(idInvitadoPuerta('c1', 0), 'PEREZ, JUAN', mesa: '12'),
      invitado(idInvitadoPuerta('c2', 0), 'GOMES, LUIS', mesa: '99'),
    ];

    test('solo toca las filas de esos alumnos', () {
      final plan = planListaPuerta(
        alumnos: alumnos,
        existentes: existentes,
        soloDe: {'c1'},
      );
      // A PEREZ le falta su acompañante; lo de GOMEZ, aunque esté mal, no es
      // de este cambio.
      expect(plan.nuevas.map((f) => f.nombre), ['ANA PEREZ']);
      expect(plan.aActualizar, isEmpty);
      expect(plan.sobrantes, isEmpty);
    });

    test('saca al acompañante que se le quitó a ese alumno', () {
      final plan = planListaPuerta(
        alumnos: [
          alumno('c1', 'PEREZ, JUAN', mesa: '12'),
          alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
        ],
        existentes: [
          ...existentes,
          invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        ],
        soloDe: {'c1'},
      );
      expect(plan.sobrantes.map((i) => i.nombreCompleto), ['ANA PEREZ']);
    });

    test('nunca vacía: en una PC donde nadie tiene mesa no hace nada', () {
      // Una PC que todavía no bajó el sorteo no puede sacar a una familia de
      // la puerta por editar un teléfono.
      final plan = planListaPuerta(
        alumnos: [
          alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ']),
          alumno('c2', 'GOMEZ, LUIS'),
        ],
        existentes: [
          ...existentes,
          invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        ],
        soloDe: {'c1'},
      );
      expect(plan.hayCambios, isFalse);
      expect(plan.sobrantes, isEmpty);
      expect(plan.sinSorteo, isTrue);
    });
  });

  group('lo que se muestra antes de pasar la lista a mano', () {
    test('dice cuántos se sacan y cuántos de ellos estaban adentro', () {
      final plan = planListaPuerta(
        alumnos: [alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ'])],
        existentes: [
          invitado(
            idInvitadoPuerta('c1', 0),
            'PEREZ, JUAN',
            mesa: '12',
            estado: EstadoIngreso.ingresado,
          ),
          invitado(idInvitadoPuerta('c1', 1), 'ANA PEREZ', mesa: '12'),
        ],
      );
      final renglones = renglonesPlanPuerta(plan, conConexion: true);
      expect(renglones, hasLength(1));
      expect(renglones.single, contains('2 se sacan de la lista'));
      expect(renglones.single, contains('ya nadie tiene mesa'));
      expect(renglones.single, contains('1 de ellos'));
    });

    test('sin conexión lo avisa', () {
      final plan = planListaPuerta(
        alumnos: [alumno('c1', 'PEREZ, JUAN', mesa: '12')],
        existentes: [],
      );
      expect(
        renglonesPlanPuerta(plan, conConexion: false).last,
        contains('Sin conexión'),
      );
      expect(
        renglonesPlanPuerta(plan, conConexion: true).join(),
        isNot(contains('Sin conexión')),
      );
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

    /// Deja la cola como si lo guardado ya hubiera subido.
    Future<void> yaSubio() async {
      final db = await LocalDatabase.instance;
      await db.delete('_sync_queue');
    }

    Future<List<Map<String, Object?>>> cola() async {
      final db = await LocalDatabase.instance;
      return db.query('_sync_queue', where: 'tabla = ?', whereArgs: ['invitados']);
    }

    test('al deshacer el sorteo la lista se vacía, y cada baja queda para '
        'subir', () async {
      final sorteados = [
        alumno('c1', 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']),
        alumno('c2', 'GOMEZ, LUIS', mesa: '13'),
      ];
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: sorteados, existentes: []),
      );
      expect(await repo.getLocalesByEvento(ev), hasLength(3));
      await yaSubio();

      final deshecho = [
        alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ']),
        alumno('c2', 'GOMEZ, LUIS'),
      ];
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: deshecho,
          existentes: await repo.getLocalesByEvento(ev),
        ),
      );

      expect(await repo.getLocalesByEvento(ev), isEmpty);
      final pendientes = await cola();
      expect(pendientes, hasLength(3));
      expect(pendientes.map((r) => r['operacion']).toSet(), {'delete'});
      expect(
        pendientes.map((r) => r['registro_id']).toSet(),
        {
          idInvitadoPuerta('c1', 0),
          idInvitadoPuerta('c1', 1),
          idInvitadoPuerta('c2', 0),
        },
      );
    });

    test('al deshacer no se toca lo cargado a mano en esa lista', () async {
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: [alumno('c1', 'PEREZ, JUAN', mesa: '12')],
          existentes: [],
        ),
      );
      final db = await LocalDatabase.instance;
      const aMano = '11111111-2222-4333-8444-555555555555';
      await db.insert('invitados', {
        'id': aMano,
        'evento_id': ev,
        'nombre_completo': 'DJ INVITADO',
        'dni': '30111222',
        'estado_ingreso': 'pendiente',
        'intentos_fallidos': 0,
      });
      await yaSubio();

      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: [alumno('c1', 'PEREZ, JUAN')],
          existentes: await repo.getLocalesByEvento(ev),
        ),
      );

      final quedan = await repo.getLocalesByEvento(ev);
      expect(quedan.map((i) => i.id), [aMano]);
      expect((await cola()).map((r) => r['registro_id']), [
        idInvitadoPuerta('c1', 0),
      ]);
    });

    test('sortear y deshacer antes de que suba no deja nada para subir',
        () async {
      // La fila nunca llegó a la nube: el alta y la baja se anulan en la cola.
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: [alumno('c1', 'PEREZ, JUAN', mesa: '12')],
          existentes: [],
        ),
      );
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: [alumno('c1', 'PEREZ, JUAN')],
          existentes: await repo.getLocalesByEvento(ev),
        ),
      );
      expect(await repo.getLocalesByEvento(ev), isEmpty);
      expect(await cola(), isEmpty);
    });

    test('deshacer y restaurar vuelve a dejar la lista, con las mismas filas',
        () async {
      final sorteados = [alumno('c1', 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ'])];
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: sorteados, existentes: []),
      );
      final antes = (await repo.getLocalesByEvento(ev)).map((i) => i.id).toSet();
      await yaSubio();
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: [alumno('c1', 'PEREZ, JUAN', acomp: ['ANA PEREZ'])],
          existentes: await repo.getLocalesByEvento(ev),
        ),
      );
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(
          alumnos: sorteados,
          existentes: await repo.getLocalesByEvento(ev),
        ),
      );
      final despues = await repo.getLocalesByEvento(ev);
      expect(despues.map((i) => i.id).toSet(), antes);
      expect(despues.map((i) => i.numeroMesa).toSet(), {'12'});
      // La baja que esperaba subir se convierte en el alta de la misma fila.
      expect((await cola()).map((r) => r['operacion']).toSet(), {'insert'});
    });

    test('un plan sin nada para hacer no escribe ni encola', () async {
      await repo.aplicarListaPuerta(
        ev,
        planListaPuerta(alumnos: [alumno('c1', 'PEREZ, JUAN')], existentes: []),
      );
      expect(await repo.getLocalesByEvento(ev), isEmpty);
      expect(await cola(), isEmpty);
    });
  });

  // El servicio que usan las pantallas: lee los alumnos y la lista de esta PC,
  // compara y escribe. Con los repositorios de verdad, sobre una base temporal.
  group('la puerta al día (base temporal)', () {
    late Directory docs;
    late InvitadosRepository invitados;
    late ContratosRepository contratos;
    late PuertaAlDia puerta;
    const ev = 'eeeeeeee-0000-4000-8000-000000000002';
    const c1 = 'c1000000-0000-4000-8000-000000000001';
    const c2 = 'c2000000-0000-4000-8000-000000000002';

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('puerta_al_dia');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => docs.path,
          );
      final supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
      final conexion = _SinConexion();
      invitados = InvitadosRepository(supabase, conexion);
      contratos = ContratosRepository(supabase, conexion);
      puerta = PuertaAlDia(contratos, invitados, conexion);
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    Future<void> sembrar(
      String id,
      String nombre, {
      String? mesa,
      List<String> acomp = const [],
    }) async {
      final db = await LocalDatabase.instance;
      await db.insert('contratos_alumnos', {
        'id': id,
        'evento_id': ev,
        'nombre_alumno': nombre,
        'monto_total_pactado': 300000,
        'saldo_deudor': 0,
        'cantidad_acompanantes': acomp.length,
        'nombres_acompanantes': jsonEncode(acomp),
        'numero_mesa': mesa,
        'created_at': DateTime.utc(2026, 3, 30, 12).toIso8601String(),
      });
    }

    Future<void> ponerMesa(String id, String? mesa) async {
      final db = await LocalDatabase.instance;
      await db.update(
        'contratos_alumnos',
        {'numero_mesa': mesa},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    test('sortear arma la lista; deshacer la vacía; restaurar la devuelve',
        () async {
      await sembrar(c1, 'PEREZ, JUAN', acomp: ['ANA PEREZ']);
      await sembrar(c2, 'GOMEZ, LUIS');

      // Antes del sorteo no hay nada, y no hay nada que decir.
      var r = await puerta.trasElSalon(ev);
      expect(r.sinSorteo, isTrue);
      expect(r.renglon, isEmpty);
      expect(await invitados.getLocalesByEvento(ev), isEmpty);

      // Se sortea.
      await ponerMesa(c1, '12');
      await ponerMesa(c2, '13');
      r = await puerta.trasElSalon(ev);
      expect(r.fallo, isFalse);
      expect(r.personas, 3);
      expect(
        r.renglon,
        'Recepción y el tótem ya tienen la lista: 3 persona(s)',
      );
      final lista = await invitados.getLocalesByEvento(ev);
      expect(lista, hasLength(3));
      expect(
        lista.firstWhere((i) => i.nombreCompleto == 'ANA PEREZ').numeroMesa,
        '12',
      );

      // Alguien entra, y se deshace el sorteo entero.
      await invitados.marcarIngreso(idInvitadoPuerta(c1, 0));
      expect(await puerta.adentro(ev), 1);
      await ponerMesa(c1, null);
      await ponerMesa(c2, null);
      r = await puerta.trasElSalon(ev);
      expect(r.sinSorteo, isTrue);
      expect(r.sacadas, 3);
      expect(
        r.renglon,
        'Recepción y el tótem quedaron sin la lista de esta fiesta',
      );
      expect(await invitados.getLocalesByEvento(ev), isEmpty);
      expect(await puerta.adentro(ev), 0);

      // Se restaura.
      await ponerMesa(c1, '12');
      await ponerMesa(c2, '13');
      r = await puerta.trasElSalon(ev);
      expect(r.personas, 3);
      expect(await invitados.getLocalesByEvento(ev), hasLength(3));
    });

    test('una mesa cambiada llega a la puerta sin tocar el ingreso', () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']);
      await puerta.trasElSalon(ev);
      await invitados.marcarIngreso(idInvitadoPuerta(c1, 1));

      await ponerMesa(c1, '30');
      final r = await puerta.trasElSalon(ev);
      expect(r.personas, 2);
      final lista = await invitados.getLocalesByEvento(ev);
      expect(lista.map((i) => i.numeroMesa).toSet(), {'30'});
      expect(
        lista.firstWhere((i) => i.id == idInvitadoPuerta(c1, 1)).estadoIngreso,
        EstadoIngreso.ingresado,
      );
    });

    test('cambiarle los acompañantes a uno corrige solo sus filas', () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']);
      await sembrar(c2, 'GOMEZ, LUIS', mesa: '13');
      await puerta.trasElSalon(ev);

      final db = await LocalDatabase.instance;
      await db.update(
        'contratos_alumnos',
        {
          'nombres_acompanantes': jsonEncode(['HUGO PEREZ', 'MARTA PEREZ']),
          'cantidad_acompanantes': 2,
        },
        where: 'id = ?',
        whereArgs: [c1],
      );
      final r = await puerta.trasLosAlumnos(ev, [c1]);
      expect(r.fallo, isFalse);
      final lista = await invitados.getLocalesByEvento(ev);
      expect(
        lista.map((i) => i.nombreCompleto),
        unorderedEquals(
          ['PEREZ, JUAN', 'HUGO PEREZ', 'MARTA PEREZ', 'GOMEZ, LUIS'],
        ),
      );
    });

    test('dar de baja a un alumno lo saca con su familia; al reincorporarlo '
        'vuelve', () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']);
      await sembrar(c2, 'GOMEZ, LUIS', mesa: '13');
      await puerta.trasElSalon(ev);

      final db = await LocalDatabase.instance;
      Future<void> nombrar(String nombre) => db.update(
            'contratos_alumnos',
            {'nombre_alumno': nombre},
            where: 'id = ?',
            whereArgs: [c1],
          );

      await nombrar('[BAJA] PEREZ, JUAN');
      var r = await puerta.trasLosAlumnos(ev, [c1]);
      expect(r.sacadas, 2);
      expect(
        (await invitados.getLocalesByEvento(ev)).map((i) => i.nombreCompleto),
        ['GOMEZ, LUIS'],
      );

      await nombrar('PEREZ, JUAN');
      r = await puerta.trasLosAlumnos(ev, [c1]);
      expect(r.sacadas, 0);
      expect(await invitados.getLocalesByEvento(ev), hasLength(3));
    });

    test('un alumno eliminado se lleva sus filas, y solo las suyas', () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']);
      await sembrar(c2, 'GOMEZ, LUIS', mesa: '13');
      await puerta.trasElSalon(ev);

      final db = await LocalDatabase.instance;
      await db.delete('contratos_alumnos', where: 'id = ?', whereArgs: [c1]);
      final r = await puerta.trasEliminar(ev, c1);
      expect(r.fallo, isFalse);
      expect(r.sacadas, 2);
      expect(
        (await invitados.getLocalesByEvento(ev)).map((i) => i.nombreCompleto),
        ['GOMEZ, LUIS'],
      );
      // Sin eso quedaban para siempre: ya no hay alumno del que salgan.
      expect((await puerta.trasElSalon(ev)).sacadas, 0);
    });

    test('un alumno que se anota con la fiesta ya sorteada entra sin mesa',
        () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12');
      await puerta.trasElSalon(ev);
      await sembrar(c2, 'GOMEZ, LUIS');
      final r = await puerta.trasLosAlumnos(ev, [c2]);
      expect(r.fallo, isFalse);
      final gomez = (await invitados.getLocalesByEvento(ev))
          .firstWhere((i) => i.nombreCompleto == 'GOMEZ, LUIS');
      expect(gomez.numeroMesa, isNull);
    });

    test('en una PC que todavía no bajó el sorteo, editar a un alumno no saca '
        'a nadie de la puerta', () async {
      await sembrar(c1, 'PEREZ, JUAN', mesa: '12', acomp: ['ANA PEREZ']);
      await puerta.trasElSalon(ev);
      // Esta PC queda como si no hubiera bajado las mesas.
      await ponerMesa(c1, null);

      final r = await puerta.trasLosAlumnos(ev, [c1]);
      expect(r.sacadas, 0);
      expect(r.renglon, isEmpty);
      expect(await invitados.getLocalesByEvento(ev), hasLength(2));
    });
  });
}

/// Sin red: el servicio no intenta bajar la lista de la nube.
class _SinConexion extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
}
