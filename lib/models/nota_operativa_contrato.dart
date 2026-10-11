import '../core/utils/ar_time.dart';

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

  /// Lo que puede tardar una nota recién escrita en volver de la nube con su
  /// `updated_at`. El trigger de Supabase lo reescribe también al insertar: sin
  /// este margen, toda nota que subió figuraría como modificada.
  ///
  /// Una nota escrita sin internet y subida más tarde pasa el margen y figura
  /// como modificada a la hora en que subió. Es raro, y no hay otro dato del
  /// que sacarlo.
  static const Duration margenDeSubida = Duration(minutes: 5);

  /// Se tocó después de escribirla: el texto, o el "hecho".
  bool get seModifico => updatedAt.difference(createdAt) > margenDeSubida;

  /// Cuándo se escribió y, si se tocó después, cuándo fue la última vez, en
  /// hora de Argentina. Vacío si la nota no trae fecha.
  ///
  /// - con hora: "Escrita el 13/05/2026 20:16 hs · modificada el 10/06/2026
  ///   09:35 hs";
  /// - sin hora, para un renglón corto: "Escrita el 13/05/2026 · modificada el
  ///   10/06/2026".
  String cuando({bool conHora = true}) {
    if (createdAt.millisecondsSinceEpoch == 0) return '';
    String fecha(DateTime d) =>
        conHora ? ArTime.formatFechaHora(d) : ArTime.formatFechaCorta(d);
    final escrita = 'Escrita el ${fecha(createdAt)}';
    return seModifico
        ? '$escrita · modificada el ${fecha(updatedAt)}'
        : escrita;
  }
}
