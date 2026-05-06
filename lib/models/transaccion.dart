/// Prefijo del concepto de la bonificación única por evento (% sobre presupuesto total).
const String kConceptoBonificacionGlobalPrefix = 'Bonificación global (';

class Transaccion {
  final String id;
  final String eventoId;
  final double monto;
  final String? concepto;
  final DateTime? fechaPago;
  final String? createdBy;
  final String? medioPago;
  /// 1 = anulado en sistema (no borra fila; no suma en saldos).
  final int anulado;
  final String? motivoAnulacion;
  final DateTime? fechaAnulacion;

  Transaccion({
    required this.id,
    required this.eventoId,
    required this.monto,
    this.concepto,
    this.fechaPago,
    this.createdBy,
    this.medioPago,
    this.anulado = 0,
    this.motivoAnulacion,
    this.fechaAnulacion,
  });

  factory Transaccion.fromJson(Map<String, dynamic> json) {
    return Transaccion(
      id: json['id'],
      eventoId: json['evento_id'],
      monto: double.parse(json['monto'].toString()),
      concepto: json['concepto'],
      fechaPago: json['fecha_pago'] != null ? DateTime.parse(json['fecha_pago']) : null,
      createdBy: json['created_by'],
      medioPago: json['medio_pago'],
      anulado: (json['anulado'] as num?)?.toInt() ?? 0,
      motivoAnulacion: json['motivo_anulacion']?.toString(),
      fechaAnulacion: json['fecha_anulacion'] != null ? DateTime.tryParse(json['fecha_anulacion'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'concepto': concepto,
      'medio_pago': medioPago,
      if (anulado != 0) 'anulado': anulado,
      if (motivoAnulacion != null) 'motivo_anulacion': motivoAnulacion,
      if (fechaAnulacion != null) 'fecha_anulacion': fechaAnulacion!.toUtc().toIso8601String(),
      // Insert fecha_pago only if explicitly defined, else DB sets NOW()
    };
  }
}

/// Crédito registrado al aplicar descuento en el diálogo de pago (`Bonificación Especial`).
extension TransaccionTipo on Transaccion {
  bool get esAnulada => anulado != 0;

  bool get esBonificacion {
    final c = concepto?.toLowerCase() ?? '';
    return c.contains('bonificaci');
  }

  bool get esBonificacionGlobal {
    final c = concepto ?? '';
    return c.startsWith(kConceptoBonificacionGlobalPrefix);
  }
}
