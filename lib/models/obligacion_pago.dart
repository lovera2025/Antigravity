class ObligacionPago {
  final String id;
  final String titulo;
  final String tipoObligacion; // 'empresa' o 'adrian'
  final DateTime fechaVencimiento;
  final double montoEstimado;
  final String estado; // 'pendiente' o 'pagado'
  final DateTime? fechaPago;
  final DateTime createdAt;

  ObligacionPago({
    required this.id,
    required this.titulo,
    required this.tipoObligacion,
    required this.fechaVencimiento,
    this.montoEstimado = 0.0,
    this.estado = 'pendiente',
    this.fechaPago,
    required this.createdAt,
  });

  factory ObligacionPago.fromJson(Map<String, dynamic> json) {
    final rawVenc = json['fecha_vencimiento']?.toString();
    final rawCreated = json['created_at']?.toString();
    final rawPago = json['fecha_pago']?.toString();
    return ObligacionPago(
      id: json['id']?.toString() ?? '',
      titulo: json['titulo']?.toString() ?? '',
      tipoObligacion: json['tipo_obligacion']?.toString() ?? 'empresa',
      fechaVencimiento: rawVenc != null
          ? (DateTime.tryParse(rawVenc) ?? DateTime.now())
          : DateTime.now(),
      montoEstimado: (json['monto_estimado'] as num?)?.toDouble() ?? 0.0,
      estado: json['estado']?.toString() ?? 'pendiente',
      fechaPago: rawPago != null ? DateTime.tryParse(rawPago) : null,
      createdAt: rawCreated != null
          ? (DateTime.tryParse(rawCreated) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'titulo': titulo,
      'tipo_obligacion': tipoObligacion,
      'fecha_vencimiento': fechaVencimiento.toIso8601String(),
      'monto_estimado': montoEstimado,
      'estado': estado,
      'fecha_pago': fechaPago?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  ObligacionPago copyWith({
    String? titulo,
    String? tipoObligacion,
    DateTime? fechaVencimiento,
    double? montoEstimado,
    String? estado,
    DateTime? fechaPago,
  }) {
    return ObligacionPago(
      id: id,
      titulo: titulo ?? this.titulo,
      tipoObligacion: tipoObligacion ?? this.tipoObligacion,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      montoEstimado: montoEstimado ?? this.montoEstimado,
      estado: estado ?? this.estado,
      fechaPago: fechaPago ?? this.fechaPago,
      createdAt: createdAt,
    );
  }
}
