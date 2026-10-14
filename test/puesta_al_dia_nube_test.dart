// Las dos bajadas de "Lista para trabajar sin internet" (sección 5 de la
// 6.0.0): la lista de la puerta del evento entera
// (`InvitadosRepository.bajarListaDelEvento`) y, en un masivo, el evento, los
// alumnos, sus sillas y el plano (`SyncEngine.bajarParaLaPuerta`). Sobre una
// base temporal y una nube simulada: no sale nada de la PC.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';

const _ev = 'eeeeeeee-0000-4000-8000-00000000000b';

class _Conexion extends ConnectivityService {
  _Conexion(this.estado);
  final AppConnectivity estado;
  @override
  AppConnectivity get currentStatus => estado;
}

Map<String, Object?> _fila(String id, String nombre) => {
      'id': id,
      'evento_id': _ev,
      'nombre_completo': nombre,
      'dni': '',
      'numero_mesa': '12',
      'estado_ingreso': 'pendiente',
      'intentos_fallidos': 0,
      'updated_at': '2026-12-12T20:00:00Z',
      'created_at': '2026-12-12T20:00:00Z',
    };

/// La nube: qué devuelve cada tabla, y cuáles fallan.
class _Nube {
  final filas = <String, List<Map<String, Object?>>>{};
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
        return http.Response(
          jsonEncode(filas[tabla] ?? const []),
          200,
          headers: {'content-type': 'application/json'},
          request: req,
        );
      });
}

void main() {
  late Directory docs;
  late _Nube nube;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docs = Directory.systemTemp.createTempSync('puesta_al_dia');
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

  group('la lista de la puerta del evento', () {
    const a = 'aaaaaaaa-0000-4000-8000-000000000001';
    const b = 'aaaaaaaa-0000-4000-8000-000000000002';

    test('baja entera, aunque la PC ya tuviera parte', () async {
      // Esta PC tenía a A; después, en otra PC, cargaron a B.
      final db = await LocalDatabase.instance;
      await db.insert('invitados', _fila(a, 'PÉREZ, ANA'));
      nube.filas['invitados'] = [_fila(a, 'PÉREZ, ANA'), _fila(b, 'GÓMEZ, BRUNO')];
      final repo =
          InvitadosRepository(cliente(), _Conexion(AppConnectivity.online));

      expect(await repo.bajarListaDelEvento(_ev), isTrue);
      final locales = await repo.getLocalesByEvento(_ev);
      expect({for (final i in locales) i.id}, {a, b});
    });

    test('si la nube falla, dice que no', () async {
      nube.fallan.add('invitados');
      final repo =
          InvitadosRepository(cliente(), _Conexion(AppConnectivity.online));
      expect(await repo.bajarListaDelEvento(_ev), isFalse);
    });

    test('sin internet no pide nada', () async {
      final repo =
          InvitadosRepository(cliente(), _Conexion(AppConnectivity.offline));
      expect(await repo.bajarListaDelEvento(_ev), isFalse);
      expect(nube.pedidas, isEmpty);
    });
  });

  group('lo de un masivo: el evento, los alumnos, las sillas y el plano', () {
    test('si bajan todas, sí', () async {
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.online),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaPuerta(), isTrue);
      expect(nube.pedidas.toSet(), SyncEngine.tablasDeLaPuerta.toSet());
    });

    test('si una no baja (una tabla que todavía no está en la nube), no',
        () async {
      nube.fallan.add('sillas_reparto');
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.online),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaPuerta(), isFalse);
    });

    test('sin internet no pide nada', () async {
      final motor = SyncEngine(
        connectivity: _Conexion(AppConnectivity.offline),
        supabase: cliente(),
      );
      expect(await motor.bajarParaLaPuerta(), isFalse);
      expect(nube.pedidas, isEmpty);
    });
  });
}
