import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ingreso_detallado.dart';
import '../../../core/utils/ar_time.dart';
import '../../cierre_caja/models/turno_caja.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../repositories/finanzas_repository.dart';
import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/services/pdf_service.dart';
import 'package:flutter/material.dart';
import '../../../main.dart';
import '../../../core/database/local_database.dart';
import '../../../core/utils/pago_interes_mora.dart';
import '../bolsa_personal_helpers.dart';
import '../../dashboard/providers/dashboard_provider.dart';

export '../bolsa_personal_helpers.dart' show finanzasEgresoAfectaCajaEmpresa;

/// Clasificación única de medio de pago para buckets EFECTIVO / TRANSFERENCIA del HUD.
bool finanzasEsMedioTransferencia(String? medioPago) =>
    medioPago?.toLowerCase().trim() == 'transferencia';

/// Gastos operativos del negocio (excluye retiros al bolsillo y gastos personales).
bool finanzasEgresoEsGastoOperativoNegocio(Egreso e) {
  final cat = (e.categoria ?? '').trim();
  return cat != kCategoriaGastoPersonal && cat != kCategoriaRetiroDueno;
}

/// Modo del panel «Resumen de caja» (HUD): día, solo cobros históricos o saldo empresa con proyección local.
enum FinanzasHudModo {
  /// Ingresos cobrados hoy (calendario AR); métricas secundarias del mismo día.
  hoy,

  /// Suma histórica de todos los ingresos locales (sin restar egresos).
  acumuladoIngresos,

  /// Ingresos históricos − egresos históricos (misma base SQLite que el listado), gastos últimos 30 días locales y retiros de bolsillo aparte en UI.
  acumuladoNeto,
}

class FinanzasState {
  final List<IngresoDetallado> ingresos;
  final List<Egreso> egresos;
  final double totalIngresos;
  final double totalEgresos;
  final double balanceGlobal;
  final DateTime? mesFiltro;
  final String? eventoIdFiltro;
  /// Día puntual (calendario AR) para drill-down en Salud / Flujo / categorías.
  final DateTime? fechaExactaFiltro;
  /// Día elegido para el modo «HOY» del Resumen de caja (`null` = siempre el día actual según [ArTime.nowAr]).
  final DateTime? fechaInteligenciaHud;
  final Map<String, dynamic>? proyeccionFinanciera;

  /// Totales globales (sin filtro mes/evento) para el HUD; alineados con SQLite local.
  final double hudIngresosHoy;
  /// Subtotales de hoy por medio de pago (misma base que [ingresosHoyLista]).
  final double hudIngresosHoyEfectivo;
  final double hudIngresosHoyTransferencia;
  final double hudIngresosHoyOtrosMedio;
  /// Ingresos del día (calendario AR) sin filtro mes/evento; para detalle al tocar efectivo/transferencia.
  final List<IngresoDetallado> ingresosHoyLista;
  /// Egresos del mismo día que [ingresosHoyLista] (calendario AR, sin filtro listado).
  final List<Egreso> egresosHoyLista;
  final double hudEgresosHoy;
  final double hudTotalIngresosHistoricoGlobal;
  /// Cobros históricos por medio (misma regla que [hudIngresosHoyEfectivo] / [hudIngresosHoyTransferencia]).
  final double hudTotalIngresosHistoricoEfectivo;
  final double hudTotalIngresosHistoricoTransferencia;
  /// Todos los ingresos locales sin filtro mes/evento; drill-down histórico del HUD.
  final List<IngresoDetallado> ingresosHistoricosLista;
  /// Suma egresos que afectan saldo empresa ([finanzasEgresoAfectaCajaEmpresa]).
  final double hudTotalEgresosHistoricoGlobal;
  /// Egresos empresa históricos por medio (misma regla que el total).
  final double hudTotalEgresosHistoricoEfectivo;
  final double hudTotalEgresosHistoricoTransferencia;
  /// Gastos personales que restaron directo del negocio ([empresa]).
  final double hudGastosPersonalEmpresaTotal;
  /// Cobros históricos − gastos empresa históricos, por medio.
  final double hudEfectivoNetoHistorico;
  final double hudTransferenciaNetaHistorica;
  final double hudOpex30DiasLocal;
  final double hudProyeccion30DiasLocal;
  final FinanzasHudModo hudModoInteligencia;

  /// Turno seleccionado en el HUD para los buckets EFECTIVO/TRANSFERENCIA netos.
  /// `dia` (default) considera todo el día; `manana`/`tarde` aplican el corte horario AR.
  final TurnoCaja hudTurno;

  /// Retiros de caja que descuentan del bucket netos (categoría = 'Retiro de caja').
  final double hudRetirosEfectivoHoy;
  final double hudRetirosTransferenciaHoy;

  /// Ingresos del turno menos retiros del turno (mismos criterios de filtrado).
  final double hudEfectivoNetoHoy;
  final double hudTransferenciaNetaHoy;

  /// Sumas históricas de egresos categoría [kCategoriaRetiroDueno] (retiros al bolsillo personal).
  final double hudRetirosBolsaPersonalTotal;
  final double hudRetirosBolsaPersonalEfectivo;
  final double hudRetirosBolsaPersonalTransferencia;
  /// Retiros al bolsillo en el día del HUD (seleccionado o hoy AR).
  final double hudRetirosBolsaPersonalHoy;

  /// Gastos registrados desde el bolsillo ([kCategoriaGastoPersonal]) por medio.
  final double hudGastosBolsaPersonalTotal;
  final double hudGastosBolsaPersonalEfectivo;
  final double hudGastosBolsaPersonalTransferencia;
  final double hudGastosBolsaPersonalHoy;

  /// Retiro al bolsillo sin gastar aún: `max(0, retiros − gastos desde pendiente)` por medio.
  final double hudSaldoBolsaPersonalTotal;
  final double hudSaldoBolsaPersonalEfectivo;
  final double hudSaldoBolsaPersonalTransferencia;

  FinanzasState({
    required this.ingresos,
    required this.egresos,
    required this.totalIngresos,
    required this.totalEgresos,
    required this.balanceGlobal,
    this.mesFiltro,
    this.eventoIdFiltro,
    this.fechaExactaFiltro,
    this.fechaInteligenciaHud,
    this.proyeccionFinanciera,
    this.hudIngresosHoy = 0,
    this.hudIngresosHoyEfectivo = 0,
    this.hudIngresosHoyTransferencia = 0,
    this.hudIngresosHoyOtrosMedio = 0,
    this.ingresosHoyLista = const [],
    this.egresosHoyLista = const [],
    this.hudEgresosHoy = 0,
    this.hudTotalIngresosHistoricoGlobal = 0,
    this.hudTotalIngresosHistoricoEfectivo = 0,
    this.hudTotalIngresosHistoricoTransferencia = 0,
    this.ingresosHistoricosLista = const [],
    this.hudTotalEgresosHistoricoGlobal = 0,
    this.hudTotalEgresosHistoricoEfectivo = 0,
    this.hudTotalEgresosHistoricoTransferencia = 0,
    this.hudGastosPersonalEmpresaTotal = 0,
    this.hudEfectivoNetoHistorico = 0,
    this.hudTransferenciaNetaHistorica = 0,
    this.hudOpex30DiasLocal = 0,
    this.hudProyeccion30DiasLocal = 0,
    this.hudModoInteligencia = FinanzasHudModo.acumuladoNeto,
    this.hudTurno = TurnoCaja.dia,
    this.hudRetirosEfectivoHoy = 0,
    this.hudRetirosTransferenciaHoy = 0,
    this.hudEfectivoNetoHoy = 0,
    this.hudTransferenciaNetaHoy = 0,
    this.hudRetirosBolsaPersonalTotal = 0,
    this.hudRetirosBolsaPersonalEfectivo = 0,
    this.hudRetirosBolsaPersonalTransferencia = 0,
    this.hudRetirosBolsaPersonalHoy = 0,
    this.hudGastosBolsaPersonalTotal = 0,
    this.hudGastosBolsaPersonalEfectivo = 0,
    this.hudGastosBolsaPersonalTransferencia = 0,
    this.hudGastosBolsaPersonalHoy = 0,
    this.hudSaldoBolsaPersonalTotal = 0,
    this.hudSaldoBolsaPersonalEfectivo = 0,
    this.hudSaldoBolsaPersonalTransferencia = 0,
  });

  FinanzasState copyWith({
    List<IngresoDetallado>? ingresos,
    List<Egreso>? egresos,
    double? totalIngresos,
    double? totalEgresos,
    double? balanceGlobal,
    DateTime? mesFiltro,
    String? eventoIdFiltro,
    DateTime? fechaExactaFiltro,
    DateTime? fechaInteligenciaHud,
    Map<String, dynamic>? proyeccionFinanciera,
    double? hudIngresosHoy,
    double? hudIngresosHoyEfectivo,
    double? hudIngresosHoyTransferencia,
    double? hudIngresosHoyOtrosMedio,
    List<IngresoDetallado>? ingresosHoyLista,
    List<Egreso>? egresosHoyLista,
    double? hudEgresosHoy,
    double? hudTotalIngresosHistoricoGlobal,
    double? hudTotalIngresosHistoricoEfectivo,
    double? hudTotalIngresosHistoricoTransferencia,
    List<IngresoDetallado>? ingresosHistoricosLista,
    double? hudTotalEgresosHistoricoGlobal,
    double? hudTotalEgresosHistoricoEfectivo,
    double? hudTotalEgresosHistoricoTransferencia,
    double? hudGastosPersonalEmpresaTotal,
    double? hudEfectivoNetoHistorico,
    double? hudTransferenciaNetaHistorica,
    double? hudOpex30DiasLocal,
    double? hudProyeccion30DiasLocal,
    FinanzasHudModo? hudModoInteligencia,
    TurnoCaja? hudTurno,
    double? hudRetirosEfectivoHoy,
    double? hudRetirosTransferenciaHoy,
    double? hudEfectivoNetoHoy,
    double? hudTransferenciaNetaHoy,
    double? hudRetirosBolsaPersonalTotal,
    double? hudRetirosBolsaPersonalEfectivo,
    double? hudRetirosBolsaPersonalTransferencia,
    double? hudRetirosBolsaPersonalHoy,
    double? hudGastosBolsaPersonalTotal,
    double? hudGastosBolsaPersonalEfectivo,
    double? hudGastosBolsaPersonalTransferencia,
    double? hudGastosBolsaPersonalHoy,
    double? hudSaldoBolsaPersonalTotal,
    double? hudSaldoBolsaPersonalEfectivo,
    double? hudSaldoBolsaPersonalTransferencia,
    bool clearMesFiltro = false,
    bool clearEventoIdFiltro = false,
    bool clearFechaExacta = false,
    bool clearFechaInteligenciaHud = false,
  }) {
    return FinanzasState(
      ingresos: ingresos ?? this.ingresos,
      egresos: egresos ?? this.egresos,
      totalIngresos: totalIngresos ?? this.totalIngresos,
      totalEgresos: totalEgresos ?? this.totalEgresos,
      balanceGlobal: balanceGlobal ?? this.balanceGlobal,
      mesFiltro: clearMesFiltro ? null : (mesFiltro ?? this.mesFiltro),
      eventoIdFiltro: clearEventoIdFiltro ? null : (eventoIdFiltro ?? this.eventoIdFiltro),
      fechaExactaFiltro: clearFechaExacta ? null : (fechaExactaFiltro ?? this.fechaExactaFiltro),
      fechaInteligenciaHud: clearFechaInteligenciaHud ? null : (fechaInteligenciaHud ?? this.fechaInteligenciaHud),
      proyeccionFinanciera: proyeccionFinanciera ?? this.proyeccionFinanciera,
      hudIngresosHoy: hudIngresosHoy ?? this.hudIngresosHoy,
      hudIngresosHoyEfectivo: hudIngresosHoyEfectivo ?? this.hudIngresosHoyEfectivo,
      hudIngresosHoyTransferencia: hudIngresosHoyTransferencia ?? this.hudIngresosHoyTransferencia,
      hudIngresosHoyOtrosMedio: hudIngresosHoyOtrosMedio ?? this.hudIngresosHoyOtrosMedio,
      ingresosHoyLista: ingresosHoyLista ?? this.ingresosHoyLista,
      egresosHoyLista: egresosHoyLista ?? this.egresosHoyLista,
      hudEgresosHoy: hudEgresosHoy ?? this.hudEgresosHoy,
      hudTotalIngresosHistoricoGlobal: hudTotalIngresosHistoricoGlobal ?? this.hudTotalIngresosHistoricoGlobal,
      hudTotalIngresosHistoricoEfectivo: hudTotalIngresosHistoricoEfectivo ?? this.hudTotalIngresosHistoricoEfectivo,
      hudTotalIngresosHistoricoTransferencia:
          hudTotalIngresosHistoricoTransferencia ?? this.hudTotalIngresosHistoricoTransferencia,
      ingresosHistoricosLista: ingresosHistoricosLista ?? this.ingresosHistoricosLista,
      hudTotalEgresosHistoricoGlobal: hudTotalEgresosHistoricoGlobal ?? this.hudTotalEgresosHistoricoGlobal,
      hudTotalEgresosHistoricoEfectivo: hudTotalEgresosHistoricoEfectivo ?? this.hudTotalEgresosHistoricoEfectivo,
      hudTotalEgresosHistoricoTransferencia:
          hudTotalEgresosHistoricoTransferencia ?? this.hudTotalEgresosHistoricoTransferencia,
      hudGastosPersonalEmpresaTotal:
          hudGastosPersonalEmpresaTotal ?? this.hudGastosPersonalEmpresaTotal,
      hudEfectivoNetoHistorico: hudEfectivoNetoHistorico ?? this.hudEfectivoNetoHistorico,
      hudTransferenciaNetaHistorica: hudTransferenciaNetaHistorica ?? this.hudTransferenciaNetaHistorica,
      hudOpex30DiasLocal: hudOpex30DiasLocal ?? this.hudOpex30DiasLocal,
      hudProyeccion30DiasLocal: hudProyeccion30DiasLocal ?? this.hudProyeccion30DiasLocal,
      hudModoInteligencia: hudModoInteligencia ?? this.hudModoInteligencia,
      hudTurno: hudTurno ?? this.hudTurno,
      hudRetirosEfectivoHoy: hudRetirosEfectivoHoy ?? this.hudRetirosEfectivoHoy,
      hudRetirosTransferenciaHoy: hudRetirosTransferenciaHoy ?? this.hudRetirosTransferenciaHoy,
      hudEfectivoNetoHoy: hudEfectivoNetoHoy ?? this.hudEfectivoNetoHoy,
      hudTransferenciaNetaHoy: hudTransferenciaNetaHoy ?? this.hudTransferenciaNetaHoy,
      hudRetirosBolsaPersonalTotal: hudRetirosBolsaPersonalTotal ?? this.hudRetirosBolsaPersonalTotal,
      hudRetirosBolsaPersonalEfectivo: hudRetirosBolsaPersonalEfectivo ?? this.hudRetirosBolsaPersonalEfectivo,
      hudRetirosBolsaPersonalTransferencia: hudRetirosBolsaPersonalTransferencia ?? this.hudRetirosBolsaPersonalTransferencia,
      hudRetirosBolsaPersonalHoy: hudRetirosBolsaPersonalHoy ?? this.hudRetirosBolsaPersonalHoy,
      hudGastosBolsaPersonalTotal: hudGastosBolsaPersonalTotal ?? this.hudGastosBolsaPersonalTotal,
      hudGastosBolsaPersonalEfectivo: hudGastosBolsaPersonalEfectivo ?? this.hudGastosBolsaPersonalEfectivo,
      hudGastosBolsaPersonalTransferencia: hudGastosBolsaPersonalTransferencia ?? this.hudGastosBolsaPersonalTransferencia,
      hudGastosBolsaPersonalHoy: hudGastosBolsaPersonalHoy ?? this.hudGastosBolsaPersonalHoy,
      hudSaldoBolsaPersonalTotal: hudSaldoBolsaPersonalTotal ?? this.hudSaldoBolsaPersonalTotal,
      hudSaldoBolsaPersonalEfectivo: hudSaldoBolsaPersonalEfectivo ?? this.hudSaldoBolsaPersonalEfectivo,
      hudSaldoBolsaPersonalTransferencia: hudSaldoBolsaPersonalTransferencia ?? this.hudSaldoBolsaPersonalTransferencia,
    );
  }

  /// Cobros históricos − egresos que afectan saldo empresa (operativos, retiros pendientes, gastos personales [empresa]).
  double get hudPlataDelNegocio =>
      hudTotalIngresosHistoricoGlobal - hudTotalEgresosHistoricoGlobal;

  /// Total histórico gastado a título personal.
  double get hudGastadoPersonalTotal => hudGastosBolsaPersonalTotal;

  /// Retiro pendiente sin gastar (alias de [hudSaldoBolsaPersonalTotal]).
  double get hudRetiroPendienteTotal => hudSaldoBolsaPersonalTotal;

  /// Gastos operativos históricos (sin retiros pendientes ni gastos personales [empresa]).
  double get hudGastosOperativosHistoricoGlobal =>
      hudTotalEgresosHistoricoGlobal - hudRetirosBolsaPersonalTotal - hudGastosPersonalEmpresaTotal;

  double get hudGastosOperativosHistoricoEfectivo =>
      hudTotalEgresosHistoricoEfectivo - hudRetirosBolsaPersonalEfectivo;

  double get hudGastosOperativosHistoricoTransferencia =>
      hudTotalEgresosHistoricoTransferencia - hudRetirosBolsaPersonalTransferencia;

  /// Neto del día (cobros − salidas del negocio).
  double get hudNetoDelDia => hudIngresosHoy - hudEgresosHoy;
}

class FinanzasNotifier extends AsyncNotifier<FinanzasState> {
  RealtimeChannel? _channel;

  @override
  Future<FinanzasState> build() async {
    ref.onDispose(() {
      _channel?.unsubscribe();
    });

    _setupRealtime();
    final ar = ArTime.nowAr();
    final mesDefecto = DateTime(ar.year, ar.month, 1);
    return _fetchData(mesDefecto, null);
  }

  void _setupRealtime() {
    final repo = ref.read(finanzasRepositoryProvider);
    _channel = repo.subscribeToChanges(() async {
      // Recarga silenciosa: mantenemos los filtros actuales
      final curMes = state.value?.mesFiltro;
      final curEventoId = state.value?.eventoIdFiltro;
      final curFe = state.value?.fechaExactaFiltro;
      final curHudFe = state.value?.fechaInteligenciaHud;

      // Actualizamos solo si el estado actual tiene valor (evita carreras en carga inicial)
      if (state.hasValue) {
        state = await AsyncValue.guard(() => _fetchData(
              curMes,
              curEventoId,
              preserveFechaExacta: curFe,
              preserveHudModo: state.value?.hudModoInteligencia,
              preserveFechaInteligenciaHud: curHudFe,
              preserveHudTurno: state.value?.hudTurno,
            ));
      }
    });
  }

  /// Suma de egresos cuyo día (AR) cae en [inicioDiaAr, finDiaAr] inclusive.
  static double _sumEgresosEnRangoCalendarioAr(List<Egreso> todos, DateTime inicioDiaAr, DateTime finDiaAr) {
    var s = 0.0;
    for (final e in todos) {
      if (e.fecha == null) continue;
      final d = ArTime.toAr(e.fecha!);
      final dd = DateTime(d.year, d.month, d.day);
      if (dd.isBefore(inicioDiaAr) || dd.isAfter(finDiaAr)) continue;
      s += e.monto;
    }
    return s;
  }

  static DateTime _soloDiaCalendarioAr(DateTime cualquier) {
    final a = ArTime.toAr(cualquier);
    return DateTime(a.year, a.month, a.day);
  }

  Future<FinanzasState> _fetchData(
    DateTime? mes,
    String? eventoId, {
    DateTime? preserveFechaExacta,
    FinanzasHudModo? preserveHudModo,
    DateTime? preserveFechaInteligenciaHud,
    TurnoCaja? preserveHudTurno,
  }) async {
    final finanzasRepo = ref.read(finanzasRepositoryProvider);
    final egresosRepo = ref.read(egresosRepositoryProvider);

    final results = await Future.wait([
      finanzasRepo.obtenerIngresosDetallados(mes: null, eventoId: null),
      egresosRepo.getEgresosConEvento(),
      finanzasRepo.obtenerProyeccionFinanciera(),
    ]);

    final ingresosFull = results[0] as List<IngresoDetallado>;
    final egresosRaw = results[1] as List<dynamic>;
    final proyeccion = results[2] as Map<String, dynamic>?;

    List<Egreso> egresosFull = egresosRaw.map((e) => Egreso.fromJson(e)).toList();

    var ingresosList = ingresosFull;
    if (eventoId != null) {
      ingresosList = ingresosList.where((i) => i.eventoId == eventoId).toList();
    }
    if (mes != null) {
      ingresosList = ingresosList.where((i) => ArTime.mismoMes(i.fecha, mes)).toList();
    }

    var egresosList = egresosFull;
    if (eventoId != null) {
      egresosList = egresosList.where((e) => e.eventoId == eventoId).toList();
    }
    if (mes != null) {
      egresosList = egresosList.where((e) {
        if (e.fecha == null) return false;
        return ArTime.mismoMes(e.fecha!, mes);
      }).toList();
    }

    final totalIngresos = ingresosList.fold<double>(0, (sum, i) => sum + i.monto);
    final totalEgresos = egresosList.fold<double>(0, (sum, e) => sum + e.monto);
    final totalEgresosSaldoEmpresa = egresosList
        .where(finanzasEgresoAfectaCajaEmpresa)
        .fold<double>(0, (sum, e) => sum + e.monto);
    final balanceGlobal = totalIngresos - totalEgresosSaldoEmpresa;

    final nAr = ArTime.nowAr();
    final hoyDia = DateTime(nAr.year, nAr.month, nAr.day);
    final preservedHud = preserveFechaInteligenciaHud;
    final diaHudRef =
        preservedHud != null ? _soloDiaCalendarioAr(preservedHud) : hoyDia;

    double hudIngresosHoy = 0;
    double hudIngresosHoyEfectivo = 0;
    double hudIngresosHoyTransferencia = 0;
    final ingresosHoyLista = <IngresoDetallado>[];
    for (final i in ingresosFull) {
      if (!ArTime.mismoDia(i.fecha, diaHudRef)) continue;
      ingresosHoyLista.add(i);
      hudIngresosHoy += i.monto;
      // Solo ingresos del día: transferencia aparte; el resto (incl. sin medio) suma a efectivo en el HUD.
      if (finanzasEsMedioTransferencia(i.medioPago)) {
        hudIngresosHoyTransferencia += i.monto;
      } else {
        hudIngresosHoyEfectivo += i.monto;
      }
    }
    ingresosHoyLista.sort((a, b) => b.fecha.compareTo(a.fecha));

    // Turno seleccionado para los buckets netos del HUD: ingresos siguen siendo del día,
    // pero los retiros de caja se descuentan según el turno (mañana / tarde / día).
    final turnoHud = preserveHudTurno ?? TurnoCaja.dia;
    final rangoHud = rangoHorarioAr(diaHudRef, turnoHud);

    final egresosHoyLista = <Egreso>[];
    double hudEgresosHoy = 0;
    double hudRetirosEfectivoHoy = 0;
    double hudRetirosTransferenciaHoy = 0;
    for (final e in egresosFull) {
      if (e.fecha != null && ArTime.mismoDia(e.fecha!, diaHudRef)) {
        egresosHoyLista.add(e);
        if (finanzasEgresoAfectaCajaEmpresa(e)) {
          hudEgresosHoy += e.monto;
        }
      }
      if (e.fecha == null) continue;
      if (!ArTime.mismoDia(e.fecha!, diaHudRef)) continue;
      if (!rangoHud.contiene(e.fecha!)) continue;
      if (!finanzasEgresoAfectaCajaEmpresa(e)) continue;
      // Egresos de empresa del turno restan del bucket (operadores, retiros, etc.).
      if (finanzasEsMedioTransferencia(e.medioPago)) {
        hudRetirosTransferenciaHoy += e.monto;
      } else {
        hudRetirosEfectivoHoy += e.monto;
      }
    }
    final hudEfectivoNetoHoy = hudIngresosHoyEfectivo - hudRetirosEfectivoHoy;
    final hudTransferenciaNetaHoy = hudIngresosHoyTransferencia - hudRetirosTransferenciaHoy;
    egresosHoyLista.sort((a, b) {
      final fa = a.fecha;
      final fb = b.fecha;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fb.compareTo(fa);
    });

    var hudTotalIngresosHistoricoEfectivo = 0.0;
    var hudTotalIngresosHistoricoTransferencia = 0.0;
    for (final i in ingresosFull) {
      if (finanzasEsMedioTransferencia(i.medioPago)) {
        hudTotalIngresosHistoricoTransferencia += i.monto;
      } else {
        hudTotalIngresosHistoricoEfectivo += i.monto;
      }
    }
    final hudTotalIngresosHistoricoGlobal =
        hudTotalIngresosHistoricoEfectivo + hudTotalIngresosHistoricoTransferencia;
    final ingresosHistoricosLista = List<IngresoDetallado>.from(ingresosFull)
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

    var hudTotalEgresosHistoricoEfectivo = 0.0;
    var hudTotalEgresosHistoricoTransferencia = 0.0;
    for (final e in egresosFull) {
      if (!finanzasEgresoAfectaCajaEmpresa(e)) continue;
      if (finanzasEsMedioTransferencia(e.medioPago)) {
        hudTotalEgresosHistoricoTransferencia += e.monto;
      } else {
        hudTotalEgresosHistoricoEfectivo += e.monto;
      }
    }
    final hudTotalEgresosHistoricoGlobal =
        hudTotalEgresosHistoricoEfectivo + hudTotalEgresosHistoricoTransferencia;
    final hudEfectivoNetoHistorico = hudTotalIngresosHistoricoEfectivo - hudTotalEgresosHistoricoEfectivo;
    final hudTransferenciaNetaHistorica =
        hudTotalIngresosHistoricoTransferencia - hudTotalEgresosHistoricoTransferencia;

    var hudRetirosBolsaPersonalEfectivo = 0.0;
    var hudRetirosBolsaPersonalTransferencia = 0.0;
    var hudRetirosBolsaPersonalHoy = 0.0;
    for (final e in egresosFull) {
      if ((e.categoria ?? '').trim() != kCategoriaRetiroDueno) continue;
      if (finanzasEsMedioTransferencia(e.medioPago)) {
        hudRetirosBolsaPersonalTransferencia += e.monto;
      } else {
        hudRetirosBolsaPersonalEfectivo += e.monto;
      }
      if (e.fecha != null && ArTime.mismoDia(e.fecha!, diaHudRef)) {
        hudRetirosBolsaPersonalHoy += e.monto;
      }
    }
    final hudRetirosBolsaPersonalTotal =
        hudRetirosBolsaPersonalEfectivo + hudRetirosBolsaPersonalTransferencia;

    var hudGastosBolsaPersonalEfectivo = 0.0;
    var hudGastosBolsaPersonalTransferencia = 0.0;
    var hudGastosBolsaPersonalHoy = 0.0;
    var hudGastosPendienteEfectivo = 0.0;
    var hudGastosPendienteTransferencia = 0.0;
    var hudGastosPersonalEmpresaTotal = 0.0;
    for (final e in egresosFull) {
      if ((e.categoria ?? '').trim() != kCategoriaGastoPersonal) continue;
      if (gastoPersonalEsDesdeEmpresa(e)) {
        hudGastosPersonalEmpresaTotal += e.monto;
      }
      if (finanzasEsMedioTransferencia(e.medioPago)) {
        hudGastosBolsaPersonalTransferencia += e.monto;
        if (finanzasGastoPersonalConsumePendiente(e)) {
          hudGastosPendienteTransferencia += e.monto;
        }
      } else {
        hudGastosBolsaPersonalEfectivo += e.monto;
        if (finanzasGastoPersonalConsumePendiente(e)) {
          hudGastosPendienteEfectivo += e.monto;
        }
      }
      if (e.fecha != null && ArTime.mismoDia(e.fecha!, diaHudRef)) {
        hudGastosBolsaPersonalHoy += e.monto;
      }
    }
    final hudGastosBolsaPersonalTotal =
        hudGastosBolsaPersonalEfectivo + hudGastosBolsaPersonalTransferencia;

    final hudSaldoBolsaPersonalEfectivo =
        (hudRetirosBolsaPersonalEfectivo - hudGastosPendienteEfectivo).clamp(0.0, double.infinity);
    final hudSaldoBolsaPersonalTransferencia =
        (hudRetirosBolsaPersonalTransferencia - hudGastosPendienteTransferencia)
            .clamp(0.0, double.infinity);
    final hudSaldoBolsaPersonalTotal =
        hudSaldoBolsaPersonalEfectivo + hudSaldoBolsaPersonalTransferencia;

    final limite30 = hoyDia.subtract(const Duration(days: 30));
    final egresosParaOpexEmpresa = egresosFull.where(finanzasEgresoEsGastoOperativoNegocio).toList();
    final hudOpex30DiasLocal = _sumEgresosEnRangoCalendarioAr(egresosParaOpexEmpresa, limite30, hoyDia);
    final capNeto = hudTotalIngresosHistoricoGlobal - hudTotalEgresosHistoricoGlobal;
    final hudProyeccion30DiasLocal = capNeto - hudOpex30DiasLocal;

    DateTime? fe = preserveFechaExacta;
    if (fe != null) {
      if (mes == null || !ArTime.mismoMes(fe, mes)) {
        fe = null;
      }
    }

    final fechaHudStored =
        preservedHud != null ? _soloDiaCalendarioAr(preservedHud) : null;

    return FinanzasState(
      ingresos: ingresosList,
      egresos: egresosList,
      totalIngresos: totalIngresos,
      totalEgresos: totalEgresos,
      balanceGlobal: balanceGlobal,
      mesFiltro: mes,
      eventoIdFiltro: eventoId,
      fechaExactaFiltro: fe,
      fechaInteligenciaHud: fechaHudStored,
      proyeccionFinanciera: proyeccion,
      hudIngresosHoy: hudIngresosHoy,
      hudIngresosHoyEfectivo: hudIngresosHoyEfectivo,
      hudIngresosHoyTransferencia: hudIngresosHoyTransferencia,
      hudIngresosHoyOtrosMedio: 0,
      ingresosHoyLista: ingresosHoyLista,
      egresosHoyLista: egresosHoyLista,
      hudEgresosHoy: hudEgresosHoy,
      hudTotalIngresosHistoricoGlobal: hudTotalIngresosHistoricoGlobal,
      hudTotalIngresosHistoricoEfectivo: hudTotalIngresosHistoricoEfectivo,
      hudTotalIngresosHistoricoTransferencia: hudTotalIngresosHistoricoTransferencia,
      ingresosHistoricosLista: ingresosHistoricosLista,
      hudTotalEgresosHistoricoGlobal: hudTotalEgresosHistoricoGlobal,
      hudTotalEgresosHistoricoEfectivo: hudTotalEgresosHistoricoEfectivo,
      hudTotalEgresosHistoricoTransferencia: hudTotalEgresosHistoricoTransferencia,
      hudGastosPersonalEmpresaTotal: hudGastosPersonalEmpresaTotal,
      hudEfectivoNetoHistorico: hudEfectivoNetoHistorico,
      hudTransferenciaNetaHistorica: hudTransferenciaNetaHistorica,
      hudOpex30DiasLocal: hudOpex30DiasLocal,
      hudProyeccion30DiasLocal: hudProyeccion30DiasLocal,
      hudModoInteligencia: preserveHudModo ?? FinanzasHudModo.acumuladoNeto,
      hudTurno: turnoHud,
      hudRetirosEfectivoHoy: hudRetirosEfectivoHoy,
      hudRetirosTransferenciaHoy: hudRetirosTransferenciaHoy,
      hudEfectivoNetoHoy: hudEfectivoNetoHoy,
      hudTransferenciaNetaHoy: hudTransferenciaNetaHoy,
      hudRetirosBolsaPersonalTotal: hudRetirosBolsaPersonalTotal,
      hudRetirosBolsaPersonalEfectivo: hudRetirosBolsaPersonalEfectivo,
      hudRetirosBolsaPersonalTransferencia: hudRetirosBolsaPersonalTransferencia,
      hudRetirosBolsaPersonalHoy: hudRetirosBolsaPersonalHoy,
      hudGastosBolsaPersonalTotal: hudGastosBolsaPersonalTotal,
      hudGastosBolsaPersonalEfectivo: hudGastosBolsaPersonalEfectivo,
      hudGastosBolsaPersonalTransferencia: hudGastosBolsaPersonalTransferencia,
      hudGastosBolsaPersonalHoy: hudGastosBolsaPersonalHoy,
      hudSaldoBolsaPersonalTotal: hudSaldoBolsaPersonalTotal,
      hudSaldoBolsaPersonalEfectivo: hudSaldoBolsaPersonalEfectivo,
      hudSaldoBolsaPersonalTransferencia: hudSaldoBolsaPersonalTransferencia,
    );
  }

  void setHudModoInteligencia(FinanzasHudModo modo) {
    final v = state.value;
    if (v == null) return;
    state = AsyncValue.data(v.copyWith(hudModoInteligencia: modo));
  }

  Future<void> aplicarFiltro({
    DateTime? mes,
    String? eventoId,
    DateTime? fechaExactaFiltro,
    bool clearMes = false,
    bool clearEvento = false,
    bool clearFechaExacta = false,
  }) async {
    final prev = state.value;

    state = const AsyncValue.loading();

    DateTime? newMes = clearMes ? null : (mes ?? prev?.mesFiltro);
    String? newEventoId = clearEvento ? null : (eventoId ?? prev?.eventoIdFiltro);

    DateTime? newFe;
    if (clearFechaExacta) {
      newFe = null;
    } else if (fechaExactaFiltro != null) {
      newFe = fechaExactaFiltro;
    } else {
      newFe = prev?.fechaExactaFiltro;
    }
    if (newFe != null) {
      if (newMes == null || !ArTime.mismoMes(newFe, newMes)) {
        newFe = null;
      }
    }

    state = await AsyncValue.guard(() => _fetchData(
          newMes,
          newEventoId,
          preserveFechaExacta: newFe,
          preserveHudModo: prev?.hudModoInteligencia,
          preserveFechaInteligenciaHud: prev?.fechaInteligenciaHud,
          preserveHudTurno: prev?.hudTurno,
        ));
  }

  Future<void> recargar() async {
    final curState = state.value;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchData(
          curState?.mesFiltro,
          curState?.eventoIdFiltro,
          preserveFechaExacta: curState?.fechaExactaFiltro,
          preserveHudModo: curState?.hudModoInteligencia,
          preserveFechaInteligenciaHud: curState?.fechaInteligenciaHud,
          preserveHudTurno: curState?.hudTurno,
        ));
  }

  /// `dia`: día calendario (AR); `null` = el HUD usa siempre el día actual (actualización en vivo).
  Future<void> setFechaInteligenciaHud(DateTime? dia) async {
    final v = state.value;
    if (v == null) return;
    DateTime? norm;
    if (dia != null) {
      norm = _soloDiaCalendarioAr(dia);
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchData(
          v.mesFiltro,
          v.eventoIdFiltro,
          preserveFechaExacta: v.fechaExactaFiltro,
          preserveHudModo: v.hudModoInteligencia,
          preserveFechaInteligenciaHud: norm,
          preserveHudTurno: v.hudTurno,
        ));
  }

  /// Cambia el turno usado para descontar retiros del HUD; recalcula los netos.
  Future<void> setHudTurno(TurnoCaja t) async {
    final v = state.value;
    if (v == null) return;
    state = await AsyncValue.guard(() => _fetchData(
          v.mesFiltro,
          v.eventoIdFiltro,
          preserveFechaExacta: v.fechaExactaFiltro,
          preserveHudModo: v.hudModoInteligencia,
          preserveFechaInteligenciaHud: v.fechaInteligenciaHud,
          preserveHudTurno: t,
        ));
  }

  Future<void> imprimirRecibo(BuildContext context, IngresoDetallado ingreso) async {
    final supabase = ref.read(supabaseProvider);
    try {
      if (ingreso.fuente == 'Particular') {
        final resT = await supabase.from('transacciones').select('*, eventos(*, clientes(*))').eq('id', ingreso.id).single();
        final evento = Evento.fromJson(resT['eventos']);
        
        final resAllT = await supabase.from('transacciones').select('*').eq('evento_id', evento.id);
        final todasTrans = (resAllT as List).map((x) => Transaccion.fromJson(x)).toList();
        
        final resServs = await supabase.from('eventos_servicios').select('*, servicios(*)').eq('evento_id', evento.id);
        final servs = (resServs as List).map((x) => EventosServicios.fromJson(x)).toList();
        
        final pagado = todasTrans.fold<double>(0, (s, t) => s + t.monto);
        final presupuesto = servs.fold<double>(0, (s, e) => s + e.precioFinalAcordado);
        final saldo = presupuesto - pagado;

        await PdfService.generarReciboCompacto(
          evento: evento,
          saldoActual: saldo,
          transacciones: todasTrans,
          servicios: servs,
          transaccionDestacadaId: ingreso.id,
        );
      } else if (ingreso.fuente == 'Masivo') {
        final db = await LocalDatabase.instance;
        final pagoRows = await db.query(
          'pagos_contrato_alumno',
          where: 'id = ?',
          whereArgs: [ingreso.id],
          limit: 1,
        );
        if (pagoRows.isEmpty) {
          throw Exception('No se encontró el pago en la base de datos local.');
        }
        final resP = Map<String, dynamic>.from(pagoRows.first);

        final String contratoId = resP['contrato_alumno_id'] as String;
        final contratoRows = await db.query(
          'contratos_alumnos',
          where: 'id = ?',
          whereArgs: [contratoId],
          limit: 1,
        );
        if (contratoRows.isEmpty) {
          throw Exception('No se encontró el contrato en la base de datos local.');
        }
        final contratoJson = Map<String, dynamic>.from(contratoRows.first);

        final String eventoId = contratoJson['evento_id'] as String;
        final eventoRows = await db.query(
          'eventos',
          where: 'id = ?',
          whereArgs: [eventoId],
          limit: 1,
        );
        if (eventoRows.isEmpty) {
          throw Exception('No se encontró el evento en la base de datos local.');
        }
        final eventoJson = Map<String, dynamic>.from(eventoRows.first);

        final String clienteId = eventoJson['cliente_id'] as String;
        final clienteRows = await db.query(
          'clientes',
          where: 'id = ?',
          whereArgs: [clienteId],
          limit: 1,
        );
        if (clienteRows.isEmpty) {
          throw Exception('No se encontró el cliente en la base de datos local.');
        }
        final clienteJson = Map<String, dynamic>.from(clienteRows.first);

        eventoJson['clientes'] = clienteJson;
        contratoJson['eventos'] = eventoJson;

        final contrato = ContratoAlumno.fromJson(contratoJson);
        final evento = Evento.fromJson(eventoJson);
        
        final String fechaBase = (resP['fecha_pago'] ?? resP['created_at']) as String;
        final DateTime dtBase = DateTime.parse(fechaBase);

        // Buscar otros "conceptos" pagados en la misma operación (mismo alumno, misma fecha +- 2 seg)
        final todosPagosRows = await db.query(
          'pagos_contrato_alumno',
          where: 'contrato_alumno_id = ?',
          whereArgs: [contrato.id],
        );
        
        final listOtrosRaw = <Map<String, dynamic>>[];
        for (final row in todosPagosRows) {
          final String? fp = row['fecha_pago'] as String?;
          final String? ca = row['created_at'] as String?;
          final String pFechaStr = fp ?? ca ?? '';
          if (pFechaStr.isEmpty) continue;
          try {
            final pDt = DateTime.parse(pFechaStr);
            final diff = pDt.difference(dtBase).inSeconds.abs();
            if (diff <= 2) {
              listOtrosRaw.add(row);
            }
          } catch (_) {
            // Ignorar errores de parseo
          }
        }

        // Detect dynamic "Mixto" details
        String? medioPago;
        double? montoEfectivoDetalle;
        double? montoTransferenciaDetalle;

        double totalEfectivo = 0.0;
        double totalTransferencia = 0.0;
        for (final p in listOtrosRaw) {
          final double m = (p['monto'] as num?)?.toDouble() ?? 0.0;
          final String mp = (p['medio_pago'] as String?)?.trim() ?? '';
          if (mp.toLowerCase() == 'efectivo') {
            totalEfectivo += m;
          } else if (mp.toLowerCase().contains('transfer') || mp.toLowerCase() == 'transferencia') {
            totalTransferencia += m;
          }
        }

        if (totalEfectivo > 0.01 && totalTransferencia > 0.01) {
          medioPago = 'Mixto';
          montoEfectivoDetalle = totalEfectivo;
          montoTransferenciaDetalle = totalTransferencia;
        } else if (totalEfectivo > 0.01) {
          medioPago = 'Efectivo';
        } else if (totalTransferencia > 0.01) {
          medioPago = 'Transferencia';
        }

        // Group by normalized concept and sum amounts to merge split payments
        final Map<String, double> agrupados = {};
        for (final p in listOtrosRaw) {
          final String raw = (p['concepto'] as String?) ?? 'Pago';
          final String upper = raw.toUpperCase().trim();
          String mapped = raw;
          
          // Prioritize mapping for interest/mora so it doesn't match legacy 'BASE' rules
          if (upper.contains('MORA') || upper.contains('INTERE')) {
            mapped = 'Interés mora (cuota base — este cobro)';
          } else if (upper.contains('(') && upper.contains(')')) {
            // Keep detailed rich concept names as-is
            mapped = raw;
          } else if (upper == 'BASE' || upper == 'CUOTA BASE' || upper.contains('CUOTA BASE')) {
            mapped = 'Cuota Base';
          } else if (upper == 'MESA' || upper == 'MESA EXTRA' || upper.contains('MESA')) {
            mapped = contrato.mesaExtraCuotas <= 1
                ? 'Mesa Extra - Entrega'
                : 'Mesa Extra (Abono)';
          } else if (upper == 'SILLA' || upper == 'SILLAS EXTRAS' || upper.contains('SILLA')) {
            mapped = 'Sillas Extras - Entrega';
          }
          
          agrupados[mapped] = (agrupados[mapped] ?? 0.0) +
              ((p['monto'] as num?)?.toDouble() ?? 0.0);
        }

        final listOtros = agrupados.entries.map<Map<String, dynamic>>((e) {
          return <String, dynamic>{
            'concepto': e.key,
            'monto': double.parse(e.value.toStringAsFixed(2)),
          };
        }).toList();

        final double valPago = listOtros.fold<double>(
          0.0,
          (sum, c) => sum + ((c['monto'] as num?)?.toDouble() ?? 0.0),
        );

        // Calcular de forma cronológica el progreso del contrato al momento de esta transacción:
        // Consideramos pagos no anulados con fecha <= dtBase + 2 segundos
        int cuotasBaseCronologicas = 0;
        int cuotasMesaCronologicas = 0;
        int cuotasSillaCronologicas = 0;
        double pagadoMesaCronologicas = 0;
        double pagadoSillaCronologicas = 0;
        double totalRecaudadoCronologico = 0;

        final double cuotaPuraBase = contrato.totalCuotas > 0
            ? (contrato.montoTotalPactado - contrato.mesaExtraPrecio - contrato.sillasExtraPrecioTotal) / contrato.totalCuotas
            : 0.0;
        final double cuotaPuraMesa = contrato.mesaExtraCuotas > 0
            ? contrato.mesaExtraPrecio / contrato.mesaExtraCuotas
            : 0.0;
        final double cuotaPuraSilla = contrato.sillasExtraCuotas > 0
            ? contrato.sillasExtraPrecioTotal / contrato.sillasExtraCuotas
            : 0.0;

        for (final p in todosPagosRows) {
          if (((p['anulado'] as num?)?.toInt() ?? 0) != 0) continue;

          final String? fp = p['fecha_pago'] as String?;
          final String? ca = p['created_at'] as String?;
          final String pFechaStr = fp ?? ca ?? '';
          if (pFechaStr.isEmpty) continue;

          try {
            final pDt = DateTime.parse(pFechaStr);
            if (pDt.isAfter(dtBase.add(const Duration(seconds: 2)))) {
              continue;
            }
          } catch (_) {
            continue;
          }

          final montoVal = (p['monto'] as num).toDouble();
          final conceptoRaw = p['concepto'] as String? ?? '';
          final lkRow = (p['line_kind'] as String?)?.trim();
          if (lkRow == 'Interés mora' ||
              lkRow == 'cargo_canal' ||
              esPagoInteresMoraPorConcepto(conceptoRaw)) {
            continue;
          }
          final concepto = conceptoRaw.toLowerCase();
          final bool esEntregaParcial = concepto.contains('entrega') || 
                                         concepto.contains('adelanto') || 
                                         concepto.contains('parcial');

          double mgOriginal = (p['monto_gross'] as num? ?? montoVal).toDouble();
          double mgSanado = mgOriginal;

          if (concepto.contains('base')) {
            int cant = 0;
            if (!esEntregaParcial) {
              if (concepto.contains('liquidación de')) {
                final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
                cant = match != null ? int.parse(match.group(1)!) : 1;
              } else if (concepto.contains('cuota')) {
                cant = 1;
              }
            }
            if (cant > 0 && mgOriginal == montoVal && montoVal < (cuotaPuraBase * cant - 0.1) && cuotaPuraBase > 0) {
              mgSanado = cuotaPuraBase * cant;
            }
            cuotasBaseCronologicas += cant;
          } else if (concepto.contains('mesa')) {
            int cant = 0;
            if (!esEntregaParcial) {
              if (concepto.contains('liquidación de')) {
                final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
                cant = match != null ? int.parse(match.group(1)!) : 1;
              } else if (concepto.contains('mesa extra')) {
                cant = 1;
              }
            }
            if (cant > 0 && mgOriginal == montoVal && montoVal < (cuotaPuraMesa * cant - 0.1) && cuotaPuraMesa > 0) {
              mgSanado = cuotaPuraMesa * cant;
            }
            cuotasMesaCronologicas += cant;
            pagadoMesaCronologicas += mgSanado;
          } else if (concepto.contains('silla')) {
            int cant = 0;
            if (!esEntregaParcial) {
              if (concepto.contains('liquidación de')) {
                final match = RegExp(r'liquidación de (\d+)').firstMatch(concepto);
                cant = match != null ? int.parse(match.group(1)!) : 1;
              } else if (concepto.contains('sillas extra')) {
                cant = 1;
              }
            }
            if (cant > 0 && mgOriginal == montoVal && montoVal < (cuotaPuraSilla * cant - 0.1) && cuotaPuraSilla > 0) {
              mgSanado = cuotaPuraSilla * cant;
            }
            cuotasSillaCronologicas += cant;
            pagadoSillaCronologicas += mgSanado;
          }

          totalRecaudadoCronologico += mgSanado;
        }

        final double saldoCronologico = (contrato.montoTotalPactado - totalRecaudadoCronologico).clamp(0, double.infinity);

        final contratoCronologico = contrato.copyWith(
          cuotasPagadas: cuotasBaseCronologicas.clamp(0, contrato.totalCuotas),
          mesaExtraCuotasPagadas: cuotasMesaCronologicas.clamp(0, contrato.mesaExtraCuotas),
          sillasExtraCuotasPagadas: cuotasSillaCronologicas.clamp(0, contrato.sillasExtraCuotas > 0 ? contrato.sillasExtraCuotas : 99),
          mesaExtraPagado: pagadoMesaCronologicas,
          sillasExtraPagado: pagadoSillaCronologicas,
          saldoDeudor: saldoCronologico,
        );

        await PdfService.generarReciboAlumno(
          alumno: contratoCronologico,
          evento: evento,
          montoPagado: valPago,
          saldoPendiente: contratoCronologico.saldoDeudor,
          conceptosPagados: listOtros.isNotEmpty ? listOtros : null,
          fechaManual: dtBase,
          medioPago: medioPago,
          montoEfectivoDetalle: montoEfectivoDetalle,
          montoTransferenciaDetalle: montoTransferenciaDetalle,
        );
      } else if (ingreso.fuente == 'Alquiler') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Para alquiler de ítems: abrí el préstamo con el ícono de caja y generá el PDF del acta o consultá los pagos allí.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar recibo: $e')));
      }
    }
  }
}

final finanzasProvider = AsyncNotifierProvider<FinanzasNotifier, FinanzasState>(
  () => FinanzasNotifier(),
);

/// Se incrementa tras mutar contratos (mora, pagos, etc.) para que COBRO y otras
/// vistas recarguen alumnos sin depender solo del ciclo de [finanzasProvider].
class ContratosMutationTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final contratosMutationTickProvider =
    NotifierProvider<ContratosMutationTick, int>(ContratosMutationTick.new);

class MesData {
  final DateTime mes;
  final double ingresos;
  final double egresos;
  double get neto => ingresos - egresos;
  const MesData({required this.mes, required this.ingresos, required this.egresos});
}

MesData calcularMesData(FinanzasState state, DateTime mesInicio) {
  final mes = DateTime(mesInicio.year, mesInicio.month, 1);
  final siguiente = DateTime(mes.year, mes.month + 1, 1);
  final ing = state.ingresos
      .where((x) => !x.fecha.isBefore(mes) && x.fecha.isBefore(siguiente))
      .fold(0.0, (s, e) => s + e.monto);
  final eg = state.egresos
      .where((x) => x.fecha != null && !x.fecha!.isBefore(mes) && x.fecha!.isBefore(siguiente))
      .fold(0.0, (s, e) => s + e.monto);
  return MesData(mes: mes, ingresos: ing, egresos: eg);
}

class HealthScoreData {
  final double score;
  final double liquidez;
  final double margen;
  final double momentum;
  final double alertas;
  final double runwayMeses;
  final double margenPct;
  final double deltaIngPct;
  final int alertasCount;

  const HealthScoreData({
    required this.score,
    required this.liquidez,
    required this.margen,
    required this.momentum,
    required this.alertas,
    required this.runwayMeses,
    required this.margenPct,
    required this.deltaIngPct,
    required this.alertasCount,
  });
}

HealthScoreData calcularHealthScore(FinanzasState state, int alertasFinancieras) {
  final capNeto = state.hudTotalIngresosHistoricoGlobal - state.hudTotalEgresosHistoricoGlobal;
  final opex = state.hudOpex30DiasLocal.abs();

  double runwayMeses;
  if (opex <= 0) {
    runwayMeses = capNeto > 0 ? 999 : 0;
  } else {
    runwayMeses = (capNeto / opex).clamp(0.0, 999.0);
  }
  final liquidez = (runwayMeses / 6.0).clamp(0.0, 1.0) * 30.0;

  final ingHist = state.hudTotalIngresosHistoricoGlobal;
  final margenPct = ingHist > 0 ? (capNeto / ingHist) : 0.0;
  final margen = (margenPct / 0.30).clamp(0.0, 1.0) * 30.0;

  final nowAr = ArTime.nowAr();
  final mesAct = DateTime(nowAr.year, nowAr.month, 1);
  final mesPrev = DateTime(mesAct.year, mesAct.month - 1, 1);
  final curr = calcularMesData(state, mesAct);
  final prev = calcularMesData(state, mesPrev);
  double deltaPct;
  if (prev.ingresos <= 0) {
    deltaPct = curr.ingresos > 0 ? 1.0 : 0.0;
  } else {
    deltaPct = (curr.ingresos - prev.ingresos) / prev.ingresos;
  }
  final momentumNorm = ((deltaPct + 0.20) / 0.40).clamp(0.0, 1.0);
  final momentum = momentumNorm * 25.0;

  final alertas = (15.0 - alertasFinancieras * 3.0).clamp(0.0, 15.0);

  final score = (liquidez + margen + momentum + alertas).clamp(0.0, 100.0);

  return HealthScoreData(
    score: score,
    liquidez: liquidez,
    margen: margen,
    momentum: momentum,
    alertas: alertas,
    runwayMeses: runwayMeses,
    margenPct: margenPct,
    deltaIngPct: deltaPct,
    alertasCount: alertasFinancieras,
  );
}

final healthScoreProvider = Provider<AsyncValue<HealthScoreData>>((ref) {
  final finanzasState = ref.watch(finanzasProvider);
  final statsState = ref.watch(dashboardStatsProvider);

  return finanzasState.when(
    data: (state) {
      final alertasCount = statsState.maybeWhen(
        data: (s) => s.alertas.where((a) => a.isFinanciera).length,
        orElse: () => 0,
      );
      return AsyncValue.data(calcularHealthScore(state, alertasCount));
    },
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});
