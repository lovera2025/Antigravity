import 'cliente.dart';
import 'servicio.dart';

enum EstadoEvento { planificacion, confirmado, finalizado, cancelado }

class Evento {
  final String id;
  final String clienteId;
  final String tipo;
  final DateTime fechaEvento;
  final EstadoEvento estado;
  final int cantidadCuotas;
  final DateTime? createdAt;
  final String? pinOperador;
  final String modalidad; // 'particular' o 'masivo'
  final String? observaciones;
  /// Homenajeado / motivo del festejo (legacy; preferir [nombreFestejado]).
  final String? tituloFestejado;
  /// Nombre corto del festejado/a (para redacción IA y frases).
  final String? nombreFestejado;
  /// Título grande en PDF y pantalla (opcional; si vacío se compone desde [nombreFestejado]).
  final String? encabezadoEvento;
  /// Porcentaje de bonificación acordado sobre el presupuesto total (persistido en eventos).
  final double? bonificacionGlobalPct;

  /// Presupuesto del que salió este evento al confirmarse.
  ///
  /// Antes el vínculo era un subproducto: las líneas del evento heredan el id de
  /// la línea del presupuesto, así que se podía rastrear cruzando por ahí. Eso
  /// se cae justo cuando hace falta —un evento creado sin ítems no tiene ninguna
  /// fila de la que colgarse—, que es el caso a reparar. Declararlo en el evento
  /// lo hace sobrevivir aunque esté vacío.
  final String? presupuestoId;

  // To hold joined properties when queried
  final Cliente? cliente;
  final List<EventosServicios>? presupuesto;
  final double? presupuestoTotal;
  final double? totalIngresos;
  final double? saldoDeudor;

  Evento({
    required this.id,
    required this.clienteId,
    required this.tipo,
    required this.fechaEvento,
    required this.estado,
    this.cantidadCuotas = 1,
    this.createdAt,
    this.pinOperador,
    this.modalidad = 'particular',
    this.observaciones,
    this.tituloFestejado,
    this.nombreFestejado,
    this.encabezadoEvento,
    this.bonificacionGlobalPct,
    this.presupuestoId,
    this.cliente,
    this.presupuesto,
    this.presupuestoTotal,
    this.totalIngresos,
    this.saldoDeudor,
  });

  factory Evento.fromJson(Map<String, dynamic> json) {
    EstadoEvento parseEstado(String est) {
      switch (est) {
        case 'Confirmado': return EstadoEvento.confirmado;
        case 'Finalizado': return EstadoEvento.finalizado;
        case 'Cancelado': return EstadoEvento.cancelado;
        case 'Planificacion':
        default:
          return EstadoEvento.planificacion;
      }
    }

    return Evento(
      id: json['id'],
      clienteId: json['cliente_id'],
      tipo: json['tipo'],
      fechaEvento: DateTime.parse(json['fecha_evento']),
      estado: parseEstado(json['estado'] ?? 'Planificacion'),
      cantidadCuotas: json['cantidad_cuotas'] ?? 1,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      pinOperador: json['pin_operador'] as String?,
      modalidad: (json['modalidad'] ?? 'particular') as String,
      observaciones: json['observaciones'] as String?,
      tituloFestejado: json['titulo_festejado'] as String?,
      nombreFestejado: json['nombre_festejado'] as String?,
      encabezadoEvento: json['encabezado_evento'] as String?,
      bonificacionGlobalPct: json['bonificacion_global_pct'] != null
          ? double.tryParse(json['bonificacion_global_pct'].toString())
          : null,
      presupuestoId: json['presupuesto_id'] as String?,

      // Attempt to parse joined Vistas/Tables if they exist in the JSON response
      cliente: json['clientes'] != null ? Cliente.fromJson(json['clientes']) : null,
      presupuestoTotal: json['vista_saldos_eventos']?['presupuesto_total'] != null 
          ? double.parse(json['vista_saldos_eventos']['presupuesto_total'].toString()) : null,
      totalIngresos: json['vista_saldos_eventos']?['total_ingresos'] != null 
          ? double.parse(json['vista_saldos_eventos']['total_ingresos'].toString()) : null,
      saldoDeudor: json['vista_saldos_eventos']?['saldo_deudor'] != null 
          ? double.parse(json['vista_saldos_eventos']['saldo_deudor'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    String formatEstado(EstadoEvento est) {
      switch (est) {
        case EstadoEvento.confirmado: return 'Confirmado';
        case EstadoEvento.finalizado: return 'Finalizado';
        case EstadoEvento.cancelado: return 'Cancelado';
        case EstadoEvento.planificacion: return 'Planificacion';
      }
    }

    return {
      'id': id,
      'cliente_id': clienteId,
      'tipo': tipo,
      'fecha_evento': "${fechaEvento.year}-${fechaEvento.month.toString().padLeft(2, '0')}-${fechaEvento.day.toString().padLeft(2, '0')}",
      'estado': formatEstado(estado),
      'cantidad_cuotas': cantidadCuotas,
      'modalidad': modalidad,
      if (pinOperador != null) 'pin_operador': pinOperador,
      if (observaciones != null) 'observaciones': observaciones,
      if (tituloFestejado != null) 'titulo_festejado': tituloFestejado,
      if (nombreFestejado != null) 'nombre_festejado': nombreFestejado,
      if (encabezadoEvento != null) 'encabezado_evento': encabezadoEvento,
      if (bonificacionGlobalPct != null) 'bonificacion_global_pct': bonificacionGlobalPct,
      if (presupuestoId != null) 'presupuesto_id': presupuestoId,
    };
  }

  /// Tipo listo para mostrar en UI: reemplaza _ por espacio (ej. 15_años → 15 años).
  String get tipoParaMostrar => Evento.formatearTipo(tipo);

  /// Formatea el tipo de evento para mostrar: sin guión bajo, con ñ correcta.
  static String formatearTipo(String? tipo) {
    if (tipo == null || tipo.isEmpty) return '';
    String t = tipo.replaceAll('_', ' ').trim();
    if (t.toLowerCase() == '15 años') {
      return '15 Años';
    }
    return t;
  }

  /// Normaliza para comparaciones (histórico, filtros): minúsculas, _ → espacio.
  static String normalizarTipo(String? tipo) {
    if (tipo == null || tipo.isEmpty) return '';
    return tipo.replaceAll('_', ' ').trim().toLowerCase();
  }

  String get iconoPath {
    switch (Evento.normalizarTipo(tipo)) {
      case 'bautismo':
        return 'assets/icons/3.png';
      case '15 años':
        return 'assets/icons/2.png';
      case 'boda':
        return 'assets/icons/nombre1.png';
      default:
        return 'assets/icons/LOGO 01.png'; // Fallback a un logo genérico
    }
  }
}

class EventosServicios {
  /// Fila lógica; permite el mismo [servicioId] varias veces en un evento.
  final String id;
  final String eventoId;
  final String servicioId;
  final double precioFinalAcordado;
  final double cantidad;
  final String? grupo;
  /// Orden dentro del combo (0 = primero: lleva el precio total del bloque en PDF/panel).
  final int comboOrden;
  final bool esExtra;
  final String? detalleServicio;

  
  final Servicio? servicio;

  EventosServicios({
    required this.id,
    required this.eventoId,
    required this.servicioId,
    required this.precioFinalAcordado,
    this.cantidad = 1.0,
    this.grupo,
    this.comboOrden = 0,
    this.esExtra = false,
    this.detalleServicio,
    this.servicio,
  });

  factory EventosServicios.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    if (idRaw == null || (idRaw is String && idRaw.length != 36)) {
      throw FormatException('eventos_servicios: falta id (línea) de 36 caracteres');
    }
    return EventosServicios(
      id: idRaw as String,
      eventoId: json['evento_id'] as String,
      servicioId: json['servicio_id'] as String,
      precioFinalAcordado: double.parse(json['precio_final_acordado'].toString()),
      cantidad: json['cantidad'] != null ? double.parse(json['cantidad'].toString()) : 1.0,
      grupo: json['grupo'] as String?,
      comboOrden: (json['combo_orden'] as num?)?.toInt() ?? 0,
      esExtra: (json['es_extra'] ?? 0) == 1 || json['es_extra'] == true,
      detalleServicio: json['detalle_servicio'] as String?,
      servicio: json['servicios'] != null ? Servicio.fromJson(json['servicios'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'servicio_id': servicioId,
      'precio_final_acordado': precioFinalAcordado,
      'cantidad': cantidad,
      'grupo': grupo,
      'combo_orden': comboOrden,
      'es_extra': esExtra ? 1 : 0,
      'detalle_servicio': detalleServicio,
    };
  }
}
