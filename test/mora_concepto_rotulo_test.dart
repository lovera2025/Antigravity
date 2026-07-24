import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

void main() {
  group('MoraConceptoRotulo', () {
    final c3 = MoraCuotaDetalle(
      numeroCuota: 3,
      vencimiento: DateTime(2026, 6, 30),
      diasMora: 23,
      interesBruto: 6900,
      mesLabel: 'Jun 2026',
    );
    final prev2 = MoraPendientePreviaDetalle(
      numeroCuota: 2,
      mesLabel: 'May 2026',
      montoAtribuido: 6900,
      fechaPagoCuota: DateTime(2026, 6, 24),
      moraDebida: 7200,
      moraCobrada: 300,
    );

    test('solo calendario', () {
      final c = MoraConceptoRotulo.conceptoPersistido(
        detallesCalendario: [c3],
        montoPendientePrevias: 0,
        montoTotal: 6900,
      );
      expect(c, 'Interés mora cuota 3 (vto Jun 2026)');
      final pdf = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: 6900,
        moraDesglose: [
          {
            'numeroCuota': 3,
            'mesLabel': 'Jun 2026',
            'monto': 6900.0,
            'diasMora': 23,
          },
        ],
        moraPendientePrevias: 0,
      );
      expect(pdf.length, 1);
      expect(pdf.first['monto'], 6900.0);
      expect(pdf.first['subtexto'], '23 días de atraso');
    });

    test('solo pendiente previas sin detalle', () {
      final c = MoraConceptoRotulo.conceptoPersistido(
        detallesCalendario: const [],
        montoPendientePrevias: 6900,
        montoTotal: 6900,
      );
      expect(c, MoraConceptoRotulo.conceptoPendientePrevias());
      final pdf = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: 6900,
        moraDesglose: const [],
        moraPendientePrevias: 6900,
      );
      expect(pdf.length, 1);
      expect(pdf.first['concepto'], MoraConceptoRotulo.conceptoPendientePreviasGenerico);
      expect(pdf.first['subtexto'], 'No cobrada en cobros anteriores');
    });

    test('mixto Alderete Opción B: 6900+6900 cuota 2', () {
      final c = MoraConceptoRotulo.conceptoPersistido(
        detallesCalendario: [c3],
        montoPendientePrevias: 6900,
        montoTotal: 13800,
        detallePendiente: [prev2],
      );
      expect(
        c,
        'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2',
      );
      final pdf = MoraConceptoRotulo.lineasPdfDesdePreviewMora(
        montoTotal: 13800,
        moraDesglose: [
          {
            'numeroCuota': 3,
            'mesLabel': 'Jun 2026',
            'monto': 6900.0,
            'diasMora': 23,
          },
        ],
        moraPendientePrevias: 6900,
        detallePendiente: [prev2],
      );
      expect(pdf.length, 2);
      expect(pdf[0]['monto'], 6900.0);
      expect(pdf[0]['concepto'], 'Interés mora cuota 3 (vto Jun 2026)');
      expect(pdf[1]['monto'], 6900.0);
      expect(pdf[1]['concepto'], 'Mora pendiente cuota 2');
      expect(
        pdf[1]['subtexto'],
        'Al pagar el 24/06 se cobró \$300,00 de \$7.200,00',
      );
      final sum = (pdf[0]['monto'] as num) + (pdf[1]['monto'] as num);
      expect(sum, 13800);
    });
  });

  group('MoraTrackedOrigen — Alderete Brisa', () {
    test('cuota1 full + cuota2 parcial → origen cuota 2 / 6900', () {
      final contrato = ContratoAlumno(
        id: 'brisa-test',
        eventoId: 'ev',
        nombreAlumno: 'ALDERETE, BRISA GUADALUPE',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        totalCuotas: 9,
        cuotasPagadas: 2,
        saldoDeudor: 210000,
        createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
      );
      final pagos = [
        {
          'id': 'p1',
          'concepto': 'Cuota Base (1/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'fecha_pago': '2026-05-29T19:41:55.865821+00:00',
          'anulado': 0,
        },
        {
          'id': 'p2',
          'concepto': 'Interés mora cuota 1 (vto Abr 2026)',
          'monto': 8700.0,
          'monto_gross': 8700.0,
          'fecha_pago': '2026-05-29T19:41:55.915106+00:00',
          'anulado': 0,
          'line_kind': kLineKindInteresMora,
        },
        {
          'id': 'p3',
          'concepto': 'Cuota Base (2/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'fecha_pago': '2026-06-24T21:49:13.583682+00:00',
          'anulado': 0,
        },
        {
          'id': 'p4',
          'concepto': 'Interés mora (cuota base — este cobro)',
          'monto': 300.0,
          'monto_gross': 300.0,
          'fecha_pago': '2026-06-24T21:49:13.622093+00:00',
          'anulado': 0,
          'line_kind': kLineKindInteresMora,
        },
      ];

      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: 6900,
      );
      expect(origen.length, 1);
      expect(origen.first.numeroCuota, 2);
      expect(origen.first.montoAtribuido, 6900);
      expect(origen.first.moraCobrada, 300);
      expect(origen.first.moraDebida, 7200);
    });
  });

  group('conceptosFinalesDesdePreviewMasivo — mora mixto', () {
    test('no atribuye remanente a la cuota calendario', () {
      final out = conceptosFinalesDesdePreviewMasivo(
        previewConceptos: [
          {
            'concepto':
                'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2',
            'monto': 13800.0,
            'gross': 13800.0,
            'cuotas': 0,
            'lineKind': kLineKindInteresMora,
            'moraPendientePrevias': 6900.0,
            'moraDesglose': [
              {
                'numeroCuota': 3,
                'mesLabel': 'Jun 2026',
                'monto': 6900.0,
                'diasMora': 23,
              },
            ],
            'moraPendientePreviasDetalle': [
              {
                'numeroCuota': 2,
                'mesLabel': 'May 2026',
                'monto': 6900.0,
                'moraDebida': 7200.0,
                'moraCobrada': 300.0,
                'fechaPagoCuota': '2026-06-24T00:00:00.000',
              },
            ],
          },
        ],
        esLineaInteresMora: (c) => c['lineKind'] == kLineKindInteresMora,
        esLineaCargoCanal: (_) => false,
        cPagadas: 2,
        mPagadas: 0,
        sPagadas: 0,
        tCuotas: 9,
        mCuotas: 1,
        sCuotas: 1,
        cantMesas: 0,
      );
      final mora = out.where((c) => c['esMora'] == true).toList();
      expect(mora.length, 2);
      expect(mora[0]['monto'], 6900.0);
      expect(mora[1]['monto'], 6900.0);
      expect(mora[1]['concepto'], 'Mora pendiente cuota 2');
    });
  });

  group('esPagoInteresMoraPorConcepto — rótulos Opción B', () {
    test('reconoce mora pendiente cuota N', () {
      expect(
        esPagoInteresMoraPorConcepto(
          MoraConceptoRotulo.conceptoPendientePrevias(
            detalle: [
              const MoraPendientePreviaDetalle(
                numeroCuota: 2,
                mesLabel: 'May 2026',
                montoAtribuido: 6900,
              ),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        esPagoInteresMoraPorConcepto(
          'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2',
        ),
        isTrue,
      );
      expect(
        esPagoInteresMoraPorConcepto(
          'Interés mora cuota 3 (vto Jun 2026) + mora cuotas ya pagadas',
        ),
        isTrue,
      );
    });
  });
}
