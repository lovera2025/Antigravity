import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/nombre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/stock_por_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/datos/movimiento_de_stock.dart';
import 'package:arguello_events/features/barra/datos/stock_en_la_barra.dart';

/// El stock por barra (decidido por el usuario el 25-nov-2026;
/// `docs/SPEC_repositor_y_stock_por_barra_2026-11-25.md`): el jefe reparte el stock
/// general entre las barras, el depósito es el límite, el repositor repone, pasa de una
/// barra a otra explicando, anota faltantes con motivo, cuenta lo que hay y avisa "voy
/// en camino"; **sin stock no se vende**.
///
/// La noche del 4-dic no hay internet y cada barra tiene su router: un equipo puede
/// saber menos que otro. Por eso hay pruebas donde el repositor cuenta sin tener todas
/// las ventas (revisión independiente del 25-nov).
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _otraFiesta = 'e0000000-0000-4000-8000-000000000002';
const _cerveza = 'p0000000-0000-4000-8000-000000000001';
const _speed = 'p0000000-0000-4000-8000-000000000002';
const _agua = 'p0000000-0000-4000-8000-000000000003';
const _b1 = 'Barra 1';
const _b2 = 'Barra 2';
const _celu = 'celular-nico';
const _otro = 'celular-sole';

void main() {
  final ahora = DateTime.utc(2026, 12, 4, 23);

  PrecioBarra precio(String producto, int? general) => PrecioBarra.para(
        eventoId: _evento,
        productoId: producto,
        precio: 4000,
        stockInicial: general,
        ahora: ahora,
      );

  StockEnLaBarra reparto(String producto, String barra, int arranque, {int? aviso, bool activo = true}) =>
      StockEnLaBarra.para(
        eventoId: _evento,
        productoId: producto,
        barra: barra,
        arranque: arranque,
        aviso: aviso,
        activo: activo,
        ahora: ahora,
      );

  final repartoDeSiempre = [
    reparto(_cerveza, _b1, 60, aviso: 10),
    reparto(_cerveza, _b2, 60, aviso: 6),
    reparto(_speed, _b1, 24, aviso: 5),
    reparto(_speed, _b2, 24, aviso: 5),
  ];

  CajaBarra caja(int n, String? barra, {String eventoId = _evento}) =>
      CajaBarra.abrir(eventoId: eventoId, numeroCaja: n, sede: barra, ahora: ahora);

  // Las horas: el conteo va a las 23; "antes" y "despues" de contar, por el reloj.
  final antes = DateTime.utc(2026, 12, 4, 22);
  final despues = DateTime.utc(2026, 12, 4, 23, 30);
  final numeros = <String, int>{};
  /// Una venta en la tablet de la caja (`tablet-<n>`), como la guarda la app.
  VentaBarra vender(CajaBarra c, String producto, int cantidad, {DateTime? cuando, String? equipo}) {
    final r = [RenglonVenta(productoId: producto, nombre: 'x', precio: 4000, cantidad: cantidad)];
    final n = (numeros[c.id] ?? 0) + 1;
    numeros[c.id] = n;
    return VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: c.eventoId,
      numero: n,
      renglones: r,
      medio: MedioBarra.efectivo,
      efectivo: CuentaBarra(r).total,
      deviceId: equipo ?? 'tablet-${c.numeroCaja}',
      ahora: cuando ?? ahora,
    );
  }

  StockPorBarra stock({
    List<PrecioBarra>? precios,
    List<StockEnLaBarra>? repartos,
    List<MovimientoDeStock> movimientos = const [],
    List<VentaBarra> ventas = const [],
    List<CajaBarra> cajas = const [],
    List<AnulacionBarra> anulaciones = const [],
  }) =>
      StockPorBarra.de(
        eventoId: _evento,
        precios: precios ?? [precio(_cerveza, 240), precio(_speed, 96)],
        repartos: repartos ?? repartoDeSiempre,
        movimientos: movimientos,
        ventas: ventas,
        cajas: cajas,
        anulaciones: anulaciones,
      );

  MovimientoDeStock reponer(String producto, String barra, int n,
          {String equipo = _celu, String? respondeA, DateTime? cuando}) =>
      MovimientoDeStock.reposicion(
        eventoId: _evento,
        productoId: producto,
        barra: barra,
        cantidad: n,
        respondeA: respondeA,
        hechoPor: 'Nico',
        ahora: cuando ?? ahora,
      ).conEquipo(equipo);

  /// El repositor cuenta [contadas] en [lugar] con lo que sabe [visto].
  MovimientoDeStock contar(StockPorBarra visto, String lugar, String producto, int contadas,
      {String? motivo, String equipo = _celu, DateTime? cuando}) {
    final ajuste = visto.ajustePara(lugar, producto, contadas);
    return MovimientoDeStock.conteo(
      eventoId: _evento,
      productoId: producto,
      lugar: lugar,
      contadas: contadas,
      foto: visto.fotoDe(lugar, producto),
      ajuste: ajuste,
      motivo: motivo ?? (ajuste == 0 ? null : 'Se perdió'),
      ahora: cuando ?? ahora,
    ).conEquipo(equipo);
  }

  group('el reparto del jefe', () {
    test('cada barra arranca con lo suyo y el resto queda en el depósito', () {
      final s = stock();
      expect(s.hayReparto, isTrue);
      expect(s.nombresDeBarras, [_b1, _b2]);
      expect(s.en(_b1, _cerveza)!.queda, 60);
      expect(s.en(_b2, _cerveza)!.queda, 60);
      expect(s.en(kDeposito, _cerveza)!.queda, 120);
      expect(s.en(kDeposito, _speed)!.queda, 48);
    });

    test('sin reparto no hay stock por barra: sigue la cuenta de la fiesta de siempre', () {
      final s = stock(repartos: []);
      expect(s.hayReparto, isFalse);
      expect(s.sePuedeVender(_b1, _cerveza, 1000), isTrue);
      expect(s.en(kDeposito, _cerveza), isNull);
    });

    test('un producto que el jefe no repartió en una barra no se frena ahí', () {
      final s = stock(repartos: [reparto(_cerveza, _b1, 10)]);
      expect(s.controla(_b2, _cerveza), isFalse);
      expect(s.sePuedeVender(_b2, _cerveza, 50), isTrue);
      expect(s.cuantasSePuedenVender(_b2, _cerveza), isNull);
      expect(s.controla(_b1, _agua), isFalse);
    });

    test('sin stock general cargado, el reparto no frena nada y se avisa al jefe', () {
      final s = stock(precios: [precio(_cerveza, null)], repartos: [reparto(_cerveza, _b1, 10)]);
      expect(s.controla(_b1, _cerveza), isFalse);
      expect(s.sePuedeVender(_b1, _cerveza, 99), isTrue);
      expect(s.faltaElStockGeneral, {_cerveza});
      expect(s.errorDelReparto(_cerveza, null, {_b1: 10}), 'Primero cargá el stock general.');
    });

    test('una fila sacada (activo en false) no cuenta', () {
      final s = stock(repartos: [reparto(_cerveza, _b1, 60), reparto(_cerveza, _b2, 60, activo: false)]);
      expect(s.controla(_b2, _cerveza), isFalse);
      expect(s.en(kDeposito, _cerveza)!.queda, 180);
    });

    test('no se reparte más de lo que hay', () {
      final s = stock();
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 120, _b2: 120}), isNull);
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 121, _b2: 120}), 'Hay 240: no se puede repartir 241.');
      expect(s.errorDelReparto(_cerveza, 240, {_b1: -1}), 'No puede ser negativo.');
    });

    test('las barras que no se tocan quedan con lo suyo al contar el límite', () {
      // La Barra 2 tiene 60: darle 240 a la Barra 1 dejaría el depósito en −60.
      expect(stock().errorDelReparto(_cerveza, 240, {_b1: 240}), 'Hay 240: no se puede repartir 300.');
      expect(stock().errorDelReparto(_cerveza, 240, {_b1: 180}), isNull);
    });

    test('al cambiar el reparto cuenta lo que ya entró y salió del depósito', () {
      final s = stock(movimientos: [
        MovimientoDeStock.entrada(
            eventoId: _evento, productoId: _cerveza, cantidad: 24, deDonde: 'Trajo el jefe', ahora: ahora),
        reponer(_cerveza, _b1, 30),
      ]);
      // 240 + 24 entraron − 30 repuestos = 234 para repartir.
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 134, _b2: 100}), isNull);
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 135, _b2: 100}), isNotNull);
    });

    test('en plena noche, una barra que ya vendió no puede arrancar con menos de lo que usó', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 50)]);
      expect(s.errorDelReparto(_cerveza, 240, {_b2: 49}), contains('no puede arrancar con menos de 50'));
      expect(s.errorDelReparto(_cerveza, 240, {_b2: 50}), isNull);
      expect(s.errorDelReparto(_cerveza, 240, {_b2: 60}), isNull, reason: 'dejarla como está siempre se puede');
    });

    test('dejarla como está se puede aunque haya vendido de más', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 62)]);
      expect(s.en(_b2, _cerveza)!.queda, -2);
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 60}), isNull);
    });

    test('no se saca del reparto una barra que ya vendió o movió ese producto', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 1)], movimientos: [reponer(_speed, _b1, 2)]);
      expect(s.errorAlSacarDelReparto(_cerveza, _b2), contains('no se puede sacar'));
      expect(s.errorAlSacarDelReparto(_speed, _b1), contains('no se puede sacar'));
      expect(s.errorAlSacarDelReparto(_speed, _b2), isNull);
    });
  });

  group('los nombres de las barras', () {
    test('mayúsculas, acentos y espacios de más son la misma barra', () {
      expect(claveDeBarra('  BARRA   1 '), claveDeBarra('Barra 1'));
      expect(esElDeposito('Depósito'), isTrue);
      expect(esElDeposito(' DEPOSITO '), isTrue);
      expect(esElDeposito('Barra 1'), isFalse);
    });

    test('una caja escrita distinto descuenta de su barra igual', () {
      final c = caja(1, 'barra  1');
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 4)]);
      expect(s.en(_b1, _cerveza)!.vendido, 4);
      expect(s.en('BARRA 1', _cerveza)!.queda, 56);
      expect(s.vendidoSinBarra, 0);
    });

    test('el reparto escrito distinto es la misma fila', () {
      expect(reparto(_cerveza, 'barra 1', 1).id, reparto(_cerveza, 'Barra  1', 2).id);
      expect(reparto(_cerveza, ' Barra 1 ', 60).barra, _b1);
    });

    test('un faltante en "Depósito" con acento resta del depósito', () {
      final f = MovimientoDeStock.faltante(
          eventoId: _evento, productoId: _cerveza, lugar: 'Depósito', cantidad: 1, motivo: 'Rota', ahora: ahora);
      expect(f.desde, kDeposito);
      expect(stock(movimientos: [f]).en(kDeposito, _cerveza)!.queda, 119);
    });

    test('una barra no puede llamarse como el depósito', () {
      expect(() => reponer(_cerveza, kDeposito, 3), throwsArgumentError);
      expect(() => reponer(_cerveza, 'Depósito', 3), throwsArgumentError);
      expect(() => reparto(_cerveza, 'Depósito', 3), throwsArgumentError);
    });
  });

  group('lo vendido descuenta de la barra de su caja', () {
    test('cada caja descuenta de su barra; las anuladas no cuentan', () {
      final c1 = caja(1, _b1), c4 = caja(4, _b2);
      final anulada = vender(c1, _cerveza, 5);
      final s = stock(
        cajas: [c1, c4],
        ventas: [vender(c1, _cerveza, 12), anulada, vender(c4, _cerveza, 3), vender(c4, _speed, 24)],
        anulaciones: [AnulacionBarra.de(anulada, motivo: 'Se equivocó', ahora: ahora)],
      );
      expect(s.en(_b1, _cerveza)!.queda, 48);
      expect(s.en(_b1, _cerveza)!.vendido, 12);
      expect(s.en(_b2, _cerveza)!.queda, 57);
      expect(s.en(_b2, _speed)!.queda, 0);
      expect(s.en(kDeposito, _cerveza)!.queda, 120, reason: 'vender no toca el depósito');
    });

    test('una caja sin barra no descuenta de ninguna y queda contada aparte', () {
      final c = caja(3, null);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 7)]);
      expect(s.en(_b1, _cerveza)!.queda, 60);
      expect(s.en(_b2, _cerveza)!.queda, 60);
      expect(s.vendidoSinBarra, 7);
    });

    test('una venta cuya caja todavía no llegó se cuenta aparte', () {
      final c = caja(1, _b1);
      final s = stock(cajas: const [], ventas: [vender(c, _cerveza, 2)]);
      expect(s.ventasSinCaja, 1);
      expect(s.en(_b1, _cerveza)!.queda, 60);
    });

    test('lo de otra fiesta no cuenta', () {
      final c = caja(1, _b1, eventoId: _otraFiesta);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 9)]);
      expect(s.en(_b1, _cerveza)!.queda, 60);
    });
  });

  group('sin stock no se vende', () {
    test('se vende hasta lo que queda, ni una más', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _speed, 22)]);
      expect(s.cuantasSePuedenVender(_b2, _speed), 2);
      expect(s.sePuedeVender(_b2, _speed, 2), isTrue);
      expect(s.sePuedeVender(_b2, _speed, 3), isFalse);
    });

    test('vendido de más (dos cajas sin la central) da sin stock, no un número negativo para vender', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _speed, 20), vender(c, _speed, 6)]);
      expect(s.en(_b2, _speed)!.queda, -2);
      expect(s.en(_b2, _speed)!.sinStock, isTrue);
      expect(s.cuantasSePuedenVender(_b2, _speed), 0);
      expect(s.sePuedeVender(_b2, _speed, 1), isFalse);
    });

    test('al reponer vuelve a venderse con la cantidad repuesta', () {
      final c = caja(4, _b2);
      final ventas = [vender(c, _speed, 24)];
      expect(stock(cajas: [c], ventas: ventas).sePuedeVender(_b2, _speed, 1), isFalse);
      final s = stock(cajas: [c], ventas: ventas, movimientos: [reponer(_speed, _b2, 12)]);
      expect(s.cuantasSePuedenVender(_b2, _speed), 12);
    });
  });

  group('reponer: el depósito es el límite', () {
    test('lo repuesto pasa del depósito a la barra', () {
      final s = stock(movimientos: [reponer(_cerveza, _b1, 12)]);
      expect(s.en(_b1, _cerveza)!.queda, 72);
      expect(s.en(kDeposito, _cerveza)!.queda, 108);
    });

    test('no se repone más de lo que queda en el depósito', () {
      final s = stock(movimientos: [reponer(_speed, _b1, 40)]);
      expect(s.cuantoSePuedeReponer(_speed), 8);
      expect(s.errorAlReponer(_speed, _b2, 8), isNull);
      expect(s.errorAlReponer(_speed, _b2, 9), 'En el depósito quedan 8: no se puede reponer más.');
      expect(s.errorAlReponer(_speed, _b2, 0), 'Poné cuánto reponés.');
    });

    test('no se repone a una barra donde el producto no se repartió', () {
      final s = stock(repartos: [reparto(_cerveza, _b1, 60)]);
      expect(s.errorAlReponer(_cerveza, _b2, 1), contains('no lo repartió'));
    });

    test('si entra mercadería, el depósito crece y se puede reponer más', () {
      final entrada = MovimientoDeStock.entrada(
          eventoId: _evento, productoId: _speed, cantidad: 24, deDonde: 'La trajo el jefe del súper', ahora: ahora);
      final s = stock(movimientos: [reponer(_speed, _b1, 48), entrada]);
      expect(s.en(kDeposito, _speed)!.queda, 24);
      expect(s.errorAlReponer(_speed, _b2, 24), isNull);
    });

    test('una entrada sin decir de dónde vino no se arma', () {
      expect(
          () => MovimientoDeStock.entrada(
              eventoId: _evento, productoId: _speed, cantidad: 24, deDonde: '  ', ahora: ahora),
          throwsArgumentError);
      expect(StockPorBarra.errorAlEntrar(24, ''), 'Decí de dónde vino.');
      expect(StockPorBarra.errorAlEntrar(0, 'súper'), 'Poné cuánto entró.');
      expect(StockPorBarra.errorAlEntrar(24, 'súper'), isNull);
    });
  });

  group('pasar de una barra a otra, explicando', () {
    MovimientoDeStock pasar(int n, {String desde = _b2, String hacia = _b1, String equipo = _celu}) =>
        MovimientoDeStock.traspaso(
          eventoId: _evento,
          productoId: _cerveza,
          desdeBarra: desde,
          haciaBarra: hacia,
          cantidad: n,
          porque: 'En la Barra 2 casi no piden',
          ahora: ahora,
        ).conEquipo(equipo);

    test('sale de una barra y entra en la otra; el depósito no cambia', () {
      final s = stock(movimientos: [pasar(6)]);
      expect(s.en(_b1, _cerveza)!.queda, 66);
      expect(s.en(_b2, _cerveza)!.queda, 54);
      expect(s.en(kDeposito, _cerveza)!.queda, 120);
    });

    test('no se pasa más de lo que tiene la barra de origen, y hace falta el porqué', () {
      final c = caja(4, _b2);
      final s = stock(cajas: [c], ventas: [vender(c, _cerveza, 55)]);
      expect(s.cuantoSePuedePasar(_b2, _cerveza), 5);
      expect(s.errorAlPasar(_cerveza, _b2, _b1, 5, 'casi no piden'), isNull);
      expect(s.errorAlPasar(_cerveza, _b2, _b1, 6, 'casi no piden'), 'La Barra 2 tiene 5: no se puede pasar más.');
      expect(s.errorAlPasar(_cerveza, _b2, _b1, 5, ' '), 'Para pasar de una barra a otra, decí por qué.');
      expect(s.errorAlPasar(_cerveza, _b2, 'barra 2', 1, 'x'), 'Elegí otra barra.');
    });

    test('un traspaso sin porqué o a la misma barra no se arma', () {
      expect(
          () => MovimientoDeStock.traspaso(
              eventoId: _evento,
              productoId: _cerveza,
              desdeBarra: _b2,
              haciaBarra: _b1,
              cantidad: 3,
              porque: '',
              ahora: ahora),
          throwsArgumentError);
      expect(() => pasar(3, desde: _b1, hacia: ' barra 1'), throwsArgumentError);
    });
  });

  group('faltantes', () {
    test('un faltante resta de su lugar, con motivo', () {
      final s = stock(movimientos: [
        MovimientoDeStock.faltante(
            eventoId: _evento, productoId: _cerveza, lugar: _b1, cantidad: 2, motivo: 'Congelada', ahora: ahora),
        MovimientoDeStock.faltante(
            eventoId: _evento, productoId: _cerveza, lugar: kDeposito, cantidad: 1, motivo: 'Rota', ahora: ahora),
      ]);
      expect(s.en(_b1, _cerveza)!.queda, 58);
      expect(s.en(_b1, _cerveza)!.falto, 2);
      expect(s.en(kDeposito, _cerveza)!.queda, 119);
    });

    test('no pueden faltar más de las que hay, y el motivo es obligatorio', () {
      final s = stock();
      expect(s.errorAlDescontar(_speed, _b1, 24, 'Rota'), isNull);
      expect(s.errorAlDescontar(_speed, _b1, 25, 'Rota'), 'Hay 24: no pueden faltar más.');
      expect(s.errorAlDescontar(_speed, _b1, 1, null), 'Elegí el motivo.');
      expect(
          () => MovimientoDeStock.faltante(
              eventoId: _evento, productoId: _speed, lugar: _b1, cantidad: 1, motivo: '', ahora: ahora),
          throwsArgumentError);
    });
  });

  group('contar lo que hay', () {
    test('"se sabía que eran 70 y hay 68": queda 68 y pide el motivo de las 2', () {
      final s = stock(movimientos: [reponer(_cerveza, _b1, 10)]);
      expect(s.en(_b1, _cerveza)!.queda, 70);
      expect(s.ajustePara(_b1, _cerveza, 68), -2);
      expect(StockPorBarra.errorDelAjuste(-2, null), 'Faltan 2: elegí qué pasó con esas.');
      expect(StockPorBarra.errorDelAjuste(-1, ''), 'Faltan 1: elegí qué pasó con esa.');
      expect(StockPorBarra.errorDelAjuste(3, null), 'Sobran 3: decí de dónde salieron.');
      expect(StockPorBarra.errorDelAjuste(0, null), isNull);
      final conteo = contar(s, _b1, _cerveza, 68, motivo: 'Congelada');
      final despues = stock(movimientos: [reponer(_cerveza, _b1, 10), conteo]);
      expect(despues.en(_b1, _cerveza)!.queda, 68);
      expect(despues.en(_b1, _cerveza)!.porConteos, -2);
    });

    test('un conteo sin motivo cuando no da, o sin lo que se sabía, no se arma', () {
      final s = stock();
      expect(
          () => MovimientoDeStock.conteo(
              eventoId: _evento,
              productoId: _cerveza,
              lugar: _b1,
              contadas: 58,
              foto: s.fotoDe(_b1, _cerveza),
              ajuste: -2,
              ahora: ahora),
          throwsArgumentError);
      expect(
          () => MovimientoDeStock.reposicion(
              eventoId: _evento, productoId: _cerveza, barra: _b1, cantidad: 3, contadas: 63, ahora: ahora),
          throwsArgumentError);
    });

    test('lo que se vende después del conteo se descuenta de lo contado', () {
      final c = caja(1, _b1);
      final antes = [vender(c, _cerveza, 10)];
      final conteo = contar(stock(cajas: [c], ventas: antes), _b1, _cerveza, 49, motivo: 'Rota');
      final s = stock(cajas: [c], ventas: [...antes, vender(c, _cerveza, 5, cuando: despues)], movimientos: [conteo]);
      expect(s.en(_b1, _cerveza)!.queda, 44);
    });

    test('LA REVISIÓN: el repositor cuenta sin tener 20 ventas que estaban en el otro router', () {
      // La Caja 2 vendió 20 antes de que él contara; su celular todavía no las tiene.
      final c2 = caja(2, _b1);
      final ventas = [for (var i = 0; i < 20; i++) vender(c2, _cerveza, 1, cuando: antes)];
      // Él ve 60, cuenta 40 (lo que de verdad hay): la diferencia que ve es −20.
      final visto = stock(cajas: [c2]);
      final conteo = contar(visto, _b1, _cerveza, 40, motivo: 'Se perdió');
      expect(conteo.ajuste, -20);
      // Cuando llegan las ventas, no se restan dos veces: quedan 40, no 20.
      final s = stock(cajas: [c2], ventas: ventas, movimientos: [conteo]);
      expect(s.en(_b1, _cerveza)!.queda, 40);
      expect(s.sePuedeVender(_b1, _cerveza, 40), isTrue);
    });

    test('si conocía una venta de esa caja, todas las anteriores de esa caja fueron antes', () {
      // Aunque la tablet tenga la hora atrasada: el orden de los números no miente.
      final c = caja(2, _b1);
      final masTarde = DateTime.utc(2026, 12, 5, 3); // la hora de la tablet, corrida
      final previas = [for (var i = 0; i < 4; i++) vender(c, _cerveza, 1, cuando: masTarde)];
      final conocida = vender(c, _cerveza, 1, cuando: masTarde);
      final conteo = contar(stock(cajas: [c], ventas: [conocida]), _b1, _cerveza, 55, motivo: 'Rota');
      expect(conteo.foto!.ventasHasta[c.id], 5);
      final s = stock(cajas: [c], ventas: [...previas, conocida], movimientos: [conteo]);
      expect(s.en(_b1, _cerveza)!.queda, 55, reason: 'las 4 de antes ya estaban fuera de la barra al contar');
    });

    test('lo de un equipo que conocía, hasta donde lo conocía, fue antes', () {
      final r1 = reponer(_cerveza, _b1, 6, equipo: _otro, cuando: DateTime.utc(2026, 12, 5, 4));
      final r2 = reponer(_cerveza, _b1, 6, equipo: _otro, cuando: DateTime.utc(2026, 12, 5, 5));
      // Nico conocía r2 (y no r1): r1 es del mismo equipo y anterior, así que fue antes.
      final conteo = contar(stock(movimientos: [r2]), _b1, _cerveza, 72, motivo: 'Estaban sin anotar');
      expect(stock(movimientos: [conteo, r1, r2]).en(_b1, _cerveza)!.queda, 72);
    });

    test('LA REVISIÓN: una reposición de otro equipo que no conocía no se suma dos veces', () {
      final deSole = reponer(_cerveza, _b1, 12, equipo: _otro, cuando: antes);
      // Nico no la conoce: ve 60, cuenta 72 (las de Sole ya están en la barra).
      final conteo = contar(stock(), _b1, _cerveza, 72, motivo: 'Estaban sin anotar');
      final s = stock(movimientos: [conteo, deSole]);
      expect(s.en(_b1, _cerveza)!.queda, 72);
      expect(s.en(kDeposito, _cerveza)!.queda, 108);
    });

    test('LA REVISIÓN: dos conteos a la vez que no se conocen no restan dos veces', () {
      final s0 = stock();
      final a = contar(s0, _b1, _cerveza, 58, motivo: 'Rota', equipo: _celu);
      final b = contar(s0, _b1, _cerveza, 58, motivo: 'Rota', equipo: _otro);
      expect(stock(movimientos: [a, b]).en(_b1, _cerveza)!.queda, 58);
      // Si contaron distinto, vale el que da menos: mejor frenar que vender lo que no hay.
      final c = contar(s0, _b1, _cerveza, 57, motivo: 'Rota', equipo: _otro);
      expect(stock(movimientos: [a, c]).en(_b1, _cerveza)!.queda, 57);
    });

    test('un conteo que conoce al anterior lo reemplaza', () {
      final s0 = stock();
      final primero = contar(s0, _b1, _cerveza, 50, motivo: 'Rota');
      final s1 = stock(movimientos: [primero]);
      final segundo = contar(s1, _b1, _cerveza, 55, motivo: 'Estaban sin anotar');
      final s = stock(movimientos: [segundo, primero]);
      expect(s.en(_b1, _cerveza)!.queda, 55);
    });

    test('una venta anulada después del conteo vuelve a la barra', () {
      final c = caja(1, _b1);
      final v = vender(c, _cerveza, 3);
      final conteo = contar(stock(cajas: [c], ventas: [v]), _b1, _cerveza, 57);
      final s = stock(
        cajas: [c],
        ventas: [v],
        movimientos: [conteo],
        anulaciones: [AnulacionBarra.de(v, motivo: 'No la sirvió', ahora: ahora)],
      );
      expect(s.en(_b1, _cerveza)!.queda, 60);
    });

    test('una venta conocida por número salteado no se resta dos veces', () {
      final c = caja(1, _b1);
      final v1 = vender(c, _cerveza, 1), v2 = vender(c, _cerveza, 2), v3 = vender(c, _cerveza, 4);
      // El celular tiene la 1 y la 3, pero no la 2.
      final visto = stock(cajas: [c], ventas: [v1, v3]);
      final conteo = contar(visto, _b1, _cerveza, 53, motivo: 'Rota'); // ve 55, cuenta 53
      expect(conteo.foto!.ventasHasta[c.id], 3);
      final s = stock(cajas: [c], ventas: [v1, v2, v3], movimientos: [conteo]);
      // Lo contado (53) ya tenía la 2 vendida: queda 53, no 51.
      expect(s.en(_b1, _cerveza)!.queda, 53);
    });

    test('al reponer deja dicho cuántas quedan, con lo que sabía', () {
      final s = stock();
      // Tenía 60, repone 12: la cuenta da 72; contó 71.
      final ajuste = s.ajustePara(_b1, _cerveza, 71, ademas: 12);
      expect(ajuste, -1);
      final r = MovimientoDeStock.reposicion(
        eventoId: _evento,
        productoId: _cerveza,
        barra: _b1,
        cantidad: 12,
        contadas: 71,
        foto: s.fotoDe(_b1, _cerveza),
        ajuste: ajuste,
        motivo: 'Rota',
        ahora: ahora,
      );
      expect(r.esConteo, isTrue);
      final despues = stock(movimientos: [r]);
      expect(despues.en(_b1, _cerveza)!.queda, 71);
      expect(despues.en(kDeposito, _cerveza)!.queda, 108, reason: 'el depósito da lo que repuso, no lo contado');
    });

    test('contar el depósito', () {
      final conteo = contar(stock(), kDeposito, _cerveza, 117, motivo: 'Rota');
      final s = stock(movimientos: [conteo, reponer(_cerveza, _b1, 7, equipo: _otro)]);
      expect(s.en(kDeposito, _cerveza)!.queda, 110);
      expect(s.cuantoSePuedeReponer(_cerveza), 110);
    });

    test('el orden en que llegan las filas no cambia nada', () {
      final c = caja(1, _b1);
      final v = vender(c, _cerveza, 10);
      final r = reponer(_cerveza, _b1, 12);
      final s1 = stock(cajas: [c], ventas: [v], movimientos: [r]);
      final conteo = contar(s1, _b1, _cerveza, 59, motivo: 'Rota');
      final f = MovimientoDeStock.faltante(
          eventoId: _evento, productoId: _cerveza, lugar: _b1, cantidad: 2, motivo: 'Congelada', ahora: ahora);
      final movs = [r, conteo, f];
      final a = stock(movimientos: movs, cajas: [c], ventas: [v]);
      final b = stock(movimientos: movs.reversed.toList(), cajas: [c], ventas: [v]);
      expect(a.en(_b1, _cerveza)!.queda, 57);
      expect(b.en(_b1, _cerveza)!.queda, 57);
    });

    test('una foto que no se puede leer no rompe: cuenta como sin conteo', () {
      final raro = MovimientoDeStock.fromMap({
        ...contar(stock(), _b1, _cerveza, 50, motivo: 'Rota').toMap(),
        'conocido': '{no es json',
      });
      expect(raro.esConteo, isFalse);
      expect(stock(movimientos: [raro]).en(_b1, _cerveza)!.queda, 60);
    });
  });

  group('"voy en camino"', () {
    MovimientoDeStock avisar(String barra, String producto, List<MovimientoDeStock> conocidos,
            {String equipo = _celu}) =>
        MovimientoDeStock.enCamino(
          eventoId: _evento,
          productoId: producto,
          barra: barra,
          avisosPrevios: StockPorBarra.llegadasDesde(conocidos, _evento, barra, producto, equipo),
          hechoPor: 'Nico',
          ahora: ahora,
        ).conEquipo(equipo);

    test('se avisa a la barra elegida y sigue hasta que repone ahí', () {
      final aviso = avisar(_b2, _speed, const []);
      final s = stock(movimientos: [aviso]);
      expect(s.enCaminoDe(_b2, _speed)?.quien, 'Nico');
      expect(s.enCaminoDe(_b1, _speed), isNull, reason: 'el aviso es solo para la barra elegida');
      expect(s.enCamino(_b2), hasLength(1));
      expect(s.enCamino(_b1), isEmpty);
      expect(stock(movimientos: [aviso, reponer(_speed, _b2, 12)]).enCaminoDe(_b2, _speed), isNull);
    });

    test('pasar de la otra barra también lo cumple', () {
      final aviso = avisar(_b1, _speed, const []);
      final pase = MovimientoDeStock.traspaso(
              eventoId: _evento,
              productoId: _speed,
              desdeBarra: _b2,
              haciaBarra: _b1,
              cantidad: 4,
              porque: 'No hay en el depósito',
              ahora: ahora)
          .conEquipo(_celu);
      expect(stock(movimientos: [aviso, pase]).enCaminoDe(_b1, _speed), isNull);
    });

    test('reponer a otra barra u otro producto no lo resuelve', () {
      final aviso = avisar(_b2, _speed, const []);
      final s = stock(movimientos: [aviso, reponer(_speed, _b1, 12), reponer(_cerveza, _b2, 12)]);
      expect(s.enCaminoDe(_b2, _speed), isNotNull);
    });

    test('LA REVISIÓN: una reposición de otro equipo que llegó tarde no lo saca', () {
      final deSole = reponer(_speed, _b2, 6, equipo: _otro);
      final aviso = avisar(_b2, _speed, const []); // Nico no conoce lo de Sole
      expect(stock(movimientos: [aviso, deSole]).enCaminoDe(_b2, _speed), isNotNull);
    });

    test('una reposición del mismo equipo anterior al aviso no lo resuelve', () {
      final antes = reponer(_speed, _b2, 6);
      final aviso = avisar(_b2, _speed, [antes]);
      expect(aviso.avisosPrevios, 1);
      expect(stock(movimientos: [aviso, antes]).enCaminoDe(_b2, _speed), isNotNull);
      expect(stock(movimientos: [antes, aviso, reponer(_speed, _b2, 6)]).enCaminoDe(_b2, _speed), isNull);
    });

    test('lo cumple una reposición de otro equipo que lo contesta', () {
      final aviso = avisar(_b2, _speed, const []);
      final deSole = reponer(_speed, _b2, 6, equipo: _otro, respondeA: aviso.id);
      expect(stock(movimientos: [aviso, deSole]).enCaminoDe(_b2, _speed), isNull);
    });

    test('"ya no voy" lo saca', () {
      final aviso = avisar(_b2, _speed, const []);
      final no = MovimientoDeStock.yaNoVoy(aviso: aviso, nota: 'No hay en el depósito', ahora: ahora);
      expect(stock(movimientos: [aviso, no]).enCaminoDe(_b2, _speed), isNull);
      expect(() => MovimientoDeStock.yaNoVoy(aviso: no, ahora: ahora), throwsArgumentError);
    });

    test('si el jefe saca el reparto de esa barra, el aviso no se muestra', () {
      final aviso = avisar(_b2, _speed, const []);
      final s = stock(movimientos: [aviso], repartos: [reparto(_speed, _b1, 24)]);
      expect(s.enCaminoDe(_b2, _speed), isNull);
    });

    test('un "voy en camino" no toca el stock', () {
      expect(stock(movimientos: [avisar(_b2, _speed, const [])]).en(_b2, _speed)!.queda, 24);
    });
  });

  group('el aviso de "está quedando poco", por barra', () {
    test('cada barra con el suyo; sin stock arriba', () {
      final c1 = caja(1, _b1), c4 = caja(4, _b2);
      final s = stock(cajas: [c1, c4], ventas: [
        vender(c1, _cerveza, 50), // queda 10: llega al aviso de la Barra 1 (10)
        vender(c4, _cerveza, 53), // queda 7: no llega al aviso de la Barra 2 (6)
        vender(c4, _speed, 24), // sin stock
      ]);
      expect([for (final x in s.enAviso()) '${x.lugar} ${x.productoId == _speed ? 'Speed' : 'Cerveza'} ${x.queda}'],
          ['Barra 2 Speed 0', 'Barra 1 Cerveza 10']);
    });

    test('sin aviso puesto, avisa solo sin stock', () {
      final repartos = [reparto(_agua, _b1, 3)];
      final precios = [precio(_agua, 3)];
      expect(stock(repartos: repartos, precios: precios).enAviso(), isEmpty);
      final c = caja(1, _b1);
      expect(stock(repartos: repartos, precios: precios, cajas: [c], ventas: [vender(c, _agua, 3)]).enAviso(),
          hasLength(1));
    });
  });

  // Lo que pidió la segunda revisión independiente (25-nov): el código ya estaba, faltaban
  // las pruebas. Cada una está armada para que la vigile una sola regla.
  group('LA SEGUNDA REVISIÓN', () {
    test('dos conteos que no se conocen, a distinta hora: queda el menor, sea el primero o el segundo', () {
      final s0 = stock();
      final temprano = DateTime.utc(2026, 12, 4, 22, 10), tarde = DateTime.utc(2026, 12, 5, 1, 40);
      final c = caja(1, _b1);
      final despuesDeLosDos = vender(c, _cerveza, 3, cuando: DateTime.utc(2026, 12, 5, 2));
      // El menor es el de más temprano…
      final a = contar(s0, _b1, _cerveza, 50, equipo: _celu, cuando: temprano);
      final b = contar(s0, _b1, _cerveza, 54, equipo: _otro, cuando: tarde);
      // …o el de más tarde.
      final x = contar(s0, _b1, _cerveza, 54, equipo: _celu, cuando: temprano);
      final y = contar(s0, _b1, _cerveza, 50, equipo: _otro, cuando: tarde);
      for (final movs in [
        [a, b],
        [b, a],
        [x, y],
        [y, x],
      ]) {
        expect(stock(movimientos: movs).en(_b1, _cerveza)!.queda, 50);
        expect(stock(movimientos: movs, cajas: [c], ventas: [despuesDeLosDos]).en(_b1, _cerveza)!.queda, 47,
            reason: 'lo vendido después de los dos se descuenta una vez');
      }
    });

    test('tres conteos con un reloj corrido que se "conocen" en ronda: nunca queda sin ninguno', () {
      // El celular C tuvo la hora adelantada y la corrigió: lo que anotó antes dice las 2,
      // y su conteo, las 00:30. Así A "conoce" a C, B a A y C a B: cada uno parece anterior
      // a otro. Sin el respaldo, no quedaría ningún conteo y volvería la cuenta (60).
      MovimientoDeStock conteo(int contadas, String equipo, DateTime cuando, Map<String, String> conocia) =>
          MovimientoDeStock.conteo(
            eventoId: _evento,
            productoId: _cerveza,
            lugar: _b1,
            contadas: contadas,
            foto: FotoDeStock(equiposHasta: conocia),
            ajuste: contadas - 60,
            motivo: 'Rota',
            ahora: cuando,
          ).conEquipo(equipo);
      final a = conteo(52, 'celu-a', DateTime.utc(2026, 12, 4, 23), {'celu-c': DateTime.utc(2026, 12, 5, 2).toIso8601String()});
      final b = conteo(55, 'celu-b', DateTime.utc(2026, 12, 4, 23, 30), {'celu-a': a.createdAt});
      final c = conteo(50, 'celu-c', DateTime.utc(2026, 12, 5, 0, 30), {'celu-b': b.createdAt});
      for (final movs in [
        [a, b, c],
        [c, b, a],
        [b, c, a],
      ]) {
        final s = stock(movimientos: movs);
        expect(s.en(_b1, _cerveza)!.queda, 50, reason: 'vale el que da menos');
        expect(s.en(_b1, _cerveza)!.porConteos, -10);
      }
    });

    test('una venta que llegó antes que su caja: manda el número, aunque la tablet haya corrido la hora', () {
      final c = caja(2, _b1);
      // Las 4 primeras con la hora adelantada; después la tablet se corrigió.
      final adelantada = DateTime.utc(2026, 12, 5, 4);
      final previas = [for (var i = 0; i < 4; i++) vender(c, _cerveza, 1, cuando: adelantada)];
      final quinta = vender(c, _cerveza, 1, cuando: DateTime.utc(2026, 12, 4, 22, 30));
      // El celular tiene la quinta, pero no la caja: todavía no sabe de qué barra es.
      final visto = stock(cajas: const [], ventas: [quinta]);
      expect(visto.ventasSinCaja, 1);
      expect(visto.en(_b1, _cerveza)!.queda, 60);
      final conteo = contar(visto, _b1, _cerveza, 55);
      expect(conteo.foto!.ventasHasta[c.id], 5);
      final sexta = vender(c, _cerveza, 1, cuando: DateTime.utc(2026, 12, 4, 23, 40));
      final s = stock(cajas: [c], ventas: [...previas, quinta, sexta], movimientos: [conteo]);
      expect(s.en(_b1, _cerveza)!.queda, 54,
          reason: 'las 5 primeras ya estaban fuera de la barra al contar; la sexta se vendió después');
    });

    test('una anulación de otro equipo que conocía al contar ya estaba hecha, aunque su hora diga después', () {
      final c = caja(1, _b1);
      final v = vender(c, _cerveza, 3, cuando: antes);
      // La PC del jefe anuló con la hora adelantada.
      final anulacion =
          AnulacionBarra.de(v, motivo: 'Se equivocó', deviceId: 'pc-jefe', ahora: DateTime.utc(2026, 12, 5, 1));
      final visto = stock(cajas: [c], ventas: [v], anulaciones: [anulacion]);
      expect(visto.en(_b1, _cerveza)!.queda, 60);
      final conteo = contar(visto, _b1, _cerveza, 60);
      expect(conteo.foto!.conoce('pc-jefe', anulacion.createdAt), isTrue);
      final s = stock(cajas: [c], ventas: [v], anulaciones: [anulacion], movimientos: [conteo]);
      expect(s.en(_b1, _cerveza)!.queda, 60, reason: 'la botella ya había vuelto al contar: no se suma dos veces');
    });

    test('con un producto ya contado, el jefe no cambia su stock general ni su reparto', () {
      final s = stock(movimientos: [contar(stock(), _b1, _cerveza, 58, motivo: 'Rota')]);
      const frena = 'Este producto ya se contó: lo que cambie, que lo anote el repositor '
          '(entró mercadería, reponer o faltante).';
      expect(s.errorDelReparto(_cerveza, 250, {}), frena);
      expect(s.errorDelReparto(_cerveza, 240, {_b2: 70}), frena);
      expect(s.errorDelReparto(_cerveza, 240, {_b1: 60, 'barra 2': 60}), isNull,
          reason: 'guardar sin cambiar nada siempre se puede');
      expect(s.errorDelReparto(_speed, 96, {_b1: 30}), isNull, reason: 'otro producto, sin contar, sí');
      // Contar el depósito también frena.
      final d = stock(movimientos: [contar(stock(), kDeposito, _speed, 48)]);
      expect(d.errorDelReparto(_speed, 96, {_b1: 20}), frena);
    });

    test('no se saca del reparto mientras haya ventas cuya caja no llegó (las anuladas no frenan)', () {
      final c = caja(4, _b2);
      final v = vender(c, _speed, 2);
      expect(stock(cajas: const [], ventas: [v]).errorAlSacarDelReparto(_speed, _b2),
          'Hay ventas de cajas que todavía no llegaron a este equipo: probá de nuevo en un rato.');
      final anulada = AnulacionBarra.de(v, motivo: 'Se equivocó', ahora: ahora);
      expect(stock(cajas: const [], ventas: [v], anulaciones: [anulada]).errorAlSacarDelReparto(_speed, _b2), isNull);
      expect(stock(cajas: [c], ventas: [v]).errorAlSacarDelReparto(_speed, _b2), contains('no se puede sacar'));
    });

    test('el primer reparto de un producto cuenta lo que ya entró y faltó en el depósito', () {
      final precios = [precio(_cerveza, 240), precio(_speed, 96), precio(_agua, 30)];
      final s = stock(precios: precios, movimientos: [
        MovimientoDeStock.entrada(
            eventoId: _evento, productoId: _agua, cantidad: 10, deDonde: 'Trajo el jefe', ahora: ahora),
        MovimientoDeStock.faltante(
            eventoId: _evento, productoId: _agua, lugar: kDeposito, cantidad: 2, motivo: 'Rota', ahora: ahora),
      ]);
      expect(s.controla(_b1, _agua), isFalse, reason: 'todavía no se repartió');
      expect(s.errorDelReparto(_agua, 30, {_b1: 20, _b2: 18}), isNull, reason: '30 + 10 − 2 = 38');
      expect(s.errorDelReparto(_agua, 30, {_b1: 20, _b2: 19}), 'Hay 38: no se puede repartir 39.');
      expect(s.errorDelReparto(_agua, 40, {_b1: 20, _b2: 28}), isNull, reason: 'subir el stock general suma');
    });

    test('dos "voy en camino" a la misma barra y producto: se ve uno solo, el más nuevo, en cualquier orden', () {
      MovimientoDeStock avisar(String equipo, String quien, DateTime cuando) => MovimientoDeStock.enCamino(
            eventoId: _evento,
            productoId: _speed,
            barra: _b2,
            avisosPrevios: 0,
            hechoPor: quien,
            ahora: cuando,
          ).conEquipo(equipo);
      final deNico = avisar(_celu, 'Nico', DateTime.utc(2026, 12, 5, 0, 10));
      final deSole = avisar(_otro, 'Sole', DateTime.utc(2026, 12, 5, 0, 20));
      for (final movs in [
        [deNico, deSole],
        [deSole, deNico],
      ]) {
        final s = stock(movimientos: movs);
        expect(s.enCamino(_b2), hasLength(1));
        expect(s.enCaminoDe(_b2, _speed)!.quien, 'Sole');
      }
      // Si Sole ya repuso, queda el de Nico.
      final repusoSole = reponer(_speed, _b2, 6, equipo: _otro, cuando: DateTime.utc(2026, 12, 5, 0, 30));
      expect(stock(movimientos: [deSole, repusoSole, deNico]).enCaminoDe(_b2, _speed)!.quien, 'Nico');
      // A la misma hora decide el id: el mismo en todos los equipos.
      final otroDeNico = avisar(_celu, 'Nico', DateTime.utc(2026, 12, 5, 0, 20));
      expect(stock(movimientos: [otroDeNico, deSole]).enCaminoDe(_b2, _speed)!.aviso.id,
          stock(movimientos: [deSole, otroDeNico]).enCaminoDe(_b2, _speed)!.aviso.id);
    });

    test('el orden en que llegan ventas, cajas, anulaciones y movimientos no cambia nada', () {
      final c1 = caja(1, _b1), c4 = caja(4, _b2), c5 = caja(5, null);
      final ventas = [
        vender(c1, _cerveza, 5, cuando: antes),
        vender(c4, _cerveza, 3, cuando: antes),
        vender(c1, _speed, 2),
        vender(c4, _speed, 4, cuando: despues),
        vender(c5, _cerveza, 1),
        vender(c1, _cerveza, 2, cuando: despues),
      ];
      final anulaciones = [
        AnulacionBarra.de(ventas[2], motivo: 'No la sirvió', deviceId: 'pc-jefe', ahora: despues),
        AnulacionBarra.de(ventas[1], motivo: 'Se equivocó', deviceId: 'pc-jefe', ahora: antes),
      ];
      final repuesto = reponer(_cerveza, _b1, 12, cuando: antes);
      final visto = stock(cajas: [c1], ventas: ventas.sublist(0, 1), movimientos: [repuesto]);
      final movs = [
        repuesto,
        contar(visto, _b1, _cerveza, 66, motivo: 'Rota'),
        reponer(_speed, _b2, 6, equipo: _otro, cuando: despues),
        MovimientoDeStock.faltante(
            eventoId: _evento, productoId: _speed, lugar: _b2, cantidad: 1, motivo: 'Rota', ahora: despues),
      ];
      String todo(StockPorBarra s) => [
            for (final l in [kDeposito, _b1, _b2])
              for (final p in [_cerveza, _speed]) '$l $p ${s.en(l, p)?.queda}',
            'sin barra ${s.vendidoSinBarra}',
            'sin caja ${s.ventasSinCaja}',
          ].join('\n');
      final base = stock(cajas: [c1, c4, c5], ventas: ventas, anulaciones: anulaciones, movimientos: movs);
      expect(base.en(_b1, _cerveza)!.queda, 64, reason: 'contó 66; después se vendieron 2');
      expect(base.en(_b2, _cerveza)!.queda, 60, reason: 'la única venta de cerveza de la Barra 2 se anuló');
      final azar = Random(4);
      for (var i = 0; i < 25; i++) {
        final s = stock(
          cajas: [c1, c4, c5]..shuffle(azar),
          ventas: [...ventas]..shuffle(azar),
          anulaciones: [...anulaciones]..shuffle(azar),
          movimientos: [...movs]..shuffle(azar),
        );
        expect(todo(s), todo(base));
      }
    });
  });

  group('lo que se guarda', () {
    test('un movimiento va y vuelve de la base igual, con su foto', () {
      final m = contar(stock(), _b1, _cerveza, 58, motivo: 'Rota');
      final otra = MovimientoDeStock.fromMap(m.toMap());
      expect(otra.toMap(), m.toMap());
      expect(otra.tipo, TipoMovimientoDeStock.conteo);
      expect(otra.esConteo, isTrue);
    });

    test('un tipo que no se conoce (de una versión más nueva) se ignora sin romper', () {
      final raro = MovimientoDeStock.fromMap({...reponer(_cerveza, _b1, 12).toMap(), 'tipo': 'algo_nuevo'});
      expect(raro.tipo, isNull);
      expect(stock(movimientos: [raro]).en(_b1, _cerveza)!.queda, 60);
    });

    test('el reparto va y vuelve igual', () {
      final r = reparto(_cerveza, _b1, 60, aviso: 10);
      expect(StockEnLaBarra.fromMap(r.toMap()).toMap(), r.toMap());
      expect(r.id, isNot(reparto(_cerveza, _b2, 60).id));
    });

    test('un reparto negativo o sin barra no se arma', () {
      expect(() => reparto(_cerveza, _b1, -1), throwsArgumentError);
      expect(() => reparto(_cerveza, '  ', 3), throwsArgumentError);
      expect(() => reparto(_cerveza, _b1, 3, aviso: -1), throwsArgumentError);
    });
  });
}
