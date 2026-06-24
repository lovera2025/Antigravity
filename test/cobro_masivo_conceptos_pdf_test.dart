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

  group('agruparConceptosMesasParaPdf', () {
    test('no agrupa con menos de 3 mesas en contrato', () {
      final conceptos = [
        {
          'concepto': 'Mesa Extra 1 (1/7)',
          'monto': 10000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 2 (1/7)',
          'monto': 10000.0,
          'esPlanLiquidacion': true,
        },
      ];
      final out = agruparConceptosMesasParaPdf(conceptos, 2);
      expect(out.length, 2);
    });

    test('agrupa 4 mesas en una línea con subtexto', () {
      final conceptos = [
        {
          'concepto': 'Cuota Base (3/9)',
          'monto': 30000.0,
          'gross': 30000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 1 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 2 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 3 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 4 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
      ];
      final out = agruparConceptosMesasParaPdf(conceptos, 7);
      expect(out.length, 2);
      expect(out[0]['concepto'], 'Cuota Base (3/9)');
      expect(out[1]['concepto'], 'Mesas Extra 1–4 (1/7) c/u');
      expect(out[1]['monto'], closeTo(40000, 0.01));
      expect(out[1]['subtexto'], 'incluye mesas 1, 2, 3, 4');
    });

    test('preserva totales al agrupar', () {
      final conceptos = [
        {
          'concepto': 'Mesa Extra 1 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 2 (1/7)',
          'monto': 15000.0,
          'gross': 15000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Mesa Extra 3 (1/7)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
      ];
      final sumAntes = conceptos.fold<double>(
        0,
        (s, c) => s + (c['monto'] as num).toDouble(),
      );
      final out = agruparConceptosMesasParaPdf(conceptos, 5);
      final sumDespues = out.fold<double>(
        0,
        (s, c) => s + (c['monto'] as num).toDouble(),
      );
      expect(sumDespues, closeTo(sumAntes, 0.01));
      expect(out.length, 1);
      expect(out.first['concepto'], 'Mesas Extra (3 seleccionadas)');
    });
  });
}
