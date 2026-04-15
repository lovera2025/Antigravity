class Invitado {
  final String id;
  final String eventoId;
  final String nombreCompleto;
  final String dni;
  final String? numeroMesa;
  final EstadoIngreso estadoIngreso;
  final int intentosFallidos;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Invitado({
    required this.id,
    required this.eventoId,
    required this.nombreCompleto,
    required this.dni,
    this.numeroMesa,
    required this.estadoIngreso,
    this.intentosFallidos = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory Invitado.fromJson(Map<String, dynamic> json) {
    return Invitado(
      id: json['id'] as String,
      eventoId: json['evento_id'] as String,
      nombreCompleto: json['nombre_completo'] as String,
      dni: json['dni'] as String? ?? '',
      numeroMesa: json['numero_mesa'] as String?,
      estadoIngreso: _parseEstado(json['estado_ingreso'] as String?),
      intentosFallidos: json['intentos_fallidos'] as int? ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'dni': dni,
      'numero_mesa': numeroMesa,
      'estado_ingreso': _formatEstado(estadoIngreso),
      'intentos_fallidos': intentosFallidos,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Invitado copyWith({
    String? id,
    String? eventoId,
    String? nombreCompleto,
    String? dni,
    String? numeroMesa,
    EstadoIngreso? estadoIngreso,
    int? intentosFallidos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Invitado(
      id: id ?? this.id,
      eventoId: eventoId ?? this.eventoId,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      dni: dni ?? this.dni,
      numeroMesa: numeroMesa ?? this.numeroMesa,
      estadoIngreso: estadoIngreso ?? this.estadoIngreso,
      intentosFallidos: intentosFallidos ?? this.intentosFallidos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static EstadoIngreso _parseEstado(String? estado) {
    switch (estado?.toLowerCase()) {
      case 'ingresado':
        return EstadoIngreso.ingresado;
      case 'pendiente':
      default:
        return EstadoIngreso.pendiente;
    }
  }

  static String _formatEstado(EstadoIngreso estado) {
    switch (estado) {
      case EstadoIngreso.ingresado:
        return 'ingresado';
      case EstadoIngreso.pendiente:
        return 'pendiente';
    }
  }
}

enum EstadoIngreso {
  pendiente,
  ingresado,
}
