import '../datos/barra_repositorio.dart';
import 'cierre_de_barra.dart';

/// Cuánto queda de un producto en una fiesta.
class StockDeProducto {
  final String productoId;

  /// Lo que cargó el jefe. Null: no se controla.
  final int? inicial;
  final int? aviso;

  /// Lo vendido que cuenta: sin las ventas anuladas.
  final int vendido;

  const StockDeProducto({
    required this.productoId,
    required this.inicial,
    required this.aviso,
    required this.vendido,
  });

  bool get controla => inicial != null;

  /// Puede dar negativo: **el stock avisa, no frena la venta.**
  int? get queda => inicial == null ? null : inicial! - vendido;

  bool get agotado => controla && queda! <= 0;

  /// Llegó al mínimo que puso el jefe, o se terminó.
  bool get enAviso => controla && (agotado || (aviso != null && queda! <= aviso!));
}

/// El stock de la barra en una fiesta: lo que cargó el jefe menos lo vendido.
///
/// **Sin internet cada equipo descuenta solo lo que vendió él**: las ventas de las otras
/// cajas llegan cuando vuelve el internet. La pantalla lo dice; esta cuenta usa las
/// ventas que tenga el equipo.
abstract final class StockDeLaBarra {
  /// Uno por producto con precio en [eventoId].
  static Map<String, StockDeProducto> de({
    required String eventoId,
    required Iterable<PrecioBarra> precios,
    required Iterable<VentaBarra> ventas,
    required Iterable<AnulacionBarra> anulaciones,
  }) {
    final anuladas = ventasAnuladas(anulaciones);
    final vendido = <String, int>{};
    for (final v in ventas) {
      if (v.eventoId != eventoId || anuladas.contains(v.id)) continue;
      for (final r in v.renglones) {
        vendido[r.productoId] = (vendido[r.productoId] ?? 0) + r.cantidad;
      }
    }
    return {
      for (final p in precios)
        if (p.eventoId == eventoId)
          p.productoId: StockDeProducto(
            productoId: p.productoId,
            inicial: p.stockInicial,
            aviso: p.avisoStock,
            vendido: vendido[p.productoId] ?? 0,
          ),
    };
  }

  /// Para CAJAS del jefe: solo los que se controlan, **los que están en aviso arriba**,
  /// y entre ellos los que tienen menos.
  static List<StockDeProducto> paraElJefe(Map<String, StockDeProducto> stock) =>
      stock.values.where((s) => s.controla).toList()
        ..sort((a, b) {
          if (a.enAviso != b.enAviso) return a.enAviso ? -1 : 1;
          return a.queda!.compareTo(b.queda!);
        });
}

/// Las fiestas que la cajera puede elegir: las que tienen al menos un precio activo.
Set<String> fiestasConPrecios(Iterable<PrecioBarra> precios) =>
    {for (final p in precios) if (p.activo) p.eventoId};
