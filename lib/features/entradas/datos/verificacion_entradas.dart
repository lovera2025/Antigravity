import '../../../core/utils/uuid_utils.dart';
import '../../barra/datos/lectura_de_filas.dart';
import 'venta_entradas.dart';

/// "Pago verificado" de una venta de entradas (`entradas_verificaciones`, v80):
/// el jefe mira su cuenta y tilda que la plata entró. Una fila por venta, con id
/// fijo ([UuidUtils.entradasVerificacionId]); tildar y destildar la actualiza,
/// no se borra.
///
/// **Va aparte para no editar la venta**, que nunca se toca. Queda quién la
/// tildó y cuándo.
class VerificacionEntradas {
  final String id;
  final String ventaId;
  final String eventoId;
  final bool verificado;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const VerificacionEntradas({
    required this.id,
    required this.ventaId,
    required this.eventoId,
    required this.verificado,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La de [venta], tildada o no. [createdAt] es cuándo nació la fila que ya
  /// había: volver a tildar no le cambia esa fecha.
  factory VerificacionEntradas.de(
    VentaEntradas venta, {
    required bool verificado,
    String? hechoPor,
    String? deviceId,
    String? createdAt,
    required DateTime ahora,
  }) {
    final iso = isoDe(ahora);
    return VerificacionEntradas(
      id: UuidUtils.entradasVerificacionId(venta.id),
      ventaId: venta.id,
      eventoId: venta.eventoId,
      verificado: verificado,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: createdAt ?? iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'venta_id': ventaId,
        'evento_id': eventoId,
        'verificado': verificado ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory VerificacionEntradas.fromMap(Map<String, dynamic> m) =>
      VerificacionEntradas(
        id: comoTexto(m['id']),
        ventaId: comoTexto(m['venta_id']),
        eventoId: comoTexto(m['evento_id']),
        verificado: comoBool(m['verificado']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
