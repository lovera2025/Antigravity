import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/cierre_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Los retiros y el cambio de la encargada (v84, plan del 4-dic): entran en el efectivo
/// que tiene que haber al cerrar. Retirar resta; dar cambio suma; el ajuste del cambio
/// (se anotó mal al abrir) suma o resta. Solo se agregan filas.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';

void main() {
  final noche = DateTime.utc(2026, 12, 5, 2);
  final caja = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 1, sede: 'Barra 1', cambioInicial: 15000, ahora: noche);
  final otra = CajaBarra.abrir(eventoId: _fiesta, numeroCaja: 2, sede: 'Barra 1', ahora: noche);

  VentaBarra vender(int n, {double efectivo = 0, double transferencia = 0}) => VentaBarra.nueva(
        cajaBarraId: caja.id,
        eventoId: _fiesta,
        numero: n,
        renglones: [
          RenglonVenta(productoId: 'p1', nombre: 'Cerveza', precio: efectivo + transferencia, cantidad: 1),
        ],
        medio: transferencia > 0 ? MedioBarra.transferencia : MedioBarra.efectivo,
        efectivo: efectivo,
        transferencia: transferencia,
        ahora: noche,
      );

  MovimientoDeCaja mov(TipoMovimientoDeCaja tipo, double monto, {CajaBarra? de}) => MovimientoDeCaja.nuevo(
        eventoId: _fiesta,
        cajaBarraId: (de ?? caja).id,
        tipo: tipo,
        monto: monto,
        motivo: 'porque sí',
        hechoPor: 'Romi',
        ahora: noche,
      );

  final ventas = [vender(1, efectivo: 12000), vender(2, transferencia: 8000)];

  test('sin movimientos, lo de siempre: el cambio más el efectivo vendido', () {
    final c = CierreDeBarra.de(caja, ventas, const []);
    expect(c.efectivoEsperado, 27000);
    expect((c.cambioAgregado, c.retirado), (0, 0));
  });

  test('el retiro resta, el cambio suma y el ajuste corrige: \$27.000 − 20.000 + 5.000 − 3.000 = \$9.000', () {
    final c = CierreDeBarra.de(caja, ventas, const [], movimientos: [
      mov(TipoMovimientoDeCaja.retiro, 20000),
      mov(TipoMovimientoDeCaja.cambio, 5000),
      mov(TipoMovimientoDeCaja.ajusteCambio, -3000),
    ]);
    expect(c.retirado, 20000);
    expect(c.cambioAgregado, 2000);
    expect(c.efectivoEsperado, 9000);
    expect(c.diferenciaCon(9500), 500, reason: 'la diferencia sale del esperado con los movimientos');
    expect(c.total, 20000, reason: 'lo vendido no cambia');
  });

  test('lo de otra caja no cuenta, y el mismo movimiento llegado dos veces cuenta una', () {
    final retiro = mov(TipoMovimientoDeCaja.retiro, 10000);
    final c = CierreDeBarra.de(caja, ventas, const [], movimientos: [
      retiro,
      retiro,
      mov(TipoMovimientoDeCaja.retiro, 99999, de: otra),
    ]);
    expect(c.efectivoEsperado, 17000);
  });

  test('toda la fiesta junta suma los movimientos de todas las cajas que recibe', () {
    final f = CierreDeBarra.deLaFiesta(ventas, const [], cambioInicial: 15000, movimientos: [
      mov(TipoMovimientoDeCaja.retiro, 10000),
      mov(TipoMovimientoDeCaja.cambio, 2000, de: otra),
    ]);
    expect(f.efectivoEsperado, 15000 + 12000 - 10000 + 2000);
  });

  test('un movimiento de un tipo que esta versión no conoce no cuenta', () {
    final raro = MovimientoDeCaja.fromMap({...mov(TipoMovimientoDeCaja.retiro, 5000).toMap(), 'tipo': 'algo_nuevo'});
    expect(raro.tipo, isNull);
    expect(CierreDeBarra.de(caja, ventas, const [], movimientos: [raro]).efectivoEsperado, 27000);
  });

  test('sin monto o sin el porqué no se arma; el retiro y el cambio van en positivo', () {
    MovimientoDeCaja armar(TipoMovimientoDeCaja t, double monto, String motivo) => MovimientoDeCaja.nuevo(
          eventoId: _fiesta,
          cajaBarraId: caja.id,
          tipo: t,
          monto: monto,
          motivo: motivo,
          ahora: noche,
        );
    expect(() => armar(TipoMovimientoDeCaja.retiro, 0, 'x'), throwsArgumentError);
    expect(() => armar(TipoMovimientoDeCaja.retiro, -100, 'x'), throwsArgumentError);
    expect(() => armar(TipoMovimientoDeCaja.cambio, -100, 'x'), throwsArgumentError);
    expect(() => armar(TipoMovimientoDeCaja.retiro, 100, '   '), throwsArgumentError);
    expect(armar(TipoMovimientoDeCaja.ajusteCambio, -100, 'se anotó mal').efectoEnCentavos, -10000);
  });

  test('va y vuelve de la base igual', () {
    final m = mov(TipoMovimientoDeCaja.ajusteCambio, -3000);
    expect(MovimientoDeCaja.fromMap(m.toMap()).toMap(), m.toMap());
  });

  test(
    'toda pantalla o papel que dice el efectivo esperado pasa los movimientos',
    () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.replaceAll('\\', '/').endsWith('cuentas/cierre_de_barra.dart')) {
          continue;
        }
        final fuente = f.readAsStringSync().replaceAll('\r\n', '\n');
        for (final m in RegExp(r'CierreDeBarra\.de\(|ResumenDeCajas\.de\(').allMatches(fuente)) {
          final cuerpo = fuente.substring(m.end, (m.end + 400).clamp(0, fuente.length));
          expect(cuerpo, contains('movimientos:'), reason: f.path);
        }
      }
    },
  );
}
