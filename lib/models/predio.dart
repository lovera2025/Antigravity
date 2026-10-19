import 'dart:convert';

import '../features/plano/modelo/armado_salon.dart';
import '../features/plano/modelo/medidas_salon.dart';

DateTime? _fecha(Object? v) => v is String ? DateTime.tryParse(v) : null;
String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

/// Un predio: el espacio de un lugar armado una vez, con nombre ("Buena
/// Vista"), para arrancar otra fiesta desde ahí (6.1.0). Una fila por predio en
/// `predios`, para todas las fiestas.
///
/// Lleva el playón con lo que mide y sus sectores (el escenario, la pista, las
/// barras, el Ingreso), **sin mesas**. Las mesas, los colores, los títulos, las
/// fijadas y la distancia entre mesas son de cada fiesta. Una fiesta que lo
/// elige se lleva una copia: si el predio cambia o se borra, la fiesta no.
///
/// **Borrar no saca la fila**: le pone [borradoAt] y deja de aparecer. Así
/// ninguna PC tiene que borrar filas para enterarse, ni la que estaba apagada.
class Predio {
  final String id;
  final String nombre;

  /// El espacio, en JSON: un `ArmadoSalon` sin mesas, con la clave
  /// `predio@<id>` (`ArmarAMedida.claveDePredio`).
  final String armadoJson;

  /// Las medidas del playón, las mismas que la fiesta ve en Medidas.
  final PlayonReal playon;
  final DateTime? borradoAt;
  final String? hechoPor;
  final DateTime createdAt;
  final DateTime updatedAt;

  Predio({
    required this.id,
    required this.nombre,
    required this.armadoJson,
    required this.playon,
    this.borradoAt,
    this.hechoPor,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get borrado => borradoAt != null;

  /// El espacio guardado, o null si no se puede leer (un JSON roto o sin
  /// hojas). Uno así no se ofrece: no hay de dónde arrancar.
  late final ArmadoSalon? espacioONull = _leerEspacio();

  ArmadoSalon? _leerEspacio() {
    try {
      final crudo = jsonDecode(armadoJson);
      if (crudo is! Map) return null;
      final a = ArmadoSalon.fromJson(Map<String, dynamic>.from(crudo));
      return a.hojas.isEmpty ? null : a;
    } catch (_) {
      return null;
    }
  }

  Predio copyWith({
    String? nombre,
    ArmadoSalon? espacio,
    PlayonReal? playon,
    DateTime? borradoAt,
    String? hechoPor,
    required DateTime ahora,
  }) =>
      Predio(
        id: id,
        nombre: nombre ?? this.nombre,
        armadoJson:
            espacio == null ? armadoJson : jsonEncode(espacio.toJson()),
        playon: playon ?? this.playon,
        borradoAt: borradoAt ?? this.borradoAt,
        hechoPor: hechoPor ?? this.hechoPor,
        createdAt: createdAt,
        updatedAt: ahora,
      );

  /// La fila para SQLite y para la cola. Ninguna columna NOT NULL va vacía:
  /// en la nube una fila rechazada queda trabada en la cola.
  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'armado_json': armadoJson,
        'medidas': jsonEncode({'playon': playon.toMap()}),
        'borrado_at': _iso(borradoAt),
        'hecho_por': hechoPor,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
      };

  /// Lo que no se pueda leer de las medidas queda en las de fábrica: el
  /// espacio dibujado sigue siendo el que manda.
  factory Predio.fromMap(Map<String, dynamic> m) {
    final creado =
        _fecha(m['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    PlayonReal? playon;
    try {
      final medidas = m['medidas'];
      final crudo = medidas is String ? jsonDecode(medidas) : medidas;
      if (crudo is Map) playon = PlayonReal.fromMap(crudo['playon']);
    } catch (_) {
      playon = null;
    }
    return Predio(
      id: m['id'] as String,
      nombre: (m['nombre'] as String?) ?? '',
      armadoJson: (m['armado_json'] as String?) ?? '{}',
      playon: playon ?? PlayonReal.costaSurubi,
      borradoAt: _fecha(m['borrado_at']),
      hechoPor: m['hecho_por'] as String?,
      createdAt: creado,
      updatedAt: _fecha(m['updated_at']) ?? creado,
    );
  }
}
