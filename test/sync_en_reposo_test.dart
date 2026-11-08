// El sync en reposo (6.3.3): la nube se toca solo cuando algo cambia.
//
// El plan: docs/PLAN_SYNC_EN_REPOSO_2026-11-06.md. Hasta la 6.3.2 cada PC le
// pedía a la nube unas 120 cosas por minuto aunque nadie tocara nada (el ciclo
// de 10 s). Estas pruebas cuentan, con un reloj que avanza a mano y una nube de
// mentira, qué pide el motor en cada momento.
//
// Corre contra una base SQLite temporal y una nube simulada: no sale nada de la
// PC.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/instalacion_id.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/mi_empresa/repositories/finanzas_repository.dart';

import 'helpers/nube_de_prueba.dart';
import 'helpers/reloj_de_prueba.dart';

const _alumno = '1308f6f9-ea42-4b73-a329-ca3080394a58';

Map<String, Object?> _pago(String id) => {
      'id': id,
      'contrato_alumno_id': _alumno,
      'fecha_pago': '2026-11-10T12:00:00+00:00',
      'created_at': '2026-11-10T12:00:00+00:00',
      'updated_at': '2026-11-10T12:00:00+00:00',
      'concepto': 'Cuota Base (1/9)',
      'monto': 35000,
      'monto_gross': 35000,
      'medio_pago': 'Efectivo',
      'anulado': 0,
    };

void main() {
  group('cuánto esperar para volver a intentar', () {
    test('30 s, 1, 2 y 5 minutos, y 5 minutos para siempre', () {
      expect(esperaCreciente(0), const Duration(seconds: 30));
      expect(esperaCreciente(1), const Duration(minutes: 1));
      expect(esperaCreciente(2), const Duration(minutes: 2));
      expect(esperaCreciente(3), const Duration(minutes: 5));
      expect(esperaCreciente(4), const Duration(minutes: 5));
      expect(esperaCreciente(500), const Duration(minutes: 5));
      expect(esperaCreciente(-1), const Duration(seconds: 30));
    });
  });

  group('si la nube no está o si rechazó lo que se mandó', () {
    test('sin red, sin respuesta o con la puerta caída: la nube no está', () {
      expect(esCaidaDeLaNube(const SocketException('Failed host lookup')), isTrue);
      expect(esCaidaDeLaNube(http.ClientException('Connection closed')), isTrue);
      expect(esCaidaDeLaNube(TimeoutException('3 s')), isTrue);
      // Lo que devolvió la puerta de entrada el 6-nov, con la base trabada.
      expect(esCaidaDeLaNube(const PostgrestException(message: 'Gateway Timeout', code: '504')), isTrue);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'x', code: '522')), isTrue);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'no db', code: 'PGRST001')), isTrue);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'timeout', code: '57014')), isTrue);
    });

    test('un rechazo de la fila no es una caída: la fila se queda en la cola', () {
      expect(esCaidaDeLaNube(const PostgrestException(message: 'duplicate key', code: '23505')), isFalse);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'violates foreign key', code: '23503')), isFalse);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'bad', code: '400')), isFalse);
      expect(esCaidaDeLaNube(const PostgrestException(message: 'JWT expired', code: 'PGRST301')), isFalse);
      expect(esCaidaDeLaNube(Exception('UUID_INVALIDO: el campo "id"')), isFalse);
    });
  });

  group('el reloj de prueba', () {
    test('corre lo programado a su hora, y lo periódico una vez por vuelta', () async {
      final reloj = RelojDePrueba();
      final corridas = <String>[];
      reloj.programar(const Duration(seconds: 2), () => corridas.add('a los 2 s'));
      final cada5 = reloj.periodico(const Duration(minutes: 5), () => corridas.add('red'));
      await reloj.avanzar(const Duration(seconds: 1));
      expect(corridas, isEmpty);
      await reloj.avanzar(const Duration(minutes: 11));
      expect(corridas, ['a los 2 s', 'red', 'red']);
      expect(reloj.pendientes, [const Duration(minutes: 3, seconds: 59)]);
      cada5.cancel();
      expect(reloj.pendientes, isEmpty);
    });
  });

  group('el motor con el reloj de prueba', () {
    late Directory docs;
    late NubeDePrueba nube;
    late RelojDePrueba reloj;
    late RedDePrueba red;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('sync_en_reposo');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      nube = NubeDePrueba();
      reloj = RelojDePrueba();
      red = RedDePrueba();
      await LocalDatabase.instance;
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    SyncEngine motor() {
      final cliente = nube.clienteSupabase();
      addTearDown(cliente.dispose);
      final m = SyncEngine(
        connectivity: red,
        supabase: cliente,
        reloj: reloj,
        conCanalDelPulso: false,
      );
      reloj.esperarAlMotor = m.aquietar;
      m.start();
      addTearDown(m.dispose);
      return m;
    }

    test('un cobro sube a los 2 s de guardarlo, con el reloj del motor', () async {
      final m = motor();
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'aaaaaaaa-0000-4000-8000-000000000001',
        payload: _pago('aaaaaaaa-0000-4000-8000-000000000001'),
      );
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.pedidas, isEmpty, reason: 'todavía no pasaron los 2 s');

      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.pedidas, contains('POST pagos_contrato_alumno'));
      expect(await SyncQueue.pendingCount, 0);
      expect(m.ultimoPulsoArmado?['tablas'], ['pagos_contrato_alumno']);
    });

    /// Lo que pide la red del cobro en una vuelta: cada tabla del cobro y la
    /// cuenta de pagos, alumnos y egresos.
    List<String> unaVueltaDelCobro() => [
          for (final t in SyncEngine.tablasDelCobro) 'GET $t',
          for (final t in SyncEngine.tablasQueSeCuentan) 'HEAD $t',
        ]..sort();

    List<String> ordenadas(List<String> l) => [...l]..sort();

    test('1. en reposo no le pide nada a la nube; a los 5 minutos, una vuelta '
        'de lo del cobro; a los 30, lo demás', () async {
      final m = motor();
      // El arranque: todo, la revisión de borrados y la de la mora.
      expect(await m.pullOperationalUpdates(), isTrue);
      await m.aquietar();
      final marca = nube.pedidas.length;

      // Ni la revisión de borrados de los 20 s (la hizo el arranque) ni nada.
      await reloj.avanzar(const Duration(minutes: 4, seconds: 30));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty, reason: 'en reposo, silencio');

      await reloj.avanzar(const Duration(minutes: 1));
      await m.aquietar();
      expect(ordenadas(nube.desde(marca)), unaVueltaDelCobro());

      final marca2 = nube.pedidas.length;
      // De los 5:30 a los 29:30: tres vueltas más del cobro (10, 15, 20, 25 min
      // son cuatro) y las revisiones de borrados de los 10 y los 20 minutos.
      await reloj.avanzar(const Duration(minutes: 24));
      await m.aquietar();
      final hasta29 = nube.desde(marca2);
      // `mora_congelada` la baja solo la red (la revisión de borrados no la
      // mira): una por vuelta, a los 10, 15, 20 y 25 minutos.
      expect(hasta29.where((p) => p == 'GET mora_congelada').length, 4);
      expect(
        // `planos_evento` es de carga y la revisión de borrados no la mira.
        hasta29.where((p) => p == 'GET planos_evento'),
        isEmpty,
        reason: 'lo de carga baja recién a los 30 minutos',
      );

      final marca3 = nube.pedidas.length;
      await reloj.avanzar(const Duration(minutes: 1));
      await m.aquietar();
      final a30 = nube.desde(marca3);
      for (final t in SyncEngine.tablasDeCarga) {
        expect(a30, contains('GET $t'), reason: '$t baja a los 30 minutos');
      }
      expect(red.despertares, 0,
          reason: 'sin el pedido de prueba antes de cada bajada (6.3.3)');
    });

    test('con la nube caída, la vuelta de la red pide una sola tabla y para; '
        'cuando vuelve, baja todo', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      await reloj.avanzar(const Duration(minutes: 4));
      await m.aquietar();

      nube.caida = true;
      final marca = nube.pedidas.length;
      await reloj.avanzar(const Duration(minutes: 1, seconds: 30));
      await m.aquietar();
      expect(nube.desde(marca), hasLength(1), reason: 'la primera tabla hace de ping');
      expect(m.status, SyncStatus.error);
      expect(m.lastError, 'Nube no disponible');

      nube.caida = false;
      final marca2 = nube.pedidas.length;
      await reloj.avanzar(const Duration(minutes: 5));
      await m.aquietar();
      // A los 10 minutos coincide con la revisión de borrados: se mira que
      // esté la vuelta entera del cobro.
      expect(nube.desde(marca2), containsAll(unaVueltaDelCobro()));
      expect(m.status, SyncStatus.idle);
    });

    test('con la nube caída, un cobro no se marca como fallido: se reintenta '
        'y sube cuando vuelve', () async {
      final m = motor();
      await reloj.avanzar(const Duration(seconds: 25));
      await m.aquietar();
      nube.caida = true;
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'acacacac-0000-4000-8000-000000000001',
        payload: _pago('acacacac-0000-4000-8000-000000000001'),
      );
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      expect(nube.pedidas.where((p) => p.startsWith('POST')), hasLength(1));
      final db = await LocalDatabase.instance;
      final fila = (await db.query('_sync_queue')).single;
      expect(fila['intentos'], 0,
          reason: 'no es culpa de la fila: no queda "trabada" por un corte largo');
      expect(reloj.esperasSueltas, [const Duration(seconds: 30)]);

      nube.caida = false;
      await reloj.avanzar(const Duration(seconds: 30));
      await m.aquietar();
      expect(await SyncQueue.pendingCount, 0);
      expect(m.status, SyncStatus.idle);
    });

    test('7. la proyección de Finanzas se invalida solo si bajó algo nuevo', () async {
      final m = motor();
      final avisos = <Set<String>>[];
      final sub = m.cambiosBajadosStream.listen(avisos.add);
      addTearDown(sub.cancel);
      expect(await m.bajarAlArrancar(), isTrue);
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      final antes = FinanzasRepository.vecesInvalidada;

      // Una vuelta sin novedades.
      await reloj.avanzar(const Duration(minutes: 5));
      await m.aquietar();
      expect(FinanzasRepository.vecesInvalidada, antes);
      expect(avisos, isEmpty, reason: 'nada nuevo: las pantallas no se rehacen');

      // Una vuelta con una caja nueva de la otra PC.
      nube.filas['sesiones_caja'] = [
        {
          'id': 'bcbcbcbc-0000-4000-8000-000000000001',
          'operador_id': 'bbbbbbbb-0000-4000-8000-000000000001',
          'abierta_at': '2026-11-10T13:00:00Z',
          'cambio_inicial': 0,
          'device_id': 'pc-del-jefe',
          'last_heartbeat': '2026-11-10T13:00:00Z',
          'created_at': '2026-11-10T13:00:00Z',
          'updated_at': '2026-11-10T13:00:00Z',
        },
      ];
      await reloj.avanzar(const Duration(minutes: 5));
      await m.aquietar();
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(FinanzasRepository.vecesInvalidada, antes + 1);
      expect(avisos, [
        {'sesiones_caja'},
      ]);
    });

    test('vuelve la red: sube lo que esperaba y baja lo del cobro', () async {
      final m = motor();
      expect(await m.pullOperationalUpdates(), isTrue);
      await m.aquietar();
      red.poner(AppConnectivity.offline);
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'aaaaaaaa-0000-4000-8000-000000000003',
        payload: _pago('aaaaaaaa-0000-4000-8000-000000000003'),
      );
      await reloj.avanzar(const Duration(seconds: 3));
      await m.aquietar();
      final marca = nube.pedidas.length;
      expect(await SyncQueue.pendingCount, 1);

      red.poner(AppConnectivity.online);
      await Future<void>.delayed(Duration.zero);
      await m.aquietar();
      final despues = nube.desde(marca);
      expect(despues.first, 'POST pagos_contrato_alumno', reason: 'primero sube');
      expect(despues, containsAll(unaVueltaDelCobro()));
      expect(await SyncQueue.pendingCount, 0);
    });

    test('la vuelta de la red no sale si alguien acaba de bajar todo', () async {
      final m = motor();
      await reloj.avanzar(const Duration(minutes: 4, seconds: 30));
      await m.aquietar();
      // Antes de cobrar se baja todo (refreshBeforePayment).
      expect(await m.pullOperationalUpdates(), isTrue);
      await m.aquietar();
      final marca = nube.pedidas.length;
      await reloj.avanzar(const Duration(seconds: 40));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty,
          reason: 'la de los 5 minutos se saltea: bajó todo hace 10 s');
    });

    test('sin internet no sale a la nube, y el cobro queda en la cola', () async {
      red.estado = AppConnectivity.offline;
      final m = motor();
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'aaaaaaaa-0000-4000-8000-000000000002',
        payload: _pago('aaaaaaaa-0000-4000-8000-000000000002'),
      );
      await reloj.avanzar(const Duration(seconds: 3));
      await m.aquietar();
      expect(nube.pedidas, isEmpty);
      expect(await SyncQueue.pendingCount, 1);
    });

    test('5. el campo: se abre la app sin internet, se cobra todo el día y al '
        'llegar a la oficina sube todo solo', () async {
      red.estado = AppConnectivity.offline;
      final m = motor();
      // Al abrir sin internet no baja nada (y no se queda reintentando).
      expect(await m.bajarAlArrancar(), isFalse);
      final cobros = [
        for (var i = 1; i <= 6; i++) 'cccccccc-0000-4000-8000-00000000000$i',
      ];
      for (final id in cobros) {
        await SyncQueue.enqueue(
          tabla: 'pagos_contrato_alumno',
          operacion: SyncOperation.insert,
          registroId: id,
          payload: _pago(id),
        );
        await reloj.avanzar(const Duration(minutes: 40));
      }
      await m.aquietar();
      expect(nube.pedidas, isEmpty, reason: 'sin internet no sale nada');
      expect(await SyncQueue.pendingCount, cobros.length,
          reason: 'los seis cobros esperan en la PC');

      // Llega a la oficina.
      red.poner(AppConnectivity.online);
      await Future<void>.delayed(Duration.zero);
      await m.aquietar();
      expect(
        nube.pedidas.where((p) => p == 'POST pagos_contrato_alumno').length,
        cobros.length,
      );
      expect(await SyncQueue.pendingCount, 0, reason: 'no queda nada en la cola');
      // Y como nunca había bajado nada, baja todo: lo del cobro y lo demás.
      for (final t in [...SyncEngine.tablasDelCobro, ...SyncEngine.tablasDeCarga]) {
        expect(nube.pedidas, contains('GET $t'));
      }
      // Lo único que puede quedar es la mirada de 2 s a la cola, que no sale a
      // la nube si no hay nada.
      final marca = nube.pedidas.length;
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      expect(reloj.esperasSueltas, isEmpty, reason: 'nada para reintentar');
      expect(nube.desde(marca), isEmpty);
    });

    test('6. lo que la nube no toma se reintenta a los 30 s, 1, 2 y 5 minutos, '
        'y cada 5 minutos para siempre; al subir, se termina', () async {
      final m = motor();
      // Que pase la primera revisión de borrados (a los 20 s de abrir).
      await reloj.avanzar(const Duration(seconds: 25));
      await m.aquietar();
      nube.fallan['POST pagos_contrato_alumno'] = 503;
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'dddddddd-0000-4000-8000-000000000001',
        payload: _pago('dddddddd-0000-4000-8000-000000000001'),
      );
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      int intentos() =>
          nube.pedidas.where((p) => p == 'POST pagos_contrato_alumno').length;
      expect(intentos(), 1);

      for (final (espera, n) in [
        (const Duration(seconds: 30), 2),
        (const Duration(minutes: 1), 3),
        (const Duration(minutes: 2), 4),
        (const Duration(minutes: 5), 5),
        (const Duration(minutes: 5), 6),
      ]) {
        expect(reloj.esperasSueltas, [espera]);
        await reloj.avanzar(espera - const Duration(seconds: 1));
        await m.aquietar();
        expect(intentos(), n - 1, reason: 'todavía no');
        await reloj.avanzar(const Duration(seconds: 1));
        await m.aquietar();
        expect(intentos(), n);
      }
      expect(await SyncQueue.pendingCount, 1, reason: 'nada se saca por fallar');

      // La nube vuelve a tomarlo.
      nube.fallan.clear();
      await reloj.avanzar(const Duration(minutes: 5));
      await m.aquietar();
      expect(intentos(), 7);
      expect(await SyncQueue.pendingCount, 0);
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      expect(reloj.esperasSueltas, isEmpty, reason: 'subió: no queda reintento');
    });

    test('si toca subir con el motor bajando, prueba de nuevo a los 3 s', () async {
      final m = motor();
      nube.frenadas['sesiones_caja'] = Completer<void>();
      final bajada = m.pullOperationalUpdates();
      await Future<void>.delayed(Duration.zero);
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'eeeeeeee-0000-4000-8000-000000000001',
        payload: _pago('eeeeeeee-0000-4000-8000-000000000001'),
      );
      await reloj.avanzar(const Duration(seconds: 2));
      expect(nube.pedidas, isNot(contains('POST pagos_contrato_alumno')));
      expect(reloj.esperasSueltas, contains(const Duration(seconds: 3)));

      nube.frenadas.remove('sesiones_caja')!.complete();
      // Que termine la bajada de verdad, sin un tiempo fijo: con la PC cargada,
      // 50 ms no alcanzaban.
      await bajada;
      await m.aquietar();
      await reloj.avanzar(const Duration(seconds: 3));
      await m.aquietar();
      expect(nube.pedidas, contains('POST pagos_contrato_alumno'));
      expect(await SyncQueue.pendingCount, 0);
    });

    test('al volver a la ventana baja lo del cobro, si pasó más de un minuto', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      final marca = nube.pedidas.length;

      await reloj.avanzar(const Duration(seconds: 30));
      expect(await m.bajarAlMirar(), isFalse, reason: 'bajó hace 30 s');
      expect(nube.desde(marca), isEmpty);

      await reloj.avanzar(const Duration(seconds: 40));
      expect(await m.bajarAlMirar(), isTrue);
      expect(ordenadas(nube.desde(marca)), [
        for (final t in SyncEngine.tablasDelCobro) 'GET $t',
      ]..sort());
    });

    Map<String, dynamic> aviso(List<String> tablas) => {
          'payload': {
            'origen': 'pc-del-jefe',
            'tablas': tablas,
            'borrados': <String, List<String>>{},
          },
        };

    test('3. un aviso que llega con la PC ocupada no se tira: se baja a los 3 s', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();

      // La PC está bajando (antes de cobrar) y se queda esperando a la nube.
      nube.frenadas['sesiones_caja'] = Completer<void>();
      final bajada = m.pullOperationalUpdates();
      await Future<void>.delayed(Duration.zero);
      final antesDelAviso = nube.pedidas.length;

      m.recibirPulso(aviso(['presupuestos']));
      await reloj.avanzar(const Duration(milliseconds: 400));
      expect(nube.desde(antesDelAviso), isNot(contains('GET presupuestos')),
          reason: 'está ocupada: no se pisa con otra bajada');
      expect(reloj.esperasSueltas, contains(const Duration(seconds: 3)));

      nube.frenadas.remove('sesiones_caja')!.complete();
      await bajada;
      final marca = nube.pedidas.length;
      await reloj.avanzar(const Duration(seconds: 3));
      await m.aquietar();
      expect(nube.desde(marca), ['GET presupuestos'],
          reason: 'hasta la 6.3.2 el aviso se tiraba y lo bajaba el ciclo de 10 s');
    });

    test('un aviso con la PC libre baja solo lo avisado, enseguida', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      final marca = nube.pedidas.length;
      m.recibirPulso(aviso(['pagos_contrato_alumno', 'contratos_alumnos']));
      await reloj.avanzar(const Duration(milliseconds: 400));
      await m.aquietar();
      expect(ordenadas(nube.desde(marca)),
          ['GET contratos_alumnos', 'GET pagos_contrato_alumno']);
      expect(m.status, SyncStatus.idle, reason: 'vuelve a quedar libre');
    });

    // Por el socket (lo normal) el aviso llega suelto, con `type` y `event` de
    // la librería; por REST, envuelto en `payload`. Hasta la 6.4.0 la PC leía
    // solo el envuelto y tiraba el del socket sin error
    // (docs/SPEC_pulso_por_el_socket_2026-11-07.md).
    Map<String, dynamic> porElSocket(Map<String, dynamic> datos) => {
          ...datos,
          'type': 'broadcast',
          'event': 'cambios',
        };

    test('un aviso por el socket baja solo lo avisado, enseguida', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      final marca = nube.pedidas.length;
      m.recibirPulso(porElSocket({
        'origen': 'pc-del-jefe',
        'tablas': ['pagos_contrato_alumno', 'contratos_alumnos'],
        'borrados': <String, List<String>>{},
      }));
      await reloj.avanzar(const Duration(milliseconds: 400));
      await m.aquietar();
      expect(ordenadas(nube.desde(marca)),
          ['GET contratos_alumnos', 'GET pagos_contrato_alumno'],
          reason: 'hasta la 6.4.0 el aviso del socket se tiraba');
    });

    test('el eco propio por el socket no baja nada', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      SharedPreferences.setMockInitialValues({'caja_device_id': 'esta-pc'});
      final yo = await InstalacionId.inicializar();
      final marca = nube.pedidas.length;
      m.recibirPulso(porElSocket({
        'origen': yo,
        'tablas': ['pagos_contrato_alumno'],
        'borrados': <String, List<String>>{},
      }));
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty);
    });

    test('lo que arma el pulso no lleva una clave payload', () async {
      final m = motor();
      await SyncQueue.enqueue(
        tabla: 'pagos_contrato_alumno',
        operacion: SyncOperation.insert,
        registroId: 'aaaaaaaa-0000-4000-8000-000000000002',
        payload: _pago('aaaaaaaa-0000-4000-8000-000000000002'),
      );
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      expect(m.ultimoPulsoArmado, isNotNull);
      expect(m.ultimoPulsoArmado!.containsKey('payload'), isFalse,
          reason: 'cuerpoDelBroadcast lo tomaría por la forma del REST');
    });

    test('un aviso que llega justo antes de quedarse sin red se baja al volver', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      // Que pase la primera revisión de borrados (a los 20 s de abrir).
      await reloj.avanzar(const Duration(seconds: 25));
      await m.aquietar();
      final marca = nube.pedidas.length;
      m.recibirPulso(aviso(['presupuestos']));
      red.poner(AppConnectivity.offline);
      await Future<void>.delayed(Duration.zero);
      await reloj.avanzar(const Duration(seconds: 10));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty);
      expect(reloj.esperasSueltas, isEmpty,
          reason: 'sin red no se queda reintentando');

      red.poner(AppConnectivity.online);
      await Future<void>.delayed(Duration.zero);
      await m.aquietar();
      expect(nube.desde(marca), contains('GET presupuestos'));
    });

    test('4. si el canal del aviso estuvo caído más de 20 s, al volver baja lo '
        'del cobro; si fueron 10 s, no', () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      // La primera conexión no es un corte.
      m.recibirEstadoDelCanal(RealtimeSubscribeStatus.subscribed);
      await m.aquietar();
      var marca = nube.pedidas.length;

      m.recibirEstadoDelCanal(RealtimeSubscribeStatus.channelError);
      await reloj.avanzar(const Duration(seconds: 10));
      m.recibirEstadoDelCanal(RealtimeSubscribeStatus.subscribed);
      await m.aquietar();
      expect(nube.desde(marca), isEmpty, reason: 'diez segundos no');

      await reloj.avanzar(const Duration(minutes: 2));
      marca = nube.pedidas.length;
      m.recibirEstadoDelCanal(RealtimeSubscribeStatus.timedOut);
      await reloj.avanzar(const Duration(seconds: 25));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty);
      m.recibirEstadoDelCanal(RealtimeSubscribeStatus.subscribed);
      await m.aquietar();
      expect(ordenadas(nube.desde(marca)), unaVueltaDelCobro(),
          reason: 'los avisos de esos 25 s se perdieron');
    });
  });

  group('2. el latido de la caja', () {
    late Directory docs;
    late NubeDePrueba nube;
    late RelojDePrueba reloj;
    late RedDePrueba red;
    const sesion = 'ffffffff-0000-4000-8000-000000000001';

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('sync_latido');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      nube = NubeDePrueba();
      reloj = RelojDePrueba();
      red = RedDePrueba();
      await LocalDatabase.instance;
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    SyncEngine motor() {
      final cliente = nube.clienteSupabase();
      addTearDown(cliente.dispose);
      final m = SyncEngine(
        connectivity: red,
        supabase: cliente,
        reloj: reloj,
        conCanalDelPulso: false,
      );
      reloj.esperarAlMotor = m.aquietar;
      m.start();
      addTearDown(m.dispose);
      return m;
    }

    Future<void> encolarLatido() => SyncQueue.enqueue(
          tabla: 'sesiones_caja',
          operacion: SyncOperation.update,
          registroId: sesion,
          payload: {
            'id': sesion,
            'last_heartbeat': '2026-11-10T15:05:00Z',
            'updated_at': '2026-11-10T15:05:00Z',
          },
        );

    test('el latido sube y avisa a la otra PC, marcado como "solo latido"', () async {
      final m = motor();
      await encolarLatido();
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      expect(nube.pedidas, contains('PATCH sesiones_caja'));
      expect(m.ultimoPulsoArmado?['tablas'], ['sesiones_caja']);
      expect(m.ultimoPulsoArmado?['latido'], isTrue);
    });

    test('8. un cobro, una entrega de entradas y una silla de la noche avisan '
        'normal, aunque suban con un latido', () async {
      final m = motor();
      await encolarLatido();
      for (final (tabla, id) in [
        ('barra_ventas', 'abababab-0000-4000-8000-000000000001'),
        ('entradas_retiro', 'abababab-0000-4000-8000-000000000002'),
        ('sillas_puerta', 'abababab-0000-4000-8000-000000000003'),
      ]) {
        await SyncQueue.enqueue(
          tabla: tabla,
          operacion: SyncOperation.insert,
          registroId: id,
          payload: {'id': id, 'updated_at': '2026-11-10T15:05:00Z'},
        );
      }
      await reloj.avanzar(const Duration(seconds: 2));
      await m.aquietar();
      final tablas = (m.ultimoPulsoArmado?['tablas'] as List).toSet();
      expect(tablas, containsAll(['barra_ventas', 'entradas_retiro', 'sillas_puerta']));
      expect(m.ultimoPulsoArmado?.containsKey('latido'), isFalse,
          reason: 'con algo más que el latido, la otra PC refresca las pantallas');
    }, skip: !SyncEngine.tablasQueSeBajan.contains('sillas_puerta')
        ? 'esta versión todavía no tiene las sillas de la noche'
        : false);

    test('la otra PC baja el latido sin refrescar las pantallas; un aviso '
        'normal sí las refresca', () async {
      final m = motor();
      final avisos = <Set<String>>[];
      final sub = m.cambiosBajadosStream.listen(avisos.add);
      addTearDown(sub.cancel);
      Map<String, Object?> fila(String latido) => {
            'id': sesion,
            'operador_id': 'bbbbbbbb-0000-4000-8000-000000000001',
            'abierta_at': '2026-11-10T13:00:00Z',
            'cambio_inicial': 0,
            'device_id': 'pc-del-jefe',
            'last_heartbeat': latido,
            'created_at': '2026-11-10T13:00:00Z',
            'updated_at': latido,
          };

      nube.filas['sesiones_caja'] = [fila('2026-11-10T15:05:00Z')];
      final marca = nube.pedidas.length;
      m.recibirPulso({
        'payload': {
          'origen': 'pc-del-jefe',
          'tablas': ['sesiones_caja'],
          'borrados': <String, List<String>>{},
          'latido': true,
        },
      });
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.desde(marca), ['GET sesiones_caja'], reason: 'baja solo eso');
      expect(avisos, isEmpty, reason: 'el latido no refresca las pantallas');

      nube.filas['sesiones_caja'] = [fila('2026-11-10T15:10:00Z')];
      m.recibirPulso({
        'payload': {
          'origen': 'pc-del-jefe',
          'tablas': ['sesiones_caja'],
          'borrados': <String, List<String>>{},
        },
      });
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(avisos, [
        {'sesiones_caja'},
      ], reason: 'abrir o cerrar la caja sí');
    });

    test('un latido por el socket baja sesiones_caja sin refrescar las pantallas',
        () async {
      final m = motor();
      final avisos = <Set<String>>[];
      final sub = m.cambiosBajadosStream.listen(avisos.add);
      addTearDown(sub.cancel);
      nube.filas['sesiones_caja'] = [
        {
          'id': sesion,
          'operador_id': 'bbbbbbbb-0000-4000-8000-000000000001',
          'abierta_at': '2026-11-10T13:00:00Z',
          'cambio_inicial': 0,
          'device_id': 'pc-del-jefe',
          'last_heartbeat': '2026-11-10T15:05:00Z',
          'created_at': '2026-11-10T13:00:00Z',
          'updated_at': '2026-11-10T15:05:00Z',
        },
      ];
      final marca = nube.pedidas.length;
      m.recibirPulso({
        'origen': 'pc-del-jefe',
        'tablas': ['sesiones_caja'],
        'borrados': <String, List<String>>{},
        'latido': true,
        'type': 'broadcast',
        'event': 'cambios',
      });
      await reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.desde(marca), ['GET sesiones_caja'],
          reason: 'hasta la 6.4.0 el latido del socket se tiraba');
      expect(avisos, isEmpty);
    });

    test('un "latido" que no es un true de verdad avisa normal', () {
      final t = trabajoDelPulso(
        {
          'origen': 'otra',
          'tablas': ['sesiones_caja'],
          'latido': 'true',
        },
        yo: 'esta',
        tablasConocidas: {'sesiones_caja'},
      );
      expect(t.soloLatido, isFalse);
    });
  });

  group('el coordinador ya no tiene reloj', () {
    test('no vuelve el ciclo de 10 s ni la subida por rol', () {
      final s = File('lib/features/common/widgets/operational_sync_coordinator.dart')
          .readAsStringSync();
      expect(s, isNot(contains('Timer.periodic')),
          reason: 'lo que corre solo vive en el motor (6.3.3)');
      expect(s, isNot(contains('pullOperationalUpdates')));
      expect(s, isNot(contains('flushPending')));
      expect(s, contains('cambiosBajadosStream'),
          reason: 'las pantallas se refrescan cuando bajó algo nuevo');
      expect(s, contains('bajarAlArrancar'));
      expect(s, contains('bajarAlMirar'));
    });
  });
}
