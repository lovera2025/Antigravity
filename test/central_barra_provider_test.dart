import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra_provider.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/linea_de_la_caja.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/providers/barra_del_jefe_provider.dart';
import 'package:arguello_events/features/barra/services/barra_sin_internet.dart';
import 'package:arguello_events/features/common/widgets/operational_sync_coordinator.dart';

import 'helpers/barra_en_memoria.dart';

/// La central de la barra como la arma la app: la notebook la prende desde BARRA y la
/// tablet la encuentra sola al abrir VENDER, cada una con sus providers. Por la red de
/// esta PC (loopback), con barras en memoria.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

class _GuardadoEnMemoria extends GuardadoDeLaCentral {
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

Future<void> hasta(bool Function() listo, {String? que}) async {
  final limite = DateTime.now().add(const Duration(seconds: 6));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late int puertoBusqueda;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    puertoBusqueda = s.port;
    s.close();
  });

  ({ProviderContainer c, BarraEnMemoria barra, _GuardadoEnMemoria guardado}) equipo(String id) {
    final barra = BarraEnMemoria()
      ..equipo = id
      ..reloj = (() => DateTime.now().toUtc());
    final aviso = AvisoALaRed();
    final guardado = _GuardadoEnMemoria();
    final c = ProviderContainer(overrides: [
      avisoALaRedProvider.overrideWithValue(aviso),
      barraDeEsteEquipoProvider.overrideWithValue(BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso)),
      barraDeLaRedProvider.overrideWithValue(barra),
      escuchaCentralBarraProvider.overrideWithValue(InternetAddress.loopbackIPv4),
      puertoCentralBarraProvider.overrideWithValue(0),
      puertoBusquedaBarraProvider.overrideWithValue(puertoBusqueda),
      destinosBusquedaBarraProvider.overrideWithValue(() async => [InternetAddress.loopbackIPv4]),
      direccionesCentralBarraProvider.overrideWithValue(() async => ['192.168.0.10']),
      equipoDeLaBarraProvider.overrideWithValue(() async => id),
      guardadoDeLaCentralProvider.overrideWithValue(guardado),
    ]);
    addTearDown(c.dispose);
    return (c: c, barra: barra, guardado: guardado);
  }

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
      operadorId: UuidUtils.generate(),
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

  test('en la notebook con la central prendida, VENDER no arranca otro cliente', () async {
    final notebook = equipo('notebook');
    await notebook.c.read(centralDeLaBarraProvider.notifier).prender(_fiesta);
    await notebook.c.read(clienteDeLaBarraProvider.notifier).arrancar(eventoId: _fiesta, nombreCaja: 'Caja 9 · Jefe');
    expect(notebook.c.read(clienteDeLaBarraProvider), isNull);
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
