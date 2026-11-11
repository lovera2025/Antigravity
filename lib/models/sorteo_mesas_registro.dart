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

  /// En un sorteo: alumno → qué tan lejos se pidió (`DistanciaLejos.name`), solo
  /// de los que tildaron "lejos". `null` si no hubo ninguno.
  final Map<String, String>? lejos;

  /// En un sorteo: alumno → las mesas de la zona que eligió el jefe para sus
  /// "lejos" ("45, 46"), 6.5.0. `null` si nadie eligió.
  final Map<String, String>? zonas;

  /// En un sorteo: alumno → las mesas que se agregaron al salón para él, al
  /// fondo, porque llegó después del sorteo ("102, 103"), 6.5.1. `null` si no
  /// se agregó ninguna.
  final Map<String, String>? nuevas;

  /// El renglón no lo hizo el jefe con SORTEO: el programa le dio sola la mesa
  /// a quien pagó después del sorteo (`MesaNuevaSola`, 6.5.1). No cuenta como
  /// "el último sorteo" para saber quién llegó después.
  final bool automatico;

  final String? hechoPor;
  final DateTime createdAt;

  const SorteoMesasRegistro({
    required this.id,
    required this.eventoId,
    required this.tipo,
    required this.resultado,
    this.antes,
    this.quedan,
    this.lejos,
    this.zonas,
    this.nuevas,
    this.automatico = false,
    this.hechoPor,
    required this.createdAt,
  });

  /// [antes] y [quedan] viajan adentro del texto de `resultado`, con estas
  /// claves: el id de un alumno nunca empieza con guion bajo. Así no hace
  /// falta una columna nueva, ni en la base ni en la nube.
  static const claveAntes = '_antes';
  static const claveQuedan = '_quedan';
  static const claveLejos = '_lejos';
  static const claveZonas = '_zonas';
  static const claveNuevas = '_nuevas';
  static const claveAutomatico = '_auto';

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
    Map<String, String>? lejos;
    Map<String, String>? zonas;
    Map<String, String>? nuevas;
    var automatico = false;
    try {
      final decodificado = crudo is String ? jsonDecode(crudo) : crudo;
      if (decodificado is Map) {
        for (final e in decodificado.entries) {
          final clave = e.key.toString();
          if (clave == claveAntes) {
            antes = _mapa(e.value);
          } else if (clave == claveQuedan) {
            quedan = _mapa(e.value);
          } else if (clave == claveLejos) {
            lejos = _mapa(e.value);
          } else if (clave == claveZonas) {
            zonas = _mapa(e.value);
          } else if (clave == claveNuevas) {
            nuevas = _mapa(e.value);
          } else if (clave == claveAutomatico) {
            automatico = e.value == true || e.value == 1 || e.value == '1';
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
      lejos: lejos,
      zonas: zonas,
      nuevas: nuevas,
      automatico: automatico,
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
        claveLejos: ?lejos,
        claveZonas: ?zonas,
        claveNuevas: ?nuevas,
        if (automatico) claveAutomatico: 1,
      }),
      'alumnos': alumnos,
      'hecho_por': hechoPor,
      'created_at': iso,
      'updated_at': iso,
    };
  }
}
