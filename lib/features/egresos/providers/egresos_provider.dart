import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/egresos_repository.dart';
import '../../common/widgets/operational_sync_coordinator.dart';

/// Notifier que maneja el estado de los egresos.
class EgresosNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  FutureOr<List<Map<String, dynamic>>> build() async {
    // El canal de Realtime se retiró el 2026-09-02: `egresos` ya baja cada 10
    // segundos en el pull incremental, así que basta con escuchar ese pull.
    ref.listen<int>(operationalSyncRevisionProvider, (prev, next) {
      if (prev != next) unawaited(refresh());
    });

    return _fetchEgresos();
  }

  Future<List<Map<String, dynamic>>> _fetchEgresos() async {
    final repo = ref.read(egresosRepositoryProvider);
    return await repo.getEgresosConEvento();
  }

  /// Método para refrescar manualmente (ej. pull-to-refresh)
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchEgresos());
  }
}

/// Provider global para los egresos.
final egresosProvider = AsyncNotifierProvider<EgresosNotifier, List<Map<String, dynamic>>>(
  EgresosNotifier.new,
);

/// Provider derivado para calcular totales y categorías de forma eficiente.
final egresosStatsProvider = Provider((ref) {
  final egresosAsync = ref.watch(egresosProvider);
  
  return egresosAsync.maybeWhen(
    data: (data) {
      double totalMes = 0;
      double totalGeneral = 0;
      final now = DateTime.now();
      final mapCategorias = <String, double>{};
      final countCategorias = <String, int>{};

      for (var item in data) {
        final monto = double.tryParse(item['monto'].toString()) ?? 0;
        totalGeneral += monto;
        
        final egresoDate = DateTime.tryParse(item['fecha']?.toString() ?? '')?.toLocal();
        if (egresoDate != null && egresoDate.month == now.month && egresoDate.year == now.year) {
          totalMes += monto;
        }

        final cat = (item['categoria'] ?? 'Otro') as String;
        mapCategorias[cat] = (mapCategorias[cat] ?? 0) + monto;
        countCategorias[cat] = (countCategorias[cat] ?? 0) + 1;
      }

      return {
        'totalMes': totalMes,
        'totalGeneral': totalGeneral,
        'totalesPorCategoria': mapCategorias,
        'conteoPorCategoria': countCategorias,
        'categorias': mapCategorias.keys.toSet(),
      };
    },
    orElse: () => {
      'totalMes': 0.0,
      'totalGeneral': 0.0,
      'totalesPorCategoria': <String, double>{},
      'conteoPorCategoria': <String, int>{},
      'categorias': <String>{},
    },
  );
});
