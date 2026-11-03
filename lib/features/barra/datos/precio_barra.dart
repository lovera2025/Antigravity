import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// El precio de un producto en una fiesta (`barra_precios`, v77), con su stock si el
/// jefe lo controla. **El precio es por fiesta, no por caja.**
///
/// Una fila por producto y fiesta, con id fijo ([UuidUtils.barraPrecioId]): si el jefe
/// lo cambia desde dos PCs, escriben la misma fila. Sacarlo de la lista de esa fiesta
/// es [activo] en false: **no se borra**.
class PrecioBarra {
  final String id;
  final String eventoId;
  final String productoId;
  final double precio;
  final bool activo;
  final int orden;

  /// Cuántas unidades hay para la fiesta. Null: no se controla el stock.
  final int? stockInicial;

  /// Desde cuántas unidades que quedan se avisa. Null: no avisa.
  final int? avisoStock;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const PrecioBarra({
    required this.id,
    required this.eventoId,
    required this.productoId,
    required this.precio,
    this.activo = true,
    this.orden = 0,
    this.stockInicial,
    this.avisoStock,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// El precio de [productoId] en [eventoId]. Un precio negativo o un stock negativo
  /// no tienen sentido y no se guardan.
  factory PrecioBarra.para({
    required String eventoId,
    required String productoId,
    required double precio,
    bool activo = true,
    int orden = 0,
    int? stockInicial,
    int? avisoStock,
    required DateTime ahora,
  }) {
    _validar(precio, stockInicial, avisoStock);
    final iso = isoDe(ahora);
    return PrecioBarra(
      id: UuidUtils.barraPrecioId(eventoId, productoId),
      eventoId: eventoId,
      productoId: productoId,
      precio: precio,
      activo: activo,
      orden: orden,
      stockInicial: stockInicial,
      avisoStock: avisoStock,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  static void _validar(double precio, int? stock, int? aviso) {
    if (precio.isNaN || precio < 0) {
      throw ArgumentError.value(precio, 'precio', 'no puede ser negativo');
    }
    if (stock != null && stock < 0) {
      throw ArgumentError.value(stock, 'stockInicial', 'no puede ser negativo');
    }
    if (aviso != null && aviso < 0) {
      throw ArgumentError.value(aviso, 'avisoStock', 'no puede ser negativo');
    }
  }

  bool get controlaStock => stockInicial != null;

  /// Lo mismo con otro precio, orden o estado. [sinStock] saca el control de stock.
  PrecioBarra conCambios({
    double? precio,
    bool? activo,
    int? orden,
    int? stockInicial,
    int? avisoStock,
    bool sinStock = false,
  }) {
    final p = precio ?? this.precio;
    final s = sinStock ? null : (stockInicial ?? this.stockInicial);
    final a = sinStock ? null : (avisoStock ?? this.avisoStock);
    _validar(p, s, a);
    return PrecioBarra(
      id: id,
      eventoId: eventoId,
      productoId: productoId,
      precio: p,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      stockInicial: s,
      avisoStock: a,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  PrecioBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      PrecioBarra(
        id: id,
        eventoId: eventoId,
        productoId: productoId,
        precio: precio,
        activo: activo,
        orden: orden,
        stockInicial: stockInicial,
        avisoStock: avisoStock,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'producto_id': productoId,
        'precio': precio,
        'activo': activo ? 1 : 0,
        'orden': orden,
        'stock_inicial': stockInicial,
        'aviso_stock': avisoStock,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory PrecioBarra.fromMap(Map<String, dynamic> m) => PrecioBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        productoId: comoTexto(m['producto_id']),
        precio: comoDouble(m['precio']),
        activo: comoBool(m['activo']),
        orden: comoInt(m['orden']),
        stockInicial: comoIntONull(m['stock_inicial']),
        avisoStock: comoIntONull(m['aviso_stock']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
