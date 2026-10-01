import 'dart:convert';

/// Qué se hizo con las mesas de unas familias después del sorteo.
enum TipoMovimientoMesas {
  /// Dos familias con la misma cantidad de mesas cambian de lugar.
  intercambio('intercambio'),

  /// Una familia pasa a mesas libres.
  mover('mover'),

  /// Vuelve atrás un cambio anterior ([MovimientoMesas.deshaceId]).
  deshacer('deshacer');

  final String clave;
  const TipoMovimientoMesas(this.clave);

  /// Uno desconocido (de una versión más nueva) se lee como un movimiento:
  /// igual se aplica lo que dice `despues`, que es lo que importa.
  static TipoMovimientoMesas deClave(String? clave) {
    for (final t in values) {
      if (t.clave == clave) return t;
    }
    return TipoMovimientoMesas.mover;
  }
}

/// Un renglón de `mesas_movimientos`: quién cambió qué mesas, cuándo y por qué.
/// Solo se agregan renglones; deshacer es otro renglón.
class MovimientoMesas {
  final String id;
  final String eventoId;
  final TipoMovimientoMesas tipo;

  /// Alumno → sus números antes y después ("12, 13"). Null: sin mesa.
  final Map<String, String?> antes;
  final Map<String, String?> despues;

  /// Obligatorio: sin motivo no se cambia una mesa.
  final String motivo;
  final String? deshaceId;

  /// Lo que se le avisó a quien hizo el cambio (ya retiró entradas, otra
  /// división...). Queda escrito para después.
  final List<String> avisos;
  final String? hechoPor;
  final DateTime createdAt;

  const MovimientoMesas({
    required this.id,
    required this.eventoId,
    required this.tipo,
    required this.antes,
    required this.despues,
    required this.motivo,
    this.deshaceId,
    this.avisos = const [],
    this.hechoPor,
    required this.createdAt,
  });

  static Map<String, String?> _mapa(Object? crudo) {
    final r = <String, String?>{};
    try {
      final v = crudo is String ? jsonDecode(crudo) : crudo;
      if (v is Map) {
        for (final e in v.entries) {
          r[e.key.toString()] = e.value?.toString();
        }
      }
    } catch (_) {
      // Un renglón con el detalle ilegible igual dice quién, cuándo y por qué.
    }
    return r;
  }

  factory MovimientoMesas.fromMap(Map<String, dynamic> m) {
    final avisos = <String>[];
    try {
      final v = m['avisos'];
      final l = v is String ? jsonDecode(v) : v;
      if (l is List) avisos.addAll(l.map((e) => e.toString()));
    } catch (_) {}
    return MovimientoMesas(
      id: m['id'] as String? ?? '',
      eventoId: m['evento_id'] as String,
      tipo: TipoMovimientoMesas.deClave(m['tipo'] as String?),
      antes: _mapa(m['antes']),
      despues: _mapa(m['despues']),
      motivo: m['motivo'] as String? ?? '',
      deshaceId: m['deshace_id'] as String?,
      avisos: avisos,
      hechoPor: m['hecho_por'] as String?,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() {
    final iso = createdAt.toUtc().toIso8601String();
    return {
      'id': id,
      'evento_id': eventoId,
      'tipo': tipo.clave,
      'antes': jsonEncode(antes),
      'despues': jsonEncode(despues),
      'motivo': motivo,
      'deshace_id': deshaceId,
      'avisos': avisos.isEmpty ? null : jsonEncode(avisos),
      'hecho_por': hechoPor,
      'created_at': iso,
      'updated_at': iso,
    };
  }
}
