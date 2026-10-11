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

  /// En un sorteo o una restauración: lo que ya tenía cada familia que tenía
  /// mesa (el sorteo no se las mueve, les suma las que faltan). Sirve para
  /// deshacer solo este renglón y devolverle a cada uno lo suyo, también una
  /// mesa cargada a mano que el registro nunca vio.
  ///
  /// `null` si el renglón no lo anotó.
  final Map<String, String>? antes;

  /// En un deshacer de **solo los últimos sorteados**: lo que conserva cada
  /// familia que no quedó sin mesa. Que esté —aunque vacío— es lo que dice que
  /// el deshacer fue parcial; `null` en el que borra a toda la escuela.
  final Map<String, String>? quedan;

  final String? hechoPor;
  final DateTime createdAt;

  const SorteoMesasRegistro({
    required this.id,
    required this.eventoId,
    required this.tipo,
    required this.resultado,
    this.antes,
    this.quedan,
    this.hechoPor,
    required this.createdAt,
  });

  /// [antes] y [quedan] viajan adentro del texto de `resultado`, con estas
  /// claves: el id de un alumno nunca empieza con guion bajo. Así no hace
  /// falta una columna nueva, ni en la base ni en la nube.
  static const claveAntes = '_antes';
  static const claveQuedan = '_quedan';

  int get alumnos => resultado.length;

  /// Deshizo solo a los últimos sorteados, no a toda la escuela.
  bool get esDeshacerDeUltimos =>
      tipo == TipoRegistroSorteo.deshacer && quedan != null;

  static Map<String, String>? _mapa(Object? crudo) {
    if (crudo is! Map) return null;
    return {
      for (final e in crudo.entries) e.key.toString(): e.value?.toString() ?? '',
    };
  }

  factory SorteoMesasRegistro.fromMap(Map<String, dynamic> map) {
    final crudo = map['resultado'];
    final resultado = <String, String>{};
    Map<String, String>? antes;
    Map<String, String>? quedan;
    try {
      final decodificado = crudo is String ? jsonDecode(crudo) : crudo;
      if (decodificado is Map) {
        for (final e in decodificado.entries) {
          final clave = e.key.toString();
          if (clave == claveAntes) {
            antes = _mapa(e.value);
          } else if (clave == claveQuedan) {
            quedan = _mapa(e.value);
          } else if (!clave.startsWith('_')) {
            resultado[clave] = e.value?.toString() ?? '';
          }
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
      antes: antes,
      quedan: quedan,
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
      'resultado': jsonEncode({
        ...resultado,
        claveAntes: ?antes,
        claveQuedan: ?quedan,
      }),
      'alumnos': alumnos,
      'hecho_por': hechoPor,
      'created_at': iso,
      'updated_at': iso,
    };
  }
}
