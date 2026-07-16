import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../common/providers/admin_provider.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../models/guia_cambio_movimiento.dart';
import '../models/turno_caja.dart';
import '../repositories/cierre_caja_repository.dart';

class CierreCajaState {
  final DateTime dia;
  final TurnoCaja turno;

  /// Hora AR (0..23) en la que termina la mañana y arranca la tarde.
  final int corteHorarioAr;

  final List<IngresoDetallado> ingresosTurno;
  final List<Egreso> egresosTurno;
  final List<Egreso> retirosTurno;
  final List<Egreso> otrosEgresosTurno;

  final double efectivoBruto;
  final double transferenciaBruta;
  final double egresosEfectivo;
  final double egresosTransferencia;
  final double retirosEfectivo;
  final double retirosTransferencia;
  final double efectivoNeto;
  final double transferenciaNeta;
  final double totalNeto;

  /// Guía de cambio del día (no contable). Saldo derivado del historial SQLite.
  final double fondoCambioGuia;
  final List<GuiaCambioMovimiento> guiaCambioMovimientos;
  final int guiaCantReposiciones;
  final int guiaCantUsos;
  final double guiaTotalReposiciones;
  final double guiaTotalUsos;

  /// Anotación opcional para PDF del turno activo.
  final String anotacionTurno;

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
    this.egresosEfectivo = 0,
    this.egresosTransferencia = 0,
    this.retirosEfectivo = 0,
    this.retirosTransferencia = 0,
    this.efectivoNeto = 0,
    this.transferenciaNeta = 0,
    this.totalNeto = 0,
    this.fondoCambioGuia = 0,
    this.guiaCambioMovimientos = const [],
    this.guiaCantReposiciones = 0,
    this.guiaCantUsos = 0,
    this.guiaTotalReposiciones = 0,
    this.guiaTotalUsos = 0,
    this.anotacionTurno = '',
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
    double? egresosEfectivo,
    double? egresosTransferencia,
    double? retirosEfectivo,
    double? retirosTransferencia,
    double? efectivoNeto,
    double? transferenciaNeta,
    double? totalNeto,
    double? fondoCambioGuia,
    List<GuiaCambioMovimiento>? guiaCambioMovimientos,
    int? guiaCantReposiciones,
    int? guiaCantUsos,
    double? guiaTotalReposiciones,
    double? guiaTotalUsos,
    String? anotacionTurno,
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
      egresosEfectivo: egresosEfectivo ?? this.egresosEfectivo,
      egresosTransferencia: egresosTransferencia ?? this.egresosTransferencia,
      retirosEfectivo: retirosEfectivo ?? this.retirosEfectivo,
      retirosTransferencia: retirosTransferencia ?? this.retirosTransferencia,
      efectivoNeto: efectivoNeto ?? this.efectivoNeto,
      transferenciaNeta: transferenciaNeta ?? this.transferenciaNeta,
      totalNeto: totalNeto ?? this.totalNeto,
      fondoCambioGuia: fondoCambioGuia ?? this.fondoCambioGuia,
      guiaCambioMovimientos: guiaCambioMovimientos ?? this.guiaCambioMovimientos,
      guiaCantReposiciones: guiaCantReposiciones ?? this.guiaCantReposiciones,
      guiaCantUsos: guiaCantUsos ?? this.guiaCantUsos,
      guiaTotalReposiciones: guiaTotalReposiciones ?? this.guiaTotalReposiciones,
      guiaTotalUsos: guiaTotalUsos ?? this.guiaTotalUsos,
      anotacionTurno: anotacionTurno ?? this.anotacionTurno,
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
      final modoJefe = ref.read(adminAuthProvider).esModoJefe;
      late final TurnoCaja turnoVista;
      if (modoJefe) {
        final iso = p.getString(_kPrefsDiaKey);
        if (iso != null && iso.isNotEmpty) {
          final guardado = _fechaDesdeAString(iso);
          if (guardado != null) {
            diaVista = guardado.isBefore(hoyAr) ? hoyAr : guardado;
          }
        }
        turnoVista = _turnoDesdeSlug(p.getString(_kPrefsTurnoKey)?.trim());
      } else {
        turnoVista = turnoActualAr(corteHora: state.corteHorarioAr);
      }

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
    ref.listen(adminAuthProvider, (prev, next) {
      if (prev == null) return;
      if (prev.modoJefe && !next.modoJefe) {
        Future.microtask(aplicarRestriccionOperativa);
      } else if (prev.modoJefe != next.modoJefe) {
        Future.microtask(_refrescar);
      }
    });
    Future.microtask(_bootstrap);
    return CierreCajaState(
      dia: _diaArHoy(),
      turno: turnoActualAr(),
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
    var n = DateTime(nuevoDia.year, nuevoDia.month, nuevoDia.day);
    if (!ref.read(adminAuthProvider).esModoJefe) {
      n = _diaArHoy();
    }
    state = state.copyWith(dia: n);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setTurno(TurnoCaja t) async {
    if (!ref.read(adminAuthProvider).esModoJefe) {
      final actual = turnoActualAr(corteHora: state.corteHorarioAr);
      state = state.copyWith(dia: _diaArHoy(), turno: actual);
      await _guardarVistaSeleccion(state.dia, state.turno);
      await _refrescar();
      return;
    }
    state = state.copyWith(turno: t);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> avanzarANuevaJornadaVisual() async {
    if (!ref.read(adminAuthProvider).esModoJefe) {
      await aplicarRestriccionOperativa();
      return;
    }
    final siguiente = state.dia.add(const Duration(days: 1));
    final n = DateTime(siguiente.year, siguiente.month, siguiente.day);
    state = state.copyWith(dia: n, turno: TurnoCaja.dia);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  /// Al salir de modo jefe: fuerza hoy + turno actual AR y recalcula.
  Future<void> aplicarRestriccionOperativa() async {
    final turno = turnoActualAr(corteHora: state.corteHorarioAr);
    state = state.copyWith(dia: _diaArHoy(), turno: turno);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setCorteHorario(int horaAr) async {
    final h = horaAr.clamp(0, 23);
    state = state.copyWith(corteHorarioAr: h);
    await _refrescar();
  }

  Future<void> refrescarManual() => _refrescar();

  Future<void> registrarReposicionGuia(double monto, {String? nota}) async {
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarReposicion(dia: dia, monto: monto, nota: nota);
    await _refrescar();
  }

  Future<void> registrarUsoCambioGuia(double monto, {String? nota}) async {
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarUso(dia: dia, monto: monto, nota: nota);
    await _refrescar();
  }

  Future<void> registrarAjusteGuia(double saldoReal, {String? nota}) async {
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarAjuste(dia: dia, saldoReal: saldoReal, nota: nota);
    await _refrescar();
  }

  Future<void> setAnotacionTurno(String texto) async {
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.guardarAnotacion(dia: dia, turno: state.turno, texto: texto);
    state = state.copyWith(anotacionTurno: texto.trim());
  }

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
      final cierreRepo = ref.read(cierreCajaRepositoryProvider);
      final diaNorm = DateTime(state.dia.year, state.dia.month, state.dia.day);

      final results = await Future.wait([
        finanzasRepo.obtenerIngresosDetallados(),
        egresosRepo.getEgresosConEvento(),
        cierreRepo.obtenerGuiaCambioDia(diaNorm),
        cierreRepo.obtenerAnotacionTexto(diaNorm, state.turno),
      ]);

      final ingresosFull = results[0] as List<IngresoDetallado>;
      final egresosRaw = results[1] as List<dynamic>;
      final egresosFull = egresosRaw.map((e) => Egreso.fromJson(e)).toList();
      final guia = results[2] as GuiaCambioResumen;
      final anotacion = results[3] as String?;

      final rango = rangoHorarioAr(
        state.dia,
        state.turno,
        corteHora: state.corteHorarioAr,
      );

      double efectivoBruto = 0;
      double transferenciaBruta = 0;
      final ingresosTurno = <IngresoDetallado>[];
      final modoJefe = ref.read(adminAuthProvider).esModoJefe;
      for (final i in ingresosFull) {
        if (!ArTime.mismoDia(i.fecha, state.dia)) continue;
        if (!rango.contiene(i.fecha)) continue;
        final mp = i.medioPago?.toLowerCase().trim();
        // Modo operativo: no mostrar ingresos de eventos particulares (efectivo ni transferencia).
        if (!modoJefe && i.fuente == 'Particular') {
          continue;
        }
        ingresosTurno.add(i);
        if (mp == 'transferencia') {
          transferenciaBruta += i.monto;
        } else {
          efectivoBruto += i.monto;
        }
      }
      ingresosTurno.sort((a, b) => b.fecha.compareTo(a.fecha));

      final egresosTurno = <Egreso>[];
      final retirosTurno = <Egreso>[];
      double egresosEfectivo = 0;
      double egresosTransferencia = 0;
      double retirosEfectivo = 0;
      double retirosTransferencia = 0;
      for (final e in egresosFull) {
        if (e.fecha == null) continue;
        if (!ArTime.mismoDia(e.fecha!, state.dia)) continue;
        if (!rango.contiene(e.fecha!)) continue;
        egresosTurno.add(e);
        final mp = (e.medioPago ?? '').toLowerCase().trim();
        if (mp == 'transferencia') {
          egresosTransferencia += e.monto;
        } else {
          egresosEfectivo += e.monto;
        }
        if ((e.categoria ?? '').trim() == kCategoriaRetiroCaja) {
          retirosTurno.add(e);
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

      final efectivoNeto = efectivoBruto - egresosEfectivo;
      final transferenciaNeta = transferenciaBruta - egresosTransferencia;
      final totalNeto = efectivoNeto + transferenciaNeta;

      state = state.copyWith(
        ingresosTurno: ingresosTurno,
        egresosTurno: egresosTurno,
        retirosTurno: retirosTurno,
        otrosEgresosTurno: otrosEgresosTurno,
        efectivoBruto: efectivoBruto,
        transferenciaBruta: transferenciaBruta,
        egresosEfectivo: egresosEfectivo,
        egresosTransferencia: egresosTransferencia,
        retirosEfectivo: retirosEfectivo,
        retirosTransferencia: retirosTransferencia,
        efectivoNeto: efectivoNeto,
        transferenciaNeta: transferenciaNeta,
        totalNeto: totalNeto,
        fondoCambioGuia: guia.saldoActual,
        guiaCambioMovimientos: guia.movimientos,
        guiaCantReposiciones: guia.cantReposiciones,
        guiaCantUsos: guia.cantUsos,
        guiaTotalReposiciones: guia.totalReposiciones,
        guiaTotalUsos: guia.totalUsos,
        anotacionTurno: anotacion ?? '',
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
