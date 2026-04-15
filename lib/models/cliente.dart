class Cliente {
  final String id;
  final String nombreCompleto;
  final String? telefono;
  final String? email;
  final bool isArchived;
  final DateTime? createdAt;

  Cliente({
    required this.id,
    required this.nombreCompleto,
    this.telefono,
    this.email,
    this.isArchived = false,
    this.createdAt,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      id: json['id'],
      nombreCompleto: json['nombre_completo'] ?? 'CLIENTE DESCONOCIDO',
      telefono: json['telefono'],
      email: json['email'],
      isArchived: (json['is_archived'] == 1 || json['is_archived'] == true),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre_completo': nombreCompleto,
      'telefono': telefono,
      'email': email,
      'is_archived': isArchived ? 1 : 0,
    };
  }
}
