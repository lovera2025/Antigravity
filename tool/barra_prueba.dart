// Ventana de prueba de la barra: **la cajera a la izquierda (una tablet) y el jefe a la
// derecha (la PC de la oficina), sobre la misma barra en memoria**, sin tocar la base de
// la PC ni la nube. La cajera entra con su PIN, elige la fiesta, abre su caja, vende,
// cobra, saca los vales y cierra; el jefe arma el catálogo y los precios y mira CAJAS.
// Lo que hace uno le llega al otro como en la app: lo que la tablet sube, el jefe lo ve
// (CAJAS se pone al día sola), y lo que el jefe guarda, la tablet lo baja (VENDER y la
// lista de fiestas se rehacen). Al cerrar la ventana se olvida todo.
//
//   flutter run -d windows -t tool/barra_prueba.dart
//
// No corre `main.dart`: no abre la base ni inicia sesión. Arriba de cada lado, su barra:
// - la cajera: los PIN inventados, VER COMO CELULAR / TABLET (el ancho de su lado) y
//   CORTAR INTERNET, que vale para los dos: sin internet nada cruza, las ventas quedan
//   "por subir" en la tablet y el jefe no las ve; al volver, suben y le llegan;
// - el jefe: MODO JEFE SÍ / NO, para ver lo apagado con su motivo.
//
// Lo que no es como en la app: la barra es una sola en memoria. El jefe no ve las
// ventas que la tablet no subió (como en la app), pero un precio que el jefe guarda sin
// internet la tablet lo ve la próxima vez que relee.
//
// Los papeles salen por la TP-POS58 de verdad, si está prendida (se elige con el ícono
// de la impresora de la cajera); la misma impresora para los dos lados. Sin gastar papel:
// `--dart-define=papel=pantalla`, y PAPEL, arriba, muestra el último como texto (las
// líneas grandes, con >>).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/impresion/canal_universal_ble.dart';
import 'package:arguello_events/features/barra/impresion/impresora_bluetooth.dart';
import 'package:arguello_events/features/barra/impresion/ticket_esc_pos.dart';
import 'package:arguello_events/features/barra/jefe/barra_jefe_screen.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/providers/barra_providers.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/widgets/barra_home_screen.dart';
import 'package:arguello_events/features/caja_sesiones/models/permisos_operador.dart';
import 'package:arguello_events/features/caja_sesiones/providers/app_role_provider.dart';
import 'package:arguello_events/features/caja_sesiones/widgets/role_gate_screen.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';

import '../test/helpers/barra_en_memoria.dart';
import '../test/helpers/operadores_en_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // La impresora que ya eligió esta PC, para que se conecte sola; el resto, en memoria,
  // sin tocar las preferencias de la PC (el PIN maestro de siempre).
  final real = await const ImpresoraRecordada().leer();
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  if (real != null) {
    await const ImpresoraRecordada().guardar(real);
  }
  runApp(PruebaDeLaBarra(armarLados(
    papelEnPantalla: _papelEnPantalla,
    impresora: _papelEnPantalla
        ? null
        : ImpresoraBluetooth(CanalUniversalBle(), recordada: const ImpresoraRecordada()),
  )));
  unawaited(_agrandarCuandoSeVea());
}

/// La tablet y la PC del jefe no entran en la ventana de siempre. Se agranda **cuando ya
/// se ve**: el runner de Windows la muestra después del primer cuadro, y mostrarla deshace
/// un `maximize` de antes.
Future<void> _agrandarCuandoSeVea() async {
  try {
    await windowManager.ensureInitialized();
    for (var i = 0; i < 50 && !await windowManager.isVisible(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await windowManager.setTitle('Prueba de la barra · la cajera y el jefe');
    await windowManager.maximize();
  } catch (_) {}
}

const _papelEnPantalla = String.fromEnvironment('papel') == 'pantalla';

/// Puerto Viejo, la fiesta de hoy: con stock y la silla extra.
final idPuertoViejo = BarraEnPrueba.id(1);

/// Buena Vista, sin precios: la cajera no la ve hasta que el jefe le pone alguno.
final idBuenaVista = BarraEnPrueba.id(3);

/// El modo jefe del lado del jefe, que se prende y se apaga con su barra de arriba.
class ModoJefeDeLaPrueba extends Notifier<bool> {
  @override
  bool build() => true;

  void poner(bool prendido) => state = prendido;
}

final modoJefeDeLaPruebaProvider = NotifierProvider<ModoJefeDeLaPrueba, bool>(ModoJefeDeLaPrueba.new);

/// Los dos lados de la ventana, cada uno con sus providers, sobre la misma barra.
class LadosDeLaPrueba {
  final ProviderContainer cajera;
  final ProviderContainer jefe;
  final BarraEnMemoria barra;
  final ConexionFija conexion;

  /// Con `papel=pantalla`: los papeles que "salieron", de los dos lados.
  final PapelEnMemoria? papel;

  LadosDeLaPrueba._({
    required this.cajera,
    required this.jefe,
    required this.barra,
    required this.conexion,
    required this.papel,
  });

  bool get hayInternet => conexion.currentStatus == AppConnectivity.online;

  /// CORTAR INTERNET y VOLVER EL INTERNET, para los dos lados. Al volver, la tablet sube
  /// lo que esperaba y cada lado baja lo del otro.
  void cambiarInternet() {
    final vuelve = !hayInternet;
    conexion.estado = vuelve ? AppConnectivity.online : AppConnectivity.offline;
    // La línea sin internet de la cajera se vuelve a armar con la conexión nueva.
    cajera.invalidate(puestaAlDiaBarraProvider);
    if (vuelve) {
      barra.subioTodo();
      _bajaEn(jefe);
      _bajaEn(cajera);
    }
  }

  void dispose() {
    cajera.dispose();
    jefe.dispose();
  }
}

/// Lo que en la app hace la nube: avisarle al otro equipo que bajó algo nuevo. Las
/// pantallas que miran `operationalSyncRevisionProvider` se rehacen.
void _bajaEn(ProviderContainer otro) => otro.read(operationalSyncRevisionProvider.notifier).bump();

/// Arma los datos inventados y los dos lados. [impresora]: la TP-POS58 de verdad, una
/// sola para los dos (dos se pelearían por ella). Con [papelEnPantalla], ninguna.
LadosDeLaPrueba armarLados({bool papelEnPantalla = false, ImpresoraBluetooth? impresora}) {
  final operadores = OperadoresEnPrueba();
  operadores.operadores.lista.addAll([
    operadorDePrueba('a0000000-0000-4000-8000-000000000001', 'Marta (solo Barra)', '1111'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000002', 'Tati (los tres)', '5555'),
    operadorDePrueba('a0000000-0000-4000-8000-000000000007', 'Romi (Encargada)', '7777'),
  ]);
  operadores.permisos
    ..poner('a0000000-0000-4000-8000-000000000001', const PermisosEfectivos(barra: true))
    ..poner(
      'a0000000-0000-4000-8000-000000000002',
      const PermisosEfectivos(cobros: true, entradas: true, barra: true),
    )
    // 6.4.0: vende con su caja y además ve LAS CAJAS y anula cualquier venta.
    ..poner('a0000000-0000-4000-8000-000000000007', const PermisosEfectivos(encargadaBarra: true));

  final prueba = BarraEnPrueba();
  final hoy = DateTime.now();
  final puertoViejo = fiestaDePrueba(idPuertoViejo, 'PUERTO VIEJO', hoy);
  final tecnica = fiestaDePrueba(BarraEnPrueba.id(2), 'TÉCNICA', hoy.add(const Duration(days: 1)));
  prueba.eventos.addAll([
    puertoViejo,
    tecnica,
    fiestaDePrueba(idBuenaVista, 'BUENA VISTA (sin precios)', hoy.add(const Duration(days: 9))),
  ]);
  final b = prueba.barra
    // Las horas de las cajas y las ventas, las de verdad: la barra en memoria trae una fija.
    ..reloj = (() => DateTime.now().toUtc());
  var orden = 0;
  for (final (nombre, categoria, precio, stock) in [
    ('Cerveza lata', 'Cervezas', 3500.0, 240),
    ('Cerveza porrón', 'Cervezas', 5000.0, null),
    ('Fernet con coca', 'Tragos', 6000.0, null),
    ('Gin tonic', 'Tragos', 7000.0, null),
    ('Speed con vodka', 'Tragos', 8000.0, 12),
    ('Agua sin gas', 'Sin alcohol', 1000.0, 3),
    ('Gaseosa', 'Sin alcohol', 2000.0, null),
    ('Champán Chandon Extra Brut', 'Vinos', 45000.0, null),
    // La silla de la noche (6.4.0): sale en su propio vale, que va a la recepcionista.
    ('Silla extra', 'Sillas', 8000.0, null),
  ]) {
    final p = b.producto(nombre, categoria: categoria, orden: orden);
    b.precio(puertoViejo.id, p, precio, orden: orden, stock: stock, aviso: stock == null ? null : 2);
    b.precio(tecnica.id, p, precio + 500, orden: orden);
    orden++;
  }

  final conexion = operadores.conexion;
  bool hay() => conexion.currentStatus == AppConnectivity.online;
  late final ProviderContainer cajera;
  late final ProviderContainer jefe;

  List<Override> comunes() => [
        // Sin la red del salón: acá los dos lados ya comparten la barra en memoria. La
        // central de verdad se prueba en `tool/central_barra_prueba.dart`.
        redDeLaBarraHabilitadaProvider.overrideWithValue(false),
        ...operadores.reemplazos,
        barraDeLaCajaProvider.overrideWithValue(b),
        eventosDeLaBarraProvider.overrideWith((ref) async => prueba.eventos),
        if (papelEnPantalla) papelDeLaBarraProvider.overrideWithValue(prueba.papel),
        if (impresora != null) impresoraDeLaBarraProvider.overrideWithValue(impresora),
      ];

  cajera = ProviderContainer(overrides: [
    ...comunes(),
    barraDelJefeProvider.overrideWithValue(b),
    // La izquierda es una tablet: ahí no se prende la central.
    centralSePrendeAcaProvider.overrideWithValue(false),
    subirVentaProvider.overrideWithValue((v) async {
      if (!hay()) return;
      b.sinSubir.remove(v.id);
      _bajaEn(jefe);
    }),
    // Las anulaciones, los vales que salieron y la caja cerrada.
    subirDeLaBarraProvider.overrideWithValue((tabla, id) async {
      if (hay()) _bajaEn(jefe);
    }),
    accesosBarraProvider.overrideWithValue(AccesosBarra(
      bajar: () async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return hay();
      },
      contarFiestas: () async => (await b.fiestasConPrecio()).length,
      contarSinSubir: b.ventasSinSubir,
      leerAlDia: () async => prueba.alDia,
      anotarAlDia: (c) async => prueba.alDia = c,
    )),
  ]);

  jefe = ProviderContainer(overrides: [
    ...comunes(),
    barraDelJefeProvider.overrideWithValue(_LoQueSubio(b)),
    // El catálogo, los precios, el recargo, las anulaciones y las copias.
    subirDeLaBarraProvider.overrideWithValue((tabla, id) async {
      if (hay()) _bajaEn(cajera);
    }),
    esRolJefeProvider.overrideWith((ref) => ref.watch(modoJefeDeLaPruebaProvider)),
  ]);

  return LadosDeLaPrueba._(
    cajera: cajera,
    jefe: jefe,
    barra: b,
    conexion: conexion,
    papel: papelEnPantalla ? prueba.papel : null,
  );
}

/// Lo que el jefe ve de la barra: lo de la tablet, **menos las ventas que la tablet
/// todavía no subió** (las de sin internet) y sus anulaciones, como en la app.
class _LoQueSubio implements BarraDelJefe {
  final BarraEnMemoria b;

  _LoQueSubio(this.b);

  @override
  Future<List<ProductoBarra>> productos({bool conBajas = false}) => b.productos(conBajas: conBajas);

  @override
  Future<ProductoBarra> guardarProducto(ProductoBarra producto, {required String quien}) =>
      b.guardarProducto(producto, quien: quien);

  @override
  Future<List<PrecioBarra>> precios(String eventoId, {bool conBajas = false}) =>
      b.precios(eventoId, conBajas: conBajas);

  @override
  Future<PrecioBarra> guardarPrecio(PrecioBarra precio, {required String quien}) =>
      b.guardarPrecio(precio, quien: quien);

  @override
  Future<RecargoBarra?> recargo(String eventoId) => b.recargo(eventoId);

  @override
  Future<RecargoBarra> guardarRecargo(RecargoBarra recargo, {required String quien}) =>
      b.guardarRecargo(recargo, quien: quien);

  @override
  Future<List<CajaBarra>> cajas(String eventoId) => b.cajas(eventoId);

  @override
  Future<List<VentaBarra>> ventas(String eventoId) async =>
      [for (final v in await b.ventas(eventoId)) if (!b.sinSubir.contains(v.id)) v];

  @override
  Future<List<AnulacionBarra>> anulaciones(String eventoId) async =>
      [for (final a in await b.anulaciones(eventoId)) if (!b.sinSubir.contains(a.ventaId)) a];

  @override
  Future<AnulacionBarra> anular(VentaBarra venta, {required String motivo, required String quien}) =>
      b.anular(venta, motivo: motivo, quien: quien);

  @override
  Future<List<ValeBarra>> vales(String eventoId) => b.vales(eventoId);

  // El pedido de cierre y el OK (v79): en esta ventana los dos lados comparten la barra.
  @override
  Future<List<PasoDelCierre>> pasosDelCierre(String eventoId) => b.pasosDelCierre(eventoId);

  @override
  Future<PasoDelCierre> anotarPasoDelCierre(PasoDelCierre paso) => b.anotarPasoDelCierre(paso);
}

/// La ventana: la cajera a la izquierda y el jefe a la derecha. **Cada lado es su propia
/// app** (su `MaterialApp`, sus diálogos y su ancho): así la hoja de cobrar o CAMBIAR DE
/// FIESTA quedan en su lado, y `CortesPantalla` mide el lado y no la ventana.
class PruebaDeLaBarra extends StatefulWidget {
  final LadosDeLaPrueba lados;

  const PruebaDeLaBarra(this.lados, {super.key});

  @override
  State<PruebaDeLaBarra> createState() => _PruebaDeLaBarraState();
}

class _PruebaDeLaBarraState extends State<PruebaDeLaBarra> {
  static const anchoTablet = 800.0;
  static const anchoCelular = 390.0;

  var _anchoCajera = anchoTablet;
  final _navCajera = GlobalKey<NavigatorState>();
  final _navJefe = GlobalKey<NavigatorState>();
  Timer? _reloj;
  var _vistos = 0;

  @override
  void initState() {
    super.initState();
    // El contador de PAPEL se pone al día solo, cuando sale uno nuevo.
    if (widget.lados.papel case final papel?) {
      _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && papel.papeles.length != _vistos) {
          setState(() => _vistos = papel.papeles.length);
        }
      });
    }
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  /// El último papel, como texto: lo grande con >>, los renglones con su precio, y
  /// [LOGO] o [QR] si los lleva.
  void _verPapel(GlobalKey<NavigatorState> donde) {
    final papel = widget.lados.papel;
    final context = donde.currentContext;
    if (papel == null || context == null) return;
    final ultimo = papel.enCrudo.lastOrNull;
    final lineas = [
      for (final l in ultimo ?? const <LineaTicket>[])
        switch (l) {
          GrandeTicket() => '>> ${l.texto}',
          TituloTicket() => '## ${l.texto}',
          TextoTicket() => l.texto,
          RenglonTicket() => '${l.izquierda}  ·  ${l.derecha}',
          SeparadorTicket() => '--------------------------------',
          QrTicket() => '[QR]',
          LogoTicket() => '[LOGO]',
        },
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Papel ${papel.papeles.length}'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: SelectableText(
              ultimo == null ? 'Todavía no salió ningún papel.' : lineas.join('\n'),
              key: const Key('prueba_papel_texto'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR'))],
      ),
    );
  }

  Widget _botonPapel(GlobalKey<NavigatorState> donde, String clave) {
    final papel = widget.lados.papel;
    if (papel == null) return const SizedBox.shrink();
    return TextButton(
      key: Key(clave),
      onPressed: () => _verPapel(donde),
      child: Text('PAPEL (${papel.papeles.length})'),
    );
  }

  Widget _barraCajera() {
    final l = widget.lados;
    final celular = _anchoCajera == anchoCelular;
    return _BarraDeArriba(
      color: const Color(0xFFFFF3CD),
      texto: 'CAJERA · ${celular ? 'celular' : 'tablet'}   PIN: Marta 1111 · Tati 5555 · Romi (encargada) 7777',
      botones: [
        TextButton(
          key: const Key('prueba_ancho_cajera'),
          onPressed: () => setState(() => _anchoCajera = celular ? anchoTablet : anchoCelular),
          child: Text(celular ? 'VER COMO TABLET' : 'VER COMO CELULAR'),
        ),
        _botonPapel(_navCajera, 'prueba_papel_cajera'),
        TextButton(
          key: const Key('prueba_internet'),
          onPressed: () => setState(l.cambiarInternet),
          child: Text(l.hayInternet ? 'CORTAR INTERNET' : 'VOLVER EL INTERNET'),
        ),
      ],
    );
  }

  Widget _barraJefe() {
    final l = widget.lados;
    return _BarraDeArriba(
      color: l.hayInternet ? const Color(0xFFDCEBFF) : const Color(0xFFFFD9D2),
      texto: l.hayInternet
          ? 'JEFE · la PC de la oficina'
          : 'JEFE · sin internet: no ve lo que la tablet no subió',
      botones: [
        Consumer(
          builder: (context, ref, _) {
            final prendido = ref.watch(modoJefeDeLaPruebaProvider);
            return TextButton(
              key: const Key('prueba_modo_jefe'),
              onPressed: () => ref.read(modoJefeDeLaPruebaProvider.notifier).poner(!prendido),
              child: Text(prendido ? 'MODO JEFE: SÍ' : 'MODO JEFE: NO'),
            );
          },
        ),
        _botonPapel(_navJefe, 'prueba_papel_jefe'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lados;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: LayoutBuilder(
          builder: (context, c) {
            // Al jefe le quedan por lo menos 360: en una pantalla chica, la tablet se achica.
            final ancho = math.min(_anchoCajera, math.max(320.0, c.maxWidth - 366));
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: ancho,
                  child: UncontrolledProviderScope(
                    container: l.cajera,
                    child: MaterialApp(
                      navigatorKey: _navCajera,
                      debugShowCheckedModeBanner: false,
                      builder: (context, nav) => _Lado(arriba: _barraCajera(), child: nav!),
                      home: const _Cajera(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: UncontrolledProviderScope(
                    container: l.jefe,
                    child: MaterialApp(
                      navigatorKey: _navJefe,
                      debugShowCheckedModeBanner: false,
                      builder: (context, nav) => _Lado(arriba: _barraJefe(), child: nav!),
                      home: const BarraJefeScreen(pestanaInicial: PestanaBarraJefe.cajas),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Un lado: su barra de prueba arriba y la app abajo, que mide solo su lado.
class _Lado extends StatelessWidget {
  final Widget arriba;
  final Widget child;

  const _Lado({required this.arriba, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        arriba,
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: c.biggest),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarraDeArriba extends StatelessWidget {
  final Color color;
  final String texto;
  final List<Widget> botones;

  const _BarraDeArriba({required this.color, required this.texto, required this.botones});

  @override
  Widget build(BuildContext context) {
    // En un lado angosto (la cajera como celular) los botones bajan a otro renglón.
    return Material(
      color: color,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(texto),
              ),
              ...botones,
            ],
          ),
        ),
      ),
    );
  }
}

/// El lado de la cajera: la entrada con el PIN y, con Barra, su pantalla.
class _Cajera extends ConsumerWidget {
  const _Cajera();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appRoleProvider);
    return switch (destinoDeEntrada(app)) {
      DestinoDeEntrada.barra => const BarraHomeScreen(),
      DestinoDeEntrada.elegir => const RoleGateScreen(),
      _ => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: ref.read(appRoleProvider.notifier).logoutApp,
              child: const Text('Esto no es la barra (la prueba es de la barra). SALIR'),
            ),
          ),
        ),
    };
  }
}
