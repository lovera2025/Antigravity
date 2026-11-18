import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_engine.dart';
import '../../../models/contrato_alumno.dart';
import '../../../models/sillas_reparto.dart';
import '../../../models/sorteo_mesas_registro.dart';
import '../../common/utils/subir_ya.dart';
import '../services/revision_de_lugares.dart';
import 'contratos_repository.dart';
import 'sillas_reparto_repository.dart';
import 'sorteos_mesas_repository.dart';

/// [RevisionDeLugares] con la base de la PC y la nube de verdad.
///
/// **Es el único lugar que le agrega algo a un renglón ya escrito del registro
/// de sorteos** (`completarLugares`), y solo lo llama la ventana de la lista de
/// PRECIOS, en modo jefe (`test/solo_modo_jefe_test.dart` lo vigila).
class _PuertosDeLaApp implements PuertosDeLaRevision {
  final Ref _ref;

  _PuertosDeLaApp(this._ref);

  ContratosRepository get _contratos => _ref.read(contratosRepositoryProvider);

  @override
  Future<bool> ponerAlDia() =>
      _ref.read(syncEngineProvider).bajarParaLosLugares();

  @override
  Future<List<ContratoAlumno>> alumnos(String eventoId) =>
      _contratos.getByEvento(eventoId);

  @override
  Future<Map<String, List<Map<String, dynamic>>>> pagos(
    List<String> alumnoIds,
  ) async {
    final r = <String, List<Map<String, dynamic>>>{};
    for (final p in await _contratos.getPagosForContratoIds(alumnoIds)) {
      final id = p['contrato_alumno_id'] as String?;
      if (id != null) r.putIfAbsent(id, () => []).add(p);
    }
    return r;
  }

  @override
  Future<Map<String, SillasReparto>> repartos(List<String> alumnoIds) =>
      _ref.read(sillasRepartoRepositoryProvider).obtenerPorContratoIds(alumnoIds);

  @override
  Future<List<SorteoMesasRegistro>> registros(String eventoId) =>
      _ref.read(sorteosMesasRepositoryProvider).delEvento(eventoId);

  @override
  Future<bool> guardar(String registroId, Map<String, String> lugares) async {
    final desde = DateTime.now().toUtc();
    final bien = await _ref
        .read(sorteosMesasRepositoryProvider)
        .completarLugares(registroId, lugares);
    if (!bien) return false;
    // Cuanto antes sube, antes lo ven las otras PCs y la tablet que vende. Si
    // no sube ahora, sube con la cola de siempre: ya quedó guardado.
    try {
      await _ref.read(subidaInmediataProvider).subir(
            tabla: 'sorteos_mesas',
            registroId: registroId,
            desde: desde,
          );
    } catch (e) {
      debugPrint('Los lugares quedaron guardados; suben con la cola: $e');
    }
    return true;
  }
}

final revisionDeLugaresProvider = Provider<RevisionDeLugares>(
  (ref) => RevisionDeLugares(_PuertosDeLaApp(ref)),
);
