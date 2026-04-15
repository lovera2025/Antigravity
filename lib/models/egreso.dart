class Egreso {
  final String id;
  final String eventoId;
  final double monto;
  final String? proveedor;
  final String? categoria;
  final DateTime? fecha;
  final String? createdBy;

  Egreso({
    required this.id,
    required this.eventoId,
    required this.monto,
    this.proveedor,
    this.categoria,
    this.fecha,
    this.createdBy,
  });

  factory Egreso.fromJson(Map<String, dynamic> json) {
    return Egreso(
      id: json['id']?.toString() ?? '',
      eventoId: json['evento_id']?.toString() ?? '',
      monto: double.tryParse(json['monto']?.toString() ?? '0') ?? 0.0,
      proveedor: json['proveedor'] ?? json['concepto'] ?? 'Gasto sin nombre',
      categoria: json['categoria'] ?? 'Otro',
      fecha: json['fecha'] != null 
          ? DateTime.tryParse(json['fecha']) 
          : (json['fecha_pago'] != null ? DateTime.tryParse(json['fecha_pago']) : DateTime.now()),
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'proveedor': proveedor,
      'categoria': categoria,
      'fecha': fecha?.toIso8601String(),
    };
  }
}
