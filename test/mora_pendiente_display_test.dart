import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

void main() {
  group('MoraCuotaCalculator.desglosePendiente', () {
    final desglose = [
      MoraCuotaDetalle(
        numeroCuota: 1,
        vencimiento: DateTime(2024, 4, 30),
        diasMora: 49,
        interesBruto: 14700,
        mesLabel: 'Abr 2024',
      ),
      MoraCuotaDetalle(
        numeroCuota: 2,
        vencimiento: DateTime(2024, 5, 31),
        diasMora: 19,
        interesBruto: 5400,
        mesLabel: 'May 2024',
      ),
    ];

    test('sin pagos: devuelve desglose bruto completo', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 0);
      expect(r.length, 2);
      expect(r[0].interesBruto, closeTo(14700, 0.01));
      expect(r[1].interesBruto, closeTo(5400, 0.01));
    });

    test('mora cuota 1 pagada: omite cuota 1 y deja cuota 2', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 14700);
      expect(r.length, 1);
      expect(r.first.numeroCuota, 2);
      expect(r.first.interesBruto, closeTo(5400, 0.01));
    });

    test('pago parcial en cuota 1: reduce solo la primera cuota', () {
      final r = MoraCuotaCalculator.desglosePendiente(desglose, 10000);
      expect(r.length, 2);
      expect(r[0].numeroCuota, 1);
      expect(r[0].interesBruto, closeTo(4700, 0.01));
      expect(r[1].interesBruto, closeTo(5400, 0.01));
    });
  });

  group('MoraCuotaCalculator.moraPendienteOperativa (nuevo modelo)', () {
    test('solo desglose calendario, tracked = 0 → total = desglose', () {
      final c = ContratoAlumno(
        id: 'a',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 270000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseTotal =
          desglose.fold<double>(0, (s, d) => s + d.interesBruto);
      expect(desgloseTotal, greaterThan(0));

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(desgloseTotal, 0.01));
    });

    test('tracked legacy 0/9 no infla mora (migración limpia tracked)', () {
      // Post-migración v49: tracked = 0 para contratos con tracked inflado
      final c = ContratoAlumno(
        id: 'ayala',
        eventoId: 'evt',
        nombreAlumno: 'AYALA',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 270000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        moraPendienteTracked: 0, // limpiado por migración
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
      );
      final desglose = MoraCuotaCalculator.calcularDesglose(c);
      final desgloseTotal =
          desglose.fold<double>(0, (s, d) => s + d.interesBruto);
      expect(r, closeTo(desgloseTotal, 0.01));
    });

    test('cuota pagada sin mora: mora pasa a tracked (ficha), no se pierde', () {
      final c = ContratoAlumno(
        id: 'b',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        moraPendienteTracked: 8700,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseTotal =
          desglose.fold<double>(0, (s, d) => s + d.interesBruto);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(desgloseTotal + 8700, 0.01));
    });

    test('remanente parcial legítimo se suma al desglose', () {
      // Cuota 1 fue pagada con mora parcial → tracked = $3,700 (remanente)
      // Cuota 2 vencida → desglose calendario.
      // offset = $5,000 (mora cobrada para cuota 1, absorbida)
      final c = ContratoAlumno(
        id: 'c',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        moraPendienteTracked: 3700, // remanente real
        moraCobradaOffset: 5000,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);

      // moraCobradaAjustada = 5000 - 5000 = 0 → desglose neto = bruto completo
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseTotal =
          desglose.fold<double>(0, (s, d) => s + d.interesBruto);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 5000,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(desgloseTotal + 3700, 0.01));
    });

    test('mora parcial cobrada en período actual reduce desglose FIFO', () {
      // Cuota 2 vencida, se cobró $2,000 de mora en este período.
      // offset = $5,000, moraCobradaHist = $7,000
      // moraCobradaAjustada = $7,000 - $5,000 = $2,000 → FIFO resta $2,000
      final c = ContratoAlumno(
        id: 'd',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        moraPendienteTracked: 0,
        moraCobradaOffset: 5000,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desgloseBruto = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseBrutoTotal =
          desgloseBruto.fold<double>(0, (s, d) => s + d.interesBruto);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 7000,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(desgloseBrutoTotal - 2000, 0.01));
    });

    test('toda la mora cobrada → pendiente 0', () {
      final c = ContratoAlumno(
        id: 'e',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desgloseBruto = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseBrutoTotal =
          desgloseBruto.fold<double>(0, (s, d) => s + d.interesBruto);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: desgloseBrutoTotal,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(0, 0.01));
    });

    test('mora solo parcial con offset 0 reduce pendiente vía FIFO', () {
      final c = ContratoAlumno(
        id: 'g',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 270000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desgloseBruto = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseBrutoTotal =
          desgloseBruto.fold<double>(0, (s, d) => s + d.interesBruto);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 5000,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(desgloseBrutoTotal - 5000, 0.01));
    });

    test('sin cuotas vencidas + tracked remanente parcial', () {
      // Cuota 3 no venció aún. tracked = $3,700 de remanente parcial.
      final c = ContratoAlumno(
        id: 'f',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 210000,
        cuotasPagadas: 2,
        totalCuotas: 9,
        moraPendienteTracked: 3700,
        moraCobradaOffset: 14700,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 1); // cuota 3 vence 30/06
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      expect(desglose, isEmpty);

      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 14700,
        ahoraAr: ahoraAr,
      );
      expect(r, closeTo(3700, 0.01));
    });
  });

  group('MoraCuotaCalculator.postCobroTrackedOffset', () {
    final desgloseCuota1 = [
      MoraCuotaDetalle(
        numeroCuota: 1,
        vencimiento: DateTime(2026, 3, 31),
        diasMora: 90,
        interesBruto: 8700,
        mesLabel: 'Mar 2026',
      ),
    ];

    test('cuota sin mora con remanente previo → tracked acumula el carry-over', () {
      // Forma Bernel: el remanente es de una cuota YA pagada (la 2, $6.900) y
      // ahora se liquida la cuota 3 ($8.100) sin cobrar mora. Conjuntos
      // disjuntos → 15.000. Pisar el tracked daría 8.100 (el bug v53).
      final desgloseNetoCuota3 = [
        MoraCuotaDetalle(
          numeroCuota: 3,
          vencimiento: DateTime(2026, 6, 30),
          diasMora: 27,
          interesBruto: 8100,
          mesLabel: 'Jun 2026',
        ),
      ];
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 6900,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: desgloseNetoCuota3,
        moraDesgloseNetoPreCobro: desgloseNetoCuota3,
        moraDesgloseNetoTotal: 8100,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(15000, 0.01));
      expect(r.offset, closeTo(0, 0.01));
    });

    test('cobrar solo una cuota del arrastre deja la otra pendiente', () {
      // Bernel con 15.000 en ficha (C2 6.900 + C3 8.100). El operador tilda
      // solo la C2 y paga 6.900: tiene que quedar la C3 viva.
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 15000,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 6900,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: const [],
        moraDesgloseNetoPreCobro: const [],
        moraDesgloseNetoTotal: 0,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(8100, 0.01));
      expect(r.offset, closeTo(6900, 0.01));
    });

    test('cuota base + una sola cuota del arrastre → resto sigue en ficha', () {
      // Mismo caso pero liquidando además la cuota 4, que aún no venció
      // (desglose calendario en cero).
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 15000,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 6900,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 4,
        moraDesglosePreCobro: const [],
        moraDesgloseNetoPreCobro: const [],
        moraDesgloseNetoTotal: 0,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(8100, 0.01));
      expect(r.offset, closeTo(6900, 0.01));
    });

    test('snapshot legacy sin cuotas previas → no duplica el desglose', () {
      // cuotasPreCobro == 0: no puede existir carry-over legítimo (no se liquidó
      // ninguna cuota antes), así que ese tracked solo puede referirse a cuotas
      // todavía impagas — las mismas del desglose. No se suma.
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 3700,
        moraCobradaOffsetActual: 5000,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(8700, 0.01));
      expect(r.offset, closeTo(5000, 0.01));
    });

    test('cuota sin mora sin remanente previo → tracked = mora de la cuota', () {
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(8700, 0.01));
      expect(r.offset, closeTo(0, 0.01));
    });

    test('anti-Arrospide: post cuota sin mora, operativa = desglose + tracked', () {
      final post = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      final c = ContratoAlumno(
        id: 'arro',
        eventoId: 'evt',
        nombreAlumno: 'Test',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        moraPendienteTracked: post.tracked,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseNeto = MoraCuotaCalculator.desglosePendiente(desglose, 0);
      final operativa = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
        ahoraAr: ahoraAr,
      );
      final sumDesglose =
          desgloseNeto.fold<double>(0, (s, d) => s + d.interesBruto);
      expect(operativa, closeTo(sumDesglose + post.tracked, 0.01));
      expect(post.tracked, closeTo(8700, 0.01));
    });

    test('cuota + mora parcial → tracked remanente', () {
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 5000,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(3700, 0.01));
      expect(r.offset, closeTo(5000, 0.01));
    });

    test('solo mora parcial → offset sin cambio, FIFO en desglose', () {
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 5000,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 0,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(0, 0.01));
      expect(r.offset, closeTo(0, 0.01));
    });

    test('solo mora completa → offset absorbe desglose (exención permanente)', () {
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 8700,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 0,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseCuota1,
        moraDesgloseNetoTotal: 8700,
        saldoDeudorPost: 180000,
        fechaCobroAr: DateTime(2026, 8, 7),
        exencionActual: null,
        reiniciaActual: false,
      );
      expect(r.tracked, closeTo(0, 0.01));
      expect(r.offset, closeTo(8700, 0.01));
      // El offset sube junto con el historial, así que por sí solo no borra la
      // cuota del calendario: quien la borra es la exención. Tiene que salir de
      // la misma llamada o el estado post-cobro queda a medias.
      expect(r.exentaHasta, DateTime(2026, 8, 31));
      expect(r.reinicia, isFalse);
    });

    // Historial REAL de BORDA (contrato 4fa099cb…, verificado en Supabase).
    // Reg 30-mar-2026 (el fixture viejo usaba 25-mar, que no existe en la base).
    // Cuota base $30.000 → $300/día. C1 vence 30-abr, C2 31-may, C3 30-jun.
    List<Map<String, dynamic>> pagosBordaReales() => [
          {
            'fecha_pago': '2026-05-20T21:15:11.215229+00:00',
            'concepto': 'Cuota Base (1/9)',
            'monto': 30000.0,
            'monto_gross': 30000.0,
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-05-20T21:15:11.533734+00:00',
            'concepto': 'Interés mora (cuota base — este cobro)',
            'monto': 300.0,
            'monto_gross': 300.0,
            'line_kind': 'interes_mora',
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-05-20T21:15:11.647885+00:00',
            'concepto': 'Cargo canal / operador (ref. MP u otro)',
            'monto': 2000.0,
            'monto_gross': 0.0,
            'line_kind': 'cargo_canal_ref',
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-06-30T22:46:35.070075+00:00',
            'concepto': 'Cuota Base (2/9)',
            'monto': 30000.0,
            'monto_gross': 30000.0,
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-07-01T14:16:00.394883+00:00',
            'concepto': 'Mora pendiente cuota 2 (no cobrada al pagar)',
            'monto': 9000.0,
            'monto_gross': 9000.0,
            'line_kind': 'interes_mora',
            'anulado': 0,
          },
        ];

    ContratoAlumno contratoBordaReal({required double saldoDeudor}) =>
        ContratoAlumno(
          id: 'borda',
          eventoId: 'evt',
          nombreAlumno: 'BORDA, LUDMILA AILEN',
          cantidadAcompanantes: 0,
          montoTotalPactado: 270000,
          saldoDeudor: saldoDeudor,
          cuotasPagadas: 0,
          totalCuotas: 9,
          createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
        );

    test('Borda: cuota 2 sin mora arrastra el remanente de la cuota 1', () {
      // Al 20-may la cuota 1 llevaba 20 días vencida ($6.000 devengados) y solo
      // se cobraron $300 → quedan $5.700 de carry-over. Al 30-jun se liquida la
      // cuota 2 ($9.000 de mora) sin cobrar interés → 5.700 + 9.000 = 14.700.
      // Conjuntos disjuntos (cuota 1 vs cuota 2): no hay doble conteo. La
      // expectativa vieja (8.700) codificaba la pérdida del remanente.
      final resultado = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBordaReal(saldoDeudor: 240000),
        pagos: pagosBordaReales().take(4).toList(),
      );
      expect(resultado.tracked, closeTo(14700, 0.01));
      expect(resultado.offset, closeTo(300, 0.01));
    });

    test('Borda: el pago de mora remanente descuenta, no borra el carry-over', () {
      // El 1-jul se cobraron $9.000 de "mora pendiente cuota 2" — lo que la UI
      // mostraba entonces con el tracked pisado. Devengado real 15.000, cobrado
      // 9.300 → quedan 5.700 de la cuota 1. Ese remanente no viene del bug del
      // carry-over sino de que el cobro del 20-may se hizo con otro criterio de
      // mora; el replay le aplica la regla de hoy.
      final contratoBase = contratoBordaReal(saldoDeudor: 210000);
      final resultado = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagosBordaReales(),
      );
      expect(resultado.tracked, closeTo(5700, 0.01));
      expect(resultado.offset, closeTo(9300, 0.01));

      final contratoJul2 = contratoBase.copyWith(
        cuotasPagadas: 2,
        moraPendienteTracked: resultado.tracked,
        moraCobradaOffset: resultado.offset,
      );
      final operativa = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contratoJul2,
        moraCobradaHistorial: 9300,
        ahoraAr: DateTime(2026, 7, 2),
      );
      // Carry-over 5.700 + cuota 3 (vence 30-jun; al 2-jul, 2 días × $300).
      expect(operativa, closeTo(6300, 50));
    });

    test('Bernel: tres cuotas sin mora acumulan 0 → 6.900 → 15.000', () {
      // Historial REAL (contrato 9a41293d…, verificado en Supabase): tres
      // "Cuota Base (n/9)" de $30.000, ninguna línea de mora en toda su historia.
      // Reg 30-mar-2026 → C1 vence 30-abr, C2 31-may, C3 30-jun.
      final pagos = <Map<String, dynamic>>[
        {
          'fecha_pago': '2026-04-28T21:28:04.595192+00:00',
          'concepto': 'Cuota Base (1/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-06-23T20:22:45.683166+00:00',
          'concepto': 'Cuota Base (2/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-07-27T20:08:41.809065+00:00',
          'concepto': 'Cuota Base (3/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'anulado': 0,
        },
      ];
      final contratoBase = ContratoAlumno(
        id: 'bernel',
        eventoId: 'evt',
        nombreAlumno: 'BERNEL, LUCILA FATIMA',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 180000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
      );

      // Cobro 1 (28-abr): la cuota 1 vence el 30-abr → pagó antes, sin mora.
      final tras1 = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagos.take(1).toList(),
      );
      expect(tras1.tracked, closeTo(0, 0.01));

      // Cobro 2 (23-jun): cuota 2 vencida el 31-may → 23 días × $300.
      final tras2 = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagos.take(2).toList(),
      );
      expect(tras2.tracked, closeTo(6900, 0.01));

      // Cobro 3 (27-jul): cuota 3 vencida el 30-jun → 27 días × $300 = 8.100.
      // Con el bug el tracked quedaba en 8.100 (es lo que hay hoy en la nube).
      final tras3 = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagos,
      );
      expect(tras3.tracked, closeTo(15000, 0.01));
      expect(tras3.offset, closeTo(0, 0.01));
    });
  });

  group('Exención mora (pago total salda mora → limpio hasta fin de mes)', () {
    test('Lezcano: pagó cuota 1 + mora 3 cuotas → 0 hasta 31-jul', () {
      // Inscripción 30-mar-2026 (UTC) → AR idem.
      // Cuota 1 vence 30-abr, cuota 2 vence 31-may, cuota 3 vence 30-jun.
      // Pagó el 6-jul: cuota 1 ($30k) + mora ($32.700).
      // Post-cobro: tracked=0, offset=$32.700, exención=31-jul-2026.
      // moraExencionReinicia=true (default): tras vencer, reinicia desde exención.
      final contrato = ContratoAlumno(
        id: 'lezcano',
        eventoId: 'evt',
        nombreAlumno: 'LEZCANO, BLAS',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 12, 21, 17),
        moraPendienteTracked: 0,
        moraCobradaOffset: 32700,
        moraExentaHasta: DateTime(2026, 7, 31),
        moraExencionReinicia: true,
      );

      // Jul 7: dentro de exención → $0
      final moraJul7 = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato,
        moraCobradaHistorial: 32700,
        ahoraAr: DateTime(2026, 7, 7),
      );
      expect(moraJul7, closeTo(0, 0.01));

      // Jul 31: último día exento → $0
      final moraJul31 = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato,
        moraCobradaHistorial: 32700,
        ahoraAr: DateTime(2026, 7, 31),
      );
      expect(moraJul31, closeTo(0, 0.01));

      // Ago 1: exención venció. Cuotas 2,3,4 vencen antes de jul-31 →
      // cada una cuenta desde jul-31. 1 día × $300 × 3 cuotas = $900.
      final moraAgo1 = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato,
        moraCobradaHistorial: 32700,
        ahoraAr: DateTime(2026, 8, 1),
      );
      expect(moraAgo1, closeTo(900, 0.01));
    });

    test('Espíndola: abono+mora Abr/May → permanente; al 9-jul solo C3', () {
      // Inscripción 31-mar → C1 Abr, C2 May, C3 Jun.
      // 27-jun: abono + mora Abr+May → exención 30-jun, reinicia=false.
      // Al 9-jul: Abr/May omitidos; C3 = 9 días × $350 = $3.150.
      final contrato = ContratoAlumno(
        id: 'espindola',
        eventoId: 'evt',
        nombreAlumno: 'ESPINDOLA, BENJAMIN TOMAS',
        cantidadAcompanantes: 0,
        montoTotalPactado: 315000,
        saldoDeudor: 284750,
        cuotasPagadas: 0,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 31, 3, 0, 0),
        moraPendienteTracked: 0,
        moraCobradaOffset: 29750,
        moraExentaHasta: DateTime(2026, 6, 30),
        moraExencionReinicia: false,
      );

      final desglose = MoraCuotaCalculator.calcularDesglose(
        contrato,
        DateTime(2026, 7, 9),
      );
      expect(desglose.length, 1);
      expect(desglose.first.numeroCuota, 3);
      expect(desglose.first.diasMora, 9);
      expect(desglose.first.interesBruto, closeTo(3150, 0.01));

      final operativa = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato,
        moraCobradaHistorial: 29750,
        ahoraAr: DateTime(2026, 7, 9),
      );
      expect(operativa, closeTo(3150, 0.01));
    });

    test('Sin exención, mora sigue acumulando desde vencimiento original', () {
      final contrato = ContratoAlumno(
        id: 'sin-exencion',
        eventoId: 'evt',
        nombreAlumno: 'TEST',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 1,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
      );

      // Jul 7 sin exención: cuota 2 vence 31-may (37 días), cuota 3 vence 30-jun (7 días).
      final mora = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato,
        moraCobradaHistorial: 0,
        ahoraAr: DateTime(2026, 7, 7),
      );
      // 37×300 + 7×300 = 11100 + 2100 = 13200
      expect(mora, closeTo(13200, 0.01));
    });
  });

  group('MoraCuotaCalculator.remanenteTrackedNeto (legacy compat)', () {
    test('tracked e historial iguales → remanente 0', () {
      expect(
        MoraCuotaCalculator.remanenteTrackedNeto(
          moraPendienteTracked: 7800,
          moraCobradaHistorial: 7800,
        ),
        closeTo(0, 0.01),
      );
    });

    test('sin historial: remanente = tracked', () {
      expect(
        MoraCuotaCalculator.remanenteTrackedNeto(
          moraPendienteTracked: 7800,
          moraCobradaHistorial: 0,
        ),
        closeTo(7800, 0.01),
      );
    });

    test('carry-over pagado (offset=0): remanente 0', () {
      expect(
        MoraCuotaCalculator.remanenteTrackedNeto(
          moraPendienteTracked: 230,
          moraCobradaHistorial: 230,
        ),
        closeTo(0, 0.01),
      );
    });
  });

  group('MoraTrackedRecovery.objetivoDesdeHistorial (v51)', () {
    final contratoBaseToledo = ContratoAlumno(
      id: 'toledo',
      eventoId: 'evt',
      nombreAlumno: 'TOLEDO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 210000,
      cuotasPagadas: 2,
      totalCuotas: 9,
      moraPendienteTracked: 9800,
      moraCobradaOffset: 0,
      createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
    );

    final pagosToledoMoraCompleta = [
      {
        'fecha_pago': '2026-04-10',
        'monto': 30000.0,
        'concepto': 'Cuota base 1',
        'anulado': 0,
        'line_kind': null,
      },
      {
        'fecha_pago': '2026-05-10',
        'monto': 30000.0,
        'concepto': 'Cuota base 2',
        'anulado': 0,
        'line_kind': null,
      },
      {
        'fecha_pago': '2026-05-10',
        'monto': 10150.0,
        'concepto': 'Interés mora',
        'anulado': 0,
        'line_kind': 'interes_mora',
      },
    ];

    test('TOLEDO: cuota 2 + mora parcial → tracked remanente cuota 2 neto', () {
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: contratoBaseToledo,
        pagos: pagosToledoMoraCompleta,
      );
      // Abr: cuota 1 sin mora → tracked mora cuota 1 (~$3000 al 10-abr).
      // May: cuota 2 + mora $10150; mora neta cuota 2 al 10-may < $10150 → tracked 0.
      expect(obj.tracked, closeTo(0, 0.01));
      expect(obj.offset, closeTo(10150, 0.01));
    });

    test('post-reconcile TOLEDO: mora pendiente = desglose vivo + tracked', () {
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: contratoBaseToledo,
        pagos: pagosToledoMoraCompleta,
      );
      final c = contratoBaseToledo.copyWith(
        moraPendienteTracked: obj.tracked,
        moraCobradaOffset: obj.offset,
      );
      final ahoraAr = DateTime(2026, 6, 29);
      final desglose = MoraCuotaCalculator.calcularDesglose(c, ahoraAr);
      final desgloseNeto = MoraCuotaCalculator.desglosePendiente(
        desglose,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: 10150,
          moraCobradaOffset: obj.offset,
        ),
      );
      final r = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 10150,
        ahoraAr: ahoraAr,
      );
      final sumDesglose =
          desgloseNeto.fold<double>(0, (s, d) => s + d.interesBruto);
      expect(r, closeTo(sumDesglose + obj.tracked, 0.01));
    });

    test('remanente parcial legítimo: usa sim, no tracked stale', () {
      final pagos = [
        {
          'fecha_pago': '2026-05-15',
          'monto': 30000.0,
          'concepto': 'Cuota base 1',
          'anulado': 0,
          'line_kind': null,
        },
        {
          'fecha_pago': '2026-05-15',
          'monto': 1500.0,
          'concepto': 'Interés mora cuota 1',
          'anulado': 0,
          'line_kind': 'interes_mora',
        },
      ];
      final c = ContratoAlumno(
        id: 'parcial',
        eventoId: 'evt',
        nombreAlumno: 'Parcial',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        moraPendienteTracked: 9999,
        moraCobradaOffset: 0,
        createdAt: DateTime.utc(2026, 3, 1, 3, 0, 0),
      );
      final esperado = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: c.copyWith(
          moraPendienteTracked: 0,
          moraCobradaOffset: 0,
        ),
        pagos: pagos,
      );
      expect(esperado.tracked, greaterThan(0.01));
      expect(esperado.offset, closeTo(1500, 0.01));

      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: c,
        pagos: pagos,
      );
      expect(obj.tracked, closeTo(esperado.tracked, 0.01));
      expect(obj.offset, closeTo(esperado.offset, 0.01));
      expect(obj.tracked, isNot(closeTo(9999, 0.01)));
    });

    test('tracked inflado sin historial mora → 0 vía replay', () {
      final c = contratoBaseToledo.copyWith(moraPendienteTracked: 9800);
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: c,
        pagos: const [],
      );
      expect(obj.tracked, closeTo(0, 0.01));
      expect(obj.offset, closeTo(0, 0.01));
    });
  });

  group('MoraTrackedRecovery.necesitaReconciliar (v53)', () {
    final contratoDeCarlo = ContratoAlumno(
      id: 'de-carlo',
      eventoId: 'evt',
      nombreAlumno: 'DE CARLO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 210000,
      cuotasPagadas: 2,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 23, 12, 16, 15),
    );

    final pagosCuotaSinMora = [
      {
        'fecha_pago': '2026-05-28',
        'monto': 60000.0,
        'concepto': '2 Cuotas (Cuota Base)',
        'anulado': 0,
        'line_kind': null,
      },
    ];

    test('cuota base sin mora en historial → sí reconciliar', () {
      expect(
        MoraTrackedRecovery.necesitaReconciliar(
          contratoDeCarlo,
          pagosCuotaSinMora,
        ),
        isTrue,
      );
      final obj = MoraTrackedRecovery.objetivoDesdeHistorial(
        contrato: contratoDeCarlo,
        pagos: pagosCuotaSinMora,
      );
      expect(obj.tracked, closeTo(8400, 0.01));
    });

    test('sin pagos ni tracked → no reconciliar', () {
      final c = contratoDeCarlo.copyWith(
        cuotasPagadas: 0,
        moraPendienteTracked: 0,
        moraCobradaOffset: 0,
      );
      expect(MoraTrackedRecovery.necesitaReconciliar(c, const []), isFalse);
    });
  });

  group('resolverExencionPreservandoLocal (perdón admin)', () {
    test('sin historial conserva exención admin permanente', () {
      final r = MoraTrackedRecovery.resolverExencionPreservandoLocal(
        localHasta: DateTime(2026, 7, 31),
        localReinicia: false,
        desdeHistorial: null,
      );
      expect(r.escribir, isFalse);
      expect(r.reinicia, isFalse);
      expect(r.hasta, DateTime(2026, 7, 31));
    });

    test('no acorta fecha local más lejana que historial', () {
      final r = MoraTrackedRecovery.resolverExencionPreservandoLocal(
        localHasta: DateTime(2026, 7, 31),
        localReinicia: false,
        desdeHistorial: (hasta: DateTime(2026, 6, 30), reinicia: true),
      );
      expect(r.escribir, isFalse);
      expect(r.hasta, DateTime(2026, 7, 31));
      expect(r.reinicia, isFalse);
    });

    test('historial más lejano extiende sin forzar reinicia=true', () {
      final r = MoraTrackedRecovery.resolverExencionPreservandoLocal(
        localHasta: DateTime(2026, 6, 30),
        localReinicia: false,
        desdeHistorial: (hasta: DateTime(2026, 7, 31), reinicia: true),
      );
      expect(r.escribir, isTrue);
      expect(r.hasta, DateTime(2026, 7, 31));
      expect(r.reinicia, isFalse);
    });

    test('sin local aplica historial', () {
      final r = MoraTrackedRecovery.resolverExencionPreservandoLocal(
        localHasta: null,
        localReinicia: true,
        desdeHistorial: (hasta: DateTime(2026, 7, 31), reinicia: true),
      );
      expect(r.escribir, isTrue);
      expect(r.hasta, DateTime(2026, 7, 31));
      expect(r.reinicia, isTrue);
    });
  });

  group('simularPerdonMora (exención sin Reg)', () {
    final contrato = ContratoAlumno(
      id: 'perdon-test',
      eventoId: 'evt',
      nombreAlumno: 'TEST PERDON',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 270000,
      cuotasPagadas: 0,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 31, 3, 0, 0),
      moraPendienteTracked: 0,
      moraCobradaOffset: 0,
    );

    test('prefijo normaliza selección a cuotas ≤ max pedida', () {
      expect(
        MoraCuotaCalculator.normalizarSeleccionPerdonPrefijo(
          disponibles: {1, 2, 3},
          pedidas: {2},
        ),
        {1, 2},
      );
    });

    test('perdonar todo → fin de mes, reinicia=false, Reg intacto', () {
      final hoy = DateTime(2026, 7, 9);
      final bruto = MoraCuotaCalculator.calcularDesglose(contrato, hoy);
      expect(bruto.length, greaterThanOrEqualTo(2));
      final nums = bruto.map((d) => d.numeroCuota).toSet();
      final sim = MoraCuotaCalculator.simularPerdonMora(
        contrato: contrato,
        numerosCuotaSeleccionados: nums,
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
      );
      expect(sim, isNotNull);
      expect(sim!.cubreHastaFinDeMes, isTrue);
      expect(sim.exentaHasta, DateTime(2026, 7, 31));
      expect(sim.moraExencionReinicia, isFalse);
      expect(sim.moraOperativaPost, closeTo(0, 0.01));
      expect(
        MoraCuotaCalculator.payloadPerdonMora(sim).containsKey('created_at'),
        isFalse,
      );
    });

    test('perdonar solo prefijo Abr deja mora de cuotas posteriores', () {
      final hoy = DateTime(2026, 7, 9);
      final bruto = MoraCuotaCalculator.calcularDesglose(contrato, hoy);
      expect(bruto.first.numeroCuota, 1);
      final sim = MoraCuotaCalculator.simularPerdonMora(
        contrato: contrato,
        numerosCuotaSeleccionados: {1},
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
      );
      expect(sim, isNotNull);
      expect(sim!.cubreHastaFinDeMes, isFalse);
      expect(sim.aplicaExencion, isTrue);
      expect(sim.cuotasPerdonadas.map((d) => d.numeroCuota), [1]);
      expect(sim.cuotasRestantes, isNotEmpty);
      expect(sim.moraOperativaPost, greaterThan(0.01));
      // Tras aplicar, Abr no aparece; posteriores sí.
      final post = contrato.copyWith(
        moraExentaHasta: sim.exentaHasta,
        moraExencionReinicia: false,
      );
      final desglosePost =
          MoraCuotaCalculator.calcularDesglose(post, hoy);
      expect(desglosePost.any((d) => d.numeroCuota == 1), isFalse);
      expect(desglosePost, isNotEmpty);
    });

    test('solo ficha (tracked) no escribe exención y deja calendario', () {
      final hoy = DateTime(2026, 7, 10);
      // Como Aranda: 2/9, C3 vencida + tracked de cobros sin mora.
      final aranda = ContratoAlumno(
        id: 'aranda',
        eventoId: 'evt',
        nombreAlumno: 'ARANDA',
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 280000,
        cuotasPagadas: 2,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
        moraPendienteTracked: 8800,
        moraCobradaOffset: 0,
      );
      final sim = MoraCuotaCalculator.simularPerdonMora(
        contrato: aranda,
        numerosCuotaSeleccionados: const {},
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
        incluirTracked: true,
      );
      expect(sim, isNotNull);
      expect(sim!.soloTracked, isTrue);
      expect(sim.aplicaExencion, isFalse);
      expect(sim.incluyeTracked, isTrue);
      expect(sim.trackedPost, 0);
      expect(sim.montoPerdonado, closeTo(8800, 0.01));
      // Calendario C3 (~10d × $400) sigue vivo.
      expect(sim.moraOperativaPost, closeTo(4000, 0.01));
      expect(sim.cuotasRestantes, isNotEmpty);
      expect(sim.cuotasRestantes.first.numeroCuota, 3);

      final payload = MoraCuotaCalculator.payloadPerdonMora(sim);
      expect(payload['mora_pendiente_tracked'], 0.0);
      expect(payload.containsKey('mora_exenta_hasta'), isFalse);
      expect(payload.containsKey('mora_exencion_reinicia'), isFalse);
    });

    test('cuotas + ficha limpia tracked aunque queden cuotas', () {
      final hoy = DateTime(2026, 7, 10);
      final c = ContratoAlumno(
        id: 'mix',
        eventoId: 'evt',
        nombreAlumno: 'MIX',
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 280000,
        cuotasPagadas: 2,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
        moraPendienteTracked: 8800,
      );
      // Sin cuotas seleccionadas no aplica; con C3 + tracked:
      final bruto = MoraCuotaCalculator.calcularDesglose(c, hoy);
      final nums = bruto.map((d) => d.numeroCuota).toSet();
      final sim = MoraCuotaCalculator.simularPerdonMora(
        contrato: c,
        numerosCuotaSeleccionados: nums,
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
        incluirTracked: true,
      );
      expect(sim, isNotNull);
      expect(sim!.incluyeTracked, isTrue);
      expect(sim.trackedPost, 0);
      expect(sim.aplicaExencion, isTrue);
      expect(sim.moraOperativaPost, closeTo(0, 0.01));
    });

    test('prefijo sin incluir tracked conserva ficha', () {
      final hoy = DateTime(2026, 7, 10);
      final c = ContratoAlumno(
        id: 'keep-tr',
        eventoId: 'evt',
        nombreAlumno: 'KEEP',
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 280000,
        cuotasPagadas: 2,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
        moraPendienteTracked: 8800,
      );
      final sim = MoraCuotaCalculator.simularPerdonMora(
        contrato: c,
        numerosCuotaSeleccionados: {3},
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
        incluirTracked: false,
      );
      expect(sim, isNotNull);
      expect(sim!.incluyeTracked, isFalse);
      expect(sim.trackedPost, closeTo(8800, 0.01));
      expect(sim.aplicaExencion, isTrue);
      // Solo queda tracked como mora operativa.
      expect(sim.moraOperativaPost, closeTo(8800, 0.01));
    });

    test('modos masivos: completo escribe exención; solo ficha no', () {
      final hoy = DateTime(2026, 7, 10);
      final c = ContratoAlumno(
        id: 'bulk-modes',
        eventoId: 'evt',
        nombreAlumno: 'BULK',
        cantidadAcompanantes: 0,
        montoTotalPactado: 360000,
        saldoDeudor: 280000,
        cuotasPagadas: 2,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
        moraPendienteTracked: 5000,
      );
      final bruto = MoraCuotaCalculator.calcularDesglose(c, hoy);
      final nums = bruto.map((d) => d.numeroCuota).toSet();

      final completo = MoraCuotaCalculator.simularPerdonMora(
        contrato: c,
        numerosCuotaSeleccionados: nums,
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
        incluirTracked: true,
      );
      expect(completo, isNotNull);
      expect(completo!.montoPerdonado, greaterThan(0.01));
      final payloadCompleto =
          MoraCuotaCalculator.payloadPerdonMora(completo);
      expect(payloadCompleto.containsKey('mora_exenta_hasta'), isTrue);
      expect(payloadCompleto['mora_exencion_reinicia'], 0);
      expect(payloadCompleto['mora_pendiente_tracked'], 0.0);

      final soloFicha = MoraCuotaCalculator.simularPerdonMora(
        contrato: c,
        numerosCuotaSeleccionados: const {},
        moraCobradaHistorial: 0,
        ahoraAr: hoy,
        incluirTracked: true,
      );
      expect(soloFicha, isNotNull);
      expect(soloFicha!.soloTracked, isTrue);
      expect(soloFicha.montoPerdonado, greaterThan(0.01));
      final payloadFicha = MoraCuotaCalculator.payloadPerdonMora(soloFicha);
      expect(payloadFicha.containsKey('mora_exenta_hasta'), isFalse);
      expect(payloadFicha['mora_pendiente_tracked'], 0.0);
    });
  });

  group('Baja temporal — mora congelada (v52)', () {
    final contratoConDeuda = ContratoAlumno(
      id: 'freeze',
      eventoId: 'evt',
      nombreAlumno: 'ALUMNA TEST',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 270000,
      cuotasPagadas: 0,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 1, 1, 3, 0, 0),
    );

    test('fechaEfectivaMoraAr sin referencia usa el día pasado', () {
      final c = contratoConDeuda;
      final dia = DateTime(2026, 7, 15);
      expect(
        MoraCuotaCalculator.fechaEfectivaMoraAr(c, dia),
        DateTime(2026, 7, 15),
      );
    });

    test('fechaEfectivaMoraAr con referencia ignora hoy real', () {
      final c = contratoConDeuda.copyWith(
        moraFechaReferencia: DateTime(2026, 6, 30),
      );
      expect(
        MoraCuotaCalculator.fechaEfectivaMoraAr(c, DateTime(2026, 7, 20)),
        DateTime(2026, 6, 30),
      );
    });

    test('mora congelada no crece entre día de baja y 20 días después', () {
      final c = contratoConDeuda.copyWith(
        moraFechaReferencia: DateTime(2026, 6, 30),
      );
      final alBaja = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
        ahoraAr: DateTime(2026, 6, 30),
      );
      final simJul20 = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: c,
        moraCobradaHistorial: 0,
        ahoraAr: DateTime(2026, 7, 20),
      );
      expect(simJul20, closeTo(alBaja, 0.01));
      expect(alBaja, greaterThan(0.01));

      final sinFreeze = c.copyWith(moraFechaReferencia: null);
      final jul20Vivo = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: sinFreeze,
        moraCobradaHistorial: 0,
        ahoraAr: DateTime(2026, 7, 20),
      );
      expect(jul20Vivo, greaterThan(alBaja + 0.01));
    });

    test('debeDescongelar cuando mora operativa queda en cero', () {
      final c = contratoConDeuda.copyWith(
        moraFechaReferencia: DateTime(2026, 6, 30),
      );
      expect(
        MoraCuotaCalculator.debeDescongelarMoraReferencia(
          contrato: c,
          moraPendienteOperativaPost: 0,
          saldoDeudorPost: 100000,
        ),
        isTrue,
      );
      expect(
        MoraCuotaCalculator.debeDescongelarMoraReferencia(
          contrato: c,
          moraPendienteOperativaPost: 5000,
          saldoDeudorPost: 0,
        ),
        isTrue,
      );
      expect(
        MoraCuotaCalculator.debeDescongelarMoraReferencia(
          contrato: c,
          moraPendienteOperativaPost: 5000,
          saldoDeudorPost: 100000,
        ),
        isFalse,
      );
    });

    test('sin moraFechaReferencia no descongela', () {
      final c = contratoConDeuda;
      expect(
        MoraCuotaCalculator.debeDescongelarMoraReferencia(
          contrato: c,
          moraPendienteOperativaPost: 0,
          saldoDeudorPost: 0,
        ),
        isFalse,
      );
    });
  });
}
