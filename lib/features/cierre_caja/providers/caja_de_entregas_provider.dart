import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../common/services/pdf_service.dart';
import '../../common/widgets/operational_sync_coordinator.dart'
    show operationalSyncRevisionProvider;
import '../../eventos/repositories/contratos_repository.dart';
import '../../eventos/repositories/entradas_entregas_repository.dart';
import '../../eventos/repositories/entradas_retiro_repository.dart';
import '../../eventos/services/caja_de_entregas.dart';

/// La caja de entregas de una fiesta, para ENTRADAS del cierre de caja: lo que
/// se entregó sin cargo, por quién (20-nov-2026). Se relee cuando baja algo de
/// otro equipo y **se descarta al dejar de mirarla** (al volver, lee de nuevo,
/// también lo que se entregó en este mismo equipo). **Solo en el equipo**: la
/// web no tiene esa base (lo decide quien la muestra).
final cajaDeEntregasDeLaFiestaProvider =
    FutureProvider.autoDispose.family<CajaDeEntregas, String>((ref, eventoId) async {
  ref.watch(operationalSyncRevisionProvider);
  final todos = await ref.read(contratosRepositoryProvider).getByEvento(eventoId);
  final ids = [for (final a in todos) a.id];
  final retiros =
      await ref.read(entradasRetiroRepositoryProvider).obtenerPorContratoIds(ids);
  final renglones =
      await ref.read(entradasEntregasRepositoryProvider).deContratos(ids);
  return CajaDeEntregas.de(
    alumnos: [for (final a in todos) if (!a.esBajaTemporal) a],
    todos: todos,
    retiros: retiros,
    renglones: [for (final l in renglones.values) ...l],
  );
});

/// IMPRIMIR de la caja de entregas: arma el PDF y lo abre. Las pruebas lo
/// reemplazan (no abren nada).
typedef ImprimirEntregasSinCargo = Future<void> Function(
  CajaDeEntregas caja, {
  required String fiesta,
  DateTime? fechaFiesta,
  String? soloDe,
});

final imprimirEntregasSinCargoProvider = Provider<ImprimirEntregasSinCargo>(
  (ref) => PdfService.generarEntregasSinCargo,
);
