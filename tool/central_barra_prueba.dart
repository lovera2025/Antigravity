// Ventana de prueba de la central de la barra: **dos tablets y la notebook de la barra,
// cada una con su propia barra en memoria, unidas por la central de verdad** (el servidor,
// la búsqueda por UDP y los clientes reales, por la red de esta PC). Sin base, sin nube y
// sin router. Al cerrar se olvida todo.
//
//   flutter run -d windows -t tool/central_barra_prueba.dart
//
// - En la notebook (a la derecha), BARRA → CAJAS: PRENDER LA CENTRAL. Las tablets la
//   encuentran solas. APAGAR es como si la notebook se quedara sin wifi.
// - En cada tablet, la cajera entra con su PIN (Marta 1111, Sofía 2222), elige PUERTO VIEJO,
//   abre su caja y vende: "Quedan" baja en la otra tablet, y la notebook ve las cajas.
// - CORTAR INTERNET (arriba de la notebook): nada sube a la nube; con internet, cada dos
//   segundos "sube" todo, y las líneas dicen "Todo subido".
// Los papeles no salen por la impresora: se guardan en memoria.
//
// **Con un celular o una tablet de verdad** (etapa 9): con `--dart-define=red=todas` la
// central de la notebook escucha por el wifi, en los puertos de la app (8797 y 8777), y el
// celular con `tool/tablet_barra_prueba.dart` la encuentra solo, como en el salón. Windows
// pregunta si deja pasar a la ventana de prueba por el cortafuegos: hay que permitirlo.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';

import '../test/helpers/barra_en_memoria.dart' show PapelEnMemoria;
import 'salon_de_barra_prueba.dart';

/// `--dart-define=red=todas`: la notebook escucha por el wifi de verdad.
const _redDeVerdad = String.fromEnvironment('red') == 'todas';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final puertoBusqueda = s.port;
  s.close();
  runApp(PruebaDeLaCentral(armarSalon(puertoBusqueda: puertoBusqueda, redDeVerdad: _redDeVerdad)));
  unawaited(_agrandarCuandoSeVea());
}

Future<void> _agrandarCuandoSeVea() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle(_redDeVerdad
        ? 'Prueba de la central de la barra · por el wifi (red=todas)'
        : 'Prueba de la central de la barra · dos tablets y la notebook');
    await windowManager.maximize();
  } catch (_) {}
}

class SalonDePrueba {
  SalonDePrueba(this.tabletA, this.tabletB, this.notebook);

  final EquipoDePrueba tabletA;
  final EquipoDePrueba tabletB;
  final EquipoDePrueba notebook;
  bool hayInternet = true;

  List<EquipoDePrueba> get todos => [tabletA, tabletB, notebook];

  void cambiarInternet() {
    hayInternet = !hayInternet;
    for (final e in todos) {
      e.conexion.cambiar(hayInternet ? AppConnectivity.online : AppConnectivity.offline);
      if (e.container.exists(puestaAlDiaBarraProvider)) {
        e.container.read(puestaAlDiaBarraProvider).conexion(hayInternet);
      }
    }
    subir();
  }

  /// Con internet, todo lo de cada equipo "sube" (como la cola de subida de la app).
  void subir() {
    if (!hayInternet) return;
    for (final e in todos) {
      e.barra.subioTodo();
      if (e.container.exists(puestaAlDiaBarraProvider)) {
        unawaited(e.container.read(puestaAlDiaBarraProvider).recontar());
      }
    }
  }

  void dispose() {
    for (final e in todos) {
      e.container.dispose();
    }
  }
}

/// Los tres equipos, con el mismo catálogo y los mismos precios. Con [redDeVerdad], la
/// notebook escucha por el wifi y las dos tablets de la ventana la buscan en esta PC.
SalonDePrueba armarSalon({required int puertoBusqueda, bool redDeVerdad = false}) {
  final eventos = fiestasDePrueba();
  final catalogo = catalogoDePrueba();
  final enEstaPc = RedDePrueba.enEstaPc(puertoBusqueda: puertoBusqueda);
  final redTablet = redDeVerdad ? RedDePrueba.tabletEnLaPc : enEstaPc;
  final redNotebook = redDeVerdad ? RedDePrueba.delSalon : enEstaPc;

  EquipoDePrueba equipo(String id, String nombre, RedDePrueba red, {String? cajera, String? pin, bool jefe = false}) =>
      armarEquipo(
        id: id,
        nombre: nombre,
        catalogo: catalogo,
        eventos: eventos,
        red: red,
        cajera: cajera,
        pin: pin,
        jefe: jefe,
        papel: PapelEnMemoria(),
      );

  return SalonDePrueba(
    equipo('tablet-a', 'TABLET A', redTablet, cajera: 'Marta', pin: '1111'),
    equipo('tablet-b', 'TABLET B', redTablet, cajera: 'Sofía', pin: '2222'),
    equipo('notebook', 'NOTEBOOK DE LA BARRA', redNotebook, jefe: true),
  );
}

/// La ventana: las dos tablets y la notebook, cada una su propia app.
class PruebaDeLaCentral extends StatefulWidget {
  final SalonDePrueba salon;

  const PruebaDeLaCentral(this.salon, {super.key});

  @override
  State<PruebaDeLaCentral> createState() => _PruebaDeLaCentralState();
}

class _PruebaDeLaCentralState extends State<PruebaDeLaCentral> {
  Timer? _subida;

  @override
  void initState() {
    super.initState();
    _subida = Timer.periodic(const Duration(seconds: 2), (_) => widget.salon.subir());
  }

  @override
  void dispose() {
    _subida?.cancel();
    super.dispose();
  }

  Widget _lado(EquipoDePrueba e, Widget home, {List<Widget> botones = const []}) => UncontrolledProviderScope(
        container: e.container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, nav) => Column(
            children: [
              Material(
                color: e == widget.salon.notebook ? const Color(0xFFDCEBFF) : const Color(0xFFFFF3CD),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ...botones,
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: c.biggest),
                    child: nav!,
                  ),
                ),
              ),
            ],
          ),
          home: home,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.salon;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: LayoutBuilder(builder: (context, c) {
          final tablet = math.min(800.0, (c.maxWidth - 12) / 3);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: tablet,
                child: _lado(s.tabletA, const CajeraDePrueba(), botones: const [Text('PIN Marta 1111')]),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: tablet,
                child: _lado(s.tabletB, const CajeraDePrueba(), botones: const [Text('PIN Sofía 2222')]),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _lado(
                  s.notebook,
                  const BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas),
                  botones: [
                    TextButton(
                      key: const Key('prueba_internet'),
                      onPressed: () => setState(s.cambiarInternet),
                      child: Text(s.hayInternet ? 'CORTAR INTERNET' : 'VOLVER EL INTERNET'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
