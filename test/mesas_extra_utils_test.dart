import 'package:flutter_test/flutter_test.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/mesa_extra_item.dart';

void main() {
  test('repartirPagadoFifo asigna primero a mesa 1', () {
    final mesas = MesasExtraUtils.repartirPagadoFifo(
      cantidad: 2,
      precioUnitario: 70000,
      cuotasPlan: 7,
      pagadoTotal: 80000,
      cuotasPagadasLegacy: 0,
    );
    expect(mesas.length, 2);
    expect(mesas[0].pagado, 70000);
    expect(mesas[0].liquidada, true);
    expect(mesas[1].pagado, 10000);
    expect(mesas[1].liquidada, false);
  });

  test('estadoDesdeContrato legacy una mesa', () {
    final c = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'Test',
      cantidadAcompanantes: 0,
      montoTotalPactado: 100000,
      saldoDeudor: 50000,
      mesaExtraPrecio: 70000,
      mesaExtraPagado: 20000,
      mesaExtraCuotasPagadas: 2,
      mesaExtraCuotas: 7,
    );
    final mesas = MesasExtraUtils.estadoDesdeContrato(c);
    expect(mesas.length, 1);
    expect(mesas.first.pagado, 20000);
    expect(mesas.first.cuotasPagadas, 2);
  });

  test('numeroMesaDesdeConcepto legacy sin numero', () {
    expect(
      MesasExtraUtils.numeroMesaDesdeConcepto('Mesa Extra (2/7)'),
      1,
    );
    expect(
      MesasExtraUtils.numeroMesaDesdeConcepto('Mesa Extra 2 (1/7)'),
      2,
    );
  });

  test('construirParaGuardar conserva pagos mesa 1 al agregar mesa 2', () {
    final prev = [
      MesaExtraItem(n: 1, precio: 70000, pagado: 20000, cuotasPagadas: 2),
    ];
    final next = MesasExtraUtils.construirParaGuardar(
      cantidadNueva: 2,
      precioUnitario: 70000,
      cuotasPlan: 7,
      estadoAnterior: prev,
    );
    expect(next.length, 2);
    expect(next[0].pagado, 20000);
    expect(next[1].pagado, 0);
  });
}
