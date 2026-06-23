import 'dart:convert';

/// Estado de una mesa extra individual dentro de un contrato masivo.
class MesaExtraItem {
  final int n;
  final double precio;
  final double pagado;
  final int cuotasPagadas;
  final bool liquidada;

  const MesaExtraItem({
    required this.n,
    required this.precio,
    this.pagado = 0.0,
    this.cuotasPagadas = 0,
    this.liquidada = false,
  });

  double get deuda =>
      liquidada ? 0.0 : (precio - pagado).clamp(0.0, double.infinity);

  bool get activa => !liquidada && deuda > 0.01;

  double cuotaPura(int cuotasPlan) {
    if (cuotasPlan <= 0) return precio;
    return double.parse((precio / cuotasPlan).toStringAsFixed(2));
  }

  int cuotasRestantes(int cuotasPlan) =>
      (cuotasPlan - cuotasPagadas).clamp(0, cuotasPlan);

  MesaExtraItem copyWith({
    int? n,
    double? precio,
    double? pagado,
    int? cuotasPagadas,
    bool? liquidada,
  }) {
    return MesaExtraItem(
      n: n ?? this.n,
      precio: precio ?? this.precio,
      pagado: pagado ?? this.pagado,
      cuotasPagadas: cuotasPagadas ?? this.cuotasPagadas,
      liquidada: liquidada ?? this.liquidada,
    );
  }

  Map<String, dynamic> toJson() => {
        'n': n,
        'precio': precio,
        'pagado': pagado,
        'cuotasPagadas': cuotasPagadas,
        'liquidada': liquidada,
      };

  factory MesaExtraItem.fromJson(Map<String, dynamic> json) {
    final precio = double.parse((json['precio'] ?? 0.0).toString());
    final pagado = double.parse((json['pagado'] ?? 0.0).toString());
    final liquidadaRaw = json['liquidada'];
    final liquidada = liquidadaRaw == true ||
        liquidadaRaw == 1 ||
        (liquidadaRaw != false &&
            liquidadaRaw != 0 &&
            pagado >= precio - 0.01 &&
            precio > 0.01);
    return MesaExtraItem(
      n: (json['n'] as num?)?.toInt() ?? 1,
      precio: precio,
      pagado: pagado,
      cuotasPagadas: (json['cuotasPagadas'] as num?)?.toInt() ??
          (json['cuotas_pagadas'] as num?)?.toInt() ??
          0,
      liquidada: liquidada,
    );
  }

  static List<MesaExtraItem> listFromJson(dynamic raw) {
    if (raw == null) return [];
    List<dynamic> decoded;
    if (raw is List) {
      decoded = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is! List) return [];
        decoded = d;
      } catch (_) {
        return [];
      }
    } else {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map((e) => MesaExtraItem.fromJson(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.n.compareTo(b.n));
  }

  static String encodeList(List<MesaExtraItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  /// Etiqueta para UI / conceptos de pago.
  String label({bool incluirNumeroSiUna = false}) {
    if (incluirNumeroSiUna) return 'Mesa Extra $n';
    return 'Mesa Extra $n';
  }
}
