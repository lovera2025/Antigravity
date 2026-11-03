import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Los vales de una venta: todo junto, o por separado, cada uno armado a mano.
void main() {
  const cerveza = RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10);

  test('"vale por" sirve de 1 a las que quedan, y vacío es por todas las que quedan', () {
    expect(valePorValido(10, 3), isTrue);
    expect(valePorValido(10, 10), isTrue);
    expect(valePorValido(10, null), isTrue);
    expect(valePorValido(7, 8), isFalse, reason: 'quedan 7');
    expect(valePorValido(10, 0), isFalse);
    expect(valePorValido(10, -2), isFalse);
    expect(valePorValido(0, null), isFalse, reason: 'no queda nada');
    expect(valePorValido(0, 1), isFalse);
  });

  test('por separado: un vale por lo que se escribió, con su número en la venta', () {
    final vale = Vale.deUnaBebida(cerveza, cantidad: 3, numero: 2);
    expect(vale.bebidas, [const BebidaDelVale(3, 'Cerveza lata')]);
    expect(vale.porSeparado, isTrue);
    expect(vale.numero, 2);
  });

  test('un vale por más de lo comprado, o por nada, no se arma', () {
    expect(() => Vale.deUnaBebida(cerveza, cantidad: 11, numero: 1), throwsArgumentError);
    expect(() => Vale.deUnaBebida(cerveza, cantidad: 0, numero: 1), throwsArgumentError);
    expect(() => Vale.deUnaBebida(cerveza, cantidad: 3, numero: 0), throwsArgumentError);
  });

  test('todo junto: un vale con todas las bebidas de la venta', () {
    final venta = VentaBarra.nueva(
      cajaBarraId: 'c',
      eventoId: 'e',
      numero: 1,
      renglones: const [
        cerveza,
        RenglonVenta(productoId: 'b', nombre: 'Agua', precio: 1000, cantidad: 3),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 38000,
      ahora: DateTime.utc(2026, 12, 5),
    );
    final vale = Vale.todoJunto(venta);
    expect(vale.bebidas, [const BebidaDelVale(10, 'Cerveza lata'), const BebidaDelVale(3, 'Agua')]);
    expect(vale.porSeparado, isFalse);
  });
}
