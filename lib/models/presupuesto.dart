import 'cliente.dart';
import 'servicio.dart';

enum EstadoPresupuesto { borrador, enviado, aprobado, rechazado, vencido }

class Presupuesto {
  final String id;
  final String clienteId;
  final String tipoEvento;
  final String? lugar;
  final String? detalleAnclaje;
  final DateTime fechaVencimiento;
  final DateTime? fechaEvento;
  final EstadoPresupuesto estado;
  final String? instagram;
  final String? telefono;
  final String? vendedorNombre;
  final String? tituloFestejado;
  final bool notificadoVencimiento;
  final DateTime createdAt;
  final Cliente? cliente;
  final List<PresupuestoServicio> servicios;

  Presupuesto({
    required this.id,
    required this.clienteId,
    required this.tipoEvento,
    this.lugar,
    this.detalleAnclaje,
    required this.fechaVencimiento,
    this.fechaEvento,
    this.estado = EstadoPresupuesto.enviado,
    this.instagram,
    this.telefono,
    this.vendedorNombre,
    this.tituloFestejado,
    this.notificadoVencimiento = false,
    required this.createdAt,
    this.cliente,
    this.servicios = const [],
  });

  bool get estaVencido => DateTime.now().isAfter(fechaVencimiento) && estado == EstadoPresupuesto.enviado;

  double get total => servicios
      .where((item) => !item.esExtra)
      .fold(0, (sum, item) => sum + (item.precioFinal * item.cantidad));

  static EstadoPresupuesto _mapEstado(String? estadoRaw) {
    if (estadoRaw == null) return EstadoPresupuesto.enviado;
    switch(estadoRaw.toLowerCase()) {
      case 'activo':
        return EstadoPresupuesto.enviado;
      case 'confirmado':
        return EstadoPresupuesto.aprobado;
      default:
        try {
          return EstadoPresupuesto.values.byName(estadoRaw);
        } catch(_) {
          return EstadoPresupuesto.enviado;
        }
    }
  }

  factory Presupuesto.fromJson(Map<String, dynamic> json) {
    return Presupuesto(
      id: json['id'],
      clienteId: json['cliente_id'],
      tipoEvento: json['tipo_evento'],
      lugar: json['lugar'],
      detalleAnclaje: json['detalle_anclaje'],
      fechaVencimiento: json['fecha_vencimiento'] != null 
          ? (DateTime.tryParse(json['fecha_vencimiento'].toString()) ?? DateTime.now().add(const Duration(days: 7)))
          : DateTime.now().add(const Duration(days: 7)),
      fechaEvento: json['fecha_evento'] != null ? DateTime.tryParse(json['fecha_evento'].toString()) : null,
      estado: _mapEstado(json['estado']),
      instagram: json['instagram'],
      telefono: json['telefono'],
      vendedorNombre: json['vendedor_nombre'],
      tituloFestejado: json['titulo_festejado'],
      notificadoVencimiento: (json['notificado_vencimiento'] ?? 0) == 1,
      createdAt: json['created_at'] != null 
          ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      cliente: json['clientes'] != null ? Cliente.fromJson(json['clientes']) : null,
      servicios: json['presupuesto_servicios'] != null
          ? (json['presupuesto_servicios'] as List)
              .map((s) => PresupuestoServicio.fromJson(Map<String, dynamic>.from(s)))
              .toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'tipo_evento': tipoEvento,
      'lugar': lugar,
      'detalle_anclaje': detalleAnclaje,
      'fecha_vencimiento': fechaVencimiento.toIso8601String(),
      if (fechaEvento != null) 'fecha_evento': fechaEvento!.toIso8601String(),
      'estado': estado.name,
      'instagram': instagram,
      'telefono': telefono,
      'vendedor_nombre': vendedorNombre,
      'titulo_festejado': tituloFestejado,
      'notificado_vencimiento': notificadoVencimiento ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class PresupuestoServicio {
  final String id;
  final String presupuestoId;
  final String servicioId;
  final double precioFinal;
  final double cantidad;
  final String? detalleServicio;
  final String? grupo;
  final int comboOrden;
  final bool esExtra;
  final String? categoria;
  final Servicio? servicio;

  String? get nombre => servicio?.nombre;

  PresupuestoServicio({
    required this.id,
    required this.presupuestoId,
    required this.servicioId,
    required this.precioFinal,
    this.cantidad = 1.0,
    this.detalleServicio,
    this.grupo,
    this.comboOrden = 0,
    this.esExtra = false,
    this.categoria,
    this.servicio,
  });

  factory PresupuestoServicio.fromJson(Map<String, dynamic> json) {
    return PresupuestoServicio(
      id: (json['id'] ?? json['presupuesto_id'] ?? json['servicio_id'] ?? '') as String,
      presupuestoId: (json['presupuesto_id'] ?? '').toString(),
      servicioId: (json['servicio_id'] ?? '').toString(),
      precioFinal: double.tryParse(json['precio_final']?.toString() ?? '0') ?? 0.0,
      cantidad: double.tryParse((json['cantidad'] ?? 1.0).toString()) ?? 1.0,
      detalleServicio: json['detalle_servicio'],
      grupo: json['grupo'],
      comboOrden: (json['combo_orden'] as num?)?.toInt() ?? 0,
      esExtra: (json['es_extra'] ?? 0) == 1 || json['es_extra'] == true,
      categoria: json['servicios'] != null ? json['servicios']['categoria'] : null,
      servicio: json['servicios'] != null ? Servicio.fromJson(Map<String, dynamic>.from(json['servicios'])) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'presupuesto_id': presupuestoId,
      'servicio_id': servicioId,
      'precio_final': precioFinal,
      'cantidad': cantidad,
      'detalle_servicio': detalleServicio,
      'grupo': grupo,
      'combo_orden': comboOrden,
      'es_extra': esExtra ? 1 : 0,
    };
  }
}
