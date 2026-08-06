/// Regla única del cierre de caja para decidir en qué bucket cae un movimiento.
///
/// Transferencia es **solo** lo rotulado `'transferencia'`. Todo lo demás —`null`,
/// `''`, `'Efectivo'`, `'Mercado Pago'`— cuenta como efectivo.
///
/// La regla estaba retipeada en cinco lugares (totales del provider, tarjetas,
/// detalle de bucket, resumen por sesión, Finanzas). Vive acá sola porque el
/// aviso previo al cierre, las tarjetas, la lista y los papeles **tienen que dar
/// el mismo número**: si uno de esos lugares clasifica distinto, el papel con el
/// que se cuenta la plata deja de coincidir con la pantalla.
///
/// No "mejorar" la semántica sin cambiar los cinco lugares a la vez: agregar
/// medios nuevos al lado de transferencia mueve plata de un bucket al otro.
bool esTransferenciaCaja(String? medioPago) =>
    (medioPago ?? '').toLowerCase().trim() == 'transferencia';

/// Rótulo normalizado para mostrar. La base guarda `'Efectivo'` y `'efectivo'`
/// según por dónde entró el pago (el modal de cobro capitaliza, el de retiro no),
/// así que sin esto la misma lista mezcla las dos grafías.
String? medioPagoLabel(String? medioPago) {
  final v = (medioPago ?? '').trim();
  if (v.isEmpty) return null;
  return esTransferenciaCaja(v) ? 'Transferencia' : 'Efectivo';
}
