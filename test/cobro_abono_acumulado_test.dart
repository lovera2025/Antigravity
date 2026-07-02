import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';

void main() {
  group('evaluarAvanceCuotaConAbonos', () {
    test('abono parcial sin cerrar cuota', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 5000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 0);
      expect(r.esAbonoSolo, isTrue);
    });

    test('segundo abono cierra cuota (20k + 10k = 30k)', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 10000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraCuotaExacta, isTrue);
      expect(r.cuotasCompletasDespues, 1);
    });

    test('pago completo de una cuota sin historial', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 0,
        grossActual: 30000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraCuotaExacta, isTrue);
    });

    test('cierra cuota y deja adelanto hacia la siguiente', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 20000,
        grossActual: 15000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 1);
      expect(r.cierraConAdelanto, isTrue);
      expect(r.restoAbono, closeTo(5000, 0.01));
    });

    test('dos cuotas nuevas en un solo cobro con acumulado', () {
      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: 25000,
        grossActual: 35000,
        cuotaPura: 30000,
      );
      expect(r.cuotasLiquidadas, 2);
      expect(r.cierraCuotaExacta, isTrue);
      expect(r.cuotasCompletasDespues, 2);
    });

    test('regresión: 2 cuotas ya pagadas + 20k parcial = solo abono', () {
      const cuotaPura = 210000 / 9; // ~23333.33
      const historico2Cuotas = cuotaPura * 2;

      final r = evaluarAvanceCuotaConAbonos(
        grossHistoricoClase: historico2Cuotas,
        grossActual: 20000,
        cuotaPura: cuotaPura,
      );

      expect(r.cuotasLiquidadas, 0);
      expect(r.esAbonoSolo, isTrue);
      expect(r.cuotasCompletasDespues, 2);
    });
  });

  group('grossHistoricoClaseCobro', () {
    test('excluye mora, cargo canal y anulados', () {
      final pagos = [
        {
          'anulado': 0,
          'concepto': 'Abono a Cuota Base (1/9)',
          'monto': 20000,
          'monto_gross': 20000,
        },
        {
          'anulado': 1,
          'concepto': 'Cuota Base',
          'monto': 30000,
          'monto_gross': 30000,
        },
        {
          'anulado': 0,
          'line_kind': 'interes_mora',
          'concepto': 'Interés mora (cuota base — este cobro)',
          'monto': 500,
          'monto_gross': 500,
        },
        {
          'anulado': 0,
          'line_kind': 'cargo_canal_ref',
          'concepto': 'Cargo canal',
          'monto': 100,
          'monto_gross': 0,
        },
        {
          'anulado': 0,
          'concepto': 'Mesa Extra (1/3)',
          'monto': 5000,
          'monto_gross': 5000,
        },
      ];

      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.base),
        20000,
      );
      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.mesa),
        5000,
      );
      expect(
        grossHistoricoClaseCobro(pagos, CobroConceptoClase.sillas),
        0,
      );
    });
  });

  group('rotularDesgloseConAbonosAcumulados', () {
    String detalle(String raw, int offset) => 'Cuota Base (${offset}/9)';

    test('abono cuando no alcanza', () {
      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 20000,
        cuotaPura: 30000,
        grossHistoricoClase: 0,
        getConceptoDetallado: detalle,
        cuotasPagadasActuales: 0,
      );
      expect(r.cuotas, 0);
      expect(r.concepto, contains('Entrega parcial'));
    });

    test('cuota pagada al cerrar con abonos previos', () {
      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 10000,
        cuotaPura: 30000,
        grossHistoricoClase: 20000,
        getConceptoDetallado: detalle,
        cuotasPagadasActuales: 0,
      );
      expect(r.cuotas, 1);
      expect(r.concepto, 'Cuota Base (1/9) — Completada');
      expect(r.concepto, isNot(contains('Entrega parcial')));
    });

    test('regresión Arguello: 2 cuotas pagadas + 20k = abono hacia cuota 3', () {
      const cuotaPura = 210000 / 9;
      const historico2Cuotas = cuotaPura * 2;

      String detalleArguello(String raw, int offset) =>
          'Cuota Base (${2 + offset}/9)';

      final r = rotularDesgloseConAbonosAcumulados(
        conceptoKey: 'Base',
        label: 'Cuota Base',
        grossActual: 20000,
        cuotaPura: cuotaPura,
        grossHistoricoClase: historico2Cuotas,
        getConceptoDetallado: detalleArguello,
        cuotasPagadasActuales: 2,
      );

      expect(r.cuotas, 0);
      expect(r.concepto, contains('Entrega parcial'));
      expect(r.concepto, isNot(contains('2 Cuotas')));
    });
  });

  group('rotuloCuotaLiquidada y lineasPreviewDesglosePlan', () {
    test('cuota entera sin parcial previo', () {
      expect(
        rotuloCuotaLiquidada(
          etiqueta: 'Cuota Base',
          numeroCuota: 2,
          totalCuotas: 9,
          cierraEntregaParcialPrevio: false,
        ),
        'Cuota Base (2/9)',
      );
    });

    test('cierra entrega parcial previa', () {
      expect(
        rotuloCuotaLiquidada(
          etiqueta: 'Mesa Extra 1',
          numeroCuota: 1,
          totalCuotas: 7,
          cierraEntregaParcialPrevio: true,
        ),
        'Mesa Extra 1 (1/7) — Completada',
      );
    });

    test('lineasPreview: parcial libre que cierra parcial', () {
      const cuotaPura = 35000.0;
      const historico = 30250.0;
      final lineas = lineasPreviewDesglosePlan(
        modo: ModoPagoConceptoTipo.parcialLibre,
        cuotasSeleccionadas: null,
        grossTotal: 4750,
        cuotaPura: cuotaPura,
        totalCuotas: 9,
        grossHistorico: historico,
        etiqueta: 'Cuota Base',
      );
      expect(lineas.length, 1);
      expect(lineas.first.concepto, 'Cuota Base (1/9) — Completada');
      expect(lineas.first.cuotasLiquidadas, 1);
      expect(
        lineas.first.subtexto,
        'Entrega parcial previa: \$30.250,00. '
            'Este cobro: \$4.750,00 (saldo restante). Cuota al día.',
      );
    });

    test('lineasPreview: cuota entera sin parcial', () {
      final lineas = lineasPreviewDesglosePlan(
        modo: ModoPagoConceptoTipo.cuotas,
        cuotasSeleccionadas: {1},
        grossTotal: 35000,
        cuotaPura: 35000,
        totalCuotas: 9,
        grossHistorico: 0,
        etiqueta: 'Cuota Base',
      );
      expect(lineas.first.concepto, 'Cuota Base (1/9)');
      expect(lineas.first.concepto, isNot(contains('Completada')));
    });

    test('lineasPreview: seleccionar cuotas cierra parcial', () {
      final lineas = lineasPreviewDesglosePlan(
        modo: ModoPagoConceptoTipo.cuotas,
        cuotasSeleccionadas: {1},
        grossTotal: 4750,
        cuotaPura: 35000,
        totalCuotas: 9,
        grossHistorico: 30250,
        etiqueta: 'Cuota Base',
      );
      expect(lineas.first.concepto, 'Cuota Base (1/9) — Completada');
      expect(lineas.first.cuotasLiquidadas, 1);
      expect(lineas.first.subtexto, contains('30.250,00'));
      expect(lineas.first.subtexto, contains('4.750,00'));
    });

    test('lineasPreview: cierra parcial y otra cuota entera sin subtexto en la 2', () {
      final lineas = lineasPreviewDesglosePlan(
        modo: ModoPagoConceptoTipo.cuotas,
        cuotasSeleccionadas: {1, 2},
        grossTotal: 39750,
        cuotaPura: 35000,
        totalCuotas: 9,
        grossHistorico: 30250,
        etiqueta: 'Cuota Base',
      );
      expect(lineas.length, 2);
      expect(lineas[0].concepto, 'Cuota Base (1/9) — Completada');
      expect(lineas[0].subtexto, isNotNull);
      expect(lineas[1].concepto, 'Cuota Base (2/9)');
      expect(lineas[1].subtexto, isNull);
    });

    test('rotulo Completada no dispara heurística de entrega parcial', () {
      final c = 'Cuota Base (1/9) — Completada'.toLowerCase();
      final esEntregaParcial = c.contains('entrega') ||
          c.contains('adelanto') ||
          c.contains('parcial') ||
          c.contains('abono');
      expect(esEntregaParcial, isFalse);
      expect(c.contains('cuota'), isTrue);
    });

    test('regresión Chamorro: adelanto C3 + cobro 66.500 no deja parcial fantasma', () {
      const cuotaPura = 30000.0;
      const totalCuotas = 9;
      const pactado = 270000.0;
      // 2 cuotas + adelanto $23.500 en C3
      const grossHistorico = 83500.0;
      const grossCobro = 66500.0;

      final lineas = lineasPreviewDesglosePlan(
        modo: ModoPagoConceptoTipo.cuotas,
        cuotasSeleccionadas: {3, 4, 5},
        grossTotal: grossCobro,
        cuotaPura: cuotaPura,
        totalCuotas: totalCuotas,
        grossHistorico: grossHistorico,
        etiqueta: 'Cuota Base',
      );

      expect(lineas.length, 3);
      expect(lineas[0].gross, closeTo(6500, 0.01));
      expect(lineas[0].cuotasLiquidadas, 1);
      expect(lineas[1].gross, closeTo(30000, 0.01));
      expect(lineas[2].gross, closeTo(30000, 0.01));

      final grossTotalPagado = grossHistorico + grossCobro;
      final saldoEsperado = pactado - grossTotalPagado;
      expect(saldoEsperado, closeTo(120000, 0.01));

      final desglose = desgloseCuotasPlan(
        grossHistorico: grossTotalPagado,
        cuotaPura: cuotaPura,
        totalCuotas: totalCuotas,
      );
      final parciales = desglose.where((c) => c.estado == EstadoCuotaPlan.parcial);
      expect(parciales, isEmpty);
      expect(
        desglose.where((c) => c.numero <= 5).every((c) => c.estado == EstadoCuotaPlan.pagada),
        isTrue,
      );
    });
  });
}
