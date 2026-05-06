class IngresoDetallado {
  final String id;
  final String fuente; // 'Masivo', 'Particular', 'Alquiler'
  /// Instante UTC canónico (ISO desde DB). La vista convierte a hora Argentina al mostrar.
  final DateTime fecha;
  final double monto;
  final String concepto;
  final String alumnoOCliente;
  final String nombreEvento;
  final String? eventoId;
  final String? clienteId;
  /// Cuando [fuente] es Alquiler, enlace al préstamo (pantalla detalle).
  final String? prestamoId;
  final String? medioPago;

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
    this.prestamoId,
    this.medioPago,
  });

  // Utilidad para ordenar
  int compareTo(IngresoDetallado other) {
    // Orden cronológico descendente (más reciente primero)
    return other.fecha.compareTo(fecha);
  }
}
