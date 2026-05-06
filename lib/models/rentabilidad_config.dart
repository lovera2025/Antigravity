class RentabilidadConfig {
  final String id;
  final double alquilerLocal;
  final double sueldosAdmin;
  final double serviciosOficina;
  final double impuestosFijos;
  final double honorarioAdrianDefaultMonto;
  final double honorarioAdrianDefaultPct;
  final String honorarioModoDefault;
  final int eventosEstimadosMes;
  final DateTime? updatedAt;
  final String? updatedBy;

  const RentabilidadConfig({
    required this.id,
    this.alquilerLocal = 0.0,
    this.sueldosAdmin = 0.0,
    this.serviciosOficina = 0.0,
    this.impuestosFijos = 0.0,
    this.honorarioAdrianDefaultMonto = 0.0,
    this.honorarioAdrianDefaultPct = 0.0,
    this.honorarioModoDefault = 'monto',
    this.eventosEstimadosMes = 1,
    this.updatedAt,
    this.updatedBy,
  });

  /// Costo fijo total mensual
  double get totalCostosFijosMensuales {
    return alquilerLocal + sueldosAdmin + serviciosOficina + impuestosFijos;
  }

  /// Costo fijo prorrateado por evento
  double get costoFijoPorEvento {
    if (eventosEstimadosMes <= 0) return 0.0;
    return totalCostosFijosMensuales / eventosEstimadosMes;
  }

  factory RentabilidadConfig.fromJson(Map<String, dynamic> json) {
    return RentabilidadConfig(
      id: json['id'] as String,
      alquilerLocal: (json['alquiler_local'] as num?)?.toDouble() ?? 0.0,
      sueldosAdmin: (json['sueldos_admin'] as num?)?.toDouble() ?? 0.0,
      serviciosOficina: (json['servicios_oficina'] as num?)?.toDouble() ?? 0.0,
      impuestosFijos: (json['impuestos_fijos'] as num?)?.toDouble() ?? 0.0,
      honorarioAdrianDefaultMonto: (json['honorario_adrian_default_monto'] as num?)?.toDouble() ?? 0.0,
      honorarioAdrianDefaultPct: (json['honorario_adrian_default_pct'] as num?)?.toDouble() ?? 0.0,
      honorarioModoDefault: json['honorario_modo_default'] as String? ?? 'monto',
      eventosEstimadosMes: (json['eventos_estimados_mes'] as num?)?.toInt() ?? 1,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
      updatedBy: json['updated_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'alquiler_local': alquilerLocal,
      'sueldos_admin': sueldosAdmin,
      'servicios_oficina': serviciosOficina,
      'impuestos_fijos': impuestosFijos,
      'honorario_adrian_default_monto': honorarioAdrianDefaultMonto,
      'honorario_adrian_default_pct': honorarioAdrianDefaultPct,
      'honorario_modo_default': honorarioModoDefault,
      'eventos_estimados_mes': eventosEstimadosMes,
      'updated_at': updatedAt?.toIso8601String(),
      'updated_by': updatedBy,
    };
  }

  factory RentabilidadConfig.defaultConfig() {
    return const RentabilidadConfig(
      id: 'default',
    );
  }
}
