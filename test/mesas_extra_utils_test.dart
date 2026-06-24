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

  test('resolveMesa usa mesa activa única cuando clave es Mesa:2', () {
    final mesas = [
      MesaExtraItem(
        n: 1,
        precio: 70000,
        pagado: 70000,
        cuotasPagadas: 7,
        liquidada: true,
      ),
      MesaExtraItem(n: 2, precio: 70000, pagado: 0, cuotasPagadas: 0),
    ];
    final activas = MesasExtraUtils.mesasActivas(mesas);
    expect(activas.length, 1);
    expect(activas.first.n, 2);

    final item = MesasExtraUtils.resolveMesa(
      conceptoKey: 'Mesa:2',
      mesasEstado: mesas,
      mesasActivas: activas,
      precioUnitarioFallback: 70000,
    );
    expect(item.n, 2);
    expect(item.cuotasPagadas, 0);

    final concepto = MesasExtraUtils.conceptoCuotaDetallado(
      item: item,
      cuotasPlan: 7,
      cantidadMesas: 2,
      cuotaOffset: 1,
    );
    expect(concepto, 'Mesa Extra 2 (1/7)');
  });

  test('resolveMesa no asume mesa 1 con label genérico y una activa', () {
    final mesas = [
      MesaExtraItem(
        n: 1,
        precio: 70000,
        pagado: 70000,
        cuotasPagadas: 7,
        liquidada: true,
      ),
      MesaExtraItem(n: 2, precio: 70000, pagado: 0, cuotasPagadas: 0),
    ];
    final activas = MesasExtraUtils.mesasActivas(mesas);
    final item = MesasExtraUtils.resolveMesa(
      conceptoKey: 'Mesa',
      mesasEstado: mesas,
      mesasActivas: activas,
      precioUnitarioFallback: 70000,
    );
    expect(item.n, 2);
    expect(
      MesasExtraUtils.conceptoCuotaDetallado(
        item: item,
        cuotasPlan: 7,
        cantidadMesas: 2,
      ),
      'Mesa Extra 2 (1/7)',
    );
  });

  test('labelCobro numera cuando hay varias mesas en contrato', () {
    expect(MesasExtraUtils.labelCobro(2, 2), 'Mesa Extra 2');
    expect(MesasExtraUtils.tituloCobro(2, 2), 'MESA EXTRA 2');
    expect(MesasExtraUtils.labelCobro(1, 1), 'Mesa Extra');
  });

  // Caso Dramisino real: pagos legacy sin número + pago nuevo numerado.
  // Legacy "Mesa Extra (1/7)"=$70k y "Mesa Extra (2/7)"=$10k deben ir
  // por FIFO (mesa 1 llena → mesa 2). El nuevo "Mesa Extra 2 (1/7)"=$10k
  // va directo a mesa 2. Resultado: mesa1=$70k liquidada, mesa2=$20k (2/7).
  test('reconciliarDesdePagos híbrido: legacy FIFO + nuevo numerado', () {
    final pagos = [
      {
        'concepto': 'Mesa Extra (1/7)',
        'monto_gross': 70000.0,
        'fecha_pago': '2026-05-22T19:16:00',
        'anulado': 0,
      },
      {
        'concepto': 'Mesa Extra (2/7)',
        'monto_gross': 10000.0,
        'fecha_pago': '2026-05-22T19:16:01',
        'anulado': 0,
      },
      {
        'concepto': 'Mesa Extra 2 (1/7)',
        'monto_gross': 10000.0,
        'fecha_pago': '2026-06-23T21:07:00',
        'anulado': 0,
      },
    ];
    final mesas = MesasExtraUtils.reconciliarDesdePagos(
      cantidad: 2,
      precioUnitario: 70000,
      cuotasPlan: 7,
      pagos: pagos,
    );
    expect(mesas.length, 2);
    // Mesa 1: $70k → liquidada 7/7
    expect(mesas[0].pagado, 70000);
    expect(mesas[0].liquidada, true);
    expect(mesas[0].cuotasPagadas, 7);
    // Mesa 2: $10k legacy + $10k numerado = $20k → 2/7
    expect(mesas[1].pagado, 20000);
    expect(mesas[1].liquidada, false);
    expect(mesas[1].cuotasPagadas, 2);
  });

  // Caso: todos los pagos son legacy sin número, 2 mesas.
  // FIFO puro: el overflow se distribuye correctamente.
  test('reconciliarDesdePagos legacy puro FIFO sin número explícito', () {
    final pagos = [
      {
        'concepto': 'Mesa Extra (1/7)',
        'monto_gross': 70000.0,
        'fecha_pago': '2026-05-01T10:00:00',
        'anulado': 0,
      },
      {
        'concepto': 'Mesa Extra (2/7)',
        'monto_gross': 10000.0,
        'fecha_pago': '2026-05-15T10:00:00',
        'anulado': 0,
      },
    ];
    final mesas = MesasExtraUtils.reconciliarDesdePagos(
      cantidad: 2,
      precioUnitario: 70000,
      cuotasPlan: 7,
      pagos: pagos,
    );
    expect(mesas[0].pagado, 70000);
    expect(mesas[0].liquidada, true);
    expect(mesas[1].pagado, 10000);
    expect(mesas[1].liquidada, false);
    expect(mesas[1].cuotasPagadas, 1);
  });

  test('usarUiCompactaMesasCobro umbral en 3', () {
    expect(MesasExtraUtils.usarUiCompactaMesasCobro(2), false);
    expect(MesasExtraUtils.usarUiCompactaMesasCobro(3), true);
    expect(MesasExtraUtils.usarUiCompactaMesasCobro(10), true);
  });

  test('tituloGrupoDesgloseMesas agrupa mismo monto y cuota', () {
    final lineas = [
      {
        'concepto': 'Mesa Extra 1 (1/7)',
        'monto': 10000.0,
        'mesaN': 1,
      },
      {
        'concepto': 'Mesa Extra 2 (1/7)',
        'monto': 10000.0,
        'mesaN': 2,
      },
      {
        'concepto': 'Mesa Extra 3 (1/7)',
        'monto': 10000.0,
        'mesaN': 3,
      },
    ];
    expect(
      MesasExtraUtils.tituloGrupoDesgloseMesas(lineas),
      'Mesas Extra 1–3 (1/7) c/u',
    );
    expect(MesasExtraUtils.sumaMontosPreview(lineas), 30000.0);
  });

  test('esLineaPreviewMesa detecta mesaN y concepto', () {
    expect(
      MesasExtraUtils.esLineaPreviewMesa({'concepto': 'Cuota Base (3/9)'}),
      false,
    );
    expect(
      MesasExtraUtils.esLineaPreviewMesa({
        'concepto': 'Mesa Extra 2 (1/7)',
        'mesaN': 2,
      }),
      true,
    );
    expect(
      MesasExtraUtils.esLineaPreviewMesa({
        'concepto': 'Interés mora',
        'lineKind': 'interes_mora',
      }),
      false,
    );
  });

  test('montosManualesMesasDesde y limpiarClavesMesasEnMontosManuales', () {
    final montos = <String, double>{
      'Base': 30000,
      'Mesa:1': 10000,
      'Mesa:2': 10000,
      'Mesa': 999,
    };
    expect(
      MesasExtraUtils.montosManualesMesasDesde(montos),
      {'Mesa:1': 10000, 'Mesa:2': 10000},
    );
    MesasExtraUtils.limpiarClavesMesasEnMontosManuales(montos);
    expect(montos.containsKey('Mesa'), false);
    expect(montos.containsKey('Mesa:1'), false);
    expect(montos['Base'], 30000);
  });

  test('cantidadMesasFisicasSorteo respeta mesas extra contratadas', () {
    final sinExtra = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'A',
      cantidadAcompanantes: 0,
      montoTotalPactado: 100000,
      saldoDeudor: 100000,
    );
    expect(MesasExtraUtils.cantidadMesasFisicasSorteo(sinExtra), 1);

    final unaExtra = sinExtra.copyWith(
      mesaExtraPrecio: 70000,
      mesaExtraCantidad: 1,
    );
    expect(MesasExtraUtils.cantidadMesasFisicasSorteo(unaExtra), 2);

    final tresExtra = unaExtra.copyWith(
      mesaExtraCantidad: 3,
      mesasExtraEstadoRaw: List.generate(
        3,
        (i) => MesaExtraItem(n: i + 1, precio: 23333).toJson(),
      ),
    );
    expect(MesasExtraUtils.cantidadMesasFisicasSorteo(tresExtra), 4);
  });

  test('tomarMesasDisponibles prefiere consecutivas', () {
    final libres = [5, 10, 11, 12, 20];
    final picked = MesasExtraUtils.tomarMesasDisponibles(libres, 3);
    expect(picked, [10, 11, 12]);
    expect(libres, [5, 20]);
  });

  test('lineasResumenGrilla muestra cuota y deuda por mesa', () {
    final c = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'A',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 70000,
      mesaExtraCuotas: 7,
      mesaExtraCantidad: 1,
      mesaExtraPagado: 10000,
      mesaExtraCuotasPagadas: 1,
    );
    final lineas = MesasExtraUtils.lineasResumenGrilla(c);
    expect(lineas.length, 1);
    expect(lineas.first, contains('Mesa extra'));
    expect(lineas.first, contains('1/7'));
  });
}
