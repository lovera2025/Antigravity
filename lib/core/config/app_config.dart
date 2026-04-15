class AppConfig {
  /// Umbral de deuda para disparar alertas de gestión de cobro.
  /// Se establece en 0.01 para detectar cualquier saldo pendiente mínimo.
  static const double umbralDeuda = 0.01;

  /// Título profesional para las notificaciones de deuda.
  static const String tituloGestionCobro = 'Aviso de Gestión de Cobro';

  /// Mensaje corporativo base para el dashboard.
  static const String mensajeDeudaDashboard = 'Gestión de Cobros: Se han detectado eventos con saldos de clientes pendientes de cobro.';
}
