import '../../../core/utils/uuid_utils.dart';
import '../../barra/datos/lectura_de_filas.dart';
import 'venta_entradas.dart';

/// La anulación de una venta de entradas (`entradas_anulaciones`, v80). **Solo
/// el jefe anula, y con motivo.** La venta no se toca: queda como se vendió, y
/// esta fila dice que no cuenta. Una por venta, con id fijo
/// ([UuidUtils.entradasAnulacionId]). **Solo se agregan filas.**
///
/// [devueltas] dice si devolvieron las entradas y las pulseras. Si no, los
/// números de esa venta quedan anulados para siempre: no se vuelven a vender
/// ni a entregar.
class AnulacionEntradas {
  final String id;
  final String ventaId;
  final String cajaEntradasId;
  final String eventoId;
  final String motivo;
  final bool devueltas;
  final String? hechoPor;
  final String? deviceId;
  final String createdAt;
  final String updatedAt;

  const AnulacionEntradas({
    required this.id,
    required this.ventaId,
    required this.cajaEntradasId,
    required this.eventoId,
    required this.motivo,
    required this.devueltas,
    this.hechoPor,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// La anulación de [venta]. Sin motivo no se anula.
  factory AnulacionEntradas.de(
    VentaEntradas venta, {
    required String motivo,
    required bool devueltas,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    final m = motivo.trim();
    if (m.isEmpty) {
      throw ArgumentError.value(motivo, 'motivo', 'anular lleva motivo');
    }
    final iso = isoDe(ahora);
    return AnulacionEntradas(
      id: UuidUtils.entradasAnulacionId(venta.id),
      ventaId: venta.id,
      cajaEntradasId: venta.cajaEntradasId,
      eventoId: venta.eventoId,
      motivo: m,
      devueltas: devueltas,
      hechoPor: hechoPor,
      deviceId: deviceId,
      createdAt: iso,
      updatedAt: iso,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'venta_id': ventaId,
        'caja_entradas_id': cajaEntradasId,
        'evento_id': eventoId,
        'motivo': motivo,
        'devueltas': devueltas ? 1 : 0,
        'hecho_por': hechoPor,
        'device_id': deviceId,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory AnulacionEntradas.fromMap(Map<String, dynamic> m) =>
      AnulacionEntradas(
        id: comoTexto(m['id']),
        ventaId: comoTexto(m['venta_id']),
        cajaEntradasId: comoTexto(m['caja_entradas_id']),
        eventoId: comoTexto(m['evento_id']),
        motivo: comoTexto(m['motivo']),
        devueltas: comoBool(m['devueltas']),
        hechoPor: comoTextoONull(m['hecho_por']),
        deviceId: comoTextoONull(m['device_id']),
        createdAt: comoTexto(m['created_at']),
        updatedAt: comoTexto(m['updated_at']),
      );
}
