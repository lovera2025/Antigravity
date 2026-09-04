import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/invitado.dart';
import '../../../models/evento.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/kiosk_launcher.dart';
import '../../eventos/repositories/eventos_repository.dart';
import '../repositories/invitados_repository.dart';
import '../repositories/supabase_invitados_repository.dart';
import '../../../main.dart';

// ── Eventos Activos Provider ───────────────────────────────────────────────

final eventosActivosProvider = FutureProvider<List<Evento>>((ref) async {
  final repo = ref.watch(eventosRepositoryProvider);
  // Filtrar solo los confirmados o en planificación para recepción
  final todos = await repo.getAll();
  return todos.where((e) => e.estado == EstadoEvento.confirmado || e.estado == EstadoEvento.planificacion).toList();
});

// ── Selected Event Provider ────────────────────────────────────────────────

class SelectedEventNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? eventoId) {
    if (state == eventoId) return;
    state = eventoId;

    // El tótem proyectado sigue al evento activo. Va acá y no con un `ref.listen`
    // en alguna pantalla porque este es el **único** punto de mutación —los tres
    // dropdowns pasan por `select`— y así funciona aunque la pantalla que cambió
    // el evento no esté montada.
    //
    // Si se limpia la selección no se toca el tótem a propósito: dejar la
    // pantalla del salón en blanco a mitad de un evento es peor que que muestre
    // el anterior un rato.
    if (eventoId != null && KioskLauncher.isTotemActive) {
      KioskLauncher.setEvento(eventoId);
    }
  }

  void clear() {
    state = null;
  }
}

final selectedEventProvider = NotifierProvider<SelectedEventNotifier, String?>(
  SelectedEventNotifier.new,
);

// ── Invitados Stream Provider ──────────────────────────────────────────────
// Nota: En la arquitectura offline-first, usamos un FutureProvider que se invalida
// cuando hay cambios locales o remotos, o un Stream que observa la DB local.
// Por ahora, usaremos un Stream simple que emula la reactividad básica.

final invitadosStreamProvider = StreamProvider.autoDispose.family<List<Invitado>, String>((ref, eventoId) {
  final repo = ref.watch(invitadosRepositoryProvider);
  return repo.watchByEvento(eventoId);
});

final statsEventoProvider = Provider.autoDispose.family<AsyncValue<Map<String, int>>, String>((ref, eventoId) {
  final invitadosAsync = ref.watch(invitadosStreamProvider(eventoId));
  return invitadosAsync.whenData((invitados) {
    final total = invitados.length;
    final ingresados = invitados.where((i) => i.estadoIngreso == EstadoIngreso.ingresado).length;
    return {
      'total': total,
      'ingresados': ingresados,
      'pendientes': total - ingresados,
    };
  });
});


// ── Supabase Invitados Provider (Rutas Públicas/Web) ───────────────────────

final supabaseInvitadosRepositoryProvider = Provider<SupabaseInvitadosRepository>((ref) {
  final supabase = ref.watch(supabaseProvider);
  return SupabaseInvitadosRepository(supabase);
});

// ── Connection Health Provider ─────────────────────────────────────────────

final connectionHealthProvider = StreamProvider<bool>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return connectivity.stream.map((status) => status == AppConnectivity.online);
});
