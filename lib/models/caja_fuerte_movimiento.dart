/// Movimiento de «Caja fuerte» (asignaciones y retiros del dueño).
/// SQLite + sincronización con Supabase (`caja_fuerte_movimientos`).
class CajaFuerteMovimiento {
  final String id;
  /// `asignacion` suma al saldo; `retiro` resta.
  final String tipo;
  final double monto;
  final String? nota;
  /// Instante UTC (ISO desde SQLite).
  final DateTime createdAt;

  static const tipoAsignacion = 'asignacion';
  static const tipoRetiro = 'retiro';

  const CajaFuerteMovimiento({
    required this.id,
    required this.tipo,
    required this.monto,
    this.nota,
    required this.createdAt,
  });

  factory CajaFuerteMovimiento.fromJson(Map<String, dynamic> json) {
    final raw = json['created_at']?.toString();
    return CajaFuerteMovimiento(
      id: json['id']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? tipoRetiro,
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      nota: json['nota']?.toString(),
      createdAt: raw != null ? (DateTime.tryParse(raw) ?? DateTime.now().toUtc()) : DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': tipo,
      'monto': monto,
      'nota': nota,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get esAsignacion => tipo == tipoAsignacion;
}
