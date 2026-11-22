/// Quién emite los recibos: lo que va arriba a la izquierda, al lado del logo,
/// en el "RECIBO DE PAGO" de las cuotas (`PdfService.generarReciboAlumno`) y en
/// los papeles de la venta de entradas, que se arman con su misma forma
/// (22-nov-2026: "hacelo como un recibo tal cual").
///
/// **Un solo lugar:** si cambia un dato del dueño, cambia acá y sale igual en
/// los dos papeles.
class EmisorDelRecibo {
  EmisorDelRecibo._();

  /// En negrita.
  static const nombre = 'Victor Adrián Argüello';

  /// Las tres de abajo van en gris.
  static const cargo = 'Dueño, Junior Eventos';
  static const cuit = 'CUIT 23-32837670-9';
  static const condicion = 'Responsable Inscripto';
}
