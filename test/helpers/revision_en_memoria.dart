// La lista de PRECIOS de una fiesta ya sorteada (`RevisionDeLugares`) sin base
// ni nube: los alumnos, sus pagos, los repartos y el registro en memoria.
// "Poner al día" puede traer lo que cargó otra PC, y guardar le agrega los
// lugares al renglón igual que `completarLugares`.
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:arguello_events/features/eventos/repositories/revision_de_lugares_de_la_app.dart';
import 'package:arguello_events/features/eventos/services/revision_de_lugares.dart';
import 'package:arguello_events/models/contrato_alumno.dart';
import 'package:arguello_events/models/sillas_reparto.dart';
import 'package:arguello_events/models/sorteo_mesas_registro.dart';

class RevisionEnMemoria implements PuertosDeLaRevision {
  RevisionEnMemoria({
    required this.alumnosDeLaFiesta,
    required this.registrosDeLaFiesta,
    Map<String, List<Map<String, dynamic>>>? pagos,
    Map<String, SillasReparto>? repartos,
  })  : pagosPorAlumno = pagos ?? {},
        repartosPorAlumno = repartos ?? {};

  /// Las mismas listas que usa el resto de la prueba, si las comparte.
  final List<ContratoAlumno> alumnosDeLaFiesta;
  final List<SorteoMesasRegistro> registrosDeLaFiesta;
  final Map<String, List<Map<String, dynamic>>> pagosPorAlumno;
  final Map<String, SillasReparto> repartosPorAlumno;

  bool hayInternet = true;

  /// En false, la base no guarda.
  bool guarda = true;

  /// Lo que "baja" de la nube al poner al día: otra PC cargó algo.
  void Function(RevisionEnMemoria)? alPonerAlDia;

  int puestasAlDia = 0;
  int lecturasDePagos = 0;
  final guardados = <({String registroId, Map<String, String> lugares})>[];

  @override
  Future<bool> ponerAlDia() async {
    if (!hayInternet) return false;
    puestasAlDia++;
    alPonerAlDia?.call(this);
    return true;
  }

  @override
  Future<List<ContratoAlumno>> alumnos(String eventoId) async =>
      [for (final a in alumnosDeLaFiesta) if (a.eventoId == eventoId) a];

  @override
  Future<Map<String, List<Map<String, dynamic>>>> pagos(
    List<String> alumnoIds,
  ) async {
    lecturasDePagos++;
    return {
      for (final id in alumnoIds)
        if (pagosPorAlumno[id] != null) id: pagosPorAlumno[id]!,
    };
  }

  @override
  Future<Map<String, SillasReparto>> repartos(List<String> alumnoIds) async => {
        for (final id in alumnoIds)
          if (repartosPorAlumno[id] != null) id: repartosPorAlumno[id]!,
      };

  @override
  Future<List<SorteoMesasRegistro>> registros(String eventoId) async =>
      [for (final r in registrosDeLaFiesta) if (r.eventoId == eventoId) r];

  @override
  Future<bool> guardar(String registroId, Map<String, String> lugares) async {
    if (!guarda) return false;
    final i = registrosDeLaFiesta.indexWhere((r) => r.id == registroId);
    if (i < 0) return false;
    final fila = registrosDeLaFiesta[i].toMap();
    final texto =
        SorteoMesasRegistro.resultadoConLugares(fila['resultado'], lugares);
    if (texto == null) return false;
    registrosDeLaFiesta[i] =
        SorteoMesasRegistro.fromMap({...fila, 'resultado': texto});
    guardados.add((registroId: registroId, lugares: lugares));
    return true;
  }

  RevisionDeLugares get revision => RevisionDeLugares(this);

  /// El provider de la app, apuntando acá.
  Override get reemplazo =>
      revisionDeLugaresProvider.overrideWithValue(revision);
}
