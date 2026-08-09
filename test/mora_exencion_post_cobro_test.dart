import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// Regresión del recibo Nº 0661293D — BERNEL, LUCILA FATIMA, 07/08/2026 17:30.
///
/// El papel cobró $17.100 de mora (C2 $6.900 + C3 $8.100 de arrastre + C4
/// $2.100 del calendario, toda la que había) y en el mismo recibo imprimió
/// "TODAVÍA QUEDA MORA SIN PAGAR — $2.100 · Viene de: cuota 4 (Jul, 7 d)":
/// la misma mora que estaba cobrando dos renglones más arriba.
///
/// Causa: el número del aviso salía de un contrato simulado que llevaba el
/// tracked y el offset nuevos pero **no** la exención que ese mismo cobro
/// otorgaba. Y el offset no alcanza para borrar la cuota del calendario porque
/// sube junto con el historial: el crédito FIFO (`historial − offset`) queda
/// igual que antes del cobro.
///
/// Estos tests fijan que el estado post-cobro se calcule y se aplique completo.
void main() {
  // Reg 15/03/2026 → C1 vence 30/04, C2 31/05, C3 30/06, C4 31/07.
  // Plan $270.000 en 9 cuotas → cuota pura $30.000 → mora $300/día (1 %).
  ContratoAlumno bernel({
    double saldoDeudor = 180000,
    int cuotasPagadas = 3,
    double moraPendienteTracked = 15000,
    double moraCobradaOffset = 0,
    DateTime? moraExentaHasta,
    bool moraExencionReinicia = false,
  }) {
    return ContratoAlumno(
      id: 'bernel-test',
      eventoId: 'ev-test',
      nombreAlumno: 'BERNEL, LUCILA FATIMA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: saldoDeudor,
      cuotasPagadas: cuotasPagadas,
      totalCuotas: 9,
      createdAt: DateTime.utc(2026, 3, 15, 12),
      moraPendienteTracked: moraPendienteTracked,
      moraCobradaOffset: moraCobradaOffset,
      moraExentaHasta: moraExentaHasta,
      moraExencionReinicia: moraExencionReinicia,
    );
  }

  final hoy = DateTime(2026, 8, 7);

  group('BERNEL 07/08/2026 — cobro que salda toda la mora', () {
    test('el desglose pre-cobro es la cuota 4 con 7 días = \$2.100', () {
      final desglose = MoraCuotaCalculator.calcularDesglose(bernel(), hoy);

      expect(desglose.length, 1);
      expect(desglose.first.numeroCuota, 4);
      expect(desglose.first.diasMora, 7);
      expect(desglose.first.interesBruto, closeTo(2100, 0.01));
    });

    test('cobrar los \$17.100 deja la mora en cero, no en \$2.100', () {
      final contrato = bernel();
      final desgloseBruto = MoraCuotaCalculator.calcularDesglose(contrato, hoy);
      final desgloseNeto = MoraCuotaCalculator.desglosePendiente(
        desgloseBruto,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: 0,
          moraCobradaOffset: contrato.moraCobradaOffset,
        ),
      );
      final netoTotal =
          desgloseNeto.fold<double>(0, (s, d) => s + d.interesBruto);

      // C4 (2.100) + arrastre C2+C3 (15.000) = 17.100, lo que se cobró.
      expect(netoTotal + contrato.moraPendienteTracked, closeTo(17100, 0.01));

      final post = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: contrato.moraPendienteTracked,
        moraCobradaOffsetActual: contrato.moraCobradaOffset,
        moraEsteCobro: 17100,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: desgloseBruto,
        moraDesgloseNetoPreCobro: desgloseNeto,
        moraDesgloseNetoTotal: netoTotal,
        saldoDeudorPost: contrato.saldoDeudor,
        fechaCobroAr: hoy,
        exencionActual: contrato.moraExentaHasta,
        reiniciaActual: contrato.moraExencionReinicia,
      );

      expect(post.tracked, closeTo(0, 0.01));
      expect(post.exentaHasta, DateTime(2026, 8, 31));
      // Fue un cobro de sola mora: julio queda saldado para siempre.
      expect(post.reinicia, isFalse);

      // Lo que el recibo imprime en el aviso rojo.
      final detalle = MoraCuotaCalculator.moraPendienteOperativaDetallada(
        contrato: post.aplicarA(
          contrato,
          moraFechaReferencia: contrato.moraFechaReferencia,
        ),
        moraCobradaHistorial: 17100,
        ahoraAr: hoy,
      );

      expect(detalle.total, closeTo(0, 0.01));
      expect(detalle.desglose, isEmpty);
      expect(detalle.tracked, closeTo(0, 0.01));
    });

    test('sin la exención el aviso reclama la mora recién cobrada', () {
      // Reproduce el estado a medias que emitió el papel: tracked y offset
      // nuevos, exención vieja. Es el bug, y queda documentado como tal.
      final contrato = bernel();
      final aMedias = contrato.copyWith(
        moraPendienteTracked: 0,
        moraCobradaOffset: 17100,
      );

      final detalle = MoraCuotaCalculator.moraPendienteOperativaDetallada(
        contrato: aMedias,
        moraCobradaHistorial: 17100,
        ahoraAr: hoy,
      );

      // Los $2.100 de "cuota 4 (Jul, 7 d)" que salieron impresos.
      expect(detalle.total, closeTo(2100, 0.01));
      expect(detalle.desglose.single.numeroCuota, 4);
      expect(detalle.desglose.single.diasMora, 7);
    });

    test('la exención no depende de que el offset la tape', () {
      // El offset sube junto con el historial: el crédito FIFO queda igual que
      // antes del cobro. Si alguna vez se cambia esa regla, este test avisa.
      final contrato = bernel();
      final creditoAntes = MoraCuotaCalculator.moraCobradaParaFifo(
        moraCobradaHistorial: 0,
        moraCobradaOffset: contrato.moraCobradaOffset,
      );
      final creditoDespues = MoraCuotaCalculator.moraCobradaParaFifo(
        moraCobradaHistorial: 17100,
        moraCobradaOffset: contrato.moraCobradaOffset + 17100,
      );

      expect(creditoDespues, closeTo(creditoAntes, 0.01));
    });
  });

  group('la exención se otorga solo cuando corresponde', () {
    ({
      List<MoraCuotaDetalle> bruto,
      List<MoraCuotaDetalle> neto,
      double netoTotal,
    })
    desgloseDe(ContratoAlumno c) {
      final bruto = MoraCuotaCalculator.calcularDesglose(c, hoy);
      final neto = MoraCuotaCalculator.desglosePendiente(
        bruto,
        MoraCuotaCalculator.moraCobradaParaFifo(
          moraCobradaHistorial: 0,
          moraCobradaOffset: c.moraCobradaOffset,
        ),
      );
      return (
        bruto: bruto,
        neto: neto,
        netoTotal: neto.fold<double>(0, (s, d) => s + d.interesBruto),
      );
    }

    EstadoMoraPostCobro cobrar(
      ContratoAlumno c, {
      required double moraEsteCobro,
      int cuotasLiquidadas = 0,
      double? saldoDeudorPost,
    }) {
      final d = desgloseDe(c);
      return MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: c.moraPendienteTracked,
        moraCobradaOffsetActual: c.moraCobradaOffset,
        moraEsteCobro: moraEsteCobro,
        cuotasBaseLiquidadasEnCobro: cuotasLiquidadas,
        cuotasBasePagadasPostCobro: c.cuotasPagadas + cuotasLiquidadas,
        moraDesglosePreCobro: d.bruto,
        moraDesgloseNetoPreCobro: d.neto,
        moraDesgloseNetoTotal: d.netoTotal,
        saldoDeudorPost: saldoDeudorPost ?? c.saldoDeudor,
        fechaCobroAr: hoy,
        exencionActual: c.moraExentaHasta,
        reiniciaActual: c.moraExencionReinicia,
      );
    }

    test('cobro parcial → sin exención, la mora sigue viva', () {
      final post = cobrar(bernel(), moraEsteCobro: 10000);

      expect(post.exentaHasta, isNull);
      expect(post.tracked, closeTo(5000, 0.01));
    });

    test('mora en cero → no toca la exención vigente', () {
      final vieja = DateTime(2026, 5, 31);
      final post = cobrar(
        bernel(moraExentaHasta: vieja),
        moraEsteCobro: 0,
        cuotasLiquidadas: 1,
      );

      expect(post.exentaHasta, vieja);
    });

    test('contrato que queda saldado → no se exime nada', () {
      final post = cobrar(bernel(), moraEsteCobro: 17100, saldoDeudorPost: 0);

      expect(post.exentaHasta, isNull);
    });

    test('liquidar cuota base además de la mora → la exención reinicia', () {
      final post = cobrar(
        bernel(moraPendienteTracked: 0),
        moraEsteCobro: 2100,
        cuotasLiquidadas: 1,
      );

      expect(post.exentaHasta, DateTime(2026, 8, 31));
      expect(post.reinicia, isTrue);
    });

    test('lote histórico sin fecha legible → conserva la exención vigente', () {
      final vieja = DateTime(2026, 5, 31);
      final c = bernel(moraExentaHasta: vieja);
      final d = desgloseDe(c);

      final post = MoraCuotaCalculator.postCobroTrackedOffset(
        moraPendienteTrackedActual: c.moraPendienteTracked,
        moraCobradaOffsetActual: c.moraCobradaOffset,
        moraEsteCobro: 17100,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 3,
        moraDesglosePreCobro: d.bruto,
        moraDesgloseNetoPreCobro: d.neto,
        moraDesgloseNetoTotal: d.netoTotal,
        saldoDeudorPost: c.saldoDeudor,
        fechaCobroAr: null,
        exencionActual: c.moraExentaHasta,
        reiniciaActual: c.moraExencionReinicia,
      );

      expect(post.exentaHasta, vieja);
    });
  });

  group('EstadoMoraPostCobro.aplicarA', () {
    final post = EstadoMoraPostCobro(
      tracked: 1234.5,
      offset: 6789,
      exentaHasta: DateTime(2026, 8, 31),
      reinicia: true,
    );

    test('aplica los cuatro campos de una sola vez', () {
      final c = post.aplicarA(
        bernel(moraExentaHasta: DateTime(2026, 5, 31)),
        moraFechaReferencia: null,
      );

      expect(c.moraPendienteTracked, 1234.5);
      expect(c.moraCobradaOffset, 6789);
      expect(c.moraExentaHasta, DateTime(2026, 8, 31));
      expect(c.moraExencionReinicia, isTrue);
    });

    test('exentaHastaIso es lo que espera la columna', () {
      expect(post.exentaHastaIso, '2026-08-31');
      expect(
        const EstadoMoraPostCobro(
          tracked: 0,
          offset: 0,
          exentaHasta: null,
          reinicia: false,
        ).exentaHastaIso,
        isNull,
      );
    });

    test('conserva la fecha de referencia salvo que se pida limpiarla', () {
      final ref = DateTime(2026, 7, 1);
      final base = bernel();

      expect(
        post.aplicarA(base, moraFechaReferencia: ref).moraFechaReferencia,
        ref,
      );
      expect(
        post
            .aplicarA(
              base,
              moraFechaReferencia: ref,
              limpiarMoraReferencia: true,
            )
            .moraFechaReferencia,
        isNull,
      );
    });
  });
}
