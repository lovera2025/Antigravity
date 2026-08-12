import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';

/// CARACTERIZACIÓN — fija lo que `postCobroTrackedOffset` hace **hoy** con la
/// mora parcial. No afirma que sea lo correcto: sirve para que un cambio en
/// esta lógica sea deliberado y no accidental.
///
/// `moraCobradaParaFifo` = historial − offset. El offset es la mora cobrada que
/// **no** se acredita contra el calendario (se pagó sobre tracked, o sobre una
/// cuota ya liquidada que salió del desglose). Por eso un pago parcial contra
/// el calendario no lo mueve: se acredita vía FIFO.
///
/// CUIDADO — hay una discrepancia sin resolver (11/08/2026). Para ZARATE
/// (GUEMEZ DE TEJADA), que pagó $38.500 de mora el 06/08:
///
///   - la ficha muestra          $0
///   - `auditoria_mora_masivos`  $18.550
///   - la cuenta a mano          ~$3.500  (5 días nuevos sobre C3 y C4 al 1%
///                                         diario de $35.000 de cuota base)
///
/// Ninguna de las dos primeras da bien. Además ese cobro no actualizó ni el
/// offset ni `mora_exenta_hasta` (quedó en 31/05, la de mayo), así que algo de
/// ese guardado no llegó.
///
/// Y hay una razón de fondo, más grave, por la que el replay no cierra: la
/// **fecha de alta se movió a mano**. El cronograma se ancla en `created_at`
/// (la cuota N vence a fin del mes `alta + N`), y en su momento se perdonó mora
/// corriendo esa fecha, para después normalizar casi todas al 30/03/2026. De
/// 639 contratos masivos activos, 390 tienen el alta redonda —puesta a mano— y
/// esos se desvían 2,4 veces más que los 249 con hora real de creación.
///
/// Un cobro de mayo se hizo bajo un cronograma que hoy ya no existe, y el
/// replay lo recalcula con el alta actual. La fecha vieja no quedó registrada.
///
/// Antes de "corregir" nada acá o de aplicar `reconciliar_mora_masivos_test`
/// con APPLY=1: hace falta poder saber qué alta regía en cada cobro. Aplicar la
/// reconciliación tal como está le reclamaría a seis familias mora que ya
/// pagaron.
void main() {
  MoraCuotaDetalle cuota(int n, double interes, {String mes = 'May 2026'}) =>
      MoraCuotaDetalle(
        numeroCuota: n,
        vencimiento: DateTime(2026, 5, 31),
        diasMora: 30,
        interesBruto: interes,
        mesLabel: mes,
      );

  final desglose = [cuota(3, 20000), cuota(4, 25000, mes: 'Jun 2026')];
  const totalDesglose = 45000.0;

  EstadoMoraPostCobro correr({
    required double moraEsteCobro,
    required int cuotasLiquidadas,
    double offsetActual = 0,
    double trackedActual = 0,
  }) {
    return MoraCuotaCalculator.postCobroTrackedOffset(
      moraPendienteTrackedActual: trackedActual,
      moraCobradaOffsetActual: offsetActual,
      moraEsteCobro: moraEsteCobro,
      cuotasBaseLiquidadasEnCobro: cuotasLiquidadas,
      cuotasBasePagadasPostCobro: 2 + cuotasLiquidadas,
      moraDesglosePreCobro: desglose,
      moraDesgloseNetoPreCobro: desglose,
      moraDesgloseNetoTotal: totalDesglose,
      saldoDeudorPost: 100000,
      fechaCobroAr: DateTime(2026, 8, 6),
      exencionActual: null,
      reiniciaActual: true,
    );
  }

  group('offset y mora parcial', () {
    test('pago PARCIAL contra el calendario no entra al offset', () {
      // $45.000 de mora, la familia entrega $15.000 y no liquida cuota base.
      final e = correr(moraEsteCobro: 15000, cuotasLiquidadas: 0);

      // El offset queda quieto para que el crédito FIFO (historial − offset)
      // valga esos $15.000 y descuente el calendario. Subirlo lo anularía.
      expect(e.offset, 0, reason: 'un pago parcial se acredita vía FIFO');
      expect(e.tracked, 0);
    });

    test('pago parcial no pisa ni mueve el offset previo', () {
      final e = correr(
        moraEsteCobro: 15000,
        cuotasLiquidadas: 0,
        offsetActual: 2100,
      );
      expect(e.offset, 2100, reason: 'el offset de cobros previos se conserva');
    });

    test('pago COMPLETO del calendario sí entra al offset', () {
      // Sin desglose pendiente no hay contra qué acreditar: el offset evita que
      // el FIFO futuro se coma cuotas nuevas con crédito viejo.
      final e = correr(moraEsteCobro: totalDesglose, cuotasLiquidadas: 0);
      expect(e.offset, totalDesglose);
    });

    test('con cuota base liquidada el offset absorbe la mora cobrada', () {
      // La cuota liquidada sale del calendario (calcularDesglose arranca en
      // cuotasPagadas + 1), así que esa mora no tiene dónde acreditarse.
      final e = correr(moraEsteCobro: 15000, cuotasLiquidadas: 1);
      expect(e.offset, 15000);
    });

    test('mora pagada sobre el tracked remanente entra al offset', () {
      final e = correr(
        moraEsteCobro: 5000,
        cuotasLiquidadas: 0,
        trackedActual: 8000,
      );
      expect(e.offset, 5000, reason: 'no se acredita contra el calendario');
      expect(e.tracked, 3000);
    });

    test('sin cobro de mora el offset no se mueve', () {
      final e = correr(
        moraEsteCobro: 0,
        cuotasLiquidadas: 1,
        offsetActual: 2100,
      );
      expect(e.offset, 2100);
    });
  });
}
