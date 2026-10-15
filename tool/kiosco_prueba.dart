// Arnés manual: la ventana del tótem de verdad, para probar el modo kiosco
// (sección 6 de la 6.0.0) en Windows **sin tocar la base de la PC ni la nube**.
//
//   flutter run -d windows -t tool/kiosco_prueba.dart
//
// No corre `main.dart`: no abre la base local (así la v73 no migra nada), no
// inicia sesión y la nube apunta a ningún lado. Abre una ventana chica con un
// botón; el botón abre la ventana del tótem (`TotemDisplay`, la misma de la
// app) con un evento inventado. En su barra de arriba a la derecha está
// KIOSCO. El runner de Windows es el de la app: el canal del kiosco
// (`windows/runner/kiosco.cpp`) es el de verdad.

import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/features/totem/totem_display.dart';
import 'package:arguello_events/main.dart' show supabaseProvider;
import 'package:arguello_events/services/supabase_service.dart';

/// Un evento inventado: no existe en la nube ni en la PC.
const _evento = 'deadbeef-0000-4000-8000-00000000c10c';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.isNotEmpty && args.first == 'multi_window') {
    final id = int.parse(args[1]);
    // A ningún lado: la conexión falla al instante, como sin internet.
    final nube = SupabaseClient('http://127.0.0.1:9', 'anon-de-prueba');
    DesktopMultiWindow.setMethodHandler((call, _) async => null);
    runApp(
      ProviderScope(
        overrides: [supabaseProvider.overrideWithValue(nube)],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: TotemDisplay(
            eventoId: _evento,
            showExitButton: true,
            svc: SupabaseService(client: nube),
            windowId: id,
          ),
        ),
      ),
    );
    return;
  }

  // La ventana principal no tiene ficha ni lista que darle: contesta nada.
  DesktopMultiWindow.setMethodHandler((call, _) async => null);
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _Principal(),
  ));
}

class _Principal extends StatefulWidget {
  const _Principal();

  @override
  State<_Principal> createState() => _PrincipalState();
}

class _PrincipalState extends State<_Principal> {
  int? _totem;

  Future<void> _abrir() async {
    final id = _totem;
    if (id != null) {
      await WindowController.fromWindowId(id).show();
      await DesktopMultiWindow.invokeMethod(id, 'reanudar');
      return;
    }
    final ventana = await DesktopMultiWindow.createWindow(
      jsonEncode({'eventoId': _evento}),
    );
    ventana
      ..setFrame(const Offset(120, 80) & const Size(900, 560))
      ..setTitle('Tótem de prueba')
      ..show();
    setState(() => _totem = ventana.windowId);
  }

  /// Lo que hace Recepción con `KioskLauncher.close`: le pide al tótem que se
  /// pause, espera la respuesta y lo esconde. A los 5 s, para tener tiempo de
  /// ponerlo en kiosco.
  Future<void> _esconderEnUnRato() async {
    final id = _totem;
    if (id == null) return;
    await Future<void>.delayed(const Duration(seconds: 5));
    await DesktopMultiWindow.invokeMethod(id, 'pausar');
    await WindowController.fromWindowId(id).hide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Arnés del modo kiosco: no toca la base ni la nube.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _abrir,
              child: Text(_totem == null
                  ? 'Abrir el tótem de prueba'
                  : 'Volver a mostrar el tótem'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _totem == null ? null : _esconderEnUnRato,
              child: const Text('Esconder el tótem en 5 s (como Recepción)'),
            ),
          ],
        ),
      ),
    );
  }
}
