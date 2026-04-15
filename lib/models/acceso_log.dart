class AccesoLog {
  final String id;
  final String invitadoId;
  final String eventoId;
  final String dniIngresado;
  final bool valido;
  final String? marcadoPor;
  final String? ipDispositivo;
  final DateTime timestamp;

  AccesoLog({
    required this.id,
    required this.invitadoId,
    required this.eventoId,
    required this.dniIngresado,
    required this.valido,
    this.marcadoPor,
    this.ipDispositivo,
    required this.timestamp,
  });

  factory AccesoLog.fromJson(Map<String, dynamic> json) {
    return AccesoLog(
      id: json['id'] as String,
      invitadoId: json['invitado_id'] as String,
      eventoId: json['evento_id'] as String,
      dniIngresado: json['dni_ingresado'] as String,
      valido: json['valido'] as bool,
      marcadoPor: json['marcado_por'] as String?,
      ipDispositivo: json['ip_dispositivo'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'invitado_id': invitadoId,
      'evento_id': eventoId,
      'dni_ingresado': dniIngresado,
      'valido': valido,
      'marcado_por': marcadoPor,
      'ip_dispositivo': ipDispositivo,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
