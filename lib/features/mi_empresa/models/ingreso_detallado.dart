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
  final String? sesionCajaId;

  /// Solo `fuente == 'Masivo'`: contrato del alumno que pagó.
  ///
  /// Es la clave exacta para agrupar las líneas de un mismo cobro. Sin esto habría
  /// que agrupar por [alumnoOCliente], y dos alumnos homónimos del mismo colegio
  /// —normal en cohortes escolares, donde el nombre es texto libre— terminarían
  /// fusionados en una fila, poniendo la plata de una familia en la de otra.
  final String? contratoAlumnoId;

  /// Solo `fuente == 'Masivo'`: colegio del alumno (`contratos_alumnos.institucion`).
  ///
  /// Es texto libre copiado del cliente del evento masivo al guardar el alumno,
  /// no una entidad con id: puede venir vacío. La vista no dibuja el chip cuando
  /// no hay valor, en vez de inventar un "Sin colegio".
  final String? institucion;

  /// Solo `fuente == 'Masivo'`: `interes_mora` / `cargo_canal_ref` cuando la fila
  /// lo tiene. Clasifica mora y recargo sin adivinar por el texto del concepto.
  ///
  /// `null` en filas previas a la columna: ahí se cae a las heurísticas de
  /// `pago_interes_mora.dart`.
  final String? lineKind;

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
    this.sesionCajaId,
    this.contratoAlumnoId,
    this.institucion,
    this.lineKind,
  });

  // Utilidad para ordenar
  int compareTo(IngresoDetallado other) {
    // Orden cronológico descendente (más reciente primero)
    return other.fecha.compareTo(fecha);
  }
}
