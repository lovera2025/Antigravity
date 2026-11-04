import '../datos/barra_repositorio.dart';

/// Un producto que se puede vender en la fiesta: del catálogo, con el precio de esa
/// fiesta.
class ProductoEnVenta {
  final ProductoBarra producto;
  final PrecioBarra precio;

  const ProductoEnVenta(this.producto, this.precio);

  String get id => producto.id;
  String get nombre => producto.nombre;
  String get categoria => producto.categoria;
}

/// Lo que se ve en VENDER: los productos activos con precio activo en la fiesta, en el
/// orden de los precios (el que eligió el jefe para esa fiesta) y después por nombre.
/// Un precio de otra fiesta no cuenta.
List<ProductoEnVenta> productosParaVender(
  Iterable<ProductoBarra> productos,
  Iterable<PrecioBarra> precios, {
  required String eventoId,
}) {
  final porId = {for (final p in productos) if (p.activo) p.id: p};
  final lista = [
    for (final pr in precios)
      if (pr.eventoId == eventoId && pr.activo && porId.containsKey(pr.productoId))
        ProductoEnVenta(porId[pr.productoId]!, pr),
  ];
  lista.sort((a, b) {
    final o = a.precio.orden.compareTo(b.precio.orden);
    return o != 0 ? o : a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return lista;
}

/// Las categorías que hay, en el orden en que aparecen. Sin categoría no cuenta.
List<String> categoriasDe(Iterable<ProductoEnVenta> lista) {
  final vistas = <String>[];
  for (final p in lista) {
    final c = p.categoria.trim();
    if (c.isNotEmpty && !vistas.contains(c)) vistas.add(c);
  }
  return vistas;
}

/// Sin acentos y en minúscula, para buscar: "fernét" encuentra "Fernet", y "Jäger"
/// es "jager" (las marcas traen letras de otros idiomas).
String paraBuscar(String s) {
  const cambios = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n', //
    'ä': 'a', 'ë': 'e', 'ï': 'i', 'ö': 'o', 'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
    'â': 'a', 'ê': 'e', 'î': 'i', 'ô': 'o', 'û': 'u', 'ã': 'a', 'õ': 'o', 'ç': 'c',
  };
  final b = StringBuffer();
  for (final letra in s.toLowerCase().split('')) {
    b.write(cambios[letra] ?? letra);
  }
  return b.toString().trim();
}

/// Lo que queda después del buscador y la categoría. Cada palabra buscada tiene que
/// estar en el nombre o en la categoría: "cer lat" encuentra "Cerveza lata".
List<ProductoEnVenta> filtrarProductos(
  List<ProductoEnVenta> lista, {
  String busqueda = '',
  String? categoria,
}) {
  final palabras = paraBuscar(busqueda).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  return [
    for (final p in lista)
      if ((categoria == null || p.categoria.trim() == categoria) &&
          palabras.every((w) => paraBuscar('${p.nombre} ${p.categoria}').contains(w)))
        p,
  ];
}
