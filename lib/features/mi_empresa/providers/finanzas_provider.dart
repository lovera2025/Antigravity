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

/// Modo del panel “Inteligencia financiera” (HUD): día, solo ingresos históricos o capital neto local.
enum FinanzasHudModo {
  /// Ingresos cobrados hoy (calendario AR); métricas secundarias del mismo día.
  hoy,

  /// Suma histórica de todos los ingresos locales (sin restar egresos).
  acumuladoIngresos,

  /// Ingresos históricos − egresos históricos (misma base SQLite que el listado), con OPEX/proyección 30 días locales.
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
  /// Día elegido para el HUD «Inteligencia financiera» en modo [FinanzasHudModo.hoy] (`null` = siempre el día actual según [ArTime.nowAr]).
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
  final double hudTotalEgresosHistoricoGlobal;
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
    this.hudTotalEgresosHistoricoGlobal = 0,
    this.hudOpex30DiasLocal = 0,
    this.hudProyeccion30DiasLocal = 0,
    this.hudModoInteligencia = FinanzasHudModo.hoy,
    this.hudTurno = TurnoCaja.dia,
    this.hudRetirosEfectivoHoy = 0,
    this.hudRetirosTransferenciaHoy = 0,
    this.hudEfectivoNetoHoy = 0,
    this.hudTransferenciaNetaHoy = 0,
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
    double? hudTotalEgresosHistoricoGlobal,
    double? hudOpex30DiasLocal,
    double? hudProyeccion30DiasLocal,
    FinanzasHudModo? hudModoInteligencia,
    TurnoCaja? hudTurno,
    double? hudRetirosEfectivoHoy,
    double? hudRetirosTransferenciaHoy,
    double? hudEfectivoNetoHoy,
    double? hudTransferenciaNetaHoy,
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
      hudTotalEgresosHistoricoGlobal: hudTotalEgresosHistoricoGlobal ?? this.hudTotalEgresosHistoricoGlobal,
      hudOpex30DiasLocal: hudOpex30DiasLocal ?? this.hudOpex30DiasLocal,
      hudProyeccion30DiasLocal: hudProyeccion30DiasLocal ?? this.hudProyeccion30DiasLocal,
      hudModoInteligencia: hudModoInteligencia ?? this.hudModoInteligencia,
      hudTurno: hudTurno ?? this.hudTurno,
      hudRetirosEfectivoHoy: hudRetirosEfectivoHoy ?? this.hudRetirosEfectivoHoy,
      hudRetirosTransferenciaHoy: hudRetirosTransferenciaHoy ?? this.hudRetirosTransferenciaHoy,
      hudEfectivoNetoHoy: hudEfectivoNetoHoy ?? this.hudEfectivoNetoHoy,
      hudTransferenciaNetaHoy: hudTransferenciaNetaHoy ?? this.hudTransferenciaNetaHoy,
    );
  }
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
    final balanceGlobal = totalIngresos - totalEgresos;

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
      final mp = i.medioPago?.toLowerCase().trim();
      // Solo ingresos del día: transferencia aparte; el resto (incl. sin medio) suma a efectivo en el HUD.
      if (mp == 'transferencia') {
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
        hudEgresosHoy += e.monto;
      }
      if (e.fecha == null) continue;
      if ((e.categoria ?? '').trim() != kCategoriaRetiroCaja) continue;
      if (!ArTime.mismoDia(e.fecha!, diaHudRef)) continue;
      if (!rangoHud.contiene(e.fecha!)) continue;
      final mp = (e.medioPago ?? '').toLowerCase().trim();
      if (mp == 'transferencia') {
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

    final hudTotalIngresosHistoricoGlobal = ingresosFull.fold<double>(0, (s, i) => s + i.monto);
    final hudTotalEgresosHistoricoGlobal = egresosFull.fold<double>(0, (s, e) => s + e.monto);

    final limite30 = hoyDia.subtract(const Duration(days: 30));
    final hudOpex30DiasLocal = _sumEgresosEnRangoCalendarioAr(egresosFull, limite30, hoyDia);
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
      hudTotalEgresosHistoricoGlobal: hudTotalEgresosHistoricoGlobal,
      hudOpex30DiasLocal: hudOpex30DiasLocal,
      hudProyeccion30DiasLocal: hudProyeccion30DiasLocal,
      hudModoInteligencia: preserveHudModo ?? FinanzasHudModo.hoy,
      hudTurno: turnoHud,
      hudRetirosEfectivoHoy: hudRetirosEfectivoHoy,
      hudRetirosTransferenciaHoy: hudRetirosTransferenciaHoy,
      hudEfectivoNetoHoy: hudEfectivoNetoHoy,
      hudTransferenciaNetaHoy: hudTransferenciaNetaHoy,
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
        final resP = await supabase.from('pagos_contrato_alumno').select('*, contratos_alumnos(*, eventos(*, clientes(*)))').eq('id', ingreso.id).single();
        final contratoJson = resP['contratos_alumnos'];
        final contrato = ContratoAlumno.fromJson(contratoJson);
        final evento = Evento.fromJson(contratoJson['eventos']);
        
        final String fechaBase = resP['fecha_pago'] ?? resP['created_at'];
        final DateTime dtBase = DateTime.parse(fechaBase);

        // Buscar otros "conceptos" pagados en la misma operación (mismo alumno, misma fecha +- 2 seg)
        final otrosPagosRes = await supabase
            .from('pagos_contrato_alumno')
            .select('concepto, monto')
            .eq('contrato_alumno_id', contrato.id)
            .gte('fecha_pago', dtBase.subtract(const Duration(seconds: 2)).toIso8601String())
            .lte('fecha_pago', dtBase.add(const Duration(seconds: 2)).toIso8601String());
        
        final listOtros = (otrosPagosRes as List).map((p) {
          String raw = p['concepto']?.toString() ?? 'Pago';
          if (raw.toUpperCase().contains('MESA')) {
             raw = contrato.mesaExtraCuotas <= 1 ? 'Mesa Extra - Entrega' : 'Mesa Extra (Abono)';
          } else if (raw.toUpperCase().contains('SILLA')) {
             raw = 'Sillas Extras - Entrega';
          } else if (raw.toUpperCase().contains('BASE')) {
             raw = 'Cuota Base';
          }
          return {
            'concepto': raw,
            'monto': (p['monto'] as num?)?.toDouble() ?? 0.0,
          };
        }).toList();

        await PdfService.generarReciboAlumno(
          alumno: contrato,
          evento: evento,
          montoPagado: ingreso.monto,
          saldoPendiente: contrato.saldoDeudor,
          conceptosPagados: listOtros.isNotEmpty ? listOtros : null,
          fechaManual: dtBase, // Marcamos como reimpresión con la fecha original
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
