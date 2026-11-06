// Recepción suelta su canal de Realtime apenas se deja de mirar la lista.
//
// Antes el canal seguía abierto hasta el próximo cambio de ese evento, y
// Supabase seguía evaluando el WAL para una pantalla que nadie miraba.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/recepcion/repositories/invitados_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  late SupabaseClient supabase;
  late InvitadosRepository repo;
  const ev = 'eeeeeeee-0000-4000-8000-000000000002';

  setUp(() {
    docs = Directory.systemTemp.createTempSync('recepcion_canal');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
    supabase = SupabaseClient('http://localhost:1', 'anon-de-test');
    repo = InvitadosRepository(supabase, ConnectivityService());
  });

  tearDown(() async {
    await LocalDatabase.close();
    try {
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    } catch (_) {
      // Windows puede tener el archivo tomado un instante más; es un temporal.
    }
  });

  /// Escucha y espera la primera lista, así la lectura inicial ya terminó.
  Future<StreamSubscription<dynamic>> escuchar() async {
    final primera = Completer<void>();
    final sub = repo.watchByEvento(ev).listen((_) {
      if (!primera.isCompleted) primera.complete();
    });
    await primera.future.timeout(const Duration(seconds: 20));
    return sub;
  }

  test('al cancelar la escucha, el canal se va en el momento', () async {
    final sub = await escuchar();
    expect(supabase.getChannels(), isNotEmpty);

    await sub.cancel();
    expect(supabase.getChannels(), isEmpty);
  });

  test('con dos pantallas mirando, el canal sigue hasta que se va la última', () async {
    final a = await escuchar();
    final b = await escuchar();
    expect(supabase.getChannels(), hasLength(1));

    await a.cancel();
    expect(supabase.getChannels(), hasLength(1));
    await b.cancel();
    expect(supabase.getChannels(), isEmpty);
  });

  test('sigue emitiendo la lista cuando cambia algo', () async {
    // Se espera la primera lista y después la que trae al invitado, con tope: con
    // 50 ms fijos fallaba cuando la PC estaba cargada (la suite entera), porque abrir
    // la base de prueba tardaba más.
    final primera = Completer<void>();
    final conUno = Completer<void>();
    final sub = repo.watchByEvento(ev).listen((l) {
      if (!primera.isCompleted) primera.complete();
      if (l.length == 1 && !conUno.isCompleted) conUno.complete();
    });
    await primera.future.timeout(const Duration(seconds: 20));
    await repo.agregar(eventoId: ev, nombreCompleto: 'TEST INVITADO', numeroMesa: '3');
    await conUno.future.timeout(const Duration(seconds: 20));
    await sub.cancel();
  });
}
