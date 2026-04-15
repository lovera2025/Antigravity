class Servicio {
  final String id;
  final String nombre;
  final String categoria;
  final double? costoBase; // May be null if user doesn't have permissions
  final double? margenGanancia; // May be null if user doesn't have permissions
  final double? costoInterno; // Nuevo campo elite
  final String? eventoId;
  final bool isArchived;


  Servicio({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.costoBase,
    this.margenGanancia,
    this.costoInterno,
    this.eventoId,
    this.isArchived = false,
  });

  factory Servicio.fromJson(Map<String, dynamic> json) {
    return Servicio(
      id: json['id'].toString(),
      nombre: json['nombre'] ?? '',
      categoria: json['categoria'] ?? 'General',
      costoBase: json['costo_base'] != null ? double.parse(json['costo_base'].toString()) : null,
      margenGanancia: json['margen_ganancia'] != null ? double.parse(json['margen_ganancia'].toString()) : null,
      costoInterno: json['costo_interno'] != null ? double.parse(json['costo_interno'].toString()) : null,
      eventoId: json['evento_id'] as String?,
      isArchived: json['is_archived'] == true || json['is_archived'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'categoria': categoria,
      if (costoBase != null) 'costo_base': costoBase,
      if (margenGanancia != null) 'margen_ganancia': margenGanancia,
      if (costoInterno != null) 'costo_interno': costoInterno,
      if (eventoId != null) 'evento_id': eventoId,
      'is_archived': isArchived ? 1 : 0,
    };
  }
}
