import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';

void main() {
  group('esPagoInteresMoraPorConcepto', () {
    test('reconoce interés mora estándar del modal', () {
      expect(
        esPagoInteresMoraPorConcepto(
          'Interés mora (cuota base — este cobro)',
        ),
        isTrue,
      );
    });

    test('reconoce Mora remanente (solo tracked, sin desglose calendario)', () {
      expect(esPagoInteresMoraPorConcepto('Mora remanente'), isTrue);
    });

    test('no confunde cuota base con mora', () {
      expect(esPagoInteresMoraPorConcepto('Cuota Base (2/9)'), isFalse);
    });
  });

  group('recalcularSaldoDesdePagos — Mora remanente', () {
    test('mora remanente no reduce saldo del plan', () {
      final pagos = [
        {
          'anulado': 0,
          'concepto': 'Cuota Base (1/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
        },
        {
          'anulado': 0,
          'concepto': 'Cuota Base (2/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
        },
        {
          'anulado': 0,
          'concepto': 'Mora remanente',
          'monto': 9000.0,
          'monto_gross': 9000.0,
        },
      ];
      final r = recalcularSaldoDesdePagos(
        montoTotalPactado: 270000,
        totalCuotas: 9,
        mesaExtraPrecio: 0,
        sillasExtraPrecioTotal: 0,
        precioUnitarioMesaExtra: 0,
        mesaExtraCuotas: 0,
        mesaExtraCantidad: 0,
        sillasExtraCuotas: 0,
        pagos: pagos,
      );
      expect(r.grossBase, closeTo(60000, 0.01));
      expect(r.saldoDeudor, closeTo(210000, 0.01));
    });
  });
}
