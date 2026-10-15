// El cobro de los eventos masivos, igual en la 5.0.0 y en la 6.0.0
// (sección 9, paso 9d: "las pruebas del modal de cobro").
//
// Corre el MISMO archivo en las dos versiones, sobre la MISMA copia de la base
// del usuario, y deja lo que da cada una en un JSON (y los PDF). Después se
// comparan. Lo que calcula la ventana de cobro no cambió desde la 5.0.0; sí la
// base (v73), el guardado de los contratos, la cola de subida y el recibo
// reimpreso. Esto mira que, con los datos reales, todo dé lo mismo.
//
// NUNCA abre la base real: trabaja sobre copias de la copia, en carpetas
// temporales que se borran al terminar. La nube apunta a ningún lado
// (http://localhost:1), así que no sale nada.
//
//   flutter test tool/cobro_igual_que_hoy_test.dart
//     --dart-define=copia=<data.db copiada con VACUUM INTO>
//     --dart-define=salida=<carpeta>
//     --dart-define=version=6.0.0
//     [--dart-define=alumnos=APELLIDO, NOMBRE;APELLIDO, NOMBRE]
//
// Tres partes:
//   1. La ventana y el papel de cada alumno de cada evento masivo: la ficha, el
//      recálculo desde los pagos, la mora (por cuota y la de ficha), lo que arma
//      el simulador del cobro y el recibo de su último cobro.
//   2. Las operaciones del día, de punta a punta, sobre otra copia: cobrar
//      cuota, mesa, sillas y mora, un abono y anular. Después de cada una, la
//      ficha, los pagos y lo que quedó para subir.
//   3. Los papeles de los alumnos elegidos (o, sin elegir, los cinco de la
//      parte 2): la planilla de mora de su institución, el resumen, y el
//      recibo después de cobrar, en PDF.
//
// El cobro se arma como la ventana (detalle_evento_masivo_screen.dart): las
// líneas con lineasPreviewDesglosePlan, el concepto con conceptoPagoPersistido,
// la línea de mora con construirPreviewMora (toda la mora tildada: cada cuota
// vencida y la de ficha), lo que queda con resolverMoraDeCobro, el patch de mesas con
// aplicarCobroPreviewAEstado y todo en registrarPagosLote. En efectivo, sin
// descuento y sin cargo por transferencia.
//
// En la carpeta de la 5.0.0 hay que poner antes las cuatro líneas de 3944fbe
// (en flutter test el PDF se guarda y no se abre): sin eso, la 5.0.0 abre cada
// PDF en el navegador. No cambian el papel.

// ignore_for_file: avoid_print

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arguello_events/core/database/local_database.dart';
import 'package:arguello_events/core/services/connectivity_service.dart';
import 'package:arguello_events/core/services/sync_engine.dart';
import 'package:arguello_events/core/utils/pago_interes_mora.dart';
import 'package:arguello_events/features/common/services/pdf_service.dart';
import 'package:arguello_events/features/common/utils/currency_extensions.dart';
import 'package:arguello_events/features/eventos/repositories/contratos_repository.dart';
import 'package:arguello_events/features/eventos/repositories/eventos_repository.dart';
import 'package:arguello_events/features/eventos/services/cobro_abono_acumulado.dart';
import 'package:arguello_events/features/eventos/services/cobro_masivo_conceptos_pdf.dart';
import 'package:arguello_events/features/eventos/services/cobro_mora_resolver.dart';
import 'package:arguello_events/features/eventos/services/concepto_pago_display.dart';
import 'package:arguello_events/features/eventos/services/dry_run_cobro_simulator.dart';
import 'package:arguello_events/features/eventos/services/filtro_mora_masivos.dart';
import 'package:arguello_events/features/eventos/services/mesas_extra_utils.dart';
import 'package:arguello_events/features/eventos/services/mora_concepto_rotulo.dart';
import 'package:arguello_events/features/eventos/services/mora_cuota_calculator.dart';
import 'package:arguello_events/features/eventos/services/mora_tracked_origen.dart';
import 'package:arguello_events/features/mi_empresa/repositories/finanzas_repository.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/mesa_extra_item.dart';

const _copia = String.fromEnvironment('copia');
const _salida = String.fromEnvironment('salida');
const _version = String.fromEnvironment('version', defaultValue: 'sin-version');
const _alumnosElegidos = String.fromEnvironment('alumnos');

const _motivoAnulacion = 'prueba sobre una copia: se anula el cobro de la cuota';

// ── JSON estable ────────────────────────────────────────────────────────────

/// Lo vuelve JSON con las claves ordenadas y los decimales a centavos, para que
/// dos corridas iguales den el mismo texto.
Object? _j(Object? v) {
  if (v == null || v is bool || v is String || v is int) return v;
  if (v is double) {
    final r = double.parse(v.toStringAsFixed(2));
    return r == 0 ? 0.0 : r;
  }
  if (v is num) return v;
  if (v is DateTime) return v.toIso8601String();
  if (v is Enum) return v.name;
  if (v is Map) {
    final m = SplayTreeMap<String, Object?>();
    for (final e in v.entries) {
      m[e.key.toString()] = _j(e.value);
    }
    return m;
  }
  if (v is Iterable) return v.map(_j).toList();
  return v.toString();
}

int _orden(Object? a, Object? b) => jsonEncode(a).compareTo(jsonEncode(b));

Map<String, Object?> _cuota(MoraCuotaDetalle d) => {
  'cuota': d.numeroCuota,
  'vence': d.vencimiento,
  'dias': d.diasMora,
  'interes': d.interesBruto,
  'mes': d.mesLabel,
};

Map<String, Object?> _arrastre(MoraPendientePreviaDetalle d) => {
  'cuota': d.numeroCuota,
  'mes': d.mesLabel,
  'atribuido': d.montoAtribuido,
  'pago_cuota': d.fechaPagoCuota,
  'debida': d.moraDebida,
  'cobrada': d.moraCobrada,
};

// ── La base de cada parte ───────────────────────────────────────────────────

class _Copia {
  final Directory docs;
  final ContratosRepository contratos;
  final FinanzasRepository finanzas;
  final EventosRepository eventos;
  _Copia(this.docs, this.contratos, this.finanzas, this.eventos);
}

/// Una copia nueva de la copia, en una carpeta temporal, con `LocalDatabase`
/// apuntando ahí. En la 6.0.0, abrirla la migra de la v71 a la v73, como al
/// instalar.
Future<_Copia> _abrirCopia(String nombre) async {
  await LocalDatabase.close();
  final docs = Directory.systemTemp.createTempSync('cobro_$nombre');
  final carpeta = Directory('${docs.path}${Platform.pathSeparator}Junior Eventos')
    ..createSync(recursive: true);
  File(_copia).copySync('${carpeta.path}${Platform.pathSeparator}data.db');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => docs.path,
      );
  final supabase = SupabaseClient('http://localhost:1', 'anon-de-prueba');
  final connectivity = ConnectivityService();
  final engine = SyncEngine(connectivity: connectivity, supabase: supabase);
  await LocalDatabase.instance;
  return _Copia(
    docs,
    ContratosRepository(supabase, connectivity),
    FinanzasRepository(supabase, connectivity, engine),
    EventosRepository(supabase, connectivity, engine),
  );
}

Future<void> _cerrarCopia(_Copia c) async {
  await LocalDatabase.close();
  try {
    c.docs.deleteSync(recursive: true);
  } catch (_) {}
}

bool _deBaja(ContratoAlumno a) =>
    a.nombreAlumno.trim().toUpperCase().startsWith('[BAJA]');

Future<List<String>> _eventosMasivos() async {
  final db = await LocalDatabase.instance;
  final rows = await db.rawQuery(
    "SELECT id FROM eventos WHERE modalidad = 'masivo' ORDER BY id",
  );
  return [for (final r in rows) r['id'] as String];
}

// ── Lo que debe cada alumno, como lo ve la ventana ─────────────────────────

class _Deuda {
  final ContratoAlumno a;
  final List<Map<String, dynamic>> pagos;
  final double moraCobrada;
  final ({double total, List<MoraCuotaDetalle> desglose, double tracked}) mora;
  final int tCuotas;
  final int mCuotas;
  final int sCuotas;
  final double cuotaPura;
  final double deudaBase;
  final double deudaMesa;
  final double deudaSillas;
  final List<MesaExtraItem> mesasEstado;
  final List<MesaExtraItem> mesasActivas;
  final int cantMesas;
  final Map<String, double> historico;

  _Deuda._(
    this.a,
    this.pagos,
    this.moraCobrada,
    this.mora,
    this.tCuotas,
    this.mCuotas,
    this.sCuotas,
    this.cuotaPura,
    this.deudaBase,
    this.deudaMesa,
    this.deudaSillas,
    this.mesasEstado,
    this.mesasActivas,
    this.cantMesas,
    this.historico,
  );

  static Future<_Deuda> de(ContratosRepository repo, ContratoAlumno a) async {
    final pagos = await repo.getHistorialPagosAlumno(a.id);
    final moraCobrada = await repo.sumMoraCobradaHistorial(a.id);
    final mora = MoraCuotaCalculator.moraPendienteOperativaDetallada(
      contrato: a,
      moraCobradaHistorial: moraCobrada,
    );
    final tCuotas = a.totalCuotas > 0 ? a.totalCuotas : 9;
    final mCuotas = a.mesaExtraCuotas > 0 ? a.mesaExtraCuotas : 1;
    final sCuotas = a.sillasExtraCuotas > 0 ? a.sillasExtraCuotas : 1;
    final totalBase =
        (a.montoTotalPactado - a.mesaExtraPrecio - a.sillasExtraPrecioTotal)
            .clamp(0.0, double.infinity);
    final cuotaPura = tCuotas > 0
        ? double.parse((totalBase / tCuotas).toStringAsFixed(2))
        : totalBase;
    final mesasEstado = MesasExtraUtils.estadoDesdeContrato(a);
    final mesasActivas = MesasExtraUtils.mesasActivas(mesasEstado);
    final deudaBase = (totalBase -
            (a.montoTotalPactado -
                a.saldoDeudor -
                a.mesaExtraPagado -
                a.sillasExtraPagado))
        .clamp(0.0, double.infinity);
    final deudaMesa = mesasActivas.isEmpty
        ? (a.mesaExtraPrecio - a.mesaExtraPagado).clamp(0.0, double.infinity)
        : mesasActivas.fold<double>(0, (s, m) => s + m.deuda);
    final deudaSillas = (a.sillasExtraPrecioTotal - a.sillasExtraPagado).clamp(
      0.0,
      double.infinity,
    );
    return _Deuda._(
      a,
      pagos,
      moraCobrada,
      mora,
      tCuotas,
      mCuotas,
      sCuotas,
      cuotaPura,
      deudaBase,
      deudaMesa,
      deudaSillas,
      mesasEstado,
      mesasActivas,
      MesasExtraUtils.cantidadMesasContrato(a, mesasEstado),
      grossHistoricoPorConceptoKeyExtended(pagos),
    );
  }

  bool get activo => !_deBaja(a) && a.saldoDeudor > 0.01;

  /// Líneas de la ventana para un concepto del plan, como `_previewDesdePlan`
  /// del simulador (neto = bruto: sin descuento).
  List<Map<String, dynamic>> _lineas({
    required String etiqueta,
    required double gross,
    required double cuotaPlan,
    required int cuotasPlan,
    required double historicoClase,
    int? mesaN,
  }) {
    final lineas = lineasPreviewDesglosePlan(
      modo: ModoPagoConceptoTipo.total,
      cuotasSeleccionadas: null,
      grossTotal: gross,
      cuotaPura: cuotaPlan,
      totalCuotas: cuotasPlan,
      grossHistorico: historicoClase,
      etiqueta: etiqueta,
    );
    Map<String, dynamic> conMesa(Map<String, dynamic> m) {
      if (mesaN != null) m['mesaN'] = mesaN;
      return m;
    }

    if (lineas.isEmpty) {
      return [
        conMesa({'concepto': etiqueta, 'monto': gross, 'gross': gross, 'cuotas': 0}),
      ];
    }
    return [
      for (final l in lineas)
        conMesa({
          'concepto': l.concepto,
          if (l.subtexto != null) 'subtexto': l.subtexto,
          'monto': l.gross,
          'gross': l.gross,
          'cuotas': l.cuotasLiquidadas,
        }),
    ];
  }

  double _tope(double cuota, double deuda) =>
      double.parse((cuota > deuda ? deuda : cuota).toStringAsFixed(2));

  List<Map<String, dynamic>> lineaCuotaBase({bool abono = false}) {
    if (deudaBase <= 0.01 || cuotaPura <= 0.01) return const [];
    var gross = _tope(cuotaPura, deudaBase);
    if (abono) gross = double.parse((gross / 2).toStringAsFixed(2));
    return _lineas(
      etiqueta: 'Cuota Base',
      gross: gross,
      cuotaPlan: cuotaPura,
      cuotasPlan: tCuotas,
      historicoClase: historico['Base'] ?? 0.0,
    );
  }

  List<Map<String, dynamic>> lineaMesa() {
    if (deudaMesa <= 0.01) return const [];
    if (mesasActivas.isNotEmpty) {
      final m = mesasActivas.first;
      final cuota = mCuotas > 0
          ? double.parse((m.precio / mCuotas).toStringAsFixed(2))
          : m.precio;
      return _lineas(
        etiqueta: MesasExtraUtils.labelCobro(m.n, cantMesas),
        gross: _tope(cuota, m.deuda),
        cuotaPlan: cuota,
        cuotasPlan: mCuotas,
        historicoClase:
            historico[MesasExtraUtils.claveCobro(m.n)] ?? historico['Mesa'] ?? 0,
        mesaN: m.n,
      );
    }
    if (a.mesaExtraPrecio <= 0.01) return const [];
    final cuota = mCuotas > 0
        ? double.parse((a.mesaExtraPrecio / mCuotas).toStringAsFixed(2))
        : a.mesaExtraPrecio;
    return _lineas(
      etiqueta: 'Mesa Extra',
      gross: _tope(cuota, deudaMesa),
      cuotaPlan: cuota,
      cuotasPlan: mCuotas,
      historicoClase: historico['Mesa'] ?? 0.0,
      mesaN: 1,
    );
  }

  List<Map<String, dynamic>> lineaSillas() {
    if (deudaSillas <= 0.01 || a.sillasExtraPrecioTotal <= 0.01) {
      return const [];
    }
    final cuota = sCuotas > 0
        ? double.parse((a.sillasExtraPrecioTotal / sCuotas).toStringAsFixed(2))
        : a.sillasExtraPrecioTotal;
    return _lineas(
      etiqueta: sCuotas <= 1 ? 'Sillas Extras - Entrega' : 'Sillas Extras',
      gross: _tope(cuota, deudaSillas),
      cuotaPlan: cuota,
      cuotasPlan: sCuotas,
      historicoClase: historico['Sillas'] ?? 0.0,
    );
  }

  /// Toda la mora, como cuando el operador tilda todas las cuotas vencidas y
  /// toda la de ficha: `lineaPreviewInteresMora` de la ventana.
  List<Map<String, dynamic>> lineaMora() {
    if (mora.total <= 0.01) return const [];
    final remanente = mora.tracked;
    final origen = remanente > 0.01
        ? MoraTrackedOrigen.inferir(
            contratoBase: a,
            pagos: pagos,
            trackedMonto: remanente,
            recorte: MoraOrigenRecorte.loQueQueda,
          )
        : const <MoraPendientePreviaDetalle>[];
    final pendiente = remanente <= 0.01
        ? 0.0
        : origen.isEmpty
        ? remanente
        : origen
              .fold<double>(0, (s, x) => s + x.montoAtribuido)
              .clamp(0.0, remanente);
    final pendiente2 = double.parse(pendiente.toStringAsFixed(2));
    return [
      MoraConceptoRotulo.construirPreviewMora(
        montoTotal: mora.total,
        detallesCalendario: mora.desglose,
        montoPendientePrevias: pendiente2,
        lineKind: kLineKindInteresMora,
        detallePendiente: pendiente2 > 0.01
            ? origen.where((x) => x.numeroCuota > 0).toList()
            : const <MoraPendientePreviaDetalle>[],
      ),
    ];
  }
}

// ── Cobrar como la ventana ──────────────────────────────────────────────────

class _Cobro {
  final List<Map<String, dynamic>> preview;
  final List<Map<String, dynamic>> conceptosFinales;
  final ResolucionMoraCobro mora;
  final double montoIngresado;
  final ContratoAlumno? fresco;
  final List<String> idsPagos;
  _Cobro(
    this.preview,
    this.conceptosFinales,
    this.mora,
    this.montoIngresado,
    this.fresco,
    this.idsPagos,
  );
}

/// Lo que hace el botón COBRAR de la ventana, en efectivo, sin descuento y sin
/// cargo: arma el contrato post-cobro, resuelve la mora, arma las líneas y el
/// patch, y guarda todo en un solo lote.
Future<_Cobro> _cobrarComoLaVentana(
  ContratosRepository repo,
  _Deuda d,
  List<Map<String, dynamic>> preview,
  DateTime fechaCobroAr,
) async {
  final a = d.a;
  final cPagadas = a.cuotasPagadas;
  final mPagadas = a.mesaExtraCuotasPagadas;
  final sPagadas = a.sillasExtraCuotasPagadas;

  var nuevasBase = 0, nuevasMesa = 0, nuevasSillas = 0;
  var totalDeducidoBruto = 0.0, grossMesaPagado = 0.0, grossSillasPagado = 0.0;
  for (final conc in preview) {
    if (esLineaCargoCanalDry(conc) || esLineaInteresMoraDry(conc)) continue;
    final cTexto = (conc['concepto'] as String).toUpperCase();
    final cCuotas = ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99);
    final cGross = (conc['gross'] as num).toDouble();
    if (cTexto.contains('BASE')) nuevasBase += cCuotas;
    if (cTexto.contains('MESA')) {
      nuevasMesa += cCuotas;
      grossMesaPagado += cGross;
    }
    if (cTexto.contains('SILLA')) {
      nuevasSillas += cCuotas;
      grossSillasPagado += cGross;
    }
    totalDeducidoBruto += cGross;
  }

  final grossHistoricoPlan = (d.historico['Base'] ?? 0.0) +
      (d.historico['Mesa'] ?? 0.0) +
      (d.historico['Sillas'] ?? 0.0);
  final saldoRestante = double.parse(
    (a.montoTotalPactado - grossHistoricoPlan - totalDeducidoBruto)
        .toStringAsFixed(2),
  ).clamp(0.0, double.infinity);

  var currentBasePagadas = (cPagadas + nuevasBase).clamp(0, d.tCuotas);
  var currentMesaPagadas =
      (mPagadas + nuevasMesa).clamp(0, d.mCuotas > 0 ? d.mCuotas : 1);
  var currentSillasPagadas =
      (sPagadas + nuevasSillas).clamp(0, d.sCuotas > 0 ? d.sCuotas : 1);
  if (saldoRestante <= 0.01) {
    currentBasePagadas = d.tCuotas;
    currentMesaPagadas = (a.mesaExtraPrecio > 0 && d.mCuotas > 0) ? d.mCuotas : 0;
    currentSillasPagadas =
        (a.sillasExtraPrecioTotal > 0 && d.sCuotas > 0) ? d.sCuotas : 0;
  }

  final conceptosFinales = conceptosFinalesDesdePreviewMasivo(
    previewConceptos: preview,
    esLineaCargoCanal: esLineaCargoCanalDry,
    esLineaInteresMora: esLineaInteresMoraDry,
    cPagadas: cPagadas,
    tCuotas: d.tCuotas,
    mPagadas: mPagadas,
    mCuotas: d.mCuotas,
    sPagadas: sPagadas,
    sCuotas: d.sCuotas,
    cantMesas: d.cantMesas,
  );

  final mesasPatch = grossMesaPagado > 0.01 && d.mesasEstado.isNotEmpty
      ? MesasExtraUtils.aplicarCobroPreviewAEstado(
          estado: d.mesasEstado,
          lineasPreview: preview,
          cuotasPlan: d.mCuotas,
        )
      : d.mesasEstado;

  final alumnoFresco = a.copyWith(
    saldoDeudor: saldoRestante,
    cuotasPagadas: currentBasePagadas,
    mesaExtraCuotasPagadas: currentMesaPagadas,
    sillasExtraCuotasPagadas: currentSillasPagadas,
    mesaExtraPagado: a.mesaExtraPagado + grossMesaPagado,
    sillasExtraPagado: a.sillasExtraPagado + grossSillasPagado,
    mesasExtraEstadoRaw: grossMesaPagado > 0.01 && mesasPatch.isNotEmpty
        ? mesasPatch.map((e) => e.toJson()).toList()
        : a.mesasExtraEstadoRaw,
  );

  final moraEsteCobro = preview
      .where(esLineaInteresMoraDry)
      .fold<double>(0, (s, c) => s + (c['monto'] as num).toDouble());

  final moraResuelta = resolverMoraDeCobro(
    contratoPre: a,
    contratoPost: alumnoFresco,
    moraCobradaHistorial: d.moraCobrada,
    moraEsteCobro: moraEsteCobro,
    cuotasBaseLiquidadasEnCobro:
        (currentBasePagadas - cPagadas).clamp(0, d.tCuotas),
    cuotasBasePagadasPostCobro: currentBasePagadas,
    saldoDeudorPost: saldoRestante,
    fechaCobroAr: fechaCobroAr,
    formatoMonto: (v) => v.toCurrency(),
  );

  final lineas = <PagoLoteLinea>[];
  for (final conc in preview) {
    final cTexto = conc['concepto'] as String;
    final monto = (conc['monto'] as num).toDouble();
    if (monto <= 0.004) continue;
    final lineKind = conc['lineKind'] as String?;
    lineas.add(
      PagoLoteLinea(
        monto: monto,
        concepto: MesasExtraUtils.conceptoPagoPersistido(
          previewLinea: conc,
          conceptoOriginal: cTexto,
          cantidadMesas: d.cantMesas,
        ),
        montoADescontarDeSaldo: (conc['gross'] as num?)?.toDouble() ?? monto,
        descuentoPorcentaje: 0,
        cuotasLiquidadas: ((conc['cuotas'] as num?)?.toInt() ?? 0).clamp(0, 99),
        medioPago: 'Efectivo',
        lineKind: lineKind,
        moraPendienteAntesDeLote:
            lineKind == kLineKindInteresMora ? d.mora.total : null,
      ),
    );
  }

  final estado = moraResuelta.estado;
  final patch = <String, dynamic>{
    if (grossMesaPagado > 0.01 && mesasPatch.isNotEmpty) ...{
      'mesas_extra_estado': mesasPatch.map((e) => e.toJson()).toList(),
      'mesa_extra_pagado': double.parse(
        MesasExtraUtils.totalPagado(mesasPatch).toStringAsFixed(2),
      ),
      'mesa_extra_cuotas_pagadas': MesasExtraUtils.maxCuotasPagadas(mesasPatch),
    },
    'mora_pendiente_tracked': double.parse(estado.tracked.toStringAsFixed(2)),
    'mora_cobrada_offset': estado.offset,
    if (moraResuelta.limpiarMoraReferencia) 'mora_fecha_referencia': null,
    if (estado.exentaHastaIso != null) 'mora_exenta_hasta': estado.exentaHastaIso,
    'mora_exencion_reinicia': estado.reinicia ? 1 : 0,
  };

  final antes = {for (final p in await repo.getHistorialPagosAlumno(a.id)) p['id']};
  final fresco = await repo.registrarPagosLote(
    contratoId: a.id,
    lineas: lineas,
    contratoPatch: patch,
  );
  final despues = await repo.getHistorialPagosAlumno(a.id);
  final ids = [
    for (final p in despues)
      if (!antes.contains(p['id'])) p['id'] as String,
  ];

  return _Cobro(
    preview,
    conceptosFinales,
    moraResuelta,
    preview.fold<double>(0, (s, c) => s + (c['monto'] as num).toDouble()),
    fresco,
    ids,
  );
}

// ── El estado de un alumno en la base, para comparar ───────────────────────

Future<Map<String, Object?>> _estado(String contratoId) async {
  final db = await LocalDatabase.instance;
  final contrato = Map<String, Object?>.from(
    (await db.query(
      'contratos_alumnos',
      where: 'id = ?',
      whereArgs: [contratoId],
    )).first,
  )..remove('updated_at');

  const variables = {
    'id',
    'contrato_alumno_id',
    'fecha_pago',
    'created_at',
    'updated_at',
    'fecha_anulacion',
  };
  final filasPagos = await db.query(
    'pagos_contrato_alumno',
    where: 'contrato_alumno_id = ?',
    whereArgs: [contratoId],
  );
  final idsPagos = {for (final p in filasPagos) p['id'] as String};
  final pagos = [
    for (final p in filasPagos)
      _j({
        for (final e in p.entries)
          if (!variables.contains(e.key)) e.key: e.value,
      }),
  ]..sort(_orden);

  final cola = <Object?>[];
  for (final r in await db.query('_sync_queue')) {
    final rid = r['registro_id'] as String?;
    final esContrato = rid == contratoId;
    if (!esContrato && !idsPagos.contains(rid)) continue;
    final payload = Map<String, dynamic>.from(
      jsonDecode(r['payload'] as String) as Map,
    )..removeWhere((k, _) => variables.contains(k));
    cola.add(
      _j({
        'tabla': r['tabla'],
        'operacion': r['operacion'],
        'de': esContrato ? 'el contrato' : 'un pago',
        'payload': payload,
      }),
    );
  }
  cola.sort(_orden);

  final repo = ContratosRepository(
    SupabaseClient('http://localhost:1', 'anon-de-prueba'),
    ConnectivityService(),
  );
  final a = (await repo.getContratoById(contratoId))!;
  final d = await _Deuda.de(repo, a);
  return {
    'contrato': _j(contrato),
    'pagos': pagos,
    'para_subir': cola,
    'mora': _j({
      'total': d.mora.total,
      'de_ficha': d.mora.tracked,
      'por_cuota': [for (final c in d.mora.desglose) _cuota(c)],
    }),
  };
}

// ── Parte 1 ─────────────────────────────────────────────────────────────────

Future<Map<String, Object?>> _ventanaYPapel(_Copia c) async {
  final repo = c.contratos;
  final eventos = <Object?>[];
  var alumnos = 0, escenarios = 0, escenariosMal = 0;
  for (final eventoId in await _eventosMasivos()) {
    final contratos = (await repo.getByEvento(eventoId))
      ..sort((x, y) => x.id.compareTo(y.id));
    final filas = <Object?>[];
    for (final a in contratos) {
      final d = await _Deuda.de(repo, a);
      final rec = recalcularSaldoDesdePagos(
        montoTotalPactado: a.montoTotalPactado,
        totalCuotas: a.totalCuotas,
        mesaExtraPrecio: a.mesaExtraPrecio,
        sillasExtraPrecioTotal: a.sillasExtraPrecioTotal,
        precioUnitarioMesaExtra: a.precioUnitarioMesaExtra,
        mesaExtraCuotas: a.mesaExtraCuotas,
        mesaExtraCantidad: a.mesaExtraCantidad,
        sillasExtraCuotas: a.sillasExtraCuotas,
        pagos: d.pagos,
      );
      final arrastre = a.moraPendienteTracked > 0.01
          ? MoraTrackedOrigen.inferir(
              contratoBase: a,
              pagos: d.pagos,
              trackedMonto: a.moraPendienteTracked,
              recorte: MoraOrigenRecorte.loQueQueda,
            )
          : const <MoraPendientePreviaDetalle>[];
      final sim = simularContratoDryRun(alumno: a, pagos: d.pagos);
      final lote = await repo.getUltimosPagosLote(a.id);
      final recibo = lote.isEmpty
          ? const <Map<String, dynamic>>[]
          : lineasDisplayParaPdf(
              ConceptoPagoDisplay.conceptosPdfDesdePagosLote(
                a,
                lote,
                historialCompleto: d.pagos,
              ),
            );
      alumnos++;
      for (final e in sim.escenarios) {
        escenarios++;
        if (!e.ok) escenariosMal++;
      }
      filas.add(
        _j({
          'alumno': a.nombreAlumno,
          'ficha': a.toJson(),
          'debe': {
            'base': d.deudaBase,
            'mesa': d.deudaMesa,
            'sillas': d.deudaSillas,
            'cuota_base': d.cuotaPura,
            'mesas': d.cantMesas,
          },
          'recalculo_desde_pagos': {
            'saldo': rec.saldoDeudor,
            'cuotas_base': rec.cuotasBase,
            'cuotas_mesa': rec.cuotasMesa,
            'cuotas_sillas': rec.cuotasSillas,
            'bruto_base': rec.grossBase,
            'bruto_mesa': rec.grossMesa,
            'bruto_sillas': rec.grossSillas,
          },
          'mora': {
            'total': d.mora.total,
            'de_ficha': d.mora.tracked,
            'cobrada': d.moraCobrada,
            'por_cuota': [for (final x in d.mora.desglose) _cuota(x)],
            'de_donde_viene_la_de_ficha': [for (final x in arrastre) _arrastre(x)],
          },
          'ventana': {
            'integridad': sim.advertenciasIntegridad,
            'cobros': [
              for (final e in sim.escenarios)
                {
                  'cobro': e.nombre,
                  'ok': e.ok,
                  'error': e.error,
                  'bruto': e.grossPlan,
                  'neto': e.netPlan,
                  'lineas_ventana': e.lineasPreview,
                  'lineas_papel': e.lineasPdf,
                },
            ],
          },
          'ultimo_recibo': recibo,
        }),
      );
    }
    eventos.add({'evento': eventoId, 'alumnos': filas});
  }
  print('Parte 1: $alumnos alumnos, $escenarios cobros simulados '
      '($escenariosMal que el simulador marca mal).');
  return {
    'alumnos': alumnos,
    'cobros_simulados': escenarios,
    'cobros_marcados_mal': escenariosMal,
    'eventos': eventos,
  };
}

// ── Parte 2 ─────────────────────────────────────────────────────────────────

/// Los cinco alumnos de las operaciones: el primero (por id) que sirve para
/// cada una, sin repetir. Sale de la copia, así que es el mismo en las dos
/// versiones.
Future<Map<String, _Deuda>> _elegirParaOperar(ContratosRepository repo) async {
  final todos = <_Deuda>[];
  for (final ev in await _eventosMasivos()) {
    for (final a in await repo.getByEvento(ev)) {
      final d = await _Deuda.de(repo, a);
      if (d.activo) todos.add(d);
    }
  }
  todos.sort((x, y) => x.a.id.compareTo(y.a.id));
  final usados = <String>{};
  _Deuda? primero(bool Function(_Deuda) sirve) {
    for (final d in todos) {
      if (usados.contains(d.a.id) || !sirve(d)) continue;
      usados.add(d.a.id);
      return d;
    }
    return null;
  }

  final out = <String, _Deuda>{};
  void poner(String k, _Deuda? d) {
    if (d != null) out[k] = d;
  }

  poner('cuota', primero((d) => d.lineaCuotaBase().isNotEmpty && d.mora.total < 0.01));
  poner('mesa', primero((d) => d.lineaMesa().isNotEmpty));
  poner('sillas', primero((d) => d.lineaSillas().isNotEmpty));
  poner('mora', primero((d) => d.lineaMora().isNotEmpty));
  poner('abono', primero((d) => d.lineaCuotaBase(abono: true).isNotEmpty));
  return out;
}

Future<Map<String, Object?>> _operacionesDelDia(_Copia c, DateTime hoy) async {
  final repo = c.contratos;
  final elegidos = await _elegirParaOperar(repo);
  final pasos = <Object?>[];

  Future<void> paso(
    String que,
    _Deuda? d,
    List<Map<String, dynamic>> Function(_Deuda) lineas,
  ) async {
    if (d == null) {
      pasos.add({'paso': que, 'alumno': null, 'nota': 'no hay alumno para esto'});
      return;
    }
    final antes = await _estado(d.a.id);
    final cobro = await _cobrarComoLaVentana(repo, d, lineas(d), hoy);
    pasos.add(
      _j({
        'paso': que,
        'alumno': d.a.nombreAlumno,
        'lo_cobrado': cobro.preview,
        'papel': cobro.conceptosFinales,
        'mora_que_queda': cobro.mora.moraPendientePost,
        'mora_de_donde': cobro.mora.moraPendienteOrigen,
        'antes': antes,
        'despues': await _estado(d.a.id),
      }),
    );
    if (que == 'cuota') _idsCuota = cobro.idsPagos;
  }

  await paso('cuota', elegidos['cuota'], (d) => d.lineaCuotaBase());
  await paso('mesa', elegidos['mesa'], (d) => d.lineaMesa());
  await paso('sillas', elegidos['sillas'], (d) => d.lineaSillas());
  await paso('mora', elegidos['mora'], (d) => d.lineaMora());
  await paso('abono', elegidos['abono'], (d) => d.lineaCuotaBase(abono: true));

  final cuota = elegidos['cuota'];
  if (cuota != null && _idsCuota.isNotEmpty) {
    final antes = await _estado(cuota.a.id);
    final tocados = await c.finanzas.anularPagosConMotivo(
      [for (final id in _idsCuota) (tabla: 'pagos_contrato_alumno', id: id)],
      _motivoAnulacion,
    );
    for (final id in tocados) {
      await repo.recalcularProgresoContrato(id);
    }
    pasos.add(
      _j({
        'paso': 'anular la cuota',
        'alumno': cuota.a.nombreAlumno,
        'antes': antes,
        'despues': await _estado(cuota.a.id),
      }),
    );
  }

  print('Parte 2: ${pasos.length} operaciones sobre '
      '${elegidos.length} alumnos: '
      '${elegidos.entries.map((e) => '${e.key} = ${e.value.a.nombreAlumno}').join(' · ')}.');
  return {'operaciones': pasos};
}

var _idsCuota = <String>[];

// ── Parte 3 ─────────────────────────────────────────────────────────────────

Set<String> _pdfs(Directory docs) => {
  for (final f in docs.listSync(recursive: true))
    if (f is File && f.path.toLowerCase().endsWith('.pdf')) f.path,
};

Future<String?> _guardarNuevo(
  Directory docs,
  Set<String> antes,
  Directory destino,
  String nombre,
) async {
  final nuevos = _pdfs(docs).difference(antes);
  if (nuevos.isEmpty) return null;
  final f = File(nuevos.first);
  final final_ = '${destino.path}${Platform.pathSeparator}$nombre.pdf';
  f.copySync(final_);
  return final_;
}

String _archivo(String s) => s
    .replaceAll(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ ]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');

Future<Map<String, Object?>> _papeles(_Copia c, DateTime hoy) async {
  final repo = c.contratos;
  final destino = Directory(
    '$_salida${Platform.pathSeparator}pdf_$_version',
  )..createSync(recursive: true);

  // Los elegidos por nombre, o los cinco de la parte 2.
  final elegidos = <_Deuda>[];
  if (_alumnosElegidos.trim().isNotEmpty) {
    final buscados = [
      for (final n in _alumnosElegidos.split(';'))
        if (n.trim().isNotEmpty) n.trim().toUpperCase(),
    ];
    final todos = <ContratoAlumno>[];
    for (final ev in await _eventosMasivos()) {
      todos.addAll(await repo.getByEvento(ev));
    }
    for (final b in buscados) {
      final a = todos.where((x) => x.nombreAlumno.toUpperCase().contains(b));
      if (a.isEmpty) {
        print('No encontré a "$b".');
        continue;
      }
      elegidos.add(await _Deuda.de(repo, a.first));
    }
  } else {
    elegidos.addAll((await _elegirParaOperar(repo)).values);
  }

  final generados = <Object?>[];
  var n = 0;

  // La planilla de mora de cada institución, antes de cobrar nada: como la
  // saca el operador con el filtro "Con mora" y sin elegir curso.
  final eventosHechos = <String>{};
  for (final d in elegidos) {
    final ev = d.a.eventoId;
    if (!eventosHechos.add(ev)) continue;
    final evento = await c.eventos.getById(ev);
    final alumnos = await repo.getByEvento(ev);
    final moraPorAlumno = <String, MoraDeAlumno>{};
    final arrastre = <String, List<MoraPendientePreviaDetalle>>{};
    for (final a in alumnos) {
      final x = await _Deuda.de(repo, a);
      moraPorAlumno[a.id] = x.mora;
      if (a.moraPendienteTracked > 0.01) {
        arrastre[a.id] = MoraTrackedOrigen.inferir(
          contratoBase: a,
          pagos: x.pagos,
          trackedMonto: a.moraPendienteTracked,
          recorte: MoraOrigenRecorte.loQueQueda,
        );
      }
    }
    MoraPdfFila filaDe(ContratoAlumno a) {
      final m = moraPorAlumno[a.id];
      final vencida =
          m?.desglose.fold<double>(0, (s, x) => s + x.interesBruto) ?? 0;
      final total = a.totalCuotas > 0 ? a.totalCuotas : 9;
      return MoraPdfFila(
        nombre: a.nombreAlumno.replaceFirst('[BAJA]', '').trim(),
        curso: (a.cursoDivision ?? '').trim(),
        telefono: (a.telefono ?? '').trim(),
        cuotas: '${a.cuotasPagadas}/$total',
        moraVencida: vencida,
        detalleVencida: (m?.desglose ?? const <MoraCuotaDetalle>[])
            .where((x) => x.interesBruto > 0.01)
            .map(
              (x) =>
                  'C${x.numeroCuota} (${x.mesLabel.split(' ').first}) '
                  '${x.diasMora}d ${x.interesBruto.toCurrency()}',
            )
            .join(' · '),
        moraNoCobrada: m?.tracked ?? 0,
        detalleNoCobrada: MoraConceptoRotulo.desgloseArrastre(
          arrastre[a.id] ?? const [],
          formatoMonto: (v) => v.toCurrency(),
        ),
        saldoPlan: a.saldoDeudor,
      );
    }

    final conMora = alumnos
        .where((a) => cumpleFiltroMora(a, moraPorAlumno, FiltroMora.conMora))
        .toList();
    if (conMora.isEmpty) continue;
    final antes = _pdfs(c.docs);
    await PdfService.generarPlanillaMoraPdf(
      eventoTitulo: evento?.cliente?.nombreCompleto.trim().isNotEmpty == true
          ? evento!.cliente!.nombreCompleto.trim()
          : 'Evento masivo',
      filtroTitulo: FiltroMora.conMora.label,
      generadoEn: hoy,
      filas: conMora.map(filaDe).toList(),
    );
    n++;
    final nombre =
        '${n.toString().padLeft(2, '0')}_planilla_mora_${_archivo(evento?.cliente?.nombreCompleto ?? ev)}';
    generados.add({
      'papel': 'planilla de mora',
      'evento': evento?.cliente?.nombreCompleto,
      'alumnos_con_mora': conMora.length,
      'archivo': await _guardarNuevo(c.docs, antes, destino, nombre),
    });
  }

  // El resumen (antes de cobrar) y el recibo (después), alumno por alumno:
  // la cuota que sigue, la mesa, las sillas y la mora que deba.
  for (final d in elegidos) {
    final evento = await c.eventos.getById(d.a.eventoId);
    final preview = [
      ...d.lineaCuotaBase(),
      ...d.lineaMesa(),
      ...d.lineaSillas(),
      ...d.lineaMora(),
    ];
    final quien = _archivo(d.a.nombreAlumno);
    if (preview.isEmpty || evento == null) {
      generados.add({'alumno': d.a.nombreAlumno, 'nota': 'no debe nada hoy'});
      continue;
    }
    final conceptosFinales = conceptosFinalesDesdePreviewMasivo(
      previewConceptos: preview,
      esLineaCargoCanal: esLineaCargoCanalDry,
      esLineaInteresMora: esLineaInteresMoraDry,
      cPagadas: d.a.cuotasPagadas,
      tCuotas: d.tCuotas,
      mPagadas: d.a.mesaExtraCuotasPagadas,
      mCuotas: d.mCuotas,
      sPagadas: d.a.sillasExtraCuotasPagadas,
      sCuotas: d.sCuotas,
      cantMesas: d.cantMesas,
    );
    final suma = preview.fold<double>(
      0,
      (s, x) => s + (x['monto'] as num).toDouble(),
    );

    var antes = _pdfs(c.docs);
    await PdfService.generarResumenAbonarAlumno(
      alumno: d.a,
      evento: evento,
      subtotalLiquidacion: suma,
      totalAbonar: suma,
      conceptosLineas: conceptosFinales,
      medioPago: 'Efectivo',
      moraPendienteNoIncluida: 0,
    );
    n++;
    generados.add({
      'papel': 'resumen',
      'alumno': d.a.nombreAlumno,
      'archivo': await _guardarNuevo(
        c.docs,
        antes,
        destino,
        '${n.toString().padLeft(2, '0')}_resumen_$quien',
      ),
    });

    final cobro = await _cobrarComoLaVentana(repo, d, preview, hoy);
    final fresco = cobro.fresco ?? d.a;
    final moraHist = await repo.sumMoraCobradaHistorial(fresco.id);
    final detalle = MoraCuotaCalculator.moraPendienteOperativaDetallada(
      contrato: fresco,
      moraCobradaHistorial: moraHist,
    );
    var moraRestante = cobro.mora.moraPendientePost;
    var moraOrigen = cobro.mora.moraPendienteOrigen;
    var desglose = const <MoraCuotaDetalle>[];
    var arrastre = const <MoraPendientePreviaDetalle>[];
    if ((detalle.total - moraRestante).abs() < 0.02) {
      arrastre = detalle.tracked > 0.01
          ? MoraTrackedOrigen.inferir(
              contratoBase: fresco,
              pagos: await repo.getHistorialPagosAlumno(fresco.id),
              trackedMonto: detalle.tracked,
              recorte: MoraOrigenRecorte.loQueQueda,
            )
          : const [];
      final linea = MoraConceptoRotulo.origenMoraPendienteLinea(
        desglose: detalle.desglose,
        tracked: detalle.tracked,
        trackedDetalle: arrastre,
        formatoMonto: (v) => v.toCurrency(),
      );
      if (linea.isNotEmpty) moraOrigen = linea;
      desglose = detalle.desglose;
    }

    antes = _pdfs(c.docs);
    await PdfService.generarReciboAlumno(
      alumno: fresco,
      evento: evento,
      montoPagado: cobro.montoIngresado,
      saldoPendiente: double.parse(fresco.saldoDeudor.toStringAsFixed(2)),
      conceptosPagados: cobro.conceptosFinales,
      fechaManual: hoy,
      moraPendienteRestante: moraRestante,
      moraPendienteOrigen: moraOrigen,
      moraPendienteDesglose: desglose,
      moraPendienteArrastre: arrastre,
      esReimpresion: false,
      medioPago: 'Efectivo',
    );
    n++;
    generados.add({
      'papel': 'recibo',
      'alumno': d.a.nombreAlumno,
      'cobrado': cobro.montoIngresado,
      'saldo_despues': fresco.saldoDeudor,
      'mora_que_queda': moraRestante,
      'archivo': await _guardarNuevo(
        c.docs,
        antes,
        destino,
        '${n.toString().padLeft(2, '0')}_recibo_$quien',
      ),
    });
  }
  print('Parte 3: ${generados.length} papeles en ${destino.path}.');
  return {'papeles': _j(generados)};
}

/// El resumen y la planilla de mora piden la Outfit con `PdfGoogleFonts`, que
/// la baja de internet; en flutter test no hay red y caían a Helvetica. En la
/// app, con internet, salen en Outfit. Acá se deja la misma letra en la memoria
/// del paquete, desde los archivos de la app, y no se baja nada.
Future<void> _letrasComoConInternet() async {
  for (final nombre in ['Outfit-Regular', 'Outfit-Bold']) {
    final f = File('assets${Platform.pathSeparator}google_fonts'
        '${Platform.pathSeparator}$nombre.ttf');
    await PdfBaseCache.defaultCache.add(nombre, f.readAsBytesSync());
  }
}

// ── La corrida ──────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el cobro de los masivos, con los datos del usuario ($_version)', () async {
    expect(_copia, isNotEmpty, reason: 'Falta --dart-define=copia=...');
    expect(_salida, isNotEmpty, reason: 'Falta --dart-define=salida=...');
    final real = '${Platform.environment['USERPROFILE']}\\Documents\\'
        'Junior Eventos\\data.db';
    expect(
      File(_copia).absolute.path.toLowerCase(),
      isNot(File(real).absolute.path.toLowerCase()),
      reason: 'Esto trabaja sobre una copia, nunca sobre la base real.',
    );
    expect(File(_copia).existsSync(), isTrue, reason: 'No está la copia.');
    Directory(_salida).createSync(recursive: true);
    await _letrasComoConInternet();

    // Un mediodía fijo de hoy: la mora del día es la misma en las dos corridas
    // y el papel lleva la misma fecha.
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day, 12);

    final salida = <String, Object?>{'version': _version, 'dia': hoy};

    var c = await _abrirCopia('ventana');
    try {
      final db = await LocalDatabase.instance;
      salida['version_de_la_base'] =
          (await db.rawQuery('PRAGMA user_version')).first.values.first;
      salida['ventana_y_papel'] = await _ventanaYPapel(c);
    } finally {
      await _cerrarCopia(c);
    }

    c = await _abrirCopia('operaciones');
    try {
      salida['operaciones_del_dia'] = await _operacionesDelDia(c, hoy);
    } finally {
      await _cerrarCopia(c);
    }

    c = await _abrirCopia('papeles');
    try {
      salida['papeles'] = await _papeles(c, hoy);
    } finally {
      await _cerrarCopia(c);
    }

    final archivo = File(
      '$_salida${Platform.pathSeparator}cobro_$_version.json',
    );
    archivo.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(_j(salida)),
    );
    print('Listo: ${archivo.path}');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
