import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';

void main() {
  group('compactarCuotasBaseParaResumenPdf', () {
    test('agrupa 9 cuotas base iguales en una línea', () {
      final conceptos = [
        for (var i = 1; i <= 9; i++)
          {
            'concepto': 'Cuota Base ($i/9)',
            'monto': 35000.0,
            'gross': 35000.0,
            'esPlanLiquidacion': true,
          },
        {
          'concepto': 'Interés mora cuota 1 (Abril)',
          'monto': 24850.0,
          'esMora': true,
        },
      ];
      final out = compactarCuotasBaseParaResumenPdf(conceptos);
      expect(out.length, 2);
      expect(out[0]['concepto'], 'Cuotas base (1–9/9)');
      expect(out[0]['monto'], closeTo(315000, 0.01));
      expect(out[0]['gross'], closeTo(315000, 0.01));
      expect(out[1]['esMora'], isTrue);
    });

    test('no agrupa entrega parcial ni montos distintos', () {
      final conceptos = [
        {
          'concepto': 'Cuota Base (1/9)',
          'monto': 35000.0,
          'gross': 35000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Entrega parcial — Cuota Base (2/9)',
          'monto': 10000.0,
          'gross': 10000.0,
          'esPlanLiquidacion': true,
        },
      ];
      final out = compactarCuotasBaseParaResumenPdf(conceptos);
      expect(out.length, 2);
      expect(out[0]['concepto'], 'Cuota Base (1/9)');
    });
  });

  group('grossPlanSeleccionadoPdf / moraSeleccionadaPdf', () {
    test('separa plan y mora', () {
      final conceptos = [
        {
          'concepto': 'Cuotas base (1–3/9)',
          'monto': 90000.0,
          'gross': 105000.0,
          'esPlanLiquidacion': true,
        },
        {
          'concepto': 'Interés mora',
          'monto': 5000.0,
          'esMora': true,
        },
      ];
      expect(grossPlanSeleccionadoPdf(conceptos), closeTo(105000, 0.01));
      expect(moraSeleccionadaPdf(conceptos), closeTo(5000, 0.01));
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
