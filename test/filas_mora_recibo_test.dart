// Las filas de mora del recibo tienen que sumar el número que grita el título.
//
// Es la regla que se rompió en la 4.9: `detalleMoraCobradaRecibo` descartaba las
// líneas sin número de cuota, y el recibo Nº FF677977 rotuló $25.000 como "de la
// cuota 1" cuando de ahí salían $5.600 y los otros $19.400 no decían de dónde
// eran. Un desglose que no cierra con su propio total es peor que no tenerlo.
import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/common/services/ajuste_pdf.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';

double _suma(List<FilaMoraPdf> filas) =>
    filas.fold<double>(0, (s, f) => s + f.monto);

/// Las líneas del recibo Nº FF677977: $5.600 de la cuota 1 vencida y $19.400 de
/// arrastre sin cuota reconstruible.
List<Map<String, dynamic>> _lineasVareiro() => [
  {
    'concepto': 'Cuotas base (2-3-4/9)',
    'monto': 120000.0,
    'esMora': false,
  },
  {
    'concepto': 'Mora pendiente cuota 1',
    'monto': 5600.0,
    'esMora': true,
    'cuotaPrevia': 1,
    'mesCuotaPrevia': 'Abr 2026',
    'diasMora': 14,
  },
  {
    'concepto': 'Mora pendiente (cuotas ya pagadas)',
    'monto': 19400.0,
    'esMora': true,
    'arrastreGenerico': true,
  },
];

void main() {
  group('filasMoraCobradaPdf', () {
    test('las filas suman exactamente la mora seleccionada', () {
      final lineas = _lineasVareiro();
      final filas = filasMoraCobradaPdf(lineas);

      expect(_suma(filas), closeTo(moraSeleccionadaPdf(lineas), 0.01));
      expect(_suma(filas), closeTo(25000, 0.01));
    });

    test('la línea sin cuota reconstruible no se pierde: va a la bolsa', () {
      final filas = filasMoraCobradaPdf(_lineasVareiro());

      final bolsa = filas.where(
        (f) => f.rotulo == rotuloMoraOtrasCuotasPdf,
      );
      expect(bolsa, hasLength(1));
      expect(
        bolsa.first.monto,
        closeTo(19400, 0.01),
        reason: 'los \$19.400 tienen que decir que son de cuotas ya pagadas',
      );
    });

    test('a la cuota 1 se le atribuye lo suyo, no el total del recuadro', () {
      final filas = filasMoraCobradaPdf(_lineasVareiro());

      final cuota1 = filas.firstWhere((f) => f.rotulo.startsWith('Cuota 1'));
      expect(cuota1.rotulo, 'Cuota 1 (Abr, 14 d)');
      expect(
        cuota1.monto,
        closeTo(5600, 0.01),
        reason: 'el bug de la 4.9 le colgaba los \$25.000 enteros',
      );
    });

    test('agrupa varias líneas de la misma cuota en un solo renglón', () {
      final filas = filasMoraCobradaPdf([
        {
          'concepto': 'Interés mora cuota 3',
          'monto': 1200.0,
          'esMora': true,
          'numeroCuota': 3,
          'diasMora': 27,
        },
        {
          'concepto': 'Interés mora cuota 3 (parcial)',
          'monto': 800.0,
          'esMora': true,
          'numeroCuota': 3,
          'diasMora': 27,
        },
      ]);

      expect(filas, hasLength(1));
      expect(filas.first.monto, closeTo(2000, 0.01));
    });

    test('la mora del calendario y la de arrastre no se mezclan', () {
      // La cuota 2 se está pagando ahora (calendario) y además arrastra mora de
      // cuando se liquidó: son dos deudas distintas de la misma cuota.
      final filas = filasMoraCobradaPdf([
        {
          'concepto': 'Interés mora cuota 2',
          'monto': 1000.0,
          'esMora': true,
          'numeroCuota': 2,
        },
        {
          'concepto': 'Mora pendiente cuota 2',
          'monto': 3000.0,
          'esMora': true,
          'cuotaPrevia': 2,
          'mesCuotaPrevia': 'May 2026',
        },
      ]);

      expect(filas, hasLength(2));
      expect(_suma(filas), closeTo(4000, 0.01));
    });

    test('las bolsas van al final, después de toda cuota nombrada', () {
      final filas = filasMoraCobradaPdf([
        {
          'concepto': 'Mora pendiente (cuotas ya pagadas)',
          'monto': 19400.0,
          'esMora': true,
          'arrastreGenerico': true,
        },
        {
          'concepto': 'Mora pendiente cuota 7',
          'monto': 500.0,
          'esMora': true,
          'cuotaPrevia': 7,
          'mesCuotaPrevia': 'Oct 2026',
        },
      ]);

      expect(filas.first.rotulo, startsWith('Cuota 7'));
      expect(filas.last.rotulo, rotuloMoraOtrasCuotasPdf);
    });

    test('sin líneas de mora no hay filas', () {
      expect(
        filasMoraCobradaPdf([
          {'concepto': 'Cuota Base (1/9)', 'monto': 40000.0, 'esMora': false},
        ]),
        isEmpty,
      );
    });
  });

  group('recortarFilasMoraPdf', () {
    final seis = [
      for (var i = 1; i <= 6; i++)
        FilaMoraPdf(rotulo: 'Cuota $i', monto: i * 1000.0),
    ];
    // 1000 + 2000 + … + 6000
    const totalSeis = 21000.0;

    test('el total se conserva en todos los niveles de la escalera', () {
      for (final a in AjustePdf.escalera) {
        final filas = recortarFilasMoraPdf(seis, a.maxFilasMora);
        expect(
          _suma(filas),
          closeTo(totalSeis, 0.01),
          reason: 'el nivel ${a.nivel} perdió plata al recortar',
        );
      }
    });

    test('nunca deja el recuadro mudo, ni en el escalón más agresivo', () {
      for (final a in AjustePdf.escalera) {
        expect(
          recortarFilasMoraPdf(seis, a.maxFilasMora),
          isNotEmpty,
          reason: 'el nivel ${a.nivel} se comió el detalle entero',
        );
        expect(a.maxFilasMora, greaterThanOrEqualTo(1));
      }
    });

    test('respeta el tope y agrupa el resto nombrando cuántas son', () {
      final filas = recortarFilasMoraPdf(seis, 3);

      expect(filas, hasLength(3));
      expect(filas.last.rotulo, 'y 4 cuotas más');
      expect(filas.last.monto, closeTo(3000 + 4000 + 5000 + 6000, 0.01));
    });

    test('con tope 1 queda un solo renglón que carga todo', () {
      final filas = recortarFilasMoraPdf(seis, 1);

      expect(filas, hasLength(1));
      expect(filas.first.monto, closeTo(totalSeis, 0.01));
    });

    test('si entran todas no toca nada', () {
      expect(recortarFilasMoraPdf(seis, 6), same(seis));
      expect(recortarFilasMoraPdf(seis, 10), same(seis));
    });
  });
}
