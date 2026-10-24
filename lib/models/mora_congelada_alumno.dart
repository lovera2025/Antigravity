import '../core/utils/uuid_utils.dart';
import '../features/eventos/services/mora_congelada.dart';

/// La fila de `mora_congelada` (6.2.1): las pausas de la mora de un alumno.
///
/// Una por alumno, con id fijo ([UuidUtils.moraCongeladaId]). **Nunca se
/// borra:** descongelar la guarda con otras pausas. Las columnas son exactamente
/// las que suben y bajan (`sync_engine.dart` y el SQL de la nube lo comparan en
/// los tests).
class MoraCongeladaAlumno {
  final String id;
  final String contratoAlumnoId;
  final String? eventoId;
  final MoraCongelada mora;
  final String createdAt;
  final String updatedAt;

  const MoraCongeladaAlumno({
    required this.id,
    required this.contratoAlumnoId,
    this.eventoId,
    required this.mora,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La fila nueva o la que ya había, con las pausas de [mora].
  factory MoraCongeladaAlumno.para({
    required String contratoAlumnoId,
    String? eventoId,
    required MoraCongelada mora,
    String? createdAt,
    required DateTime ahora,
  }) {
    final iso = ahora.toUtc().toIso8601String();
    return MoraCongeladaAlumno(
      id: UuidUtils.moraCongeladaId(contratoAlumnoId),
      contratoAlumnoId: contratoAlumnoId,
      eventoId: eventoId,
      mora: mora,
      createdAt: createdAt ?? iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'contrato_alumno_id': contratoAlumnoId,
        'evento_id': eventoId,
        'pausas': mora.toJson(),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory MoraCongeladaAlumno.fromMap(Map<String, dynamic> m) =>
      MoraCongeladaAlumno(
        id: m['id'] as String,
        contratoAlumnoId: m['contrato_alumno_id'] as String,
        eventoId: m['evento_id'] as String?,
        mora: MoraCongelada.fromJson(m['pausas']?.toString()),
        createdAt: (m['created_at'] ?? '').toString(),
        updatedAt: (m['updated_at'] ?? '').toString(),
      );
}
