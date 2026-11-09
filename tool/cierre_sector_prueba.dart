// Ventana de prueba del cierre de caja por sector (6.4.0): COBROS · BARRA · ENTRADAS
// arriba, en modo jefe. Es la pantalla de verdad (`CierreCajaScreen`) con los cobros del
// día inventados y la barra de una noche en memoria (TÉCNICA PINAROLI: tres cajas, 60
// ventas, una anulada, una caja cerrada con $ 500 de menos), **sin tocar la base de la
// PC ni la nube**. Arriba, MODO JEFE SÍ / NO.
//
//   flutter run -d windows -t tool/cierre_sector_prueba.dart
//   flutter build web -t tool/cierre_sector_prueba.dart --no-web-resources-cdn --output build/cierre_sector_prueba
//   python -I -m http.server 8792 --directory build/cierre_sector_prueba
//       (lo que hace `.claude/launch.json` para el navegador de la app)
//
// No corre `main.dart`: no abre la base ni inicia sesión.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/cierre_caja/cierre_caja_screen.dart';
import 'package:arguello_events/features/common/providers/admin_provider.dart';

import '../test/helpers/cierre_en_memoria.dart';
import '../test/helpers/noche_de_barra.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final noche = await nocheDeBarra(fotos: false);
  // Con cuánto cambio arrancaron las dos que siguen abiertas.
  await noche.prueba.barra.ponerCambio(noche.marta, 20000, quien: 'Marta');
  runApp(ProviderScope(
    overrides: reemplazosDelCierre(noche),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
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
                        'Prueba: el cierre por sector · nada se guarda',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final prendido = ref.watch(adminAuthProvider).esModoJefe;
                        return TextButton(
                          key: const Key('prueba_modo_jefe'),
                          onPressed: () => (ref.read(adminAuthProvider.notifier) as ModoJefeDelCierre)
                              .poner(!prendido),
                          child: Text(prendido ? 'MODO JEFE: SÍ' : 'MODO JEFE: NO'),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Expanded(child: CierreCajaScreen()),
        ],
      ),
    ),
  ));
}
