class SolicitudCotizacion {
  final String id;
  final String clienteNombre;
  final String clienteCelular;
  final List<String> serviciosIds;
  final double totalEstimado;
  final DateTime fecha;
  final String estado;
  final String? comentarios;

  SolicitudCotizacion({
    required this.id,
    required this.clienteNombre,
    required this.clienteCelular,
    required this.serviciosIds,
    required this.totalEstimado,
    required this.fecha,
    this.estado = 'pendiente',
    this.comentarios,
  });

  factory SolicitudCotizacion.fromJson(Map<String, dynamic> json) {
    return SolicitudCotizacion(
      id: json['id'],
      clienteNombre: json['cliente_nombre'] ?? 'Anónimo',
      clienteCelular: json['cliente_celular'] ?? '',
      serviciosIds: List<String>.from(json['servicios_seleccionados'] ?? []),
      totalEstimado: double.parse((json['total_estimado'] ?? 0).toString()),
      fecha: DateTime.parse(json['fecha']),
      estado: json['estado'] ?? 'pendiente',
      comentarios: json['comentarios'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cliente_nombre': clienteNombre,
      'cliente_celular': clienteCelular,
      'servicios_seleccionados': serviciosIds,
      'total_estimado': totalEstimado,
      'fecha': fecha.toIso8601String(),
      'estado': estado,
      'comentarios': comentarios,
    };
  }
}
