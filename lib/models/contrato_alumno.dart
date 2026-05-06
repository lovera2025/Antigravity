import 'dart:convert';

class ContratoAlumno {
  final String id;
  final String eventoId;
  final String nombreAlumno;
  final int cantidadAcompanantes;
  final double montoTotalPactado;
  final double saldoDeudor;
  final String? institucion;
  final int cuotasPagadas;
  final int totalCuotas;
  final List<String> nombresAcompanantes;
  final int diaVencimientoMensual;
  final double mesaExtraPrecio;
  final int mesaExtraCuotas;
  final int mesaExtraCuotasPagadas;
  final int sillasExtraCantidad;
  final int sillasExtraCuotas;
  final double sillasExtraPrecioTotal;
  final int sillasExtraCuotasPagadas;
  final double mesaExtraPagado;
  final double sillasExtraPagado;
  final String? cursoDivision;
  final String? musicaElegida;
  final String? numeroMesa;
  final String? telefono;
  final double porcentajeDescuento;
  final DateTime? createdAt;
  final bool contratoFirmado;
  /// Remanente de mora acordado en cobros parciales (solo SQLite local).
  final double moraPendienteTracked;

  ContratoAlumno({
    required this.id,
    required this.eventoId,
    required this.nombreAlumno,
    required this.cantidadAcompanantes,
    required this.montoTotalPactado,
    required this.saldoDeudor,
    this.institucion,
    this.cuotasPagadas = 0,
    this.totalCuotas = 9,
    this.nombresAcompanantes = const [],
    this.diaVencimientoMensual = 10,
    this.mesaExtraPrecio = 0.0,
    this.mesaExtraCuotas = 1,
    this.mesaExtraCuotasPagadas = 0,
    this.sillasExtraCantidad = 0,
    this.sillasExtraPrecioTotal = 0.0,
    this.sillasExtraCuotas = 1,
    this.sillasExtraCuotasPagadas = 0,
    this.mesaExtraPagado = 0.0,
    this.sillasExtraPagado = 0.0,
    this.cursoDivision,
    this.musicaElegida,
    this.numeroMesa,
    this.telefono,
    this.porcentajeDescuento = 0.0,
    this.createdAt,
    this.contratoFirmado = false,
    this.moraPendienteTracked = 0.0,
  });

  factory ContratoAlumno.fromJson(Map<String, dynamic> json) {
    return ContratoAlumno(
      id: json['id'] as String,
      eventoId: json['evento_id'] as String,
      nombreAlumno: json['nombre_alumno'] as String,
      cantidadAcompanantes: (json['cantidad_acompanantes'] ?? 0) as int,
      montoTotalPactado: double.parse(json['monto_total_pactado'].toString()),
      saldoDeudor: double.parse(json['saldo_deudor'].toString()),
      institucion: json['institucion'] as String?,
      cuotasPagadas: json['cuotas_pagadas'] as int? ?? 0,
      totalCuotas: json['total_cuotas'] as int? ?? 9,
      nombresAcompanantes: () {
        final raw = json['nombres_acompanantes'];
        if (raw is List) {
          return raw.map((e) => e.toString()).toList();
        } else if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) return decoded.map((e) => e.toString()).toList();
          } catch (_) {
            // Fallback para formato toString "[a, b]"
            final clean = raw.trim();
            if (clean.startsWith('[') && clean.endsWith(']')) {
              final inner = clean.substring(1, clean.length - 1).trim();
              if (inner.isEmpty) return <String>[];
              return inner.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
            }
          }
        }
        return <String>[];
      }(),
      diaVencimientoMensual: json['dia_vencimiento_mensual'] as int? ?? 10,
      mesaExtraPrecio: double.parse((json['mesa_extra_precio'] ?? 0.0).toString()),
      mesaExtraCuotas: json['mesa_extra_cuotas'] as int? ?? 1,
      mesaExtraCuotasPagadas: json['mesa_extra_cuotas_pagadas'] as int? ?? 0,
      sillasExtraCantidad: json['sillas_extra_cantidad'] as int? ?? 0,
      sillasExtraCuotas: json['sillas_extra_cuotas'] as int? ?? 1,
      sillasExtraPrecioTotal: double.parse((json['sillas_extra_precio_total'] ?? 0.0).toString()),
      sillasExtraCuotasPagadas: json['sillas_extra_cuotas_pagadas'] as int? ?? 0,
      mesaExtraPagado: double.parse((json['mesa_extra_pagado'] ?? 0.0).toString()),
      sillasExtraPagado: double.parse((json['sillas_extra_pagado'] ?? 0.0).toString()),
      cursoDivision: json['curso_division'] as String?,
      musicaElegida: json['musica_elegida'] as String?,
      numeroMesa: json['numero_mesa'] as String?,
      telefono: json['telefono'] as String?,
      porcentajeDescuento: double.parse((json['porcentaje_descuento'] ?? 0.0).toString()),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      contratoFirmado: (json['contrato_firmado'] == 1 || json['contrato_firmado'] == true),
      moraPendienteTracked: double.parse(
        (json['mora_pendiente_tracked'] ?? 0.0).toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'nombre_alumno': nombreAlumno,
      'cantidad_acompanantes': cantidadAcompanantes,
      'monto_total_pactado': montoTotalPactado,
      'saldo_deudor': saldoDeudor,
      'cuotas_pagadas': cuotasPagadas,
      'total_cuotas': totalCuotas,
      'nombres_acompanantes': nombresAcompanantes,
      'dia_vencimiento_mensual': diaVencimientoMensual,
      'mesa_extra_precio': mesaExtraPrecio,
      'mesa_extra_cuotas': mesaExtraCuotas,
      'mesa_extra_cuotas_pagadas': mesaExtraCuotasPagadas,
      'sillas_extra_cantidad': sillasExtraCantidad,
      'sillas_extra_cuotas': sillasExtraCuotas,
      'sillas_extra_precio_total': sillasExtraPrecioTotal,
      'sillas_extra_cuotas_pagadas': sillasExtraCuotasPagadas,
      'mesa_extra_pagado': mesaExtraPagado,
      'sillas_extra_pagado': sillasExtraPagado,
      if (institucion != null && institucion!.trim().isNotEmpty)
        'institucion': institucion,
      if (cursoDivision != null && cursoDivision!.trim().isNotEmpty)
        'curso_division': cursoDivision,
      if (musicaElegida != null && musicaElegida!.trim().isNotEmpty)
        'musica_elegida': musicaElegida,
      if (numeroMesa != null && numeroMesa!.trim().isNotEmpty)
        'numero_mesa': numeroMesa,
      if (telefono != null && telefono!.trim().isNotEmpty)
        'telefono': telefono,
      'porcentaje_descuento': porcentajeDescuento,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'contrato_firmado': contratoFirmado,
      'mora_pendiente_tracked': moraPendienteTracked,
    };
  }

  ContratoAlumno copyWith({
    String? id,
    String? eventoId,
    String? nombreAlumno,
    int? cantidadAcompanantes,
    double? montoTotalPactado,
    double? saldoDeudor,
    int? cuotasPagadas,
    int? totalCuotas,
    String? institucion,
    List<String>? nombresAcompanantes,
    int? diaVencimientoMensual,
    double? mesaExtraPrecio,
    int? mesaExtraCuotas,
    int? mesaExtraCuotasPagadas,
    int? sillasExtraCantidad,
    int? sillasExtraCuotas,
    double? sillasExtraPrecioTotal,
    int? sillasExtraCuotasPagadas,
    double? mesaExtraPagado,
    double? sillasExtraPagado,
    String? cursoDivision,
    String? musicaElegida,
    String? numeroMesa,
    String? telefono,
    double? porcentajeDescuento,
    DateTime? createdAt,
    bool? contratoFirmado,
    double? moraPendienteTracked,
  }) {
    return ContratoAlumno(
      id: id ?? this.id,
      eventoId: eventoId ?? this.eventoId,
      nombreAlumno: nombreAlumno ?? this.nombreAlumno,
      cantidadAcompanantes: cantidadAcompanantes ?? this.cantidadAcompanantes,
      montoTotalPactado: montoTotalPactado ?? this.montoTotalPactado,
      saldoDeudor: saldoDeudor ?? this.saldoDeudor,
      cuotasPagadas: cuotasPagadas ?? this.cuotasPagadas,
      totalCuotas: totalCuotas ?? this.totalCuotas,
      institucion: institucion ?? this.institucion,
      nombresAcompanantes: nombresAcompanantes ?? this.nombresAcompanantes,
      diaVencimientoMensual: diaVencimientoMensual ?? this.diaVencimientoMensual,
      mesaExtraPrecio: mesaExtraPrecio ?? this.mesaExtraPrecio,
      mesaExtraCuotas: mesaExtraCuotas ?? this.mesaExtraCuotas,
      mesaExtraCuotasPagadas: mesaExtraCuotasPagadas ?? this.mesaExtraCuotasPagadas,
      sillasExtraCantidad: sillasExtraCantidad ?? this.sillasExtraCantidad,
      sillasExtraCuotas: sillasExtraCuotas ?? this.sillasExtraCuotas,
      sillasExtraPrecioTotal: sillasExtraPrecioTotal ?? this.sillasExtraPrecioTotal,
      sillasExtraCuotasPagadas: sillasExtraCuotasPagadas ?? this.sillasExtraCuotasPagadas,
      mesaExtraPagado: mesaExtraPagado ?? this.mesaExtraPagado,
      sillasExtraPagado: sillasExtraPagado ?? this.sillasExtraPagado,
      cursoDivision: cursoDivision ?? this.cursoDivision,
      musicaElegida: musicaElegida ?? this.musicaElegida,
      numeroMesa: numeroMesa ?? this.numeroMesa,
      telefono: telefono ?? this.telefono,
      porcentajeDescuento: porcentajeDescuento ?? this.porcentajeDescuento,
      createdAt: createdAt ?? this.createdAt,
      contratoFirmado: contratoFirmado ?? this.contratoFirmado,
      moraPendienteTracked: moraPendienteTracked ?? this.moraPendienteTracked,
    );
  }
}
