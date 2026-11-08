import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/uuid_utils.dart';
import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/filas_de_la_red.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

import 'helpers/barra_en_memoria.dart';

/// La central de la barra de verdad: el servidor y dos tablets, por la red de esta PC
/// (loopback), cada una con su barra en memoria. Sin base, sin nube y sin router.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';

/// Una tablet: su barra en memoria, la barra con la red (lo que usa VENDER) y su cliente.
class _Tablet {
  _Tablet(String equipo, String nombre, DondeEstaLaCentral? donde, {String fiesta = _fiesta, BuscaCentral? buscador})
      : barra = BarraEnMemoria()..equipo = equipo {
    barra.reloj = () => DateTime.now().toUtc();
    cliente = ClienteDeLaCentral(
      eventoId: fiesta,
      equipo: equipo,
      nombreCaja: nombre,
      barra: barra,
      alGuardar: () => llegadas++,
      aMano: donde,
      buscador: buscador,
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 50),
    );
    aviso.salida = cliente.mandar;
    caja = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
  }

  final BarraEnMemoria barra;
  final aviso = AvisoALaRed();
  late final ClienteDeLaCentral cliente;
  late final BarraConLaRed caja;
  var llegadas = 0;

  Future<CajaBarra> abrir(int numero) => caja.abrirCaja(
        eventoId: _fiesta,
        operadorId: UuidUtils.generate(),
        operadorNombre: 'Cajera $numero',
        numeroCaja: numero,
      );

  Future<VentaBarra> vender(CajaBarra c, {int cantidad = 1}) => caja.vender(
        caja: c,
        renglones: [RenglonVenta(productoId: 'p', nombre: 'Cerveza lata', precio: 3500, cantidad: cantidad)],
        medio: MedioBarra.efectivo,
        efectivo: 3500.0 * cantidad,
        quien: 'Cajera',
      );
}

/// Espera hasta que [listo] o tira a los 5 s.
Future<void> hasta(bool Function() listo, {String? que}) async {
  final limite = DateTime.now().add(const Duration(seconds: 5));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late BarraEnMemoria notebook;
  late CentralBarra central;
  late DondeEstaLaCentral donde;
  var guardadas = 0;
  final aCerrar = <_Tablet>[];

  setUp(() async {
    guardadas = 0;
    notebook = BarraEnMemoria()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    central = CentralBarra(eventoId: _fiesta, barra: notebook, alGuardar: () => guardadas++);
    final puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    donde = DondeEstaLaCentral('127.0.0.1', puerto);
  });

  tearDown(() async {
    for (final t in aCerrar) {
      t.cliente.dispose();
    }
    aCerrar.clear();
    await central.cerrar();
  });

  _Tablet tablet(String equipo, String nombre, {String fiesta = _fiesta, DondeEstaLaCentral? en, BuscaCentral? buscador}) {
    final t = _Tablet(equipo, nombre, buscador == null ? (en ?? donde) : null, fiesta: fiesta, buscador: buscador);
    aCerrar.add(t);
    t.cliente.arrancar();
    return t;
  }

  test('lo que vende una caja le llega a la notebook y a la otra caja, sin subirlo de nuevo', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    final b = tablet('tablet-b', 'Caja 2 · Sofía');
    await hasta(() => a.cliente.conectada && b.cliente.conectada, que: 'las dos conectadas');

    final caja = await a.abrir(1);
    final venta = await a.vender(caja, cantidad: 2);
    await hasta(() => b.barra.ventasGuardadas.any((v) => v.id == venta.id), que: 'la venta en la caja B');
    expect(notebook.ventasGuardadas.map((v) => v.id), contains(venta.id));
    expect(notebook.cajasGuardadas.map((c) => c.id), contains(caja.id));
    expect(b.barra.ventasGuardadas.single.renglones.single.cantidad, 2);
    expect(b.barra.sinSubir, isEmpty, reason: 'lo de otra caja no se encola: lo sube la que vendió');
    expect(notebook.sinSubir, isEmpty);
    expect(b.llegadas, greaterThan(0), reason: 'VENDER de la caja B se rehace');
    expect(guardadas, greaterThan(0), reason: 'CAJAS de la notebook se rehace');
    expect(a.barra.sinSubir, contains(venta.id), reason: 'la que vendió la sigue teniendo para subir');
  });

  test('la caja que se conecta tarde recibe todo lo de la fiesta', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    await hasta(() => a.cliente.conectada);
    final caja = await a.abrir(1);
    for (var i = 0; i < 3; i++) {
      await a.vender(caja);
    }
    await hasta(() => notebook.ventasGuardadas.length == 3, que: 'las tres en la notebook');

    final b = tablet('tablet-b', 'Caja 2 · Sofía');
    await hasta(() => b.barra.ventasGuardadas.length == 3, que: 'las tres en la caja B');
    expect(b.barra.cajasGuardadas.single.id, caja.id);
  });

  test('sin central se sigue vendiendo; al volver manda lo suyo y nada se duplica', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    final b = tablet('tablet-b', 'Caja 2 · Sofía');
    await hasta(() => a.cliente.conectada && b.cliente.conectada);
    final caja = await a.abrir(1);
    final primera = await a.vender(caja);
    await hasta(() => b.barra.ventasGuardadas.length == 1);

    // Se apaga la notebook.
    await central.cerrar();
    await hasta(() => a.cliente.estado == EstadoDeLaCentral.sinCentral, que: 'la caja A se da cuenta');
    expect(a.cliente.desde, isNotNull);
    final segunda = await a.vender(caja);
    final tercera = await a.vender(caja);
    expect(a.cliente.porMandar, 2);
    expect(a.barra.ventasGuardadas, hasLength(3), reason: 'vender no espera a la central');

    // Vuelve, en otro puerto (el de antes quedó tomado).
    central = CentralBarra(eventoId: _fiesta, barra: notebook, alGuardar: () => guardadas++);
    final puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    final nueva = DondeEstaLaCentral('127.0.0.1', puerto);
    a.cliente.ponerAMano(nueva);
    b.cliente.ponerAMano(nueva);
    await hasta(() => a.cliente.conectada && b.cliente.conectada, que: 'las dos de vuelta');
    await hasta(() => b.barra.ventasGuardadas.length == 3, que: 'las tres en la caja B');
    expect(a.cliente.porMandar, 0);
    expect(a.cliente.desde, isNull);
    for (final v in [primera, segunda, tercera]) {
      expect(notebook.ventasGuardadas.where((x) => x.id == v.id), hasLength(1), reason: 'sin duplicar');
      expect(b.barra.ventasGuardadas.where((x) => x.id == v.id), hasLength(1));
    }
  });

  test('cerrar la caja llega a la notebook: deja de estar abierta', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    await hasta(() => a.cliente.conectada);
    final caja = await a.abrir(1);
    await a.vender(caja);
    await hasta(() => notebook.cajasGuardadas.any((c) => c.id == caja.id));
    // Que pase el tiempo: la caja cerrada es más nueva que la abierta.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.caja.cerrarCaja(caja, efectivoContado: 3000, diferencia: -500, quien: 'Cajera 1');
    await hasta(() => notebook.cajasGuardadas.single.abierta == false, que: 'la caja cerrada en la notebook');
    expect(notebook.cajasGuardadas.single.diferencia, -500);
  });

  test('lo que anula el jefe en la notebook les llega a las cajas', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    final b = tablet('tablet-b', 'Caja 2 · Sofía');
    await hasta(() => a.cliente.conectada && b.cliente.conectada);
    final caja = await a.abrir(1);
    final venta = await a.vender(caja);
    await hasta(() => notebook.ventasGuardadas.any((v) => v.id == venta.id));

    final avisoDeLaNotebook = AvisoALaRed()..salida = central.difundirDeEstaPc;
    final jefe = BarraConLaRed(caja: notebook, jefe: notebook, red: notebook, aviso: avisoDeLaNotebook);
    final venDeLaNotebook = notebook.ventasGuardadas.single;
    await jefe.anular(venDeLaNotebook, motivo: 'se cobró dos veces', quien: 'Jefe');
    await hasta(() => a.barra.anulacionesGuardadas.isNotEmpty && b.barra.anulacionesGuardadas.isNotEmpty,
        que: 'la anulación en las dos cajas');
    expect(a.barra.anulacionesGuardadas.single.ventaId, venta.id);
    expect(b.barra.anulacionesGuardadas.single.hechoPor, 'Jefe');
  });

  test('el latido le cuenta a la notebook lo que cada caja tiene sin subir', () async {
    final a = tablet('tablet-a', 'Caja 1 · Marta');
    await hasta(() => a.cliente.conectada);
    final caja = await a.abrir(1);
    await a.vender(caja);
    await hasta(() => central.cajas.single.porSubir.ventas == 1, que: 'la notebook sabe que tiene 1 venta sin subir');
    expect(central.cajas.single.nombre, 'Caja 1 · Marta');
    expect(central.cajas.single.porSubir.otros, greaterThan(0), reason: 'la caja abierta tampoco subió');

    a.barra.subioTodo();
    await hasta(() => central.cajas.single.porSubir.vacio, que: 'al día');
    await hasta(() => a.cliente.cajas == 1, que: 'la caja sabe cuántas hay conectadas');
  });

  test('una caja de otra fiesta no entra', () async {
    final otra = tablet('tablet-x', 'Caja 9 · Otra', fiesta: _otraFiesta);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(otra.cliente.conectada, isFalse);
    expect(central.cajas, isEmpty);
  });

  test('la caja encuentra sola a la central, preguntando por la red', () async {
    // Un puerto de búsqueda libre en esta PC.
    final prueba = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final puertoBusqueda = prueba.port;
    prueba.close();
    final responde = RespondeBusqueda(eventoId: _fiesta, puertoCentral: central.puerto!);
    expect(await responde.escuchar(puerto: puertoBusqueda, en: InternetAddress.loopbackIPv4), isTrue);
    addTearDown(responde.cerrar);

    final a = tablet(
      'tablet-a',
      'Caja 1 · Marta',
      buscador: BuscaCentral(
        eventoId: _fiesta,
        puerto: puertoBusqueda,
        cada: const Duration(milliseconds: 100),
        destinos: () async => [InternetAddress.loopbackIPv4],
      ),
    );
    await hasta(() => a.cliente.conectada, que: 'la encontró y se conectó');
    expect(a.cliente.donde?.puerto, central.puerto);
  });

  group('lo que se guarda de otro equipo', () {
    test('lo que esta caja tiene sin subir manda: no lo pisa lo que llega', () async {
      final b = BarraEnMemoria();
      final caja = await b.abrirCaja(eventoId: _fiesta, operadorId: 'o', operadorNombre: 'M', numeroCaja: 1);
      final vieja = Map<String, Object?>.from(caja.toMap())..['nota_cierre'] = 'de otro';
      expect(await b.guardarDeOtroEquipo('barra_cajas', vieja), isFalse);
    });

    test('una versión más vieja no pisa la más nueva, y la misma no cambia nada', () {
      final nueva = {'id': 'x', 'updated_at': '2026-12-05T02:10:00Z', 'cerrada_at': '2026-12-05T02:10:00Z'};
      final vieja = {'id': 'x', 'updated_at': '2026-12-05T01:00:00Z', 'cerrada_at': null};
      expect(cambiaLaFila(nueva: vieja, vieja: nueva), isFalse, reason: 'la caja cerrada no vuelve a abierta');
      expect(cambiaLaFila(nueva: nueva, vieja: vieja), isTrue);
      expect(cambiaLaFila(nueva: nueva, vieja: Map.of(nueva)), isFalse);
    });

    test('solo las cuatro tablas de las cajas, y solo de su fiesta', () {
      const id = 'b0000000-0000-4000-8000-000000000001';
      expect(filaDeLaFiesta('barra_ventas', {'id': id, 'evento_id': _fiesta}, _fiesta), isTrue);
      expect(filaDeLaFiesta('barra_ventas', {'id': id, 'evento_id': _otraFiesta}, _fiesta), isFalse);
      expect(filaDeLaFiesta('barra_precios', {'id': id, 'evento_id': _fiesta}, _fiesta), isFalse,
          reason: 'los precios van por la nube');
      expect(filaDeLaFiesta('barra_ventas', {'id': 'corto', 'evento_id': _fiesta}, _fiesta), isFalse);
    });

    test('lo que espera subir, en palabras', () {
      expect(const PendientesDeLaBarra(ventas: 2, otros: 1).enPalabras, '2 ventas y 1 cambio');
      expect(const PendientesDeLaBarra(ventas: 1).enPalabras, '1 venta');
      expect(const PendientesDeLaBarra(otros: 3).enPalabras, '3 cambios');
      expect(PendientesDeLaBarra.nada.vacio, isTrue);
    });

    test('la dirección escrita a mano se entiende', () {
      expect(DondeEstaLaCentral.deTexto('192.168.0.10:8797'), const DondeEstaLaCentral('192.168.0.10', 8797));
      expect(DondeEstaLaCentral.deTexto(' 192.168.0.10 · 8797 '), const DondeEstaLaCentral('192.168.0.10', 8797));
      expect(DondeEstaLaCentral.deTexto('192.168.0.10'), isNull);
      expect(DondeEstaLaCentral.deTexto('hola'), isNull);
    });
  });
}
