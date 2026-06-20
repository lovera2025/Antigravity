import '../../../core/utils/ar_time.dart';
import 'turno_caja.dart';

/// Anotación opcional para el PDF de cierre, por día calendario + turno.
class CierreCajaAnotacion {
  final String id;
  final String fecha;
  final TurnoCaja turno;
  final String texto;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CierreCajaAnotacion({
    required this.id,
    required this.fecha,
    required this.turno,
    required this.texto,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CierreCajaAnotacion.fromMap(Map<String, dynamic> m) {
    final ca = m['created_at']?.toString();
    final ua = m['updated_at']?.toString();
    return CierreCajaAnotacion(
      id: m['id']?.toString() ?? '',
      fecha: m['fecha']?.toString() ?? '',
      turno: _turnoFromSlug(m['turno']?.toString()),
      texto: m['texto']?.toString() ?? '',
      createdAt: ca != null
          ? (DateTime.tryParse(ca) ?? ArTime.nowUtc())
          : ArTime.nowUtc(),
      updatedAt: ua != null
          ? (DateTime.tryParse(ua) ?? ArTime.nowUtc())
          : ArTime.nowUtc(),
    );
  }

  static TurnoCaja _turnoFromSlug(String? slug) {
    switch (slug?.trim()) {
      case 'manana':
        return TurnoCaja.manana;
      case 'tarde':
        return TurnoCaja.tarde;
      case 'dia':
        return TurnoCaja.dia;
      default:
        return TurnoCaja.dia;
    }
  }

  Map<String, dynamic> toSyncPayload() => {
        'id': id,
        'fecha': fecha,
        'turno': turno.slug,
        'texto': texto,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
