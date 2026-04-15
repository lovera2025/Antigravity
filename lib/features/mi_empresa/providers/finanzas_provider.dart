import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ingreso_detallado.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../repositories/finanzas_repository.dart';
import '../../../models/egreso.dart';
import '../../../models/evento.dart';
import '../../../models/transaccion.dart';
import '../../../models/contrato_alumno.dart';
import '../../common/services/pdf_service.dart';
import 'package:flutter/material.dart';
import '../../../main.dart';

class FinanzasState {
  final List<IngresoDetallado> ingresos;
  final List<Egreso> egresos;
  final double totalIngresos;
  final double totalEgresos;
  final double balanceGlobal;
  final DateTime? mesFiltro;
  final String? eventoIdFiltro;
  final Map<String, dynamic>? proyeccionFinanciera;

  FinanzasState({
    required this.ingresos,
    required this.egresos,
    required this.totalIngresos,
    required this.totalEgresos,
    required this.balanceGlobal,
    this.mesFiltro,
    this.eventoIdFiltro,
    this.proyeccionFinanciera,
  });

  FinanzasState copyWith({
    List<IngresoDetallado>? ingresos,
    List<Egreso>? egresos,
    double? totalIngresos,
    double? totalEgresos,
    double? balanceGlobal,
    DateTime? mesFiltro,
    String? eventoIdFiltro,
    Map<String, dynamic>? proyeccionFinanciera,
    bool clearMesFiltro = false,
    bool clearEventoIdFiltro = false,
  }) {
    return FinanzasState(
      ingresos: ingresos ?? this.ingresos,
      egresos: egresos ?? this.egresos,
      totalIngresos: totalIngresos ?? this.totalIngresos,
      totalEgresos: totalEgresos ?? this.totalEgresos,
      balanceGlobal: balanceGlobal ?? this.balanceGlobal,
      mesFiltro: clearMesFiltro ? null : (mesFiltro ?? this.mesFiltro),
      eventoIdFiltro: clearEventoIdFiltro ? null : (eventoIdFiltro ?? this.eventoIdFiltro),
      proyeccionFinanciera: proyeccionFinanciera ?? this.proyeccionFinanciera,
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
    return _fetchData(null, null);
  }

  void _setupRealtime() {
    final repo = ref.read(finanzasRepositoryProvider);
    _channel = repo.subscribeToChanges(() async {
      // Recarga silenciosa: mantenemos los filtros actuales
      final curMes = state.value?.mesFiltro;
      final curEventoId = state.value?.eventoIdFiltro;
      
      // Actualizamos solo si el estado actual tiene valor (evita carreras en carga inicial)
      if (state.hasValue) {
        state = await AsyncValue.guard(() => _fetchData(curMes, curEventoId));
      }
    });
  }

  Future<FinanzasState> _fetchData(DateTime? mes, String? eventoId) async {
    final finanzasRepo = ref.read(finanzasRepositoryProvider);
    final egresosRepo = ref.read(egresosRepositoryProvider);

    final results = await Future.wait([
      finanzasRepo.obtenerIngresosDetallados(mes: mes, eventoId: eventoId),
      egresosRepo.getEgresosConEvento(),
      finanzasRepo.obtenerProyeccionFinanciera(),
    ]);

    final ingresosList = results[0] as List<IngresoDetallado>;
    final egresosRaw = results[1] as List<dynamic>;
    final proyeccion = results[2] as Map<String, dynamic>?;

    List<Egreso> egresosList = egresosRaw.map((e) => Egreso.fromJson(e)).toList();

    // Filtros locales para egresos
    if (eventoId != null) {
      egresosList = egresosList.where((e) => e.eventoId == eventoId).toList();
    }
    if (mes != null) {
      egresosList = egresosList.where((e) {
        if (e.fecha == null) return false;
        return e.fecha!.year == mes.year && e.fecha!.month == mes.month;
      }).toList();
    }

    final totalIngresos = ingresosList.fold<double>(0, (sum, i) => sum + i.monto);
    final totalEgresos = egresosList.fold<double>(0, (sum, e) => sum + e.monto);
    final balanceGlobal = totalIngresos - totalEgresos;

    return FinanzasState(
      ingresos: ingresosList,
      egresos: egresosList,
      totalIngresos: totalIngresos,
      totalEgresos: totalEgresos,
      balanceGlobal: balanceGlobal,
      mesFiltro: mes,
      eventoIdFiltro: eventoId,
      proyeccionFinanciera: proyeccion,
    );
  }

  Future<void> aplicarFiltro({DateTime? mes, String? eventoId, bool clearMes = false, bool clearEvento = false}) async {
    state = const AsyncValue.loading();
    
    DateTime? newMes = clearMes ? null : (mes ?? state.value?.mesFiltro);
    String? newEventoId = clearEvento ? null : (eventoId ?? state.value?.eventoIdFiltro);

    state = await AsyncValue.guard(() => _fetchData(newMes, newEventoId));
  }

  Future<void> recargar() async {
    final curState = state.value;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchData(curState?.mesFiltro, curState?.eventoIdFiltro));
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
