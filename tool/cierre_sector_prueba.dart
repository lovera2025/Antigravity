// Ventana de prueba del cierre de caja por sector (6.4.0): COBROS · BARRA · ENTRADAS
// arriba, en modo jefe. Es la pantalla de verdad (`CierreCajaScreen`) con los cobros del
// día inventados y la barra de una noche en memoria (TÉCNICA PINAROLI: tres cajas, 60
// ventas, una anulada, una caja cerrada con $ 500 de menos) y, en ENTRADAS (6.9.0), dos
// cajas de entradas de esa fiesta (Carla abierta; Maxi cerrada con $ 500 de menos, una
// venta anulada antes de cerrar y otra después), **sin tocar la base de la PC ni la
// nube**. Arriba, MODO JEFE SÍ / NO.
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

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/cierre_caja/cierre_caja_screen.dart';
import 'package:arguello_events/features/common/providers/admin_provider.dart';

import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart'
    hide MedioBarra;
import 'package:arguello_events/features/barra/datos/venta_barra.dart' show MedioBarra;

import '../test/helpers/cierre_en_memoria.dart';
import '../test/helpers/entradas_en_memoria.dart';
import '../test/helpers/noche_de_barra.dart';

/// Las dos cajas de entradas de la noche, como en `test/cierre_por_sector_test.dart`.
Future<EntradasEnMemoria> _entradasDeLaNoche(String fiesta) async {
  final e = EntradasEnMemoria()..conPrecio(fiesta);
  RenglonEntradas sueltas(int n, {double descuento = 0}) => RenglonEntradas.suelta(
        nombre: 'Entrada',
        precioLista: 10000,
        descuentoPct: descuento,
        cantidad: n,
      );
  final carla = await e.abrirCaja(
      eventoId: fiesta, operadorId: 'carla', operadorNombre: 'Carla', cambioInicial: 5000);
  final maxi = await e.abrirCaja(
      eventoId: fiesta, operadorId: 'maxi', operadorNombre: 'Maxi', cambioInicial: 2000);
  await e.vender(
      caja: carla, compradorNombre: 'A', renglones: [sueltas(2)],
      medio: MedioBarra.efectivo, efectivo: 20000, quien: 'Carla');
  await e.vender(
      caja: carla, compradorNombre: 'B', renglones: [sueltas(1, descuento: 50)],
      medio: MedioBarra.transferencia, transferencia: 5000, quien: 'Carla');
  await e.vender(
      caja: maxi, compradorNombre: 'C', renglones: [sueltas(3)],
      medio: MedioBarra.efectivo, efectivo: 30000, quien: 'Maxi');
  final antes = await e.vender(
      caja: maxi, compradorNombre: 'D', renglones: [sueltas(1)],
      medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Maxi');
  final despues = await e.vender(
      caja: maxi, compradorNombre: 'E', renglones: [sueltas(1)],
      medio: MedioBarra.efectivo, efectivo: 10000, quien: 'Maxi');
  await e.anular(antes, motivo: 'error', devueltas: true, quien: 'Jefe');
  await e.cerrarCaja(maxi, efectivoContado: 41500, diferencia: -500, quien: 'Maxi');
  e.adelantar(const Duration(hours: 3));
  await e.anular(despues, motivo: 'pagó dos veces', devueltas: true, quien: 'Jefe');
  return e;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final noche = await nocheDeBarra(fotos: false);
  // Con cuánto cambio arrancaron las dos que siguen abiertas.
  await noche.prueba.barra.ponerCambio(noche.marta, 20000, quien: 'Marta');
  final entradas = await _entradasDeLaNoche(noche.pinaroliId);
  runApp(ProviderScope(
    overrides: reemplazosDelCierre(noche, entradas: entradas),
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
