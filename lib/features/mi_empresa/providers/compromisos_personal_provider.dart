import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/compromiso_personal.dart';
import '../repositories/compromisos_personal_repository.dart';
import 'finanzas_provider.dart';

/// Cuentas pendientes con cada persona, con su saldo ya resuelto.
class CompromisosPersonalNotifier
    extends AsyncNotifier<List<CompromisoConSaldo>> {
  @override
  Future<List<CompromisoConSaldo>> build() => _cargar();

  Future<List<CompromisoConSaldo>> _cargar() {
    return ref.read(compromisosPersonalRepositoryProvider).listarConSaldo();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_cargar);
  }

  Future<void> crear({
    required String persona,
    required String tipo,
    required double montoTotal,
    String? concepto,
    DateTime? fechaInicio,
    String? nota,
  }) async {
    await ref.read(compromisosPersonalRepositoryProvider).crear(
          persona: persona,
          tipo: tipo,
          montoTotal: montoTotal,
          concepto: concepto,
          fechaInicio: fechaInicio,
          nota: nota,
        );
    await refresh();
  }

  /// Registra un pago y refresca **también** finanzas: el pago es un egreso, así
  /// que entra al flujo de caja del mes y a la liquidación de esa persona.
  Future<void> registrarPago({
    required String compromisoId,
    required String persona,
    required double monto,
    required String origenFondos,
    String? medioPago,
    DateTime? fecha,
    String? sesionCajaId,
  }) async {
    await ref.read(compromisosPersonalRepositoryProvider).registrarPago(
          compromisoId: compromisoId,
          persona: persona,
          monto: monto,
          origenFondos: origenFondos,
          medioPago: medioPago,
          fecha: fecha,
          sesionCajaId: sesionCajaId,
        );
    await refresh();
    await ref.read(finanzasProvider.notifier).recargar();
  }

  Future<void> cancelar(String id) async {
    await ref.read(compromisosPersonalRepositoryProvider).cancelar(id);
    await refresh();
  }

  Future<void> reabrir(String id) async {
    await ref.read(compromisosPersonalRepositoryProvider).reabrir(id);
    await refresh();
  }

  /// Lanza [CompromisoConPagosException] si la cuenta ya recibió pagos.
  Future<void> eliminar(String id) async {
    await ref.read(compromisosPersonalRepositoryProvider).eliminar(id);
    await refresh();
  }
}

final compromisosPersonalProvider =
    AsyncNotifierProvider<CompromisosPersonalNotifier, List<CompromisoConSaldo>>(
  CompromisosPersonalNotifier.new,
);

/// Cuentas abiertas de una persona, para el chip de "debe $X" al lado de su
/// nombre en LIQUIDACIÓN POR OPERADOR.
///
/// La identidad es el texto libre de `egresos.proveedor`, así que se compara sin
/// distinguir mayúsculas ni espacios de más — es lo máximo que se puede hacer
/// sin una tabla de personas.
final deudaPorPersonaProvider = Provider<Map<String, double>>((ref) {
  final cuentas = ref.watch(compromisosPersonalProvider).value ?? const [];
  final out = <String, double>{};
  for (final c in cuentas) {
    if (!c.sigueAbierto) continue;
    final clave = c.compromiso.persona.trim().toLowerCase();
    if (clave.isEmpty) continue;
    out.update(clave, (v) => v + c.saldo, ifAbsent: () => c.saldo);
  }
  return out;
});
