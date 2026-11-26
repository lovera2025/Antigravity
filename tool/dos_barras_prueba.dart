// Ventana de prueba de **las dos barras de la Técnica, cada una con su notebook y su
// central** (25-nov-2026, Parte 2 del plan): la tablet de la Barra 1 (Marta), la de la
// Barra 2 (Sofía), las dos notebooks con CAJAS y la tablet de la encargada (Romi), cada
// una con su barra en memoria y la central de verdad (servidores, búsqueda por UDP y
// clientes reales) por la red de esta PC. Sin base, sin nube y sin router. Al cerrar se
// olvida todo.
//
//   flutter run -d windows -t tool/dos_barras_prueba.dart
//
// - Trae **cajas de prueba del 20/11** (cerradas, con ventas), como las que bajaron de la
//   nube: LAS CAJAS no las suma con las de la noche.
// - El reloj es **de prueba** y arranca el viernes 4/12 a las 23:30. ADELANTAR 1 HORA lo
//   pasa de la medianoche: el vale sigue diciendo el viernes y la caja sigue en esa noche.
// - Las redes de las dos barras arrancan **separadas** (cada router por su lado). JUNTAR
//   hace que se vean: las centrales se enganchan solas y se pasan todo. SEPARAR las corta.
// - REINICIAR LA NOTEBOOK 1 la cierra y la vuelve a abrir con la misma base: la central
//   vuelve sola y las tablets la encuentran.
// Los papeles no salen por la impresora: se guardan en memoria.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/widgets/vender_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';

import '../test/helpers/barra_en_memoria.dart' show BarraEnMemoria, PapelEnMemoria, fiestaDePrueba;
import 'salon_de_barra_prueba.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ninguna ventana de prueba abre la base de la PC: si algo se escapa, falla.
  LocalDatabase.cerrarParaLaPrueba();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final (p1, p2) = await dosPuertosLibres();
  runApp(PruebaDeDosBarras(SalonDeDosBarras(p1, p2)));
  unawaited(_agrandarCuandoSeVea());
}

Future<void> _agrandarCuandoSeVea() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle('Prueba de las dos barras · cada una con su central');
    await windowManager.maximize();
  } catch (_) {}
}

/// Dos puertos UDP libres y distintos, fuera del rango que Windows reparte solo: cada
/// central contesta en el suyo.
Future<(int, int)> dosPuertosLibres() async {
  final azar = math.Random();
  final libres = <int>[];
  while (libres.length < 2) {
    final p = 20000 + azar.nextInt(20000);
    if (libres.contains(p)) continue;
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, p);
      s.close();
      libres.add(p);
    } catch (_) {}
  }
  return (libres[0], libres[1]);
}

/// La fiesta de la prueba: el viernes 4/12, con los precios de PUERTO VIEJO.
final fiestaDeLaPrueba = fiestaDePrueba(idPuertoViejo, 'TÉCNICA DE PRUEBA', DateTime(2026, 12, 4, 22));

/// Un momento en hora de Argentina (UTC-3).
DateTime enArgentina(int mes, int dia, int hora, [int minuto = 0]) => DateTime.utc(2026, mes, dia, hora + 3, minuto);

/// Las dos barras, la encargada y lo que comparten: el reloj y las redes.
class SalonDeDosBarras {
  SalonDeDosBarras(this.puerto1, this.puerto2) {
    final catalogo = catalogoDePrueba();
    _prueba = _pruebaDel20(catalogo);
    tablet1 = _equipo('tablet-1', 'TABLET · BARRA 1', puerto1, red1, cajera: 'Marta', pin: '1111', barra: 'Barra 1', catalogo: catalogo);
    tablet2 = _equipo('tablet-2', 'TABLET · BARRA 2', puerto2, red2, cajera: 'Sofía', pin: '2222', barra: 'Barra 2', catalogo: catalogo);
    notebook1 = _equipo('notebook-1', 'NOTEBOOK · BARRA 1', puerto1, red1, jefe: true, barra: 'Barra 1', catalogo: catalogo);
    notebook2 = _equipo('notebook-2', 'NOTEBOOK · BARRA 2', puerto2, red2, jefe: true, barra: 'Barra 2', catalogo: catalogo);
    encargada = _equipo('tablet-e', 'ENCARGADA · EN LA BARRA 1', puerto1, red1,
        cajera: 'Romi', pin: '7777', encargada: true, catalogo: catalogo);
  }

  final int puerto1;
  final int puerto2;

  /// A qué puertos preguntan los equipos de cada barra: separadas, solo al suyo.
  late final red1 = <int>[puerto1];
  late final red2 = <int>[puerto2];
  bool juntas = false;

  /// El reloj de prueba: el viernes 4/12 a las 23:30, en la hora de esta PC (como
  /// `DateTime.now()`).
  DateTime ahora = enArgentina(12, 4, 23, 30).toLocal();

  late final ({List<CajaBarra> cajas, List<VentaBarra> ventas}) _prueba;
  late EquipoDePrueba tablet1, tablet2, notebook1, notebook2, encargada;
  final _guardados = <String, GuardadoDePrueba>{};

  List<EquipoDePrueba> get todos => [tablet1, tablet2, notebook1, notebook2, encargada];

  /// La noche de prueba del 20/11, como bajó de la nube: la Caja 1 de Lucas (Barra 1) y la
  /// Caja 2 de Juan (Barra 2), cerradas, con sus ventas.
  ({List<CajaBarra> cajas, List<VentaBarra> ventas}) _pruebaDel20(BarraEnMemoria catalogo) {
    final fernet = catalogo.productosGuardados.firstWhere((p) => p.nombre.startsWith('Fernet'));
    final cerveza = catalogo.productosGuardados.firstWhere((p) => p.nombre.startsWith('Cerveza'));
    final cajas = <CajaBarra>[];
    final ventas = <VentaBarra>[];
    for (final (n, quien, barra, producto, precio, cantidad) in [
      (1, 'Lucas', 'Barra 1', fernet, 6000.0, 5),
      (2, 'Juan', 'Barra 2', cerveza, 3500.0, 8),
    ]) {
      final abierta = CajaBarra.abrir(
        eventoId: idPuertoViejo,
        operadorId: 'prueba-$n',
        operadorNombre: quien,
        numeroCaja: n,
        sede: barra,
        ahora: enArgentina(11, 20, 19),
      );
      final venta = VentaBarra.nueva(
        cajaBarraId: abierta.id,
        eventoId: idPuertoViejo,
        numero: 1,
        renglones: [RenglonVenta(productoId: producto.id, nombre: producto.nombre, precio: precio, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: precio * cantidad,
        ahora: enArgentina(11, 20, 20),
      );
      cajas.add(abierta.cerrada(
        efectivoContado: precio * cantidad,
        diferencia: 0,
        ahora: enArgentina(11, 20, 23),
      ));
      ventas.add(venta);
    }
    return (cajas: cajas, ventas: ventas);
  }

  EquipoDePrueba _equipo(
    String id,
    String nombre,
    int puerto,
    List<int> red, {
    required BarraEnMemoria catalogo,
    String? cajera,
    String? pin,
    bool jefe = false,
    bool encargada = false,
    String? barra,
    BarraEnMemoria? deAntes,
  }) {
    final e = armarEquipo(
      id: id,
      nombre: nombre,
      catalogo: catalogo,
      eventos: [fiestaDeLaPrueba],
      red: RedDePrueba(
        escucha: InternetAddress.loopbackIPv4,
        puertoCentral: 0,
        puertoBusqueda: puerto,
        destinos: () async => [InternetAddress.loopbackIPv4],
        direcciones: () async => ['127.0.0.1'],
        puertosQuePregunta: red,
      ),
      cajera: cajera,
      pin: pin,
      jefe: jefe,
      encargada: encargada,
      barraDelEquipo: barra,
      papel: PapelEnMemoria(),
      reloj: () => ahora,
      deAntes: deAntes,
      guardado: _guardados[id] ??= GuardadoDePrueba(),
    );
    if (deAntes == null) {
      // Lo de la prueba del 20/11, como si hubiera bajado de la nube (no se sube de nuevo).
      e.barra.cajasGuardadas.addAll(_prueba.cajas);
      e.barra.ventasGuardadas.addAll(_prueba.ventas);
    }
    return e;
  }

  /// Las redes de las dos barras se ven (los routers unidos por wifi).
  void juntar() {
    juntas = true;
    for (final (red, otro) in [(red1, puerto2), (red2, puerto1)]) {
      if (!red.contains(otro)) red.add(otro);
    }
  }

  /// Cada barra por su lado: las centrales se dejan de ver.
  void separar() {
    juntas = false;
    red1.remove(puerto2);
    red2.remove(puerto1);
    for (final n in [notebook1, notebook2]) {
      n.container.read(centralDeLaBarraProvider.notifier).volverABuscarLaOtra();
    }
  }

  /// Adelanta el reloj de todos los equipos, y las pantallas se vuelven a leer.
  void adelantar(Duration d) {
    ahora = ahora.add(d);
    for (final e in todos) {
      e.container.read(operationalSyncRevisionProvider.notifier).bump();
    }
  }

  /// Las dos centrales, cada una con su barra (como tocar PRENDER LA CENTRAL en cada una).
  Future<void> prenderLasCentrales() async {
    for (final (n, barra) in [(notebook1, 'Barra 1'), (notebook2, 'Barra 2')]) {
      await n.container.read(centralDeLaBarraProvider.notifier).prender(idPuertoViejo, barra: barra);
    }
  }

  /// La notebook de la Barra 1 vuelve a abrir con la misma base y lo guardado (después
  /// de cerrar la de antes, que se lleva su central como si se cortara la luz).
  void abrirDeNuevoLaNotebook1(BarraEnMemoria antes) {
    notebook1 = _equipo('notebook-1', 'NOTEBOOK · BARRA 1 (reiniciada)', puerto1, red1,
        jefe: true, barra: 'Barra 1', catalogo: antes, deAntes: antes);
  }

  void dispose() {
    for (final e in todos) {
      e.container.dispose();
    }
  }
}

/// Una tablet de la prueba: entra la cajera con su PIN; con la caja abierta, VENDER.
class _Tablet extends ConsumerWidget {
  final CajaBarra? Function() caja;

  const _Tablet(this.caja);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = caja();
    if (c != null && ref.watch(appRoleProvider).kind != AppRoleKind.none) {
      return VenderScreen(fiesta: fiestaDeLaPrueba, caja: c);
    }
    return const CajeraDePrueba();
  }
}

class PruebaDeDosBarras extends StatefulWidget {
  final SalonDeDosBarras salon;

  const PruebaDeDosBarras(this.salon, {super.key});

  @override
  State<PruebaDeDosBarras> createState() => _PruebaDeDosBarrasState();
}

class _PruebaDeDosBarrasState extends State<PruebaDeDosBarras> {
  SalonDeDosBarras get s => widget.salon;
  final _cajas = <String, CajaBarra>{};
  String _aviso = 'Las redes arrancan separadas. Prendé las centrales.';
  var _reinicios = 0;
  bool _reiniciando = false;

  String get _reloj {
    final ar = s.ahora.toUtc().subtract(const Duration(hours: 3));
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${DiaDeOperacion.delCalendario(ar).corto} ${dos(ar.hour)}:${dos(ar.minute)} '
        '(la noche: ${DiaDeOperacion.de(s.ahora).corto})';
  }

  Future<void> _entrarYAbrir() async {
    for (final (e, numero, barra) in [(s.tablet1, 1, 'Barra 1'), (s.tablet2, 2, 'Barra 2')]) {
      final op = e.operador!;
      // La caja primero: al entrar, la tablet ya va derecho a VENDER.
      _cajas[e.nombre] = await e.container.read(barraDeLaCajaProvider).abrirCaja(
            eventoId: idPuertoViejo,
            operadorId: op.id,
            operadorNombre: op.nombre,
            numeroCaja: numero,
            sede: barra,
          );
      await e.container.read(appRoleProvider.notifier).entrarComoBarra(op, const PermisosEfectivos(barra: true));
    }
    await s.encargada.container
        .read(appRoleProvider.notifier)
        .entrarComoBarra(s.encargada.operador!, const PermisosEfectivos(barra: true, encargadaBarra: true));
    setState(() => _aviso = 'Marta abrió la Caja 1 (Barra 1) y Sofía la Caja 2 (Barra 2).');
  }

  Future<void> _venderEnCadaCaja() async {
    final barra = s.tablet1.barra;
    final fernet = barra.productosGuardados.firstWhere((p) => p.nombre.startsWith('Fernet'));
    for (final e in [s.tablet1, s.tablet2]) {
      final caja = _cajas[e.nombre];
      if (caja == null) continue;
      await e.container.read(barraDeLaCajaProvider).vender(
            caja: caja,
            renglones: [RenglonVenta(productoId: fernet.id, nombre: fernet.nombre, precio: 6000, cantidad: 1)],
            medio: MedioBarra.efectivo,
            efectivo: 6000,
            quien: caja.operadorNombre ?? 'Cajera',
          );
      e.container.read(operationalSyncRevisionProvider.notifier).bump();
    }
    setState(() => _aviso = 'Un fernet en cada caja, a las $_reloj.');
  }

  Widget _lado(EquipoDePrueba e, Widget home, {Color color = const Color(0xFFFFF3CD)}) => UncontrolledProviderScope(
        key: ObjectKey(e.container),
        container: e.container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, nav) => Column(
            children: [
              Material(
                color: color,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _boton(String clave, String texto, Future<void> Function() hacer) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: FilledButton(
          key: Key(clave),
          onPressed: () async {
            await hacer();
            if (mounted) setState(() {});
          },
          child: Text(texto),
        ),
      );

  Widget _controles() => Material(
        color: const Color(0xFFEDE7F6),
        child: ListView(
          padding: const EdgeInsets.all(10),
          children: [
            const Text('LA PRUEBA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('Reloj de prueba: $_reloj', key: const Key('prueba_reloj')),
            Text(s.juntas ? 'Las redes de las dos barras: JUNTAS' : 'Las redes de las dos barras: SEPARADAS',
                key: const Key('prueba_redes')),
            const SizedBox(height: 4),
            Text(_aviso, style: const TextStyle(fontSize: 12.5)),
            const Divider(),
            _boton('prueba_prender', 'PRENDER LAS DOS CENTRALES', () async {
              await s.prenderLasCentrales();
              _aviso = 'Centrales prendidas: Barra 1 y Barra 2.';
            }),
            _boton('prueba_abrir', 'ENTRAR Y ABRIR LAS CAJAS', _entrarYAbrir),
            _boton('prueba_vender', 'VENDER UN FERNET EN CADA CAJA', _venderEnCadaCaja),
            _boton('prueba_juntar', s.juntas ? 'SEPARAR LAS REDES' : 'JUNTAR LAS REDES', () async {
              if (s.juntas) {
                s.separar();
                _aviso = 'Cada barra por su lado.';
              } else {
                s.juntar();
                _aviso = 'Las redes se ven: las centrales se enganchan solas.';
              }
            }),
            _boton('prueba_hora', 'ADELANTAR EL RELOJ 1 HORA', () async {
              s.adelantar(const Duration(hours: 1));
              _aviso = 'Ahora: $_reloj.';
            }),
            _boton('prueba_reiniciar', 'REINICIAR LA NOTEBOOK 1', () async {
              // Primero se saca de la pantalla, después se cierra (se lleva su central), y
              // al rato vuelve a abrir con la misma base: CAJAS prende la central sola.
              final antes = s.notebook1;
              setState(() => _reiniciando = true);
              await WidgetsBinding.instance.endOfFrame;
              antes.container.dispose();
              await Future<void>.delayed(const Duration(seconds: 2));
              s.abrirDeNuevoLaNotebook1(antes.barra);
              _reinicios++;
              _reiniciando = false;
              _aviso = 'La notebook 1 se reinició ($_reinicios): su central volvió sola.';
            }),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: LayoutBuilder(builder: (context, c) {
          final ancho = (c.maxWidth - 12) / 3;
          final alto = (c.maxHeight - 6) / 2;
          Widget celda(Widget w) => SizedBox(width: ancho, height: alto, child: w);
          return Column(
            children: [
              Row(children: [
                celda(_lado(s.tablet1, _Tablet(() => _cajas[s.tablet1.nombre]))),
                const SizedBox(width: 6),
                celda(_reiniciando
                    ? const ColoredBox(
                        color: Color(0xFF202020),
                        child: Center(
                          child: Text('La notebook 1 se está reiniciando…', style: TextStyle(color: Colors.white)),
                        ),
                      )
                    : _lado(s.notebook1, const BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas),
                        color: const Color(0xFFDCEBFF))),
                const SizedBox(width: 6),
                celda(_lado(s.encargada, const CajeraDePrueba(), color: const Color(0xFFE2F5E9))),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                celda(_lado(s.tablet2, _Tablet(() => _cajas[s.tablet2.nombre]))),
                const SizedBox(width: 6),
                celda(_lado(s.notebook2, const BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas),
                    color: const Color(0xFFDCEBFF))),
                const SizedBox(width: 6),
                celda(_controles()),
              ]),
            ],
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    s.dispose();
    super.dispose();
  }
}
