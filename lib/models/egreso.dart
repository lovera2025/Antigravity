class Egreso {
  final String id;
  final String eventoId;
  final double monto;
  final String? proveedor;
  final String? categoria;
  final DateTime? fecha;
  final String? createdBy;
  final String? medioPago;
  final String? sesionCajaId;

  Egreso({
    required this.id,
    required this.eventoId,
    required this.monto,
    this.proveedor,
    this.categoria,
    this.fecha,
    this.createdBy,
    this.medioPago,
    this.sesionCajaId,
  });

  /// ISO desde SQLite/Supabase → instante UTC canónico (misma política que ingresos).
  /// La presentación en AR usa [ArTime.toAr] en UI/PDF.
  static DateTime? _parseFechaUtc(dynamic raw) {
    if (raw == null) return null;
    final p = DateTime.tryParse(raw.toString());
    if (p == null) return null;
    return p.isUtc ? p : p.toUtc();
  }

  factory Egreso.fromJson(Map<String, dynamic> json) {
    return Egreso(
      id: json['id']?.toString() ?? '',
      eventoId: json['evento_id']?.toString() ?? '',
      monto: double.tryParse(json['monto']?.toString() ?? '0') ?? 0.0,
      proveedor: json['proveedor'] ?? json['concepto'] ?? 'Gasto sin nombre',
      categoria: json['categoria'] ?? 'Otro',
      fecha:
          _parseFechaUtc(json['fecha']) ?? _parseFechaUtc(json['fecha_pago']),
      createdBy: json['created_by'],
      medioPago: json['medio_pago'],
      sesionCajaId: json['sesion_caja_id']?.toString(),
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
      'medio_pago': medioPago,
      'sesion_caja_id': sesionCajaId,
    };
  }
}
