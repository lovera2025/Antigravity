import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// Cómo se mide un ingrediente de un trago.
enum UnidadDeReceta {
  /// En cc de una botella (fernet, coca, vodka): **no se cuenta en la barra**; sirve para
  /// calcular cuántas botellas se usaron (GANANCIA del jefe).
  cc('cc'),

  /// Entero (una lata de Speed): **baja del stock** de ese producto como si se vendiera
  /// suelto.
  unidad('unidad');

  final String clave;
  const UnidadDeReceta(this.clave);

  /// Una clave que esta versión no conoce se lee como cc: así no baja stock de nada.
  static UnidadDeReceta deClave(String? clave) =>
      values.firstWhere((u) => u.clave == clave, orElse: () => cc);
}

/// Un ingrediente de la receta de un trago en una fiesta (`barra_recetas`, v84): "el
/// Fernet con coca lleva 200 cc de fernet" o "el vodka lleva 1 Speed" (WhatsApp del jefe,
/// 26-nov-2026: "más o menos, para calcularle").
///
/// Una fila por fiesta, trago e ingrediente, con id fijo ([UuidUtils.barraRecetaId]).
/// **No lleva plata**: viaja a las tablets (el Speed del vodka baja su stock), y el
/// precio de lista queda en `barra_costos`, solo del jefe. Sacar un ingrediente es
/// [activo] en false: **no se borra**.
class RecetaBarra {
  final String id;
  final String eventoId;

  /// El trago.
  final String productoId;

  /// Lo que lleva (otro producto del catálogo).
  final String ingredienteId;

  /// Cuánto: cc si [unidad] es cc; unidades si es unidad.
  final int cantidad;
  final UnidadDeReceta unidad;
  final bool activo;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const RecetaBarra({
    required this.id,
    required this.eventoId,
    required this.productoId,
    required this.ingredienteId,
    required this.cantidad,
    required this.unidad,
    this.activo = true,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Un ingrediente de [productoId] en [eventoId]. Un trago no se lleva a sí mismo, y la
  /// cantidad va de 1 en adelante.
  factory RecetaBarra.para({
    required String eventoId,
    required String productoId,
    required String ingredienteId,
    required int cantidad,
    required UnidadDeReceta unidad,
    bool activo = true,
    required DateTime ahora,
  }) {
    if (productoId == ingredienteId) {
      throw ArgumentError.value(ingredienteId, 'ingredienteId', 'un trago no se lleva a sí mismo');
    }
    if (cantidad <= 0) {
      throw ArgumentError.value(cantidad, 'cantidad', 'tiene que ser más que 0');
    }
    final iso = isoDe(ahora);
    return RecetaBarra(
      id: UuidUtils.barraRecetaId(eventoId, productoId, ingredienteId),
      eventoId: eventoId,
      productoId: productoId,
      ingredienteId: ingredienteId,
      cantidad: cantidad,
      unidad: unidad,
      activo: activo,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  RecetaBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      RecetaBarra(
        id: id,
        eventoId: eventoId,
        productoId: productoId,
        ingredienteId: ingredienteId,
        cantidad: cantidad,
        unidad: unidad,
        activo: activo,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'producto_id': productoId,
        'ingrediente_id': ingredienteId,
        'cantidad': cantidad,
        'unidad': unidad.clave,
        'activo': activo ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory RecetaBarra.fromMap(Map<String, dynamic> m) => RecetaBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        productoId: comoTexto(m['producto_id']),
        ingredienteId: comoTexto(m['ingrediente_id']),
        cantidad: comoInt(m['cantidad']),
        unidad: UnidadDeReceta.deClave(comoTextoONull(m['unidad'])),
        activo: comoBool(m['activo']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
