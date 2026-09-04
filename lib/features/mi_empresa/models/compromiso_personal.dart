import '../../../models/egreso.dart';

/// Tipos de cuenta pendiente. El texto se usa tal cual para armar la etiqueta de
/// saldada, así que sumar uno nuevo no obliga a tocar la UI.
const String kTipoCompromisoTrabajo = 'Trabajo';
const String kTipoCompromisoProducto = 'Producto';
const String kTipoCompromisoOtro = 'Otro';

const List<String> kTiposCompromiso = [
  kTipoCompromisoTrabajo,
  kTipoCompromisoProducto,
  kTipoCompromisoOtro,
];

const String kEstadoCompromisoActivo = 'activo';
const String kEstadoCompromisoCancelado = 'cancelado';

/// De dónde salió la plata de un egreso.
///
/// `null` en todo lo histórico, y `null` se comporta igual que `negocio`: la
/// columna es aditiva y ningún saldo viejo cambia al migrar.
const String kOrigenNegocio = 'negocio';
const String kOrigenBolsillo = 'bolsillo';

/// Lo que el negocio le debe a una persona por un trabajo o un producto.
///
/// El saldo **no se guarda**. Se deriva de los egresos que apuntan a esta cuenta
/// (`egresos.compromiso_id`), así que no puede desincronizarse: editar o borrar
/// un pago recalcula solo. Es el mismo criterio que el abonado de los planes.
class CompromisoPersonal {
  final String id;

  /// Nombre tal como se escribe en `egresos.proveedor`. No hay tabla de
  /// personas: la identidad es el texto, canonizado por el autocompletado.
  final String persona;
  final String tipo;
  final String? concepto;
  final double montoTotal;
  final DateTime fechaInicio;

  /// Solo `activo` o `cancelado`. **Saldada no es un estado**: se deriva del
  /// saldo, para que no exista la posibilidad de que la columna diga "pagada"
  /// mientras los pagos dicen otra cosa.
  final String estado;
  final String? nota;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompromisoPersonal({
    required this.id,
    required this.persona,
    required this.tipo,
    required this.montoTotal,
    required this.fechaInicio,
    this.concepto,
    this.estado = kEstadoCompromisoActivo,
    this.nota,
    this.createdAt,
    this.updatedAt,
  });

  bool get estaCancelado => estado.trim() == kEstadoCompromisoCancelado;

  /// Lo que todavía falta pagarle. Nunca negativo: si se pagó de más, es cero.
  double saldo(double pagado) =>
      (montoTotal - pagado).clamp(0, double.infinity).toDouble();

  /// La tolerancia de un centavo cubre el redondeo de los `REAL` de SQLite:
  /// sin ella una cuenta saldada podía quedar debiendo $0,000001 para siempre.
  bool estaSaldado(double pagado) => montoTotal - pagado <= 0.01;

  /// Entre 0 y 1. Con monto total 0 la cuenta ya está cumplida.
  double progreso(double pagado) {
    if (montoTotal <= 0) return 1;
    return (pagado / montoTotal).clamp(0, 1).toDouble();
  }

  /// Se pagó más de lo pactado. No se bloquea —a veces pasa y se arregla
  /// después—, pero conviene poder avisarlo.
  bool huboSobrepago(double pagado) => pagado - montoTotal > 0.01;

  /// 'TRABAJO PAGADO' · 'PRODUCTO PAGADO' · 'SALDADO' para los de tipo Otro,
  /// donde "pagado" a secas quedaría raro.
  String get etiquetaSaldado =>
      tipo.trim() == kTipoCompromisoOtro ? 'SALDADO' : '${tipo.toUpperCase()} PAGADO';

  factory CompromisoPersonal.fromMap(Map<String, dynamic> m) {
    return CompromisoPersonal(
      id: m['id'].toString(),
      persona: (m['persona'] as String?)?.trim() ?? '',
      tipo: (m['tipo'] as String?)?.trim().isNotEmpty == true
          ? (m['tipo'] as String).trim()
          : kTipoCompromisoTrabajo,
      concepto: (m['concepto'] as String?)?.trim(),
      montoTotal: (m['monto_total'] as num?)?.toDouble() ?? 0,
      fechaInicio:
          DateTime.tryParse(m['fecha_inicio']?.toString() ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      estado: (m['estado'] as String?)?.trim().isNotEmpty == true
          ? (m['estado'] as String).trim()
          : kEstadoCompromisoActivo,
      nota: (m['nota'] as String?)?.trim(),
      createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(m['updated_at']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'persona': persona,
        'tipo': tipo,
        'concepto': concepto,
        'monto_total': montoTotal,
        'fecha_inicio': fechaInicio.toUtc().toIso8601String(),
        'estado': estado,
        'nota': nota,
        'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  /// Mismos campos que [toMap]: la tabla no tiene booleanos ni listas, así que
  /// SQLite y Supabase reciben lo mismo.
  Map<String, dynamic> toSyncPayload() => toMap();

  CompromisoPersonal copyWith({
    String? persona,
    String? tipo,
    String? concepto,
    double? montoTotal,
    DateTime? fechaInicio,
    String? estado,
    String? nota,
    DateTime? updatedAt,
  }) {
    return CompromisoPersonal(
      id: id,
      persona: persona ?? this.persona,
      tipo: tipo ?? this.tipo,
      concepto: concepto ?? this.concepto,
      montoTotal: montoTotal ?? this.montoTotal,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      estado: estado ?? this.estado,
      nota: nota ?? this.nota,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Una cuenta con sus pagos ya resueltos, para que la UI no calcule nada.
class CompromisoConSaldo {
  final CompromisoPersonal compromiso;

  /// Suma de los egresos aplicados a esta cuenta, salgan del negocio o del
  /// bolsillo: en los dos casos la persona cobró.
  final double pagado;
  final List<Egreso> pagos;

  const CompromisoConSaldo({
    required this.compromiso,
    required this.pagado,
    this.pagos = const [],
  });

  double get saldo => compromiso.saldo(pagado);
  bool get estaSaldado => compromiso.estaSaldado(pagado);
  double get progreso => compromiso.progreso(pagado);
  bool get huboSobrepago => compromiso.huboSobrepago(pagado);

  /// Sigue debiéndose plata: ni saldada ni cancelada a mano.
  bool get sigueAbierto => !estaSaldado && !compromiso.estaCancelado;
}
