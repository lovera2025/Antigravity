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
    final listas = <int>[];
    final sub = repo.watchByEvento(ev).listen((l) => listas.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.agregar(eventoId: ev, nombreCompleto: 'TEST INVITADO', numeroMesa: '3');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(listas.last, 1);
    await sub.cancel();
  });
}
