import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Las tablas de la v77 (la barra) en el motor de sincronización. Mismo modelo que
/// `sync_tablas_v75_test.dart`: las listas del motor son privadas y se leen del texto
/// del archivo. La bajada para preparar la tablet, con una nube simulada, como
/// `puesta_al_dia_nube_test.dart`.
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _tablas = [
  'barra_productos',
  'barra_precios',
  'barra_cajas',
  'barra_ventas',
  'barra_anulaciones',
];

class _Conexion extends ConnectivityService {
  _Conexion(this.estado);
  final AppConnectivity estado;
  @override
  AppConnectivity get currentStatus => estado;
}

class _Nube {
  final fallan = <String>{};
  final pedidas = <String>[];

  http.Client get cliente => MockClient((req) async {
        final tabla = req.url.pathSegments.last;
        pedidas.add(tabla);
        if (fallan.contains(tabla)) {
          return http.Response(
            jsonEncode({'message': 'relation does not exist', 'code': '42P01'}),
            404,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'}, request: req);
      });
}

void main() {
  sqfliteFfiInit();
  final ahora = DateTime.utc(2026, 12, 4, 23, 41);

  final motor = File('lib/core/services/sync_engine.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final cola = File('lib/core/database/sync_queue.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  String declaracion(String nombre, String cierre) {
    final i = motor.indexOf(RegExp('static const [^;]*\\b$nombre = '));
    expect(i, greaterThanOrEqualTo(0), reason: 'no encontré $nombre');
    final f = motor.indexOf('\n  $cierre;', i);
    expect(f, greaterThan(i), reason: 'no encontré el final de $nombre');
    return motor.substring(i, f);
  }

  Set<String> columnasDelMotor(String tabla) {
    final m = RegExp("'$tabla': \\[(.*?)\\]", dotAll: true).firstMatch(motor);
    expect(m, isNotNull, reason: '$tabla no está en las columnas del motor');
    return {
      for (final c in RegExp("'([a-z_]+)'").allMatches(m!.group(1)!)) c.group(1)!,
    };
  }

  group('la barra en las listas del motor', () {
    test('suben y bajan todas sus columnas: las del modelo y las de la base', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await LocalDatabase.crearTablasV77(db);
      Future<Set<String>> enLaBase(String tabla) async => {
            for (final c in await db.rawQuery('PRAGMA table_info($tabla)'))
              c['name'] as String,
          };
      final producto = ProductoBarra.nuevo(nombre: 'Agua', ahora: ahora);
      final caja = CajaBarra.abrir(eventoId: _evento, numeroCaja: 1, ahora: ahora);
      final venta = VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _evento,
        numero: 1,
        renglones: [
          RenglonVenta(productoId: producto.id, nombre: 'Agua', precio: 1000, cantidad: 1),
        ],
        medio: MedioBarra.efectivo,
        efectivo: 1000,
        ahora: ahora,
      );
      final modelos = {
        'barra_productos': producto.toMap(),
        'barra_precios': PrecioBarra.para(
          eventoId: _evento,
          productoId: producto.id,
          precio: 1000,
          ahora: ahora,
        ).toMap(),
        'barra_cajas': caja.toMap(),
        'barra_ventas': venta.toMap(),
        'barra_anulaciones': AnulacionBarra.de(venta, motivo: 'x', ahora: ahora).toMap(),
      };
      for (final t in _tablas) {
        expect(columnasDelMotor(t), await enLaBase(t), reason: '$t: motor y base');
        expect(columnasDelMotor(t), modelos[t]!.keys.toSet(), reason: '$t: motor y modelo');
      }
      await db.close();
    });

    test('las cajas, las ventas y las anulaciones bajan cada 10 s; el catálogo, cada minuto', () {
      final columnas = declaracion('_incrementalColumns', '}');
      for (final t in _tablas) {
        expect(columnas, contains("'$t': 'updated_at'"));
        expect(motor, contains("_pullTable(db, '$t', 'updated_at')"));
      }
      final cobro = declaracion('_tablasDelCobro', ']');
      final carga = declaracion('_tablasDeCarga', ']');
      for (final t in ['barra_cajas', 'barra_ventas', 'barra_anulaciones']) {
        expect(cobro, contains("'$t'"), reason: t);
        expect(carga, isNot(contains("'$t'")), reason: t);
      }
      for (final t in ['barra_productos', 'barra_precios']) {
        expect(carga, contains("'$t'"), reason: t);
        expect(cobro, isNot(contains("'$t'")), reason: t);
      }
    });

    test('suben de padres a hijas: el producto, el precio y la caja, la venta, la anulación', () {
      expect(motor, contains("if (table == 'barra_productos') return 1;"));
      expect(motor, contains("if (table == 'barra_precios' || table == 'barra_cajas') return 2;"));
      expect(motor, contains("if (table == 'barra_ventas') return 4;"));
      expect(motor, contains("if (table == 'barra_anulaciones') return 5;"));
    });

    test('una venta encolada no se descarta nunca: ninguna es hija en la limpieza de la cola', () {
      // `_cleanOrphanQueueEntries` saca de la cola las hijas de un padre que se borra.
      // Con una venta adentro, borrar la fiesta en esta PC perdería una venta que no
      // subió. En la nube no hay clave foránea que la rechace: sube igual.
      for (final t in _tablas) {
        expect(cola, isNot(contains("'$t'")), reason: t);
      }
    });

    test('no están en ninguna lista que borre filas locales', () {
      final sinRevisar = declaracion('_tablasSinRevisarBorrados', '}');
      for (final t in _tablas) {
        expect(declaracion('_tablasAReconciliar', ']'), isNot(contains("'$t'")));
        expect(declaracion('_hijasEnCascada', '}'), isNot(contains("'$t'")));
        expect(sinRevisar, contains("'$t':"));
      }
    });

    test('nada de la barra se borra a mano', () {
      for (final f in Directory('lib/features/barra').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final texto = f.readAsStringSync();
        expect(texto, isNot(contains('SyncOperation.delete')), reason: f.path);
        expect(texto, isNot(contains('.delete(')), reason: f.path);
      }
    });

    test('la tablet se lleva la fiesta, los PIN, el catálogo y los precios', () {
      expect(SyncEngine.tablasDeLaBarra.toSet(), {
        'eventos',
        'operadores_caja',
        'permisos_operador',
        'barra_productos',
        'barra_precios',
      });
    });
  });

  group('preparar la tablet: bajarParaLaBarra', () {
    late Directory docs;
    late _Nube nube;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      docs = Directory.systemTemp.createTempSync('barra_bajada');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => docs.path,
          );
      nube = _Nube();
    });

    tearDown(() async {
      await LocalDatabase.close();
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    SupabaseClient cliente() {
      final c = SupabaseClient('https://nube.test', 'anon-de-test',
          httpClient: nube.cliente);
      c.auth.stopAutoRefresh();
      addTearDown(c.dispose);
      return c;
    }

    test('si bajan todas, sí', () async {
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.online),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaBarra(), isTrue);
      expect(nube.pedidas.toSet(), SyncEngine.tablasDeLaBarra.toSet());
    });

    test('si una no está en la nube todavía, dice que no', () async {
      nube.fallan.add('barra_precios');
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.online),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaBarra(), isFalse);
    });

    test('sin internet no pide nada', () async {
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.offline),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaBarra(), isFalse);
      expect(nube.pedidas, isEmpty);
    });
  });
}
