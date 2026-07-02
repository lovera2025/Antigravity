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

    test('cuota sin mora con remanente previo → tracked = mora neta de la cuota', () {
      final desgloseNetoCuota1 = [
        MoraCuotaDetalle(
          numeroCuota: 1,
          vencimiento: DateTime(2026, 3, 31),
          diasMora: 90,
          interesBruto: 3700,
          mesLabel: 'Mar 2026',
        ),
      ];
      final r = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 3700,
        moraCobradaOffsetActual: 5000,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 1,
        moraDesglosePreCobro: desgloseCuota1,
        moraDesgloseNetoPreCobro: desgloseNetoCuota1,
        moraDesgloseNetoTotal: 3700,
      );
      expect(r.tracked, closeTo(3700, 0.01));
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
      );
      expect(r.tracked, closeTo(0, 0.01));
      expect(r.offset, closeTo(0, 0.01));
    });

    test('Borda: cuota 2 sin mora no arrastra mora de cuota 1 pagada', () {
      // Inscripción 25-mar-2026; cuota 1 cobrada 20-may con mora parcial $300;
      // cuota 2 cobrada 30-jun sin mora → tracked ≈ mora neta cuota 2 solamente.
      final contratoBase = ContratoAlumno(
        id: 'borda',
        eventoId: 'evt',
        nombreAlumno: 'BORDA, LUDMILA AILEN',
        cantidadAcompanantes: 0,
        montoTotalPactado: 270000,
        saldoDeudor: 240000,
        cuotasPagadas: 0,
        totalCuotas: 9,
        createdAt: DateTime.utc(2026, 3, 25, 10, 20, 40),
      );
      final pagos = <Map<String, dynamic>>[
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
          'fecha_pago': '2026-06-30T22:46:35.070075+00:00',
          'concepto': 'Cuota Base (2/9)',
          'monto': 30000.0,
          'monto_gross': 30000.0,
          'anulado': 0,
        },
      ];
      final resultado = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contratoBase,
        pagos: pagos,
      );
      // 30 días × $300/día = $9000 (cuota 2 al 30-jun); tolerancia ±$300.
      expect(resultado.tracked, closeTo(8700, 300));
      expect(resultado.offset, closeTo(300, 0.01));
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
