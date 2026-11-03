import '../../../core/utils/uuid_utils.dart';

/// Lo que puede hacer un operador con su PIN. Los nombres son los que ve el jefe
/// en OPERADORES. Nada dice "Caja" a secas: la de cuotas (Cobros) y la de barra
/// son dos cajas distintas.
enum PermisoOperador { cobros, entradas, barra }

/// Los permisos de un operador, ya resueltos.
///
/// **Sin fila, es de Cobros solo**: así siguen los operadores de antes de la 6.3,
/// con su mismo PIN y sin volver a darles nada. **Con fila y todo en cero, no
/// tiene permisos.** Son dos cosas distintas y cada una lleva su test.
class PermisosEfectivos {
  final bool cobros;
  final bool entradas;
  final bool barra;

  const PermisosEfectivos({
    this.cobros = false,
    this.entradas = false,
    this.barra = false,
  });

  /// El operador sin fila.
  static const soloCobros = PermisosEfectivos(cobros: true);

  factory PermisosEfectivos.de(PermisosOperador? fila) =>
      fila?.permisos ?? soloCobros;

  bool tiene(PermisoOperador p) => switch (p) {
        PermisoOperador.cobros => cobros,
        PermisoOperador.entradas => entradas,
        PermisoOperador.barra => barra,
      };

  bool get ninguno => !cobros && !entradas && !barra;

  /// Los que tiene, siempre en el mismo orden.
  List<PermisoOperador> get lista =>
      [for (final p in PermisoOperador.values) if (tiene(p)) p];

  @override
  bool operator ==(Object other) =>
      other is PermisosEfectivos &&
      other.cobros == cobros &&
      other.entradas == entradas &&
      other.barra == barra;

  @override
  int get hashCode => Object.hash(cobros, entradas, barra);
}

/// La fila de `permisos_operador` (v76): una por operador, con id fijo
/// ([UuidUtils.permisosOperadorId]). **Nunca se borra.** Las columnas son
/// exactamente las que suben y bajan (los tests las comparan con el motor de sync
/// y con el SQL de la nube).
///
/// Va en una tabla aparte y no en `operadores_caja`: esa fila se reescribe entera
/// al editar y al bajar, y una PC más vieja la volvería a subir sin la columna.
class PermisosOperador {
  final String id;
  final String operadorId;
  final PermisosEfectivos permisos;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const PermisosOperador({
    required this.id,
    required this.operadorId,
    required this.permisos,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La fila nueva o la que ya había, con [permisos].
  factory PermisosOperador.para({
    required String operadorId,
    required PermisosEfectivos permisos,
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) {
    final iso = ahora.toUtc().toIso8601String();
    return PermisosOperador(
      id: UuidUtils.permisosOperadorId(operadorId),
      operadorId: operadorId,
      permisos: permisos,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt ?? iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'operador_id': operadorId,
        'cobros': permisos.cobros ? 1 : 0,
        'entradas': permisos.entradas ? 1 : 0,
        'barra': permisos.barra ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory PermisosOperador.fromMap(Map<String, dynamic> m) {
    bool prendido(Object? v) => v == 1 || v == true;
    return PermisosOperador(
      id: m['id'] as String,
      operadorId: m['operador_id'] as String,
      permisos: PermisosEfectivos(
        cobros: prendido(m['cobros']),
        entradas: prendido(m['entradas']),
        barra: prendido(m['barra']),
      ),
      hechoPor: m['hecho_por'] as String?,
      deviceId: m['device_id'] as String?,
      createdAt: (m['created_at'] ?? '').toString(),
      updatedAt: (m['updated_at'] ?? '').toString(),
    );
  }
}

/// Un renglón de `permisos_operador_cambios`: quién dio o sacó qué permiso, y
/// cuándo. **Solo se agregan renglones.**
class CambioDePermiso {
  final String id;
  final String operadorId;
  final PermisoOperador permiso;
  final bool dado;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;

  const CambioDePermiso({
    required this.id,
    required this.operadorId,
    required this.permiso,
    required this.dado,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
  });

  /// Lo que cambió entre [antes] y [despues], un renglón por permiso.
  static List<CambioDePermiso> entre({
    required String operadorId,
    required PermisosEfectivos antes,
    required PermisosEfectivos despues,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    final iso = ahora.toUtc().toIso8601String();
    return [
      for (final p in PermisoOperador.values)
        if (antes.tiene(p) != despues.tiene(p))
          CambioDePermiso(
            id: UuidUtils.cambioDePermisoId(operadorId, p.name, iso),
            operadorId: operadorId,
            permiso: p,
            dado: despues.tiene(p),
            hechoPor: hechoPor,
            deviceId: deviceId,
            createdAt: iso,
          ),
    ];
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'operador_id': operadorId,
        'permiso': permiso.name,
        'dado': dado ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': createdAt,
      };
}
