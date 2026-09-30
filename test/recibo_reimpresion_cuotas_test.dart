import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/models/contrato_alumno.dart';

/// El recibo reimpreso cuenta las cuotas de aquel día desde los pagos.
///
/// Antes las deducía del saldo dividiendo por el total del contrato, que
/// incluye mesas y sillas: GAUNA, GERALDINE (Puerto Viejo) tenía 6 cuotas
/// pagadas y 4 mesas extra, y su recibo reimpreso decía 4/9.
void main() {
  Map<String, dynamic> pago(
    String fecha,
    double monto,
    String concepto, {
    double? gross,
    String? lineKind,
    int anulado = 0,
  }) =>
      {
        'fecha_pago': fecha,
        'monto': monto,
        'monto_gross': gross ?? monto,
        'concepto': concepto,
        'line_kind': lineKind,
        'anulado': anulado,
      };

  // GAUNA, GERALDINE: plan de $495.000 en 9 cuotas de $55.000, más 4 mesas
  // extra de $70.000.
  final geraldine = ContratoAlumno(
    id: '626ec708-19d0-4c68-83b7-dda451608f55',
    eventoId: '3ee876b0-e8d6-4560-9161-bea9c542ee53',
    nombreAlumno: 'GAUNA, GERALDINE',
    cantidadAcompanantes: 0,
    montoTotalPactado: 775000,
    saldoDeudor: 430000,
    cuotasPagadas: 6,
    totalCuotas: 9,
    mesaExtraPrecio: 280000,
    mesaExtraCantidad: 4,
    mesaExtraPagado: 15000,
  );
  final pagosGeraldine = [
    pago('2026-04-27T19:24:36.429602+00:00', 55000, 'Cuota Base (1/9)'),
    pago('2026-05-26T16:49:52.66101+00:00', 55000, 'Cuota Base (2/9)'),
    pago('2026-06-26T17:34:48.4744+00:00', 55000, 'Cuota Base (3/9)'),
    pago('2026-07-28T17:13:41.109676+00:00', 55000, 'Cuota Base (4/9)'),
    pago('2026-08-24T17:53:23.950794+00:00', 55000, 'Cuota Base (5/9)'),
    pago(
      '2026-08-24T17:53:23.962823+00:00',
      15000,
      'Entrega parcial — Mesa Extra 1 (1/1)',
    ),
    pago('2026-09-25T17:28:33.015141+00:00', 55000, 'Cuota Base (6/9)'),
  ];

  // SEGOVIA, PABLO: el mismo plan, con 1 mesa extra.
  final pablo = ContratoAlumno(
    id: '2646f9b8-db60-42a0-9cf1-5b307d0db589',
    eventoId: '3ee876b0-e8d6-4560-9161-bea9c542ee53',
    nombreAlumno: 'SEGOVIA, PABLO',
    cantidadAcompanantes: 0,
    montoTotalPactado: 565000,
    saldoDeudor: 209000,
    cuotasPagadas: 6,
    totalCuotas: 9,
    mesaExtraPrecio: 70000,
    mesaExtraCantidad: 1,
    mesaExtraPagado: 26000,
  );
  final pagosPablo = [
    pago('2026-04-27T20:05:45.799185+00:00', 55000, 'Cuota Base (1/9)'),
    pago('2026-05-26T16:53:43.221312+00:00', 55000, 'Cuota Base (2/9)'),
    pago('2026-06-26T17:22:52.832673+00:00', 55000, 'Cuota Base (3/9)'),
    pago('2026-07-28T17:21:18.12487+00:00', 55000, 'Cuota Base (4/9)'),
    pago('2026-07-28T17:21:18.164869+00:00', 26000, 'Mesa Extra (1/1)'),
    pago('2026-08-24T17:45:08.745491+00:00', 55000, 'Cuota Base (5/9)'),
    pago('2026-09-25T17:37:38.470111+00:00', 55000, 'Cuota Base (6/9)'),
  ];

  test('GERALDINE: el recibo del 25-sep dice 6 cuotas, no 4', () {
    final r = progresoAlDia(
      contrato: geraldine,
      pagos: pagosGeraldine,
      hasta: DateTime.parse('2026-09-25T17:28:33.015141+00:00'),
    );
    expect(r.cuotasBase, 6);
    expect(r.saldoDeudor, 430000);
  });

  test('PABLO: 6 cuotas el 25-sep y 5 el 24-ago', () {
    final sep = progresoAlDia(
      contrato: pablo,
      pagos: pagosPablo,
      hasta: DateTime.parse('2026-09-25T17:37:38.470111+00:00'),
    );
    expect(sep.cuotasBase, 6);
    expect(sep.saldoDeudor, 209000);

    final ago = progresoAlDia(
      contrato: pablo,
      pagos: pagosPablo,
      hasta: DateTime.parse('2026-08-24T17:45:08.745491+00:00'),
    );
    expect(ago.cuotasBase, 5);
    expect(ago.saldoDeudor, 264000);
  });

  test('los pagos posteriores al recibo no cuentan', () {
    final r = progresoAlDia(
      contrato: geraldine,
      pagos: pagosGeraldine,
      hasta: DateTime.parse('2026-06-26T17:34:48.4744+00:00'),
    );
    expect(r.cuotasBase, 3);
    expect(r.saldoDeudor, 775000 - 3 * 55000);
  });

  test('las líneas del mismo cobro, con milisegundos de diferencia, cuentan', () {
    // La cuota 5 y la entrega de mesa se guardaron con 12 ms de diferencia.
    final r = progresoAlDia(
      contrato: geraldine,
      pagos: pagosGeraldine,
      hasta: DateTime.parse('2026-08-24T17:53:23.950794+00:00'),
    );
    expect(r.cuotasBase, 5);
    expect(r.saldoDeudor, 775000 - 5 * 55000 - 15000);
  });

  test('una liquidación con descuento cuenta el valor de las cuotas', () {
    final contrato = ContratoAlumno(
      id: 'a',
      eventoId: 'e',
      nombreAlumno: 'LIQUIDÓ, CON DESCUENTO',
      cantidadAcompanantes: 0,
      montoTotalPactado: 270000,
      saldoDeudor: 0,
      cuotasPagadas: 9,
      totalCuotas: 9,
    );
    final r = progresoAlDia(
      contrato: contrato,
      pagos: [
        pago(
          '2026-05-10T12:00:00+00:00',
          243000,
          'Liquidación de 9 cuotas cuota base',
          gross: 270000,
        ),
      ],
      hasta: DateTime.parse('2026-05-10T12:00:00+00:00'),
    );
    expect(r.cuotasBase, 9);
    expect(r.saldoDeudor, 0);
  });

  test('la mora, el costo por transferencia y lo anulado no cuentan', () {
    final r = progresoAlDia(
      contrato: geraldine,
      pagos: [
        pago('2026-04-27T19:24:36+00:00', 55000, 'Cuota Base (1/9)'),
        pago(
          '2026-04-27T19:24:36+00:00',
          5000,
          'Interés mora cuota 1 (vto Abr 2026)',
          lineKind: kLineKindInteresMora,
        ),
        pago(
          '2026-04-27T19:24:36+00:00',
          2000,
          'Costo por transferencia',
          lineKind: kLineKindCargoCanal,
        ),
        pago(
          '2026-04-27T19:24:36+00:00',
          55000,
          'Cuota Base (2/9)',
          anulado: 1,
        ),
      ],
      hasta: DateTime.parse('2026-04-27T19:24:36+00:00'),
    );
    expect(r.cuotasBase, 1);
    expect(r.saldoDeudor, 775000 - 55000);
  });
}
