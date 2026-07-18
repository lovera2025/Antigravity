import '../../../core/utils/ar_time.dart';

enum TipoGuiaCambioMovimiento { reposicion, uso, ajuste }

extension TipoGuiaCambioMovimientoX on TipoGuiaCambioMovimiento {
  String get slug {
    switch (this) {
      case TipoGuiaCambioMovimiento.reposicion:
        return 'reposicion';
      case TipoGuiaCambioMovimiento.uso:
        return 'uso';
      case TipoGuiaCambioMovimiento.ajuste:
        return 'ajuste';
    }
  }

  static TipoGuiaCambioMovimiento fromSlug(String? raw) {
    switch (raw?.trim()) {
      case 'reposicion':
        return TipoGuiaCambioMovimiento.reposicion;
      case 'uso':
        return TipoGuiaCambioMovimiento.uso;
      case 'ajuste':
        return TipoGuiaCambioMovimiento.ajuste;
      default:
        return TipoGuiaCambioMovimiento.uso;
    }
  }

  String get label {
    switch (this) {
      case TipoGuiaCambioMovimiento.reposicion:
        return 'Reposición';
      case TipoGuiaCambioMovimiento.uso:
        return 'Uso';
      case TipoGuiaCambioMovimiento.ajuste:
        return 'Ajuste';
    }
  }
}

/// Movimiento de la guía de cambio (vueltos). No contable; SQLite + sync.
class GuiaCambioMovimiento {
  final String id;

  /// Día calendario AR `yyyy-mm-dd`.
  final String fecha;
  final TipoGuiaCambioMovimiento tipo;
  final double monto;
  final double? saldoAntes;
  final double saldoDespues;
  final String? nota;
  final String? sesionCajaId;
  final DateTime fechaMov;
  final DateTime createdAt;

  const GuiaCambioMovimiento({
    required this.id,
    required this.fecha,
    required this.tipo,
    required this.monto,
    this.saldoAntes,
    required this.saldoDespues,
    this.nota,
    this.sesionCajaId,
    required this.fechaMov,
    required this.createdAt,
  });

  factory GuiaCambioMovimiento.fromMap(Map<String, dynamic> m) {
    final fm = m['fecha_mov']?.toString();
    final ca = m['created_at']?.toString();
    return GuiaCambioMovimiento(
      id: m['id']?.toString() ?? '',
      fecha: m['fecha']?.toString() ?? '',
      tipo: TipoGuiaCambioMovimientoX.fromSlug(m['tipo']?.toString()),
      monto: (m['monto'] as num?)?.toDouble() ?? 0,
      saldoAntes: m['saldo_antes'] != null
          ? (m['saldo_antes'] as num).toDouble()
          : null,
      saldoDespues: (m['saldo_despues'] as num?)?.toDouble() ?? 0,
      nota: m['nota']?.toString(),
      sesionCajaId: m['sesion_caja_id']?.toString(),
      fechaMov: fm != null
          ? (DateTime.tryParse(fm) ?? ArTime.nowUtc())
          : ArTime.nowUtc(),
      createdAt: ca != null
          ? (DateTime.tryParse(ca) ?? ArTime.nowUtc())
          : ArTime.nowUtc(),
    );
  }

  Map<String, dynamic> toSyncPayload(String updatedAtIso) => {
    'id': id,
    'fecha': fecha,
    'tipo': tipo.slug,
    'monto': monto,
    'saldo_antes': saldoAntes,
    'saldo_despues': saldoDespues,
    'nota': nota,
    'sesion_caja_id': sesionCajaId,
    'fecha_mov': fechaMov.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAtIso,
  };
}
