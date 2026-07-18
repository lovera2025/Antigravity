class SesionCaja {
  final String id;
  final String operadorId;
  final DateTime abiertaAt;
  final DateTime? cerradaAt;
  final double cambioInicial;
  final String? notaApertura;
  final String? etiqueta;
  final double? arqueoCierre;
  final String? notaCierre;
  final String? deviceId;
  final DateTime? lastHeartbeat;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Nombre denormalizado para UI (join local).
  final String? operadorNombre;

  const SesionCaja({
    required this.id,
    required this.operadorId,
    required this.abiertaAt,
    this.cerradaAt,
    required this.cambioInicial,
    this.notaApertura,
    this.etiqueta,
    this.arqueoCierre,
    this.notaCierre,
    this.deviceId,
    this.lastHeartbeat,
    required this.createdAt,
    required this.updatedAt,
    this.operadorNombre,
  });

  bool get estaAbierta => cerradaAt == null;

  factory SesionCaja.fromMap(Map<String, dynamic> m) {
    return SesionCaja(
      id: m['id'] as String,
      operadorId: m['operador_id'] as String,
      abiertaAt:
          DateTime.tryParse(m['abierta_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      cerradaAt: m['cerrada_at'] != null
          ? DateTime.tryParse(m['cerrada_at'].toString())
          : null,
      cambioInicial: (m['cambio_inicial'] as num?)?.toDouble() ?? 0,
      notaApertura: m['nota_apertura'] as String?,
      etiqueta: m['etiqueta'] as String?,
      arqueoCierre: (m['arqueo_cierre'] as num?)?.toDouble(),
      notaCierre: m['nota_cierre'] as String?,
      deviceId: m['device_id'] as String?,
      lastHeartbeat: m['last_heartbeat'] != null
          ? DateTime.tryParse(m['last_heartbeat'].toString())
          : null,
      createdAt:
          DateTime.tryParse(m['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      updatedAt:
          DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      operadorNombre: m['operador_nombre'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'operador_id': operadorId,
    'abierta_at': abiertaAt.toUtc().toIso8601String(),
    'cerrada_at': cerradaAt?.toUtc().toIso8601String(),
    'cambio_inicial': cambioInicial,
    'nota_apertura': notaApertura,
    'etiqueta': etiqueta,
    'arqueo_cierre': arqueoCierre,
    'nota_cierre': notaCierre,
    'device_id': deviceId,
    'last_heartbeat': lastHeartbeat?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSyncPayload() => toMap();

  SesionCaja copyWith({
    DateTime? cerradaAt,
    double? arqueoCierre,
    String? notaCierre,
    DateTime? lastHeartbeat,
    DateTime? updatedAt,
    String? operadorNombre,
    bool clearCerrada = false,
  }) {
    return SesionCaja(
      id: id,
      operadorId: operadorId,
      abiertaAt: abiertaAt,
      cerradaAt: clearCerrada ? null : (cerradaAt ?? this.cerradaAt),
      cambioInicial: cambioInicial,
      notaApertura: notaApertura,
      etiqueta: etiqueta,
      arqueoCierre: arqueoCierre ?? this.arqueoCierre,
      notaCierre: notaCierre ?? this.notaCierre,
      deviceId: deviceId,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      operadorNombre: operadorNombre ?? this.operadorNombre,
    );
  }
}
