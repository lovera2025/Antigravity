import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/linea_de_la_caja.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/central/vigia_de_la_red.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/barra/services/barras_del_salon.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';

import 'helpers/barra_en_memoria.dart';

/// La central de la barra como la arma la app: la notebook la prende desde BARRA y la
/// tablet la encuentra sola al abrir VENDER, cada una con sus providers. Por la red de
/// esta PC (loopback), con barras en memoria.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

class _GuardadoEnMemoria extends GuardadoDeLaCentral {
  CentralGuardada? central;
  DondeEstaLaCentral? donde;

  String? get fiesta => central?.eventoId;

  @override
  Future<CentralGuardada?> prendida() async => central;

  @override
  Future<void> anotarPrendida(String? eventoId, {String? barra, DateTime? ahora}) async => central =
      eventoId == null ? null : CentralGuardada(eventoId: eventoId, desde: ahora ?? DateTime.now(), barra: barra);

  @override
  Future<DondeEstaLaCentral?> aMano() async => donde;

  @override
  Future<void> anotarAMano(DondeEstaLaCentral? d) async => donde = d;
}

Future<void> hasta(bool Function() listo, {String? que}) async {
  final limite = DateTime.now().add(const Duration(seconds: 6));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Quién es quién: el mismo en todos los equipos de la prueba (los operadores bajaron
/// con internet). Cada equipo entra con la persona `op-<equipo>`; la del nombre con
/// "encargada" es encargada.
late QuienEsQuienEnMemoria _personas;

CredencialDeLaBarra _credencialDe(String equipo) => _personas.persona(
      'op-$equipo',
      equipo,
      rol: equipo.contains('encargada') ? RolEnLaBarra.encargada : RolEnLaBarra.cajera,
    );

void main() {
  late int puertoBusqueda;

  setUp(() async {
    _personas = QuienEsQuienEnMemoria();
    SharedPreferences.setMockInitialValues({});
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    puertoBusqueda = s.port;
    s.close();
  });

  ({ProviderContainer c, BarraEnMemoria barra, _GuardadoEnMemoria guardado}) equipo(
    String id, {
    BarraEnMemoria? deAntes,
    _GuardadoEnMemoria? guardadoDeAntes,
    DateTime Function()? reloj,
    Future<String> Function()? elEquipo,
    Future<List<String>> Function()? direcciones,
    String? Function()? quien,
    CredencialDeLaBarra Function()? credencial,
    List<Override> mas = const [],
  }) {
    final barra = deAntes ??
        (BarraEnMemoria()
          ..equipo = id
          ..reloj = (() => DateTime.now().toUtc()));
    final aviso = AvisoALaRed();
    final guardado = guardadoDeAntes ?? _GuardadoEnMemoria();
    final c = ProviderContainer(overrides: [
      if (reloj != null) relojDeLaBarraProvider.overrideWithValue(reloj),
      avisoALaRedProvider.overrideWithValue(aviso),
      barraDeEsteEquipoProvider.overrideWithValue(BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso)),
      barraDeLaRedProvider.overrideWithValue(barra),
      escuchaCentralBarraProvider.overrideWithValue(InternetAddress.loopbackIPv4),
      puertoCentralBarraProvider.overrideWithValue(0),
      puertoBusquedaBarraProvider.overrideWithValue(puertoBusqueda),
      destinosBusquedaBarraProvider.overrideWithValue(() async => [InternetAddress.loopbackIPv4]),
      direccionesCentralBarraProvider.overrideWithValue(direcciones ?? () async => ['192.168.0.10']),
      equipoDeLaBarraProvider.overrideWithValue(elEquipo ?? () async => id),
      guardadoDeLaCentralProvider.overrideWithValue(guardado),
      quienEsQuienEnLaBarraProvider.overrideWithValue(_personas),
      credencialDeLaBarraProvider.overrideWithValue(() async => credencial?.call() ?? _credencialDe(id)),
      quienUsaLaBarraProvider.overrideWithValue(quien ?? () => 'operador:$id'),
      credencialDeLaCentralProvider.overrideWithValue(() async => _personas.credencialDelJefe),
      ...mas,
    ]);
    addTearDown(c.dispose);
    return (c: c, barra: barra, guardado: guardado);
  }

  // 26-nov-2026: el usuario volvió al wifi de la barra y nada se actualizó hasta apagar y
  // prender la central. Ahora la notebook se da cuenta sola de que cambió de red.
  test('la notebook cambia de red: relee sus direcciones y sigue contestando, sin apagar la central', () async {
    var dirsDelEquipo = {'Wi-Fi/10.0.0.7'};
    var paraLasTablets = ['10.0.0.7'];
    final vigia = VigiaDeLaRed(direcciones: () async => dirsDelEquipo, cada: const Duration(milliseconds: 30));
    final notebook = equipo(
      'notebook',
      direcciones: () async => paraLasTablets,
      mas: [vigiaDeLaRedProvider.overrideWithValue(() => vigia)],
    );
    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    expect(notebook.c.read(centralDeLaBarraProvider).direcciones, ['10.0.0.7']);
    final puerto = notebook.c.read(centralDeLaBarraProvider).puerto;

    // Se conecta al wifi de la barra.
    dirsDelEquipo = {'Wi-Fi/192.168.0.10'};
    paraLasTablets = ['192.168.0.10'];
    await hasta(() => notebook.c.read(centralDeLaBarraProvider).direcciones.contains('192.168.0.10'),
        que: 'CAJAS muestra la dirección nueva');
    expect(notebook.c.read(centralDeLaBarraProvider).puerto, puerto, reason: 'la central sigue prendida, la misma');

    // Y la tablet que llega la encuentra sola.
    final tablet = equipo('tablet-a');
    await tablet.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1 · Marta');
    final cliente = tablet.c.read(clienteDeLaBarraProvider)!;
    await hasta(() => cliente.estado == EstadoDeLaCentral.conectada, que: 'la tablet conectada');
  });

  test('la notebook prende la central, la tablet la encuentra sola, y lo que vende le llega', () async {
    final notebook = equipo('notebook');
    final tablet = equipo('tablet-a');
    var rehechasEnLaNotebook = 0;
    notebook.c.listen(operationalSyncRevisionProvider, (_, _) => rehechasEnLaNotebook++);

    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    final estado = notebook.c.read(centralDeLaBarraProvider);
    expect(estado.prendida, isTrue);
    expect(estado.contestaBusqueda, isTrue);
    expect(estado.direccion, '192.168.0.10:${estado.puerto}');
    expect(notebook.guardado.fiesta, _fiesta, reason: 'para reanudarla si se reinicia la notebook');

    await tablet.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1 · Marta');
    final cliente = tablet.c.read(clienteDeLaBarraProvider)!;
    await hasta(() => cliente.estado == EstadoDeLaCentral.conectada, que: 'la tablet conectada');
    await hasta(() => notebook.c.read(centralDeLaBarraProvider).conectadas == 1, que: 'la notebook la ve');

    // VENDER usa la barra con la red: lo que vende sale solo.
    final barra = tablet.c.read(barraDeEsteEquipoProvider);
    final caja = await barra.abrirCaja(
      eventoId: _fiesta,
      operadorId: 'op-tablet-a',
      operadorNombre: 'Marta',
      numeroCaja: 1,
    );
    final venta = await barra.vender(
      caja: caja,
      renglones: const [RenglonVenta(productoId: 'p', nombre: 'Fernet', precio: 6000, cantidad: 1)],
      medio: MedioBarra.efectivo,
      efectivo: 6000,
      quien: 'Marta',
    );
    await hasta(() => notebook.barra.ventasGuardadas.any((v) => v.id == venta.id), que: 'la venta en la notebook');
    await hasta(() => rehechasEnLaNotebook > 0, que: 'CAJAS de la notebook se rehace');
    await hasta(
      () => notebook.c.read(centralDeLaBarraProvider).cajas.single.porSubir.ventas == 1,
      que: 'la notebook ve que esa caja tiene 1 venta sin subir',
    );
  });

  // 25-nov-2026: una central por barra, y la madrugada.
  test('prende con la barra elegida, la tablet de esa barra la encuentra, y se recuerda', () async {
    final notebook = equipo('notebook');
    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta, barra: 'Barra 2');
    final estado = notebook.c.read(centralDeLaBarraProvider);
    expect(estado.barra, 'Barra 2');
    expect(notebook.guardado.central!.barra, 'Barra 2', reason: 'vuelve con su barra');
    expect(await const BarraDelEquipo().leer(), 'Barra 2', reason: 'queda elegida la próxima vez');

    final tablet = equipo('tablet-a');
    await tablet.c
        .read(clienteDeLaBarraProvider.notifier)
        .arrancar(eventoId: _fiesta, nombreCaja: 'Caja 2 · Sofía', barra: 'Barra 2');
    final cliente = tablet.c.read(clienteDeLaBarraProvider)!;
    await hasta(() => cliente.conectada, que: 'conectada');
    expect(cliente.donde!.barra, 'Barra 2');
    await hasta(() => notebook.c.read(centralDeLaBarraProvider).soloCajas.single.barra == 'Barra 2',
        que: 'la notebook ve de qué barra es la caja');
  });

  test('después de un reinicio pasado el mediodía, vuelve sola mientras quede una caja de esa noche', () async {
    // Se prendió a las 17 del 4-dic; la caja de Marta sigue abierta a las 13 del 5.
    var ahora = DateTime.utc(2026, 12, 4, 20);
    final antes = equipo('notebook', reloj: () => ahora);
    await antes.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta, barra: 'Barra 1');
    antes.barra.reloj = () => DateTime.utc(2026, 12, 4, 21);
    final caja = await antes.barra.abrirCaja(eventoId: _fiesta, operadorId: 'm', operadorNombre: 'Marta', numeroCaja: 1);
    antes.c.dispose(); // se reinicia la notebook

    ahora = DateTime.utc(2026, 12, 5, 16); // las 13 del 5-dic
    final despues = equipo('notebook', deAntes: antes.barra, guardadoDeAntes: antes.guardado, reloj: () => ahora);
    await despues.c.read(centralDeLaBarraProvider.notifier).reanudar(_fiesta);
    expect(despues.c.read(centralDeLaBarraProvider).prendida, isTrue, reason: 'la caja de esa noche sigue abierta');
    expect(despues.c.read(centralDeLaBarraProvider).barra, 'Barra 1');
    expect(antes.guardado.central!.desde, DateTime.utc(2026, 12, 4, 20), reason: 'volver sola no cambia desde cuándo');

    // Cerrada esa caja, otro reinicio ya no la prende.
    despues.barra.reloj = () => DateTime.utc(2026, 12, 5, 16, 5);
    await despues.barra.cerrarCaja(caja, efectivoContado: 0, diferencia: 0, quien: 'Marta');
    despues.c.dispose();
    final otraVez = equipo('notebook', deAntes: antes.barra, guardadoDeAntes: antes.guardado, reloj: () => ahora);
    await otraVez.c.read(centralDeLaBarraProvider.notifier).reanudar(_fiesta);
    expect(otraVez.c.read(centralDeLaBarraProvider).prendida, isFalse);
  });

  // La revisión independiente del 26-nov.
  test('la notebook conectada como caja a otra central suelta esa conexión al prender la suya', () async {
    final otra = equipo('b-notebook');
    await otra.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta, barra: 'Barra 2');
    final esta = equipo('a-notebook');
    await esta.c.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(eventoId: _fiesta, nombre: 'Encargada · Romi');
    final cliente = esta.c.read(clienteDeLaBarraProvider)!;
    await hasta(() => cliente.conectada, que: 'LAS CAJAS de la encargada conectada a la otra central');
    await esta.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta, barra: 'Barra 1');
    expect(esta.c.read(centralDeLaBarraProvider).prendida, isTrue);
    expect(esta.c.read(clienteDeLaBarraProvider), isNull,
        reason: 'con el mismo id que su enganche, la otra central los echaba por turno');
  });

  test('prender mientras vuelve sola: de a uno, y queda la última que se pidió', () async {
    var enCurso = 0;
    var masALaVez = 0;
    final notebook = equipo('notebook', elEquipo: () async {
      enCurso++;
      if (enCurso > masALaVez) masALaVez = enCurso;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      enCurso--;
      return 'notebook';
    });
    notebook.guardado.central =
        CentralGuardada(eventoId: _fiesta, desde: DateTime.now().toUtc(), barra: 'Barra 1');
    final central = notebook.c.read(centralDeLaBarraProvider.notifier);
    // Abrir CAJAS la vuelve a prender sola, y enseguida tocan PRENDER con la otra barra.
    final vuelve = central.reanudar(_fiesta);
    final prende = central.prender(_fiesta, barra: 'Barra 2');
    await Future.wait([vuelve, prende]);
    expect(masALaVez, 1, reason: 'nunca dos a medio armar');
    final estado = notebook.c.read(centralDeLaBarraProvider);
    expect(estado.prendida, isTrue);
    expect(estado.barra, 'Barra 2');

    final tablet = equipo('tablet-a');
    await tablet.c
        .read(clienteDeLaBarraProvider.notifier)
        .arrancar(eventoId: _fiesta, nombreCaja: 'Caja 7 · Sofía', barra: 'Barra 2');
    await hasta(() => tablet.c.read(clienteDeLaBarraProvider)!.conectada, que: 'la tablet la encuentra');
    await hasta(() => notebook.c.read(centralDeLaBarraProvider).conectadas == 1, que: 'una sola central la ve');
  });

  test('en la notebook con la central prendida, VENDER no arranca otro cliente', () async {
    final notebook = equipo('notebook');
    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    await notebook.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 9 · Jefe');
    expect(notebook.c.read(clienteDeLaBarraProvider), isNull);
  });

  // 27-nov-2026, lo pidió el usuario: el jefe en MODO JEFE desde una tablet (no desde la
  // notebook) también se conecta. Antes, sin internet, lo que aceptaba no salía de su tablet.
  group('el jefe en modo jefe desde una tablet', () {
    test('se conecta con el PIN maestro, ve el pedido de la cajera y su OK le llega, sin internet', () async {
      final notebook = equipo('notebook');
      final cajera = equipo('tablet-cajera');
      final jefe = equipo('tablet-jefe', quien: () => 'jefe', credencial: () => _personas.credencialDelJefe);
      await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);

      await cajera.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1 · Marta');
      await jefe.c.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(eventoId: _fiesta, nombre: 'Jefe');
      expect(jefe.c.read(clienteDeLaBarraProvider)!.nombreCaja, 'Jefe');
      await hasta(() => notebook.c.read(centralDeLaBarraProvider).conectadas == 2, que: 'las dos tablets conectadas');
      await hasta(() => jefe.c.read(clienteDeLaBarraProvider)!.rol == RolEnLaBarra.jefe, que: 'la central lo deja entrar como jefe');

      final barraCajera = cajera.c.read(barraDeEsteEquipoProvider);
      final caja = await barraCajera.abrirCaja(
        eventoId: _fiesta,
        operadorId: 'op-tablet-cajera',
        operadorNombre: 'Marta',
        numeroCaja: 1,
      );
      final pedido = await barraCajera.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: caja,
        efectivoContado: 27000,
        hechoPor: 'Marta',
        ahora: DateTime.now().toUtc(),
      ));
      await hasta(() => jefe.barra.pasosGuardados.any((p) => p.id == pedido.id), que: 'el pedido en la tablet del jefe');

      final ok = await jefe.c.read(barraDelJefeProvider).anotarPasoDelCierre(PasoDelCierre.responder(
            pedido: pedido,
            tipo: TipoPasoDelCierre.ok,
            hechoPor: 'Jefe',
            ahora: DateTime.now().toUtc(),
          ));
      await hasta(() => cajera.barra.pasosGuardados.any((p) => p.id == ok.id), que: 'el OK del jefe en la tablet de la cajera');
      // Que el OK llegue a la cajera ya dice que la central lo aceptó: lo rechazado no se reparte.
      expect(jefe.c.read(clienteDeLaBarraProvider)!.rechazadas, isEmpty);
    });

    test('la pantalla BARRA del jefe la busca, salvo en la web y sin modo jefe', () {
      final pantalla = File('lib/features/barra/jefe/barra_jefe_screen.dart').readAsStringSync();
      expect(pantalla, contains('if (fiesta != null && esJefe && !enLaWeb) _buscarLaCentral(fiesta.id);'));
      expect(pantalla, contains("arrancarSiNoHay(eventoId: eventoId, nombre: 'Jefe')"));
    });
  });

  // Hasta la 6.8.0 solo VENDER buscaba la central: la encargada que reabría la app y
  // entraba derecho a LAS CAJAS quedaba afuera de la red del salón (revisión del 13-nov).
  group('la encargada que entra directo a LAS CAJAS', () {
    test('se conecta, ve el pedido de la cajera y su OK le llega, sin internet', () async {
      final notebook = equipo('notebook');
      final cajera = equipo('tablet-cajera');
      final encargada = equipo('tablet-encargada');
      await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);

      await cajera.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1 · Marta');
      await encargada.c
          .read(clienteDeLaBarraProvider.notifier)
          .arrancarSiNoHay(eventoId: _fiesta, nombre: 'Encargada · Romi');
      final deLaEncargada = encargada.c.read(clienteDeLaBarraProvider);
      expect(deLaEncargada, isNotNull, reason: 'LAS CAJAS también busca la central');
      expect(deLaEncargada!.nombreCaja, 'Encargada · Romi');
      await hasta(() => notebook.c.read(centralDeLaBarraProvider).conectadas == 2, que: 'las dos tablets conectadas');

      // La cajera pide cerrar: a la encargada le llega por la red del salón.
      final barraCajera = cajera.c.read(barraDeEsteEquipoProvider);
      final caja = await barraCajera.abrirCaja(
        eventoId: _fiesta,
        operadorId: 'op-tablet-cajera',
        operadorNombre: 'Marta',
        numeroCaja: 1,
      );
      final pedido = await barraCajera.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: caja,
        efectivoContado: 27000,
        hechoPor: 'Marta',
        ahora: DateTime.now().toUtc(),
      ));
      await hasta(() => encargada.barra.pasosGuardados.any((p) => p.id == pedido.id), que: 'el pedido en la tablet de la encargada');

      // Y su OK, anotado desde LAS CAJAS (la barra de su equipo), le llega a la cajera.
      final ok = await encargada.c.read(barraDelJefeProvider).anotarPasoDelCierre(PasoDelCierre.responder(
            pedido: pedido,
            tipo: TipoPasoDelCierre.ok,
            hechoPor: 'Romi',
            ahora: DateTime.now().toUtc(),
          ));
      await hasta(() => cajera.barra.pasosGuardados.any((p) => p.id == ok.id), que: 'el OK en la tablet de la cajera');
    });

    test('si VENDER ya la conectó para esa fiesta, queda esa: no se corta ni cambia de nombre', () async {
      final tablet = equipo('tablet-encargada');
      final notifier = tablet.c.read(clienteDeLaBarraProvider.notifier);
      await notifier.arrancar(eventoId: _fiesta, nombreCaja: 'Caja 2 · Romi');
      final deVender = tablet.c.read(clienteDeLaBarraProvider);
      await notifier.arrancarSiNoHay(eventoId: _fiesta, nombre: 'Encargada · Romi');
      expect(identical(tablet.c.read(clienteDeLaBarraProvider), deVender), isTrue);
      expect(tablet.c.read(clienteDeLaBarraProvider)!.nombreCaja, 'Caja 2 · Romi');
    });

    // Revisión del 27-nov-2026: la cajera sale y la encargada entra en esa tablet a LAS
    // CAJAS. La central reconoce a quien puso su PIN al conectarse: si la conexión no se
    // rehace, la sigue tomando por la cajera y rechaza el OK, la anulación o el retiro.
    test('si en la tablet entra otra persona, la conexión se rehace con la suya', () async {
      String? quien = 'operador:sofia';
      final tablet = equipo('tablet-a', quien: () => quien);
      final notifier = tablet.c.read(clienteDeLaBarraProvider.notifier);
      await notifier.arrancar(eventoId: _fiesta, nombreCaja: 'Caja 2 · Sofía');
      final deSofia = tablet.c.read(clienteDeLaBarraProvider);
      expect(deSofia, isNotNull);

      quien = 'operador:romi';
      await notifier.arrancarSiNoHay(eventoId: _fiesta, nombre: 'Encargada · Romi');
      final deRomi = tablet.c.read(clienteDeLaBarraProvider);
      expect(identical(deRomi, deSofia), isFalse, reason: 'la de Sofía se corta');
      expect(deRomi!.nombreCaja, 'Encargada · Romi');

      // La misma caja y el mismo nombre, pero ahora es el jefe en modo jefe: también.
      quien = 'jefe';
      await notifier.arrancar(eventoId: _fiesta, nombreCaja: 'Encargada · Romi');
      expect(identical(tablet.c.read(clienteDeLaBarraProvider), deRomi), isFalse);

      // Y la misma persona de nuevo: queda la que está.
      final delJefe = tablet.c.read(clienteDeLaBarraProvider);
      await notifier.arrancarSiNoHay(eventoId: _fiesta, nombre: 'Jefe');
      expect(identical(tablet.c.read(clienteDeLaBarraProvider), delJefe), isTrue);
    });

    test('en la notebook con la central prendida, tampoco arranca otro cliente', () async {
      final notebook = equipo('notebook');
      await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
      await notebook.c.read(clienteDeLaBarraProvider.notifier).arrancarSiNoHay(eventoId: _fiesta, nombre: 'Encargada');
      expect(notebook.c.read(clienteDeLaBarraProvider), isNull);
    });

    test('el botón LAS CAJAS del inicio de la barra lo hace; la vista que comparte con el jefe, no', () {
      final inicio = File('lib/features/barra/widgets/barra_home_screen.dart').readAsStringSync();
      final abrir = inicio.substring(inicio.indexOf('void _abrirLasCajas('));
      expect(abrir.substring(0, abrir.indexOf('LasCajasScreen(')), contains('arrancarSiNoHay('));
      expect(inicio, contains('onPressed: () => _abrirLasCajas(e)'));
      // La vista de adentro la usan también el jefe en la PC y la web.
      final vista = File('lib/features/barra/jefe/cajas_de_la_fiesta.dart').readAsStringSync();
      expect(vista, isNot(contains('clienteDeLaBarraProvider')));
    });
  });

  test('apagarla cierra la puerta: la tablet pasa a "sin central"', () async {
    final notebook = equipo('notebook');
    final tablet = equipo('tablet-a');
    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    await tablet.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1 · Marta');
    final cliente = tablet.c.read(clienteDeLaBarraProvider)!;
    await hasta(() => cliente.conectada);
    await notebook.c.read(centralDeLaBarraProvider.notifier).apagar();
    expect(notebook.guardado.fiesta, isNull);
    await hasta(() => cliente.estado == EstadoDeLaCentral.sinCentral, que: 'la tablet se da cuenta');
    expect(cliente.desde, isNotNull);
  });

  test('sin la red del salón (la web, las pruebas de pantalla), nada se prende', () async {
    final c = ProviderContainer(overrides: [redDeLaBarraHabilitadaProvider.overrideWithValue(false)]);
    addTearDown(c.dispose);
    await c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    await c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 1');
    expect(c.read(centralDeLaBarraProvider).prendida, isFalse);
    expect(c.read(clienteDeLaBarraProvider), isNull);
  });

  group('lo que dice la línea de VENDER', () {
    final alDia = DateTime(2026, 12, 4, 21, 40);

    test('con internet y nada por subir: Todo subido', () {
      final t = TextosDeLaCaja.de(DatosSinInternetBarra(hayInternet: true, alDia: alDia, fiestas: 1));
      expect(t.subida, 'Todo subido');
      expect(t.tonoSubida, TonoDeLaLinea.bien);
      expect(t.central, isNull, reason: 'sin central, no se dice nada de ella');
    });

    test('lo que falta subir, con internet y sin', () {
      const p = PendientesDeLaBarra(ventas: 2, otros: 1);
      expect(TextosDeLaCaja.de(DatosSinInternetBarra(hayInternet: true, alDia: alDia, pendientes: p)).subida,
          '2 ventas y 1 cambio subiendo');
      expect(TextosDeLaCaja.de(DatosSinInternetBarra(hayInternet: false, alDia: alDia, pendientes: p)).subida,
          'Sin internet · 2 ventas y 1 cambio por subir');
      expect(TextosDeLaCaja.de(DatosSinInternetBarra(hayInternet: false, alDia: alDia)).subida,
          'Sin internet · nada por subir');
    });

    test('la central: buscando, conectada con cuántas cajas, y desde cuándo no', () {
      final d = DatosSinInternetBarra(hayInternet: false, alDia: alDia);
      expect(TextosDeLaCaja.de(d, central: EstadoDeLaCentral.buscando).central, 'Buscando la central…');
      expect(TextosDeLaCaja.de(d, central: EstadoDeLaCentral.conectada, cajas: 3).central, 'Central · 3 cajas');
      expect(TextosDeLaCaja.de(d, central: EstadoDeLaCentral.conectada, cajas: 1).central, 'Central conectada');
      final sin = TextosDeLaCaja.de(
        d,
        central: EstadoDeLaCentral.sinCentral,
        desde: DateTime(2026, 12, 4, 23, 40),
        porMandar: 2,
      );
      expect(sin.central, 'Sin central desde las 23:40 · 2 por mandar');
      expect(sin.tonoCentral, TonoDeLaLinea.atencion);
    });
  });
}
