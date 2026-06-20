import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';

void main() {
  group('totalesDescuentoPlanPdf', () {
    test('suma solo líneas del plan y calcula ahorro', () {
      final conceptos = [
        {
          'concepto': 'Abono Cuota Base (1/9)',
          'monto': 18000.0,
          'gross': 20000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Interés mora cuota 1',
          'monto': 5400.0,
          'esMora': true,
        },
      ];
      final t = totalesDescuentoPlanPdf(conceptos);
      expect(t.nominal, closeTo(20000, 0.01));
      expect(t.neto, closeTo(18000, 0.01));
      expect(t.ahorro, closeTo(2000, 0.01));
    });
  });
}
