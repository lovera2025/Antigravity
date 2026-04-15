class Transaccion {
  final String id;
  final String eventoId;
  final double monto;
  final String? concepto;
  final DateTime? fechaPago;
  final String? createdBy;

  Transaccion({
    required this.id,
    required this.eventoId,
    required this.monto,
    this.concepto,
    this.fechaPago,
    this.createdBy,
  });

  factory Transaccion.fromJson(Map<String, dynamic> json) {
    return Transaccion(
      id: json['id'],
      eventoId: json['evento_id'],
      monto: double.parse(json['monto'].toString()),
      concepto: json['concepto'],
      fechaPago: json['fecha_pago'] != null ? DateTime.parse(json['fecha_pago']) : null,
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'concepto': concepto,
      // Insert fecha_pago only if explicitly defined, else DB sets NOW()
    };
  }
}
