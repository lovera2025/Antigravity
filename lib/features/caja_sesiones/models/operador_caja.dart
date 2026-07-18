class OperadorCaja {
  final String id;
  final String nombre;
  final String pin;
  final bool activo;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OperadorCaja({
    required this.id,
    required this.nombre,
    required this.pin,
    required this.activo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OperadorCaja.fromMap(Map<String, dynamic> m) {
    return OperadorCaja(
      id: m['id'] as String,
      nombre: (m['nombre'] as String?)?.trim() ?? '',
      pin: (m['pin'] as String?) ?? '',
      activo: (m['activo'] as int? ?? 1) == 1,
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'pin': pin,
    'activo': activo ? 1 : 0,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSyncPayload() => {
    'id': id,
    'nombre': nombre,
    'pin': pin,
    'activo': activo,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  OperadorCaja copyWith({
    String? nombre,
    String? pin,
    bool? activo,
    DateTime? updatedAt,
  }) {
    return OperadorCaja(
      id: id,
      nombre: nombre ?? this.nombre,
      pin: pin ?? this.pin,
      activo: activo ?? this.activo,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
