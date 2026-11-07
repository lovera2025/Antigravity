import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';

/// El recargo por transferencia de una fiesta (`barra_recargos`, v78). Lo pone el jefe
/// en PRECIOS; **cada cobro de cada caja arranca con este %, y la cajera lo puede
/// cambiar en ese cobro** (decidido el 3-nov). En 0, el recargo arranca apagado.
///
/// Una fila por fiesta, con id fijo ([UuidUtils.barraRecargoId]): si el jefe lo cambia
/// desde la PC y desde la web, escriben la misma fila. No se borra. Las columnas son
/// exactamente las que suben y bajan (los tests las comparan con el motor de sync y con
/// el SQL de la nube).
class RecargoBarra {
  final String id;
  final String eventoId;

  /// El porcentaje sobre lo transferido. 0: sin recargo.
  final double pct;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  /// Más que esto no tiene sentido: es un error de tipeo.
  static const pctMaximo = 100.0;

  const RecargoBarra({
    required this.id,
    required this.eventoId,
    required this.pct,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// El de [eventoId]. Un porcentaje negativo o de más de 100 no se guarda.
  factory RecargoBarra.para({
    required String eventoId,
    required double pct,
    required DateTime ahora,
  }) {
    _validar(pct);
    final iso = isoDe(ahora);
    return RecargoBarra(
      id: UuidUtils.barraRecargoId(eventoId),
      eventoId: eventoId,
      pct: pct,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  static void _validar(double pct) {
    if (pct.isNaN || pct < 0 || pct > pctMaximo) {
      throw ArgumentError.value(pct, 'pct', 'tiene que ir de 0 a ${pctMaximo.toInt()}');
    }
  }

  /// Si el cobro arranca con el recargo prendido.
  bool get prendido => pct > 0;

  RecargoBarra conPct(double pct) {
    _validar(pct);
    return RecargoBarra(
      id: id,
      eventoId: eventoId,
      pct: pct,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Con quién lo guardó, desde qué equipo y cuándo: lo pone el repositorio.
  RecargoBarra sellado({
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) =>
      RecargoBarra(
        id: id,
        eventoId: eventoId,
        pct: pct,
        hechoPor: hechoPor,
        deviceId: deviceId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: isoDe(ahora),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'evento_id': eventoId,
        'recargo_pct': pct,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory RecargoBarra.fromMap(Map<String, dynamic> m) => RecargoBarra(
        id: comoTexto(m['id']),
        eventoId: comoTexto(m['evento_id']),
        pct: comoDouble(m['recargo_pct']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
