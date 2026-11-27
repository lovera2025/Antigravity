import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cuenta_barra.dart';
import 'package:arguello_events/features/barra/cuentas/cuenta_del_proveedor.dart';
import 'package:arguello_events/features/barra/cuentas/recetas_de_la_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/datos/receta_barra.dart';
import 'package:arguello_events/features/barra/datos/stock_en_la_barra.dart';

/// Los tragos con receta (WhatsApp del jefe, 26-nov-2026): el Fernet con coca lleva 200 cc
/// de fernet y 500 de coca; el vodka, 500 cc de vodka y un Speed. "Más o menos, para
/// calcularle". **Las botellas no se cuentan en la barra**: se calculan con los tragos
/// vendidos, para GANANCIA. **Lo que va entero (el Speed) baja de su stock** como si se
/// vendiera suelto. Todo en centavos.
const _fiesta = 'e0000000-0000-4000-8000-000000000004';
const _otra = 'e0000000-0000-4000-8000-000000000005';
const _cerveza = 'p0000000-0000-4000-8000-000000000001';
const _agua = 'p0000000-0000-4000-8000-000000000002';
const _speed = 'p0000000-0000-4000-8000-000000000003';
const _fernetConCoca = 'p0000000-0000-4000-8000-000000000004';
const _vodkaConSpeed = 'p0000000-0000-4000-8000-000000000005';
const _fernet = 'p0000000-0000-4000-8000-000000000006';
const _coca = 'p0000000-0000-4000-8000-000000000007';
const _vodka = 'p0000000-0000-4000-8000-000000000008';
const _b1 = 'Barra 1';

void main() {
  final noche = DateTime.utc(2026, 12, 5, 2);

  RecetaBarra ing(String trago, String ingrediente, int cantidad, UnidadDeReceta unidad,
          {String evento = _fiesta, bool activo = true}) =>
      RecetaBarra.para(
        eventoId: evento,
        productoId: trago,
        ingredienteId: ingrediente,
        cantidad: cantidad,
        unidad: unidad,
        activo: activo,
        ahora: noche,
      );

  final lasDelJefe = [
    ing(_fernetConCoca, _fernet, 200, UnidadDeReceta.cc),
    ing(_fernetConCoca, _coca, 500, UnidadDeReceta.cc),
    ing(_vodkaConSpeed, _vodka, 500, UnidadDeReceta.cc),
    ing(_vodkaConSpeed, _speed, 1, UnidadDeReceta.unidad),
  ];

  CajaBarra caja(String evento) => CajaBarra.abrir(eventoId: evento, numeroCaja: 1, sede: _b1, ahora: noche);

  final numeros = <String, int>{};
  setUp(numeros.clear);

  VentaBarra vender(CajaBarra c, String producto, double precio, int cantidad) {
    final r = [RenglonVenta(productoId: producto, nombre: 'Producto $producto', precio: precio, cantidad: cantidad)];
    final n = (numeros[c.id] ?? 0) + 1;
    numeros[c.id] = n;
    final total = CuentaBarra(r).total;
    return VentaBarra.nueva(
      cajaBarraId: c.id,
      eventoId: c.eventoId,
      numero: n,
      renglones: r,
      medio: MedioBarra.efectivo,
      efectivo: total,
      deviceId: 'tablet-1',
      ahora: noche,
    );
  }

  PrecioBarra precio(String producto, double venta, {int? stock, String evento = _fiesta}) =>
      PrecioBarra.para(eventoId: evento, productoId: producto, precio: venta, stockInicial: stock, ahora: noche);

  StockEnLaBarra reparto(String producto, int arranque) =>
      StockEnLaBarra.para(eventoId: _fiesta, productoId: producto, barra: _b1, arranque: arranque, ahora: noche);

  group('RecetasDeLaBarra', () {
    final recetas = RecetasDeLaBarra.de(lasDelJefe, eventoId: _fiesta);

    test('vender un vodka baja un Speed del stock; el fernet y la coca, en cc, no bajan nada', () {
      final c = caja(_fiesta);
      final vodkas = vender(c, _vodkaConSpeed, 10000, 3);
      final fernets = vender(c, _fernetConCoca, 10000, 2);
      final [conSpeed, sinNada] = recetas.paraElStock([vodkas, fernets]);
      expect(conSpeed.id, vodkas.id, reason: 'la misma venta: una anulación la sigue alcanzando');
      expect(conSpeed.total, vodkas.total, reason: 'lo de adentro no es plata');
      final speed = conSpeed.renglones.singleWhere((r) => r.productoId == _speed);
      expect((speed.cantidad, speed.precio), (3, 0));
      expect(conSpeed.renglones.map((r) => r.productoId), isNot(contains(_vodka)));
      expect(identical(sinNada, fernets), isTrue, reason: 'en cc no se suma ningún renglón');
    });

    test('una venta sin tragos queda igual, y sin recetas no cambia nada', () {
      final v = vender(caja(_fiesta), _cerveza, 3000, 2);
      expect(identical(recetas.paraElStock([v]).single, v), isTrue);
      expect(identical(RecetasDeLaBarra.ninguna.paraElStock([v]).single, v), isTrue);
    });

    test('las recetas de otra fiesta y los ingredientes sacados no cuentan', () {
      final r = RecetasDeLaBarra.de([
        ing(_vodkaConSpeed, _speed, 1, UnidadDeReceta.unidad, evento: _otra),
        ing(_fernetConCoca, _speed, 1, UnidadDeReceta.unidad, activo: false),
      ], eventoId: _fiesta);
      expect(r.tieneReceta(_vodkaConSpeed), isFalse);
      expect(r.tieneReceta(_fernetConCoca), isFalse);
    });

    test('para cuántos vodkas alcanza el Speed, y qué pide al stock vender 2', () {
      expect(recetas.alcanzaPara(_vodkaConSpeed, (id) => id == _speed ? 31 : null), 31);
      expect(recetas.alcanzaPara(_vodkaConSpeed, (id) => id == _speed ? 0 : null), 0);
      expect(recetas.alcanzaPara(_vodkaConSpeed, (_) => null), isNull, reason: 'Speed sin stock controlado');
      expect(recetas.alcanzaPara(_fernetConCoca, (_) => 5), isNull, reason: 'el fernet va en cc: no se cuenta');
      expect(recetas.loQueBaja(_vodkaConSpeed, 2), {_vodkaConSpeed: 2, _speed: 2});
      expect(recetas.loQueBaja(_fernetConCoca, 2), {_fernetConCoca: 2});
    });

    test('un trago no se lleva a sí mismo, y la cantidad va de 1 en adelante', () {
      expect(() => ing(_vodkaConSpeed, _vodkaConSpeed, 1, UnidadDeReceta.unidad), throwsArgumentError);
      expect(() => ing(_vodkaConSpeed, _speed, 0, UnidadDeReceta.unidad), throwsArgumentError);
    });

    test('la receta va y vuelve de la base igual', () {
      final r = lasDelJefe.last;
      final leida = RecetaBarra.fromMap(r.toMap());
      expect(leida.toMap(), r.toMap());
      expect(RecetaBarra.fromMap({...r.toMap(), 'unidad': 'algo-nuevo'}).unidad, UnidadDeReceta.cc,
          reason: 'lo que esta versión no conoce no baja stock de nada');
    });
  });

  group('GANANCIA con tragos (la maqueta del 26-nov)', () {
    FiestaParaLaGanancia laNoche({List<AnulacionBarra> anulaciones = const [], List<VentaBarra>? extra}) {
      final c = caja(_fiesta);
      final ventas = [
        vender(c, _cerveza, 3000, 180),
        vender(c, _agua, 2000, 70),
        vender(c, _speed, 3500, 60),
        vender(c, _fernetConCoca, 10000, 40),
        vender(c, _vodkaConSpeed, 10000, 25),
        ...?extra,
      ];
      return FiestaParaLaGanancia(
        eventoId: _fiesta,
        nombre: 'TÉCNICA',
        fecha: DateTime(2026, 12, 4),
        cajas: [c],
        ventas: ventas,
        anulaciones: anulaciones,
        precios: [
          precio(_cerveza, 3000),
          precio(_agua, 2000),
          precio(_speed, 3500, stock: 150),
          precio(_fernetConCoca, 10000),
          precio(_vodkaConSpeed, 10000),
        ],
        repartos: [reparto(_speed, 150)],
        recetas: lasDelJefe,
        listas: {_cerveza: 1500, _agua: 600, _speed: 1200, _fernet: 11740, _coca: 3000, _vodka: 8000},
        contenidos: {_fernet: 750, _coca: 2250, _vodka: 1000},
      );
    }

    test('el Fernet con coca cuesta \$3.797,33 y el vodka \$5.200; 40 Fernet con coca: se vendió \$400.000, '
        'le debo \$151.893,34 y gané \$248.106,66', () {
      final cuenta = CuentaDelProveedor.de([laNoche()], nombres: {_fernetConCoca: 'Fernet con coca'});
      final fyc = cuenta.productos.singleWhere((p) => p.productoId == _fernetConCoca);
      expect(fyc.porReceta, isTrue);
      expect(fyc.lista, 379733);
      expect((fyc.vendidas, fyc.seVendio, fyc.leDebo, fyc.ganancia), (40, 40000000, 15189334, 24810666));
      final vodka = cuenta.productos.singleWhere((p) => p.productoId == _vodkaConSpeed);
      expect((vodka.lista, vodka.leDebo, vodka.ganancia), (520000, 13000000, 12000000));
      expect(fyc.perdidas, 0, reason: 'un trago no tiene stock propio');
    });

    test('los totales de la maqueta (sin las roturas), y "Para el proveedor" da lo mismo contado por botella '
        'y lata', () {
      final cuenta = CuentaDelProveedor.de([laNoche()]);
      expect(cuenta.seVendio, 154000000);
      // La maqueta suma 3 cervezas y 1 agua rotas (\$5.100): acá no se rompe nada.
      expect(cuenta.leDebo, 67099334 - 510000);
      expect(cuenta.ganancia, 86900666 + 510000);
      final usos = {for (final u in cuenta.paraElProveedor) u.productoId: u};
      expect(usos.values.fold<int>(0, (s, u) => s + u.leDebo), cuenta.leDebo);
      final speed = usos[_speed]!;
      expect((speed.sueltas, speed.enTragos, speed.unidades, speed.leDebo), (60, 25, 85, 10200000));
      final fernet = usos[_fernet]!;
      expect(fernet.cc, 8000);
      expect(fernet.usadas, closeTo(10.667, 0.001));
      expect(fernet.leDebo, 12522667);
      expect(usos[_coca]!.usadas, closeTo(8.889, 0.001));
      expect(usos[_vodka]!.usadas, 12.5);
      expect(usos[_vodka]!.leDebo, 10000000);
      expect(usos.containsKey(_fernetConCoca), isFalse, reason: 'el trago no se le compra a nadie');
    });

    test('el Speed de los vodkas baja de su stock: de 150 quedan 65, sin perdidas', () {
      final cuenta = CuentaDelProveedor.de([laNoche()]);
      final speed = cuenta.productos.singleWhere((p) => p.productoId == _speed);
      expect(speed.vendidas, 60, reason: 'vendidos sueltos: los del vodka no son ventas de Speed');
      expect(speed.quedaron, 65);
      expect(speed.perdidas, 0);
    });

    test('un vodka anulado no cuenta y devuelve su Speed', () {
      final c = caja(_fiesta);
      numeros[c.id] = 5;
      final anulado = vender(c, _vodkaConSpeed, 10000, 2);
      numeros.clear();
      final cuenta = CuentaDelProveedor.de([
        laNoche(
          extra: [anulado],
          anulaciones: [AnulacionBarra.de(anulado, motivo: 'se equivocó', ahora: noche)],
        ),
      ]);
      final vodka = cuenta.productos.singleWhere((p) => p.productoId == _vodkaConSpeed);
      expect(vodka.vendidas, 25);
      expect(cuenta.productos.singleWhere((p) => p.productoId == _speed).quedaron, 65);
      expect(cuenta.paraElProveedor.singleWhere((u) => u.productoId == _speed).enTragos, 25);
    });

    test('sin el precio de lista del fernet o sin lo que trae la botella, el trago no entra en lo que se debe '
        'y se avisa', () {
      final f = laNoche();
      for (final (listas, contenidos) in [
        ({...f.listas}..remove(_fernet), f.contenidos),
        (f.listas, {...f.contenidos}..remove(_fernet)),
      ]) {
        final cuenta = CuentaDelProveedor.de([
          FiestaParaLaGanancia(
            eventoId: f.eventoId,
            nombre: f.nombre,
            fecha: f.fecha,
            cajas: f.cajas,
            ventas: f.ventas,
            precios: f.precios,
            repartos: f.repartos,
            recetas: f.recetas,
            listas: listas,
            contenidos: contenidos,
          ),
        ]);
        final fyc = cuenta.productos.singleWhere((p) => p.productoId == _fernetConCoca);
        // Lo que se debe va con lo que sí se sabe (la coca: \$26.666,67); la ganancia, no.
        expect((fyc.faltaLaLista, fyc.leDebo, fyc.ganancia, fyc.lista), (true, 2666667, null, null));
        expect(cuenta.faltaLaLista.map((p) => p.productoId), contains(_fernetConCoca));
        expect(cuenta.paraElProveedor.singleWhere((u) => u.productoId == _fernet).faltaLaLista, isTrue);
        expect(cuenta.paraElProveedor.fold<int>(0, (s, u) => s + u.leDebo), cuenta.leDebo);
      }
    });

    test('dos fiestas con recetas distintas: cada una con la suya', () {
      final c1 = caja(_fiesta);
      final c2 = caja(_otra);
      FiestaParaLaGanancia fiesta(String evento, CajaBarra c, int cc) => FiestaParaLaGanancia(
            eventoId: evento,
            nombre: evento,
            fecha: DateTime(2026, 12, 4),
            cajas: [c],
            ventas: [vender(c, _fernetConCoca, 10000, 10)],
            precios: [precio(_fernetConCoca, 10000, evento: evento)],
            recetas: [ing(_fernetConCoca, _fernet, cc, UnidadDeReceta.cc, evento: evento)],
            listas: {_fernet: 750},
            contenidos: {_fernet: 750},
          );
      final cuenta = CuentaDelProveedor.de([fiesta(_fiesta, c1, 200), fiesta(_otra, c2, 250)]);
      final fernet = cuenta.paraElProveedor.single;
      expect(fernet.cc, 10 * 200 + 10 * 250);
      expect(fernet.leDebo, 10 * 200 * 100 + 10 * 250 * 100, reason: r'$1 por cc');
      expect(cuenta.productos.single.listaVaria, isTrue);
    });
  });
}
