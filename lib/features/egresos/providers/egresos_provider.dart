import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/egresos_repository.dart';

/// Notifier que maneja el estado de los egresos con soporte para Realtime.
class EgresosNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  RealtimeChannel? _channel;

  @override
  FutureOr<List<Map<String, dynamic>>> build() async {
    // Al destruir el notifier, nos aseguramos de limpiar el canal.
    ref.onDispose(() {
      _channel?.unsubscribe();
    });

    // Suscripción al canal de cambios
    _setupRealtime();

    return _fetchEgresos();
  }

  Future<List<Map<String, dynamic>>> _fetchEgresos() async {
    final repo = ref.read(egresosRepositoryProvider);
    return await repo.getEgresosConEvento();
  }

  void _setupRealtime() {
    final repo = ref.read(egresosRepositoryProvider);
    _channel = repo.subscribeToChanges(() async {
      // Cuando hay un cambio en la DB, refrescamos el estado.
      state = const AsyncValue.loading();
      state = await AsyncValue.guard(() => _fetchEgresos());
    });
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
        
        final egresoDate = DateTime.tryParse(item['fecha'] ?? '');
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
