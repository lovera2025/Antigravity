// **La noche simulada del 4-dic** (etapa C del plan del 28-nov): las dos barras con sus
// notebooks y sus centrales de verdad (servidores, búsqueda por UDP y clientes) por la red
// de esta PC, tres cajas, la encargada en su tablet, otra encargada en el iPhone (la
// página), el repositor, cientos de ventas en efectivo, transferencia y mixto, anulaciones
// con y sin el vale, retiros y cambio, pasada la medianoche. En el medio: **una tablet
// se queda sin señal casi toda la noche y vuelve**, el repositor repone sin señal, la
// notebook de la Barra 1 se apaga y se prende, y las barras se separan y se juntan.
//
// Al final todo tiene que estar en todos lados, una sola vez, y **cada cierre igual al
// centavo** en la cajera, las dos notebooks, la encargada y el iPhone, y el stock igual.
// La hora es de mentira (todo pasa entre las 21 y las 2 de la madrugada); la red, de
// verdad. Sin base, sin nube y sin router.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/dia_de_operacion.dart';
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/pagina/catalogo_de_la_pagina.dart';
import 'package:arguello_events/features/barra/pagina/cliente_de_la_pagina.dart';
import 'package:arguello_events/features/recepcion/central/cliente_central.dart' show GuardadoDelCelular;

import 'helpers/barra_en_memoria.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _b1 = 'Barra 1', _b2 = 'Barra 2';

/// La hora de la noche, para todos los equipos: arranca el viernes 4 a las 21 de
/// Argentina (00 UTC del 5) y la prueba la va pasando.
var _ahora = DateTime.utc(2026, 12, 5, 0, 0);
DateTime _reloj() => _ahora;

late QuienEsQuienEnMemoria _personas;

Future<void> hasta(bool Function() listo, {String? que, int segundos = 20}) async {
  final limite = DateTime.now().add(Duration(seconds: segundos));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<(int, int)> dosPuertosLibres() async {
  final azar = Random();
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

/// Lo que bajó de la nube antes de la fiesta (el catálogo, los precios y el reparto):
/// lo mismo en todos los equipos.
late List<ProductoBarra> _productos;
late List<PrecioBarra> _precios;
late List<StockEnLaBarra> _repartos;

BarraEnMemoria _equipo(String id) {
  final b = BarraEnMemoria()..equipo = id;
  b.reloj = _reloj;
  b.productosGuardados.addAll(_productos);
  b.preciosGuardados.addAll(_precios);
  b.repartosGuardados.addAll(_repartos);
  return b;
}

class _Notebook {
  _Notebook(this.equipo, this.barraDelSalon, this.puertoBusqueda) : barra = _equipo(equipo);

  final String equipo;
  final String barraDelSalon;
  final int puertoBusqueda;
  final BarraEnMemoria barra;
  final preguntaA = <int>[];
  CentralBarra? central;
  RespondeBusqueda? responde;

  Future<void> prender({bool conPagina = false}) async {
    if (!preguntaA.contains(puertoBusqueda)) preguntaA.add(puertoBusqueda);
    final c = CentralBarra(
      eventoId: _fiesta,
      barra: barra,
      quienEsQuien: _personas,
      barraDelSalon: barraDelSalon,
      fiestaParaLaPagina: conPagina
          ? () async => fiestaParaLaPagina(fiestaDePrueba(_fiesta, 'TÉCNICA PINAROLI', DateTime(2026, 12, 4, 22)))
          : null,
      catalogoParaLaPagina: conPagina ? () => catalogoParaLaPagina(barra, _fiesta) : null,
    );
    final puerto = await c.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    final r = RespondeBusqueda(eventoId: _fiesta, puertoCentral: puerto, barra: barraDelSalon, equipo: equipo);
    await r.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4);
    c.engancharConOtras(
      equipo: equipo,
      credencial: () async => _personas.credencialDelJefe,
      buscador: BuscaCentral(
        eventoId: _fiesta,
        cada: const Duration(milliseconds: 100),
        puertos: preguntaA,
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    central = c;
    responde = r;
  }

  Future<void> apagar() async {
    responde?.cerrar();
    responde = null;
    await central?.cerrar();
    central = null;
  }
}

/// Un aparato de una barra (una caja, la encargada o el repositor): su base en memoria,
/// la barra con la red (lo que usan las pantallas) y su conexión con la central.
class _Aparato {
  _Aparato(this.equipo, this.persona, this.barraDelSalon, this.pregunta, {required this.rol, required String pin})
      : barra = _equipo(equipo) {
    credencial = _personas.persona('op-$equipo', persona, pin: pin, rol: rol);
    caja = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
  }

  final String equipo;
  final String persona;
  final String barraDelSalon;
  final List<int> pregunta;
  final RolEnLaBarra rol;
  final BarraEnMemoria barra;
  final aviso = AvisoALaRed();
  late final CredencialDeLaBarra credencial;
  late final BarraConLaRed caja;
  ClienteDeLaCentral? cliente;

  bool get conectado => cliente?.conectada ?? false;

  /// Se conecta (o vuelve la señal): uno nuevo, con lo que ya tiene en su base.
  void conectar() {
    cliente?.dispose();
    final c = ClienteDeLaCentral(
      credencial: () async => credencial,
      eventoId: _fiesta,
      equipo: equipo,
      nombreCaja: '$persona · $barraDelSalon',
      barra: barra,
      barraDeLaCaja: barraDelSalon,
      eleccion: EleccionDeCentral.deLaCaja(barra: barraDelSalon, esperaPorSuBarra: const Duration(seconds: 20)),
      buscador: BuscaCentral(
        eventoId: _fiesta,
        cada: const Duration(milliseconds: 100),
        puertos: pregunta,
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    aviso.salida = c.mandar;
    cliente = c;
    c.arrancar();
  }

  /// Sin señal: sigue trabajando en su base; lo que hace no sale por la red.
  void sinSenial() {
    cliente?.dispose();
    cliente = null;
    aviso.salida = null;
  }
}

class _Navegador implements GuardadoDelCelular {
  final datos = <String, String>{};
  @override
  Future<String?> leer(String clave) async => datos[clave];
  @override
  Future<void> guardar(String clave, String? valor) async =>
      valor == null ? datos.remove(clave) : datos[clave] = valor;
}

void main() {
  late _Notebook barra1, barra2;
  final aparatos = <_Aparato>[];
  ClienteDeLaPagina? iphone;

  setUp(() async {
    _ahora = DateTime.utc(2026, 12, 5, 0, 0);
    _personas = QuienEsQuienEnMemoria();
    final hoy = _reloj();
    _productos = [
      ProductoBarra.nuevo(nombre: 'Speed', categoria: 'Energizantes', orden: 0, ahora: hoy),
      ProductoBarra.nuevo(nombre: 'Cerveza lata', categoria: 'Cervezas', orden: 1, ahora: hoy),
      ProductoBarra.nuevo(nombre: 'Fernet con coca', categoria: 'Tragos', orden: 2, ahora: hoy),
    ];
    _precios = [
      for (final (i, p) in _productos.indexed)
        PrecioBarra.para(
          eventoId: _fiesta,
          productoId: p.id,
          precio: const [5000.0, 3500.0, 6000.0][i],
          stockInicial: const [400, 600, null][i],
          ahora: hoy,
        ),
    ];
    _repartos = [
      for (final barra in [_b1, _b2])
        for (final (i, p) in _productos.take(2).indexed)
          StockEnLaBarra.para(
              eventoId: _fiesta, productoId: p.id, barra: barra, arranque: const [150, 250][i], ahora: hoy),
    ];
    final (p1, p2) = await dosPuertosLibres();
    barra1 = _Notebook('a-notebook', _b1, p1);
    barra2 = _Notebook('b-notebook', _b2, p2);
    await barra1.prender(conPagina: true);
    await barra2.prender();
    // Juntas: cada una pregunta también en la otra.
    barra1.preguntaA.add(p2);
    barra2.preguntaA.add(p1);
  });

  tearDown(() async {
    iphone?.dispose();
    iphone = null;
    for (final a in aparatos) {
      a.sinSenial();
    }
    aparatos.clear();
    await barra1.apagar();
    await barra2.apagar();
  });

  test('una noche entera: todo llega a todos lados una sola vez y cada cierre da igual al centavo', () async {
    final azar = Random(4);
    _Aparato aparato(String equipo, String persona, _Notebook n, RolEnLaBarra rol, String pin) {
      final a = _Aparato(equipo, persona, n.barraDelSalon, [n.puertoBusqueda], rol: rol, pin: pin);
      aparatos.add(a);
      a.conectar();
      return a;
    }

    final marta = aparato('tablet-marta', 'Marta', barra1, RolEnLaBarra.cajera, '1111');
    final sofia = aparato('tablet-sofia', 'Sofía', barra1, RolEnLaBarra.cajera, '2222');
    final lu = aparato('tablet-lu', 'Lu', barra2, RolEnLaBarra.cajera, '3333');
    final romi = aparato('tablet-romi', 'Romi', barra2, RolEnLaBarra.encargada, '7777');
    final nico = aparato('tablet-nico', 'Nico', barra1, RolEnLaBarra.repositor, '5555');
    _personas.persona('op-ana', 'Ana', pin: '4444', rol: RolEnLaBarra.encargada);
    await hasta(() => aparatos.every((a) => a.conectado), que: 'todos conectados');
    await hasta(() => barra1.central!.otras.any((o) => o.conectada) || barra2.central!.otras.any((o) => o.conectada),
        que: 'las dos barras enganchadas');

    // Ana, la otra encargada, con la página en su iPhone, en la Barra 1. Si la notebook
    // se reinicia, vuelve a poner su PIN (la ficha de la noche vive en la central).
    Future<ClienteDeLaPagina> entrarAna() async {
      iphone?.dispose();
      final c = ClienteDeLaPagina(
        servidor: Uri.parse('http://127.0.0.1:${barra1.central!.puerto}/'),
        guardado: _Navegador(),
        abrir: IOWebSocketChannel.connect,
        latido: const Duration(milliseconds: 200),
        silencioMaximo: const Duration(seconds: 3),
        pausas: const [Duration(milliseconds: 100)],
      );
      iphone = c;
      await c.iniciar();
      c.entrar('4444');
      await hasta(() => c.conectada, que: 'Ana en el iPhone');
      return c;
    }

    var ana = await entrarAna();

    // Cada cajera abre su caja a las 21.
    final cajas = <String, CajaBarra>{
      'marta': await marta.caja.abrirCaja(
          eventoId: _fiesta, operadorId: 'op-tablet-marta', operadorNombre: 'Marta', numeroCaja: 1, sede: _b1),
      'sofia': await sofia.caja.abrirCaja(
          eventoId: _fiesta, operadorId: 'op-tablet-sofia', operadorNombre: 'Sofía', numeroCaja: 2, sede: _b1),
      'lu': await lu.caja.abrirCaja(
          eventoId: _fiesta, operadorId: 'op-tablet-lu', operadorNombre: 'Lu', numeroCaja: 7, sede: _b2),
    };
    final deQuien = {'marta': marta, 'sofia': sofia, 'lu': lu};

    // Lo que se hizo, contado por la prueba (para comparar al final).
    final ventas = <VentaBarra>[];
    final anulaciones = <AnulacionBarra>[];
    final movimientosDeCaja = <MovimientoDeCaja>[];
    final movimientosDeStock = <MovimientoDeStock>[];

    var sinSenialVendio = 0;
    Future<void> vender(String quien) async {
      final a = deQuien[quien]!;
      if (a.cliente == null) sinSenialVendio++;
      final i = azar.nextInt(3);
      final cantidad = 1 + azar.nextInt(3);
      final precio = _precios[i].precio;
      final renglones = [RenglonVenta(productoId: _productos[i].id, nombre: _productos[i].nombre, precio: precio, cantidad: cantidad)];
      final total = CuentaBarra(renglones).total;
      final forma = azar.nextInt(5);
      final MedioBarra medio;
      double efectivo = 0, transferencia = 0;
      if (forma < 3) {
        medio = MedioBarra.efectivo;
        efectivo = total;
      } else if (forma == 3) {
        medio = MedioBarra.transferencia;
        transferencia = total;
      } else {
        medio = MedioBarra.mixto;
        efectivo = (total / 2 / 100).floorToDouble() * 100;
        transferencia = total - efectivo;
      }
      ventas.add(await a.caja.vender(
        caja: cajas[quien]!,
        renglones: renglones,
        medio: medio,
        efectivo: efectivo,
        transferencia: transferencia,
        quien: a.persona,
      ));
    }

    var vale = true;
    for (var i = 0; i < 300; i++) {
      _ahora = _ahora.add(const Duration(seconds: 55)); // 300 × 55 s: de las 21 a las 01:35
      final quien = const ['marta', 'sofia', 'lu'][i % 3];
      await vender(quien);

      switch (i) {
        case 20:
          sofia.sinSenial(); // Sofía se queda sin señal casi toda la noche.
        case 40:
          // Se cortan las barras (cada router por su lado).
          barra1.preguntaA.remove(barra2.puertoBusqueda);
          barra2.preguntaA.remove(barra1.puertoBusqueda);
          barra1.central!.volverABuscarLaOtra();
          barra2.central!.volverABuscarLaOtra();
        case 80:
          movimientosDeCaja.add(await romi.caja.anotarMovimientoDeCaja(
            MovimientoDeCaja.nuevo(
              eventoId: _fiesta,
              cajaBarraId: cajas['lu']!.id,
              tipo: TipoMovimientoDeCaja.retiro,
              monto: 10000,
              motivo: 'para el cambio de la otra',
              ahora: _reloj(),
            ),
            quien: 'Romi',
          ));
        case 90:
          movimientosDeCaja.add(await romi.caja.anotarMovimientoDeCaja(
            MovimientoDeCaja.nuevo(
              eventoId: _fiesta,
              cajaBarraId: cajas['lu']!.id,
              tipo: TipoMovimientoDeCaja.cambio,
              monto: 5000,
              motivo: 'se quedó sin cambio',
              ahora: _reloj(),
            ),
            quien: 'Romi',
          ));
        case 100:
          await barra1.apagar(); // Se apaga la notebook de la Barra 1.
        case 130:
          nico.sinSenial(); // El repositor repone sin señal.
          movimientosDeStock.add(await nico.caja.anotarMovimientoDeStock(
            MovimientoDeStock.reposicion(
              eventoId: _fiesta,
              productoId: _productos[0].id,
              barra: _b1,
              cantidad: 24,
              hechoPor: 'Nico',
              ahora: _reloj(),
            ),
            quien: 'Nico',
          ));
        case 140:
          await barra1.prender(conPagina: true); // Vuelve, con otra dirección.
          await hasta(() => ana.estado == EstadoDeLaPagina.pidePin || ana.estado == EstadoDeLaPagina.sinConexion);
          ana = await entrarAna();
        case 150:
          // Las barras se vuelven a ver.
          barra1.preguntaA.add(barra2.puertoBusqueda);
          barra2.preguntaA.add(barra1.puertoBusqueda);
        case 200:
          nico.conectar();
        case 280:
          sofia.conectar(); // Vuelve la señal de Sofía.
      }

      // La encargada anula cada tanto lo que ya le llegó, con y sin el vale.
      if (i % 25 == 10) {
        final conocidas = romi.barra.ventasGuardadas
            .where((v) => !romi.barra.anulacionesGuardadas.any((a) => a.ventaId == v.id))
            .toList();
        if (conocidas.isNotEmpty) {
          final v = conocidas[azar.nextInt(conocidas.length)];
          vale = !vale;
          anulaciones.add(await romi.caja.anular(v, motivo: 'se cobró mal', quien: 'Romi', valeVolvio: vale));
        }
      }
      // Ana, desde el iPhone, anula una sin el vale (cuando la notebook está prendida).
      if (i == 160) {
        await hasta(() => ana.conectada, que: 'el iPhone conectado');
        final conocidas = (await ana.barra.ventas(_fiesta))
            .where((v) => !anulaciones.any((a) => a.ventaId == v.id))
            .toList();
        anulaciones.add(await ana.barra.anular(conocidas.first, motivo: 'se la tomó', quien: 'Ana', valeVolvio: false));
      }
      if (i % 10 == 0) await Future<void>.delayed(const Duration(milliseconds: 30));
    }

    // ── Todo tiene que llegar a todos lados, una sola vez ────────────────────
    final idsVentas = {for (final v in ventas) v.id};
    final idsAnulaciones = {for (final a in anulaciones) a.id};
    final idsMovimientos = {for (final m in movimientosDeCaja) m.id};
    final idsStock = {for (final m in movimientosDeStock) m.id};
    expect(idsVentas, hasLength(300));
    // Que de verdad pasó lo difícil (si no, la prueba no prueba nada).
    expect(sinSenialVendio, greaterThanOrEqualTo(80), reason: 'Sofía vendió casi toda la noche sin señal');
    expect(anulaciones.where((a) => a.valeVolvio), isNotEmpty, reason: 'anuladas con el vale');
    expect(anulaciones.where((a) => !a.valeVolvio), hasLength(greaterThanOrEqualTo(2)), reason: 'y sin el vale');
    expect(anulaciones.any((a) => a.hechoPor == 'Ana'), isTrue, reason: 'una desde el iPhone');
    final equipos = <String, BarraEnMemoria>{
      'notebook 1': barra1.barra,
      'notebook 2': barra2.barra,
      for (final a in aparatos) a.equipo: a.barra,
    };
    bool alDia(BarraEnMemoria b) =>
        {for (final v in b.ventasGuardadas) v.id}.containsAll(idsVentas) &&
        {for (final a in b.anulacionesGuardadas) a.id}.containsAll(idsAnulaciones) &&
        {for (final m in b.movimientosDeCajaGuardados) m.id}.containsAll(idsMovimientos) &&
        {for (final m in b.movimientosGuardados) m.id}.containsAll(idsStock);
    for (final e in equipos.entries) {
      await hasta(() => alDia(e.value), que: 'todo en ${e.key}', segundos: 40);
      expect(e.value.ventasGuardadas.length, {for (final v in e.value.ventasGuardadas) v.id}.length,
          reason: '${e.key}: ninguna venta repetida');
      expect(e.value.anulacionesGuardadas.length, {for (final a in e.value.anulacionesGuardadas) a.ventaId}.length,
          reason: '${e.key}: una anulación por venta');
    }
    await hasta(() => ana.conectada, que: 'el iPhone conectado al final');
    for (var i = 0; i < 400; i++) {
      final suyas = {for (final v in await ana.barra.ventas(_fiesta)) v.id};
      final anuladas = {for (final a in await ana.barra.anulaciones(_fiesta)) a.id};
      if (suyas.containsAll(idsVentas) && anuladas.containsAll(idsAnulaciones)) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect({for (final v in await ana.barra.ventas(_fiesta)) v.id}, containsAll(idsVentas), reason: 'todo en el iPhone');

    // Todas las ventas son de la noche del viernes 4, aunque sean de madrugada.
    final porDia = CajasPorDia.de(barra2.barra.cajasGuardadas);
    for (final v in barra2.barra.ventasGuardadas) {
      expect(porDia.diaDeLaVenta(v), const DiaDeOperacion(2026, 12, 4), reason: 'la venta de las ${v.createdAt}');
    }
    expect(_ahora.toUtc().hour, lessThan(6), reason: 'la prueba pasó la medianoche');

    // ── Cada cierre, igual al centavo en todos lados ─────────────────────────
    String cierre(Iterable<VentaBarra> vs, Iterable<AnulacionBarra> an, Iterable<MovimientoDeCaja> mv, CajaBarra c) {
      final x = CierreDeBarra.de(c, vs, an, movimientos: mv);
      return '${centavos(x.efectivoEsperado)} ${centavos(x.transferencia)} ${centavos(x.total)} ${x.ventas} ${x.anuladas}';
    }

    for (final c in cajas.values) {
      // Lo que tiene que dar, contado por la prueba.
      final esperado = cierre(ventas, anulaciones, movimientosDeCaja, c);
      for (final e in equipos.entries) {
        expect(
          cierre(e.value.ventasGuardadas, e.value.anulacionesGuardadas, e.value.movimientosDeCajaGuardados, c),
          esperado,
          reason: 'Caja ${c.numeroCaja} en ${e.key}',
        );
      }
      expect(
        cierre(await ana.barra.ventas(_fiesta), await ana.barra.anulaciones(_fiesta),
            await ana.barra.movimientosDeCaja(_fiesta), c),
        esperado,
        reason: 'Caja ${c.numeroCaja} en el iPhone de Ana',
      );
    }

    // ── El stock, igual en todos lados ───────────────────────────────────────
    String stock(BarraEnMemoria b) {
      final s = StockPorBarra.deLaNoche(
        eventoId: _fiesta,
        precios: _precios,
        repartos: _repartos,
        movimientos: b.movimientosGuardados,
        ventas: b.ventasGuardadas,
        anulaciones: b.anulacionesGuardadas,
        cajas: CajasPorDia.de(b.cajasGuardadas),
        dia: const DiaDeOperacion(2026, 12, 4),
      );
      return [
        for (final barra in [_b1, _b2])
          for (final p in _productos.take(2)) '$barra ${p.nombre} ${s.en(barra, p.id)?.queda}',
      ].join(' · ');
    }

    final stockDeLaNotebook = stock(barra1.barra);
    for (final e in equipos.entries) {
      expect(stock(e.value), stockDeLaNotebook, reason: 'el stock en ${e.key}');
    }

    // ── GANANCIA, igual en las dos notebooks ─────────────────────────────────
    String ganancia(BarraEnMemoria b) {
      final c = CuentaDelProveedor.de([
        FiestaParaLaGanancia(
          eventoId: _fiesta,
          nombre: 'TÉCNICA',
          fecha: DateTime(2026, 12, 4),
          cajas: b.cajasGuardadas,
          ventas: b.ventasGuardadas,
          anulaciones: b.anulacionesGuardadas,
          precios: _precios,
          repartos: _repartos,
          movimientos: b.movimientosGuardados,
          listas: {for (final p in _productos) p.id: 1000},
        ),
      ]);
      return '${c.seVendio} ${c.leDebo} ${c.perdidas} ${c.vendidas}';
    }

    expect(ganancia(barra2.barra), ganancia(barra1.barra));
    expect(ganancia(barra1.barra).split(' ')[2], isNot('0'), reason: 'lo entregado sin el vale cuenta como perdido');

    // ── Y se cierran las tres cajas con el OK de la encargada ────────────────
    for (final e in cajas.entries) {
      final a = deQuien[e.key]!;
      final c = e.value;
      final cuenta = CierreDeBarra.de(c, a.barra.ventasGuardadas, a.barra.anulacionesGuardadas,
          movimientos: a.barra.movimientosDeCajaGuardados);
      final pedido = await a.caja.anotarPasoDelCierre(PasoDelCierre.pedir(
        caja: c,
        efectivoContado: cuenta.efectivoEsperado,
        hechoPor: a.persona,
        ahora: _reloj(),
      ));
      await hasta(() => romi.barra.pasosGuardados.any((p) => p.id == pedido.id), que: 'el pedido de ${a.persona}');
      final ok = await romi.caja.anotarPasoDelCierre(PasoDelCierre.responder(
        pedido: pedido,
        tipo: TipoPasoDelCierre.ok,
        hechoPor: 'Romi',
        ahora: _reloj(),
      ));
      await hasta(() => a.barra.pasosGuardados.any((p) => p.id == ok.id), que: 'el OK en la tablet de ${a.persona}');
      final cerrada = await a.caja.cerrarCaja(c,
          efectivoContado: cuenta.efectivoEsperado, diferencia: 0, quien: a.persona);
      await hasta(
        () => barra1.barra.cajasGuardadas.any((x) => x.id == cerrada.id && !x.abierta) &&
            barra2.barra.cajasGuardadas.any((x) => x.id == cerrada.id && !x.abierta),
        que: 'la Caja ${c.numeroCaja} cerrada en las dos notebooks',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
