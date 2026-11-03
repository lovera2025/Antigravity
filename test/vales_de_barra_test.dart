import 'package:flutter_test/flutter_test.dart';

import 'package:arguello_events/features/barra/cuentas/vales_de_barra.dart';
import 'package:arguello_events/features/barra/datos/barra_repositorio.dart';

/// Cuántos vales salen de una bebida comprada por separado, con la casilla "vale por".
void main() {
  test('10 y "vale por 3" son 3, 3, 3 y 1: el último con lo que sobra', () {
    expect(partirEnVales(10, 3), [3, 3, 3, 1]);
    expect(partirEnVales(10, 2), [2, 2, 2, 2, 2]);
    expect(partirEnVales(10, 1), List.filled(10, 1));
    expect(partirEnVales(10, 10), [10]);
  });

  test('sin "vale por", un vale con todas', () {
    expect(partirEnVales(10, null), [10]);
    expect(partirEnVales(1, null), [1]);
  });

  test('un "vale por" que no sirve no arma vales', () {
    expect(valePorValido(10, 0), isFalse);
    expect(valePorValido(10, 11), isFalse);
    expect(valePorValido(10, -2), isFalse);
    expect(valePorValido(10, null), isTrue);
    expect(() => partirEnVales(10, 0), throwsArgumentError);
    expect(() => partirEnVales(10, 11), throwsArgumentError);
    expect(() => partirEnVales(0, null), throwsArgumentError);
  });

  test('los vales suman siempre lo comprado', () {
    for (var cantidad = 1; cantidad <= 30; cantidad++) {
      for (var por = 1; por <= cantidad; por++) {
        final partes = partirEnVales(cantidad, por);
        expect(partes.fold<int>(0, (s, p) => s + p), cantidad, reason: '$cantidad por $por');
        expect(partes.every((p) => p >= 1 && p <= por), isTrue, reason: '$cantidad por $por');
      }
    }
  });

  test('por separado: cada vale sabe cuál es de cuántos', () {
    const r = RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10);
    final vales = Vale.porSeparadoDe(r, valePor: 3);
    expect([for (final v in vales) v.bebidas.single], [
      const BebidaDelVale(3, 'Cerveza lata'),
      const BebidaDelVale(3, 'Cerveza lata'),
      const BebidaDelVale(3, 'Cerveza lata'),
      const BebidaDelVale(1, 'Cerveza lata'),
    ]);
    expect([for (final v in vales) '${v.numero} de ${v.de}'], ['1 de 4', '2 de 4', '3 de 4', '4 de 4']);
    expect(vales.every((v) => v.porSeparado), isTrue);
  });

  test('todo junto: un vale con todas las bebidas de la venta', () {
    final venta = VentaBarra.nueva(
      cajaBarraId: 'c',
      eventoId: 'e',
      numero: 1,
      renglones: const [
        RenglonVenta(productoId: 'a', nombre: 'Cerveza lata', precio: 3500, cantidad: 10),
        RenglonVenta(productoId: 'b', nombre: 'Agua', precio: 1000, cantidad: 3),
      ],
      medio: MedioBarra.efectivo,
      efectivo: 38000,
      ahora: DateTime.utc(2026, 12, 5),
    );
    final vale = Vale.todoJunto(venta);
    expect(vale.bebidas, [const BebidaDelVale(10, 'Cerveza lata'), const BebidaDelVale(3, 'Agua')]);
    expect(vale.porSeparado, isFalse);
    expect('${vale.numero} de ${vale.de}', '1 de 1');
  });
}
