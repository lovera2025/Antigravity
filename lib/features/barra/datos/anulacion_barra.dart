import '../../../core/utils/uuid_utils.dart';
import 'lectura_de_filas.dart';
import 'venta_barra.dart';

/// La anulación de una venta de la barra (`barra_anulaciones`, v77). **Solo el jefe
/// anula, y con motivo.** La venta no se toca: queda como se vendió, y esta fila dice
/// que no cuenta. Una por venta, con id fijo ([UuidUtils.barraAnulacionId]): anularla
/// desde la PC y desde la web deja una sola. **Solo se agregan filas.**
class AnulacionBarra {
  final String id;
  final String ventaId;
  final String cajaBarraId;
  final String eventoId;
  final String motivo;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const AnulacionBarra({
    required this.id,
    required this.ventaId,
    required this.cajaBarraId,
    required this.eventoId,
    required this.motivo,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La anulación de [venta]. Sin motivo no se anula.
  factory AnulacionBarra.de(
    VentaBarra venta, {
    required String motivo,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    final m = motivo.trim();
    if (m.isEmpty) {
      throw ArgumentError.value(motivo, 'motivo', 'anular lleva motivo');
    }
    final iso = isoDe(ahora);
    return AnulacionBarra(
      id: UuidUtils.barraAnulacionId(venta.id),
      ventaId: venta.id,
      cajaBarraId: venta.cajaBarraId,
      eventoId: venta.eventoId,
      motivo: m,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'venta_id': ventaId,
        'caja_barra_id': cajaBarraId,
        'evento_id': eventoId,
        'motivo': motivo,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AnulacionBarra.fromMap(Map<String, dynamic> m) => AnulacionBarra(
        id: comoTexto(m['id']),
        ventaId: comoTexto(m['venta_id']),
        cajaBarraId: comoTexto(m['caja_barra_id']),
        eventoId: comoTexto(m['evento_id']),
        motivo: comoTexto(m['motivo']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
