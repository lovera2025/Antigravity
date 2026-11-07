import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cobro_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/numero_de_ticket.dart';
import 'package:arguello_events/features/barra/cuentas/pesos.dart';
import 'package:arguello_events/features/barra/cuentas/stock_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Las cuentas de la barra, sin pantalla ni base: la cuenta de VENDER, el cobro con su
/// vuelto y su mixto, el número del ticket, el cierre de la caja, el resumen del jefe
/// y el stock.
const _evento = 'e0000000-0000-4000-8000-000000000001';
const _cerveza = 'p0000000-0000-4000-8000-000000000001';
const _agua = 'p0000000-0000-4000-8000-000000000002';
const _fernet = 'p0000000-0000-4000-8000-000000000003';

void main() {
  final ahora = DateTime.utc(2026, 12, 4, 23);

  group('la plata en el papel', () {
    test('sin decimales si no hay centavos, con puntos de mil', () {
      expect(pesos(0), r'$ 0');
      expect(pesos(7000), r'$ 7.000');
      expect(pesos(123000), r'$ 123.000');
      expect(pesos(1234567), r'$ 1.234.567');
      expect(pesos(3999.99), r'$ 3.999,99');
      expect(pesos(1500.5), r'$ 1.500,50');
      expect(pesos(-500), r'$ -500');
    });

    test('las cuentas van en centavos: 0,1 + 0,2 da 0,3', () {
      expect(centavos(0.1) + centavos(0.2), centavos(0.3));
      expect(deCentavos(centavos(1333.33) * 3), 3999.99);
    });
  });

  group('la cuenta de VENDER', () {
    CuentaBarra sumar(CuentaBarra c, String id, String n, double p) =>
        c.sumar(productoId: id, nombre: n, precio: p);

    test('tocar suma uno; el mismo producto suma en su renglón', () {
      var c = CuentaBarra.vacia;
      c = sumar(c, _cerveza, 'Cerveza', 3500);
      c = sumar(c, _agua, 'Agua', 1500);
      c = sumar(c, _cerveza, 'Cerveza', 3500);
      expect([for (final r in c.renglones) '${r.cantidad} ${r.nombre}'], ['2 Cerveza', '1 Agua']);
      expect(c.total, 8500);
      expect(c.unidades, 3);
      expect(c.cantidadDe(_cerveza), 2);
      expect(c.cantidadDe(_fernet), 0);
    });

    test('menos resta, y en cero el renglón sale; quitar lo saca entero', () {
      var c = sumar(sumar(CuentaBarra.vacia, _cerveza, 'Cerveza', 3500), _cerveza, 'Cerveza', 3500);
      c = sumar(c, _agua, 'Agua', 1500);
      c = c.restar(_cerveza);
      expect(c.cantidadDe(_cerveza), 1);
      c = c.restar(_cerveza);
      expect(c.cantidadDe(_cerveza), 0);
      expect(c.renglones.single.nombre, 'Agua');
      expect(c.restar(_fernet).renglones, c.renglones, reason: 'restar lo que no está no hace nada');
      expect(c.quitar(_agua).estaVacia, isTrue);
    });

    test('cada toque da una cuenta nueva: la de antes no cambia', () {
      final antes = sumar(CuentaBarra.vacia, _cerveza, 'Cerveza', 3500);
      final despues = sumar(antes, _cerveza, 'Cerveza', 3500);
      expect(antes.cantidadDe(_cerveza), 1);
      expect(despues.cantidadDe(_cerveza), 2);
    });

    test('un renglón se queda con el precio con que se sumó', () {
      var c = sumar(CuentaBarra.vacia, _cerveza, 'Cerveza', 3500);
      c = sumar(c, _cerveza, 'Cerveza', 4000);
      expect(c.total, 7000);
    });

    test('los centavos no se pierden', () {
      var c = CuentaBarra.vacia;
      for (var i = 0; i < 3; i++) {
        c = sumar(c, _fernet, 'Algo', 1333.33);
      }
      expect(c.total, 3999.99);
    });
  });

  group('el mixto', () {
    test('escribir el efectivo completa la transferencia, y al revés', () {
      final m = PartidoMixto.de(8500).conEfectivo(5000);
      expect(m.transferencia, 3500);
      final otro = m.conTransferencia(2000);
      expect(otro.efectivo, 6500);
      expect(centavos(otro.efectivo) + centavos(otro.transferencia), centavos(8500));
    });

    test('lo que se pasa del total queda en el total, lo negativo en cero', () {
      expect(PartidoMixto.de(8500).conEfectivo(9999).efectivo, 8500);
      expect(PartidoMixto.de(8500).conEfectivo(-5).efectivo, 0);
      expect(PartidoMixto.de(8500).conTransferencia(9999).efectivo, 0);
    });

    test('un mixto lleva las dos partes', () {
      expect(PartidoMixto.de(8500).lasDosPartes, isFalse, reason: 'empieza todo por transferencia');
      expect(PartidoMixto.de(8500).conEfectivo(8500).lasDosPartes, isFalse);
      expect(PartidoMixto.de(8500).conEfectivo(0.01).lasDosPartes, isTrue);
    });
  });

  group('COBRAR', () {
    test('en efectivo: con lo que entrega, el vuelto en vivo', () {
      final c = CobroBarra.de(7000).conRecibe(10000);
      expect(c.efectivo, 7000);
      expect(c.transferencia, 0);
      expect(c.vuelto, 3000);
      expect(c.puedeConfirmar, isTrue);
    });

    test('en efectivo justo, sin anotar lo que entrega, se confirma', () {
      final c = CobroBarra.de(7000);
      expect(c.vuelto, isNull);
      expect(c.puedeConfirmar, isTrue);
    });

    test('si entrega menos que el total, no confirma y dice por qué', () {
      final c = CobroBarra.de(7000).conRecibe(5000);
      expect(c.puedeConfirmar, isFalse);
      expect(c.falta, 'Entrega menos que el total');
      expect(c.vuelto, isNull);
      expect(c.conRecibe(null).puedeConfirmar, isTrue, reason: 'borrar lo que entrega es pagar justo');
    });

    test('por transferencia se confirma sin tilde: quien cobra ve el pago en el posnet', () {
      final c = CobroBarra.de(7000, recargo: false).conMedio(MedioBarra.transferencia);
      expect(c.efectivo, 0);
      expect(c.transferencia, 7000);
      expect(c.recargo, 0);
      expect(c.transfiere, 7000);
      expect(c.puedeConfirmar, isTrue);
    });

    test('el recargo: un % de lo transferido, en pesos enteros, y se suma a lo que paga', () {
      final c = CobroBarra.de(50000, medio: MedioBarra.transferencia);
      expect(c.recargoPrendido, isTrue, reason: 'viene prendido');
      expect(c.recargoPct, 5);
      expect(c.recargo, 2500);
      expect(c.transfiere, 52500);
      expect(c.aCobrar, 52500);
      expect(c.recargoPctQueQueda, 5);
      expect(c.conRecargoPct(3.5).recargo, 1750);
      expect(CobroBarra.de(3333, medio: MedioBarra.transferencia).recargo, 167, reason: '166,65 redondea');
    });

    test('el recargo en pesos, escrito a mano; y el check lo apaga', () {
      final c = CobroBarra.de(50000, medio: MedioBarra.transferencia)
          .conModoRecargo(ModoRecargo.pesos)
          .conRecargoPesos(2000);
      expect(c.recargo, 2000);
      expect(c.transfiere, 52000);
      expect(c.recargoPctQueQueda, isNull, reason: 'en pesos no queda %');
      expect(c.conRecargo(false).recargo, 0);
      expect(c.conRecargo(false).aCobrar, 50000);
    });

    test('el recargo prendido sin número no confirma, y dice por qué', () {
      final c = CobroBarra.de(50000, medio: MedioBarra.transferencia);
      expect(c.conRecargoPct(0).falta, 'Poné el porcentaje del recargo');
      expect(c.conModoRecargo(ModoRecargo.pesos).falta, 'Poné el recargo en pesos');
      expect(c.conRecargoPct(0).conRecargo(false).puedeConfirmar, isTrue);
    });

    test('en efectivo no hay recargo, aunque el check esté prendido', () {
      final c = CobroBarra.de(7000);
      expect(c.recargoPrendido, isTrue);
      expect(c.recargo, 0);
      expect(c.aCobrar, 7000);
    });

    test('por transferencia, lo que se había anotado en efectivo no cuenta', () {
      final c = CobroBarra.de(7000).conRecibe(5000).conMedio(MedioBarra.transferencia);
      expect(c.recibeQueCuenta, isNull);
      expect(c.vuelto, isNull);
      expect(c.puedeConfirmar, isTrue);
    });

    test('mixto: suma el total, lleva las dos partes, y el recargo va solo sobre lo transferido', () {
      var c = CobroBarra.de(50000, medio: MedioBarra.mixto);
      expect(c.falta, 'Poné cuánto es en efectivo y cuánto por transferencia');
      c = c.conEfectivoDelMixto(20000);
      expect(c.efectivo + c.transferencia, 50000);
      expect(c.recargo, 1500, reason: '5 % de 30.000');
      expect(c.transfiere, 31500);
      expect(c.aCobrar, 51500);
      expect(c.puedeConfirmar, isTrue);
      c = c.conRecibe(10000);
      expect(c.falta, 'Entrega menos que la parte en efectivo');
      c = c.conRecibe(25000);
      expect(c.vuelto, 5000);
      expect(c.puedeConfirmar, isTrue);
    });

    test('mixto: "Por transferencia" se escribe con el recargo adentro, como se ve', () {
      final c = CobroBarra.de(50000, medio: MedioBarra.mixto).conTransfiereDelMixto(31500);
      expect(c.transferencia, 30000);
      expect(c.efectivo, 20000);
      expect(c.transfiere, 31500);
      final enPesos = CobroBarra.de(50000, medio: MedioBarra.mixto)
          .conModoRecargo(ModoRecargo.pesos)
          .conRecargoPesos(1000)
          .conTransfiereDelMixto(31000);
      expect(enPesos.transferencia, 30000);
      expect(enPesos.transfiere, 31000);
      final sinRecargo = CobroBarra.de(50000, medio: MedioBarra.mixto, recargo: false)
          .conTransfiereDelMixto(31000);
      expect(sinRecargo.transferencia, 31000);
    });

    test('cambiar de medio y volver deja lo que estaba', () {
      final c = CobroBarra.de(8500)
          .conMedio(MedioBarra.mixto)
          .conEfectivoDelMixto(5000)
          .conMedio(MedioBarra.efectivo)
          .conMedio(MedioBarra.mixto);
      expect(c.efectivo, 5000);
    });

    test('una cuenta vacía no se cobra', () {
      expect(CobroBarra.de(0).falta, 'La cuenta está vacía');
    });

    test('todo cobro que se puede confirmar arma una venta que cierra', () {
      final renglones = [
        const RenglonVenta(productoId: _cerveza, nombre: 'Cerveza', precio: 3500, cantidad: 2),
        const RenglonVenta(productoId: _agua, nombre: 'Agua', precio: 1500, cantidad: 1),
      ];
      final total = CuentaBarra(renglones).total;
      final cobros = <CobroBarra>[
        CobroBarra.de(total),
        CobroBarra.de(total).conRecibe(10000),
        CobroBarra.de(total).conRecibe(total),
        CobroBarra.de(total).conMedio(MedioBarra.transferencia),
        CobroBarra.de(total, recargo: false).conMedio(MedioBarra.transferencia),
        CobroBarra.de(total).conRecibe(20000).conMedio(MedioBarra.transferencia),
        CobroBarra.de(total, medio: MedioBarra.transferencia)
            .conModoRecargo(ModoRecargo.pesos)
            .conRecargoPesos(700),
        for (final e in <double>[0.01, 100, 5000, 8499.99])
          CobroBarra.de(total).conMedio(MedioBarra.mixto).conEfectivoDelMixto(e),
        CobroBarra.de(total).conMedio(MedioBarra.mixto).conTransferenciaDelMixto(1500).conRecibe(7000),
        CobroBarra.de(total, medio: MedioBarra.mixto).conTransfiereDelMixto(4000),
      ];
      for (final c in cobros) {
        expect(c.puedeConfirmar, isTrue, reason: '${c.medio} ${c.efectivo}');
        final v = VentaBarra.nueva(
          cajaBarraId: 'c',
          eventoId: _evento,
          numero: 1,
          renglones: renglones,
          medio: c.medio,
          efectivo: c.efectivo,
          transferencia: c.transfiere,
          recibe: c.recibeQueCuenta,
          recargo: c.recargo,
          recargoPct: c.recargoPctQueQueda,
          ahora: ahora,
        );
        expect(v.total, total);
        expect(v.recargo, c.recargo);
        expect(v.cobrado, c.aCobrar);
        expect(v.vuelto, c.vuelto ?? 0);
      }
    });
  });

  group('el número del ticket y su QR', () {
    test('Caja 2 · N° 0017', () {
      expect(NumeroDeTicket.texto(numeroCaja: 2, numero: 17), 'Caja 2 · N° 0017');
      expect(NumeroDeTicket.texto(numeroCaja: 6, numero: 12345), 'Caja 6 · N° 12345');
    });

    test('el QR lleva el id de la venta, y se lee de vuelta', () {
      const id = 'a1b2c3d4-0000-4000-8000-000000000017';
      final qr = NumeroDeTicket.qr(id);
      expect(qr, 'je:barra:$id');
      expect(NumeroDeTicket.ventaDelQr(' $qr\n'), id);
      expect(NumeroDeTicket.ventaDelQr(qr.toUpperCase().replaceFirst('JE:BARRA:', 'je:barra:')), id);
    });

    test('otro QR no es una venta', () {
      expect(NumeroDeTicket.ventaDelQr('https://arguello-events.vercel.app/lista?evento=x'), isNull);
      expect(NumeroDeTicket.ventaDelQr('je:barra:no-es-un-id'), isNull);
      expect(NumeroDeTicket.ventaDelQr(''), isNull);
    });
  });

  // ── El cierre, el resumen y el stock ─────────────────────────────────────

  CajaBarra caja(int numero, {double cambio = 20000}) => CajaBarra.abrir(
        eventoId: _evento,
        operadorNombre: 'Caja $numero',
        numeroCaja: numero,
        cambioInicial: cambio,
        ahora: ahora,
      );

  var numero = 0;
  VentaBarra vender(
    CajaBarra c,
    List<RenglonVenta> renglones, {
    MedioBarra medio = MedioBarra.efectivo,
    double? efectivo,
    double transferencia = 0,
    String eventoId = _evento,
  }) {
    final total = CuentaBarra(renglones).total;
    return VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: eventoId,
      numero: ++numero,
      renglones: renglones,
      medio: medio,
      efectivo: efectivo ?? (medio == MedioBarra.transferencia ? 0 : total - transferencia),
      transferencia: medio == MedioBarra.transferencia ? total : transferencia,
      ahora: ahora,
    );
  }

  RenglonVenta cervezas(int n) =>
      RenglonVenta(productoId: _cerveza, nombre: 'Cerveza', precio: 3500, cantidad: n);
  RenglonVenta aguas(int n) =>
      RenglonVenta(productoId: _agua, nombre: 'Agua', precio: 1500, cantidad: n);

  group('el cierre de la caja', () {
    test('el efectivo esperado es el cambio más lo cobrado en efectivo', () {
      final c = caja(2);
      final ventas = [
        vender(c, [cervezas(2)]),
        vender(c, [aguas(1)], medio: MedioBarra.transferencia),
        vender(c, [cervezas(1), aguas(1)], medio: MedioBarra.mixto, efectivo: 3000, transferencia: 2000),
      ];
      final cierre = CierreDeBarra.de(c, ventas, const []);
      expect(cierre.ventas, 3);
      expect(cierre.mixtos, 1);
      expect(cierre.efectivo, 10000);
      expect(cierre.transferencia, 3500);
      expect(cierre.total, 13500);
      expect(cierre.efectivoEsperado, 30000);
      expect(cierre.diferenciaCon(30000), 0);
      expect(cierre.diferenciaCon(29500), -500);
      expect(cierre.diferenciaCon(31000), 1000);
    });

    test('una venta anulada no cuenta, tampoco en el efectivo esperado', () {
      final c = caja(2);
      final buena = vender(c, [cervezas(2)]);
      final anulada = vender(c, [aguas(2)]);
      final cierre = CierreDeBarra.de(
        c,
        [buena, anulada],
        [AnulacionBarra.de(anulada, motivo: 'se cobró dos veces', ahora: ahora)],
      );
      expect(cierre.ventas, 1);
      expect(cierre.anuladas, 1);
      expect(cierre.efectivo, 7000);
      expect(cierre.efectivoAnulado, 3000);
      expect(cierre.efectivoEsperado, 27000);
    });

    test('las ventas de otra caja no entran', () {
      final a = caja(2);
      final b = caja(3);
      final cierre = CierreDeBarra.de(a, [vender(a, [cervezas(1)]), vender(b, [cervezas(5)])], const []);
      expect(cierre.ventas, 1);
      expect(cierre.efectivo, 3500);
    });

    test('los recargos entran en la transferencia y se cuentan aparte; no en el efectivo', () {
      final c = caja(2);
      final conRecargo = VentaBarra.nueva(
        cajaBarraId: c.id,
        eventoId: _evento,
        numero: ++numero,
        renglones: [cervezas(2)],
        medio: MedioBarra.mixto,
        efectivo: 3000,
        transferencia: 4200,
        recargo: 200,
        recargoPct: 5,
        ahora: ahora,
      );
      final cierre = CierreDeBarra.de(c, [conRecargo, vender(c, [aguas(1)])], const []);
      expect(cierre.transferencia, 4200);
      expect(cierre.recargos, 200);
      expect(cierre.total, 8700);
      expect(cierre.efectivoEsperado, 24500);
      expect(ResumenDeCajas.de(cajas: [c], ventas: [conRecargo], anulaciones: const []).recargos, 200);
    });

    test('lo vendido por producto: agrupado, sin las anuladas, el que más salió primero', () {
      final c = caja(2);
      final ventas = [
        vender(c, [cervezas(2), aguas(1)]),
        vender(c, [aguas(3)]),
        vender(c, [cervezas(5)]),
      ];
      final anulada = vender(c, [cervezas(10)]);
      final cierre = CierreDeBarra.de(
        c,
        [...ventas, anulada, vender(caja(3), [aguas(9)])],
        [AnulacionBarra.de(anulada, motivo: 'error', ahora: ahora)],
      );
      expect([for (final p in cierre.porProducto) '${p.unidades} ${p.nombre} ${p.plata}'], [
        '7 Cerveza 24500.0',
        '4 Agua 6000.0',
      ]);
      expect(cierre.unidades, 11);
      expect(cierre.sillas, 0);
    });

    test('a igual cantidad, por nombre; y el nombre que queda es el de la última venta', () {
      final c = caja(2);
      final cierre = CierreDeBarra.de(c, [
        vender(c, [aguas(2)]),
        vender(c, [cervezas(2)]),
        vender(c, [const RenglonVenta(productoId: _agua, nombre: 'Agua sin gas', precio: 1500, cantidad: 1)]),
        vender(c, [cervezas(1)]),
      ], const []);
      expect([for (final p in cierre.porProducto) p.nombre], ['Agua sin gas', 'Cerveza']);
    });

    test('las sillas de la noche se cuentan aparte', () {
      final c = caja(2);
      final cierre = CierreDeBarra.de(c, [
        vender(c, [
          cervezas(2),
          const RenglonVenta(productoId: 's', nombre: 'Silla extra', precio: 8000, cantidad: 3),
        ]),
      ], const []);
      expect(cierre.sillas, 3);
      expect(cierre.unidades, 5);
    });

    test('la diferencia en palabras', () {
      expect(diferenciaEnPalabras(0), 'Justo, sin diferencia');
      expect(diferenciaEnPalabras(500), r'Sobran $ 500');
      expect(diferenciaEnPalabras(-1500), r'Faltan $ 1.500');
    });
  });

  group('CAJAS del jefe', () {
    test('cada caja con sus cuentas, por número, y los totales', () {
      final tres = caja(3);
      final dos = caja(2, cambio: 10000);
      final ventas = [
        vender(dos, [cervezas(2)]),
        vender(tres, [aguas(2)], medio: MedioBarra.transferencia),
        vender(tres, [cervezas(1)]),
      ];
      final cerrada = dos.cerrada(efectivoContado: 16500, diferencia: -500, ahora: ahora);
      final r = ResumenDeCajas.de(cajas: [tres, cerrada], ventas: ventas, anulaciones: const []);
      expect([for (final c in r.cajas) c.caja.numeroCaja], [2, 3]);
      expect(r.ventas, 3);
      expect(r.efectivo, 10500);
      expect(r.transferencia, 3000);
      expect(r.total, 13500);
      expect(r.abiertas, 1);
      expect(r.contado, 16500, reason: 'solo las cerradas');
      expect(r.diferencia, -500);
      expect(r.cajas.first.diferencia, -500);
      expect(r.cajas.last.diferencia, isNull);
    });

    test('anular después de cerrar no le cambia la diferencia anotada', () {
      final c = caja(2);
      final v = vender(c, [cervezas(2)]);
      final cerrada = c.cerrada(efectivoContado: 27000, diferencia: 0, ahora: ahora);
      final r = ResumenDeCajas.de(
        cajas: [cerrada],
        ventas: [v],
        anulaciones: [AnulacionBarra.de(v, motivo: 'error', ahora: ahora)],
      );
      expect(r.cajas.single.diferencia, 0, reason: 'el cierre no se corrige');
      expect(r.cajas.single.cuentas.efectivoEsperado, 20000, reason: 'las cuentas de hoy sí la sacan');
      expect(r.anuladas, 1);
    });
  });

  group('el stock', () {
    PrecioBarra precio(String producto, {int? stock, int? aviso, String eventoId = _evento}) =>
        PrecioBarra.para(
          eventoId: eventoId,
          productoId: producto,
          precio: 1,
          stockInicial: stock,
          avisoStock: aviso,
          ahora: ahora,
        );

    test('descuenta lo vendido que cuenta: las anuladas no', () {
      final c = caja(2);
      final v1 = vender(c, [cervezas(3), aguas(1)]);
      final v2 = vender(c, [cervezas(2)]);
      final stock = StockDeLaBarra.de(
        eventoId: _evento,
        precios: [precio(_cerveza, stock: 100, aviso: 10), precio(_agua, stock: 50)],
        ventas: [v1, v2],
        anulaciones: [AnulacionBarra.de(v2, motivo: 'x', ahora: ahora)],
      );
      expect(stock[_cerveza]!.vendido, 3);
      expect(stock[_cerveza]!.queda, 97);
      expect(stock[_agua]!.queda, 49);
      expect(stock[_cerveza]!.enAviso, isFalse);
    });

    test('avisa al llegar al mínimo, y en cero o menos, siempre', () {
      final c = caja(2);
      Map<String, StockDeProducto> con(int vendidas) => StockDeLaBarra.de(
            eventoId: _evento,
            precios: [precio(_cerveza, stock: 12, aviso: 2), precio(_agua, stock: 1)],
            ventas: [vender(c, [cervezas(vendidas), aguas(1)])],
            anulaciones: const [],
          );
      expect(con(9)[_cerveza]!.enAviso, isFalse);
      expect(con(10)[_cerveza]!.enAviso, isTrue);
      expect(con(10)[_cerveza]!.agotado, isFalse);
      expect(con(12)[_cerveza]!.agotado, isTrue);
      expect(con(14)[_cerveza]!.queda, -2, reason: 'el stock avisa, no frena la venta');
      expect(con(1)[_agua]!.enAviso, isTrue, reason: 'sin mínimo cargado, avisa al terminarse');
    });

    test('sin stock cargado no se controla', () {
      final stock = StockDeLaBarra.de(
        eventoId: _evento,
        precios: [precio(_fernet)],
        ventas: [vender(caja(1), [const RenglonVenta(productoId: _fernet, nombre: 'Fernet', precio: 6000, cantidad: 4)])],
        anulaciones: const [],
      );
      expect(stock[_fernet]!.controla, isFalse);
      expect(stock[_fernet]!.queda, isNull);
      expect(stock[_fernet]!.enAviso, isFalse);
      expect(stock[_fernet]!.vendido, 4);
    });

    test('cada fiesta cuenta lo suyo', () {
      const otra = 'e0000000-0000-4000-8000-000000000002';
      final c = caja(1);
      final stock = StockDeLaBarra.de(
        eventoId: _evento,
        precios: [precio(_cerveza, stock: 10), precio(_cerveza, stock: 99, eventoId: otra)],
        ventas: [vender(c, [cervezas(2)]), vender(c, [cervezas(5)], eventoId: otra)],
        anulaciones: const [],
      );
      expect(stock.keys, [_cerveza]);
      expect(stock[_cerveza]!.inicial, 10);
      expect(stock[_cerveza]!.queda, 8);
    });

    test('para el jefe: solo los controlados, los que están en aviso arriba', () {
      final c = caja(1);
      final stock = StockDeLaBarra.de(
        eventoId: _evento,
        precios: [
          precio(_cerveza, stock: 100, aviso: 10),
          precio(_agua, stock: 20, aviso: 5),
          precio(_fernet),
        ],
        ventas: [vender(c, [cervezas(10), aguas(16)])],
        anulaciones: const [],
      );
      expect([for (final s in StockDeLaBarra.paraElJefe(stock)) s.productoId], [_agua, _cerveza]);
    });
  });

  test('las fiestas que la cajera puede elegir: las que tienen algún precio activo', () {
    const otra = 'e0000000-0000-4000-8000-000000000002';
    const sinActivos = 'e0000000-0000-4000-8000-000000000003';
    final precios = [
      PrecioBarra.para(eventoId: _evento, productoId: _cerveza, precio: 1, ahora: ahora),
      PrecioBarra.para(eventoId: otra, productoId: _cerveza, precio: 1, ahora: ahora),
      PrecioBarra.para(eventoId: sinActivos, productoId: _agua, precio: 1, activo: false, ahora: ahora),
    ];
    expect(fiestasConPrecios(precios), {_evento, otra});
  });
}
