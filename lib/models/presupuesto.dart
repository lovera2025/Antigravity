import 'cliente.dart';
import 'servicio.dart';

enum EstadoPresupuesto { activo, vencido, confirmado }

class Presupuesto {
  final String id;
  final String clienteId;
  final String tipoEvento;
  final String? lugar;
  final String? detalleAnclaje;
  final DateTime fechaVencimiento;
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
    this.estado = EstadoPresupuesto.activo,
    this.instagram,
    this.telefono,
    this.vendedorNombre,
    this.tituloFestejado,
    this.notificadoVencimiento = false,
    required this.createdAt,
    this.cliente,
    this.servicios = const [],
  });

  bool get estaVencido => DateTime.now().isAfter(fechaVencimiento) && estado == EstadoPresupuesto.activo;

  double get total => servicios.fold(0, (sum, item) => sum + (item.precioFinal * item.cantidad));

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
      estado: EstadoPresupuesto.values.byName(json['estado'] ?? 'activo'),
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
  final String presupuestoId;
  final String servicioId;
  final double precioFinal;
  final double cantidad;
  final String? detalleServicio;
  final String? grupo;
  final Servicio? servicio;

  String? get nombre => servicio?.nombre;

  PresupuestoServicio({
    required this.presupuestoId,
    required this.servicioId,
    required this.precioFinal,
    this.cantidad = 1.0,
    this.detalleServicio,
    this.grupo,
    this.servicio,
  });

  factory PresupuestoServicio.fromJson(Map<String, dynamic> json) {
    return PresupuestoServicio(
      presupuestoId: (json['presupuesto_id'] ?? '').toString(),
      servicioId: (json['servicio_id'] ?? '').toString(),
      precioFinal: double.tryParse(json['precio_final']?.toString() ?? '0') ?? 0.0,
      cantidad: double.tryParse((json['cantidad'] ?? 1.0).toString()) ?? 1.0,
      detalleServicio: json['detalle_servicio'],
      grupo: json['grupo'],
      servicio: json['servicios'] != null ? Servicio.fromJson(Map<String, dynamic>.from(json['servicios'])) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'presupuesto_id': presupuestoId,
      'servicio_id': servicioId,
      'precio_final': precioFinal,
      'cantidad': cantidad,
      'detalle_servicio': detalleServicio,
      'grupo': grupo,
    };
  }
}
