class IngresoDetallado {
  final String id;
  final String fuente; // 'Masivo' o 'Particular'
  final DateTime fecha;
  final double monto;
  final String concepto;
  final String alumnoOCliente;
  final String nombreEvento;
  final String? eventoId;
  final String? clienteId;

  IngresoDetallado({
    required this.id,
    required this.fuente,
    required this.fecha,
    required this.monto,
    required this.concepto,
    required this.alumnoOCliente,
    required this.nombreEvento,
    this.eventoId,
    this.clienteId,
  });

  // Utilidad para ordenar
  int compareTo(IngresoDetallado other) {
    // Orden cronológico descendente (más reciente primero)
    return other.fecha.compareTo(fecha);
  }
}
