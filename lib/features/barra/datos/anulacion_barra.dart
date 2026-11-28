import '../../../core/utils/uuid_utils.dart';
import '../cuentas/silla_de_la_puerta.dart';
import 'lectura_de_filas.dart';
import 'venta_barra.dart';

/// La anulación de una venta de la barra (`barra_anulaciones`, v77). **Solo el jefe
/// anula, y con motivo.** La venta no se toca: queda como se vendió, y esta fila dice
/// que no cuenta. Una por venta, con id fijo ([UuidUtils.barraAnulacionId]): anularla
/// desde la PC y desde la web deja una sola. **Solo se agregan filas.**
///
/// **"¿Volvió el vale?"** (28-nov-2026, decidido por el usuario): quien anula dice si
/// tiene el vale en la mano. Si volvió, el stock vuelve (lo de siempre); si ya se
/// entregó, la plata se anula igual pero **el stock no vuelve** y GANANCIA lo cuenta
/// como perdido. La respuesta va **dentro del motivo**, con [marcaValeNoVolvio] al final
/// (sin SQL ni columnas: como "Reservada para" en la mesa libre). Lo anulado sin la
/// marca (todo lo de antes) cuenta como "volvió". Una versión anterior lee la marca como
/// parte del motivo y devuelve el stock.
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

  /// Lo que va al final del motivo cuando el vale **no** volvió.
  static const marcaValeNoVolvio = '[el vale no volvió]';

  /// Si el vale volvió a la mano de quien anuló: el stock vuelve. Sin la marca, sí.
  bool get valeVolvio => !motivo.trimRight().endsWith(marcaValeNoVolvio);

  /// El motivo que escribió quien anuló, sin la marca: el de la pantalla y el papel.
  String get motivoParaMostrar => sinLaMarca(motivo);

  /// El motivo escrito sin la marca del vale (si alguien la tipeó, también se saca).
  static String sinLaMarca(String motivo) {
    var m = motivo.trim();
    while (m.endsWith(marcaValeNoVolvio)) {
      m = m.substring(0, m.length - marcaValeNoVolvio.length).trimRight();
    }
    return m;
  }

  /// Si al anular [venta] hay que preguntar por el vale: solo si lleva algo que cuenta
  /// en el stock. **Una venta de solo sillas de la noche no pregunta**: el vale de la
  /// silla lo tiene la recepcionista, y la silla queda en rojo en la puerta igual.
  static bool preguntaPorElVale(VentaBarra venta) =>
      venta.renglones.any((r) => !esSillaDeLaPuerta(r.nombre));

  /// La anulación de [venta]. Sin motivo no se anula (la marca sola no es un motivo).
  /// [valeVolvio] en false deja la marca al final del motivo.
  factory AnulacionBarra.de(
    VentaBarra venta, {
    required String motivo,
    bool valeVolvio = true,
    String? hechoPor,
    String? deviceId,
    required DateTime ahora,
  }) {
    final escrito = sinLaMarca(motivo);
    if (escrito.isEmpty) {
      throw ArgumentError.value(motivo, 'motivo', 'anular lleva motivo');
    }
    final m = valeVolvio ? escrito : '$escrito $marcaValeNoVolvio';
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
