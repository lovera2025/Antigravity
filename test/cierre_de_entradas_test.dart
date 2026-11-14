// El cierre de una caja de entradas (sección 5.5 del spec del 13-nov): cuántas
// se vendieron y de qué tipo, cómo se cobraron y cuánto efectivo tiene que
// haber. Puro: sin pantalla ni base.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart'
    show diferenciaEnPalabras;
import 'package:arguello_events/features/entradas/cuentas/cierre_de_entradas.dart';
import 'package:arguello_events/features/entradas/datos/entradas_repositorio.dart';

const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _familia = 'c0000000-0000-4000-8000-000000000001';

final _abre = DateTime.utc(2026, 11, 20, 15);
final _vende = DateTime.utc(2026, 11, 20, 16);
final _cierra = DateTime.utc(2026, 11, 20, 20);
final _despues = DateTime.utc(2026, 11, 21, 10);

CajaEntradas _caja({double cambio = 0, String operador = 'F1', DateTime? abre}) =>
    CajaEntradas.abrir(
      eventoId: _fiesta,
      operadorNombre: operador,
      cambioInicial: cambio,
      ahora: abre ?? _abre,
    );

/// Una venta de [sueltas] a $10.000 (con [descuento] a mano) y [deLugar] a
/// $5.000, cobrada por [medio]. En el mixto, [efectivo] es la parte en mano.
VentaEntradas _venta(
  CajaEntradas caja, {
  int sueltas = 0,
  int deLugar = 0,
  double descuento = 0,
  MedioBarra medio = MedioBarra.efectivo,
  double efectivo = 0,
  double recargo = 0,
}) {
  final renglones = [
    if (deLugar > 0)
      RenglonEntradas.lugar(
        nombre: 'Entrada de lugar adicional (50 %)',
        precioLista: 10000,
        descuentoPct: 50,
        cantidad: deLugar,
      ),
    if (sueltas > 0)
      RenglonEntradas.suelta(
        nombre: 'Entrada',
        precioLista: 10000,
        descuentoPct: descuento,
        cantidad: sueltas,
      ),
  ];
  final total = renglones.fold<double>(0, (s, r) => s + r.subtotal);
  final enMano = switch (medio) {
    MedioBarra.efectivo => total,
    MedioBarra.mixto => efectivo,
    _ => 0.0,
  };
  return VentaEntradas.nueva(
    cajaEntradasId: caja.id,
    eventoId: _fiesta,
    numero: 1,
    contratoAlumnoId: deLugar > 0 ? _familia : null,
    compradorNombre: 'COMPRADORA, UNA',
    renglones: renglones,
    medio: medio,
    efectivo: enMano,
    transferencia: total - enMano + recargo,
    recargo: recargo,
    recargoPct: recargo > 0 ? 5 : null,
    ahora: _vende,
  );
}

AnulacionEntradas _anulada(VentaEntradas v, {DateTime? cuando}) =>
    AnulacionEntradas.de(
      v,
      motivo: 'se equivocó',
      devueltas: true,
      ahora: cuando ?? _vende,
    );

void main() {
  test('cuántas de cada tipo, su plata y cómo se cobraron', () {
    final caja = _caja(cambio: 5000);
    final ventas = [
      _venta(caja, sueltas: 2), // $20.000 en efectivo
      _venta(caja, deLugar: 8), // $40.000 en efectivo
      _venta(caja,
          sueltas: 1, medio: MedioBarra.transferencia, recargo: 500), // $10.500
      _venta(caja,
          sueltas: 2, deLugar: 2, medio: MedioBarra.mixto, efectivo: 12000), // 30.000
    ];
    final c = CierreDeEntradas.de(caja, ventas, const []);

    expect(c.ventas, 4);
    expect(c.anuladas, 0);
    expect(c.sueltas, 5);
    expect(c.plataSueltas, 50000);
    expect(c.deLugar, 10);
    expect(c.plataDeLugar, 50000);
    expect(c.otras, 0);
    expect(c.entradas, 15);
    expect(c.vendido, 100000);

    expect(c.efectivo, 72000);
    expect(c.transferencia, 28500, reason: 'con el recargo adentro');
    expect(c.recargos, 500, reason: 'y el recargo aparte: no es de ninguna entrada');
    expect(c.total, 100500);
    expect(c.total, c.vendido + c.recargos);
    expect(c.mixtos, 1);
    expect(c.conTransferencia, 2);

    expect(c.efectivoEsperado, 77000, reason: 'el cambio más el efectivo');
    expect(c.diferenciaCon(77000), 0);
    expect(diferenciaEnPalabras(c.diferenciaCon(77000)), 'Justo, sin diferencia');
    expect(diferenciaEnPalabras(c.diferenciaCon(77500)), r'Sobran $ 500');
    expect(diferenciaEnPalabras(c.diferenciaCon(75500)), r'Faltan $ 1.500');
  });

  test('una venta anulada no cuenta, tampoco en el efectivo que tiene que haber', () {
    final caja = _caja(cambio: 1000);
    final queda = _venta(caja, sueltas: 2);
    final anulada = _venta(caja, sueltas: 3);
    final anuladaMixta =
        _venta(caja, sueltas: 2, medio: MedioBarra.mixto, efectivo: 5000);
    final c = CierreDeEntradas.de(
      caja,
      [queda, anulada, anuladaMixta],
      [_anulada(anulada), _anulada(anuladaMixta)],
    );

    expect(c.ventas, 1);
    expect(c.anuladas, 2);
    expect(c.sueltas, 2);
    expect(c.efectivo, 20000);
    expect(c.transferencia, 0);
    expect(c.mixtos, 0);
    expect(c.efectivoEsperado, 21000);
    // Lo anulado va aparte.
    expect(c.efectivoAnulado, 35000);
    expect(c.transferenciaAnulada, 15000);
    // Se anularon con la caja abierta: no es "después del cierre".
    expect(c.hayAnuladoDespues, isFalse);
  });

  test('los descuentos a mano van en su renglón; el 50 % de los lugares no es uno', () {
    final caja = _caja();
    final c = CierreDeEntradas.de(
      caja,
      [
        _venta(caja, sueltas: 2, descuento: 10), // deja de entrar $2.000
        _venta(caja, sueltas: 1, descuento: 100), // de cortesía: $10.000
        _venta(caja, deLugar: 8), // el 50 % sale solo: no es a mano
        _venta(caja, sueltas: 1),
      ],
      const [],
    );
    expect(c.descuentos, 12000);
    expect(c.conDescuento, 2);
    expect(c.plataSueltas, 28000);
    expect(c.plataDeLugar, 40000);
    expect(c.efectivo, 68000);
  });

  test('un descuento de una venta anulada tampoco cuenta', () {
    final caja = _caja();
    final v = _venta(caja, sueltas: 2, descuento: 10);
    final c = CierreDeEntradas.de(caja, [v], [_anulada(v)]);
    expect(c.descuentos, 0);
    expect(c.conDescuento, 0);
  });

  test('anulada después de cerrar: el cierre queda como estaba y va la línea aparte', () {
    final abierta = _caja(cambio: 2000);
    final v1 = _venta(abierta, sueltas: 2);
    final v2 = _venta(abierta, sueltas: 1, medio: MedioBarra.transferencia);
    final antes = _venta(abierta, sueltas: 1);

    // Al cerrar había $32.000 en efectivo: contó $32.000, justo.
    final alCerrar = CierreDeEntradas.de(abierta, [v1, v2, antes], const []);
    expect(alCerrar.efectivoEsperado, 32000);
    final cerrada = abierta.cerrada(
      efectivoContado: 32000,
      diferencia: alCerrar.diferenciaCon(32000),
      ahora: _cierra,
    );

    // Al otro día el jefe anula dos.
    final anulaciones = [
      _anulada(v1, cuando: _despues),
      _anulada(v2, cuando: _despues),
    ];
    final resumen = ResumenDeCajaEntradas(
      cerrada,
      CierreDeEntradas.de(cerrada, [v1, v2, antes], anulaciones),
    );

    expect(resumen.contado, 32000);
    expect(resumen.diferencia, 0,
        reason: 'la diferencia es la que se anotó al cerrar, no una cuenta de ahora');
    expect(resumen.cuentas.anuladas, 2);
    expect(resumen.cuentas.efectivoAnuladoDespues, 20000);
    expect(resumen.cuentas.transferenciaAnuladaDespues, 10000);
    expect(resumen.cuentas.anuladoDespues, 30000);
    expect(resumen.cuentas.hayAnuladoDespues, isTrue);
  });

  test('lo anulado antes de cerrar no va en "después del cierre"', () {
    final abierta = _caja();
    final antes = _venta(abierta, sueltas: 1);
    final despues = _venta(abierta, sueltas: 2);
    final cerrada =
        abierta.cerrada(efectivoContado: 20000, diferencia: 0, ahora: _cierra);
    final c = CierreDeEntradas.de(
      cerrada,
      [antes, despues],
      [
        _anulada(antes, cuando: _vende),
        _anulada(despues, cuando: _despues),
      ],
    );
    expect(c.efectivoAnulado, 30000);
    expect(c.efectivoAnuladoDespues, 20000);
  });

  test('de una caja se miran solo sus ventas; la fiesta las junta', () {
    final una = _caja(cambio: 1000, operador: 'F1');
    final otra = _caja(
      cambio: 500,
      operador: 'F2',
      abre: _abre.add(const Duration(hours: 1)),
    );
    final ventas = [
      _venta(una, sueltas: 2),
      _venta(otra, sueltas: 1),
      _venta(otra, deLugar: 4),
    ];
    final anulada = ventas[1];
    final anulaciones = [_anulada(anulada)];

    final deUna = CierreDeEntradas.de(una, ventas, anulaciones);
    expect(deUna.ventas, 1);
    expect(deUna.anuladas, 0);
    expect(deUna.efectivo, 20000);
    expect(deUna.efectivoEsperado, 21000);

    final deOtra = CierreDeEntradas.de(otra, ventas, anulaciones);
    expect(deOtra.ventas, 1);
    expect(deOtra.anuladas, 1);
    expect(deOtra.deLugar, 4);

    final fiesta = CierreDeEntradas.deLaFiesta([una, otra], ventas, anulaciones);
    expect(fiesta.ventas, 2);
    expect(fiesta.anuladas, 1);
    expect(fiesta.entradas, 6);
    expect(fiesta.vendido, 40000);
    expect(fiesta.cambioInicial, 1500);
    expect(fiesta.efectivoEsperado, 41500);

    // Una línea por caja, la que abrió primero arriba.
    final porCaja = ResumenDeCajaEntradas.porCaja([otra, una], ventas, anulaciones);
    expect([for (final r in porCaja) r.caja.operadorNombre], ['F1', 'F2']);
    expect(porCaja.first.cuentas.efectivo, 20000);
    expect(porCaja.last.cuentas.anuladas, 1);
    expect(porCaja.first.diferencia, isNull, reason: 'sigue abierta');
  });

  test('lo que no se puede leer de los renglones va a "otras", sin perder nada', () {
    final caja = _caja();
    Map<String, dynamic> fila(String id, Object? renglones) => {
          'id': id,
          'caja_entradas_id': caja.id,
          'evento_id': _fiesta,
          'numero': 1,
          'comprador_nombre': 'COMPRADORA, UNA',
          'renglones': renglones,
          'cantidad': 3,
          'total': 30000,
          'medio': 'efectivo',
          'efectivo': 30000,
          'created_at': 'x',
          'updated_at': 'x',
        };
    final c = CierreDeEntradas.de(
      caja,
      [
        // Renglones ilegibles.
        VentaEntradas.fromMap(fila('v1', 'esto no es una lista')),
        // Un tipo que esta versión no conoce, junto con uno que sí.
        VentaEntradas.fromMap(fila(
          'v2',
          '[{"tipo":"con_cena","nombre":"Con cena","precio_lista":20000,'
              '"precio":20000,"cantidad":1},'
              '{"tipo":"suelta","nombre":"Entrada","precio_lista":5000,'
              '"precio":5000,"cantidad":2}]',
        )),
        _venta(caja, sueltas: 1),
      ],
      const [],
    );
    expect(c.ventas, 3);
    expect(c.otras, 4, reason: 'las 3 ilegibles y la de un tipo nuevo');
    expect(c.plataOtras, 50000);
    expect(c.sueltas, 3);
    expect(c.plataSueltas, 20000);
    // Las entradas y la plata suman siempre lo vendido.
    expect(c.entradas, 7);
    expect(c.vendido, 70000);
    expect(c.efectivo, 70000);
  });

  test('una caja sin ventas da todo en cero y espera su cambio', () {
    final c = CierreDeEntradas.de(_caja(cambio: 3000), const [], const []);
    expect(c.ventas, 0);
    expect(c.entradas, 0);
    expect(c.total, 0);
    expect(c.efectivoEsperado, 3000);
    expect(c.diferenciaCon(3000), 0);
  });
}
