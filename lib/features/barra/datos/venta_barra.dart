import 'dart:convert';

import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// Cómo se pagó una venta de la barra.
enum MedioBarra {
  efectivo,
  transferencia,

  /// Parte en efectivo y parte por transferencia.
  mixto,

  /// Un medio que esta versión no conoce (lo escribió una más nueva). Se cuenta por
  /// sus montos de efectivo y transferencia, que siempre están.
  otro;

  static MedioBarra deTexto(Object? v) => MedioBarra.values.firstWhere(
        (m) => m != MedioBarra.otro && m.name == v,
        orElse: () => MedioBarra.otro,
      );
}

/// Un renglón del ticket: el producto **con el nombre y el precio de ese momento**.
/// Si después el jefe le cambia el precio, la venta vieja sigue diciendo lo que se
/// cobró.
class RenglonVenta {
  final String productoId;
  final String nombre;
  final double precio;
  final int cantidad;

  const RenglonVenta({
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.cantidad,
  });

  double get subtotal => precio * cantidad;

  Map<String, dynamic> toJson() => {
        'producto_id': productoId,
        'nombre': nombre,
        'precio': precio,
        'cantidad': cantidad,
      };

  factory RenglonVenta.fromJson(Map<String, dynamic> m) => RenglonVenta(
        productoId: comoTexto(m['producto_id']),
        nombre: comoTexto(m['nombre']),
        precio: comoDouble(m['precio']),
        cantidad: comoInt(m['cantidad']),
      );

  @override
  bool operator ==(Object other) =>
      other is RenglonVenta &&
      other.productoId == productoId &&
      other.nombre == nombre &&
      other.precio == precio &&
      other.cantidad == cantidad;

  @override
  int get hashCode => Object.hash(productoId, nombre, precio, cantidad);
}

/// Una venta de la barra (`barra_ventas`, v77). **Nunca se edita ni se borra:**
/// anularla es una fila nueva en `barra_anulaciones`, que hace el jefe. Así la tablet
/// nunca pisa una anulación hecha desde la PC.
class VentaBarra {
  final String id;
  final String cajaBarraId;
  final String eventoId;

  /// Correlativo dentro de su caja: "Caja 2 · N° 0017".
  final int numero;
  final List<RenglonVenta> renglones;
  final double total;
  final MedioBarra medio;

  /// Lo que se cobró en efectivo y por transferencia. Suman el [total].
  final double efectivo;
  final double transferencia;

  /// Lo que entregó en efectivo, si pagó en efectivo. Null: no se anotó.
  final double? recibe;
  final double vuelto;

  /// La cajera tildó que vio el comprobante de la transferencia.
  final bool comprobanteVisto;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const VentaBarra({
    required this.id,
    required this.cajaBarraId,
    required this.eventoId,
    required this.numero,
    required this.renglones,
    required this.total,
    required this.medio,
    this.efectivo = 0,
    this.transferencia = 0,
    this.recibe,
    this.vuelto = 0,
    this.comprobanteVisto = false,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Una venta nueva, con su número. **Tiene que cerrar**: el total es la suma de los
  /// renglones, el efectivo más la transferencia dan el total, el vuelto es lo que
  /// sobra de lo recibido, y una transferencia lleva el comprobante visto. Si no
  /// cierra es un error del programa, y la venta no se arma.
  factory VentaBarra.nueva({
    required String cajaBarraId,
    required String eventoId,
    required int numero,
    required List<RenglonVenta> renglones,
    required MedioBarra medio,
    double efectivo = 0,
    double transferencia = 0,
    double? recibe,
    bool comprobanteVisto = false,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    int centavos(double v) => (v * 100).round();
    Never no(String por) => throw ArgumentError('la venta no cierra: $por');

    if (numero < 1) no('el número va de 1 en adelante');
    if (renglones.isEmpty) no('no tiene renglones');
    for (final r in renglones) {
      if (r.cantidad < 1) no('${r.nombre} tiene cantidad ${r.cantidad}');
      if (r.precio.isNaN || r.precio < 0) no('${r.nombre} tiene precio ${r.precio}');
    }
    final total = renglones.fold<double>(0, (s, r) => s + r.subtotal);
    if (efectivo.isNaN || efectivo < 0) no('efectivo negativo');
    if (transferencia.isNaN || transferencia < 0) no('transferencia negativa');
    if (centavos(efectivo) + centavos(transferencia) != centavos(total)) {
      no('efectivo $efectivo + transferencia $transferencia no da el total $total');
    }
    switch (medio) {
      case MedioBarra.efectivo:
        if (centavos(transferencia) != 0) no('en efectivo no va transferencia');
      case MedioBarra.transferencia:
        if (centavos(efectivo) != 0) no('por transferencia no va efectivo');
      case MedioBarra.mixto:
        if (centavos(efectivo) == 0 || centavos(transferencia) == 0) {
          no('un mixto lleva las dos partes');
        }
      case MedioBarra.otro:
        no('el medio de pago no se conoce');
    }
    if (centavos(transferencia) > 0 && !comprobanteVisto) {
      no('la transferencia lleva el comprobante visto');
    }
    double vuelto = 0;
    if (recibe != null) {
      if (recibe.isNaN || centavos(recibe) < centavos(efectivo)) {
        no('recibe $recibe es menos que el efectivo $efectivo');
      }
      vuelto = (centavos(recibe) - centavos(efectivo)) / 100;
    }
    final iso = isoDe(ahora);
    return VentaBarra(
      id: UuidUtils.generate(),
      cajaBarraId: cajaBarraId,
      eventoId: eventoId,
      numero: numero,
      renglones: List.unmodifiable(renglones),
      total: centavos(total) / 100,
      medio: medio,
      efectivo: efectivo,
      transferencia: transferencia,
      recibe: recibe,
      vuelto: vuelto,
      comprobanteVisto: comprobanteVisto,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  int get unidades => renglones.fold(0, (s, r) => s + r.cantidad);

  Map<String, dynamic> toMap() => {
        'id': id,
        'caja_barra_id': cajaBarraId,
        'evento_id': eventoId,
        'numero': numero,
        'renglones': jsonEncode([for (final r in renglones) r.toJson()]),
        'total': total,
        'medio': medio.name,
        'efectivo': efectivo,
        'transferencia': transferencia,
        'recibe': recibe,
        'vuelto': vuelto,
        'comprobante_visto': comprobanteVisto ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Unos renglones ilegibles dejan la venta sin renglones, no frenan la lista: el
  /// total y los montos siguen estando.
  static List<RenglonVenta> _renglonesDe(Object? v) {
    try {
      final lista = v is String ? jsonDecode(v) : v;
      if (lista is! List) return const [];
      return [
        for (final r in lista)
          if (r is Map) RenglonVenta.fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (_) {
      return const [];
    }
  }

  factory VentaBarra.fromMap(Map<String, dynamic> m) => VentaBarra(
        id: comoTexto(m['id']),
        cajaBarraId: comoTexto(m['caja_barra_id']),
        eventoId: comoTexto(m['evento_id']),
        numero: comoInt(m['numero']),
        renglones: _renglonesDe(m['renglones']),
        total: comoDouble(m['total']),
        medio: MedioBarra.deTexto(m['medio']),
        efectivo: comoDouble(m['efectivo']),
        transferencia: comoDouble(m['transferencia']),
        recibe: comoDoubleONull(m['recibe']),
        vuelto: comoDouble(m['vuelto']),
        comprobanteVisto: comoBool(m['comprobante_visto']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
