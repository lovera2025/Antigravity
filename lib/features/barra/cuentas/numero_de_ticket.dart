/// Cómo se nombra un ticket: "Caja 2 · N° 0017", y el QR que lleva, con el id de la
/// venta (único en todos los equipos): sirve para encontrarla y anularla.
abstract final class NumeroDeTicket {
  static const prefijoQr = 'je:barra:';

  static String texto({required int numeroCaja, required int numero}) =>
      'Caja $numeroCaja · N° ${numero.toString().padLeft(4, '0')}';

  static String qr(String ventaId) => '$prefijoQr$ventaId';

  /// El id de la venta que dice un QR leído. Null si no es un QR de la barra.
  static String? ventaDelQr(String leido) {
    final t = leido.trim();
    if (!t.startsWith(prefijoQr)) return null;
    final id = t.substring(prefijoQr.length).toLowerCase();
    final esUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(id);
    return esUuid ? id : null;
  }
}
