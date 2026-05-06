import 'dart:convert';
import 'dart:math' as math;

/// Descuento ya confirmado con el botón «Guardar ajuste» (se acumula sobre la misma partida).
class RegistroDescuentoRent {
  final String modoAjuste;
  final double sacarPesos;
  final double sacarPorcentaje;
  final String detalle;
  final double montoDescontado;

  RegistroDescuentoRent({
    required this.modoAjuste,
    this.sacarPesos = 0,
    this.sacarPorcentaje = 0,
    this.detalle = '',
    required this.montoDescontado,
  });

  Map<String, dynamic> toJson() => {
        'modo_ajuste': modoAjuste,
        'sacar_pesos': sacarPesos,
        'sacar_porcentaje': sacarPorcentaje,
        'detalle': detalle,
        'monto_descontado': montoDescontado,
      };

  factory RegistroDescuentoRent.fromJson(Map<String, dynamic> json) {
    return RegistroDescuentoRent(
      modoAjuste: (json['modo_ajuste'] ?? json['modoAjuste'] ?? 'pesos').toString(),
      sacarPesos: (json['sacar_pesos'] as num?)?.toDouble() ?? 0,
      sacarPorcentaje: (json['sacar_porcentaje'] as num?)?.toDouble() ?? 0,
      detalle: json['detalle']?.toString() ?? '',
      montoDescontado: (json['monto_descontado'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Línea de costo en el simulador de rentabilidad.
/// [montoBase] es la referencia cargada; el costo que entra al cálculo es [montoEfectivo]
/// (base menos lo que sacás en $ o %).
class CostoItem {
  String concepto;
  /// Referencia (ej. costo interno desde presupuesto o monto cargado al agregar manual).
  double montoBase;
  /// `'pesos'` | `'porcentaje'`
  String modoAjuste;
  /// Cuánto restás del base en pesos (solo aplica si [modoAjuste] == pesos).
  double sacarPesos;
  /// Cuánto % restás del base (solo aplica si [modoAjuste] == porcentaje).
  double sacarPorcentaje;
  /// Nota libre: a quién o qué aplica el descuento (solo aclaración, no entra al cálculo).
  String detalleAjuste;
  /// Descuentos ya guardados con «Guardar ajuste»; el %/$ pendiente se aplica sobre lo que queda.
  List<RegistroDescuentoRent> registrosDescuento;

  CostoItem({
    required this.concepto,
    this.montoBase = 0,
    this.modoAjuste = 'pesos',
    this.sacarPesos = 0,
    this.sacarPorcentaje = 0,
    this.detalleAjuste = '',
    List<RegistroDescuentoRent>? registrosDescuento,
  }) : registrosDescuento = registrosDescuento ?? [];

  double _basePos() => montoBase < 0 ? 0.0 : montoBase;

  double get _sumaRegistrada =>
      registrosDescuento.fold<double>(0.0, (a, r) => a + r.montoDescontado);

  /// Saldo de base después de los descuentos ya guardados (antes del ajuste pendiente).
  double get baseRestanteTrasRegistros =>
      (_basePos() - _sumaRegistrada).clamp(0.0, double.infinity);

  /// Importe que aún descontarían los campos actuales ($ o %) sobre [baseRestanteTrasRegistros].
  double get montoDescuentoPendiente {
    final rest = baseRestanteTrasRegistros;
    if (modoAjuste == 'porcentaje') {
      return rest * (sacarPorcentaje.clamp(0.0, 100.0) / 100.0);
    }
    return math.min(sacarPesos.clamp(0.0, double.infinity), rest);
  }

  /// Costo neto que usa el motor (CV/CF).
  double get montoEfectivo {
    final rest = baseRestanteTrasRegistros;
    if (modoAjuste == 'porcentaje') {
      final p = sacarPorcentaje.clamp(0.0, 100.0);
      return (rest * (1.0 - p / 100.0)).clamp(0.0, double.infinity);
    }
    final s = sacarPesos.clamp(0.0, double.infinity);
    return (rest - math.min(s, rest)).clamp(0.0, double.infinity);
  }

  /// Alias compatible con código previo y [CalculadorRentabilidadService].
  double get monto => montoEfectivo;

  /// Importe descontado respecto del base (base − neto). Solo informativo.
  double get montoDescuento {
    final base = _basePos();
    final d = base - montoEfectivo;
    return d > 0 ? d : 0.0;
  }

  /// Guarda el descuento pendiente + detalle en la lista y limpia campos para otro ajuste.
  /// Devuelve false si no hay nada que guardar (sin descuento pendiente).
  bool guardarDescuentoPendiente() {
    final pend = montoDescuentoPendiente;
    if (pend < 0.005) return false;
    registrosDescuento.add(RegistroDescuentoRent(
      modoAjuste: modoAjuste,
      sacarPesos: sacarPesos,
      sacarPorcentaje: sacarPorcentaje,
      detalle: detalleAjuste.trim(),
      montoDescontado: pend,
    ));
    sacarPesos = 0;
    sacarPorcentaje = 0;
    detalleAjuste = '';
    return true;
  }

  void quitarUltimoRegistro() {
    if (registrosDescuento.isEmpty) return;
    registrosDescuento.removeLast();
  }

  Map<String, dynamic> toJson() => {
        'concepto': concepto,
        'monto_base': montoBase,
        'modo_ajuste': modoAjuste,
        'sacar_pesos': sacarPesos,
        'sacar_porcentaje': sacarPorcentaje,
        'detalle_ajuste': detalleAjuste,
        'registros_descuento': registrosDescuento.map((r) => r.toJson()).toList(),
        'monto': montoEfectivo,
      };

  factory CostoItem.fromJson(Map<String, dynamic> json) {
    final concepto = json['concepto']?.toString() ?? '';
    final modo = (json['modo_ajuste'] ?? json['modoAjuste'])?.toString() ?? 'pesos';
    final mb = (json['monto_base'] as num?)?.toDouble();
    final sp = (json['sacar_pesos'] as num?)?.toDouble();
    final sc = (json['sacar_porcentaje'] as num?)?.toDouble();
    final det = (json['detalle_ajuste'] ?? json['detalleAjuste'])?.toString() ?? '';
    List<RegistroDescuentoRent> regs = [];
    final rawRegs = json['registros_descuento'];
    if (rawRegs is List) {
      for (final e in rawRegs) {
        if (e is Map) {
          regs.add(RegistroDescuentoRent.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    if (mb != null || json.containsKey('monto_base') || json.containsKey('modo_ajuste') || json.containsKey('sacar_pesos')) {
      return CostoItem(
        concepto: concepto,
        montoBase: mb ?? 0.0,
        modoAjuste: modo == 'porcentaje' ? 'porcentaje' : 'pesos',
        sacarPesos: sp ?? 0.0,
        sacarPorcentaje: sc ?? 0.0,
        detalleAjuste: det,
        registrosDescuento: regs,
      );
    }

    // Legado: solo `monto` → tratamos todo como base sin ajuste.
    final legacy = (json['monto'] as num?)?.toDouble() ?? 0.0;
    return CostoItem(
      concepto: concepto,
      montoBase: legacy,
      modoAjuste: 'pesos',
      sacarPesos: 0,
      sacarPorcentaje: 0,
      detalleAjuste: det,
      registrosDescuento: regs,
    );
  }
}

class CalculoRentabilidad {
  final String id;
  final String? eventoId;
  final String? presupuestoId;
  final double precioVenta;
  final double honorarioAdrianMonto;
  final double honorarioAdrianPct;
  final String honorarioModo; // 'monto' | 'porcentaje'
  final List<CostoItem> costosVariables;
  final List<CostoItem> costosFijos;
  final double? resultado;
  final String? notas;
  final DateTime createdAt;
  final String? createdBy;

  CalculoRentabilidad({
    required this.id,
    this.eventoId,
    this.presupuestoId,
    required this.precioVenta,
    this.honorarioAdrianMonto = 0.0,
    this.honorarioAdrianPct = 0.0,
    this.honorarioModo = 'monto',
    required this.costosVariables,
    required this.costosFijos,
    this.resultado,
    this.notas,
    required this.createdAt,
    this.createdBy,
  });

  factory CalculoRentabilidad.fromJson(Map<String, dynamic> json) {
    List<CostoItem> parseCostos(dynamic source) {
      if (source == null) return [];
      if (source is String) {
        if (source.isEmpty) return [];
        try {
          source = jsonDecode(source);
        } catch (_) {
          return [];
        }
      }
      if (source is List) {
        return source.map((e) => CostoItem.fromJson(Map<String, dynamic>.from(e))).toList();
      }
      return [];
    }

    return CalculoRentabilidad(
      id: json['id'],
      eventoId: json['evento_id'],
      presupuestoId: json['presupuesto_id'],
      precioVenta: (json['precio_venta'] as num?)?.toDouble() ?? 0.0,
      honorarioAdrianMonto: (json['honorario_adrian_monto'] as num?)?.toDouble() ?? 0.0,
      honorarioAdrianPct: (json['honorario_adrian_pct'] as num?)?.toDouble() ?? 0.0,
      honorarioModo: json['honorario_modo'] ?? 'monto',
      costosVariables: parseCostos(json['costos_variables_json']),
      costosFijos: parseCostos(json['costos_fijos_json']),
      resultado: (json['resultado'] as num?)?.toDouble(),
      notas: json['notas'],
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now() : DateTime.now(),
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'evento_id': eventoId,
      'presupuesto_id': presupuestoId,
      'precio_venta': precioVenta,
      'honorario_adrian_monto': honorarioAdrianMonto,
      'honorario_adrian_pct': honorarioAdrianPct,
      'honorario_modo': honorarioModo,
      'costos_variables_json': jsonEncode(costosVariables.map((x) => x.toJson()).toList()),
      'costos_fijos_json': jsonEncode(costosFijos.map((x) => x.toJson()).toList()),
      'resultado': resultado,
      'notas': notas,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }
}
