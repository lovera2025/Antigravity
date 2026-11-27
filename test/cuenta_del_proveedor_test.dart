import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/datos/movimiento_de_stock.dart';
import 'package:arguello_events/features/barra/datos/stock_en_la_barra.dart';

/// La pestaña GANANCIA del jefe (audio 77, 26-nov-2026): el jefe carga el stock con el
/// precio de lista del proveedor, vende a su precio, y ve lo que se vendió, lo que le
/// debe al proveedor y lo que ganó, juntando las noches que rinde de una vez. **Lo
/// perdido (roto, congelado) se le paga igual** (decisión del usuario). Todo en centavos.
const _viernes = 'e0000000-0000-4000-8000-000000000004';
const _sabado = 'e0000000-0000-4000-8000-000000000005';
const _lata = 'p0000000-0000-4000-8000-000000000001';
const _fernet = 'p0000000-0000-4000-8000-000000000002';
const _gaseosa = 'p0000000-0000-4000-8000-000000000003';
const _silla = 'p0000000-0000-4000-8000-000000000004';
const _b1 = 'Barra 1';

void main() {
  // Las fiestas: viernes 4 y sábado 5 de diciembre, a las 23 de Argentina (02 UTC del día siguiente).
  final noche4 = DateTime.utc(2026, 12, 5, 2);
  final noche5 = DateTime.utc(2026, 12, 6, 2);

  PrecioBarra precio(String evento, String producto, double venta, {int? stock, DateTime? ahora}) =>
      PrecioBarra.para(
        eventoId: evento,
        productoId: producto,
        precio: venta,
        stockInicial: stock,
        ahora: ahora ?? noche4,
      );

  StockEnLaBarra reparto(String evento, String producto, int arranque, {DateTime? ahora}) =>
      StockEnLaBarra.para(
        eventoId: evento,
        productoId: producto,
        barra: _b1,
        arranque: arranque,
        ahora: ahora ?? noche4,
      );

  CajaBarra caja(String evento, DateTime ahora, {int n = 1, String barra = _b1}) =>
      CajaBarra.abrir(eventoId: evento, numeroCaja: n, sede: barra, ahora: ahora);

  final numeros = <String, int>{};
  VentaBarra vender(CajaBarra c, String producto, double precio, int cantidad,
      {DateTime? ahora, double recargo = 0}) {
    final r = [RenglonVenta(productoId: producto, nombre: 'Producto $producto', precio: precio, cantidad: cantidad)];
    final n = (numeros[c.id] ?? 0) + 1;
    numeros[c.id] = n;
    final total = CuentaBarra(r).total;
    return VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: c.eventoId,
      numero: n,
      renglones: r,
      medio: recargo > 0 ? MedioBarra.transferencia : MedioBarra.efectivo,
      efectivo: recargo > 0 ? 0 : total,
      transferencia: recargo > 0 ? total + recargo : 0,
      recargo: recargo,
      deviceId: 'tablet-${c.numeroCaja}',
      ahora: ahora ?? DateTime.parse(c.abiertaAt),
    );
  }

  group('el ejemplo del audio', () {
    test('200 latas a \$1.500 de lista, venta \$5.000, vende 2: se vendió \$10.000, le debe \$3.000, '
        'ganó \$7.000 y quedan 198', () {
      final c = caja(_viernes, noche4);
      final cuenta = CuentaDelProveedor.de([
        FiestaParaLaGanancia(
          eventoId: _viernes,
          nombre: 'TÉCNICA',
          fecha: DateTime(2026, 12, 4),
          cajas: [c],
          ventas: [vender(c, _lata, 5000, 2)],
          precios: [precio(_viernes, _lata, 5000, stock: 200)],
          repartos: [reparto(_viernes, _lata, 200)],
          listas: {_lata: 1500},
        ),
      ]);
      final lata = cuenta.productos.single;
      expect(lata.vendidas, 2);
      expect(lata.seVendio, 1000000);
      expect(lata.leDebo, 300000);
      expect(lata.ganancia, 700000);
      expect(lata.quedaron, 198);
      expect(cuenta.seVendio, 1000000);
      expect(cuenta.leDebo, 300000);
      expect(cuenta.ganancia, 700000);
    });

    test('el agua de la maqueta: 100 a \$600, venta \$2.000, se venden 70: \$140.000 / \$42.000 / \$98.000; '
        'si se rompe 1, le debe \$42.600 y gana \$97.400', () {
      final c = caja(_viernes, noche4);
      FiestaParaLaGanancia fiesta({List<MovimientoDeStock> movimientos = const []}) => FiestaParaLaGanancia(
            eventoId: _viernes,
            nombre: 'TÉCNICA',
            fecha: DateTime(2026, 12, 4),
            cajas: [c],
            ventas: [vender(c, _lata, 2000, 70)],
            precios: [precio(_viernes, _lata, 2000, stock: 100)],
            repartos: [reparto(_viernes, _lata, 100)],
            movimientos: movimientos,
            listas: {_lata: 600},
          );
      numeros.clear();
      final sana = CuentaDelProveedor.de([fiesta()]).productos.single;
      expect((sana.seVendio, sana.leDebo, sana.ganancia, sana.quedaron), (14000000, 4200000, 9800000, 30));
      numeros.clear();
      final rota = MovimientoDeStock.faltante(
        eventoId: _viernes,
        productoId: _lata,
        lugar: _b1,
        cantidad: 1,
        motivo: 'rota',
        ahora: noche4.add(const Duration(hours: 1)),
      );
      final conRota = CuentaDelProveedor.de([fiesta(movimientos: [rota])]).productos.single;
      expect(conRota.perdidas, 1);
      expect(conRota.leDebo, 4260000);
      expect(conRota.ganancia, 9740000);
      expect(conRota.quedaron, 29);
    });
  });

  test('lo perdido se le paga igual: 2 vendidas y 2 rotas son 4 a precio de lista', () {
    final c = caja(_viernes, noche4);
    final rotas = MovimientoDeStock.faltante(
      eventoId: _viernes,
      productoId: _lata,
      lugar: _b1,
      cantidad: 2,
      motivo: 'rotas',
      ahora: noche4,
    );
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _lata, 5000, 2)],
        precios: [precio(_viernes, _lata, 5000, stock: 200)],
        repartos: [reparto(_viernes, _lata, 200)],
        movimientos: [rotas],
        listas: {_lata: 1500},
      ),
    ]).productos.single;
    expect(p.perdidas, 2);
    expect(p.leDebo, 600000);
    expect(p.ganancia, 400000);
  });

  test('una venta anulada no cuenta, ni en lo vendido ni en lo que se debe', () {
    final c = caja(_viernes, noche4);
    final buena = vender(c, _lata, 5000, 2);
    final anulada = vender(c, _lata, 5000, 3);
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [buena, anulada],
        anulaciones: [AnulacionBarra.de(anulada, motivo: 'se equivocó', ahora: noche4)],
        precios: [precio(_viernes, _lata, 5000)],
        listas: {_lata: 1500},
      ),
    ]).productos.single;
    expect(p.vendidas, 2);
    expect(p.seVendio, 1000000);
    expect(p.leDebo, 300000);
  });

  test('el recargo por transferencia va aparte: no entra en lo vendido ni en la ganancia', () {
    final c = caja(_viernes, noche4);
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _lata, 5000, 2, recargo: 500)],
        precios: [precio(_viernes, _lata, 5000)],
        listas: {_lata: 1500},
      ),
    ]);
    expect(cuenta.seVendio, 1000000);
    expect(cuenta.recargo, 50000);
    expect(cuenta.ganancia, 700000);
  });

  test('una caja de prueba de otro día no suma, y se dice', () {
    final prueba = caja(_viernes, DateTime.utc(2026, 12, 2, 18), n: 9);
    final c = caja(_viernes, noche4);
    final f = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [prueba, c],
        ventas: [vender(prueba, _lata, 5000, 10), vender(c, _lata, 5000, 2)],
        precios: [precio(_viernes, _lata, 5000)],
        listas: {_lata: 1500},
      ),
    ]);
    expect(f.vendidas, 2);
    expect(f.fiestas.single.noche, const DiaDeOperacion(2026, 12, 4));
    expect(f.fiestas.single.otrasNoches, {const DiaDeOperacion(2026, 12, 2): 1});
  });

  test('si la noche de la fiesta no tuvo cajas (la fecha quedó mal), se cuenta la que más vendió', () {
    final c = caja(_viernes, noche5);
    final f = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _lata, 5000, 4)],
        precios: [precio(_viernes, _lata, 5000)],
        listas: {_lata: 1500},
      ),
    ]);
    expect(f.vendidas, 4);
    expect(f.fiestas.single.noche, const DiaDeOperacion(2026, 12, 5));
  });

  test('el precio de lista con centavos: 3 × \$1.467,50 = \$4.402,50, sin errores de coma', () {
    final c = caja(_viernes, noche4);
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _fernet, 6000, 3)],
        precios: [precio(_viernes, _fernet, 6000)],
        listas: {_fernet: 1467.50},
      ),
    ]).productos.single;
    expect(p.leDebo, 440250);
    expect(p.ganancia, 1800000 - 440250);
    expect(p.lista, 146750);
  });

  test('dos fiestas: se suman, y si el precio de lista cambió, cada una con el suyo', () {
    final c4 = caja(_viernes, noche4);
    final c5 = caja(_sabado, noche5);
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _sabado,
        nombre: 'COLEGIO',
        fecha: DateTime(2026, 12, 5),
        cajas: [c5],
        ventas: [vender(c5, _lata, 5000, 10)],
        precios: [precio(_sabado, _lata, 5000)],
        listas: {_lata: 1600},
      ),
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c4],
        ventas: [vender(c4, _lata, 5000, 20)],
        precios: [precio(_viernes, _lata, 5000)],
        listas: {_lata: 1500},
      ),
    ]);
    final lata = cuenta.productos.single;
    expect(lata.vendidas, 30);
    expect(lata.leDebo, 20 * 150000 + 10 * 160000);
    expect(lata.listaVaria, isTrue);
    expect(lata.lista, isNull);
    expect([for (final f in cuenta.fiestas) f.nombre], ['TÉCNICA', 'COLEGIO'], reason: 'en el orden de las fechas');
  });

  test('sin precio de lista: no entra en lo que se debe, la ganancia no se sabe y se avisa; '
      'la silla con lista 0 es toda ganancia', () {
    final c = caja(_viernes, noche4);
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _gaseosa, 3000, 5), vender(c, _silla, 10000, 1), vender(c, _lata, 5000, 2)],
        precios: [precio(_viernes, _gaseosa, 3000), precio(_viernes, _silla, 10000), precio(_viernes, _lata, 5000)],
        listas: {_silla: 0, _lata: 1500},
      ),
    ]);
    final gaseosa = cuenta.productos.firstWhere((p) => p.productoId == _gaseosa);
    final silla = cuenta.productos.firstWhere((p) => p.productoId == _silla);
    expect(gaseosa.faltaLaLista, isTrue);
    expect(gaseosa.ganancia, isNull);
    expect(gaseosa.leDebo, 0);
    expect(silla.leDebo, 0);
    expect(silla.ganancia, 1000000);
    expect(cuenta.faltaLaLista.map((p) => p.productoId), [_gaseosa]);
    expect(cuenta.seVendio, 1500000 + 1000000 + 1000000);
    expect(cuenta.leDebo, 300000);
    expect(cuenta.ganancia, 1000000 + 700000, reason: 'sin la gaseosa, que no tiene lista');
  });

  test('un producto que no se vendió ni se perdió no pide precio de lista', () {
    final c = caja(_viernes, noche4);
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _lata, 5000, 1)],
        precios: [precio(_viernes, _lata, 5000), precio(_viernes, _gaseosa, 3000)],
        listas: {_lata: 1500},
      ),
    ]);
    expect(cuenta.faltaLaLista, isEmpty);
  });

  test('un conteo que encontró de más no baja lo que se le debe por lo vendido', () {
    final c = caja(_viernes, noche4);
    final venta = vender(c, _lata, 5000, 10);
    final conteo = MovimientoDeStock.conteo(
      eventoId: _viernes,
      productoId: _lata,
      lugar: _b1,
      contadas: 95,
      ajuste: 5,
      motivo: 'estaban en la heladera',
      foto: FotoDeStock(ventasHasta: {c.id: venta.numero}),
      ahora: noche4.add(const Duration(hours: 1)),
    );
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [venta],
        precios: [precio(_viernes, _lata, 5000, stock: 100)],
        repartos: [reparto(_viernes, _lata, 100)],
        movimientos: [conteo],
        listas: {_lata: 1500},
      ),
    ]).productos.single;
    expect(p.perdidas, 0);
    expect(p.leDebo, 10 * 150000);
    expect(p.quedaron, 95);
  });

  test('sin reparto a las barras, lo vendido igual baja lo que quedó', () {
    final c = caja(_viernes, noche4);
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: [vender(c, _lata, 5000, 2)],
        precios: [precio(_viernes, _lata, 5000, stock: 200)],
        listas: {_lata: 1500},
      ),
    ]).productos.single;
    expect(p.quedaron, 198);
  });

  test('lo que quedó, juntando fiestas, es lo de la última', () {
    final c4 = caja(_viernes, noche4);
    final c5 = caja(_sabado, noche5);
    final cuenta = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c4],
        ventas: [vender(c4, _lata, 5000, 20)],
        precios: [precio(_viernes, _lata, 5000, stock: 100)],
        repartos: [reparto(_viernes, _lata, 100)],
        listas: {_lata: 1500},
      ),
      FiestaParaLaGanancia(
        eventoId: _sabado,
        nombre: 'COLEGIO',
        fecha: DateTime(2026, 12, 5),
        cajas: [c5],
        ventas: [vender(c5, _lata, 5000, 50)],
        precios: [precio(_sabado, _lata, 5000, stock: 80, ahora: noche5)],
        repartos: [reparto(_sabado, _lata, 80, ahora: noche5)],
        listas: {_lata: 1500},
      ),
    ]);
    expect(cuenta.productos.single.quedaron, 30);
    expect(cuenta.fiestas.first.productos.single.quedaron, 80);
  });

  test('lo vendido en una barra donde ese producto no se repartió igual baja lo que quedó', () {
    final enLaBarra2 = caja(_viernes, noche4, n: 7, barra: 'Barra 2');
    final p = CuentaDelProveedor.de([
      FiestaParaLaGanancia(
        eventoId: _viernes,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [enLaBarra2],
        ventas: [vender(enLaBarra2, _lata, 5000, 5)],
        precios: [precio(_viernes, _lata, 5000, stock: 100)],
        repartos: [reparto(_viernes, _lata, 100)],
        listas: {_lata: 1500},
      ),
    ]).productos.single;
    expect(p.vendidas, 5);
    expect(p.quedaron, 95);
  });
}
