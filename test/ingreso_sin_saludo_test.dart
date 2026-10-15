// Un ingreso que llega tarde a la central de la puerta (un celular que estuvo
// sin wifi) se marca igual, pero el tótem no lo saluda: la familia ya pasó.
// Sobre una base temporal, sin red, y con la ventana del tótem de mentira.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/kiosk_launcher.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';
import 'package:arguello_events/features/recepcion/services/lista_puerta.dart';
import 'package:arguello_events/models/invitado.dart';

const _ev = 'eeeeeeee-0000-4000-8000-000000000009';
const _c1 = 'c1000000-0000-4000-8000-000000000001';
const _c2 = 'c2000000-0000-4000-8000-000000000002';

class _SinConexion extends ConnectivityService {
  @override
  AppConnectivity get currentStatus => AppConnectivity.offline;
}

/// La ventana del tótem: anota los avisos que le llegan.
class _TotemDeMentira implements VentanasTotem {
  final avisos = <String>[];

  @override
  Future<dynamic> invocar(int id, String metodo, [dynamic args]) async {
    if (metodo == 'guest_checkin') {
      // Viaja como texto (`notifyGuestCheckin`).
      avisos.add((jsonDecode(args as String) as Map)['id'] as String);
    }
    return null;
  }

  @override
  Future<List<int>> abiertas() async => [1];

  @override
  Future<int> crear(
    String argumentos, {
    required Size tamanio,
    required String titulo,
  }) async =>
      1;

  @override
  Future<void> mostrar(int id) async {}

  @override
  Future<void> esconder(int id) async {}
}

void main() {
  late Directory docs;
  late InvitadosRepository repo;
  late _TotemDeMentira totem;
  final juan = idInvitadoPuerta(_c1, 0);
  final lucia = idInvitadoPuerta(_c2, 0);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    docs = Directory.systemTemp.createTempSync('ingreso_sin_saludo');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    repo = InvitadosRepository(
      SupabaseClient('http://localhost:1', 'anon-de-test'),
      _SinConexion(),
    );
    KioskLauncher.reiniciar();
    totem = _TotemDeMentira();
    KioskLauncher.ventanas = totem;
    await KioskLauncher.launch(_ev);
    expect(KioskLauncher.isTotemActive, isTrue);
  });

  tearDown(() async {
    KioskLauncher.reiniciar();
    await LocalDatabase.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<void> llegan() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('sin fila: se crea marcada y el tótem no se entera', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
      saludar: false,
    );
    await llegan();
    expect((await repo.getLocal(juan))!.estadoIngreso, EstadoIngreso.ingresado);
    expect(totem.avisos, isEmpty);
  });

  test('con fila: se marca y el tótem no se entera', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: lucia,
      nombre: 'ACOSTA, LUCÍA',
    );
    await repo.deshacerIngreso(lucia);
    await llegan();
    totem.avisos.clear();

    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: lucia,
      nombre: 'ACOSTA, LUCÍA',
      saludar: false,
    );
    await llegan();
    expect((await repo.getLocal(lucia))!.estadoIngreso, EstadoIngreso.ingresado);
    expect(totem.avisos, isEmpty);
  });

  test('como siempre (a tiempo), el tótem saluda', () async {
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
    );
    await repo.deshacerIngreso(juan);
    await repo.marcarIngreso(juan);
    await llegan();
    expect(totem.avisos, [juan, juan]);
  });

  test('la central lee una fila sola, y null si no está', () async {
    expect(await repo.getLocal(juan), isNull);
    await repo.ingresarDesdeLaPuerta(
      eventoId: _ev,
      id: juan,
      nombre: 'PÉREZ, JUAN',
    );
    final fila = await repo.getLocal(juan);
    expect(fila!.nombreCompleto, 'PÉREZ, JUAN');
    expect(fila.eventoId, _ev);
  });
}
