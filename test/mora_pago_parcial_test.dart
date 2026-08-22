import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';

/// Pago parcial de mora: las líneas del papel tienen que sumar lo que se cobra,
/// no la mora completa.
///
/// El caso que originó esto: mora total $45.000, la familia entrega $15.000, y
/// tanto el desglose del modal como el PDF listaban los $45.000.
void main() {
  MoraCuotaDetalle cuota(int n, double interes, {String mes = 'May 2026'}) =>
      MoraCuotaDetalle(
        numeroCuota: n,
        vencimiento: DateTime(2026, 5, 31),
        diasMora: 30,
        interesBruto: interes,
        mesLabel: mes,
      );

  MoraPendientePreviaDetalle arrastre(int n, double monto) =>
      MoraPendientePreviaDetalle(
        numeroCuota: n,
        mesLabel: 'Abr 2026',
        montoAtribuido: monto,
        moraDebida: monto,
        diasMora: 20,
        vencimiento: DateTime(2026, 4, 30),
      );

  double sumar(List<Map<String, dynamic>> lineas) => double.parse(
    lineas
        .fold<double>(0, (s, l) => s + (l['monto'] as num).toDouble())
        .toStringAsFixed(2),
  );

  group('repartirMoraParcial', () {
    test('mora \$45.000 con entrega de \$15.000 reparte solo lo cobrado', () {
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 15000,
        calendario: [cuota(3, 20000), cuota(4, 25000, mes: 'Jun 2026')],
        pendientePrevias: 0,
        detallePendiente: const [],
      );

      // La cuota más vieja se cubre primero, con lo que alcanza.
      expect(r.calendario.length, 1);
      expect(r.calendario.first.numeroCuota, 3);
      expect(r.calendario.first.interesBruto, 15000);
      expect(r.pendientePrevias, 0);
    });

    test('no toca nada cuando se cobra la mora completa', () {
      final calendario = [cuota(3, 20000), cuota(4, 25000)];
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 45000,
        calendario: calendario,
        pendientePrevias: 0,
        detallePendiente: const [],
      );
      expect(identical(r.calendario, calendario), isTrue);
    });

    test('si el pago entra entero en el arrastre, va todo al arrastre', () {
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 3000,
        calendario: [cuota(5, 20000)],
        pendientePrevias: 10000,
        detallePendiente: [arrastre(2, 6000), arrastre(3, 4000)],
      );
      expect(r.calendario, isEmpty);
      expect(r.pendientePrevias, 3000);
      expect(r.detallePendiente.length, 1);
      expect(r.detallePendiente.first.numeroCuota, 2);
      expect(r.detallePendiente.first.montoAtribuido, 3000);
    });

    test('si supera el arrastre, lo salda entero y el resto va al calendario', () {
      // El arrastre es de cuotas ya liquidadas y el calendario de cuotas
      // todavía impagas: el arrastre es siempre el bucket más viejo, así que se
      // consume entero antes de tocar el calendario.
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 8000,
        calendario: [cuota(5, 6000)],
        pendientePrevias: 4000,
        detallePendiente: [arrastre(2, 4000)],
      );
      expect(r.pendientePrevias, 4000, reason: 'el arrastre se salda entero');
      expect(r.detallePendiente.single.montoAtribuido, 4000);
      expect(
        r.calendario.single.interesBruto,
        4000,
        reason: 'al calendario le llega solo lo que sobró',
      );
    });

    test('un peso de más no da vuelta la imputación', () {
      // Antes la regla era "si entra justo en el arrastre va todo ahí, si no
      // va todo al calendario": cobrar \$4.000 imputaba al arrastre y cobrar
      // \$4.001 imputaba al calendario, sin nada que lo explicara en el papel.
      List<double> reparto(double monto) {
        final r = MoraConceptoRotulo.repartirMoraParcial(
          montoTotal: monto,
          calendario: [cuota(5, 6000)],
          pendientePrevias: 4000,
          detallePendiente: [arrastre(2, 4000)],
        );
        return [
          r.pendientePrevias,
          r.calendario.fold<double>(0, (s, d) => s + d.interesBruto),
        ];
      }

      expect(reparto(4000), [4000, 0]);
      expect(reparto(4001), [4000, 1]);
    });

    test('VAREIRO: \$25.000 sobre arrastre \$19.400 y calendario vivo', () {
      // Recibo Nº FF677977. El arrastre entero primero; al calendario le llega
      // el resto, y la cuota más vieja del calendario queda parcial.
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 25000,
        calendario: [cuota(5, 15000), cuota(6, 12800, mes: 'Jun 2026')],
        pendientePrevias: 19400,
        detallePendiente: [arrastre(1, 19400)],
      );
      expect(r.pendientePrevias, 19400);
      expect(r.detallePendiente.single.numeroCuota, 1);
      expect(r.calendario.single.numeroCuota, 5);
      expect(r.calendario.single.interesBruto, 5600);
    });

    test('conserva moraDebida para que el recibo no mienta lo adeudado', () {
      final r = MoraConceptoRotulo.repartirMoraParcial(
        montoTotal: 1000,
        calendario: const [],
        pendientePrevias: 6000,
        detallePendiente: [arrastre(2, 6000)],
      );
      final d = r.detallePendiente.single;
      expect(d.montoAtribuido, 1000, reason: 'se cobra el parcial');
      expect(d.moraDebida, 6000, reason: 'pero se debía el total');
      expect(d.diasMora, 20);
    });
  });

  group('líneas emitidas', () {
    test('las líneas suman lo cobrado, no la mora total', () {
      final lineas = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: 15000,
        moraDesglose: [
          {
            'numeroCuota': 3,
            'mesLabel': 'May 2026',
            'monto': 20000,
            'diasMora': 30,
          },
          {
            'numeroCuota': 4,
            'mesLabel': 'Jun 2026',
            'monto': 25000,
            'diasMora': 15,
          },
        ],
        moraPendientePrevias: 0,
      );
      expect(sumar(lineas), 15000);
      expect(lineas.length, 1);
      expect(lineas.single['concepto'], contains('(parcial)'));
    });

    test('mora completa emite exactamente lo de siempre, sin "(parcial)"', () {
      final desglose = [
        {
          'numeroCuota': 3,
          'mesLabel': 'May 2026',
          'monto': 20000,
          'diasMora': 30,
        },
        {
          'numeroCuota': 4,
          'mesLabel': 'Jun 2026',
          'monto': 25000,
          'diasMora': 15,
        },
      ];
      final lineas = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: 45000,
        moraDesglose: desglose,
        moraPendientePrevias: 0,
      );
      expect(sumar(lineas), 45000);
      expect(lineas.length, 2);
      for (final l in lineas) {
        expect(l['concepto'], isNot(contains('(parcial)')));
      }
    });

    test('el preview del modal y sus líneas cuadran con el parcial', () {
      final preview = MoraConceptoRotulo.construirPreviewMora(
        montoTotal: 15000,
        detallesCalendario: [cuota(3, 20000), cuota(4, 25000)],
        montoPendientePrevias: 0,
        lineKind: kLineKindInteresMora,
      );
      expect((preview['monto'] as num).toDouble(), 15000);

      final filas = MoraConceptoRotulo.filasPreviewDesdeMora(preview);
      expect(
        sumar(filas),
        15000,
        reason: 'el desglose del modal no puede sumar más que el cobro',
      );
    });

    test('el rótulo guardado nombra solo la cuota realmente cubierta', () {
      final preview = MoraConceptoRotulo.construirPreviewMora(
        montoTotal: 15000,
        detallesCalendario: [cuota(3, 20000), cuota(4, 25000)],
        montoPendientePrevias: 0,
        lineKind: kLineKindInteresMora,
      );
      final concepto = preview['concepto'] as String;
      expect(concepto, contains('3'));
      expect(
        concepto,
        isNot(contains('cuotas 3, 4')),
        reason: 'la cuota 4 no se cobró en este pago',
      );
    });

    test('el detector de líneas de mora sigue reconociendo el concepto', () {
      final preview = MoraConceptoRotulo.construirPreviewMora(
        montoTotal: 15000,
        detallesCalendario: [cuota(3, 20000)],
        montoPendientePrevias: 0,
        lineKind: kLineKindInteresMora,
      );
      expect(
        esPagoInteresMoraPorConcepto(preview['concepto'] as String),
        isTrue,
      );

      for (final l in MoraConceptoRotulo.filasPreviewDesdeMora(preview)) {
        expect(
          esPagoInteresMoraPorConcepto(l['concepto'] as String),
          isTrue,
          reason: 'el sufijo (parcial) no debe romper la detección',
        );
      }
    });
  });
}
