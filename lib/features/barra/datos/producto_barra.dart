import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// Un producto del catálogo de la barra (`barra_productos`, v77): lo carga el jefe una
/// vez y después le pone precio en cada fiesta ([PrecioBarra]).
///
/// **No se borra nunca:** se da de baja ([activo] en false) y deja de ofrecerse, pero
/// las ventas viejas lo siguen nombrando. Las columnas son exactamente las que suben y
/// bajan (los tests las comparan con el motor de sync y con el SQL de la nube).
class ProductoBarra {
  final String id;
  final String nombre;

  /// Libre, la que escriba el jefe ("Bebidas", "Tragos"). Vacía: sin categoría.
  final String categoria;
  final bool activo;
  final int orden;

  /// La foto, en el depósito `barra` de la nube. Null: sin foto (se muestra la inicial).
  final String? imagenUrl;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const ProductoBarra({
    required this.id,
    required this.nombre,
    this.categoria = '',
    this.activo = true,
    this.orden = 0,
    this.imagenUrl,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Uno nuevo, con su id. El nombre no puede quedar vacío.
  factory ProductoBarra.nuevo({
    required String nombre,
    String categoria = '',
    int orden = 0,
    String? imagenUrl,
    required DateTime ahora,
  }) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      throw ArgumentError.value(nombre, 'nombre', 'un producto necesita nombre');
    }
    final iso = isoDe(ahora);
    return ProductoBarra(
      id: UuidUtils.generate(),
      nombre: limpio,
      categoria: categoria.trim(),
      orden: orden,
      imagenUrl: comoTextoONull(imagenUrl),
      createdAt: iso,
      updatedAt: iso,
    );
  }

  /// Lo mismo con otro nombre, categoría, orden o estado. Dar de baja es
  /// `conCambios(activo: false)`.
  ProductoBarra conCambios({
    String? nombre,
    String? categoria,
    int? orden,
    bool? activo,
  }) {
    final n = nombre?.trim();
    if (n != null && n.isEmpty) {
      throw ArgumentError.value(nombre, 'nombre', 'un producto necesita nombre');
    }
    return ProductoBarra(
      id: id,
      nombre: n ?? this.nombre,
      categoria: categoria?.trim() ?? this.categoria,
      activo: activo ?? this.activo,
      orden: orden ?? this.orden,
      imagenUrl: imagenUrl,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Con otra foto, o sin foto con null.
  ProductoBarra conImagen(String? url) => ProductoBarra(
        id: id,
        nombre: nombre,
        categoria: categoria,
        activo: activo,
        orden: orden,
        imagenUrl: comoTextoONull(url),
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  ProductoBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      ProductoBarra(
        id: id,
        nombre: nombre,
        categoria: categoria,
        activo: activo,
        orden: orden,
        imagenUrl: imagenUrl,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'categoria': categoria,
        'activo': activo ? 1 : 0,
        'orden': orden,
        'imagen_url': imagenUrl,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ProductoBarra.fromMap(Map<String, dynamic> m) => ProductoBarra(
        id: comoTexto(m['id']),
        nombre: comoTexto(m['nombre']),
        categoria: comoTexto(m['categoria']),
        activo: comoBool(m['activo']),
        orden: comoInt(m['orden']),
        imagenUrl: comoTextoONull(m['imagen_url']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
