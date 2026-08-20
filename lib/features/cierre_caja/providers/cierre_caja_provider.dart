import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/ar_time.dart';
import '../../../models/egreso.dart';
import '../../common/providers/admin_provider.dart';
import '../../caja_sesiones/models/modo_jefe_caja.dart';
import '../../caja_sesiones/models/sesion_caja.dart';
import '../../caja_sesiones/providers/app_role_provider.dart';
import '../../caja_sesiones/repositories/sesiones_caja_repository.dart';
import '../../egresos/repositories/egresos_repository.dart';
import '../../mi_empresa/models/ingreso_detallado.dart';
import '../../mi_empresa/repositories/finanzas_repository.dart';
import '../models/guia_cambio_movimiento.dart';
import '../models/turno_caja.dart';
import '../repositories/cierre_caja_repository.dart';
import '../services/datos_cierre_sesion.dart';

class CierreCajaState {
  final DateTime dia;
  final TurnoCaja turno;
  final List<SesionCaja> sesionesDia;
  final String? sesionSeleccionadaId;
  final bool consolidado;

  /// Vista contraste: movimientos del día **sin** `sesion_caja_id` (build viejo).
  final bool sinSesiones;

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

  final bool cargando;
  final Object? error;

  const CierreCajaState({
    required this.dia,
    required this.turno,
    this.sesionesDia = const [],
    this.sesionSeleccionadaId,
    this.consolidado = false,
    this.sinSesiones = false,
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
    this.cargando = false,
    this.error,
  });

  CierreCajaState copyWith({
    DateTime? dia,
    TurnoCaja? turno,
    List<SesionCaja>? sesionesDia,
    String? sesionSeleccionadaId,
    bool? consolidado,
    bool? sinSesiones,
    bool clearSesionSeleccionada = false,
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
    bool? cargando,
    Object? error,
    bool clearError = false,
  }) {
    return CierreCajaState(
      dia: dia ?? this.dia,
      turno: turno ?? this.turno,
      sesionesDia: sesionesDia ?? this.sesionesDia,
      sesionSeleccionadaId: clearSesionSeleccionada
          ? null
          : (sesionSeleccionadaId ?? this.sesionSeleccionadaId),
      consolidado: consolidado ?? this.consolidado,
      sinSesiones: sinSesiones ?? this.sinSesiones,
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
      guiaCambioMovimientos:
          guiaCambioMovimientos ?? this.guiaCambioMovimientos,
      guiaCantReposiciones: guiaCantReposiciones ?? this.guiaCantReposiciones,
      guiaCantUsos: guiaCantUsos ?? this.guiaCantUsos,
      guiaTotalReposiciones:
          guiaTotalReposiciones ?? this.guiaTotalReposiciones,
      guiaTotalUsos: guiaTotalUsos ?? this.guiaTotalUsos,
      cargando: cargando ?? this.cargando,
      error: clearError ? null : (error ?? this.error),
    );
  }

  SesionCaja? get sesionSeleccionada {
    final id = sesionSeleccionadaId;
    if (id == null) return null;
    for (final s in sesionesDia) {
      if (s.id == id) return s;
    }
    return null;
  }

  String get alcanceLabel {
    if (sinSesiones) {
      return 'Sin sesiones · ${turno.labelCorto}';
    }
    if (consolidado) return 'Día completo · sesiones';
    final s = sesionSeleccionada;
    if (s == null) return 'Sin sesión';
    if (esOperadorModoJefeId(s.operadorId)) return kOperadorModoJefeNombre;
    return [
      s.operadorNombre ?? 'Operario',
      if ((s.etiqueta ?? '').isNotEmpty) s.etiqueta!,
    ].join(' · ');
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
    final appRole = ref.read(appRoleProvider);
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
      turno: appRole.sesionActiva == null
          ? TurnoCaja.dia
          : turnoDeSesion(appRole.sesionActiva!),
      sesionSeleccionadaId: appRole.sesionActiva?.id,
      consolidado: appRole.esJefe,
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
    // En vista "sin sesiones" el turno filtra por hora; en sesiones se ignora
    // salvo que estemos en esa vista.
    state = state.copyWith(turno: t);
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setSesion(String sesionId) async {
    if (!ref.read(appRoleProvider).esJefe) return;
    final sesion = state.sesionesDia.where((s) => s.id == sesionId).firstOrNull;
    if (sesion == null) return;
    state = state.copyWith(
      sesionSeleccionadaId: sesionId,
      consolidado: false,
      sinSesiones: false,
      turno: turnoDeSesion(sesion),
    );
    await _refrescar();
  }

  Future<void> setConsolidado() async {
    if (!ref.read(appRoleProvider).esJefe) return;
    state = state.copyWith(
      consolidado: true,
      sinSesiones: false,
      clearSesionSeleccionada: true,
      turno: TurnoCaja.dia,
    );
    await _refrescar();
  }

  /// Contraste build viejo: cobros/egresos del día sin `sesion_caja_id`.
  Future<void> setSinSesiones({bool activo = true}) async {
    if (!ref.read(appRoleProvider).esJefe) return;
    if (activo) {
      state = state.copyWith(
        sinSesiones: true,
        consolidado: false,
        clearSesionSeleccionada: true,
        turno: TurnoCaja.dia,
      );
    } else {
      state = state.copyWith(
        sinSesiones: false,
        consolidado: true,
        clearSesionSeleccionada: true,
        turno: TurnoCaja.dia,
      );
    }
    await _refrescar();
  }

  Future<void> avanzarANuevaJornadaVisual() async {
    if (!ref.read(adminAuthProvider).esModoJefe) {
      await aplicarRestriccionOperativa();
      return;
    }
    final siguiente = state.dia.add(const Duration(days: 1));
    final n = DateTime(siguiente.year, siguiente.month, siguiente.day);
    state = state.copyWith(
      dia: n,
      turno: TurnoCaja.dia,
      sinSesiones: false,
      consolidado: true,
      clearSesionSeleccionada: true,
    );
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  /// Al salir de modo jefe: fuerza hoy + turno actual AR y recalcula.
  Future<void> aplicarRestriccionOperativa() async {
    final sesion = ref.read(appRoleProvider).sesionActiva;
    state = state.copyWith(
      dia: _diaArHoy(),
      turno: sesion == null ? turnoActualAr() : turnoDeSesion(sesion),
      sesionSeleccionadaId: sesion?.id,
      consolidado: false,
      sinSesiones: false,
    );
    await _guardarVistaSeleccion(state.dia, state.turno);
    await _refrescar();
  }

  Future<void> setCorteHorario(int horaAr) async {
    final h = horaAr.clamp(0, 23);
    state = state.copyWith(corteHorarioAr: h);
    await _refrescar();
  }

  Future<void> refrescarManual() => _refrescar();

  String _sesionEditableId() {
    final id = state.sesionSeleccionadaId;
    if (state.sinSesiones || state.consolidado || id == null) {
      throw StateError('Seleccioná una sesión para registrar movimientos.');
    }
    return id;
  }

  Future<void> _autoSyncCaja(DateTime checkpoint) async {
    if (!ref.read(appRoleProvider).esCaja) return;
    await ref
        .read(sesionesCajaRepositoryProvider)
        .flushBestEffort(createdSince: checkpoint);
  }

  Future<void> registrarReposicionGuia(double monto, {String? nota}) async {
    final checkpoint = DateTime.now().toUtc();
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarReposicion(
      dia: dia,
      sesionCajaId: _sesionEditableId(),
      monto: monto,
      nota: nota,
    );
    await _autoSyncCaja(checkpoint);
    await _refrescar();
  }

  Future<void> registrarUsoCambioGuia(double monto, {String? nota}) async {
    final checkpoint = DateTime.now().toUtc();
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarUso(
      dia: dia,
      sesionCajaId: _sesionEditableId(),
      monto: monto,
      nota: nota,
    );
    await _autoSyncCaja(checkpoint);
    await _refrescar();
  }

  Future<void> registrarAjusteGuia(double saldoReal, {String? nota}) async {
    final checkpoint = DateTime.now().toUtc();
    final repo = ref.read(cierreCajaRepositoryProvider);
    final dia = DateTime(state.dia.year, state.dia.month, state.dia.day);
    await repo.registrarAjuste(
      dia: dia,
      sesionCajaId: _sesionEditableId(),
      saldoReal: saldoReal,
      nota: nota,
    );
    await _autoSyncCaja(checkpoint);
    await _refrescar();
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
      final checkpoint = DateTime.now().toUtc();
      final egRepo = ref.read(egresosRepositoryProvider);
      final concepto = (notas ?? '').trim().isNotEmpty
          ? 'Retiro de caja — ${notas!.trim()}'
          : 'Retiro de caja';

      await egRepo.registrarEgresoSinEvento(
        monto: monto,
        proveedor: concepto,
        categoria: kCategoriaRetiroCaja,
        medioPago: medio,
        sesionCajaId: _sesionEditableId(),
      );

      await _autoSyncCaja(checkpoint);
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
      final sesionesRepo = ref.read(sesionesCajaRepositoryProvider);
      final appRole = ref.read(appRoleProvider);
      final diaNorm = DateTime(state.dia.year, state.dia.month, state.dia.day);

      var sesiones = await sesionesRepo.sesionesDelDia(diaNorm);
      String? seleccionadaId = state.sesionSeleccionadaId;
      var consolidado = state.consolidado;
      var sinSesiones = state.sinSesiones;
      if (appRole.esCaja) {
        final activa = appRole.sesionActiva;
        sesiones = activa == null ? const [] : [activa];
        seleccionadaId = activa?.id;
        consolidado = false;
        sinSesiones = false;
      } else if (sinSesiones) {
        seleccionadaId = null;
        consolidado = false;
      } else if (!consolidado && !sesiones.any((s) => s.id == seleccionadaId)) {
        seleccionadaId = sesiones.firstOrNull?.id;
        consolidado = seleccionadaId == null;
      }

      final ids = sinSesiones
          ? <String>{}
          : consolidado
          ? sesiones.map((s) => s.id).toSet()
          : <String>{?seleccionadaId};
      SesionCaja? seleccionada;
      if (seleccionadaId != null) {
        seleccionada = sesiones
            .where((s) => s.id == seleccionadaId)
            .firstOrNull;
      }
      final turno = sinSesiones
          ? state.turno
          : consolidado
          ? TurnoCaja.dia
          : (seleccionada == null ? state.turno : turnoDeSesion(seleccionada));

      final rangoSinSesion = sinSesiones
          ? rangoHorarioAr(diaNorm, turno, corteHora: state.corteHorarioAr)
          : null;

      final results = await Future.wait([
        cargarDatosCierreSesion(
          sesionIds: ids,
          rangoSinSesion: rangoSinSesion,
          finanzasRepo: finanzasRepo,
          egresosRepo: egresosRepo,
        ),
        sinSesiones || seleccionadaId == null || consolidado
            ? Future<GuiaCambioResumen>.value(
                const GuiaCambioResumen(
                  saldoActual: 0,
                  movimientos: [],
                  cantReposiciones: 0,
                  cantUsos: 0,
                  totalReposiciones: 0,
                  totalUsos: 0,
                ),
              )
            : cierreRepo.obtenerGuiaCambioSesiones(ids),
      ]);

      final datos = results[0] as DatosCierreSesion;
      final guia = results[1] as GuiaCambioResumen;

      final ingresosTurno = datos.ingresos;
      final egresosTurno = datos.egresos;
      final retirosTurno = datos.retiros;
      final otrosEgresosTurno = datos.otrosEgresos;
      final efectivoBruto = datos.efectivoBruto;
      final transferenciaBruta = datos.transferenciaBruta;
      final egresosEfectivo = datos.egresosEfectivo;
      final egresosTransferencia = datos.egresosTransferencia;
      final retirosEfectivo = datos.retirosEfectivo;
      final retirosTransferencia = datos.retirosTransferencia;
      final efectivoNeto = datos.efectivoNeto;
      final transferenciaNeta = datos.transferenciaNeta;
      final totalNeto = datos.totalNeto;

      state = state.copyWith(
        sesionesDia: sesiones,
        sesionSeleccionadaId: seleccionadaId,
        clearSesionSeleccionada: seleccionadaId == null,
        consolidado: consolidado,
        sinSesiones: sinSesiones,
        turno: turno,
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
