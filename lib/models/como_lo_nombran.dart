import 'dart:convert';

import '../core/utils/uuid_utils.dart';

/// Cómo nombra el locutor a un acompañante (un lugar de la familia).
class NombreDeAcompanante {
  /// Su lugar en la familia: 1, 2, 3… el mismo de `idInvitadoPuerta`.
  final int lugar;

  /// Cómo estaba cargado cuando se lo nombró ("GÓMEZ, LAURA"; vacío si era un
  /// acompañante sin nombre en la lista).
  final String cargado;

  /// Cómo lo nombran ("Laura", "la abuela Tita").
  final String nombre;

  const NombreDeAcompanante({required this.lugar, required this.cargado, required this.nombre});

  Map<String, Object?> toJson() => {'l': lugar, 'c': cargado, 'n': nombre};

  static NombreDeAcompanante? fromJson(Object? j) {
    if (j is! Map) return null;
    final l = j['l'], c = j['c'], n = j['n'];
    if (l is! int || n is! String || n.trim().isEmpty) return null;
    return NombreDeAcompanante(lugar: l, cargado: c is String ? c : '', nombre: n);
  }

  @override
  bool operator ==(Object other) =>
      other is NombreDeAcompanante && other.lugar == lugar && other.cargado == cargado && other.nombre == nombre;

  @override
  int get hashCode => Object.hash(lugar, cargado, nombre);
}

/// **Cómo nombra el locutor a un egresado y a sus acompañantes** (`como_lo_nombran`,
/// v85, 28-nov-2026; `docs/SPEC_locutor_2026-11-18.md`). La recepcionista lo cambia la
/// noche de la fiesta ("Juani 'el Tano' Pérez" en vez de "PÉREZ, JUAN IGNACIO"); **la
/// ficha de la oficina no cambia** (`contratos_alumnos` ni `invitados`).
///
/// Una fila por alumno, con id fijo ([UuidUtils.comoLoNombranId]). **Nunca se borra:**
/// volver a la lista la deja con [alumno] null y sin acompañantes. Las columnas son
/// exactamente las que suben y bajan.
class ComoLoNombran {
  final String id;
  final String eventoId;
  final String contratoAlumnoId;

  /// Cómo lo nombran al egresado; null = como en la lista.
  final String? alumno;

  /// Cómo estaba cargado el egresado cuando se lo nombró: si la oficina después le
  /// corrige el nombre, lo nombrado no se aplica a ciegas.
  final String? alumnoCargado;

  /// Solo los acompañantes cambiados, por lugar.
  final List<NombreDeAcompanante> acompanantes;

  /// Quién lo cambió: la recepcionista ("Juli") o quien opera la PC.
  final String? cambiadoPor;

  /// Cuándo (ISO, UTC): lo pone la app al guardar. `updated_at` lo pisa la nube.
  final String? cambiadoAt;

  final String createdAt;
  final String updatedAt;

  const ComoLoNombran({
    required this.id,
    required this.eventoId,
    required this.contratoAlumnoId,
    this.alumno,
    this.alumnoCargado,
    this.acompanantes = const [],
    this.cambiadoPor,
    this.cambiadoAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La fila de [contratoAlumnoId] con lo que se guarda ahora.
  factory ComoLoNombran.para({
    required String eventoId,
    required String contratoAlumnoId,
    String? alumno,
    String? alumnoCargado,
    List<NombreDeAcompanante> acompanantes = const [],
    String? cambiadoPor,
    String? createdAt,
    required DateTime ahora,
  }) {
    final iso = ahora.toUtc().toIso8601String();
    return ComoLoNombran(
      id: UuidUtils.comoLoNombranId(contratoAlumnoId),
      eventoId: eventoId,
      contratoAlumnoId: contratoAlumnoId,
      alumno: alumno,
      alumnoCargado: alumnoCargado,
      acompanantes: [...acompanantes]..sort((a, b) => a.lugar.compareTo(b.lugar)),
      cambiadoPor: cambiadoPor,
      cambiadoAt: iso,
      createdAt: createdAt ?? iso,
      updatedAt: iso,
    );
  }

  /// Si no cambia nada (volver a la lista).
  bool get vacia => (alumno == null || alumno!.trim().isEmpty) && acompanantes.isEmpty;

  /// Los acompañantes en JSON, **siempre ordenados por lugar y con las claves en el
  /// mismo orden**: la firma depende de eso.
  String get acompanantesJson =>
      jsonEncode([for (final a in [...acompanantes]..sort((x, y) => x.lugar.compareTo(y.lugar))) a.toJson()]);

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'contrato_alumno_id': contratoAlumnoId,
        'alumno': alumno,
        'alumno_cargado': alumnoCargado,
        'acompanantes': acompanantesJson,
        'cambiado_por': cambiadoPor,
        'cambiado_at': cambiadoAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// Un JSON roto de los acompañantes se lee como ninguno.
  factory ComoLoNombran.fromMap(Map<String, dynamic> m) {
    var acompanantes = <NombreDeAcompanante>[];
    final crudo = m['acompanantes'];
    try {
      final lista = crudo is String ? jsonDecode(crudo) : crudo;
      if (lista is List) {
        acompanantes = [for (final j in lista) ?NombreDeAcompanante.fromJson(j)];
      }
    } catch (_) {}
    String? texto(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
    return ComoLoNombran(
      id: '${m['id']}',
      eventoId: '${m['evento_id']}',
      contratoAlumnoId: '${m['contrato_alumno_id']}',
      alumno: texto(m['alumno']),
      alumnoCargado: texto(m['alumno_cargado']),
      acompanantes: acompanantes..sort((a, b) => a.lugar.compareTo(b.lugar)),
      cambiadoPor: texto(m['cambiado_por']),
      cambiadoAt: texto(m['cambiado_at']),
      createdAt: '${m['created_at'] ?? ''}',
      updatedAt: '${m['updated_at'] ?? ''}',
    );
  }
}
