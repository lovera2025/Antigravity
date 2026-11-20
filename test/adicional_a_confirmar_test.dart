// La mesa adicional "a confirmar" (pedido del jefe, 16-nov-2026): la que no
// está paga entera. Sale de los pagos, nunca de los campos del contrato.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/adicional_a_confirmar.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

ContratoAlumno _familia({
  int extras = 1,
  List<int> mesas = const [],
  double mesaExtraPagado = 0,
}) =>
    ContratoAlumno(
      id: 'f1',
      eventoId: 'e',
      nombreAlumno: 'GARCIA, LUCAS',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 0,
      mesaExtraPrecio: 70000.0 * extras,
      mesaExtraCantidad: extras,
      mesaExtraPagado: mesaExtraPagado,
      numeroMesa:
          mesas.isEmpty ? null : MesasExtraUtils.formatearAsignacionMesas(mesas),
    );

Map<String, dynamic> _pago(double monto,
        {String concepto = 'Mesa extra (1/1)', int anulado = 0}) =>
    {
      'concepto': concepto,
      'monto': monto,
      'monto_gross': monto,
      'anulado': anulado,
    };

void main() {
  test('paga entera: nada a confirmar', () {
    final a = _familia(mesas: [12, 13]);
    expect(AdicionalesDeLaFamilia.aConfirmar(a, [_pago(70000)]), isEmpty);
  });

  test('sin nada pagado: su mesa está a confirmar y se puede anular', () {
    final a = _familia(mesas: [12, 13]);
    final r = AdicionalesDeLaFamilia.aConfirmar(a, [
      _pago(270000, concepto: 'Cuota Base'),
    ]);
    expect(r, hasLength(1));
    expect(r.single.mesa, 13);
    expect(r.single.aPagar, 70000);
    expect(r.single.sePuedeAnular, isTrue);
    expect(AdicionalesDeLaFamilia.mesas(a, const []), {13});
  });

  test('pagada en parte: a confirmar, y esa noche no se anula', () {
    final a = _familia(mesas: [12, 13]);
    final r = AdicionalesDeLaFamilia.aConfirmar(a, [_pago(30000)]);
    expect(r.single.mesa, 13);
    expect(r.single.pagado, 30000);
    expect(r.single.aPagar, 40000);
    expect(r.single.sePuedeAnular, isFalse);
  });

  test('perdonada (un pago con descuento del 100 %): cuenta como paga', () {
    final a = _familia(mesas: [12, 13]);
    final perdonado = {
      ..._pago(0),
      'monto_gross': 70000.0,
    };
    expect(AdicionalesDeLaFamilia.aConfirmar(a, [perdonado]), isEmpty);
  });

  test('un pago anulado, la mora y el costo por transferencia no la pagan',
      () {
    final a = _familia(mesas: [12, 13]);
    final r = AdicionalesDeLaFamilia.aConfirmar(a, [
      _pago(70000, anulado: 1),
      _pago(5000, concepto: 'Interés por mora (Mesa extra)'),
    ]);
    expect(r.single.mesa, 13);
  });

  test('no se mira el campo del contrato: aunque diga pagada, sin pagos está '
      'a confirmar', () {
    final a = _familia(mesas: [12, 13], mesaExtraPagado: 70000);
    expect(AdicionalesDeLaFamilia.mesas(a, const []), {13});
  });

  test('sin los pagos (todavía no se leyeron) no marca nada', () {
    final a = _familia(mesas: [12, 13]);
    expect(AdicionalesDeLaFamilia.aConfirmar(a, null), isEmpty);
  });

  test('no salió en el sorteo: a confirmar sin mesa', () {
    final a = _familia(mesas: [12]);
    final r = AdicionalesDeLaFamilia.aConfirmar(a, const []);
    expect(r.single.mesa, isNull);
    expect(AdicionalesDeLaFamilia.sinMesa(a, const []), 1);
    expect(AdicionalesDeLaFamilia.mesas(a, const []), isEmpty);
  });

  test('sin mesa todavía (antes del sorteo): nada que confirmar en la puerta',
      () {
    expect(AdicionalesDeLaFamilia.aConfirmar(_familia(), const []), isEmpty);
  });

  test('dos adicionales y una paga: queda a confirmar la segunda', () {
    final a = _familia(extras: 2, mesas: [12, 13, 14]);
    final r = AdicionalesDeLaFamilia.aConfirmar(a, [_pago(70000)]);
    expect(r, hasLength(1));
    expect(r.single.n, 2);
    expect(r.single.mesa, 14);
    expect(r.single.sePuedeAnular, isTrue);
  });

  test('cuando paga, vuelve sola a la normalidad', () {
    final a = _familia(mesas: [12, 13]);
    final pagos = [_pago(30000)];
    expect(AdicionalesDeLaFamilia.mesas(a, pagos), {13});
    pagos.add(_pago(40000));
    expect(AdicionalesDeLaFamilia.mesas(a, pagos), isEmpty);
  });

  test('una familia sin adicional nunca tiene nada a confirmar', () {
    final a = _familia(extras: 0, mesas: [12]);
    expect(AdicionalesDeLaFamilia.aConfirmar(a, const []), isEmpty);
  });

  // Revisión del 20-nov-2026: con "Las mesas adicionales: Al final" y ninguna
  // pegada (6.6.1), la principal queda sola adelante y las adicionales juntas
  // al fondo. El orden salía del tramo más largo (67-68) y la principal (la 12)
  // pasaba a ser la adicional que faltaba pagar.
  group('la mesa del contrato es la de número más bajo', () {
    test('la 12 principal y la 67-68 adicionales: la que falta pagar es la 68, '
        'nunca la 12', () {
      final a = _familia(extras: 2, mesas: [12, 67, 68]);
      final r = AdicionalesDeLaFamilia.aConfirmar(a, [_pago(70000)]);
      expect(r.single.n, 2);
      expect(r.single.mesa, 68);
      expect(AdicionalesDeLaFamilia.mesas(a, [_pago(70000)]), {68});
    });

    test('sin nada de las mesas pago: la 67 y la 68, y la 12 nunca', () {
      final a = _familia(extras: 2, mesas: [12, 67, 68]);
      expect(AdicionalesDeLaFamilia.mesas(a, const []), {67, 68});
    });

    test('con una pegada a la principal (12-13) y la otra al fondo (67): la '
        'adicional 2 es la 67', () {
      final a = _familia(extras: 2, mesas: [12, 13, 67]);
      final r = AdicionalesDeLaFamilia.aConfirmar(a, [_pago(70000)]);
      expect(r.single.mesa, 67);
    });

    test('las mesas nuevas al fondo de quien llegó después del sorteo', () {
      // Tenía la 12; agregó dos mesas y el programa le dio la 90 y la 91.
      final a = _familia(extras: 2, mesas: [12, 90, 91]);
      expect(AdicionalesDeLaFamilia.mesas(a, const []), {90, 91});
    });
  });
}
