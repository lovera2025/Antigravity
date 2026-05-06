import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/obligacion_pago.dart';
import '../repositories/obligaciones_repository.dart';

class ObligacionesNotifier extends AsyncNotifier<List<ObligacionPago>> {
  @override
  Future<List<ObligacionPago>> build() async {
    return _fetch();
  }

  Future<List<ObligacionPago>> _fetch() async {
    final repo = ref.read(obligacionesRepositoryProvider);
    return repo.getObligaciones();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetch());
  }

  Future<void> guardar(ObligacionPago oblig) async {
    final repo = ref.read(obligacionesRepositoryProvider);
    await repo.guardarObligacion(oblig);
    await refresh();
  }

  Future<void> eliminar(String id) async {
    final repo = ref.read(obligacionesRepositoryProvider);
    await repo.eliminarObligacion(id);
    await refresh();
  }
}

final obligacionesProvider = AsyncNotifierProvider<ObligacionesNotifier, List<ObligacionPago>>(
  ObligacionesNotifier.new,
);
