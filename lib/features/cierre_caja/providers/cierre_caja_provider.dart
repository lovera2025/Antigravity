import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../models/turno_caja.dart';

class CierreCajaState {
  final DateTime dia;
  final TurnoCaja turno;

  /// Hora AR (0..23) en la que termina la mañana y arranca la tarde.
  final int corteHorarioAr;

  /// Día/turno actuales.
  final List<IngresoDetallado> ingresosTurno;
  final List<Egreso> egresosTurno;

  /// Subset de [egresosTurno] cuya categoría es [kCategoriaRetiroCaja].
  final List<Egreso> retirosTurno;

  /// Egresos del mismo turno que **no** son retiros de caja (p. ej. Personal, Proveedores).
  /// Mismas filas que en Finanzas; solo se listan acá para historial del turno sin duplicar montos.
  final List<Egreso> otrosEgresosTurno;

  final double efectivoBruto;
  final double transferenciaBruta;
  final double retirosEfectivo;
  final double retirosTransferencia;
  final double efectivoNeto;
  final double transferenciaNeta;
  final double totalNeto;

  final bool cargando;
  final Object? error;

  const CierreCajaState({
    required this.dia,
    required this.turno,
    required this.corteHorarioAr,
    this.ingresosTurno = const [],
    this.egresosTurno = const [],
    this.retirosTurno = const [],
    this.otrosEgresosTurno = const [],
    this.efectivoBruto = 0,
    this.transferenciaBruta = 0,
    this.retirosEfectivo = 0,
    this.retirosTransferencia = 0,
    this.efectivoNeto = 0,
    this.transferenciaNeta = 0,
    this.totalNeto = 0,
    this.cargando = false,
    this.error,
  });

  CierreCajaState copyWith({
    DateTime? dia,
    TurnoCaja? turno,
    int? corteHorarioAr,
    List<IngresoDetallado>? ingresosTurno,
    List<Egreso>? egresosTurno,
    List<Egreso>? retirosTurno,
    List<Egreso>? otrosEgresosTurno,
    double? efectivoBruto,
    double? transferenciaBruta,
    double? retirosEfectivo,
    double? retirosTransferencia,
    double? efectivoNeto,
    double? transferenciaNeta,
    double? totalNeto,
    bool? cargando,
    Object? error,
    bool clearError = false,
  }) {
    return CierreCajaState(
      dia: dia ?? this.dia,
      turno: turno ?? this.turno,
      corteHorarioAr: corteHorarioAr ?? this.corteHorarioAr,
      ingresosTurno: ingresosTurno ?? this.ingresosTurno,
      egresosTurno: egresosTurno ?? this.egresosTurno,
      retirosTurno: retirosTurno ?? this.retirosTurno,
      otrosEgresosTurno: otrosEgresosTurno ?? this.otrosEgresosTurno,
      efectivoBruto: efectivoBruto ?? this.efectivoBruto,
      transferenciaBruta: transferenciaBruta ?? this.transferenciaBruta,
      retirosEfectivo: retirosEfectivo ?? this.retirosEfectivo,
      retirosTransferencia: retirosTransferencia ?? this.retirosTransferencia,
      efectivoNeto: efectivoNeto ?? this.efectivoNeto,
      transferenciaNeta: transferenciaNeta ?? this.transferenciaNeta,
      totalNeto: totalNeto ?? this.totalNeto,
      cargando: cargando ?? this.cargando,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CierreCajaNotifier extends Notifier<CierreCajaState> {
  RealtimeChannel? _channel;
  bool _registrandoRetiro = false;

  static const _kPrefsDiaKey = 'cierre_caja_vista_dia_ar';
  static const _kPrefsTurnoKey = 'cierre_caja_vista_turno_slug';

  static DateTime _diaArHoy() {
    final ar = ArTime.nowAr();
    return DateTime(ar.year, ar.month, ar.day);
  }

  /// `yyyy-mm-dd` en calendario (sin TZ ambiguos).
  static String _fechaAString(DateTime dia) =>
      '${dia.year.toString().padLeft(4, '0')}-'
      '${dia.month.toString().padLeft(2, '0')}-'
      '${dia.day.toString().padLeft(2, '0')}';

  static DateTime? _fechaDesdeAString(String iso) {
    final parts = iso.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  static TurnoCaja _turnoDesdeSlug(String? slug) {
    switch (slug) {
      case 'manana':
        return TurnoCaja.manana;
      case 'tarde':
        return TurnoCaja.tarde;
      case 'dia':
        return TurnoCaja.dia;
      default:
        return TurnoCaja.dia;
    }
  }

  Future<void> _guardarVistaSeleccion(DateTime dia, TurnoCaja turno) async {
    try {
      final p = await SharedPreferences.getInstance();
      final normalized = DateTime(dia.year, dia.month, dia.day);
      await p.setString(_kPrefsDiaKey, _fechaAString(normalized));
      await p.setString(_kPrefsTurnoKey, turno.slug);
    } catch (_) {}
  }

  Future<void> _bootstrap() async {
    try {
      final p = await SharedPreferences.getInstance();
      final hoyAr = _diaArHoy();
      DateTime diaVista = hoyAr;
      final iso = p.getString(_kPrefsDiaKey);
      if (iso != null && iso.isNotEmpty) {
        final guardado = _fechaDesdeAString(iso);
        if (guardado != null) {
          diaVista = guardado.isBefore(hoyAr) ? hoyAr : guardado;
        }
      }
      final turnoVista =
          _turnoDesdeSlug(p.getString(_kPrefsTurnoKey)?.trim());

      state = state.copyWith(dia: diaVista, turno: turnoVista);
      await _guardarVistaSeleccion(state.dia, state.turno);
    } catch (_) {}
    _setupRealtime();
    await _refrescar();
  }

  @override
  CierreCajaState build() {
    ref.onDispose(() {
      _channel?.unsubscribe();
    });
    Future.microtask(_bootstrap);
    return CierreCajaState(
      dia: _diaArHoy(),
      turno: TurnoCaja.dia,
      corteHorarioAr: 14,
      cargando: true,
    );
  }

  void _setupRealtime() {
    _channel?.unsubscribe();
    final repo = ref.read(finanzasRepositoryProvider);
    _channel = repo.subscribeToChanges(_refrescar);
  }

  Future<void> setDia(DateTime nuevoDia) async {
    final n = DateTime(nuevoDia.year, nuevoDia.month, nuevoDia.day);
    state = state.copyWith(dia: n);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setTurno(TurnoCaja t) async {
    state = state.copyWith(turno: t);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  /// Avanza la vista al siguiente día calendario AR sin tocar historial.
  /// Se usa para "nueva jornada" (pantalla limpia visualmente).
  Future<void> avanzarANuevaJornadaVisual() async {
    final siguiente = state.dia.add(const Duration(days: 1));
    final n = DateTime(siguiente.year, siguiente.month, siguiente.day);
    state = state.copyWith(dia: n, turno: TurnoCaja.dia);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setCorteHorario(int horaAr) async {
    final h = horaAr.clamp(0, 23);
    state = state.copyWith(corteHorarioAr: h);
    await _refrescar();
  }

  Future<void> refrescarManual() => _refrescar();

  /// `monto` validado contra el bucket; lanza si excede el disponible.
  Future<void> registrarRetiro({
    required double monto,
    required String medioPago,
    String? notas,
  }) async {
    if (_registrandoRetiro) {
      throw StateError('Ya hay un retiro en proceso; esperá un instante.');
    }
    _registrandoRetiro = true;
    if (monto <= 0) {
      _registrandoRetiro = false;
      throw ArgumentError('El monto del retiro debe ser mayor a cero.');
    }
    final medio = medioPago.toLowerCase().trim();
    if (medio != 'efectivo' && medio != 'transferencia') {
      _registrandoRetiro = false;
      throw ArgumentError('medio_pago debe ser efectivo o transferencia.');
    }

    final disponible = medio == 'efectivo'
        ? state.efectivoNeto
        : state.transferenciaNeta;

    if (monto > disponible + 0.001) {
      _registrandoRetiro = false;
      throw StateError(
        'No hay saldo suficiente en $medio: disponible \$${disponible.toStringAsFixed(2)}.',
      );
    }

    final brutoEfectivo = state.efectivoBruto;
    final brutoTransf = state.transferenciaBruta;
    if (medio == 'efectivo' && brutoEfectivo <= 0.001) {
      _registrandoRetiro = false;
      throw StateError(
        'En este turno no hubo ingresos en efectivo; no se puede registrar un retiro en efectivo.',
      );
    }
    if (medio == 'transferencia' && brutoTransf <= 0.001) {
      _registrandoRetiro = false;
      throw StateError(
        'En este turno no hubo ingresos por transferencia; no se puede registrar un retiro por transferencia.',
      );
    }

    try {
      final egRepo = ref.read(egresosRepositoryProvider);
      final concepto = (notas ?? '').trim().isNotEmpty
          ? 'Retiro de caja — ${notas!.trim()}'
          : 'Retiro de caja';

      await egRepo.registrarEgresoSinEvento(
        monto: monto,
        proveedor: concepto,
        categoria: kCategoriaRetiroCaja,
        medioPago: medio,
      );

      await _refrescar();
    } finally {
      _registrandoRetiro = false;
    }
  }

  Future<void> _refrescar() async {
    state = state.copyWith(cargando: true, clearError: true);
    try {
      final finanzasRepo = ref.read(finanzasRepositoryProvider);
      final egresosRepo = ref.read(egresosRepositoryProvider);

      final results = await Future.wait([
        finanzasRepo.obtenerIngresosDetallados(),
        egresosRepo.getEgresosConEvento(),
      ]);

      final ingresosFull = results[0] as List<IngresoDetallado>;
      final egresosRaw = results[1] as List<dynamic>;
      final egresosFull = egresosRaw.map((e) => Egreso.fromJson(e)).toList();

      final rango = rangoHorarioAr(
        state.dia,
        state.turno,
        corteHora: state.corteHorarioAr,
      );

      double efectivoBruto = 0;
      double transferenciaBruta = 0;
      final ingresosTurno = <IngresoDetallado>[];
      for (final i in ingresosFull) {
        if (!ArTime.mismoDia(i.fecha, state.dia)) continue;
        if (!rango.contiene(i.fecha)) continue;
        ingresosTurno.add(i);
        final mp = i.medioPago?.toLowerCase().trim();
        if (mp == 'transferencia') {
          transferenciaBruta += i.monto;
        } else {
          efectivoBruto += i.monto;
        }
      }
      ingresosTurno.sort((a, b) => b.fecha.compareTo(a.fecha));

      final egresosTurno = <Egreso>[];
      final retirosTurno = <Egreso>[];
      double retirosEfectivo = 0;
      double retirosTransferencia = 0;
      for (final e in egresosFull) {
        if (e.fecha == null) continue;
        if (!ArTime.mismoDia(e.fecha!, state.dia)) continue;
        if (!rango.contiene(e.fecha!)) continue;
        egresosTurno.add(e);
        if ((e.categoria ?? '').trim() == kCategoriaRetiroCaja) {
          retirosTurno.add(e);
          final mp = (e.medioPago ?? '').toLowerCase().trim();
          if (mp == 'transferencia') {
            retirosTransferencia += e.monto;
          } else {
            retirosEfectivo += e.monto;
          }
        }
      }
      egresosTurno.sort((a, b) {
        final fa = a.fecha;
        final fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });
      retirosTurno.sort((a, b) {
        final fa = a.fecha;
        final fb = b.fecha;
        if (fa == null && fb == null) return 0;
        if (fa == null) return 1;
        if (fb == null) return -1;
        return fb.compareTo(fa);
      });

      final otrosEgresosTurno = egresosTurno
          .where((e) => (e.categoria ?? '').trim() != kCategoriaRetiroCaja)
          .toList();

      final efectivoNeto = efectivoBruto - retirosEfectivo;
      final transferenciaNeta = transferenciaBruta - retirosTransferencia;
      final totalNeto = efectivoNeto + transferenciaNeta;

      state = state.copyWith(
        ingresosTurno: ingresosTurno,
        egresosTurno: egresosTurno,
        retirosTurno: retirosTurno,
        otrosEgresosTurno: otrosEgresosTurno,
        efectivoBruto: efectivoBruto,
        transferenciaBruta: transferenciaBruta,
        retirosEfectivo: retirosEfectivo,
        retirosTransferencia: retirosTransferencia,
        efectivoNeto: efectivoNeto,
        transferenciaNeta: transferenciaNeta,
        totalNeto: totalNeto,
        cargando: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(cargando: false, error: e);
    }
  }
}

final cierreCajaProvider =
    NotifierProvider<CierreCajaNotifier, CierreCajaState>(
  CierreCajaNotifier.new,
);
