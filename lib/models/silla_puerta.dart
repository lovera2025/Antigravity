/// Una silla que se sumó la noche de la fiesta, en la puerta (6.4.0).
///
/// Desde que empiezan los sorteos (10-nov) las sillas extra ya no se venden en
/// la oficina: se piden solo esa noche, ya sentados. La recepcionista ve si la
/// familia puede agregar (hasta 2 extra por mesa, también en la adicional), la
/// manda a la caja de la barra, que la cobra como un producto más y le da un
/// vale, y con ese vale anota la silla acá (decisión del jefe, 5-nov). La
/// recepcionista no toca plata.
///
/// **Las filas solo se agregan**: quitar una silla le pone [quitadaAt], quién y
/// el motivo, y la fila queda, tachada. Así nadie puede agarrar la plata y
/// desmarcar sin que quede la huella. No toca `contratos_alumnos`: la cuenta
/// del alumno, el sorteo, las planillas y el plano no cambian.
class SillaPuerta {
  final String id;
  final String eventoId;
  final String contratoAlumnoId;

  /// A qué mesa va (una de las de la familia).
  final int mesa;

  /// Cuántas sillas: hoy siempre una por fila.
  final int cantidad;

  /// El número del vale de la barra con que se pagó.
  final String vale;

  /// Quién la anotó: el puesto del celular o quien opera la PC.
  final String? anotadoPor;
  final String? nota;

  /// Si se quitó: cuándo, quién y por qué. La fila no se borra.
  final DateTime? quitadaAt;
  final String? quitadaPor;
  final String? quitadaMotivo;

  final DateTime createdAt;
  final DateTime updatedAt;

  const SillaPuerta({
    required this.id,
    required this.eventoId,
    required this.contratoAlumnoId,
    required this.mesa,
    this.cantidad = 1,
    required this.vale,
    this.anotadoPor,
    this.nota,
    this.quitadaAt,
    this.quitadaPor,
    this.quitadaMotivo,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get vigente => quitadaAt == null;

  /// La misma silla, quitada: con quién y por qué.
  SillaPuerta quitada({
    required String por,
    required String motivo,
    required DateTime ahora,
  }) =>
      SillaPuerta(
        id: id,
        eventoId: eventoId,
        contratoAlumnoId: contratoAlumnoId,
        mesa: mesa,
        cantidad: cantidad,
        vale: vale,
        anotadoPor: anotadoPor,
        nota: nota,
        quitadaAt: ahora,
        quitadaPor: por,
        quitadaMotivo: motivo,
        createdAt: createdAt,
        updatedAt: ahora,
      );

  factory SillaPuerta.fromMap(Map<String, dynamic> m) {
    int entero(Object? v, int siNo) =>
        v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? siNo;
    DateTime? fecha(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    String? texto(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return SillaPuerta(
      id: m['id'] as String,
      eventoId: m['evento_id'] as String,
      contratoAlumnoId: m['contrato_alumno_id'] as String,
      mesa: entero(m['mesa'], 0),
      cantidad: entero(m['cantidad'], 1),
      vale: texto(m['vale']) ?? '',
      anotadoPor: texto(m['anotado_por']),
      nota: texto(m['nota']),
      quitadaAt: fecha(m['quitada_at']),
      quitadaPor: texto(m['quitada_por']),
      quitadaMotivo: texto(m['quitada_motivo']),
      createdAt:
          fecha(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          fecha(m['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Las columnas de la tabla, en la PC y en la nube.
  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'contrato_alumno_id': contratoAlumnoId,
        'mesa': mesa,
        'cantidad': cantidad,
        'vale': vale,
        'anotado_por': anotadoPor,
        'nota': nota,
        'quitada_at': quitadaAt?.toUtc().toIso8601String(),
        'quitada_por': quitadaPor,
        'quitada_motivo': quitadaMotivo,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
