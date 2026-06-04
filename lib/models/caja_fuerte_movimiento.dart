/// Movimiento de «Caja fuerte»: depósitos y retiros del efectivo guardado en el cofre.
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

  static const prefijoNotaPersonal = '[Personal] ';
  static const prefijoNotaNegocio = '[Negocio] ';

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

  CajaFuerteMotivoRetiro? get motivoRetiro {
    if (esAsignacion) return null;
    final n = nota ?? '';
    if (n.startsWith(prefijoNotaPersonal)) return CajaFuerteMotivoRetiro.personal;
    if (n.startsWith(prefijoNotaNegocio)) return CajaFuerteMotivoRetiro.negocio;
    return null;
  }

  /// Texto visible al usuario (sin prefijo de motivo).
  String? get notaDetalle {
    final n = nota?.trim();
    if (n == null || n.isEmpty) return null;
    if (n.startsWith(prefijoNotaPersonal)) {
      final rest = n.substring(prefijoNotaPersonal.length).trim();
      return rest.isEmpty ? null : rest;
    }
    if (n.startsWith(prefijoNotaNegocio)) {
      final rest = n.substring(prefijoNotaNegocio.length).trim();
      return rest.isEmpty ? null : rest;
    }
    return n;
  }

  String get etiquetaMovimiento {
    if (esAsignacion) return 'Depósito en cofre';
    return switch (motivoRetiro) {
      CajaFuerteMotivoRetiro.personal => 'Retiro · gasto personal',
      CajaFuerteMotivoRetiro.negocio => 'Retiro · gasto del negocio',
      null => 'Retiro del cofre',
    };
  }

  static String? empaquetarNotaRetiro(CajaFuerteMotivoRetiro motivo, String? detalle) {
    final pref = motivo == CajaFuerteMotivoRetiro.personal ? prefijoNotaPersonal : prefijoNotaNegocio;
    final d = detalle?.trim();
    if (d == null || d.isEmpty) return pref.trim();
    return '$pref$d';
  }
}

/// Motivo de un retiro desde la caja fuerte física.
enum CajaFuerteMotivoRetiro {
  personal,
  negocio,
}

extension CajaFuerteMotivoRetiroX on CajaFuerteMotivoRetiro {
  String get label {
    switch (this) {
      case CajaFuerteMotivoRetiro.personal:
        return 'Gasto personal';
      case CajaFuerteMotivoRetiro.negocio:
        return 'Gasto del negocio';
    }
  }

  String get hint {
    switch (this) {
      case CajaFuerteMotivoRetiro.personal:
        return 'Ej.: supermercado, nafta propia…';
      case CajaFuerteMotivoRetiro.negocio:
        return 'Ej.: operador, insumos, delivery…';
    }
  }
}
