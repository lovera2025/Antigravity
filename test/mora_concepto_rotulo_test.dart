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
      vencimiento: DateTime(2026, 5, 31),
      diasMora: 24,
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
      // El subtexto explica de dónde viene la mora: cuándo venció la cuota,
      // cuánto tardó en pagarse y qué quedó sin cobrar.
      expect(
        pdf[1]['subtexto'],
        'Venció el 31/05/2026 · se pagó el 24/06/2026, 24 días tarde · '
        'se cobró \$300,00 de los \$7.200,00 de mora',
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

  group('MoraTrackedOrigen — arrastre de varias cuotas (Bernel)', () {
    // Historial real: tres "Cuota Base (n/9)" de $30.000 sin una sola línea de
    // mora. Reg 30-mar-2026 → C1 vence 30/04, C2 31/05, C3 30/06.
    final contrato = ContratoAlumno(
      id: 'bernel',
      eventoId: 'ev',
      nombreAlumno: 'BERNEL, LUCILA FATIMA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      totalCuotas: 9,
      cuotasPagadas: 3,
      saldoDeudor: 180000,
      createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
    );
    final pagos = <Map<String, dynamic>>[
      {
        'id': 'p1',
        'concepto': 'Cuota Base (1/9)',
        'monto': 30000.0,
        'monto_gross': 30000.0,
        'fecha_pago': '2026-04-28T21:28:04.595192+00:00',
        'anulado': 0,
      },
      {
        'id': 'p2',
        'concepto': 'Cuota Base (2/9)',
        'monto': 30000.0,
        'monto_gross': 30000.0,
        'fecha_pago': '2026-06-23T20:22:45.683166+00:00',
        'anulado': 0,
      },
      {
        'id': 'p3',
        'concepto': 'Cuota Base (3/9)',
        'monto': 30000.0,
        'monto_gross': 30000.0,
        'fecha_pago': '2026-07-27T20:08:41.809065+00:00',
        'anulado': 0,
      },
    ];

    test('el tracked se desglosa en C2 6.900 + C3 8.100, no en una sola cuota', () {
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: 15000,
      );

      expect(origen.length, 2, reason: 'una línea por cuota arrastrada');
      expect(origen[0].numeroCuota, 2);
      expect(origen[0].montoAtribuido, closeTo(6900, 0.01));
      expect(origen[0].diasMora, 23);
      expect(origen[0].mesLabel, 'May 2026');
      expect(origen[1].numeroCuota, 3);
      expect(origen[1].montoAtribuido, closeTo(8100, 0.01));
      expect(origen[1].diasMora, 27);
      expect(origen[1].mesLabel, 'Jun 2026');

      final total = origen.fold<double>(0, (s, o) => s + o.montoAtribuido);
      expect(total, closeTo(15000, 0.01), reason: 'el desglose cubre el tracked');
    });

    test('etiqueta corta para la grilla', () {
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: 15000,
      );
      expect(origen[0].etiquetaCorta, 'C2 (May) 23d');
      expect(origen[1].etiquetaCorta, 'C3 (Jun) 27d');
    });

    test('cobrar mora remanente descuenta FIFO desde la cuota más vieja', () {
      // Paga 6.900: cancela la C2 entera y deja viva solo la C3.
      final conPagoMora = [
        ...pagos,
        {
          'id': 'p4',
          'concepto': 'Mora pendiente cuota 2 (no cobrada al pagar)',
          'monto': 6900.0,
          'monto_gross': 6900.0,
          'fecha_pago': '2026-07-28T12:00:00.000000+00:00',
          'anulado': 0,
          'line_kind': kLineKindInteresMora,
        },
      ];
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: conPagoMora,
        trackedMonto: 8100,
      );
      expect(origen.length, 1);
      expect(origen.first.numeroCuota, 3);
      expect(origen.first.montoAtribuido, closeTo(8100, 0.01));
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
