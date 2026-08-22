import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

void main() {
  group('origenMoraPendienteLinea', () {
    String plata(double v) => '\$${v.toStringAsFixed(0)}';

    MoraCuotaDetalle det(int n, String mes, int dias, double interes) =>
        MoraCuotaDetalle(
          numeroCuota: n,
          vencimiento: DateTime(2026, 6, 30),
          diasMora: dias,
          interesBruto: interes,
          mesLabel: mes,
        );

    test('nombra las cuotas con mes, días y monto', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: [det(2, 'May 2026', 45, 3200), det(3, 'Jun 2026', 15, 1100)],
        formatoMonto: plata,
      );
      expect(
        linea,
        'Mora de cuotas vencidas: cuota 2 (May, 45 d) \$3200 · cuota 3 (Jun, 15 d) \$1100.',
      );
    });

    test('corta en maxCuotas para que entre en la hoja', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: [
          det(2, 'May 2026', 45, 3200),
          det(3, 'Jun 2026', 15, 1100),
          det(4, 'Jul 2026', 10, 800),
          det(5, 'Ago 2026', 5, 400),
          det(6, 'Sep 2026', 2, 200),
        ],
        formatoMonto: plata,
        maxCuotas: 3,
      );
      expect(linea, contains('y 2 cuotas más'));
      expect(linea, isNot(contains('cuota 5')));
    });

    test('suma el remanente de cuotas ya pagadas', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: [det(3, 'Jun 2026', 15, 1100)],
        tracked: 2400,
        formatoMonto: plata,
      );
      expect(linea, contains('Mora no cobrada al pagar (cuotas ya pagadas \$2400)'));
    });

    test('solo tracked sin origen reconstruido: se lee bien', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: const [],
        tracked: 2400,
        formatoMonto: plata,
      );
      expect(linea, 'Mora no cobrada al pagar (cuotas ya pagadas \$2400).');
    });

    test('tracked con origen reconstruido nombra las cuotas', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: const [],
        tracked: 15000,
        trackedDetalle: [
          MoraPendientePreviaDetalle(
            numeroCuota: 2,
            mesLabel: 'May 2026',
            montoAtribuido: 6900,
            diasMora: 24,
          ),
          MoraPendientePreviaDetalle(
            numeroCuota: 3,
            mesLabel: 'Jun 2026',
            montoAtribuido: 8100,
            diasMora: 27,
          ),
        ],
        formatoMonto: plata,
      );
      expect(
        linea,
        'Mora no cobrada al pagar: cuota 2 (May, 24 d) \$6900 · cuota 3 (Jun, 27 d) \$8100.',
      );
    });

    test('separa vencidas y remanente, cada bloque ordenado', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: [det(2, 'May 2026', 61, 21350), det(3, 'Jun 2026', 31, 10850)],
        tracked: 1400,
        trackedDetalle: [
          MoraPendientePreviaDetalle(
            numeroCuota: 1,
            mesLabel: 'Abr 2026',
            montoAtribuido: 1400,
            diasMora: 4,
          ),
        ],
        formatoMonto: plata,
      );
      expect(
        linea,
        'Mora de cuotas vencidas: cuota 2 (May, 61 d) \$21350 · '
        'cuota 3 (Jun, 31 d) \$10850. '
        'Mora no cobrada al pagar: cuota 1 (Abr, 4 d) \$1400.',
      );
    });

    test('desglose + tracked recortan cada bloque por separado', () {
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: [det(4, 'Jul 2026', 10, 800), det(5, 'Ago 2026', 5, 400)],
        tracked: 15000,
        trackedDetalle: [
          MoraPendientePreviaDetalle(
            numeroCuota: 2,
            mesLabel: 'May 2026',
            montoAtribuido: 6900,
            diasMora: 24,
          ),
          MoraPendientePreviaDetalle(
            numeroCuota: 3,
            mesLabel: 'Jun 2026',
            montoAtribuido: 8100,
            diasMora: 27,
          ),
        ],
        formatoMonto: plata,
        maxCuotas: 3,
      );
      expect(linea, startsWith('Mora de cuotas vencidas:'));
      expect(linea, contains('Mora no cobrada al pagar:'));
      expect(linea, contains('cuota 2'));
      expect(linea, contains('cuota 3'));
      expect(linea, contains('cuota 4'));
      expect(linea, contains('cuota 5'));
      expect(linea, isNot(contains('y 1 cuota más')));
    });

    test('vacía si no hay nada que informar', () {
      expect(
        MoraConceptoRotulo.origenMoraPendienteLinea(
          desglose: const [],
          formatoMonto: plata,
        ),
        '',
      );
    });
  });

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
      // Los días viajan como dato; el rótulo del PDF los imprime una sola vez
      // ("Mora — 23 días fuera de término"), sin subtexto que los repita.
      expect(pdf.first['diasMora'], 23);
      expect(pdf.first['subtexto'], isNull);
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
      // El rótulo ya dice "no cobrada en su momento": sin subtexto duplicado.
      expect(pdf.first['subtexto'], isNull);
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

    test('una exención de hoy no borra el origen del pasado', () {
      // La exención es una decisión de ahora ("no le cobres mora hasta fin de
      // mes"). Aplicada al replay del historial dejaba el desglose de junio en
      // cero y el tracked sin cuota que explicarlo: el recibo terminaba
      // diciendo "de cuotas ya pagadas" en vez de nombrarlas.
      final conExencion = contrato.copyWith(
        moraExentaHasta: DateTime(2026, 7, 31),
      );
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: conExencion,
        pagos: pagos,
        trackedMonto: 15000,
      );

      expect(origen.length, 2);
      expect(origen[0].numeroCuota, 2);
      expect(origen[1].numeroCuota, 3);
      final total = origen.fold<double>(0, (s, o) => s + o.montoAtribuido);
      expect(total, closeTo(15000, 0.01));
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

    test('un cobro parcial de mora no le borra los días a la cuota', () {
      // Entran 3.000 de los 6.900 de la C2: queda viva con 3.900. Al
      // reconstruirla se perdían los días de atraso y el rótulo se quedaba sin
      // el "23d" que explica el monto.
      final conPagoParcial = [
        ...pagos,
        {
          'id': 'p4',
          'concepto': 'Mora pendiente cuota 2 (no cobrada al pagar)',
          'monto': 3000.0,
          'monto_gross': 3000.0,
          'fecha_pago': '2026-07-28T12:00:00.000000+00:00',
          'anulado': 0,
          'line_kind': kLineKindInteresMora,
        },
      ];
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: conPagoParcial,
        trackedMonto: 12000,
      );

      expect(origen.length, 2);
      expect(origen[0].numeroCuota, 2);
      expect(origen[0].montoAtribuido, closeTo(3900, 0.01));
      expect(origen[0].diasMora, 23);
      expect(origen[0].etiquetaCorta, 'C2 (May) 23d');
      expect(origen[1].numeroCuota, 3);
      expect(origen[1].diasMora, 27);
    });
  });

  group('MoraOrigenRecorte — el perdón suelta la cuota más vieja (VAREIRO)', () {
    // Mismo historial que Bernel: tres cuotas base sin una sola línea de mora,
    // así que el arrastre son $15.000 abiertos en C2 (May) $6.900 y C3 (Jun)
    // $8.100. Lo que cambia acá es qué se pregunta sobre ese arrastre.
    final contrato = ContratoAlumno(
      id: 'perdon-remanente',
      eventoId: 'ev',
      nombreAlumno: 'VAREIRO, YOSELIE ANAHI',
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

    List<MoraPendientePreviaDetalle> queQueda(double tracked) =>
        MoraTrackedOrigen.inferir(
          contratoBase: contrato,
          pagos: pagos,
          trackedMonto: tracked,
          recorte: MoraOrigenRecorte.loQueQueda,
        );

    test('perdonar la C2 entera la saca del rótulo, no a la C3', () {
      // El perdón baja el número en ficha ($15.000 → $8.100) pero no deja
      // rastro de qué mes se perdonó: el historial sigue diciendo C2 + C3.
      // Recortar por la cola dejaba nombrada justo la que se quiso perdonar.
      final queda = queQueda(8100);

      expect(queda.length, 1);
      expect(queda.first.numeroCuota, 3);
      expect(queda.first.mesLabel, 'Jun 2026');
      expect(queda.first.montoAtribuido, closeTo(8100, 0.01));
      expect(
        MoraConceptoRotulo.labelPendientePrevias(detalle: queda),
        'Mora pendiente cuota 3',
      );
    });

    test('la regla vieja seguía nombrando la cuota perdonada', () {
      // Guarda del bug: sin el recorte nuevo, los $8.100 que quedan se imputan
      // desde la cabeza y el rótulo insiste con la C2 (mayo).
      final comoAntes = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: 8100,
      );

      expect(comoAntes.first.numeroCuota, 2);
      expect(
        MoraConceptoRotulo.labelPendientePrevias(detalle: comoAntes),
        'Mora pendiente cuotas 2 y 3',
      );
    });

    test('un perdón que corta en medio de una cuota la deja recortada', () {
      // Se perdonan $10.000 de $15.000: la C2 se va entera y a la C3 le quedan
      // $5.000 de los $8.100. Sigue nombrada, con el monto que de verdad queda.
      final queda = queQueda(5000);

      expect(queda.length, 1);
      expect(queda.first.numeroCuota, 3);
      expect(queda.first.montoAtribuido, closeTo(5000, 0.01));
      expect(queda.first.diasMora, 27, reason: 'el recorte no toca los días');
      expect(
        queda.first.moraCobrada,
        0,
        reason: 'un perdón no es plata que entró',
      );
      expect(queda.first.moraDebida, closeTo(8100, 0.01));
    });

    test('sin perdón las dos reglas dicen lo mismo', () {
      // El caso de la enorme mayoría de los contratos: la cola suma exactamente
      // lo que hay en ficha, no hay brecha que recortar por ninguna punta.
      final queda = queQueda(15000);
      final seCobra = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: 15000,
      );

      expect(queda.map((d) => d.numeroCuota).toList(), [2, 3]);
      expect(
        queda.map((d) => d.montoAtribuido).toList(),
        seCobra.map((d) => d.montoAtribuido).toList(),
      );
    });

    test('poner mora a mano por encima del historial no recorta nada', () {
      // Ajuste positivo (admin escribe un tracked mayor que el que el historial
      // explica): no hay brecha, y lo que sobra sigue cayendo fuera del
      // desglose para que el diálogo lo muestre como "sin origen".
      final queda = queQueda(20000);

      expect(queda.map((d) => d.numeroCuota).toList(), [2, 3]);
      final total = queda.fold<double>(0, (s, d) => s + d.montoAtribuido);
      expect(total, closeTo(15000, 0.01));
    });
  });

  group('seleccionPerdonRemanentePrefijo', () {
    // La cola viene de `inferir`, viejo→nuevo. La entrada sin origen
    // reconstruible lleva el 0 y va al final: por eso no se ordena por número.
    const cola = [2, 3, 0];

    test('tildar un mes incluye los anteriores', () {
      expect(
        MoraCuotaCalculator.seleccionPerdonRemanentePrefijo(
          ordenViejoANuevo: cola,
          seleccionActual: const {},
          tocado: 3,
          marcar: true,
        ),
        {2, 3},
      );
    });

    test('destildar un mes saca los posteriores', () {
      expect(
        MoraCuotaCalculator.seleccionPerdonRemanentePrefijo(
          ordenViejoANuevo: cola,
          seleccionActual: const {2, 3, 0},
          tocado: 3,
          marcar: false,
        ),
        {2},
      );
    });

    test('la entrada sin origen es la última, no la primera', () {
      // Su número es 0; ordenar por número la pondría al frente y perdonarla
      // sola dejaría el resto sin tocar, que es justo lo que no se puede
      // sostener al releer.
      expect(
        MoraCuotaCalculator.seleccionPerdonRemanentePrefijo(
          ordenViejoANuevo: cola,
          seleccionActual: const {},
          tocado: 0,
          marcar: true,
        ),
        {2, 3, 0},
      );
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

  // El concepto persistido está escrito en idioma de origen: "(no cobrada al
  // pagar)" habla de cuando se pagó la cuota, no de este movimiento. En la ficha
  // queda arriba de plata que sí entró y se lee como que el cobro no se hizo
  // (recibo Nº 11408158, VIZGARRA 08/07/2026).
  group('rotuloFichaMora', () {
    test('una cuota: dice de cuál es y que se cobró en este pago', () {
      final r = MoraConceptoRotulo.rotuloFichaMora(
        'Mora pendiente cuota 3 (no cobrada al pagar)',
      );
      expect(r.titulo, 'Mora de la cuota 3');
      expect(
        r.subtexto,
        'Quedaba de cuando se pagó la cuota 3 · se cobró en este pago',
      );
    });

    test('varias cuotas', () {
      final r = MoraConceptoRotulo.rotuloFichaMora(
        'Mora pendiente cuotas 2 y 3 (no cobrada al pagar)',
      );
      expect(r.titulo, 'Mora de las cuotas 2 y 3');
      expect(r.subtexto, contains('se cobró en este pago'));

      final tres = MoraConceptoRotulo.rotuloFichaMora(
        'Mora pendiente cuotas 2, 3 y 5 (no cobrada al pagar)',
      );
      expect(tres.titulo, 'Mora de las cuotas 2, 3 y 5');
    });

    test('genérico sin número de cuota', () {
      final r = MoraConceptoRotulo.rotuloFichaMora(
        MoraConceptoRotulo.conceptoPendientePrevias(),
      );
      expect(r.titulo, 'Mora de cuotas ya pagadas');
      expect(
        r.subtexto,
        'Quedaba de cobros anteriores · se cobró en este pago',
      );
    });

    test('los conceptos que ya se entienden vuelven intactos y sin subtexto', () {
      for (final c in const [
        'Interés mora cuota 1 (vto Abr 2026)',
        'Interés mora (cuota base — este cobro)',
        'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2',
        'Cuota Base (4/9)',
      ]) {
        final r = MoraConceptoRotulo.rotuloFichaMora(c);
        expect(r.titulo, c);
        expect(r.subtexto, isNull);
      }
    });

    test('ningún título de ficha dice "no cobrada al pagar"', () {
      for (final c in const [
        'Mora pendiente cuota 3 (no cobrada al pagar)',
        'Mora pendiente cuotas 2 y 3 (no cobrada al pagar)',
        'Mora pendiente de cuotas ya pagadas (no cobrada al pagar)',
      ]) {
        expect(
          MoraConceptoRotulo.rotuloFichaMora(c).titulo,
          isNot(contains('no cobrada al pagar')),
        );
      }
    });

    test('el concepto persistido sigue siendo clave reconocible', () {
      // El rótulo es de display: la base no se toca y el detector sigue viendo
      // la línea como mora.
      const persistido = 'Mora pendiente cuota 3 (no cobrada al pagar)';
      expect(esPagoInteresMoraPorConcepto(persistido), isTrue);
      expect(
        MoraConceptoRotulo.rotuloFichaMora(persistido).titulo,
        isNot(persistido),
      );
    });
  });
}
