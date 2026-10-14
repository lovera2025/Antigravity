import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/invitado.dart';
import '../../../models/evento.dart';
import '../../../models/sillas_reparto.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/kiosk_launcher.dart';
import '../../../core/services/sync_engine.dart';
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/eventos_repository.dart';
import '../../eventos/repositories/sillas_reparto_repository.dart';
import '../repositories/invitados_repository.dart';
import '../repositories/supabase_invitados_repository.dart';
import '../services/puerta_del_evento.dart';
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

// ── La puerta de un evento, particular o masivo ────────────────────────────

/// Los alumnos de un evento masivo y cómo repartió cada familia sus sillas,
/// tal como están en la base de esta PC.
class AlumnosDeLaPuerta {
  final List<ContratoAlumno> alumnos;
  final Map<String, SillasReparto> repartos;

  const AlumnosDeLaPuerta(this.alumnos, this.repartos);
}

/// Los alumnos de un evento y sus repartos de sillas, de la base de esta PC.
/// Lo leen Recepción ([alumnosDeLaPuertaProvider]) y la ficha del tótem.
Future<AlumnosDeLaPuerta> leerAlumnosDeLaPuerta(
  ContratosRepository contratos,
  SillasRepartoRepository sillas,
  String eventoId,
) async {
  final alumnos = await contratos.getByEvento(eventoId);
  final repartos =
      await sillas.obtenerPorContratoIds([for (final a in alumnos) a.id]);
  return AlumnosDeLaPuerta(alumnos, repartos);
}

/// Lo que bajó de la otra PC y cambia lo que se ve en la puerta de un masivo.
const _tablasDeLaPuerta = {'contratos_alumnos', 'sillas_reparto'};

/// Los alumnos de un evento masivo, de la base de esta PC. Se vuelven a leer
/// cuando baja de la otra PC un cambio de alumnos o de sillas, y cada vez que
/// se abre Recepción.
///
/// Con `StreamController` y `onCancel`, no `async*`: un `async*` con
/// `await for` no suelta la suscripción al cancelarlo (ver CLAUDE.md).
final alumnosDeLaPuertaProvider = StreamProvider.autoDispose
    .family<AlumnosDeLaPuerta, String>((ref, eventoId) {
  final contratos = ref.watch(contratosRepositoryProvider);
  final sillas = ref.watch(sillasRepartoRepositoryProvider);
  final motor = ref.watch(syncEngineProvider);

  late final StreamController<AlumnosDeLaPuerta> controller;
  StreamSubscription<Set<String>>? cambios;
  // Las lecturas van en fila, para que nunca llegue una vieja después de una
  // nueva.
  var cadena = Future<void>.value();

  void leer() {
    cadena = cadena.then((_) async {
      if (controller.isClosed) return;
      try {
        final leidos = await leerAlumnosDeLaPuerta(contratos, sillas, eventoId);
        if (!controller.isClosed) controller.add(leidos);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    });
  }

  controller = StreamController<AlumnosDeLaPuerta>(
    onListen: () {
      cambios = motor.cambiosBajadosStream.listen((tablas) {
        if (tablas.any(_tablasDeLaPuerta.contains)) leer();
      });
      leer();
    },
    onCancel: () async {
      await cambios?.cancel();
    },
  );
  ref.onDispose(() => controller.close());
  return controller.stream;
});

/// Lo que se ve en Recepción del evento elegido: un particular desde su lista
/// de la puerta; un masivo desde sus alumnos, cruzados con quién entró.
final puertaDelEventoProvider = Provider.autoDispose
    .family<AsyncValue<PuertaDelEvento>, String>((ref, eventoId) {
  final eventos = ref.watch(eventosActivosProvider);
  final invitados = ref.watch(invitadosStreamProvider(eventoId));
  if (eventos.isLoading && !eventos.hasValue) return const AsyncValue.loading();
  final evento = eventos.value?.where((e) => e.id == eventoId).firstOrNull;
  if (evento?.modalidad != 'masivo') {
    return invitados.whenData(PuertaDelEvento.particular);
  }
  final alumnos = ref.watch(alumnosDeLaPuertaProvider(eventoId));
  if (alumnos.hasError) {
    return AsyncValue.error(alumnos.error!, alumnos.stackTrace!);
  }
  if (invitados.hasError) {
    return AsyncValue.error(invitados.error!, invitados.stackTrace!);
  }
  final a = alumnos.value;
  final i = invitados.value;
  if (a == null || i == null) return const AsyncValue.loading();
  return AsyncValue.data(
    PuertaDelEvento.masivo(
      alumnos: a.alumnos,
      repartos: a.repartos,
      invitados: i,
    ),
  );
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
