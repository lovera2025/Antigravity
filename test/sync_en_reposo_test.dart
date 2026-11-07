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
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/database/sync_queue.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';

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
    test('corre lo programado a su hora, y lo periódico una vez por vuelta', () {
      final reloj = RelojDePrueba();
      final corridas = <String>[];
      reloj.programar(const Duration(seconds: 2), () => corridas.add('a los 2 s'));
      final cada5 = reloj.periodico(const Duration(minutes: 5), () => corridas.add('red'));
      reloj.avanzar(const Duration(seconds: 1));
      expect(corridas, isEmpty);
      reloj.avanzar(const Duration(minutes: 11));
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
      reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.pedidas, isEmpty, reason: 'todavía no pasaron los 2 s');

      reloj.avanzar(const Duration(seconds: 1));
      await m.aquietar();
      expect(nube.pedidas, contains('POST pagos_contrato_alumno'));
      expect(await SyncQueue.pendingCount, 0);
      expect(m.ultimoPulsoArmado?['tablas'], ['pagos_contrato_alumno']);
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
      reloj.avanzar(const Duration(seconds: 3));
      await m.aquietar();
      expect(nube.pedidas, isEmpty);
      expect(await SyncQueue.pendingCount, 1);
    });
  });
}
