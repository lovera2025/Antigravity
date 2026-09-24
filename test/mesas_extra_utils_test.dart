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
  test('conceptoPagoPersistido agrega número de mesa al guardar', () {
    expect(
      MesasExtraUtils.conceptoPagoPersistido(
        previewLinea: {'mesaN': 3},
        conceptoOriginal: 'Mesa Extra (3/7)',
        cantidadMesas: 3,
      ),
      'Mesa Extra 3 (3/7)',
    );
    expect(
      MesasExtraUtils.conceptoPagoPersistido(
        previewLinea: {'mesaN': 1, 'concepto': 'Mesa Extra (1/7)'},
        conceptoOriginal: 'Mesa Extra (1/7)',
        cantidadMesas: 1,
      ),
      'Mesa Extra (1/7)',
    );
    expect(
      MesasExtraUtils.pagoConceptoTieneMesaNumeradaExplicita('Mesa Extra 3 (3/7)'),
      true,
    );
  });

  test('reconciliarDesdePagos mesa 1 explícita no va por FIFO', () {
    final pagos = [
      {
        'concepto': 'Mesa Extra 1 (3/7)',
        'monto_gross': 30000.0,
        'fecha_pago': '2026-06-25T12:00:00',
        'anulado': 0,
      },
      {
        'concepto': 'Mesa Extra 3 (3/7)',
        'monto_gross': 30000.0,
        'fecha_pago': '2026-06-25T12:01:00',
        'anulado': 0,
      },
    ];
    final mesas = MesasExtraUtils.reconciliarDesdePagos(
      cantidad: 3,
      precioUnitario: 70000,
      cuotasPlan: 7,
      pagos: pagos,
    );
    expect(mesas[0].cuotasPagadas, 3);
    expect(mesas[2].cuotasPagadas, 3);
  });

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

  test('cantidadMesasFisicasSorteo caso Ojeda: campo 1 pero estado 2 extras', () {
    final ojeda = ContratoAlumno(
      id: 'ojeda',
      eventoId: 'rotonda',
      nombreAlumno: 'OJEDA, VICTORIA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 1,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000, pagado: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000, pagado: 70000).toJson(),
      ],
    );
    expect(MesasExtraUtils.cantidadMesasFisicasSorteo(ojeda), 3);
  });

  test('inferirCantidadMesasExtraContrato desde pagos numerados', () {
    final c = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'A',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 1,
    );
    final pagos = [
      {'concepto': 'Mesa Extra 1 (1/7)', 'monto_gross': 10000.0, 'anulado': 0},
      {'concepto': 'Mesa Extra 2 - Entrega', 'monto_gross': 70000.0, 'anulado': 0},
    ];
    expect(
      MesasExtraUtils.inferirCantidadMesasExtraContrato(c, pagos: pagos),
      2,
    );
  });

  test('inferirEntregasMesasColapsadas caso Ojeda 2x70k lotes distintos', () {
    final c = ContratoAlumno(
      id: 'ojeda',
      eventoId: 'rotonda',
      nombreAlumno: 'OJEDA, VICTORIA',
      cantidadAcompanantes: 0,
      montoTotalPactado: 300000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 1,
      mesaExtraCuotas: 1,
    );
    final pagos = [
      {
        'id': 'p1',
        'concepto': 'Mesa Extra - Entrega',
        'monto_gross': 70000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-13T17:32:00.000',
      },
      {
        'id': 'p2',
        'concepto': 'Mesa Extra - Entrega',
        'monto_gross': 70000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-13T17:35:00.000',
      },
    ];
    final inf = MesasExtraUtils.inferirEntregasMesasColapsadas(
      c: c,
      pagos: pagos,
    );
    expect(inf, isNotNull);
    expect(inf!.cantidad, 2);
    expect(inf.renombres.map((r) => r.conceptoNuevo).toSet(), {
      'Mesa Extra 1 - Entrega',
      'Mesa Extra 2 - Entrega',
    });
    expect(
      MesasExtraUtils.inferirCantidadMesasExtraContrato(c, pagos: pagos),
      2,
    );
  });

  test('inferirEntregasMesasColapsadas no parte mixto mismo minuto', () {
    final c = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'A',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 1,
      mesaExtraCuotas: 1,
    );
    final pagos = [
      {
        'id': 'p1',
        'concepto': 'Mesa Extra - Entrega',
        'monto_gross': 70000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-13T17:32:00.000',
      },
      {
        'id': 'p2',
        'concepto': 'Mesa Extra - Entrega',
        'monto_gross': 70000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-13T17:32:40.000',
      },
    ];
    expect(
      MesasExtraUtils.inferirEntregasMesasColapsadas(c: c, pagos: pagos),
      isNull,
    );
  });

  test('inferirEntregasMesasColapsadas no aplica si plan en cuotas', () {
    final c = ContratoAlumno(
      id: '1',
      eventoId: 'e1',
      nombreAlumno: 'A',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 70000,
      mesaExtraCantidad: 1,
      mesaExtraCuotas: 7,
    );
    final pagos = [
      {
        'id': 'p1',
        'concepto': 'Mesa Extra (1/7)',
        'monto_gross': 10000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-01T10:00:00.000',
      },
      {
        'id': 'p2',
        'concepto': 'Mesa Extra (2/7)',
        'monto_gross': 10000.0,
        'anulado': 0,
        'fecha_pago': '2026-05-08T10:00:00.000',
      },
    ];
    expect(
      MesasExtraUtils.inferirEntregasMesasColapsadas(c: c, pagos: pagos),
      isNull,
    );
    expect(
      MesasExtraUtils.inferirCantidadMesasExtraContrato(c, pagos: pagos),
      1,
    );
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

  test('aplicarCobroPreviewAEstado actualiza mesa correcta al cobrar', () {
    final estado = [
      MesaExtraItem(
        n: 1,
        precio: 70000,
        pagado: 70000,
        cuotasPagadas: 7,
        liquidada: true,
      ),
      MesaExtraItem(n: 2, precio: 70000, pagado: 0, cuotasPagadas: 0),
    ];
    final preview = [
      {
        'concepto': 'Mesa Extra 2 (1/7)',
        'gross': 10000.0,
        'monto': 10000.0,
        'mesaN': 2,
      },
    ];
    final next = MesasExtraUtils.aplicarCobroPreviewAEstado(
      estado: estado,
      lineasPreview: preview,
      cuotasPlan: 7,
    );
    expect(next[1].pagado, 10000);
    expect(next[1].cuotasPagadas, 1);
    expect(next[1].liquidada, false);
    expect(next[0].pagado, 70000);
  });

  group('estadoMesasReconciliado', () {
    Map<String, dynamic> pago(String concepto, double monto, String fecha) => {
          'concepto': concepto,
          'monto': monto,
          'monto_gross': monto,
          'fecha_pago': fecha,
          'anulado': 0,
        };

    ContratoAlumno contrato({
      required double precio,
      required int cantidad,
      required int cuotas,
    }) =>
        ContratoAlumno(
          id: 'c',
          eventoId: 'e',
          nombreAlumno: 'Alumno',
          cantidadAcompanantes: 0,
          montoTotalPactado: 400000,
          saldoDeudor: 0,
          mesaExtraPrecio: precio,
          mesaExtraCantidad: cantidad,
          mesaExtraCuotas: cuotas,
        );

    test('sin precio de mesa no hay nada que reconciliar', () {
      final c = contrato(precio: 0, cantidad: 0, cuotas: 1);
      expect(MesasExtraUtils.estadoMesasReconciliado(contrato: c, pagos: []),
          isNull);
    });

    test('caso Ponce: 140.000 pasa a 2 mesas; lo pagado va a la Mesa 1', () {
      final pagos = [
        pago('Mesa Extra (1/7)', 20000, '2026-04-20T14:09:26Z'),
        pago('Mesa Extra (2/7)', 20000, '2026-06-03T20:11:39Z'),
        pago('Mesa Extra (3/7)', 20000, '2026-06-22T14:35:45Z'),
        pago('Cuota Base (1/9)', 30000, '2026-04-20T14:09:26Z'),
      ];
      final antes = MesasExtraUtils.estadoMesasReconciliado(
        contrato: contrato(precio: 140000, cantidad: 1, cuotas: 7),
        pagos: pagos,
      )!;
      expect(antes.cantidad, 1);
      expect(antes.mesas.single.pagado, 60000);

      final despues = MesasExtraUtils.estadoMesasReconciliado(
        contrato: contrato(precio: 140000, cantidad: 2, cuotas: 7),
        pagos: pagos,
      )!;
      expect(despues.cantidad, 2);
      expect(despues.mesas.map((m) => m.precio), [70000, 70000]);
      expect(despues.mesas.map((m) => m.pagado), [60000, 0]);
      expect(despues.mesas.map((m) => m.cuotasPagadas), [6, 0]);
      expect(MesasExtraUtils.totalPagado(despues.mesas), 60000);
    });

    test('caso Silvero: lo que pasa de una mesa sigue en la siguiente', () {
      final pagos = [
        for (var i = 1; i <= 5; i++)
          pago('Mesa Extra ($i/8)', 17500, '2026-0${i + 3}-01T12:00:00Z'),
      ];
      final r = MesasExtraUtils.estadoMesasReconciliado(
        contrato: contrato(precio: 140000, cantidad: 2, cuotas: 8),
        pagos: pagos,
      )!;
      expect(r.mesas.map((m) => m.pagado), [70000, 17500]);
      expect(r.mesas.first.liquidada, isTrue);
      expect(MesasExtraUtils.maxCuotasPagadas(r.mesas), 8);
    });

    test('pagos con número de mesa van a su mesa, no por orden', () {
      final pagos = [
        pago('Mesa Extra 2 (1/7)', 10000, '2026-04-01T12:00:00Z'),
        pago('Mesa Extra 1 (1/7)', 10000, '2026-05-01T12:00:00Z'),
        pago('Mesa Extra 2 (2/7)', 10000, '2026-06-01T12:00:00Z'),
      ];
      final r = MesasExtraUtils.estadoMesasReconciliado(
        contrato: contrato(precio: 140000, cantidad: 2, cuotas: 7),
        pagos: pagos,
      )!;
      expect(r.mesas.map((m) => m.pagado), [10000, 20000]);
    });

    test('la cantidad nunca baja de lo que dicen los pagos numerados', () {
      final pagos = [pago('Mesa Extra 3 (1/7)', 10000, '2026-04-01T12:00:00Z')];
      final r = MesasExtraUtils.estadoMesasReconciliado(
        contrato: contrato(precio: 210000, cantidad: 2, cuotas: 7),
        pagos: pagos,
      )!;
      expect(r.cantidad, 3);
    });
  });
}
