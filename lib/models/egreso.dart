/// Prefijos técnicos en [Egreso.proveedor]: marcan de qué bolsa salió un gasto
/// personal. Viven acá —y no en el helper— para que [Egreso.proveedorVisible]
/// pueda limpiarlos sin importar nada de `features/`.
const String kPrefijoGastoPersonalEmpresa = '[empresa]';
const String kPrefijoGastoPersonalPendiente = '[pendiente]';

class Egreso {
  final String id;
  final String eventoId;
  final double monto;
  final String? proveedor;
  final String? categoria;
  final DateTime? fecha;
  final String? createdBy;
  final String? medioPago;
  final String? sesionCajaId;

  Egreso({
    required this.id,
    required this.eventoId,
    required this.monto,
    this.proveedor,
    this.categoria,
    this.fecha,
    this.createdBy,
    this.medioPago,
    this.sesionCajaId,
  });

  /// Concepto tal como lo tiene que leer una persona, sin el prefijo técnico.
  ///
  /// Usar SIEMPRE esto para mostrar o imprimir. [proveedor] guarda el prefijo
  /// (`[pendiente]` / `[empresa]`), que solo le sirve a la clasificación de
  /// bolsa: se filtró a 12 pantallas y a 4 celdas del cierre de caja impreso,
  /// donde `[pendiente] Supermercado` se lee como "falta pagarlo" cuando
  /// significa exactamente lo contrario — ya se pagó, del bolsillo del dueño.
  /// Devuelve `null` cuando no queda nada que mostrar, para que cada pantalla
  /// conserve su propio respaldo ("Egreso" en el cierre de caja, "Gasto
  /// personal" en el bolsillo) en vez de imponer uno acá.
  String? get proveedorVisible {
    var p = (proveedor ?? '').trim();
    if (p.startsWith(kPrefijoGastoPersonalEmpresa)) {
      p = p.substring(kPrefijoGastoPersonalEmpresa.length).trim();
    } else if (p.startsWith(kPrefijoGastoPersonalPendiente)) {
      p = p.substring(kPrefijoGastoPersonalPendiente.length).trim();
    }
    return p.isEmpty ? null : p;
  }

  /// ISO desde SQLite/Supabase → instante UTC canónico (misma política que ingresos).
  /// La presentación en AR usa [ArTime.toAr] en UI/PDF.
  static DateTime? _parseFechaUtc(dynamic raw) {
    if (raw == null) return null;
    final p = DateTime.tryParse(raw.toString());
    if (p == null) return null;
    return p.isUtc ? p : p.toUtc();
  }

  factory Egreso.fromJson(Map<String, dynamic> json) {
    return Egreso(
      id: json['id']?.toString() ?? '',
      eventoId: json['evento_id']?.toString() ?? '',
      monto: double.tryParse(json['monto']?.toString() ?? '0') ?? 0.0,
      proveedor: json['proveedor'] ?? json['concepto'] ?? 'Gasto sin nombre',
      categoria: json['categoria'] ?? 'Otro',
      fecha:
          _parseFechaUtc(json['fecha']) ?? _parseFechaUtc(json['fecha_pago']),
      createdBy: json['created_by'],
      medioPago: json['medio_pago'],
      sesionCajaId: json['sesion_caja_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'monto': monto,
      'proveedor': proveedor,
      'categoria': categoria,
      'fecha': fecha?.toIso8601String(),
      'medio_pago': medioPago,
      'sesion_caja_id': sesionCajaId,
    };
  }
}
