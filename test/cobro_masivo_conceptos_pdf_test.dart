import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';

void main() {
  group('compactarCuotasBaseParaPdf', () {
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
      final out = compactarCuotasBaseParaPdf(conceptos);
      expect(out.length, 2);
      expect(out[0]['concepto'], 'Cuotas base (1-2-3-4-5-6-7-8-9/9)');
      expect(out[0]['monto'], closeTo(315000, 0.01));
      expect(out[0]['gross'], closeTo(315000, 0.01));
      expect(out[1]['esMora'], isTrue);
    });

    test('no compacta 2 ni 3 cuotas consecutivas', () {
      final dos = compactarCuotasBaseParaPdf([
        for (var i = 4; i <= 5; i++)
          {
            'concepto': 'Cuota Base ($i/9)',
            'monto': 30000.0,
            'gross': 30000.0,
            'esPlanLiquidacion': true,
          },
      ]);
      expect(dos.length, 2);
      expect(dos[0]['concepto'], 'Cuota Base (4/9)');
      expect(dos[1]['concepto'], 'Cuota Base (5/9)');
    });

    test('compacta 4 o más enumerando 4-5-6-7', () {
      final out = compactarCuotasBaseParaPdf([
        for (var i = 4; i <= 7; i++)
          {
            'concepto': 'Cuota Base ($i/9)',
            'monto': 30000.0,
            'gross': 30000.0,
            'esPlanLiquidacion': true,
          },
      ]);
      expect(out.length, 1);
      expect(out.single['concepto'], 'Cuotas base (4-5-6-7/9)');
      expect(out.single['monto'], closeTo(120000, 0.01));
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
      final out = compactarCuotasBaseParaPdf(conceptos);
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

  group('cuotasConMoraCobradaPdf', () {
    test('toma numeroCuota y cuotaPrevia, deduplica y ordena', () {
      final conceptos = [
        {'concepto': 'Cuota Base (5/9)', 'monto': 35000.0},
        {'concepto': 'Interés mora cuota 3', 'monto': 900.0, 'esMora': true,
          'numeroCuota': 3},
        {'concepto': 'Mora pendiente cuota 2', 'monto': 500.0, 'esMora': true,
          'cuotaPrevia': 2},
        {'concepto': 'Interés mora cuota 3', 'monto': 100.0, 'esMora': true,
          'numeroCuota': 3},
      ];
      expect(cuotasConMoraCobradaPdf(conceptos), [2, 3]);
    });

    test('vacía si las líneas de mora no traen metadata', () {
      final conceptos = [
        {'concepto': 'Interés mora', 'monto': 900.0, 'esMora': true},
      ];
      expect(cuotasConMoraCobradaPdf(conceptos), isEmpty);
    });
  });

  group('fraseCuotasEs', () {
    test('arma la frase según la cantidad de cuotas', () {
      expect(fraseCuotasEs([]), '');
      expect(fraseCuotasEs([3]), 'cuota 3');
      expect(fraseCuotasEs([2, 3]), 'cuotas 2 y 3');
      expect(fraseCuotasEs([2, 3, 5]), 'cuotas 2, 3 y 5');
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

  group('expandirRangosCortosCuotasBase', () {
    test('parte Cuotas Base (4–5/9) en dos líneas', () {
      final out = expandirRangosCortosCuotasBase([
        {
          'concepto': 'Cuotas Base (4–5/9)',
          'monto': 60000.0,
          'gross': 60000.0,
          'esPlanLiquidacion': true,
        },
      ]);
      expect(out.length, 2);
      expect(out[0]['concepto'], 'Cuota Base (4/9)');
      expect(out[1]['concepto'], 'Cuota Base (5/9)');
      expect(out[0]['monto'], closeTo(30000, 0.01));
      expect(out[1]['monto'], closeTo(30000, 0.01));
    });
  });

  group('display mora y detalle cobrada', () {
    test('interés mora cuota N no cae al genérico', () {
      final line = <String, dynamic>{
        'concepto': 'Interés mora cuota 4 (vto Jul 2026)',
        'monto': 4200.0,
        'esMora': true,
      };
      anexarMetadatosMoraDisplay(line);
      expect(line['numeroCuota'], 4);
      final display = lineasDisplayParaPdf([line]);
      expect(display.single['display'], 'Mora de la cuota 4');
    });

    test('remanente nombra no cobrada al pagar', () {
      final line = <String, dynamic>{
        'concepto': 'Mora pendiente cuota 3 (no cobrada al pagar)',
        'monto': 3150.0,
        'esMora': true,
      };
      anexarMetadatosMoraDisplay(line);
      expect(line['cuotaPrevia'], 3);
      final display = lineasDisplayParaPdf([line]);
      expect(
        display.single['display'],
        'Mora no cobrada al pagar la cuota 3',
      );
    });

    test('el recuadro verde distingue vencida vs remanente', () {
      expect(
        detalleMoraCobradaRecibo([
          {'esMora': true, 'numeroCuota': 4, 'monto': 4200.0},
        ]),
        'de la cuota 4 (vencida)',
      );
      expect(
        detalleMoraCobradaRecibo([
          {'esMora': true, 'cuotaPrevia': 3, 'monto': 3150.0},
        ]),
        'de la cuota 3 (no cobrada al pagar)',
      );
    });
  });
}
