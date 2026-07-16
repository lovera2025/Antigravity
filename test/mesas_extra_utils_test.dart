import 'dart:math';

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

  test('tomarMesasDisponibles elige bloque consecutivo valido', () {
    final libres = [5, 10, 11, 12, 20];
    final picked = MesasExtraUtils.tomarMesasDisponibles(libres, 3);
    expect(picked, [10, 11, 12]);
    expect(libres, [5, 20]);
  });

  test('tomarMesasDisponibles elige al azar entre bloques consecutivos', () {
    final resultados = <String>{};
    for (var i = 0; i < 40; i++) {
      final libres = [5, 10, 11, 12, 13, 20];
      final picked = MesasExtraUtils.tomarMesasDisponibles(libres, 3);
      resultados.add(picked!.join(','));
    }
    expect(resultados.length, greaterThan(1));
  });

  test('tomarMesasDisponibles no usa fallback suelto si no hay bloque', () {
    final libres = [5, 10, 12, 20];
    expect(MesasExtraUtils.tomarMesasDisponibles(libres, 3), isNull);
    expect(libres, [5, 10, 12, 20]);
  });

  test('tomarMesasDisponibles prefiere bloque lejano', () {
    final libres = [1, 2, 3, 18, 19, 20];
    final picked = MesasExtraUtils.tomarMesasDisponibles(
      libres,
      3,
      preferirLejosDe: {2},
    );
    expect(picked, [18, 19, 20]);
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

  test('asignarMesasSorteo garantiza bloques consecutivos con extras', () {
    final conExtras = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 2,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000).toJson(),
      ],
    );
    final solo = ContratoAlumno(
      id: 'a2',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Solo',
      cantidadAcompanantes: 0,
      montoTotalPactado: 100000,
      saldoDeudor: 100000,
    );
    for (var seed = 0; seed < 25; seed++) {
      final asignados = MesasExtraUtils.asignarMesasSorteo(
        alumnos: [conExtras, solo],
        capacidadSalon: 20,
        ocupadasIniciales: {},
        random: Random(seed),
      );
      expect(asignados, isNotNull);
      final bloque = asignados!['a1']!;
      expect(bloque.length, 3);
      expect(MesasExtraUtils.bloqueEsConsecutivo(bloque), isTrue);
      expect(asignados['a2']!.length, 1);
    }
  });

  test('asignarMesasSorteo no falla con capacidad = demanda (salón limpio)', () {
    final alumnos = List.generate(15, (i) {
      if (i < 3) {
        return ContratoAlumno(
          id: 'e$i',
          eventoId: 'e1',
          nombreAlumno: 'Extra $i',
          cantidadAcompanantes: 0,
          montoTotalPactado: 200000,
          saldoDeudor: 100000,
          mesaExtraPrecio: 140000,
          mesaExtraCantidad: 2,
          mesasExtraEstadoRaw: [
            MesaExtraItem(n: 1, precio: 70000).toJson(),
            MesaExtraItem(n: 2, precio: 70000).toJson(),
          ],
        );
      }
      return ContratoAlumno(
        id: 's$i',
        eventoId: 'e1',
        nombreAlumno: 'Solo $i',
        cantidadAcompanantes: 0,
        montoTotalPactado: 100000,
        saldoDeudor: 100000,
      );
    });
    // 3*(1+2) + 12*1 = 21
    for (var seed = 0; seed < 20; seed++) {
      final asignados = MesasExtraUtils.asignarMesasSorteo(
        alumnos: alumnos,
        capacidadSalon: 21,
        ocupadasIniciales: {},
        random: Random(seed),
      );
      expect(asignados, isNotNull, reason: 'seed $seed');
      expect(asignados!.length, 15);
      for (final e in asignados.entries) {
        expect(MesasExtraUtils.bloqueEsConsecutivo(e.value), isTrue);
      }
    }
  });

  test('asignarMesasSorteo 2 físicas + 1 alejada: no vecinas', () {
    final a1 = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 70000,
      mesaExtraCantidad: 1,
    );
    final cap = MesasExtraUtils.capacidadMinimaSorteo(
      demanda: const DemandaSorteoMesas(
        alumnos: 1,
        mesasBase: 1,
        mesasExtras: 1,
        total: 2,
      ),
      totalAlejadas: 1,
    );
    for (var seed = 0; seed < 20; seed++) {
      final asignados = MesasExtraUtils.asignarMesasSorteo(
        alumnos: [a1],
        capacidadSalon: cap < 20 ? 20 : cap,
        ocupadasIniciales: {},
        separaciones: const [
          AlumnoMesasSeparadas(alumnoId: 'a1', cantidadAlejadas: 1),
        ],
        random: Random(seed),
      );
      expect(asignados, isNotNull, reason: 'seed $seed');
      final nums = asignados!['a1']!;
      expect(nums.length, 2);
      expect(MesasExtraUtils.bloqueEsConsecutivo(nums), isFalse);
      expect(MesasExtraUtils.numerosSonVecinos(nums[0], nums[1]), isFalse);
      expect((nums[0] - nums[1]).abs(), greaterThan(1));
    }
  });

  test('asignarMesasSorteo 3 físicas + 1 alejada: bloque de 2 + 1 lejos', () {
    final a1 = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 2,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000).toJson(),
      ],
    );
    for (var seed = 0; seed < 20; seed++) {
      final asignados = MesasExtraUtils.asignarMesasSorteo(
        alumnos: [a1],
        capacidadSalon: 30,
        ocupadasIniciales: {},
        separaciones: const [
          AlumnoMesasSeparadas(alumnoId: 'a1', cantidadAlejadas: 1),
        ],
        random: Random(seed),
      );
      expect(asignados, isNotNull, reason: 'seed $seed');
      final nums = List<int>.from(asignados!['a1']!)..sort();
      expect(nums.length, 3);

      // Exactamente un par consecutivo y una mesa aislada.
      final gaps = <int>[];
      for (var i = 1; i < nums.length; i++) {
        gaps.add(nums[i] - nums[i - 1]);
      }
      expect(gaps.where((g) => g == 1).length, 1);
      expect(gaps.any((g) => g > 1), isTrue);

      // La aislada no es vecina del bloque.
      int? bloqueA;
      int? bloqueB;
      int? aislada;
      if (nums[1] == nums[0] + 1) {
        bloqueA = nums[0];
        bloqueB = nums[1];
        aislada = nums[2];
      } else if (nums[2] == nums[1] + 1) {
        bloqueA = nums[1];
        bloqueB = nums[2];
        aislada = nums[0];
      }
      expect(bloqueA, isNotNull, reason: 'seed $seed nums=$nums');
      expect(
        MesasExtraUtils.bloquesSonVecinos([aislada!], [bloqueA!, bloqueB!]),
        isFalse,
      );
    }
  });

  test('asignarMesasSorteo 3 físicas + 2 alejadas: singles mutuamente lejos',
      () {
    final a1 = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 2,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000).toJson(),
      ],
    );
    for (var seed = 0; seed < 20; seed++) {
      final asignados = MesasExtraUtils.asignarMesasSorteo(
        alumnos: [a1],
        capacidadSalon: 40,
        ocupadasIniciales: {},
        separaciones: const [
          AlumnoMesasSeparadas(alumnoId: 'a1', cantidadAlejadas: 2),
        ],
        random: Random(seed),
      );
      expect(asignados, isNotNull, reason: 'seed $seed');
      final nums = List<int>.from(asignados!['a1']!)..sort();
      expect(nums.length, 3);
      expect(MesasExtraUtils.bloqueEsConsecutivo(nums), isFalse);
      for (var i = 0; i < nums.length; i++) {
        for (var j = i + 1; j < nums.length; j++) {
          expect(
            MesasExtraUtils.numerosSonVecinos(nums[i], nums[j]),
            isFalse,
            reason: 'seed $seed ${nums[i]}~${nums[j]}',
          );
          expect((nums[i] - nums[j]).abs(), greaterThan(1));
        }
      }
    }
  });

  test('asignarMesasSorteo sin marcar mantiene bloque entero consecutivo', () {
    final a1 = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 2,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000).toJson(),
      ],
    );
    final asignados = MesasExtraUtils.asignarMesasSorteo(
      alumnos: [a1],
      capacidadSalon: 10,
      ocupadasIniciales: {},
      separaciones: const [],
      random: Random(1),
    );
    expect(asignados, isNotNull);
    expect(MesasExtraUtils.bloqueEsConsecutivo(asignados!['a1']!), isTrue);
  });

  test('asignarMesasSorteo null si capacidad insuficiente', () {
    final a1 = ContratoAlumno(
      id: 'a1',
      eventoId: 'e1',
      nombreAlumno: 'Alumno Extra',
      cantidadAcompanantes: 0,
      montoTotalPactado: 200000,
      saldoDeudor: 100000,
      mesaExtraPrecio: 140000,
      mesaExtraCantidad: 2,
      mesasExtraEstadoRaw: [
        MesaExtraItem(n: 1, precio: 70000).toJson(),
        MesaExtraItem(n: 2, precio: 70000).toJson(),
      ],
    );
    final asignados = MesasExtraUtils.asignarMesasSorteo(
      alumnos: [a1],
      capacidadSalon: 2, // necesita 3
      ocupadasIniciales: {},
      separaciones: const [
        AlumnoMesasSeparadas(alumnoId: 'a1', cantidadAlejadas: 1),
      ],
      random: Random(1),
    );
    expect(asignados, isNull);
  });

  test('capacidadMinimaSorteo suma hueco por mesa alejada', () {
    const demanda = DemandaSorteoMesas(
      alumnos: 10,
      mesasBase: 10,
      mesasExtras: 5,
      total: 15,
    );
    expect(
      MesasExtraUtils.capacidadMinimaSorteo(
        demanda: demanda,
        totalAlejadas: 0,
      ),
      15,
    );
    expect(
      MesasExtraUtils.capacidadMinimaSorteo(
        demanda: demanda,
        totalAlejadas: 2,
      ),
      17,
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
}
