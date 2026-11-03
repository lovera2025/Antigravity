import '../datos/venta_barra.dart';
import 'pesos.dart';

/// La cuenta que arma la cajera en VENDER: tocar un producto suma uno, − resta, quitar
/// lo saca y VACIAR empieza de nuevo. **No cambia nunca: cada toque da una cuenta
/// nueva**, así la pantalla y los tests ven siempre lo mismo.
///
/// Cada renglón se queda con el precio que tenía al sumarlo: si en el medio baja otro
/// precio de la nube, lo que la cajera ya anunció no cambia.
class CuentaBarra {
  final List<RenglonVenta> renglones;

  const CuentaBarra([this.renglones = const []]);

  static const vacia = CuentaBarra();

  bool get estaVacia => renglones.isEmpty;

  int get unidades => renglones.fold<int>(0, (s, r) => s + r.cantidad);

  double get total => deCentavos(
        renglones.fold<int>(0, (s, r) => s + centavos(r.precio) * r.cantidad),
      );

  int cantidadDe(String productoId) {
    for (final r in renglones) {
      if (r.productoId == productoId) return r.cantidad;
    }
    return 0;
  }

  /// Uno más. Si ya estaba, en su lugar; si no, al final.
  CuentaBarra sumar({
    required String productoId,
    required String nombre,
    required double precio,
  }) {
    if (cantidadDe(productoId) == 0) {
      return CuentaBarra([
        ...renglones,
        RenglonVenta(productoId: productoId, nombre: nombre, precio: precio, cantidad: 1),
      ]);
    }
    return _cambiar(productoId, 1);
  }

  /// Uno menos. Al llegar a cero, el renglón sale.
  CuentaBarra restar(String productoId) => _cambiar(productoId, -1);

  CuentaBarra quitar(String productoId) => CuentaBarra([
        for (final r in renglones)
          if (r.productoId != productoId) r,
      ]);

  CuentaBarra _cambiar(String productoId, int cuanto) => CuentaBarra([
        for (final r in renglones)
          if (r.productoId != productoId)
            r
          else if (r.cantidad + cuanto > 0)
            RenglonVenta(
              productoId: r.productoId,
              nombre: r.nombre,
              precio: r.precio,
              cantidad: r.cantidad + cuanto,
            ),
      ]);
}
