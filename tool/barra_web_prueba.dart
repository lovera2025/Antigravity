// Ventana de prueba de BARRA del jefe **como en la web del iPhone** (etapa 8), con una
// noche inventada en memoria, **sin tocar la base de la PC ni la nube**: CATÁLOGO,
// PRECIOS, CAJAS con tres cajas y 60 ventas, anular, los PDF. Sin impresora, como en la
// web. Al cerrar se olvida todo.
//
//   flutter build web -t tool/barra_web_prueba.dart --no-web-resources-cdn --output build/barra_web_prueba
//   python -I -m http.server 8790 --directory build/barra_web_prueba
//       (y abrir http://localhost:8790 en un navegador a 375 px de ancho; es lo que
//       hace `.claude/launch.json` para el navegador de la app)
//   flutter run -d windows -t tool/barra_web_prueba.dart   (achicar la ventana)
//
// Se compila como la web de verdad: el compilador de desarrollo (`flutter run -d
// web-server`) se cae con este proyecto (7-nov) y deja la página en blanco.
//
// No corre `main.dart`: no abre la base ni inicia sesión. Arriba, MODO JEFE SÍ / NO.
// La web de verdad lee la nube con `BarraNube`; acá la nube es la barra en memoria.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';

import '../test/helpers/noche_de_barra.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final noche = await nocheDeBarra();
  runApp(PruebaDeLaBarraEnLaWeb(noche));
}

/// El modo jefe de la prueba, que se prende y se apaga con la barra de arriba.
class ModoJefeDeLaPruebaWeb extends Notifier<bool> {
  @override
  bool build() => true;

  void poner(bool prendido) => state = prendido;
}

final modoJefeDeLaPruebaWebProvider =
    NotifierProvider<ModoJefeDeLaPruebaWeb, bool>(ModoJefeDeLaPruebaWeb.new);

/// La app de la prueba: BARRA del jefe sobre la noche en memoria, con la llave de la
/// web prendida aunque corra en Windows.
class PruebaDeLaBarraEnLaWeb extends StatelessWidget {
  final NocheDeBarra noche;

  const PruebaDeLaBarraEnLaWeb(this.noche, {super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        ...noche.operadores.reemplazos,
        enLaWebProvider.overrideWithValue(true),
        barraDelJefeProvider.overrideWithValue(noche.prueba.barra),
        eventosDeLaBarraProvider.overrideWith((ref) async => noche.prueba.eventos),
        // En la web lo que se guarda ya está en la nube: no hay nada que subir.
        subirDeLaBarraProvider.overrideWithValue((tabla, id) async {}),
        esRolJefeProvider.overrideWith((ref) => ref.watch(modoJefeDeLaPruebaWebProvider)),
        relojDelJefeProvider.overrideWithValue(() => DateTime(2026, 12, 5, 9)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
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
                        child: Text('Prueba: BARRA en la web · nada se guarda', overflow: TextOverflow.ellipsis),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final prendido = ref.watch(modoJefeDeLaPruebaWebProvider);
                          return TextButton(
                            key: const Key('prueba_modo_jefe'),
                            onPressed: () => ref.read(modoJefeDeLaPruebaWebProvider.notifier).poner(!prendido),
                            child: Text(prendido ? 'MODO JEFE: SÍ' : 'MODO JEFE: NO'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Expanded(child: BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas)),
          ],
        ),
      ),
    );
  }
}
