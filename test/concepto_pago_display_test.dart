import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

ContratoAlumno _contratoAvilaLike() {
  return ContratoAlumno(
    id: 'c1',
    eventoId: 'e1',
    nombreAlumno: 'AVILA, BLAS ADRIEL',
    cantidadAcompanantes: 0,
    montoTotalPactado: 315000,
    saldoDeudor: 175000,
    totalCuotas: 9,
    cuotasPagadas: 4,
  );
}

Map<String, dynamic> _pago({
  required String id,
  required String fecha,
  required String concepto,
  required double gross,
  double? net,
  String? medio,
  String? lineKind,
}) {
  final m = net ?? gross;
  return {
    'id': id,
    'concepto': concepto,
    'monto': m,
    'monto_gross': gross,
    'fecha_pago': fecha,
    if (medio != null) 'medio_pago': medio,
    if (lineKind != null) 'line_kind': lineKind,
    'anulado': 0,
  };
}

void main() {
  group('rotularPlanDesdeGross', () {
    test('dos cuotas exactas desde cero', () {
      final r = ConceptoPagoDisplay.rotularPlanDesdeGross(
        grossHistorico: 0,
        grossActual: 70000,
        cuotaPura: 35000,
        totalCuotas: 9,
        etiqueta: 'Cuota Base',
      );
      expect(r.concepto, 'Cuotas Base (1–2/9)');
      expect(r.cuotasLiquidadas, 2);
    });

    test('una cuota + adelanto', () {
      final r = ConceptoPagoDisplay.rotularPlanDesdeGross(
        grossHistorico: 70000,
        grossActual: 50000,
        cuotaPura: 35000,
        totalCuotas: 9,
        etiqueta: 'Cuota Base',
      );
      expect(r.concepto, 'Cuota Base (3/9) + Cuota Base (4/9) · \$15.000,00');
      expect(r.cuotasLiquidadas, 1);
    });

    test('cierra cuota con abono previo', () {
      final r = ConceptoPagoDisplay.rotularPlanDesdeGross(
        grossHistorico: 120000,
        grossActual: 20000,
        cuotaPura: 35000,
        totalCuotas: 9,
        etiqueta: 'Cuota Base',
      );
      expect(r.concepto, 'Cuota Base (4/9) — Completada');
      expect(r.cuotasLiquidadas, 1);
      expect(r.subtexto, contains('15.000,00'));
      expect(r.subtexto, contains('20.000,00'));
    });

    test('cuota entera sin parcial previo', () {
      final r = ConceptoPagoDisplay.rotularPlanDesdeGross(
        grossHistorico: 70000,
        grossActual: 35000,
        cuotaPura: 35000,
        totalCuotas: 9,
        etiqueta: 'Cuota Base',
      );
      expect(r.concepto, 'Cuota Base (3/9)');
      expect(r.concepto, isNot(contains('Completada')));
    });
  });

  group('enriquecerPagosHistorial — caso AVILA', () {
    test('interpreta 70k + mixto 50k T + 20k E como un solo avance', () {
      final c = _contratoAvilaLike();
      final pagos = [
        _pago(
          id: '1',
          fecha: '2026-04-17T17:46:00.000Z',
          concepto: '2 Cuotas (Cuota Base)',
          gross: 70000,
        ),
        _pago(
          id: '2',
          fecha: '2026-05-13T09:36:00.000Z',
          concepto: '2 Cuotas (Cuota Base)',
          gross: 50000,
          medio: 'Transferencia',
        ),
        _pago(
          id: '3',
          fecha: '2026-05-13T09:36:00.000Z',
          concepto: '2 Cuotas (Cuota Base)',
          gross: 20000,
          medio: 'Efectivo',
        ),
        _pago(
          id: '4',
          fecha: '2026-05-13T09:36:00.000Z',
          concepto: 'Cargo canal / operador (ref. MP u otro)',
          gross: 1500,
          net: 1500,
          lineKind: 'cargo_canal_ref',
        ),
      ];

      final filas = ConceptoPagoDisplay.enriquecerPagosHistorial(c, pagos);

      expect(filas.length, 4);
      expect(filas[0]['concepto_detallado'], contains('Cargo'));
      // Par mixto: mismo rótulo en ambas patas (cuotas 3–4).
      expect(filas[1]['concepto_detallado'], 'Cuotas Base (3–4/9)');
      expect(filas[1]['subtitulo_medio'], '· Efectivo');
      expect(filas[2]['concepto_detallado'], 'Cuotas Base (3–4/9)');
      expect(filas[2]['subtitulo_medio'], '· Transferencia');
      expect(filas[3]['concepto_detallado'], 'Cuotas Base (1–2/9)');
    });
  });

  group('armarRegistroMixtoAgregado', () {
    test('3×35k con E 68k + T 37k → montos exactos y un rótulo', () {
      final c = ContratoAlumno(
        id: 'alfonzo',
        eventoId: 'e1',
        nombreAlumno: 'ALFONZO, AGUSTIN',
        cantidadAcompanantes: 0,
        montoTotalPactado: 315000,
        saldoDeudor: 315000,
        totalCuotas: 9,
        cuotasPagadas: 0,
      );
      final preview = [
        for (var i = 0; i < 3; i++)
          {
            'concepto': 'Cuota Base (${i + 1}/9)',
            'monto': 35000.0,
            'gross': 35000.0,
            'cuotas': 1,
          },
      ];
      final partes = ConceptoPagoDisplay.armarRegistroMixtoAgregado(
        contrato: c,
        previewLineas: preview,
        parteEfectivo: 68000,
        parteTransferencia: 37000,
        historicoGrossPorClave: const {},
      );
      expect(partes.length, 2);
      final nets = partes.map((p) => p.net).toList()..sort();
      expect(nets[0], 37000);
      expect(nets[1], 68000);
      expect(partes.every((p) => p.concepto == 'Cuotas Base (1–3/9)'), isTrue);
      expect(
        partes.where((p) => p.medio == 'Efectivo').single.net,
        68000,
      );
      expect(
        partes.where((p) => p.medio == 'Transferencia').single.net,
        37000,
      );
      final conCuotas = partes.where((p) => p.cuotasLiquidadas > 0).toList();
      expect(conCuotas.length, 1);
      expect(conCuotas.first.cuotasLiquidadas, 3);
    });
  });

  group('rotularPartesMixtoPlan', () {
    test('mixto 50k+20k tras 70k histórico — mismo rótulo en ambas patas', () {
      final c = _contratoAvilaLike();
      final partes = ConceptoPagoDisplay.rotularPartesMixtoPlan(
        contrato: c,
        previewLinea: {
          'concepto': '2 Cuotas (Cuota Base)',
          'gross': 70000,
          'monto': 70000,
        },
        grossHistoricoClase: 70000,
        grossLinea: 70000,
        netLinea: 70000,
        parteEfectivo: 20000,
        totalIngresado: 70000,
      );
      expect(partes.length, 2);
      expect(partes[0].rotulo.concepto, 'Cuotas Base (3–4/9)');
      expect(partes[1].rotulo.concepto, 'Cuotas Base (3–4/9)');
      expect(partes.map((p) => p.net).toSet(), {50000.0, 20000.0});
    });
  });

  group('conceptosPdfDesdePagosLote — Alderete/Brisa Opción B', () {
    test('reimpresión: cuota 3/9 + mora partida con subtexto 300/7200', () {
      final c = ContratoAlumno(
        id: 'brisa',
        eventoId: 'e1',
        nombreAlumno: 'ALDERETE, BRISA GUADALUPE',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 180000,
        totalCuotas: 9,
        cuotasPagadas: 3,
        createdAt: DateTime.parse('2026-03-30T03:00:00+00:00'),
        moraExentaHasta: DateTime(2026, 7, 31),
      );

      final hist = [
        _pago(
          id: 'p1',
          fecha: '2026-05-29T19:41:55.865821+00:00',
          concepto: 'Cuota Base (1/9)',
          gross: 30000,
        ),
        _pago(
          id: 'p2',
          fecha: '2026-05-29T19:41:55.915106+00:00',
          concepto: 'Interés mora cuota 1 (vto Abr 2026)',
          gross: 8700,
          lineKind: 'interes_mora',
        ),
        _pago(
          id: 'p3',
          fecha: '2026-06-24T21:49:13.583682+00:00',
          concepto: 'Cuota Base (2/9)',
          gross: 30000,
        ),
        _pago(
          id: 'p4',
          fecha: '2026-06-24T21:49:13.622093+00:00',
          concepto: 'Interés mora (cuota base — este cobro)',
          gross: 300,
          lineKind: 'interes_mora',
        ),
        _pago(
          id: 'p5',
          fecha: '2026-07-23T23:05:28.824901+00:00',
          concepto: 'Cuota Base (3/9)',
          gross: 30000,
          medio: 'Efectivo',
        ),
        _pago(
          id: 'p6',
          fecha: '2026-07-23T23:05:28.957938+00:00',
          concepto:
              'Interés mora cuota 3 (vto Jun 2026) + mora pendiente cuota 2',
          gross: 13800,
          medio: 'Efectivo',
          lineKind: 'interes_mora',
        ),
      ];

      final lote = hist.where((p) => p['id'] == 'p5' || p['id'] == 'p6').toList();

      final pdf = ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
        c,
        lote,
        historialCompleto: hist,
      );

      final cuota = pdf.where((l) =>
          (l['concepto'] as String).contains('Cuota Base') &&
          l['esMora'] != true);
      expect(cuota.length, 1);
      expect(cuota.first['concepto'], 'Cuota Base (3/9)');

      final mora = pdf.where((l) => l['esMora'] == true).toList();
      expect(mora.length, 2);
      expect(mora[0]['concepto'], 'Interés mora cuota 3 (vto Jun 2026)');
      expect(mora[0]['monto'], 6900.0);
      expect(mora[1]['concepto'], 'Mora pendiente cuota 2');
      expect(mora[1]['monto'], 6900.0);
      expect(
        mora[1]['subtexto'],
        contains('300'),
      );
      expect(
        mora[1]['subtexto'],
        contains('7.200'),
      );
    });
  });
}
