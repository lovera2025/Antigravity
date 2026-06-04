import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/ar_time.dart';
import '../../../models/caja_fuerte_movimiento.dart';
import '../models/ingreso_detallado.dart';
import '../repositories/caja_fuerte_repository.dart';
import '../repositories/finanzas_repository.dart';

class CajaFuerteResumen {
  final List<CajaFuerteMovimiento> movimientos;
  final double saldo;
  /// Cobros registrados en la app, semana lun–dom calendario AR actual.
  final double ingresosRegistradosSemana;
  final double ultimaAsignacionMonto;

  const CajaFuerteResumen({
    required this.movimientos,
    required this.saldo,
    required this.ingresosRegistradosSemana,
    this.ultimaAsignacionMonto = 0,
  });

  /// Suma histórica de depósitos al cofre.
  double get totalDepositado {
    var s = 0.0;
    for (final m in movimientos) {
      if (m.esAsignacion) s += m.monto;
    }
    return s;
  }

  /// Suma histórica de retiros del cofre.
  double get totalRetirado {
    var s = 0.0;
    for (final m in movimientos) {
      if (!m.esAsignacion) s += m.monto;
    }
    return s;
  }

  double get retirosPersonal {
    var s = 0.0;
    for (final m in movimientos) {
      if (m.motivoRetiro == CajaFuerteMotivoRetiro.personal) s += m.monto;
    }
    return s;
  }

  double get retirosNegocio {
    var s = 0.0;
    for (final m in movimientos) {
      if (m.motivoRetiro == CajaFuerteMotivoRetiro.negocio) s += m.monto;
    }
    return s;
  }

  /// Retiros sumados en la semana calendario AR actual.
  double get retirosSemana {
    final rango = _rangoSemanaAr();
    double s = 0;
    for (final m in movimientos) {
      if (m.esAsignacion) continue;
      final d = ArTime.toAr(m.createdAt);
      final dd = DateTime(d.year, d.month, d.day);
      if (dd.compareTo(rango.$1) >= 0 && dd.compareTo(rango.$2) <= 0) {
        s += m.monto;
      }
    }
    return s;
  }

  static (DateTime inicioIncl, DateTime finIncl) _rangoSemanaAr() {
    final na = ArTime.nowAr();
    final hoy = DateTime(na.year, na.month, na.day);
    final weekday = hoy.weekday;
    final inicio = hoy.subtract(Duration(days: weekday - 1));
    final fin = inicio.add(const Duration(days: 6));
    return (inicio, fin);
  }

  static double sumarIngresosSemanaAr(List<IngresoDetallado> todos) {
    final rango = _rangoSemanaAr();
    double s = 0;
    for (final i in todos) {
      final d = ArTime.toAr(i.fecha);
      final dd = DateTime(d.year, d.month, d.day);
      if (dd.compareTo(rango.$1) >= 0 && dd.compareTo(rango.$2) <= 0) {
        s += i.monto;
      }
    }
    return s;
  }
}

class CajaFuerteNotifier extends AsyncNotifier<CajaFuerteResumen> {
  @override
  Future<CajaFuerteResumen> build() async {
    return _cargar();
  }

  Future<CajaFuerteResumen> _cargar() async {
    final repo = ref.read(cajaFuerteRepositoryProvider);
    final fin = ref.read(finanzasRepositoryProvider);
    final mov = await repo.listarOrdenDesc();
    var saldo = 0.0;
    for (final m in mov) {
      if (m.esAsignacion) {
        saldo += m.monto;
      } else {
        saldo -= m.monto;
      }
    }
    final ingTodos = await fin.obtenerIngresosDetallados(mes: null, eventoId: null);
    final ingSem = CajaFuerteResumen.sumarIngresosSemanaAr(ingTodos);
    final ultimaAsig = await repo.montoUltimaAsignacion() ?? 0.0;
    return CajaFuerteResumen(
      movimientos: mov,
      saldo: saldo,
      ingresosRegistradosSemana: ingSem,
      ultimaAsignacionMonto: ultimaAsig,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _cargar());
  }

  Future<void> registrarAsignacion(double monto, {String? nota}) async {
    final repo = ref.read(cajaFuerteRepositoryProvider);
    await repo.insertar(
      tipo: CajaFuerteMovimiento.tipoAsignacion,
      monto: monto,
      nota: nota,
    );
    await refresh();
  }

  Future<void> registrarRetiro(
    double monto, {
    required CajaFuerteMotivoRetiro motivo,
    String? nota,
  }) async {
    final saldoPrevio = await ref.read(cajaFuerteRepositoryProvider).saldoActual();
    if (monto > saldoPrevio + 1e-6) {
      throw StateError('Saldo insuficiente en Caja fuerte');
    }
    final repo = ref.read(cajaFuerteRepositoryProvider);
    await repo.insertar(
      tipo: CajaFuerteMovimiento.tipoRetiro,
      monto: monto,
      nota: CajaFuerteMovimiento.empaquetarNotaRetiro(motivo, nota),
    );
    await refresh();
  }
}

final cajaFuerteProvider = AsyncNotifierProvider<CajaFuerteNotifier, CajaFuerteResumen>(
  CajaFuerteNotifier.new,
);
