import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';
import 'package:arguello_events/features/barra/services/productos_para_vender.dart';

/// Lo que se ve en VENDER: los productos con precio en la fiesta, en el orden del jefe,
/// y el buscador con las categorías.
const _fiesta = 'e0000000-0000-4000-8000-000000000001';
const _otra = 'e0000000-0000-4000-8000-000000000002';

void main() {
  final ahora = DateTime.utc(2026, 12, 4);
  ProductoBarra producto(String nombre, {String categoria = '', bool activo = true}) {
    final p = ProductoBarra.nuevo(nombre: nombre, categoria: categoria, ahora: ahora);
    return activo ? p : p.conCambios(activo: false);
  }

  PrecioBarra precio(ProductoBarra p, {String fiesta = _fiesta, int orden = 0, bool activo = true}) =>
      PrecioBarra.para(eventoId: fiesta, productoId: p.id, precio: 1000, orden: orden, activo: activo, ahora: ahora);

  final cerveza = producto('Cerveza lata', categoria: 'Cervezas');
  final fernet = producto('Fernet con coca', categoria: 'Tragos');
  final agua = producto('Agua sin gas', categoria: 'Sin alcohol');
  final baja = producto('Champán', activo: false);
  final sinPrecio = producto('Vino');

  test('solo los que tienen precio activo en la fiesta, en el orden del jefe', () {
    final lista = productosParaVender(
      [cerveza, fernet, agua, baja, sinPrecio],
      [
        precio(agua, orden: 0),
        precio(cerveza, orden: 1),
        precio(fernet, orden: 1),
        precio(baja),
        precio(sinPrecio, fiesta: _otra),
        precio(producto('Sacado'), activo: false),
      ],
      eventoId: _fiesta,
    );
    expect([for (final p in lista) p.nombre], ['Agua sin gas', 'Cerveza lata', 'Fernet con coca']);
  });

  final todos = productosParaVender(
    [cerveza, fernet, agua],
    [precio(cerveza), precio(fernet), precio(agua)],
    eventoId: _fiesta,
  );

  test('las categorías, en el orden en que aparecen y sin repetir', () {
    final otraCerveza = producto('Cerveza negra', categoria: 'Cervezas');
    final sinCategoria = producto('Hielo');
    final lista = productosParaVender(
      [cerveza, fernet, agua, otraCerveza, sinCategoria],
      [precio(agua), precio(cerveza), precio(fernet), precio(otraCerveza), precio(sinCategoria)],
      eventoId: _fiesta,
    );
    expect(categoriasDe(lista), ['Sin alcohol', 'Cervezas', 'Tragos']);
  });

  test('el buscador: sin acentos, sin mayúsculas, palabra por palabra', () {
    List<String> buscar(String q, {String? categoria}) =>
        [for (final p in filtrarProductos(todos, busqueda: q, categoria: categoria)) p.nombre];
    expect(buscar('fernét'), ['Fernet con coca']);
    expect(buscar('cer lat'), ['Cerveza lata']);
    expect(buscar('TRAGOS'), ['Fernet con coca'], reason: 'también por la categoría');
    expect(buscar(''), hasLength(3));
    expect(buscar('nada'), isEmpty);
    expect(buscar('', categoria: 'Sin alcohol'), ['Agua sin gas']);
    expect(buscar('cerveza', categoria: 'Tragos'), isEmpty);
  });
}
