import '../datos/barra_repositorio.dart';
import '../datos/receta_barra.dart';

/// **Las recetas de los tragos de una fiesta**, como las usa el stock (WhatsApp del jefe,
/// 26-nov-2026). Pura, sin base ni pantalla.
///
/// - Lo que va **en cc** (fernet, coca, vodka) **no se cuenta en la barra**: solo sirve
///   para calcular las botellas en GANANCIA (`CuentaDelProveedor`).
/// - Lo que va **entero** (un Speed por vodka) **baja del stock** de ese producto como si
///   se vendiera suelto: si no, al contar faltarían Speed y se pagarían dos veces.
///
/// La cuenta del stock (`StockPorBarra`, `StockDeLaBarra`) no cambia: recibe las ventas
/// de [paraElStock], con el ingrediente entero adentro. **Toda cuenta del stock de la
/// barra recibe las ventas por acá**; las cuentas de la plata (el cierre, VENTAS) no:
/// lo de adentro de un trago no se cobra aparte.
class RecetasDeLaBarra {
  final Map<String, List<RecetaBarra>> _porTrago;

  const RecetasDeLaBarra._(this._porTrago);

  static const ninguna = RecetasDeLaBarra._({});

  /// Las recetas activas de [eventoId].
  factory RecetasDeLaBarra.de(Iterable<RecetaBarra> recetas, {required String eventoId}) {
    final porTrago = <String, List<RecetaBarra>>{};
    for (final r in recetas) {
      if (r.eventoId != eventoId || !r.activo || r.cantidad <= 0) continue;
      (porTrago[r.productoId] ??= []).add(r);
    }
    return RecetasDeLaBarra._(porTrago);
  }

  /// Lo que lleva [productoId]; vacío si no es un trago con receta.
  List<RecetaBarra> de(String productoId) => _porTrago[productoId] ?? const [];

  bool tieneReceta(String productoId) => _porTrago.containsKey(productoId);

  /// Lo que lleva entero [productoId] (el Speed del vodka): ingrediente → cuántos.
  Map<String, int> enteros(String productoId) => {
        for (final r in de(productoId))
          if (r.unidad == UnidadDeReceta.unidad) r.ingredienteId: r.cantidad,
      };

  /// Las ventas como las cuenta el stock: cada renglón de un trago suma, aparte, lo que
  /// lleva entero (precio 0: no es plata). Lo que va en cc no se suma. Una venta sin
  /// tragos con algo entero queda igual (la misma instancia).
  List<VentaBarra> paraElStock(Iterable<VentaBarra> ventas) {
    if (_porTrago.isEmpty) return ventas.toList();
    return [
      for (final v in ventas) _conLoEntero(v),
    ];
  }

  VentaBarra _conLoEntero(VentaBarra v) {
    final extra = <RenglonVenta>[];
    for (final r in v.renglones) {
      for (final e in enteros(r.productoId).entries) {
        extra.add(RenglonVenta(
          productoId: e.key,
          nombre: 'en ${r.nombre}',
          precio: 0,
          cantidad: r.cantidad * e.value,
        ));
      }
    }
    if (extra.isEmpty) return v;
    return VentaBarra(
      id: v.id,
      cajaBarraId: v.cajaBarraId,
      eventoId: v.eventoId,
      numero: v.numero,
      renglones: [...v.renglones, ...extra],
      total: v.total,
      medio: v.medio,
      efectivo: v.efectivo,
      transferencia: v.transferencia,
      recibe: v.recibe,
      vuelto: v.vuelto,
      recargo: v.recargo,
      recargoPct: v.recargoPct,
      hechoPor: v.hechoPor,
      deviceId: v.deviceId,
      createdAt: v.createdAt,
      updatedAt: v.updatedAt,
    );
  }

  /// Lo que pide al stock vender [cantidad] de [productoId]: el producto mismo y lo
  /// que lleva entero. Para frenar la venta sin stock con la misma cuenta que el stock.
  Map<String, int> loQueBaja(String productoId, int cantidad) => {
        productoId: cantidad,
        for (final e in enteros(productoId).entries) e.key: e.value * cantidad,
      };

  /// Para cuántos [productoId] alcanza lo que lleva entero, según [quedan] de cada
  /// ingrediente (null: ese no se controla). Null si no lleva nada entero controlado.
  int? alcanzaPara(String productoId, int? Function(String ingredienteId) quedan) {
    int? menor;
    for (final e in enteros(productoId).entries) {
      final q = quedan(e.key);
      if (q == null) continue;
      final n = q <= 0 ? 0 : q ~/ e.value;
      if (menor == null || n < menor) menor = n;
    }
    return menor;
  }
}
