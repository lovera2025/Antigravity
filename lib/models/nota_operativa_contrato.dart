/// Nota operativa por contrato de alumno — espejo local ↔ Supabase; sin impacto contable.
class NotaOperativaContrato {
  final String id;
  final String contratoAlumnoId;
  final String texto;
  final bool resuelto;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NotaOperativaContrato({
    required this.id,
    required this.contratoAlumnoId,
    required this.texto,
    required this.resuelto,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NotaOperativaContrato.fromMap(Map<String, dynamic> map) {
    return NotaOperativaContrato(
      id: map['id'] as String? ?? '',
      contratoAlumnoId: map['contrato_alumno_id'] as String,
      texto: map['texto'] as String? ?? '',
      resuelto: ((map['resuelto'] as num?)?.toInt() ?? 0) != 0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  bool get tieneTexto => texto.trim().isNotEmpty;
}
