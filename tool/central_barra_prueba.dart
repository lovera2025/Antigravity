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

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_providers.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final puertoBusqueda = s.port;
  s.close();
  runApp(PruebaDeLaCentral(armarSalon(puertoBusqueda: puertoBusqueda)));
  unawaited(_agrandarCuandoSeVea());
}

Future<void> _agrandarCuandoSeVea() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle('Prueba de la central de la barra · dos tablets y la notebook');
    await windowManager.maximize();
  } catch (_) {}
}

final idPuertoViejo = BarraEnPrueba.id(1);

/// Lo guardado en el equipo, en memoria: cada lado tiene el suyo.
class GuardadoDePrueba extends GuardadoDeLaCentral {
  String? fiesta;
  DondeEstaLaCentral? donde;

  @override
  Future<String?> prendida({DateTime? ahora}) async => fiesta;

  @override
  Future<void> anotarPrendida(String? eventoId, {DateTime? ahora}) async => fiesta = eventoId;

  @override
  Future<DondeEstaLaCentral?> aMano() async => donde;

  @override
  Future<void> anotarAMano(DondeEstaLaCentral? d) async => donde = d;
}

/// Un equipo de la prueba: sus providers y su barra.
class EquipoDePrueba {
  EquipoDePrueba(this.nombre, this.container, this.barra, this.conexion);

  final String nombre;
  final ProviderContainer container;
  final BarraEnMemoria barra;
  final ConexionFija conexion;
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

/// Los tres equipos, con el mismo catálogo y los mismos precios (como si los hubieran
/// bajado de la nube antes de la fiesta).
SalonDePrueba armarSalon({required int puertoBusqueda}) {
  final hoy = DateTime.now();
  final eventos = [fiestaDePrueba(idPuertoViejo, 'PUERTO VIEJO', hoy)];
  final catalogo = BarraEnMemoria();
  var orden = 0;
  for (final (nombre, categoria, precio, stock) in [
    ('Cerveza lata', 'Cervezas', 3500.0, 24),
    ('Fernet con coca', 'Tragos', 6000.0, null),
    ('Gin tonic', 'Tragos', 7000.0, null),
    ('Speed con vodka', 'Tragos', 8000.0, 6),
    ('Agua sin gas', 'Sin alcohol', 1000.0, 4),
    ('Silla extra', 'Sillas', 8000.0, null),
  ]) {
    final p = catalogo.producto(nombre, categoria: categoria, orden: orden);
    catalogo.precio(idPuertoViejo, p, precio, orden: orden, stock: stock, aviso: stock == null ? null : 2);
    orden++;
  }

  EquipoDePrueba equipo(String id, String nombre, {String? cajera, String? pin, bool jefe = false}) {
    final barra = BarraEnMemoria()
      ..equipo = id
      ..reloj = (() => DateTime.now().toUtc());
    barra.productosGuardados.addAll(catalogo.productosGuardados);
    barra.preciosGuardados.addAll(catalogo.preciosGuardados);
    final operadores = OperadoresEnPrueba();
    if (cajera != null) {
      final opId = 'a0000000-0000-4000-8000-${(cajera.hashCode & 0xffffff).toString().padLeft(12, '0')}';
      operadores.operadores.lista.add(operadorDePrueba(opId, cajera, pin!));
      operadores.permisos.poner(opId, const PermisosEfectivos(barra: true));
    }
    final aviso = AvisoALaRed();
    final conLaRed = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
    final papel = PapelEnMemoria();
    var alDia = DateTime.now();
    final overrides = <Override>[
      ...operadores.reemplazos,
      avisoALaRedProvider.overrideWithValue(aviso),
      barraDeEsteEquipoProvider.overrideWithValue(conLaRed),
      barraDeLaRedProvider.overrideWithValue(barra),
      eventosDeLaBarraProvider.overrideWith((ref) async => eventos),
      papelDeLaBarraProvider.overrideWithValue(papel),
      subirVentaProvider.overrideWithValue((v) async {}),
      subirDeLaBarraProvider.overrideWithValue((tabla, id) async {}),
      accesosBarraProvider.overrideWithValue(AccesosBarra(
        bajar: () async => operadores.conexion.currentStatus == AppConnectivity.online,
        contarFiestas: () async => (await barra.fiestasConPrecio()).length,
        contarSinSubir: barra.ventasSinSubir,
        contarPendientes: barra.pendientesDeLaBarra,
        leerAlDia: () async => alDia,
        anotarAlDia: (c) async => alDia = c,
      )),
      escuchaCentralBarraProvider.overrideWithValue(InternetAddress.loopbackIPv4),
      puertoCentralBarraProvider.overrideWithValue(0),
      puertoBusquedaBarraProvider.overrideWithValue(puertoBusqueda),
      destinosBusquedaBarraProvider.overrideWithValue(() async => [InternetAddress.loopbackIPv4]),
      direccionesCentralBarraProvider.overrideWithValue(() async => ['127.0.0.1']),
      equipoDeLaBarraProvider.overrideWithValue(() async => id),
      guardadoDeLaCentralProvider.overrideWithValue(GuardadoDePrueba()),
      if (jefe) esRolJefeProvider.overrideWithValue(true),
      if (jefe) relojDelJefeProvider.overrideWithValue(DateTime.now),
    ];
    return EquipoDePrueba(nombre, ProviderContainer(overrides: overrides), barra, operadores.conexion);
  }

  return SalonDePrueba(
    equipo('tablet-a', 'TABLET A', cajera: 'Marta', pin: '1111'),
    equipo('tablet-b', 'TABLET B', cajera: 'Sofía', pin: '2222'),
    equipo('notebook', 'NOTEBOOK DE LA BARRA', jefe: true),
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
                child: _lado(s.tabletA, const _Cajera(), botones: const [Text('PIN Marta 1111')]),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: tablet,
                child: _lado(s.tabletB, const _Cajera(), botones: const [Text('PIN Sofía 2222')]),
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

class _Cajera extends ConsumerWidget {
  const _Cajera();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    return switch (destinoDeEntrada(app)) {
      DestinoDeEntrada.barra => const BarraHomeScreen(),
      _ => const RoleGateScreen(),
    };
  }
}
