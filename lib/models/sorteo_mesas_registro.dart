import 'dart:convert';

/// Qué pasó con las mesas de un evento.
enum TipoRegistroSorteo {
  sorteo('sorteo'),
  deshacer('deshacer'),
  restaurar('restaurar');

  final String clave;
  const TipoRegistroSorteo(this.clave);

  static TipoRegistroSorteo? deClave(String? clave) {
    for (final t in values) {
      if (t.clave == clave) return t;
    }
    return null;
  }
}

/// Un renglón del registro de sorteos: quién tocó las mesas, cuándo y cómo
/// quedaron. Solo se agregan renglones; nunca se editan ni se borran.
///
/// Sirve para responder una queja ("está arreglado", "nos cambiaron la mesa"):
/// qué salió en el sorteo y si después alguien cambió algo a mano.
class SorteoMesasRegistro {
  final String id;
  final String eventoId;
  final TipoRegistroSorteo tipo;

  /// Alumno → sus números, como quedaron ("12-14"). En un deshacer, los que
  /// tenía cada uno antes de borrarlos.
  final Map<String, String> resultado;

  final String? hechoPor;
  final DateTime createdAt;

  const SorteoMesasRegistro({
    required this.id,
    required this.eventoId,
    required this.tipo,
    required this.resultado,
    this.hechoPor,
    required this.createdAt,
  });

  int get alumnos => resultado.length;

  factory SorteoMesasRegistro.fromMap(Map<String, dynamic> map) {
    final crudo = map['resultado'];
    final resultado = <String, String>{};
    try {
      final decodificado = crudo is String ? jsonDecode(crudo) : crudo;
      if (decodificado is Map) {
        for (final e in decodificado.entries) {
          resultado[e.key.toString()] = e.value?.toString() ?? '';
        }
      }
    } catch (_) {
      // Un resultado que no se lee queda vacío: el renglón sigue diciendo
      // quién y cuándo, que es lo que no se puede perder.
    }
    return SorteoMesasRegistro(
      id: map['id'] as String? ?? '',
      eventoId: map['evento_id'] as String,
      tipo: TipoRegistroSorteo.deClave(map['tipo'] as String?) ??
          TipoRegistroSorteo.sorteo,
      resultado: resultado,
      hechoPor: map['hecho_por'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// La fila para SQLite y para la cola. `resultado` viaja como texto JSON: en
  /// la nube la columna es `text`, no `jsonb`, para que llegue y vuelva igual.
  Map<String, dynamic> toMap() {
    final iso = createdAt.toUtc().toIso8601String();
    return {
      'id': id,
      'evento_id': eventoId,
      'tipo': tipo.clave,
      'resultado': jsonEncode(resultado),
      'alumnos': alumnos,
      'hecho_por': hechoPor,
      'created_at': iso,
      'updated_at': iso,
    };
  }
}
