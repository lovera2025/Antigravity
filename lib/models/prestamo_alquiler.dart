/// Línea de ítem prestado (sillas, mesas, etc.).
class PrestamoAlquilerLinea {
  final String id;
  final String prestamoId;
  final String descripcion;
  final double cantidad;
  final double precioUnitario;
  final double lineaTotal;
  final int orden;

  PrestamoAlquilerLinea({
    required this.id,
    required this.prestamoId,
    required this.descripcion,
    required this.cantidad,
    required this.precioUnitario,
    required this.lineaTotal,
    this.orden = 0,
  });

  factory PrestamoAlquilerLinea.fromMap(Map<String, dynamic> m) {
    return PrestamoAlquilerLinea(
      id: m['id'].toString(),
      prestamoId: m['prestamo_id'].toString(),
      descripcion: m['descripcion']?.toString() ?? '',
      cantidad: (m['cantidad'] as num?)?.toDouble() ?? 0,
      precioUnitario: (m['precio_unitario'] as num?)?.toDouble() ?? 0,
      lineaTotal: (m['linea_total'] as num?)?.toDouble() ?? 0,
      orden: (m['orden'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'prestamo_id': prestamoId,
        'descripcion': descripcion,
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'linea_total': lineaTotal,
        'orden': orden,
      };
}

/// Pago asociado a un préstamo (seña, saldo, etc.).
class PagoPrestamoAlquiler {
  final String id;
  final String prestamoId;
  final double monto;
  final String? concepto;
  final DateTime fechaPago;
  final DateTime? createdAt;
  final String? medioPago;

  PagoPrestamoAlquiler({
    required this.id,
    required this.prestamoId,
    required this.monto,
    this.concepto,
    required this.fechaPago,
    this.createdAt,
    this.medioPago,
  });

  factory PagoPrestamoAlquiler.fromMap(Map<String, dynamic> m) {
    return PagoPrestamoAlquiler(
      id: m['id'].toString(),
      prestamoId: m['prestamo_id'].toString(),
      monto: (m['monto'] as num?)?.toDouble() ?? 0,
      concepto: m['concepto']?.toString(),
      fechaPago: m['fecha_pago'] != null
          ? DateTime.tryParse(m['fecha_pago'].toString()) ?? DateTime.now()
          : DateTime.now(),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      medioPago: m['medio_pago']?.toString(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'id': id,
        'prestamo_id': prestamoId,
        'monto': monto,
        'concepto': concepto,
        'fecha_pago': fechaPago.toUtc().toIso8601String(),
        'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        'medio_pago': medioPago,
      };
}

/// Registro operativo de préstamo / alquiler de equipamiento.
class PrestamoAlquiler {
  final String id;
  final String clienteId;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final bool aplicaIva;
  final double alicuotaIva;
  final double subtotalNeto;
  final double montoIva;
  final double total;
  final String? textoRedaccion;
  final String? textoDisclaimer;
  final bool visibleListado;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PrestamoAlquiler({
    required this.id,
    required this.clienteId,
    required this.fechaInicio,
    required this.fechaFin,
    required this.aplicaIva,
    required this.alicuotaIva,
    required this.subtotalNeto,
    required this.montoIva,
    required this.total,
    this.textoRedaccion,
    this.textoDisclaimer,
    this.visibleListado = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PrestamoAlquiler.fromMap(Map<String, dynamic> m) {
    bool flag(dynamic v) {
      if (v is bool) return v;
      if (v is int) return v != 0;
      if (v is num) return v != 0;
      return false;
    }

    return PrestamoAlquiler(
      id: m['id'].toString(),
      clienteId: m['cliente_id'].toString(),
      fechaInicio: DateTime.tryParse(m['fecha_inicio'].toString()) ?? DateTime.now(),
      fechaFin: DateTime.tryParse(m['fecha_fin'].toString()) ?? DateTime.now(),
      aplicaIva: flag(m['aplica_iva']),
      alicuotaIva: (m['alicuota_iva'] as num?)?.toDouble() ?? 21,
      subtotalNeto: (m['subtotal_neto'] as num?)?.toDouble() ?? 0,
      montoIva: (m['monto_iva'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      textoRedaccion: m['texto_redaccion']?.toString(),
      textoDisclaimer: m['texto_disclaimer']?.toString(),
      visibleListado: flag(m['visible_listado'] ?? 1),
      createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
      updatedAt: m['updated_at'] != null ? DateTime.tryParse(m['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toSqlMap() => {
        'id': id,
        'cliente_id': clienteId,
        'fecha_inicio': fechaInicio.toUtc().toIso8601String(),
        'fecha_fin': fechaFin.toUtc().toIso8601String(),
        'aplica_iva': aplicaIva ? 1 : 0,
        'alicuota_iva': alicuotaIva,
        'subtotal_neto': subtotalNeto,
        'monto_iva': montoIva,
        'total': total,
        'texto_redaccion': textoRedaccion,
        'texto_disclaimer': textoDisclaimer,
        'visible_listado': visibleListado ? 1 : 0,
        'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// Payload para Supabase (tipos JSON compatibles).
  Map<String, dynamic> toRemotePayload() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'fecha_inicio': fechaInicio.toUtc().toIso8601String(),
      'fecha_fin': fechaFin.toUtc().toIso8601String(),
      'aplica_iva': aplicaIva,
      'alicuota_iva': alicuotaIva,
      'subtotal_neto': subtotalNeto,
      'monto_iva': montoIva,
      'total': total,
      'texto_redaccion': textoRedaccion,
      'texto_disclaimer': textoDisclaimer,
      'visible_listado': visibleListado,
      'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }
}
