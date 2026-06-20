import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';

void main() {
  group('evaluarAvanceCuotaConAbonos', () {
    test('abono parcial sin cerrar cuota', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 5000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 0);
      expect(r.esAbonoSolo, isTrue);
    });

    test('segundo abono cierra cuota (20k + 10k = 30k)', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 10000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraCuotaExacta, isTrue);
      expect(r.cuotasCompletasDespues, 1);
    });

    test('pago completo de una cuota sin historial', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 0,
        grossActual: 30000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraCuotaExacta, isTrue);
    });

    test('cierra cuota y deja adelanto hacia la siguiente', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 15000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraConAdelanto, isTrue);
      expect(r.restoAbono, closeTo(5000, 0.01));
    });

    test('dos cuotas nuevas en un solo cobro con acumulado', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 25000,
        grossActual: 35000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 2);
      expect(r.cierraCuotaExacta, isTrue);
      expect(r.cuotasCompletasDespues, 2);
    });

    test('regresión: 2 cuotas ya pagadas + 20k parcial = solo abono', () {
      const cuotaPura = 210000 / 9; // ~23333.33
      const historico2Cuotas = cuotaPura * 2;

      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: historico2Cuotas,
        grossActual: 20000,
        cuotaPura: cuotaPura,
      );

      expect(r.cuotasLiquidadas, 0);
      expect(r.esAbonoSolo, isTrue);
      expect(r.cuotasCompletasDespues, 2);
    });
  });

  group('grossHistoricoClaseCobro', () {
    test('excluye mora, cargo canal y anulados', () {
      final pagos = [
        {
          'anulado': 0,
          'concepto': 'Abono a Cuota Base (1/9)',
          'monto': 20000,
          'monto_gross': 20000,
        },
        {
          'anulado': 1,
          'concepto': 'Cuota Base',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'line_kind': 'interes_mora',
          'concepto': 'Interés mora (cuota base — este cobro)',
          'monto': 500,
          'monto_gross': 500,
        },
        {
          'anulado': 0,
          'line_kind': 'cargo_canal_ref',
          'concepto': 'Cargo canal',
          'monto': 100,
          'monto_gross': 0,
        },
        {
          'anulado': 0,
          'concepto': 'Mesa Extra (1/3)',
          'monto': 5000,
          'monto_gross': 5000,
        },
      ];

      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.base),
        20000,
      );
      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
        5000,
      );
      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
        0,
      );
    });
  });

  group('rotularDesgloseConAbonosAcumulados', () {
    String detalle(String raw, int offset) => 'Cuota Base (${offset}/9)';

    test('abono cuando no alcanza', () {
      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 20000,
        cuotaPura: 30000,
        grossHistoricoClase: 0,
        getConceptoDetallado: detalle,
        cuotasPagadasActuales: 0,
      );
      expect(r.cuotas, 0);
      expect(r.concepto, contains('Abono'));
    });

    test('cuota pagada al cerrar con abonos previos', () {
      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 10000,
        cuotaPura: 30000,
        grossHistoricoClase: 20000,
        getConceptoDetallado: detalle,
        cuotasPagadasActuales: 0,
      );
      expect(r.cuotas, 1);
      expect(r.concepto, 'Cuota Base (1/9)');
      expect(r.concepto, isNot(contains('Abono')));
    });

    test('regresión Arguello: 2 cuotas pagadas + 20k = abono hacia cuota 3', () {
      const cuotaPura = 210000 / 9;
      const historico2Cuotas = cuotaPura * 2;

      String detalleArguello(String raw, int offset) =>
          'Cuota Base (${2 + offset}/9)';

      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 20000,
        cuotaPura: cuotaPura,
        grossHistoricoClase: historico2Cuotas,
        getConceptoDetallado: detalleArguello,
        cuotasPagadasActuales: 2,
      );

      expect(r.cuotas, 0);
      expect(r.concepto, 'Abono a Cuota Base (3/9)');
      expect(r.concepto, isNot(contains('2 Cuotas')));
    });
  });
}
