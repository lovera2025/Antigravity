// Una app con la v83 (el stock por barra) contra una nube que todavía no tiene
// esas dos tablas: su SQL (`supabase/migrations/20261125120000_barra_stock.sql`)
// no se corrió. Es el APK de prueba de la tele del 26-nov: la app de verdad, con
// la cuenta del jefe, antes de publicar.
//
// Lo que tiene que pasar: **todo lo demás baja igual**. Las dos tablas que faltan
// quedan nombradas en "No bajaron: …" y no se las toma por una nube caída (que
// cortaría la pasada).
//
// Corre contra una base SQLite temporal y una nube simulada: no sale nada de la
// PC.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/sync_engine.dart';

import 'helpers/nube_de_prueba.dart';
import 'helpers/reloj_de_prueba.dart';

const _stock = ['barra_stock_barras', 'barra_stock_movimientos'];

Map<String, Object?> _caja(String id, String updatedAt) => {
      'id': id,
      'operador_id': 'bbbbbbbb-0000-4000-8000-000000000001',
      'abierta_at': '2026-11-10T13:00:00Z',
      'cambio_inicial': 0,
      'device_id': 'pc-del-jefe',
      'last_heartbeat': '2026-11-10T13:00:00Z',
      'created_at': '2026-11-10T13:00:00Z',
      'updated_at': updatedAt,
    };

void main() {
  test('lo que contesta la nube por una tabla que no tiene no es una caída', () {
    // PostgREST 12 en adelante; antes era el 42P01 de Postgres.
    expect(
      esCaidaDeLaNube(const PostgrestException(
        message: "Could not find the table 'public.barra_stock_barras' in the schema cache",
        code: 'PGRST205',
      )),
      isFalse,
    );
    expect(
      esCaidaDeLaNube(const PostgrestException(
        message: 'relation "public.barra_stock_barras" does not exist',
        code: '42P01',
      )),
      isFalse,
    );
  });

  group('la nube sin las tablas del stock', () {
    late Directory docs;
    late NubeDePrueba nube;
    late RelojDePrueba reloj;
    late RedDePrueba red;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('nube_sin_stock');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
      nube = NubeDePrueba()..faltan.addAll(_stock);
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

    Future<List<String>> cajasAca() async {
      final db = await LocalDatabase.instance;
      return [
        for (final f in await db.query('sesiones_caja', orderBy: 'id'))
          f['id'] as String,
      ];
    }

    test('al abrir, baja todas las demás tablas y nombra solo las dos que faltan',
        () async {
      nube.filas['sesiones_caja'] = [
        _caja('bcbcbcbc-0000-4000-8000-000000000001', '2026-11-10T13:00:00Z'),
      ];
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue,
          reason: 'corrió: no queda reintentando el arranque');
      await m.aquietar();

      final pedidas = nube.pedidas.toSet();
      for (final t in [...SyncEngine.tablasDelCobro, ...SyncEngine.tablasDeCarga]) {
        expect(pedidas, contains('GET $t'), reason: '$t se pidió');
      }
      expect(await cajasAca(), ['bcbcbcbc-0000-4000-8000-000000000001'],
          reason: 'lo que hay en las tablas que sí existen, guardado acá');
      expect(m.status, SyncStatus.error);
      expect(m.lastError, 'No bajaron: barra_stock_barras, barra_stock_movimientos',
          reason: 'nombra las que faltan, y ninguna otra');
      expect(reloj.esperasSueltas, isNot(contains(const Duration(seconds: 30))),
          reason: 'no reintenta el arranque como si la nube no estuviera');
    });

    test('en reposo, silencio; la red de 5 minutos trae lo nuevo de las demás',
        () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      // Con una tabla sin bajar, el arranque no hace la revisión de borrados ni
      // la de la mora (las dos esperan una bajada entera): la de borrados la hace
      // la de los 20 s, como cuando la app abre sin internet.
      final antesDeLos20 = nube.pedidas.length;
      await reloj.avanzar(const Duration(seconds: 30));
      await m.aquietar();
      expect(nube.desde(antesDeLos20), contains('HEAD pagos_contrato_alumno'),
          reason: 'la revisión de borrados de los 20 s');
      final marca = nube.pedidas.length;

      await reloj.avanzar(const Duration(minutes: 4));
      await m.aquietar();
      expect(nube.desde(marca), isEmpty,
          reason: 'una tabla que falta no deja al motor pidiendo de más');

      nube.filas['sesiones_caja'] = [
        _caja('bcbcbcbc-0000-4000-8000-000000000002', '2026-11-10T15:00:00Z'),
      ];
      await reloj.avanzar(const Duration(minutes: 1));
      await m.aquietar();
      final vuelta = nube.desde(marca).toSet();
      for (final t in SyncEngine.tablasDelCobro) {
        expect(vuelta, contains('GET $t'), reason: '$t en la vuelta del cobro');
      }
      expect(await cajasAca(), ['bcbcbcbc-0000-4000-8000-000000000002']);
      expect(m.lastError, 'No bajaron: barra_stock_barras, barra_stock_movimientos');
    });

    test('un aviso de otro equipo que nombra una tabla del stock baja igual lo demás',
        () async {
      final m = motor();
      expect(await m.bajarAlArrancar(), isTrue);
      await m.aquietar();
      nube.filas['sesiones_caja'] = [
        _caja('bcbcbcbc-0000-4000-8000-000000000003', '2026-11-10T16:00:00Z'),
      ];
      final marca = nube.pedidas.length;
      m.recibirPulso({
        'payload': {
          'origen': 'pc-del-jefe',
          'tablas': ['barra_stock_movimientos', 'sesiones_caja'],
          'borrados': <String, List<String>>{},
        },
      });
      await reloj.avanzar(const Duration(milliseconds: 400));
      await m.aquietar();
      expect(nube.desde(marca).toSet(),
          {'GET barra_stock_movimientos', 'GET sesiones_caja'});
      expect(await cajasAca(), ['bcbcbcbc-0000-4000-8000-000000000003']);
      expect(m.lastError, 'No bajaron: barra_stock_movimientos');
    });

    test('"Lista para trabajar sin internet" queda lista: no necesita el stock',
        () async {
      final m = motor();
      expect(await m.bajarParaLaPuerta(), isTrue,
          reason: 'las tablas de la puerta están todas en la nube; si alguien '
              'les suma las del stock, la tele y la puerta no quedan listas '
              'hasta correr su SQL');
    });
  });
}
