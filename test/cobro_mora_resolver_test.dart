import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/eventos/services/cobro_mora_resolver.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// Cubre el camino que **usa el modal de cobro masivo** al confirmar.
///
/// Antes esta secuencia vivía suelta dentro del `onPressed`, sin test que la
/// alcanzara, y ahí se emitió el recibo Nº 0661293D con el aviso de mora
/// contradiciendo al detalle. Estos tests fijan que el estado que se persiste y
/// el número que se imprime salgan del mismo cálculo.
void main() {
  // Reg 15/03/2026 → C4 vence 31/07. Plan $270.000 / 9 → cuota $30.000.
  // Al 07/08/2026 son 7 días de atraso → $2.100 de mora en la C4.
  ContratoAlumno bernel({
    double saldoDeudor = 180000,
    int cuotasPagadas = 3,
    double moraPendienteTracked = 15000,
    DateTime? moraFechaReferencia,
  }) => ContratoAlumno(
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
    moraFechaReferencia: moraFechaReferencia,
  );

  final fechaCobro = DateTime(2026, 8, 7);
  String plata(double v) => '\$${v.toStringAsFixed(2)}';

  ResolucionMoraCobro resolver({
    required double moraEsteCobro,
    ContratoAlumno? pre,
    ContratoAlumno? post,
    int cuotasLiquidadas = 0,
    double? saldoDeudorPost,
  }) {
    final contratoPre = pre ?? bernel();
    final contratoPost = post ?? contratoPre;
    return resolverMoraDeCobro(
      contratoPre: contratoPre,
      contratoPost: contratoPost,
      moraCobradaHistorial: 0,
      moraEsteCobro: moraEsteCobro,
      cuotasBaseLiquidadasEnCobro: cuotasLiquidadas,
      cuotasBasePagadasPostCobro: contratoPre.cuotasPagadas + cuotasLiquidadas,
      saldoDeudorPost: saldoDeudorPost ?? contratoPost.saldoDeudor,
      fechaCobroAr: fechaCobro,
      formatoMonto: plata,
    );
  }

  group('recibo Nº 0661293D — cobrar toda la mora', () {
    test('no queda mora, y el recibo no lleva aviso rojo', () {
      final r = resolver(moraEsteCobro: 17100);

      expect(r.moraPendientePost, closeTo(0, 0.01));
      expect(r.quedaSaldada, isTrue);
      // Sin esto el papel imprimía "Viene de: cuota 4 (Jul, 7 d) $2.100,00".
      expect(r.moraPendienteOrigen, isEmpty);
      expect(r.desglosePost, isEmpty);
      expect(r.trackedPost, closeTo(0, 0.01));
    });

    test('lo que se imprime es lo mismo que queda en la ficha', () {
      final r = resolver(moraEsteCobro: 17100);

      expect(r.contratoPatch.moraPendienteTracked, closeTo(0, 0.01));
      expect(r.contratoPatch.moraExentaHasta, DateTime(2026, 8, 31));
      // Cobro de sola mora: julio no vuelve al vencer la exención.
      expect(r.contratoPatch.moraExencionReinicia, isFalse);
      expect(r.estado.exentaHastaIso, '2026-08-31');
    });

    test('la ficha guardada no vuelve a reclamar la mora recién cobrada', () {
      // Vuelve a resolver partiendo del contrato que quedó guardado, como si
      // se reimprimiera el recibo. Tiene que seguir dando cero.
      final primero = resolver(moraEsteCobro: 17100);
      final segundo = resolverMoraDeCobro(
        contratoPre: primero.contratoPatch,
        contratoPost: primero.contratoPatch,
        moraCobradaHistorial: 17100,
        moraEsteCobro: 0,
        cuotasBaseLiquidadasEnCobro: 0,
        cuotasBasePagadasPostCobro: 3,
        saldoDeudorPost: 180000,
        fechaCobroAr: fechaCobro,
        formatoMonto: plata,
      );

      expect(segundo.moraPendientePost, closeTo(0, 0.01));
      expect(segundo.moraPendienteOrigen, isEmpty);
    });
  });

  group('lo que no cambia', () {
    test('cobro parcial: queda mora y el aviso dice de dónde viene', () {
      // Paga $10.000 de los $17.100: quedan $7.100.
      final r = resolver(moraEsteCobro: 10000);

      expect(r.moraPendientePost, closeTo(7100, 0.01));
      expect(r.quedaSaldada, isFalse);
      expect(r.moraPendienteOrigen, startsWith('Mora'));
      expect(r.moraPendienteOrigen, contains('cuota 4'));
      expect(r.contratoPatch.moraExentaHasta, isNull);
    });

    test('no cobrar mora al liquidar una cuota: se acumula en ficha', () {
      final post = bernel(saldoDeudor: 150000, cuotasPagadas: 4);
      final r = resolver(moraEsteCobro: 0, post: post, cuotasLiquidadas: 1);

      // Los $15.000 previos + los $2.100 de la cuota 4 que se liquidó sin mora.
      expect(r.contratoPatch.moraPendienteTracked, closeTo(17100, 0.01));
      expect(r.moraPendientePost, closeTo(17100, 0.01));
      expect(r.contratoPatch.moraExentaHasta, isNull);
    });

    test('contrato que queda saldado: no se exime nada', () {
      final post = bernel(saldoDeudor: 0, cuotasPagadas: 9);
      final r = resolver(
        moraEsteCobro: 17100,
        post: post,
        cuotasLiquidadas: 6,
        saldoDeudorPost: 0,
      );

      expect(r.contratoPatch.moraExentaHasta, isNull);
    });
  });

  group('descongelar la referencia de mora', () {
    final congelado = DateTime(2026, 7, 20);

    test('saldar toda la mora descongela', () {
      final r = resolver(
        moraEsteCobro: 17100,
        pre: bernel(moraFechaReferencia: congelado),
      );

      expect(r.limpiarMoraReferencia, isTrue);
      expect(r.contratoPatch.moraFechaReferencia, isNull);
    });

    test('cobro parcial la deja congelada', () {
      final r = resolver(
        moraEsteCobro: 10000,
        pre: bernel(moraFechaReferencia: congelado),
      );

      expect(r.limpiarMoraReferencia, isFalse);
      expect(r.contratoPatch.moraFechaReferencia, congelado);
    });

    test('contrato sin referencia congelada no se toca', () {
      final r = resolver(moraEsteCobro: 17100);

      expect(r.limpiarMoraReferencia, isFalse);
      expect(r.contratoPatch.moraFechaReferencia, isNull);
    });
  });
}
