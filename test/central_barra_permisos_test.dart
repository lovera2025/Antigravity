import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:arguello_events/features/barra/central/barra_con_la_red.dart';
import 'package:arguello_events/features/barra/central/buscar_central.dart';
import 'package:arguello_events/features/barra/central/central_barra.dart';
import 'package:arguello_events/features/barra/central/cliente_de_la_central.dart';
import 'package:arguello_events/features/barra/central/llave_de_la_barra.dart';
import 'package:arguello_events/features/barra/cuentas/pedido_de_cierre.dart';
import 'package:arguello_events/features/barra/cuentas/reglas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/datos/movimiento_de_stock.dart';
import 'package:arguello_events/features/barra/datos/stock_en_la_barra.dart';

import 'helpers/barra_en_memoria.dart';

/// **La central de la barra solo deja entrar a quien puso su PIN, y de cada uno acepta lo
/// que le toca** (26-nov-2026; la revisión de los permisos encontró que cualquier aparato
/// del wifi que supiera el número de la fiesta podía anular, mandar un OK falso o cerrar
/// una caja). Con la central de verdad, por la red de esta PC (loopback).
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

Future<void> hasta(bool Function() listo, {String? que, int segundos = 6}) async {
  final limite = DateTime.now().add(Duration(seconds: segundos));
  while (!listo()) {
    if (DateTime.now().isAfter(limite)) fail('no pasó: ${que ?? 'lo esperado'}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Aparato {
  _Aparato(this.equipo, this.persona, CredencialDeLaBarra? cred, DondeEstaLaCentral donde)
      : barra = BarraEnMemoria()..equipo = equipo {
    barra.reloj = () => DateTime.now().toUtc();
    cliente = ClienteDeLaCentral(
      credencial: () async => cred,
      eventoId: _fiesta,
      equipo: equipo,
      nombreCaja: 'Caja · $persona',
      barra: barra,
      aMano: donde,
      latido: const Duration(milliseconds: 100),
      silencioMaximo: const Duration(seconds: 2),
      pausa: const Duration(milliseconds: 100),
    );
    aviso.salida = cliente.mandar;
    caja = BarraConLaRed(caja: barra, jefe: barra, red: barra, aviso: aviso);
    cliente.arrancar();
  }

  final String equipo;
  final String persona;
  final BarraEnMemoria barra;
  final aviso = AvisoALaRed();
  late final ClienteDeLaCentral cliente;
  late final BarraConLaRed caja;

  String get operadorId => 'op-$equipo';

  Future<CajaBarra> abrir(int n) =>
      caja.abrirCaja(eventoId: _fiesta, operadorId: operadorId, operadorNombre: persona, numeroCaja: n);

  Future<VentaBarra> vender(CajaBarra c) => caja.vender(
        caja: c,
        renglones: const [RenglonVenta(productoId: 'p', nombre: 'Fernet', precio: 6000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 6000,
        quien: persona,
      );

  bool rechazo(String motivo) => cliente.rechazadas.any((r) => r.motivo == motivo);
}

void main() {
  late QuienEsQuienEnMemoria personas;
  late BarraEnMemoria notebook;
  late CentralBarra central;
  late DondeEstaLaCentral donde;
  final aCerrar = <void Function()>[];

  setUp(() async {
    personas = QuienEsQuienEnMemoria(maestro: '8642');
    notebook = BarraEnMemoria()..equipo = 'notebook';
    notebook.reloj = () => DateTime.now().toUtc();
    central = CentralBarra(
      eventoId: _fiesta,
      barra: notebook,
      quienEsQuien: personas,
      esperaDelPin: const Duration(milliseconds: 600),
    );
    final puerto = await central.arrancar(desde: 0, en: InternetAddress.loopbackIPv4);
    donde = DondeEstaLaCentral('127.0.0.1', puerto);
  });

  tearDown(() async {
    for (final c in aCerrar.reversed) {
      c();
    }
    aCerrar.clear();
    await central.cerrar();
  });

  _Aparato aparato(String equipo, String persona, {RolEnLaBarra? rol = RolEnLaBarra.cajera, String? pinQuePone}) {
    final cred = personas.persona('op-$equipo', persona, pin: '1234', rol: rol);
    final usa = pinQuePone == null ? cred : CredencialDeLaBarra.operador('op-$equipo', pinQuePone);
    final a = _Aparato(equipo, persona, usa, donde);
    aCerrar.add(a.cliente.dispose);
    return a;
  }

  /// Un aparato cualquiera del wifi: se conecta y manda lo que quiera, sin PIN.
  Future<({WebSocketChannel canal, List<Map<String, dynamic>> llegaron})> deAfuera(String equipo) async {
    final canal = WebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:${donde.puerto}/barra?evento=$_fiesta&equipo=$equipo&caja=Intruso&r=0123456789abcdef0123'));
    final llegaron = <Map<String, dynamic>>[];
    canal.stream.listen((m) {
      if (m is String) llegaron.add(jsonDecode(m) as Map<String, dynamic>);
    }, onError: (_) {});
    aCerrar.add(() => canal.sink.close());
    await canal.ready;
    return (canal: canal, llegaron: llegaron);
  }

  group('el PIN', () {
    test('un aparato sin PIN no recibe nada, no guarda nada y se lo corta', () async {
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => a.cliente.conectada);
      final c = await a.abrir(1);
      await a.vender(c);
      await hasta(() => notebook.ventasGuardadas.length == 1);

      final intruso = await deAfuera('intruso');
      final venta = notebook.ventasGuardadas.single;
      final falsa = AnulacionBarra.de(venta, motivo: 'me la llevo', ahora: DateTime.now()).toMap();
      intruso.canal.sink.add(jsonEncode({'t': 'filas', 'filas': {'barra_anulaciones': [falsa]}}));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(notebook.anulacionesGuardadas, isEmpty, reason: 'sin PIN no se guarda nada');
      expect(a.barra.anulacionesGuardadas, isEmpty);
      expect(intruso.llegaron.map((m) => m['t']), ['reto'], reason: 'ni una fila de la fiesta');
      expect(intruso.canal.closeCode, 4005);
    });

    test('un aparato sin PIN que dice ser una tablet no la echa', () async {
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => a.cliente.conectada);
      await deAfuera('tablet-a');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(a.cliente.conectada, isTrue);
      expect(central.conectadas, 1);
    });

    test('con un PIN equivocado no entra, y la tablet dice por qué', () async {
      final a = aparato('tablet-a', 'Marta', pinQuePone: '9999');
      await hasta(() => a.cliente.problema != null, que: 'dice el problema');
      expect(a.cliente.problema, contains('no reconoce tu PIN'));
      expect(a.cliente.conectada, isFalse);
      expect(central.cajas, isEmpty);
    });

    test('un operador sin permiso de barra no entra', () async {
      final a = aparato('tablet-a', 'Juan', rol: null);
      await hasta(() => a.cliente.problema != null);
      expect(a.cliente.problema, 'Tu PIN no tiene permiso de barra');
      expect(a.cliente.conectada, isFalse);
    });

    test('el jefe entra con el PIN maestro de la notebook, y con otro no', () async {
      final jefe = _Aparato('pc-jefe', 'Jefe', CredencialDeLaBarra.maestro('8642'), donde);
      aCerrar.add(jefe.cliente.dispose);
      await hasta(() => jefe.cliente.conectada);
      expect(jefe.cliente.rol, RolEnLaBarra.jefe);
      final otro = _Aparato('pc-otro', 'Jefe', CredencialDeLaBarra.maestro('2026'), donde);
      aCerrar.add(otro.cliente.dispose);
      await hasta(() => otro.cliente.problema != null);
      expect(otro.cliente.conectada, isFalse);
    });

    test('una notebook de afuera no se hace pasar por la central', () async {
      // Contesta el reto y deja pasar, pero no conoce el PIN: no puede firmar.
      final falsa = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      aCerrar.add(() => falsa.close(force: true));
      falsa.listen((pedido) async {
        final ws = await WebSocketTransformer.upgrade(pedido);
        ws.add(jsonEncode({'t': 'reto', 'n': 'abcdef0123456789abcd'}));
        final venta = VentaBarra.nueva(
          cajaBarraId: 'c0000000-0000-4000-8000-0000000000c1',
          eventoId: _fiesta,
          numero: 1,
          renglones: const [RenglonVenta(productoId: 'p', nombre: 'Fernet', precio: 6000, cantidad: 1)],
          medio: MedioBarra.efectivo,
          efectivo: 6000,
          deviceId: 'otra',
          ahora: DateTime.now(),
        );
        final falsa = AnulacionBarra.de(venta, motivo: 'falsa', ahora: DateTime.now()).toMap();
        ws.listen((_) {
          // Filas antes y después de dejarla pasar: ninguna se guarda.
          ws.add(jsonEncode({'t': 'filas', 'filas': {'barra_anulaciones': [falsa]}}));
          ws.add(jsonEncode({'t': 'adelante', 'rol': 'cajera', 'prueba': 'cualquiera'}));
          ws.add(jsonEncode({'t': 'filas', 'filas': {'barra_anulaciones': [falsa]}}));
        });
      });
      final cred = personas.persona('op-tablet-a', 'Marta');
      final a = _Aparato('tablet-a', 'Marta', cred, DondeEstaLaCentral('127.0.0.1', falsa.port));
      aCerrar.add(a.cliente.dispose);
      await hasta(() => a.cliente.problema != null);
      expect(a.cliente.problema, 'Esa no es la central de la barra');
      expect(a.cliente.conectada, isFalse);
      expect(a.barra.anulacionesGuardadas, isEmpty);
    });
  });

  group('lo que le toca a cada uno', () {
    test('la cajera no anula: la central no lo guarda ni lo reparte, y se lo dice', () async {
      final a = aparato('tablet-a', 'Marta');
      final b = aparato('tablet-b', 'Sofía');
      await hasta(() => a.cliente.conectada && b.cliente.conectada);
      final c = await a.abrir(1);
      final v = await a.vender(c);
      await hasta(() => notebook.ventasGuardadas.length == 1);
      await a.barra.anular(v, motivo: 'error', quien: 'Marta');
      await a.cliente.mandar('barra_anulaciones', a.barra.anulacionesGuardadas.single.id);
      await hasta(() => a.rechazo('Anula solo la encargada'), que: 'se lo dice a la tablet');
      expect(notebook.anulacionesGuardadas, isEmpty);
      expect(b.barra.anulacionesGuardadas, isEmpty);
      expect(central.rechazos.single.motivo, 'Anula solo la encargada');
    });

    test('la encargada anula desde su aparato, y con su PIN en la tablet de la cajera también', () async {
      final a = aparato('tablet-a', 'Marta');
      final e = aparato('iphone-romi', 'Romi', rol: RolEnLaBarra.encargada);
      await hasta(() => a.cliente.conectada && e.cliente.conectada);
      final c = await a.abrir(1);
      final v1 = await a.vender(c);
      final v2 = await a.vender(c);
      await hasta(() => e.barra.ventasGuardadas.length == 2);
      await e.caja.anular(e.barra.ventasGuardadas.firstWhere((v) => v.id == v1.id), motivo: 'doble', quien: 'Romi');
      await hasta(() => a.barra.anulacionesGuardadas.any((x) => x.ventaId == v1.id), que: 'llega a la cajera');
      // En la tablet de la cajera, firmada por la encargada.
      await a.caja.anularConLaEncargada(v2, motivo: 'se equivocó', encargada: 'Romi');
      await hasta(() => notebook.anulacionesGuardadas.any((x) => x.ventaId == v2.id), que: 'la de la tablet');
      expect(central.rechazos, isEmpty);
    });

    test('nadie le da el OK a otra caja sin ser encargada, ni la encargada a la suya', () async {
      final a = aparato('tablet-a', 'Marta');
      final b = aparato('tablet-b', 'Sofía');
      final e = aparato('tablet-e', 'Romi', rol: RolEnLaBarra.encargada);
      await hasta(() => a.cliente.conectada && b.cliente.conectada && e.cliente.conectada);
      final c = await a.abrir(1);
      final pedido = await a.caja.anotarPasoDelCierre(
          PasoDelCierre.pedir(caja: c, efectivoContado: 0, hechoPor: 'Marta', ahora: DateTime.now()));
      await hasta(() => b.barra.pasosGuardados.any((p) => p.id == pedido.id));

      // Otra cajera manda un OK falso para la caja de Marta.
      await b.caja.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: pedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Sofía', ahora: DateTime.now()));
      await hasta(() => b.rechazo('No se pisa lo que hizo otro aparato') || b.rechazo('El OK lo da la encargada'));
      expect(PedidoDeCierre.de(c.id, a.barra.pasosGuardados).aceptado, isFalse, reason: 'la caja de Marta sigue esperando');

      // La encargada, con su propia caja: tampoco.
      final suya = await e.abrir(7);
      final suPedido = await e.caja.anotarPasoDelCierre(
          PasoDelCierre.pedir(caja: suya, efectivoContado: 0, hechoPor: 'Romi', ahora: DateTime.now()));
      await e.caja.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: suPedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Romi', ahora: DateTime.now()));
      await hasta(() => e.rechazo('El OK lo da la encargada'), que: 'su propia caja la aprueba el jefe');
      expect(PedidoDeCierre.de(suya.id, notebook.pasosGuardados).aceptado, isFalse);

      // La encargada, a la de Marta: sí.
      final ok = await e.caja.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: pedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Romi', ahora: DateTime.now()));
      await hasta(() => a.barra.pasosGuardados.any((p) => p.id == ok.id), que: 'el OK de verdad llega');
    });

    test('LA ENCARGADA ESTÁ ACÁ: el OK firmado por una encargada en la tablet de la cajera vale; con otro nombre, no', () async {
      personas.persona('op-romi', 'Romi', rol: RolEnLaBarra.encargada);
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => a.cliente.conectada);
      final c = await a.abrir(1);
      final pedido = await a.caja.anotarPasoDelCierre(
          PasoDelCierre.pedir(caja: c, efectivoContado: 0, hechoPor: 'Marta', ahora: DateTime.now()));
      await a.caja.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: pedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Marta', ahora: DateTime.now()));
      await hasta(() => a.rechazo('El OK lo da la encargada'), que: 'con su propio nombre no');
      final bien = await a.caja.anotarPasoDelCierre(
          PasoDelCierre.responder(pedido: pedido, tipo: TipoPasoDelCierre.ok, hechoPor: 'Romi', ahora: DateTime.now()));
      await hasta(() => notebook.pasosGuardados.any((p) => p.id == bien.id), que: 'firmado por la encargada');
    });

    test('cerrar sin el OK no se acepta; con el OK, sí', () async {
      final a = aparato('tablet-a', 'Marta');
      final e = aparato('tablet-e', 'Romi', rol: RolEnLaBarra.encargada);
      await hasta(() => a.cliente.conectada && e.cliente.conectada);
      final c = await a.abrir(1);
      await hasta(() => notebook.cajasGuardadas.any((x) => x.id == c.id));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.caja.cerrarCaja(c, efectivoContado: 0, diferencia: 0, quien: 'Marta');
      await hasta(() => a.rechazo('Falta el OK de la encargada'));
      expect(notebook.cajasGuardadas.single.abierta, isTrue);
    });

    test('una venta no se cambia, y una caja de otro aparato no recibe ventas', () async {
      final a = aparato('tablet-a', 'Marta');
      final b = aparato('tablet-b', 'Sofía');
      await hasta(() => a.cliente.conectada && b.cliente.conectada);
      final c = await a.abrir(1);
      final v = await a.vender(c);
      await hasta(() => b.barra.ventasGuardadas.length == 1);
      // La misma venta, con otro importe y más nueva.
      final cambiada = Map<String, Object?>.from(v.toMap())
        ..['efectivo'] = 1
        ..['updated_at'] = DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String();
      a.cliente.enviarFilas({'barra_ventas': [cambiada]});
      await hasta(() => a.rechazo('Una venta no se cambia'));
      // B vende en la caja de A.
      final ajena = Map<String, Object?>.from(v.toMap())
        ..['id'] = 'b0000000-0000-4000-8000-0000000000b1'
        ..['device_id'] = 'tablet-b';
      b.cliente.enviarFilas({'barra_ventas': [ajena]});
      await hasta(() => b.rechazo('La venta es de una caja de otro aparato'));
      expect(notebook.ventasGuardadas.single.efectivo, 6000);
    });

    test('la cajera pone el cambio una vez si abrió sin él; después no', () async {
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => a.cliente.conectada);
      var c = await a.abrir(1);
      await hasta(() => notebook.cajasGuardadas.any((x) => x.id == c.id));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c = await a.caja.ponerCambio(c, 20000, quien: 'Marta');
      await hasta(() => notebook.cajasGuardadas.single.cambioInicial == 20000, que: 'la primera vez sí');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.caja.ponerCambio(c, 50000, quien: 'Marta');
      await hasta(() => a.rechazo('El cambio lo maneja la encargada'));
      expect(notebook.cajasGuardadas.single.cambioInicial, 20000);
    });

    test('el repositor solo anota el stock; el reparto, solo el jefe', () async {
      final r = aparato('celu-nico', 'Nico', rol: RolEnLaBarra.repositor);
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => r.cliente.conectada && a.cliente.conectada);
      final ahora = DateTime.now().toUtc();
      final repuso = MovimientoDeStock.reposicion(
              eventoId: _fiesta, productoId: 'p', barra: 'Barra 1', cantidad: 12, hechoPor: 'Nico', ahora: ahora)
          .conEquipo('celu-nico');
      r.cliente.enviarFilas({'barra_stock_movimientos': [repuso.toMap()]});
      await hasta(() => a.barra.movimientosGuardados.any((m) => m.id == repuso.id), que: 'la reposición llega');

      // La cajera no mueve el stock; nadie más que el jefe reparte.
      final falta = MovimientoDeStock.faltante(
              eventoId: _fiesta, productoId: 'p', lugar: 'Barra 1', cantidad: 3, motivo: 'Rota', ahora: ahora)
          .conEquipo('tablet-a');
      a.cliente.enviarFilas({'barra_stock_movimientos': [falta.toMap()]});
      await hasta(() => a.rechazo('El stock lo mueve el repositor'));
      final reparto = StockEnLaBarra.para(
          eventoId: _fiesta, productoId: 'p', barra: 'Barra 1', arranque: 500, ahora: ahora);
      r.cliente.enviarFilas({
        'barra_stock_barras': [
          {...reparto.toMap(), 'device_id': 'celu-nico'},
        ],
      });
      await hasta(() => r.rechazo('El reparto lo hace el jefe'));
      // Y el repositor no vende.
      final venta = VentaBarra.nueva(
        cajaBarraId: 'c0000000-0000-4000-8000-0000000000c1',
        eventoId: _fiesta,
        numero: 1,
        renglones: const [RenglonVenta(productoId: 'p', nombre: 'Fernet', precio: 6000, cantidad: 1)],
        medio: MedioBarra.efectivo,
        efectivo: 6000,
        deviceId: 'celu-nico',
        ahora: ahora,
      );
      r.cliente.enviarFilas({'barra_ventas': [venta.toMap()]});
      await hasta(() => r.rechazo('El repositor solo anota el stock'));
      expect(notebook.ventasGuardadas, isEmpty);
      expect(notebook.repartosGuardados, isEmpty);
    });

    test('lo de otro aparato que falta se repone, pero no se pisa lo que ya está', () async {
      final a = aparato('tablet-a', 'Marta');
      await hasta(() => a.cliente.conectada);
      final c = await a.abrir(1);
      await hasta(() => notebook.cajasGuardadas.any((x) => x.id == c.id));
      final b = aparato('tablet-b', 'Sofía');
      await hasta(() => b.cliente.conectada && b.barra.cajasGuardadas.any((x) => x.id == c.id));
      // B manda la caja de A cambiada (como si la cerrara): no.
      final pisada = Map<String, Object?>.from(c.toMap())
        ..['cerrada_at'] = DateTime.now().toUtc().toIso8601String()
        ..['updated_at'] = DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String();
      b.cliente.enviarFilas({'barra_cajas': [pisada]});
      await hasta(() => b.rechazo('No se pisa lo que hizo otro aparato'));
      expect(notebook.cajasGuardadas.single.abierta, isTrue);
    });
  });
}
