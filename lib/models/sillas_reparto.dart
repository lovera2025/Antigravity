/// Cómo reparte un alumno sus sillas extra entre sus mesas, tal como se eligió.
///
/// Se guarda cuántas van a la mesa principal; el resto va a las adicionales, de
/// a 2 por mesa. También se guarda para qué cuenta se eligió —cuántas sillas
/// extra y cuántas mesas tenía en ese momento—: si después compra otra silla o
/// cambian sus mesas, la elección deja de valer sola y vuelve a "a confirmar"
/// (ver `RepartoSillas.estado`).
class SillasReparto {
  final String id;
  final String contratoAlumnoId;

  /// Sillas extra que van a la mesa principal.
  final int sillasPrincipal;

  /// Sillas extra que tenía cuando se eligió.
  final int sillasExtra;

  /// Mesas que tenía cuando se eligió (la principal más las extra).
  final int mesas;

  /// Quién lo cargó: el operador de caja, "Jefe" o el usuario logueado.
  final String? hechoPor;

  final DateTime createdAt;
  final DateTime updatedAt;

  const SillasReparto({
    required this.id,
    required this.contratoAlumnoId,
    required this.sillasPrincipal,
    required this.sillasExtra,
    required this.mesas,
    this.hechoPor,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SillasReparto.fromMap(Map<String, dynamic> map) {
    int entero(Object? v) => (v as num?)?.toInt() ?? 0;
    return SillasReparto(
      id: map['id'] as String? ?? '',
      contratoAlumnoId: map['contrato_alumno_id'] as String,
      sillasPrincipal: entero(map['sillas_principal']),
      sillasExtra: entero(map['sillas_extra']),
      mesas: entero(map['mesas']),
      hechoPor: map['hecho_por'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'contrato_alumno_id': contratoAlumnoId,
        'sillas_principal': sillasPrincipal,
        'sillas_extra': sillasExtra,
        'mesas': mesas,
        'hecho_por': hechoPor,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
