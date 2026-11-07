import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_congelada.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_recovery.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// La mora cobrada **por adelantado** de una cuota que no se completa no se
/// vuelve a pedir (6-nov-2026, `docs/PLAN_MORA_ADELANTADA_2026-11-06.md`).
///
/// LOPEZ, MORENA AILEN (contrato 31f442c5…, GREGORIA MORALES) pagó el 6/11 la
/// cuota 2 completa, la 3, $9.100 a cuenta de la 4 y $130.900 de mora de las
/// cuotas 2, 3 y 4. Se cerraron la 2 y la 3 ($98.000 de mora); los $32.900 de
/// la 4 fueron un adelanto. El "ya usado" (`mora_cobrada_offset`) se quedaba
/// con los $130.900 enteros, el crédito de la 4 desaparecía y la app le volvía
/// a pedir esa mora: $268.100 en vez de $235.200.
///
/// La regla que tiene que cumplirse después de cualquier cobro:
/// `historial − offset` (el crédito FIFO) es exactamente la mora pagada por
/// adelantado de las cuotas que **siguen abiertas**. Ni más ni menos.
///
/// Los números de Morena salen de la nube (6-nov, solo lectura). Cuota base
/// $35.000 → $350 por día. Mora congelada "Todas" desde el 2/11.
void main() {
  tearDown(MoraCongelada.vaciar);

  const idMorena = '31f442c5-de9d-479b-842d-e8ecd1baeb91';
  final congeladaDesdeEl2 = MoraCongelada([PausaMora(desde: DateTime(2026, 11, 2))]);

  ContratoAlumno morena({
    double saldoDeudor = 200900,
    int cuotasPagadas = 0,
    double tracked = 0,
    double offset = 0,
  }) =>
      ContratoAlumno(
        id: idMorena,
        eventoId: 'evt',
        nombreAlumno: 'LOPEZ, MORENA AILEN',
        cantidadAcompanantes: 0,
        montoTotalPactado: 315000,
        saldoDeudor: saldoDeudor,
        cuotasPagadas: cuotasPagadas,
        totalCuotas: 9,
        moraPendienteTracked: tracked,
        moraCobradaOffset: offset,
        createdAt: DateTime.utc(2026, 3, 30, 3, 0, 0),
      );

  /// Los seis pagos de Morena, tal cual están en la nube (sin `line_kind`: la
  /// mora se reconoce por el concepto, como en las PCs).
  List<Map<String, dynamic>> pagosMorena() => [
        {
          'fecha_pago': '2026-04-16T20:15:13.117227+00:00',
          'concepto': 'Cuota Base (1/9)',
          'monto': 35000.0,
          'monto_gross': 35000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-11-02T19:14:07.795986+00:00',
          'concepto': 'Entrega parcial — Cuota Base (2/9)',
          'monto': 10000.0,
          'monto_gross': 10000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-11-06T21:34:23.970849+00:00',
          'concepto': 'Cuota Base (2/9) — Completada',
          'monto': 25000.0,
          'monto_gross': 25000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-11-06T21:34:23.977842+00:00',
          'concepto': 'Cuota Base (3/9)',
          'monto': 35000.0,
          'monto_gross': 35000.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-11-06T21:34:23.979837+00:00',
          'concepto': 'Entrega parcial — Cuota Base (4/9)',
          'monto': 9100.0,
          'monto_gross': 9100.0,
          'anulado': 0,
        },
        {
          'fecha_pago': '2026-11-06T21:34:23.981838+00:00',
          'concepto': 'Interés mora cuotas 2, 3, 4 (vto May, Jun, Jul)',
          'monto': 130900.0,
          'monto_gross': 130900.0,
          'anulado': 0,
        },
      ];

  /// El 7.º pago del caso 3: completa la cuota 4, sin mora.
  Map<String, dynamic> completaLaCuota4() => {
        'fecha_pago': '2026-11-10T15:00:00.000000+00:00',
        'concepto': 'Cuota Base (4/9) — Completada',
        'monto': 25900.0,
        'monto_gross': 25900.0,
        'anulado': 0,
      };

  MoraCuotaDetalle cuota(int n, double interes) => MoraCuotaDetalle(
        numeroCuota: n,
        vencimiento: DateTime(2026, 3 + n + 1, 0),
        diasMora: (interes / 350).round(),
        interesBruto: interes,
        mesLabel: 'C$n',
      );

  /// La mora de Morena al 6/11 con los días hasta el 2/11 (la tabla del caso).
  final desgloseMorena6Nov = [
    cuota(2, 54250),
    cuota(3, 43750),
    cuota(4, 32900),
    cuota(5, 22050),
    cuota(6, 11550),
    cuota(7, 700),
  ];
  double suma(List<MoraCuotaDetalle> d) =>
      d.fold<double>(0, (s, x) => s + x.interesBruto);

  /// El offset nunca puede superar lo cobrado: si lo supera, se "usó" mora
  /// que nadie pagó y el FIFO queda en negativo para siempre.
  void expectNoSuperaLoCobrado(
    EstadoMoraPostCobro e, {
    required double historialPre,
    required double moraEsteCobro,
  }) {
    expect(
      e.offset,
      lessThanOrEqualTo(historialPre + moraEsteCobro + 0.01),
      reason: 'el "ya usado" no puede pasar de lo cobrado',
    );
  }

  group('Morena, la función sola', () {
    test('1. se cierran la 2 y la 3: el offset se queda con \$98.000, no con los \$130.900', () {
      // El desglose de la tabla es el mismo que da la calculadora con la pausa.
      final real = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraCuotaCalculator.calcularDesglose(
          morena(cuotasPagadas: 1),
          DateTime(2026, 11, 6, 18, 34),
        ),
      );
      expect(real.map((d) => d.interesBruto), desgloseMorena6Nov.map((d) => d.interesBruto));
      expect(suma(real), closeTo(165200, 0.01));

      final e = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 130900,
        cuotasBaseLiquidadasEnCobro: 2,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: desgloseMorena6Nov,
        moraDesgloseNetoPreCobro: desgloseMorena6Nov,
        moraDesgloseNetoTotal: 165200,
        saldoDeudorPost: 200900,
        fechaCobroAr: DateTime(2026, 11, 6),
        exencionActual: null,
        reiniciaActual: true,
        moraCobradaHistorialPreCobro: 0,
      );
      expect(e.offset, closeTo(98000, 0.01),
          reason: 'los \$32.900 de la cuota 4 son un adelanto: quedan como crédito');
      expect(e.tracked, closeTo(0, 0.01));
      expect(e.exentaHasta, isNull, reason: 'no saldó toda la mora: faltan la 5, la 6 y la 7');
      expectNoSuperaLoCobrado(e, historialPre: 0, moraEsteCobro: 130900);

      // Lo que la app le pide después: la 5, la 6 y la 7. La 4 la cubre el crédito.
      final despues = e.aplicarA(morena(cuotasPagadas: 3), moraFechaReferencia: null);
      final mora = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraCuotaCalculator.moraPendienteOperativa(
          contrato: despues,
          moraCobradaHistorial: 130900,
          ahoraAr: DateTime(2026, 11, 6),
        ),
      );
      expect(mora, closeTo(34300, 0.01), reason: '\$200.900 + \$34.300 = \$235.200');
    });
  });

  group('Morena, el repaso de su historial', () {
    test('2. con sus seis pagos y la mora congelada queda en \$98.000 y \$34.300', () {
      final pagos = pagosMorena();
      final r = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraTrackedRecovery.recomputarDesdeHistorial(
          contratoBase: morena(),
          pagos: pagos,
        ),
      );
      expect(r.offset, closeTo(98000, 0.01));
      expect(r.tracked, closeTo(0, 0.01));

      final historial = MoraTrackedRecovery.moraCobradaDelHistorial(pagos);
      expect(historial, closeTo(130900, 0.01));
      final mora = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraCuotaCalculator.moraPendienteOperativa(
          contrato: morena(cuotasPagadas: 3, tracked: r.tracked, offset: r.offset),
          moraCobradaHistorial: historial,
          ahoraAr: DateTime(2026, 11, 6),
        ),
      );
      expect(mora, closeTo(34300, 0.01));
    });

    test('3. cuando completa la 4 sin mora, el crédito se usa en la 4 y no pasa a la 5', () {
      final pagos = [...pagosMorena(), completaLaCuota4()];
      final r = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraTrackedRecovery.recomputarDesdeHistorial(
          contratoBase: morena(saldoDeudor: 175000),
          pagos: pagos,
        ),
      );
      expect(r.offset, closeTo(130900, 0.01),
          reason: 'la mora de la 4 ya estaba pagada: todo lo cobrado queda usado');
      expect(r.tracked, closeTo(0, 0.01),
          reason: 'la 4 se cierra sin deber mora: no se le vuelve a pedir');

      final mora = MoraCongelada.conPausas(
        idMorena,
        congeladaDesdeEl2,
        () => MoraCuotaCalculator.moraPendienteOperativa(
          contrato: morena(
            saldoDeudor: 175000,
            cuotasPagadas: 4,
            tracked: r.tracked,
            offset: r.offset,
          ),
          moraCobradaHistorial: MoraTrackedRecovery.moraCobradaDelHistorial(pagos),
          ahoraAr: DateTime(2026, 11, 10),
        ),
      );
      expect(mora, closeTo(22050 + 11550 + 700, 0.01),
          reason: 'la 5, la 6 y la 7 enteras: el crédito de la 4 no se descuenta de la 5');
    });
  });

  group('la función, después del adelanto', () {
    test('4. descongelada: de la 4 quedan solo los días nuevos', () {
      // Desde el estado del caso 1 (offset 98.000, historial 130.900), la mora
      // corrió 8 días más ($2.800 por cuota) y la familia completa la 4 sin
      // pagar mora.
      final bruto = [
        cuota(4, 32900 + 2800),
        cuota(5, 22050 + 2800),
        cuota(6, 11550 + 2800),
        cuota(7, 700 + 2800),
      ];
      final neto = MoraCuotaCalculator.desglosePendiente(
        bruto,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: 130900,
          moraCobradaOffset: 98000,
        ),
      );
      expect(neto.first.numeroCuota, 4);
      expect(neto.first.interesBruto, closeTo(2800, 0.01));

      final e = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 98000,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 4,
        moraDesglosePreCobro: bruto,
        moraDesgloseNetoPreCobro: neto,
        moraDesgloseNetoTotal: suma(neto),
        saldoDeudorPost: 175000,
        fechaCobroAr: DateTime(2026, 11, 14),
        exencionActual: null,
        reiniciaActual: true,
        moraCobradaHistorialPreCobro: 130900,
      );
      expect(e.tracked, closeTo(2800, 0.01), reason: 'solo los días nuevos de la 4');
      expect(e.offset, closeTo(130900, 0.01), reason: 'el crédito se gastó en la 4');
      expectNoSuperaLoCobrado(e, historialPre: 130900, moraEsteCobro: 0);
    });

    test('5. mora parcial sobre una cuota que después se completa: no se descuenta de la siguiente', () {
      // El segundo problema: paga $15.000 de mora sobre la 3 ($20.000) sin
      // completarla, y después completa la 3 sin mora. Esos $15.000 no pueden
      // volver a descontarse de la 4.
      final bruto = [cuota(3, 20000), cuota(4, 25000)];

      final a = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 15000,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 2,
        moraDesglosePreCobro: bruto,
        moraDesgloseNetoPreCobro: bruto,
        moraDesgloseNetoTotal: 45000,
        saldoDeudorPost: 200000,
        fechaCobroAr: DateTime(2026, 8, 6),
        exencionActual: null,
        reiniciaActual: true,
        moraCobradaHistorialPreCobro: 0,
      );
      expect(a.offset, closeTo(0, 0.01), reason: 'un pago parcial se acredita por FIFO');
      expect(a.tracked, closeTo(0, 0.01));

      final neto = MoraCuotaCalculator.desglosePendiente(bruto, 15000);
      final b = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: a.tracked,
        moraCobradaOffsetActual: a.offset,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 1,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: bruto,
        moraDesgloseNetoPreCobro: neto,
        moraDesgloseNetoTotal: suma(neto),
        saldoDeudorPost: 165000,
        fechaCobroAr: DateTime(2026, 8, 10),
        exencionActual: a.exentaHasta,
        reiniciaActual: a.reinicia,
        moraCobradaHistorialPreCobro: 15000,
      );
      expect(b.tracked, closeTo(5000, 0.01), reason: 'lo que faltaba de la 3');
      expect(b.offset, closeTo(15000, 0.01), reason: 'los \$15.000 se usaron en la 3');
      expectNoSuperaLoCobrado(b, historialPre: 15000, moraEsteCobro: 0);

      final cuatro = MoraCuotaCalculator.desglosePendiente(
        [cuota(4, 25000)],
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: 15000,
          moraCobradaOffset: b.offset,
        ),
      );
      expect(suma(cuatro), closeTo(25000, 0.01), reason: 'la 4 se cobra entera');
    });

    test('6. si el adelanto cubre todas las abiertas, entra entero y la eximición es la de siempre', () {
      final e = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: 0,
        moraCobradaOffsetActual: 0,
        moraEsteCobro: 165200,
        cuotasBaseLiquidadasEnCobro: 2,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: desgloseMorena6Nov,
        moraDesgloseNetoPreCobro: desgloseMorena6Nov,
        moraDesgloseNetoTotal: 165200,
        saldoDeudorPost: 200900,
        fechaCobroAr: DateTime(2026, 11, 6),
        exencionActual: null,
        reiniciaActual: true,
        moraCobradaHistorialPreCobro: 0,
      );
      expect(e.offset, closeTo(165200, 0.01));
      expect(e.tracked, closeTo(0, 0.01));
      expect(e.exentaHasta, DateTime(2026, 11, 30));
      expect(e.reinicia, isTrue, reason: 'completó cuotas: la que venga vuelve a contar');
      expectNoSuperaLoCobrado(e, historialPre: 0, moraEsteCobro: 165200);
    });

    test('7. sin el desglose bruto la cuenta no puede trasladar el crédito: falla, no calla', () {
      expect(
        () => MoraCuotaCalculator.postCobroTrackedOffset(
          moraPendienteTrackedActual: 0,
          moraCobradaOffsetActual: 98000,
          moraEsteCobro: 0,
          cuotasBaseLiquidadasEnCobro: 1,
          cuotasBasePagadasPostCobro: 4,
          moraDesglosePreCobro: const [],
          moraDesgloseNetoPreCobro: [cuota(5, 22050)],
          moraDesgloseNetoTotal: 22050,
          saldoDeudorPost: 175000,
          fechaCobroAr: DateTime(2026, 11, 10),
          exencionActual: null,
          reiniciaActual: true,
          moraCobradaHistorialPreCobro: 130900,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('el segundo problema, con el historial entero', () {
    // Un alumno como Morena, sin nada congelado: paga la 1 y la 2 antes de que
    // venzan, el 15/08 paga $15.000 de mora sin completar la 3, y el 20/08
    // completa la 3 sin pagar mora.
    List<Map<String, dynamic>> pagos() => [
          {
            'fecha_pago': '2026-04-16T15:00:00+00:00',
            'concepto': 'Cuota Base (1/9)',
            'monto': 35000.0,
            'monto_gross': 35000.0,
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-05-20T15:00:00+00:00',
            'concepto': 'Cuota Base (2/9)',
            'monto': 35000.0,
            'monto_gross': 35000.0,
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-08-15T15:00:00+00:00',
            'concepto': 'Interés mora cuota 3 (vto Jun)',
            'monto': 15000.0,
            'monto_gross': 15000.0,
            'anulado': 0,
          },
          {
            'fecha_pago': '2026-08-20T15:00:00+00:00',
            'concepto': 'Cuota Base (3/9)',
            'monto': 35000.0,
            'monto_gross': 35000.0,
            'anulado': 0,
          },
        ];

    test('la 4 se cobra entera, y lo que falta de la 3 queda en la ficha', () {
      final contrato = morena(saldoDeudor: 210000);
      final r = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contrato,
        pagos: pagos(),
      );
      // Al 20/08 la 3 lleva 51 días ($17.850): $15.000 pagados, faltan $2.850.
      expect(r.tracked, closeTo(2850, 0.01));
      expect(r.offset, closeTo(15000, 0.01));

      final mora = MoraCuotaCalculator.moraPendienteOperativa(
        contrato: contrato.copyWith(
          cuotasPagadas: 3,
          moraPendienteTracked: r.tracked,
          moraCobradaOffset: r.offset,
        ),
        moraCobradaHistorial: 15000,
        ahoraAr: DateTime(2026, 8, 20),
      );
      // La 4 (vence 31/07) lleva 20 días: $7.000, enteros. Más los $2.850.
      expect(mora, closeTo(7000 + 2850, 0.01));
    });

    test('9. los orígenes de la ficha suman lo mismo que la ficha y nombran la 3', () {
      final contrato = morena(saldoDeudor: 210000);
      final r = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contrato,
        pagos: pagos(),
      );
      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos(),
        trackedMonto: r.tracked,
      );
      expect(origen, hasLength(1));
      expect(origen.single.numeroCuota, 3);
      expect(
        origen.fold<double>(0, (s, d) => s + d.montoAtribuido),
        closeTo(r.tracked, 0.01),
      );
    });
  });

  group('la costura para comparar reglas', () {
    test('10. sin cuenta da lo mismo que con la de la calculadora, y una cuenta distinta se nota', () {
      final pagos = pagosMorena();
      final sinNada = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: morena(),
        pagos: pagos,
      );
      final conLaDeSiempre = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: morena(),
        pagos: pagos,
        cuenta: MoraCuotaCalculator.postCobroTrackedOffset,
      );
      expect(conLaDeSiempre, sinNada);

      var llamadas = 0;
      EstadoMoraPostCobro unPeso({
        required double moraPendienteTrackedActual,
        required double moraCobradaOffsetActual,
        required double moraEsteCobro,
        required int cuotasBaseLiquidadasEnCobro,
        required int cuotasBasePagadasPostCobro,
        required List<MoraCuotaDetalle> moraDesglosePreCobro,
        required List<MoraCuotaDetalle> moraDesgloseNetoPreCobro,
        required double moraDesgloseNetoTotal,
        required double saldoDeudorPost,
        required DateTime? fechaCobroAr,
        required DateTime? exencionActual,
        required bool reiniciaActual,
        double? moraCobradaHistorialPreCobro,
      }) {
        llamadas++;
        return const EstadoMoraPostCobro(
          tracked: 0,
          offset: 1,
          exentaHasta: null,
          reinicia: true,
        );
      }

      final otra = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: morena(),
        pagos: pagos,
        cuenta: unPeso,
      );
      expect(otra.offset, 1);
      expect(llamadas, 3, reason: 'un lote por día: 16/04, 02/11 y 06/11');
    });
  });

  group('Morena sin nada congelado', () {
    test('9b. al completar la 4 la ficha queda con lo que faltaba de la 4, y el origen la nombra', () {
      // Sin la pausa, al 6/11 la mora es más ($173.600) y los $130.900 cubren
      // la 2 y la 3 ($100.800) y $30.100 de la 4. El 10/11 la 4 lleva 102 días
      // ($35.700): faltan $5.600.
      final pagos = [...pagosMorena(), completaLaCuota4()];
      final contrato = morena(saldoDeudor: 175000);
      final r = MoraTrackedRecovery.recomputarDesdeHistorial(
        contratoBase: contrato,
        pagos: pagos,
      );
      expect(r.tracked, closeTo(5600, 0.01));
      expect(r.offset, closeTo(130900, 0.01));

      final origen = MoraTrackedOrigen.inferir(
        contratoBase: contrato,
        pagos: pagos,
        trackedMonto: r.tracked,
      );
      expect(origen, hasLength(1));
      expect(origen.single.numeroCuota, 4);
      expect(
        origen.fold<double>(0, (s, d) => s + d.montoAtribuido),
        closeTo(r.tracked, 0.01),
      );
    });
  });
}
