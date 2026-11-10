// Ventana de prueba de **la Encargada de barra en la web del iPhone** (6.5.0), con una
// noche inventada en memoria, **sin tocar la base de la PC ni la nube**: la pantalla de
// entrada de verdad, el PIN "por la nube" (una lista), el inicio de la barra de la web,
// LAS CAJAS con tres cajas y 60 ventas, y anular. Al cerrar se olvida todo.
//
//   flutter build web -t tool/encargada_web_prueba.dart --no-web-resources-cdn --output build/encargada_web_prueba
//   python -I -m http.server 8794 --directory build/encargada_web_prueba
//       (y abrir http://localhost:8794 en un navegador a 375 px de ancho; es lo que
//       hace `.claude/launch.json` para el navegador de la app)
//
// Se compila como la web de verdad: el compilador de desarrollo (`flutter run -d
// web-server`) se cae con este proyecto (7-nov) y deja la página en blanco.
//
// Los PIN: **Romi 7777** es la Encargada de barra (entra). Marta 2222 es cajera de barra,
// Maxi 1234 es de Cobros y Ana 5555 de Entradas: a los tres se les dice que usen la app.
// SIN INTERNET, arriba, hace que la nube no conteste.
//
// No corre `main.dart`: no abre la base ni inicia sesión. El reparto de pantallas es el
// mismo que el de la app (`destinoDeEntrada`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/services/operador_por_la_nube.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/dashboard/widgets/actualizar_app.dart';

import '../test/helpers/noche_de_barra.dart';
import '../test/helpers/operadores_de_la_nube_en_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final noche = await nocheDeBarra();
  final nube = OperadoresDeLaNubeEnMemoria()
    ..poner('a0000000-0000-4000-8000-000000000007', 'Romi', '7777', barra: 2)
    ..poner('a0000000-0000-4000-8000-000000000008', 'Marta', '2222', barra: 1)
    ..poner('a0000000-0000-4000-8000-000000000001', 'Maxi', '1234', conFila: false)
    ..poner('a0000000-0000-4000-8000-000000000002', 'Ana', '5555', entradas: 1);
  runApp(PruebaDeLaEncargadaEnLaWeb(noche, nube));
}

class PruebaDeLaEncargadaEnLaWeb extends StatefulWidget {
  final NocheDeBarra noche;
  final OperadoresDeLaNubeEnMemoria nube;

  const PruebaDeLaEncargadaEnLaWeb(this.noche, this.nube, {super.key});

  @override
  State<PruebaDeLaEncargadaEnLaWeb> createState() => _PruebaState();
}

class _PruebaState extends State<PruebaDeLaEncargadaEnLaWeb> {
  bool _sinInternet = false;

  @override
  Widget build(BuildContext context) {
    final noche = widget.noche;
    return ProviderScope(
      overrides: [
        enLaWebProvider.overrideWithValue(true),
        operadoresDeLaNubeProvider.overrideWithValue(widget.nube),
        barraDelJefeProvider.overrideWithValue(noche.prueba.barra),
        eventosDeLaBarraProvider.overrideWith((ref) async => noche.prueba.eventos),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 12, 4, 23)),
        versionNuevaEnLaTabletProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFFD4AF37),
          useMaterial3: true,
        ),
        // En una ventana ancha (la PC), la app va adentro de un marco del tamaño de un
        // iPhone, con sus carteles adentro: así se recorre a 375 px sin emular un celular.
        builder: (context, child) => LayoutBuilder(
          builder: (context, caja) {
            if (caja.maxWidth <= 500) return child!;
            final alto = caja.maxHeight < 812 ? caja.maxHeight : 812.0;
            return ColoredBox(
              color: const Color(0xFF2B2B2B),
              child: Center(
                child: SizedBox(
                  width: 375,
                  height: alto,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: Size(375, alto)),
                    child: ClipRect(child: child!),
                  ),
                ),
              ),
            );
          },
        ),
        home: Column(
          children: [
            Material(
              color: const Color(0xFFDCEBFF),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Prueba: la encargada en la web · nada se guarda',
                          style: TextStyle(color: Colors.black87, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        key: const Key('prueba_sin_internet'),
                        onPressed: () => setState(() {
                          _sinInternet = !_sinInternet;
                          widget.nube.falla = _sinInternet ? StateError('sin internet') : null;
                        }),
                        child: Text(
                          _sinInternet ? 'SIN INTERNET' : 'CON INTERNET',
                          style: const TextStyle(color: Colors.black87, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Expanded(child: _Reparto()),
          ],
        ),
      ),
    );
  }
}

/// El mismo reparto que el router de la app (`_RoleRouter`, en `main.dart`).
class _Reparto extends ConsumerWidget {
  const _Reparto();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (destinoDeEntrada(ref.watch(appRoleProvider))) {
      DestinoDeEntrada.elegir => const RoleGateScreen(),
      DestinoDeEntrada.barra => const BarraHomeScreen(),
      DestinoDeEntrada.entradas => const Scaffold(body: Center(child: Text('ENTRADAS (no debería verse)'))),
      DestinoDeEntrada.panel => const Scaffold(body: Center(child: Text('EL PANEL (no debería verse)'))),
    };
  }
}
