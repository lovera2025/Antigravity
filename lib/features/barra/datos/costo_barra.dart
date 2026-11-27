import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// El **precio de lista** de un producto en una fiesta (`barra_costos`, v84): lo que le
/// cobra el proveedor por unidad (una lata, una botella), y **cuánto trae la botella**
/// si se sirve en tragos por cc (audio 77 y WhatsApp del jefe, 26-nov-2026).
///
/// **Solo del jefe** (`ReglasDeLaBarra.veElCostoYLaGanancia`): no viaja por la red del
/// salón, no lo baja una tablet y ninguna pantalla de la cajera, la encargada o el
/// repositor lo lee. Una fila por fiesta y producto, con id fijo
/// ([UuidUtils.barraCostoId]): si el jefe lo cambia desde dos equipos, escriben la misma
/// fila (gana la última). **No se borra.**
class CostoBarra {
  final String id;
  final String eventoId;
  final String productoId;

  /// Lo que se le paga al proveedor por unidad. Null: falta cargarlo; 0: no se le paga
  /// a nadie (la silla).
  final double? precioLista;

  /// Cuántos cc trae la botella (750, 2.250), para los tragos que la usan por cc. Null:
  /// no se sirve por cc.
  final int? contenidoCc;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const CostoBarra({
    required this.id,
    required this.eventoId,
    required this.productoId,
    this.precioLista,
    this.contenidoCc,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// El precio de lista de [productoId] en [eventoId]. Un precio negativo o una botella
  /// de 0 cc no tienen sentido y no se guardan.
  factory CostoBarra.para({
    required String eventoId,
    required String productoId,
    double? precioLista,
    int? contenidoCc,
    required DateTime ahora,
  }) {
    _validar(precioLista, contenidoCc);
    final iso = isoDe(ahora);
    return CostoBarra(
      id: UuidUtils.barraCostoId(eventoId, productoId),
      eventoId: eventoId,
      productoId: productoId,
      precioLista: precioLista,
      contenidoCc: contenidoCc,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  static void _validar(double? lista, int? cc) {
    if (lista != null && (lista.isNaN || lista < 0)) {
      throw ArgumentError.value(lista, 'precioLista', 'no puede ser negativo');
    }
    if (cc != null && cc <= 0) {
      throw ArgumentError.value(cc, 'contenidoCc', 'tiene que ser más que 0');
    }
  }

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  CostoBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      CostoBarra(
        id: id,
        eventoId: eventoId,
        productoId: productoId,
        precioLista: precioLista,
        contenidoCc: contenidoCc,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'producto_id': productoId,
        'precio_lista': precioLista,
        'contenido_cc': contenidoCc,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory CostoBarra.fromMap(Map<String, dynamic> m) => CostoBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        productoId: comoTexto(m['producto_id']),
        precioLista: m['precio_lista'] == null ? null : comoDouble(m['precio_lista']),
        contenidoCc: comoIntONull(m['contenido_cc']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
